// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Guided steps shared by the first-run setup and the tabs:
 * PhoneGuide for the iPhone (Bluetooth), AppleGuide for Apple's online
 * services (iCloud account, iCloud Drive). Each step ticks itself from the
 * daemon's live state.
 */

namespace Boomerang {
    /* First-run state and small helpers around iCloud Drive (rclone mount). */
    public delegate void Refresh ();

    public class Setup : Object {
        /* Run refresh every few seconds while the widget is on screen, for a state no
           signal tells (a mount, the clock): nothing wakes the app while it is hidden. */
        public static void poll_while_mapped (Gtk.Widget widget, uint seconds, owned Refresh refresh) {
            uint source = 0;
            widget.map.connect (() => {
                if (source == 0) {
                    source = Timeout.add_seconds (seconds, () => {
                        refresh ();
                        return Source.CONTINUE;
                    });
                }
            });
            widget.unmap.connect (() => {
                if (source != 0) {
                    Source.remove (source);
                    source = 0;
                }
            });
        }

        /* The app's own settings file (window, launchers, choices): every view uses this one. */
        public static string prefs_path () {
            return Path.build_filename (Environment.get_user_config_dir (), "boomerang", "apps.conf");
        }

        public static bool is_done () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (prefs_path (), KeyFileFlags.NONE);
                return prefs.get_boolean ("setup", "done");
            } catch (Error e) {
                return false;
            }
        }

        public static void set_done () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (prefs_path (), KeyFileFlags.KEEP_COMMENTS);
            } catch (Error e) {
                // first run
            }
            prefs.set_boolean ("setup", "done", true);
            try {
                DirUtils.create_with_parents (Path.get_dirname (prefs_path ()), 0700);
                prefs.save_to_file (prefs_path ());
            } catch (Error e) {
                warning ("cannot save setup state: %s", e.message);
            }
        }

        /* iCloud Drive (drive) or iCloud Photos (photos): its options file, unit and default folder. */
        public static string drive_env (bool photos = false) {
            return Path.build_filename (Environment.get_user_config_dir (), "boomerang",
                                        photos ? "photos.env" : "drive.env");
        }

        public static string drive_env_key (bool photos = false) {
            return photos ? "BOOMERANG_PHOTOS_DIR" : "BOOMERANG_DRIVE_DIR";
        }

        public static string drive_unit (bool photos = false) {
            return photos ? "boomerang-icloud-photos.service" : "boomerang-icloud-drive.service";
        }

        public static string drive_default_folder (bool photos = false) {
            if (photos) {
                var pictures = Environment.get_user_special_dir (UserDirectory.PICTURES)
                               ?? Path.build_filename (Environment.get_home_dir (), "Images");
                return Path.build_filename (pictures, "iCloud Photos");
            }
            return Path.build_filename (Environment.get_home_dir (), "iCloud Drive");
        }

        /* The folder chosen in the options (drive.env / photos.env), else the default one. */
        public static string drive_folder (bool photos = false) {
            var key = drive_env_key (photos) + "=";
            string text;
            try {
                FileUtils.get_contents (drive_env (photos), out text);
                foreach (var line in text.split ("\n")) {
                    if (line.has_prefix (key)) {
                        return line.substring (key.length).strip ().replace ("\"", "");
                    }
                }
            } catch (Error e) {
                // defaults
            }
            return drive_default_folder (photos);
        }

        /* "mounted", "configured" (set up but not mounted now) or "absent". */
        public static string drive_state (bool photos = false) {
            string mounts;
            try {
                FileUtils.get_contents ("/proc/self/mounts", out mounts);
            } catch (Error e) {
                mounts = "";
            }
            var escaped = drive_folder (photos).replace (" ", "\\040");
            if (mounts.contains (" " + escaped + " ")) {
                return "mounted";
            }
            var wants = Path.build_filename (Environment.get_user_config_dir (), "systemd", "user",
                                             "graphical-session.target.wants", drive_unit (photos));
            return FileUtils.test (wants, FileTest.EXISTS) ? "configured" : "absent";
        }

        public static void run_helper (string name, string[] args = {}) {
            string[] argv = { Path.build_filename (Config.BINDIR, name) };
            foreach (var a in args) {
                argv += a;
            }
            try {
                new Subprocess.newv (argv, SubprocessFlags.NONE);
            } catch (Error e) {
                warning ("cannot start %s: %s", name, e.message);
            }
        }

        public static void open_drive_folder (Gtk.Window? parent, bool photos = false) {
            new Gtk.FileLauncher (File.new_for_path (drive_folder (photos))).launch.begin (parent, null);
        }
    }

    public class PhoneGuide : Gtk.Box {
        public Daemon daemon { get; construct; }
        public signal void pair_requested ();

        private SetupStep pair;
        private SetupStep settings;
        private SetupStep notifications;
        private SetupStep calls;
        private Gtk.Button pair_button;

        public PhoneGuide (Daemon daemon) {
            Object (daemon: daemon, orientation: Gtk.Orientation.VERTICAL, spacing: 18);
        }

        construct {
            var adapter_name = daemon.get_string ("AdapterName");
            var pc = Markup.escape_text (adapter_name != "" ? adapter_name : Environment.get_host_name ());
            pair = new SetupStep (1, _("Appairer l'iPhone"),
                _("Gardez l'iPhone déverrouillé près de ce PC. Un code s'affiche ici et sur l'iPhone : "
                + "vérifiez qu'ils sont identiques."));
            pair_button = pair.add_button (_("Appairer…"), true);
            pair_button.clicked.connect (() => pair_requested ());
            settings = new SetupStep (2, _("Autoriser messages et contacts"),
                _("Sur l'iPhone : Réglages › Bluetooth › ⓘ à côté de « %s », activez <b>Afficher "
                + "les notifications</b> (messages) et <b>Synchroniser les contacts</b> (noms, "
                + "photos, journal d'appels). Ces options apparaissent seulement après une première "
                + "demande de Boomerang : attendez quelques secondes après l'appairage. Boomerang "
                + "renouvelle ensuite la demande automatiquement pendant 10 minutes ; "
                + "<b>Vérifier</b> la relance immédiatement.").printf (pc));
            settings.add_button (_("Vérifier")).clicked.connect (() => daemon.call.begin ("SyncMessages"));
            notifications = new SetupStep (3, _("Notifications et musique"),
                _("L'iPhone ouvre automatiquement la liaison Bluetooth basse consommation après "
                + "l'appairage. Sous ⓘ à côté de « %s », activez <b>Partager les notifications "
                + "système</b>. Si aucune notification n'arrive, désactivez puis réactivez le "
                + "Bluetooth de l'iPhone.").printf (pc));
            calls = new SetupStep (4, _("Appels sur ce PC"),
                _("Le profil mains libres se connecte automatiquement. Les appels sonnent alors "
                + "sur ce PC ; pendant l'appel, vous choisissez si le son passe par ce PC ou reste "
                + "sur l'iPhone."));
            append (pair);
            append (settings);
            append (notifications);
            append (calls);
            daemon.changed.connect (() => {
                if (daemon.touched ({ "Paired", "MessagesState", "ContactsState", "NotificationsLinked", "CallsLinked" })) {
                    update ();
                }
            });
            update ();
        }

        private void update () {
            var paired = daemon.get_bool ("Paired");
            pair.set_done (paired);
            pair_button.label = paired ? _("Appairer un autre iPhone…") : _("Appairer…");
            pair_button.remove_css_class (Granite.CssClass.SUGGESTED);
            if (!paired) {
                pair_button.add_css_class (Granite.CssClass.SUGGESTED);
            }
            settings.set_done (daemon.get_string ("MessagesState") == "ready"
                               && daemon.get_string ("ContactsState") == "ready");
            notifications.set_done (daemon.get_bool ("NotificationsLinked"));
            calls.set_done (daemon.get_bool ("CallsLinked"));
        }
    }

    public class AppleGuide : Gtk.Box {
        public Daemon daemon { get; construct; }

        private SetupStep password;
        private SetupStep signin;
        private SetupStep drive;
        private Gtk.Button signin_button;
        private Gtk.Button drive_button;

        public AppleGuide (Daemon daemon) {
            Object (daemon: daemon, orientation: Gtk.Orientation.VERTICAL, spacing: 18);
        }

        construct {
            password = new SetupStep (1, _("Créer un mot de passe pour app"),
                _("Sur la page de votre compte Apple, ouvrez <b>Connexion et sécurité</b> › "
                + "<b>Mots de passe pour les apps</b>, touchez <b>+</b>, nommez-le « Boomerang » et "
                + "copiez le code xxxx-xxxx-xxxx-xxxx. La double authentification doit être active."));
            password.add_button (_("Ouvrir la page Apple…")).clicked.connect (() => {
                new Gtk.UriLauncher (APPLE_ACCOUNT_URL).launch.begin (get_root () as Gtk.Window, null);
            });
            signin = new SetupStep (2, _("Courriel, agendas, rappels et contacts"),
                _("Saisissez votre identifiant Apple et ce mot de passe pour app : Boomerang le vérifie "
                + "auprès d'Apple et l'enregistre dans le trousseau. Vos comptes apparaissent alors "
                + "dans Courriel, Tâches et Agenda."));
            signin_button = signin.add_button (_("Se connecter…"), true);
            signin_button.clicked.connect (() => Setup.run_helper ("boomerang-icloud-signin"));
            drive = new SetupStep (3, _("iCloud Drive (facultatif)"),
                _("Vos fichiers iCloud comme un dossier dans Fichiers. La connexion demande le mot "
                + "de passe du <b>compte Apple</b> et un code affiché sur l'iPhone. La "
                + "<b>Protection avancée des données</b> doit être désactivée."));
            drive_button = drive.add_button (_("Connecter iCloud Drive…"));
            drive_button.clicked.connect (() => {
                if (Setup.drive_state () == "mounted") {
                    Setup.open_drive_folder (get_root () as Gtk.Window);
                } else {
                    Setup.run_helper ("boomerang-icloud-drive");
                }
            });
            append (password);
            append (signin);
            append (drive);
            daemon.changed.connect (() => {
                // update () reads the mounts and drive.env: not for a hidden page
                if (get_mapped () && daemon.touched ({ "ICloudState" })) {
                    update ();
                }
            });
            // The mount is not a daemon property: look again now and then while visible.
            Setup.poll_while_mapped (this, 5, update);
            map.connect (update);
            update ();
        }

        private void update () {
            var state = daemon.get_string ("ICloudState");
            var signed_in = state == "connected" || state == "attention";
            password.set_done (signed_in);
            signin.set_done (signed_in);
            signin_button.label = signed_in ? _("Se reconnecter…") : _("Se connecter…");
            signin_button.remove_css_class (Granite.CssClass.SUGGESTED);
            if (!signed_in) {
                signin_button.add_css_class (Granite.CssClass.SUGGESTED);
            }
            var drive_state = Setup.drive_state ();
            drive.set_done (drive_state == "mounted");
            drive_button.label = drive_state == "mounted" ? _("Ouvrir le dossier") : _("Connecter iCloud Drive…");
        }
    }
}

namespace Boomerang {
    /* One detached app: icon, name, what it is, Ouvrir, and shown in the Applications menu or not. */
    public Gtk.Widget launcher_row (Mode mode, string name, string text) {
        var image = new Gtk.Image.from_icon_name (mode.icon_name ()) { pixel_size = 32 };
        var title = new Gtk.Label (name) { xalign = 0 };
        var desc = new Gtk.Label (text) { xalign = 0, wrap = true };
        desc.add_css_class (Granite.CssClass.DIM);
        desc.add_css_class (Granite.CssClass.SMALL);
        var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text_box.append (title);
        text_box.append (desc);
        var open = new Gtk.Button.with_label (_("Ouvrir")) { valign = Gtk.Align.CENTER };
        open.clicked.connect (() => launch (mode));
        var shown = new Gtk.Switch () {
            valign = Gtk.Align.CENTER,
            active = Launchers.is_visible (mode),
            tooltip_text = _("Afficher %s dans le menu des applications").printf (name)
        };
        shown.notify["active"].connect (() => Launchers.set_visible (mode, shown.active));
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };
        box.append (image);
        box.append (text_box);
        box.append (open);
        box.append (shown);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }
}
