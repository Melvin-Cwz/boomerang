// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Recopie d'écran (experimental): the iPhone's screen in a window on the PC,
 * through UxPlay, a free AirPlay receiver (boomerangd/mirror.py). The receiver
 * only runs between « Recevoir l'écran de l'iPhone » and « Arrêter ».
 *
 * The picture stays in UxPlay's own window (another program: its video cannot be
 * drawn in this GTK window without passing frames between processes). This page
 * is the control panel: start and stop, profile, rotation, full screen, and the
 * iPhone control pad (boomerangd/hid.py: the PC as a Bluetooth mouse and keyboard).
 *
 * Also here: a screenshot of the mirrored picture (taken by the mirroring window,
 * boomerangd/mirror_viewer.py), a drop area that sends files to the iPhone's LocalSend
 * app (« files » module), the iPhone's media keys and two pointer gestures (Control
 * Centre, app switcher), and a pointer size that follows the mirrored picture.
 */

public class Boomerang.MirrorView : Gtk.Box {
    public Daemon daemon { get; construct; }

    // HID usages and modifier bits for iOS shortcuts (⌘ = GUI).
    private const uint GUI = 0x08;
    private const uint KEY_H = 0x0B;
    private const uint KEY_SPACE = 0x2C;
    private const uint KEY_TAB = 0x2B;
    private const uint EVDEV_LEFTMETA = 125;
    private const uint BUTTON_LEFT = 1;
    private const uint BUTTON_RIGHT = 2;

    private InstallBox install;
    private Gtk.Box ready_box;
    private Gtk.Button start_button;
    private Gtk.Label state_label;
    private Gtk.Label steps;
    private Gtk.DropDown profile;
    private Gtk.DropDown rotation;
    private Gtk.Switch fullscreen;
    private Gtk.Switch record;
    private Gtk.Label decoder_label;
    private bool updating = false;
    private Gtk.Button capture_button;
    private Gtk.Box capture_done;
    private Gtk.Label capture_label;
    private string capture_path = "";

    private Gtk.Box drop_zone;
    private Gtk.Label drop_title;
    private Gtk.Label drop_detail;
    private Gtk.Button drop_action;
    private string drop_action_kind = "";
    private bool sending = false;

    private Gtk.Switch control_switch;
    private Gtk.Box control_box;
    private Gtk.Label control_state;
    private Gtk.ToggleButton command_held;
    private Gtk.Switch auto_size;
    private Gtk.Label video_label;
    private Gtk.Widget height_row;
    private Gtk.SpinButton width_spin;
    private Gtk.SpinButton height_spin;

    private static bool css_added = false;
    // Same C call as Gtk.StyleContext.add_provider_for_display, without the class deprecated in 4.10.
    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    private static extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider,
                                                         uint priority);
    // The drop area draws its own frame (Granite 9 draws none around plain boxes).
    private const string CSS = """
        .mirror-drop {
            border: 2px dashed alpha(@fg_color, 0.25);
            border-radius: 12px;
            padding: 18px;
        }
        .mirror-drop.drop-hover {
            border-color: @accent_color;
            background-color: alpha(@accent_color, 0.08);
        }
        .mirror-key {
            min-width: 36px;
            min-height: 28px;
            padding: 0 6px;
            border: 1px solid alpha(@fg_color, 0.18);
            border-radius: 6px;
            background-color: alpha(@fg_color, 0.04);
        }
        .mirror-key:hover { background-color: alpha(@fg_color, 0.1); }
        .mirror-key:active { background-color: alpha(@fg_color, 0.16); }
    """;
    private double last_x = -1;
    private double last_y = -1;
    private double pending_x = 0;
    private double pending_y = 0;
    private uint flush_timer = 0;

    public MirrorView (Daemon daemon) {
        Object (daemon: daemon, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
    }

    construct {
        Gtk.ScrolledWindow scroll;
        var content = PageHeader.column (out scroll);
        var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var header = PageHeader.build (
            _("Recopie d'écran"),
            _("L'écran de l'iPhone dans une fenêtre de ce PC, par AirPlay, sur le même Wi-Fi."),
            _("Expérimental"));
        header.hexpand = true;
        top.append (header);
        var guide = Guide.help_button ("mirror", _("Guide de la recopie et du contrôle"));
        guide.valign = Gtk.Align.START;
        top.append (guide);
        content.append (top);

        install = new InstallBox ();
        install.installed.connect (() => daemon.call.begin ("StopMirror"));  // refreshes the state
        content.append (install);

        ready_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        start_button = new Gtk.Button.with_label (_("Recevoir l'écran de l'iPhone")) {
            halign = Gtk.Align.START
        };
        start_button.add_css_class (Granite.CssClass.SUGGESTED);
        start_button.clicked.connect (toggle);
        capture_button = new Gtk.Button.with_label (_("Capture d'écran")) { visible = false };
        capture_button.clicked.connect (() => daemon.call.begin ("MirrorScreenshot"));
        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        buttons.append (start_button);
        buttons.append (capture_button);
        state_label = new Gtk.Label ("") { xalign = 0, wrap = true };
        state_label.add_css_class (Granite.CssClass.DIM);
        capture_label = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.MIDDLE, hexpand = true };
        capture_label.add_css_class (Granite.CssClass.DIM);
        capture_label.add_css_class (Granite.CssClass.SMALL);
        var show_capture = new Gtk.Button.with_label (_("Afficher dans Fichiers"));
        show_capture.add_css_class (Granite.CssClass.SMALL);
        show_capture.clicked.connect (() => {
            if (capture_path != "") {
                new Gtk.FileLauncher (File.new_for_path (capture_path)).open_containing_folder.begin (
                    get_root () as Gtk.Window, null);
            }
        });
        capture_done = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { visible = false };
        capture_done.append (capture_label);
        capture_done.append (show_capture);
        steps = new Gtk.Label ("") { xalign = 0, wrap = true, use_markup = true };
        ready_box.append (buttons);
        ready_box.append (state_label);
        ready_box.append (capture_done);
        ready_box.append (new Granite.HeaderLabel (_("Affichage")));
        ready_box.append (build_options ());
        ready_box.append (new Granite.HeaderLabel (_("Sur l'iPhone")));
        ready_box.append (steps);
        var note = new Gtk.Label (
            _("Boomerang utilise UxPlay, un récepteur AirPlay libre. UxPlay écoute le réseau seulement "
              + "pendant la recopie. Pour terminer, fermez la fenêtre de recopie ou cliquez sur « "
              + "Arrêter ».")
        ) { xalign = 0, wrap = true };
        note.add_css_class (Granite.CssClass.DIM);
        note.add_css_class (Granite.CssClass.SMALL);
        ready_box.append (note);
        content.append (ready_box);

        content.append (new Granite.HeaderLabel (_("Envoyer des fichiers à l'iPhone")));
        content.append (build_drop_zone ());

        content.append (new Granite.HeaderLabel (_("Contrôler l'iPhone depuis le PC")));
        content.append (build_control ());
        append (scroll);
        Snapshots.scroll_to_end (scroll);

        if (!css_added) {
            css_added = true;
            var provider = new Gtk.CssProvider ();
            provider.load_from_string (Style.colors (CSS));
            add_provider_for_display (Gdk.Display.get_default (), provider,
                                      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        daemon.changed.connect (() => {
            if (daemon.touched ({ "Mirror", "Control" })) {
                update ();
            }
            if (daemon.touched ({ "Files", "Catalog" })) {
                update_drop_zone ();
            }
        });
        update ();
        update_drop_zone ();
    }

    // --- files to LocalSend -----------------------------------------------------------------

    private Gtk.Widget build_drop_zone () {
        drop_zone = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        drop_zone.add_css_class ("mirror-drop");
        var icon = new Gtk.Image.from_icon_name ("document-send") { pixel_size = 32, valign = Gtk.Align.CENTER };
        drop_title = new Gtk.Label ("") { xalign = 0, wrap = true };
        drop_detail = new Gtk.Label ("") { xalign = 0, wrap = true };
        drop_detail.add_css_class (Granite.CssClass.DIM);
        drop_detail.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (drop_title);
        text.append (drop_detail);
        drop_action = new Gtk.Button () { valign = Gtk.Align.CENTER, visible = false };
        drop_action.clicked.connect (on_drop_action);
        drop_zone.append (icon);
        drop_zone.append (text);
        drop_zone.append (drop_action);

        var drop = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
        drop.enter.connect (() => {
            if (files_ready ()) {
                drop_zone.add_css_class ("drop-hover");
                return Gdk.DragAction.COPY;
            }
            return 0;
        });
        drop.leave.connect (() => drop_zone.remove_css_class ("drop-hover"));
        drop.drop.connect ((value) => {
            drop_zone.remove_css_class ("drop-hover");
            if (!files_ready ()) {
                return false;
            }
            string[] paths = {};
            foreach (var file in ((Gdk.FileList) value).get_files ()) {
                if (file.get_path () != null) {
                    paths += file.get_path ();
                }
            }
            if (paths.length == 0) {
                return false;
            }
            send_to_iphone.begin (paths);
            return true;
        });
        drop_zone.add_controller (drop);
        return drop_zone;
    }

    /* « files » module added and LocalSend listening. */
    private bool files_ready () {
        return Catalog.added (daemon, "files") && Props.flag (daemon.get_value ("Files"), "enabled");
    }

    private void update_drop_zone () {
        if (sending) {
            return;
        }
        drop_action.visible = true;
        if (!Catalog.added (daemon, "files")) {
            drop_title.label = _("Le module « Envoi de fichiers » n'est pas ajouté");
            drop_detail.label = _("Ajoutez-le pour déposer ici des fichiers à envoyer à l'app LocalSend de l'iPhone.");
            drop_action.label = _("Ajouter le module");
            drop_action_kind = "add";
        } else if (!Props.flag (daemon.get_value ("Files"), "enabled")) {
            drop_title.label = _("LocalSend est désactivé");
            drop_detail.label = _("Activez la réception et l'envoi dans la page Fichiers pour déposer des fichiers ici.");
            drop_action.label = _("Activer");
            drop_action_kind = "enable";
        } else {
            drop_title.label = _("Déposez des fichiers ici");
            drop_detail.label = _("Ils sont envoyés à l'app LocalSend de l'iPhone, ouverte et connectée au même Wi-Fi.");
            drop_action.visible = false;
            drop_action_kind = "";
        }
    }

    private void on_drop_action () {
        if (drop_action_kind == "add") {
            daemon.call.begin ("SetModuleAdded", new Variant ("(sb)", "files", true));
        } else if (drop_action_kind == "enable") {
            daemon.call.begin ("SetLocalSend", new Variant ("(b)", true));
        }
    }

    /* To the iPhone among the LocalSend devices seen: a phone, the one named like the
       linked iPhone if there are several. */
    private async void send_to_iphone (string[] paths) {
        sending = true;
        drop_action.visible = false;
        drop_title.label = ngettext ("Envoi de %u fichier…", "Envoi de %u fichiers…",
                                     (ulong) paths.length).printf ((uint) paths.length);
        drop_detail.label = "";
        var peers = yield daemon.call_list ("ListFilePeers");
        var device = daemon.get_string ("DeviceName");
        string chosen = "", chosen_name = "";
        foreach (var peer in peers) {
            if (Props.str (peer, "type") != "mobile") {
                continue;
            }
            if (chosen == "" || Props.str (peer, "alias") == device) {
                chosen = Props.str (peer, "id");
                chosen_name = Props.str (peer, "alias");
            }
        }
        if (chosen == "") {
            sending = false;
            update_drop_zone ();
            drop_title.label = _("L'iPhone n'est pas visible dans LocalSend");
            drop_detail.label = _("Ouvrez l'app LocalSend sur l'iPhone, sur le même Wi-Fi que ce PC, puis "
                                  + "déposez à nouveau les fichiers.");
            return;
        }
        try {
            yield daemon.call_checked ("SendFiles", new Variant ("(s^as)", chosen, paths));
            sending = false;
            update_drop_zone ();
            drop_detail.label = _("Envoyés à %s : acceptez-les dans LocalSend sur l'iPhone.").printf (chosen_name);
        } catch (Error e) {
            sending = false;
            update_drop_zone ();
            DBusError.strip_remote_error (e);
            drop_detail.label = _("L'envoi a échoué : %s").printf (e.message);
        }
    }

    // --- display options -------------------------------------------------------------------

    private Gtk.Widget option_row (string title, string subtitle, Gtk.Widget control) {
        var title_label = new Gtk.Label (title) { xalign = 0 };
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        if (subtitle != "") {
            var sub = new Gtk.Label (subtitle) { xalign = 0, wrap = true };
            sub.add_css_class (Granite.CssClass.DIM);
            sub.add_css_class (Granite.CssClass.SMALL);
            text.append (sub);
        }
        control.valign = Gtk.Align.CENTER;
        control.update_property (Gtk.AccessibleProperty.LABEL, title, -1);
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9, margin_bottom = 9, margin_start = 12, margin_end = 12
        };
        box.append (text);
        box.append (control);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }

    private Gtk.Widget build_options () {
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        list.add_css_class (Granite.CssClass.CARD);

        profile = new Gtk.DropDown.from_strings ({ _("Fluide"), _("Qualité") });
        profile.notify["selected"].connect (() => {
            if (!updating) {
                set_option ("profile", profile.selected == 1 ? "quality" : "fluid");
            }
        });
        list.append (option_row (_("Profil"),
                                 _("Fluide : le moins de retard possible, pour piloter l'iPhone. Qualité "
                                   + ": le son reste synchronisé avec l'image, pour une vidéo."), profile));

        rotation = new Gtk.DropDown.from_strings ({ _("Aucune"), _("Vers la droite"), _("Vers la gauche") });
        rotation.notify["selected"].connect (() => {
            if (!updating) {
                string[] values = { "", "R", "L" };
                set_option ("rotation", values[rotation.selected]);
            }
        });
        list.append (option_row (_("Rotation"), "", rotation));

        fullscreen = new Gtk.Switch ();
        fullscreen.notify["active"].connect (() => {
            if (!updating) {
                set_option ("fullscreen", fullscreen.active ? "true" : "false");
            }
        });
        list.append (option_row (_("Plein écran"), _("Appuyez sur Échap ou F11 dans la fenêtre de recopie pour quitter le plein écran"),
                                 fullscreen));

        record = new Gtk.Switch ();
        record.notify["active"].connect (() => {
            if (!updating) {
                set_option ("record", record.active ? "true" : "false");
            }
        });
        list.append (option_row (_("Enregistrer la recopie"),
                                 _("Image et son en MP4 dans le dossier Vidéos, un fichier daté par recopie"),
                                 record));

        decoder_label = new Gtk.Label ("") { xalign = 1 };
        decoder_label.add_css_class (Granite.CssClass.DIM);
        list.append (option_row (_("Décodage vidéo"),
                                 _("Boomerang choisit le décodage selon la carte graphique et passe au décodage logiciel en cas d'échec"),
                                 decoder_label));
        var hint = new Gtk.Label (_("Les changements s'appliquent au prochain démarrage de la recopie.")) {
            xalign = 0, wrap = true
        };
        hint.add_css_class (Granite.CssClass.DIM);
        hint.add_css_class (Granite.CssClass.SMALL);
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        box.append (list);
        box.append (hint);
        return box;
    }

    private void set_option (string key, string value) {
        daemon.call.begin ("SetMirrorOption", new Variant ("(ss)", key, value));
    }

    /* The PC's screen size, so the iPhone sends a picture that fits it. */
    private void send_screen_size () {
        var display = Gdk.Display.get_default ();
        if (display == null) {
            return;
        }
        Gdk.Monitor? monitor = null;
        var native = get_native ();
        if (native != null && native.get_surface () != null) {
            monitor = display.get_monitor_at_surface (native.get_surface ());
        }
        if (monitor == null && display.get_monitors ().get_n_items () > 0) {
            monitor = (Gdk.Monitor) display.get_monitors ().get_item (0);
        }
        if (monitor == null) {
            return;
        }
        var area = monitor.geometry;
        var scale = monitor.scale_factor;
        set_option ("screen", "%dx%d".printf (area.width * scale, area.height * scale));
    }

    private void toggle () {
        var running = Props.flag (daemon.get_value ("Mirror"), "running");
        if (!running) {
            send_screen_size ();
        }
        daemon.call.begin (running ? "StopMirror" : "StartMirror");
    }

    // --- control ----------------------------------------------------------------------------

    private Gtk.Widget build_control () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
        list.add_css_class (Granite.CssClass.CARD);
        control_switch = new Gtk.Switch ();
        control_switch.notify["active"].connect (() => {
            if (!updating) {
                daemon.call.begin ("SetAlphaFeature",
                                   new Variant ("(sb)", "iphone_control", control_switch.active));
            }
        });
        list.append (option_row (_("Souris et clavier Bluetooth"),
                                 _("Le PC se présente à l'iPhone comme une souris et un clavier. "
                                   + "Expérimental, désactivé par défaut."), control_switch));
        box.append (list);

        control_state = new Gtk.Label ("") { xalign = 0, wrap = true };
        control_state.add_css_class (Granite.CssClass.DIM);
        box.append (control_state);

        control_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        control_box.append (build_pad ());

        var shortcuts = new Gtk.FlowBox () {
            selection_mode = Gtk.SelectionMode.NONE, max_children_per_line = 4, column_spacing = 6,
            row_spacing = 6, homogeneous = false
        };
        shortcuts.append (shortcut_button (_("Accueil"), _("⌘H : retour à l'écran d'accueil"), KEY_H));
        shortcuts.append (shortcut_button (_("Recherche"), _("⌘Espace : recherche de l'iPhone"), KEY_SPACE));
        shortcuts.append (shortcut_button (_("Changer d'app"), _("⌘Tab : app précédente"), KEY_TAB));
        shortcuts.append (gesture_button (_("Centre de contrôle"),
                                          _("Glissement du pointeur vers le bas depuis le coin supérieur droit"),
                                          "control_centre"));
        shortcuts.append (gesture_button (_("Sélecteur d'apps"),
                                          _("Glissement du pointeur vers le haut depuis le bas de l'écran, avec une pause"),
                                          "app_switcher"));
        command_held = new Gtk.ToggleButton.with_label ("⌘") {
            tooltip_text = _("Maintient ⌘ enfoncé pour la touche suivante (le bureau intercepte "
                             + "souvent la touche Super du PC)")
        };
        command_held.toggled.connect (() => {
            daemon.call.begin ("ControlKey", new Variant ("(ub)", EVDEV_LEFTMETA, command_held.active));
        });
        shortcuts.append (command_held);
        var center = new Gtk.Button.with_label (_("Recentrer le pointeur")) {
            tooltip_text = _("Ramène le pointeur au centre de l'écran de l'iPhone")
        };
        center.clicked.connect (() => daemon.call.begin ("ControlGoto", new Variant ("(dd)", 0.5, 0.5)));
        shortcuts.append (center);

        // The iPhone's own keys, as on a keyboard with media keys (Consumer Control).
        var keys_line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        keys_line.append (media_button ("audio-volume-low-symbolic", _("Baisser le volume"), "volume_down"));
        keys_line.append (media_button ("audio-volume-high-symbolic", _("Monter le volume"), "volume_up"));
        keys_line.append (media_button ("media-playback-start-symbolic", _("Lecture ou pause"), "play_pause"));
        keys_line.append (media_button ("system-lock-screen-symbolic", _("Verrouiller l'iPhone"), "lock"));
        control_box.append (keys_line);
        control_box.append (shortcuts);

        var entry = new Gtk.Entry () {
            placeholder_text = _("Texte à taper sur l'iPhone"),
            hexpand = true
        };
        var send = new Gtk.Button.with_label (_("Taper"));
        send.clicked.connect (() => type_text (entry));
        entry.activate.connect (() => type_text (entry));
        var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        line.append (entry);
        line.append (send);
        control_box.append (line);

        var size_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        size_list.add_css_class (Granite.CssClass.CARD);
        width_spin = new Gtk.SpinButton.with_range (50, 4000, 10);
        height_spin = new Gtk.SpinButton.with_range (50, 8000, 10);
        width_spin.value_changed.connect (send_size);
        height_spin.value_changed.connect (send_size);
        auto_size = new Gtk.Switch ();
        auto_size.notify["active"].connect (() => {
            if (!updating) {
                daemon.call.begin ("SetControlAutoSize", new Variant ("(b)", auto_size.active));
            }
        });
        video_label = new Gtk.Label ("") { xalign = 0, wrap = true };
        video_label.add_css_class (Granite.CssClass.DIM);
        video_label.add_css_class (Granite.CssClass.SMALL);
        var auto_row = option_row (_("Suivre l'image de la recopie"),
                                   _("Pendant la recopie, la hauteur suit les proportions et l'orientation "
                                     + "de l'image reçue : seul le côté court est à régler"), auto_size);
        size_list.append (auto_row);
        size_list.append (option_row (_("Largeur de l'écran pour le pointeur"),
                                      _("Si « Recentrer le pointeur » ne place pas le pointeur au centre, "
                                        + "ajustez cette valeur (iPhone tenu verticalement)"),
                                      width_spin));
        height_row = option_row (_("Hauteur de l'écran pour le pointeur"), "", height_spin);
        size_list.append (height_row);
        var size_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) { margin_top = 6 };
        size_box.append (size_list);
        size_box.append (video_label);
        var expander = new Gtk.Expander (_("Réglage du pointeur")) { child = size_box };
        control_box.append (expander);
        box.append (control_box);
        return box;
    }

    private Gtk.Widget gesture_button (string label, string tooltip, string gesture) {
        var button = new Gtk.Button.with_label (label) { tooltip_text = tooltip };
        button.clicked.connect (() => {
            daemon.call.begin ("ControlGesture", new Variant ("(s)", gesture));
        });
        return button;
    }

    private Gtk.Widget media_button (string icon, string tooltip, string key) {
        var button = new Gtk.Button.from_icon_name (icon) { tooltip_text = tooltip };
        button.add_css_class ("mirror-key");  // a key: its own frame, whatever the theme
        button.update_property (Gtk.AccessibleProperty.LABEL, tooltip, -1);
        button.clicked.connect (() => {
            daemon.call.begin ("ControlMedia", new Variant ("(s)", key));
        });
        return button;
    }

    private Gtk.Widget shortcut_button (string label, string tooltip, uint usage) {
        var button = new Gtk.Button.with_label (label) { tooltip_text = tooltip };
        button.clicked.connect (() => {
            daemon.call.begin ("ControlShortcut", new Variant ("(uu)", usage, GUI));
        });
        return button;
    }

    private void type_text (Gtk.Entry entry) {
        var text = entry.text;
        if (text == "") {
            return;
        }
        daemon.call.begin ("ControlText", new Variant ("(s)", text));
        entry.text = "";
    }

    private void send_size () {
        if (!updating) {
            daemon.call.begin ("SetControlSize", new Variant ("(uu)", (uint) width_spin.value,
                                                             (uint) height_spin.value));
        }
    }

    /* The pad: the PC's mouse over it moves the iPhone's pointer; keys typed while it has
       the focus go to the iPhone. */
    private Gtk.Widget build_pad () {
        var pad = new Gtk.DrawingArea () {
            content_height = 220,
            hexpand = true,
            focusable = true,
            can_focus = true,
            cursor = new Gdk.Cursor.from_name ("crosshair", null)
        };
        pad.add_css_class ("control-pad");
        pad.update_property (Gtk.AccessibleProperty.LABEL, _("Pavé de contrôle de l'iPhone"), -1);
        pad.set_draw_func ((area, cr, width, height) => {
            var layout = area.create_pango_layout (
                area.has_focus
                ? _("Souris et clavier dirigés vers l'iPhone")
                : _("Cliquez ici, puis déplacez la souris : le pointeur de l'iPhone suit"));
            layout.set_width ((width - 24) * Pango.SCALE);
            layout.set_alignment (Pango.Alignment.CENTER);
            int text_width, text_height;
            layout.get_pixel_size (out text_width, out text_height);
            var color = area.get_color ();
            cr.set_source_rgba (color.red, color.green, color.blue, 0.55);
            cr.move_to (12, (height - text_height) / 2.0);
            Pango.cairo_show_layout (cr, layout);
        });

        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect ((x, y) => {
            last_x = x;
            last_y = y;
        });
        motion.motion.connect ((x, y) => {
            if (last_x >= 0) {
                pending_x += x - last_x;
                pending_y += y - last_y;
                schedule_flush ();
            }
            last_x = x;
            last_y = y;
        });
        motion.leave.connect (() => last_x = -1);
        pad.add_controller (motion);

        var click = new Gtk.GestureClick () { button = 0 };
        click.pressed.connect ((n, x, y) => {
            pad.grab_focus ();
            pad.queue_draw ();
            daemon.call.begin ("ControlButton", new Variant ("(ub)", button_of (click), true));
        });
        click.released.connect ((n, x, y) => {
            daemon.call.begin ("ControlButton", new Variant ("(ub)", button_of (click), false));
        });
        pad.add_controller (click);

        var wheel = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL
                                                   | Gtk.EventControllerScrollFlags.DISCRETE);
        wheel.scroll.connect ((dx, dy) => {
            daemon.call.begin ("ControlScroll", new Variant ("(i)", (int) (-dy)));
            return true;
        });
        pad.add_controller (wheel);

        var keys = new Gtk.EventControllerKey ();
        keys.key_pressed.connect ((keyval, keycode, state) => {
            daemon.call.begin ("ControlKey", new Variant ("(ub)", keycode - 8, true));
            return true;
        });
        keys.key_released.connect ((keyval, keycode, state) => {
            daemon.call.begin ("ControlKey", new Variant ("(ub)", keycode - 8, false));
        });
        pad.add_controller (keys);
        var focus = new Gtk.EventControllerFocus ();
        focus.leave.connect (() => {
            daemon.call.begin ("ControlRelease");
            command_held.active = false;
            pad.queue_draw ();
        });
        pad.add_controller (focus);

        var frame = new Gtk.Frame (null) { child = pad };
        return frame;
    }

    private static uint button_of (Gtk.GestureClick click) {
        return click.get_current_button () == Gdk.BUTTON_SECONDARY ? BUTTON_RIGHT : BUTTON_LEFT;
    }

    /* Moves are gathered and sent about 60 times a second. */
    private void schedule_flush () {
        if (flush_timer != 0) {
            return;
        }
        flush_timer = Timeout.add (16, () => {
            flush_timer = 0;
            var dx = (int) pending_x;
            var dy = (int) pending_y;
            if (dx != 0 || dy != 0) {
                pending_x -= dx;
                pending_y -= dy;
                daemon.call.begin ("ControlMove", new Variant ("(ii)", dx, dy));
            }
            return Source.REMOVE;
        });
    }

    // --- state ---------------------------------------------------------------------------------

    private void update () {
        updating = true;
        var mirror = daemon.get_value ("Mirror");
        var missing = Props.strings (mirror, "missing");
        install.set_missing (missing, _("La recopie d'écran"));
        ready_box.visible = missing.length == 0;
        var running = Props.flag (mirror, "running");
        var name = Props.str (mirror, "name");
        start_button.label = running ? _("Arrêter") : _("Recevoir l'écran de l'iPhone");
        start_button.remove_css_class (running ? Granite.CssClass.SUGGESTED : Granite.CssClass.DESTRUCTIVE);
        start_button.add_css_class (running ? Granite.CssClass.DESTRUCTIVE : Granite.CssClass.SUGGESTED);
        var error = Props.str (mirror, "error");
        var pin = Props.str (mirror, "pin");
        if (running && pin != "") {
            state_label.label = _("En attente de l'iPhone sous le nom « %s ». Code à saisir sur "
                                  + "l'iPhone : %s").printf (name, pin);
        } else if (running) {
            state_label.label = _("En attente de l'iPhone sous le nom « %s »").printf (name);
        } else if (error == "exited") {
            state_label.label = _("Le récepteur s'est arrêté. Vérifiez qu'Avahi fonctionne et réessayez.");
        } else if (error != "" && error != "missing") {
            state_label.label = _("Le récepteur s'est arrêté : %s").printf (error);
        } else {
            state_label.label = _("Arrêté");
        }
        if (running && Props.str (mirror, "recording") != "") {
            state_label.label += " · " + _("Enregistrement dans Vidéos");
        }
        // Screenshots come from Boomerang's mirroring window, once it shows a picture.
        var can_capture = Props.flag (mirror, "can_capture");
        capture_button.visible = running;
        capture_button.sensitive = can_capture;
        capture_button.tooltip_text = can_capture
            ? _("Enregistre l'image de l'iPhone dans le dossier Images")
            : _("Disponible quand l'image de l'iPhone s'affiche dans la fenêtre de recopie de Boomerang "
                + "(paquet gstreamer1.0-gtk4)");
        capture_path = Props.str (mirror, "screenshot");
        capture_done.visible = capture_path != "";
        capture_label.label = _("Dernière capture : %s").printf (Path.get_basename (capture_path));
        steps.label = _("1. Ouvrez le Centre de contrôle.\n2. Touchez « Recopie de l'écran ».\n"
                        + "3. Choisissez <b>%s</b>.\n4. Saisissez le code affiché ici.").printf (
                        Markup.escape_text (name));
        profile.selected = Props.str (mirror, "profile") == "quality" ? 1 : 0;
        var rot = Props.str (mirror, "rotation");
        rotation.selected = rot == "R" ? 1 : rot == "L" ? 2 : 0;
        fullscreen.active = Props.flag (mirror, "fullscreen");
        record.active = Props.flag (mirror, "record");
        switch (Props.str (mirror, "decoder")) {
            case "nvidia": decoder_label.label = _("NVIDIA"); break;
            case "vaapi": decoder_label.label = _("VA-API"); break;
            default: decoder_label.label = _("Logiciel"); break;
        }

        var control = daemon.get_value ("Control");
        var enabled = Props.flag (control, "enabled");
        control_switch.active = enabled;
        control_box.visible = enabled && Props.flag (control, "registered");
        var control_error = Props.str (control, "error");
        if (!enabled) {
            control_state.label = _("Activez l'interrupteur, puis suivez le guide : appairage dans Réglages › "
                                    + "Bluetooth de l'iPhone et AssistiveTouch pour le pointeur.");
        } else if (control_error != "") {
            control_state.label = _("Bluetooth a refusé la souris et le clavier : %s").printf (control_error);
        } else if (Props.flag (control, "connected")) {
            control_state.label = _("L'iPhone utilise la souris et le clavier de Boomerang.");
        } else {
            control_state.label = _("Souris et clavier prêts. Sur l'iPhone : Réglages › Bluetooth, "
                                    + "touchez « Boomerang » sous Autres appareils (ou reconnectez-le).");
        }
        var width = Props.integer (control, "width");
        var height = Props.integer (control, "height");
        var automatic = Props.flag (control, "auto_size", true);
        auto_size.active = automatic;
        height_row.visible = !automatic;
        var video_width = Props.integer (control, "video_width");
        var video_height = Props.integer (control, "video_height");
        if (automatic) {
            // Shown upright: the short side is the one to tune, whatever the rotation.
            var short_side = int.min (width, height);
            var long_side = int.max (width, height);
            width = short_side;
            height = long_side;
        }
        if (video_width > 0 && video_height > 0) {
            video_label.label = automatic
                ? _("Image reçue : %d × %d. Course du pointeur : %d × %d.").printf (
                    video_width, video_height, Props.integer (control, "width"), Props.integer (control, "height"))
                : _("Image reçue : %d × %d.").printf (video_width, video_height);
        } else {
            video_label.label = automatic
                ? _("La hauteur se recale dès que la recopie affiche l'image de l'iPhone.")
                : "";
        }
        video_label.visible = video_label.label != "";
        if (width > 0 && (int) width_spin.value != width) {
            width_spin.value = width;
        }
        if (height > 0 && (int) height_spin.value != height) {
            height_spin.value = height;
        }
        updating = false;
    }
}
