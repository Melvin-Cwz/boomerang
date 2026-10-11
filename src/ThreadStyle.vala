// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * The look of one conversation: a nickname and an emoji shown instead of the
 * contact's name, colour of my bubbles and of received ones, background, text
 * size and bubble shape. Kept in Boomerang only
 * (~/.config/boomerang/conversations.conf), the iPhone is not changed. The
 * editor also holds the conversation's notification settings, kept by boomerangd.
 */

namespace Boomerang {
    /* elementary's palette, in the order of the system accent colours. */
    private const string[] STYLE_COLOURS = {
        "#3689e6", "#28bca3", "#68b723", "#f9c440", "#ffa154",
        "#ed5353", "#de3e80", "#a56de2", "#8a715e", "#667885"
    };

    /* Light colours take dark text. */
    private const string[] STYLE_LIGHT = { "#68b723", "#f9c440", "#ffa154" };

    private const string[] STYLE_GRADIENTS = {
        "#ffa154,#de3e80", "#28bca3,#3689e6", "#a56de2,#de3e80", "#f9c440,#68b723", "#667885,#3689e6"
    };

    public class ThreadStyle : Object {
        public string bubble { get; set; default = ""; }      // "" : system accent
        public string incoming { get; set; default = ""; }    // "" : neutral grey
        public string background { get; set; default = ""; }  // "", "colour:#…", "gradient:#…,#…", "image:/path"
        public string text_size { get; set; default = ""; }   // "", "small", "large", "larger"
        public string shape { get; set; default = ""; }       // "", "soft", "square"
        public string nickname { get; set; default = ""; }
        public string emoji { get; set; default = ""; }

        private const string[] KEYS = { "bubble", "incoming", "background", "text-size", "shape", "nickname", "emoji" };
        private const string[] LOOK_KEYS = { "bubble", "incoming", "background", "text-size", "shape" };
        // The look every conversation takes unless it has its own (Réglages › Messages).
        public const string DEFAULTS = "*defaults*";
        // The list redraws often: the file is read once, then kept in step by save ().
        private static KeyFile? cache = null;

        private static string path () {
            return Path.build_filename (Environment.get_user_config_dir (), "boomerang", "conversations.conf");
        }

        /* Thread ids hold characters a key file group cannot. */
        private static string group (string thread) {
            return Checksum.compute_for_string (ChecksumType.SHA1, thread);
        }

        private static KeyFile read () {
            if (cache == null) {
                cache = new KeyFile ();
                try {
                    cache.load_from_file (path (), KeyFileFlags.KEEP_COMMENTS);
                } catch (Error e) {
                    // nothing customised yet
                }
            }
            return cache;
        }

        /* The look a conversation shows: its own choices, else the default look. */
        public static ThreadStyle load (string thread) {
            var style = load_raw (thread);
            if (thread == DEFAULTS) {
                return style;
            }
            var defaults = load_raw (DEFAULTS);
            foreach (var key in LOOK_KEYS) {
                Value mine = Value (typeof (string));
                style.get_property (key, ref mine);
                if (mine.get_string () == "") {
                    Value fallback = Value (typeof (string));
                    defaults.get_property (key, ref fallback);
                    style.set_property (key, fallback);
                }
            }
            return style;
        }

        /* Only what was chosen for this conversation (the editor shows and saves that). */
        public static ThreadStyle load_raw (string thread) {
            var style = new ThreadStyle ();
            var file = read ();
            var name = group (thread);
            if (!file.has_group (name)) {
                return style;  // most conversations: no error raised and caught per key
            }
            foreach (var key in KEYS) {
                try {
                    style.set_property (key, file.get_string (name, key));
                } catch (Error e) {
                    // key not set: default
                }
            }
            return style;
        }

        public bool is_default () {
            return is_default_look () && nickname == "" && emoji == "";
        }

        public bool is_default_look () {
            return bubble == "" && incoming == "" && background == "" && text_size == "" && shape == "";
        }

        /* The name to show for a conversation: emoji and nickname when set. */
        public string shown_name (string name) {
            var shown = nickname != "" ? nickname : name;
            return emoji != "" ? "%s %s".printf (emoji, shown) : shown;
        }

        public void save (string thread) {
            var file = read ();
            var name = group (thread);
            try {
                file.remove_group (name);
            } catch (Error e) {
                // not there yet
            }
            if (!is_default ()) {
                foreach (var key in KEYS) {
                    Value value = Value (typeof (string));
                    get_property (key, ref value);
                    file.set_string (name, key, value.get_string ());
                }
            }
            try {
                DirUtils.create_with_parents (Path.get_dirname (path ()), 0700);
                file.save_to_file (path ());
            } catch (Error e) {
                warning ("cannot save the conversation's look: %s", e.message);
            }
        }

        /* A background picture is copied for Boomerang: moving the original breaks nothing. */
        public void set_image (string thread, File source) throws Error {
            var folder = Path.build_filename (Environment.get_user_data_dir (), "boomerang", "backgrounds");
            DirUtils.create_with_parents (folder, 0700);
            var name = source.get_basename () ?? "";
            var dot = name.last_index_of (".");
            var extension = dot > 0 ? name.substring (dot).down () : ".jpg";
            // A new name each time, so GTK does not show a cached older picture.
            var target = File.new_for_path (Path.build_filename (
                folder, "%s-%s%s".printf (group (thread), get_real_time ().to_string (), extension)));
            source.copy (target, FileCopyFlags.OVERWRITE);
            drop_image ();
            background = "image:" + target.get_path ();
        }

        private static string own_images () {
            return Path.build_filename (Environment.get_user_data_dir (), "boomerang", "backgrounds");
        }

        /* Removes a picture copied for Boomerang; proposed pictures are left alone. */
        public void drop_image () {
            if (background.has_prefix ("image:") && background.substring (6).has_prefix (own_images () + "/")) {
                FileUtils.unlink (background.substring (6));
            }
        }

        /* Pictures offered in Fond: Boomerang's own, then the system wallpapers. */
        public static string[] proposed_images () {
            var own = Path.build_filename (Config.PKGDATADIR, "backgrounds");
            if (!FileUtils.test (own, FileTest.IS_DIR)) {
                // Development: the pictures of the source tree, next to the build directory.
                string exe = "/";
                try {
                    exe = FileUtils.read_link ("/proc/self/exe");
                } catch (FileError e) {
                    // no /proc: no development pictures
                }
                own = Path.build_filename (Path.get_dirname (Path.get_dirname (Path.get_dirname (exe))),
                                           "data", "backgrounds");
            }
            string[] found = {};
            foreach (var folder in new string[] { own, "/usr/share/backgrounds" }) {
                var names = new GenericArray<string> ();
                try {
                    var dir = Dir.open (folder);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        var lower = name.down ();
                        if (lower.has_suffix (".svg") || lower.has_suffix (".jpg") || lower.has_suffix (".png")) {
                            names.add (name);
                        }
                    }
                } catch (Error e) {
                    continue;  // no such folder
                }
                names.sort (strcmp);
                foreach (var n in names.data) {
                    found += Path.build_filename (folder, n);
                }
            }
            return found;
        }

        private static string text_on (string colour) {
            return colour in STYLE_LIGHT ? "rgba(0, 0, 0, 0.85)" : "white";
        }

        /* CSS for the thread box carrying the class "thread-styled". */
        public string css () {
            var css = new StringBuilder ();
            if (bubble != "") {
                // The contact's header bar takes the colour, darker so its white text stands out.
                css.append_printf ("headerbar.thread-bar.tinted { background: linear-gradient(mix(%s, black, 0.18), mix(%s, black, 0.32));"
                                   + " box-shadow: inset 0 1px alpha(white, 0.18), inset 0 -1px mix(%s, black, 0.5); }\n",
                                   bubble, bubble, bubble);
                css.append_printf (".thread-styled .bubble.outgoing { background-color: %s; color: %s; }\n",
                                   bubble, text_on (bubble));
                css.append_printf (".thread-styled .bubble.outgoing link { color: %s; }\n", text_on (bubble));
            }
            // Solid colours: received bubbles must stay visible on a background.
            if (incoming != "") {
                css.append_printf (".thread-styled .bubble.incoming { background-color: mix(@base_color, %s, 0.3); }\n",
                                   incoming);
            } else if (background != "") {
                css.append (".thread-styled .bubble.incoming { background-color: alpha(@base_color, 0.94); }\n");
            }
            var radius = shape == "soft" ? 10 : shape == "square" ? 4 : 18;
            var size = text_size == "small" ? "0.9em" : text_size == "large" ? "1.15em"
                     : text_size == "larger" ? "1.3em" : "1em";
            css.append_printf (".thread-styled .bubble { border-radius: %dpx; font-size: %s; }\n", radius, size);

            var scroll = ".thread-styled scrolledwindow.thread-scroll";
            if (background.has_prefix ("colour:")) {
                css.append_printf ("%s { background-color: alpha(%s, 0.14); }\n", scroll, background.substring (7));
            } else if (background.has_prefix ("gradient:")) {
                var stops = background.substring (9).split (",");
                if (stops.length == 2) {
                    css.append_printf ("%s { background-image: linear-gradient(160deg, alpha(%s, 0.22), alpha(%s, 0.22)); }\n",
                                       scroll, stops[0], stops[1]);
                }
            } else if (background.has_prefix ("image:")) {
                var uri = File.new_for_path (background.substring (6)).get_uri ().replace ("\"", "%22");
                // A veil of the window colour keeps the bubbles readable on any picture.
                css.append_printf ("%s { background-image: linear-gradient(alpha(@base_color, 0.45), alpha(@base_color, 0.45)), url(\"%s\");"
                                   + " background-size: cover, cover; background-position: center, center; }\n", scroll, uri);
            }
            return css.str;
        }
    }

    /* The popover behind the conversation's palette button: Apparence and Notifications. */
    public class ThreadStyleEditor : Gtk.Box {
        public signal void changed ();

        private string thread;
        private ThreadStyle style;
        private Gtk.Window? window;
        private Daemon daemon;
        private Gtk.Box page;
        private Gtk.Box alerts;
        private string notify_mode = "";
        private string notify_sound = "";
        private string[] sound_values = {};
        private string[] sound_labels = {};

        /* thread = ThreadStyle.DEFAULTS: the default look, in Réglages (no name, no notifications). */
        public ThreadStyleEditor (string thread, ThreadStyle style, Gtk.Window? window, Daemon daemon) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 9);
            this.thread = thread;
            this.style = style;
            this.window = window;
            this.daemon = daemon;
            width_request = 320;

            page = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            if (thread == ThreadStyle.DEFAULTS) {
                append (page);
                build ();
                return;
            }
            margin_top = margin_bottom = 9;
            margin_start = margin_end = 9;
            alerts = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var stack = new Gtk.Stack () { vhomogeneous = false };
            // Scrolls in a short window: a popover taller than the window does not open.
            var look = new Gtk.ScrolledWindow () {
                child = page,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_height = true,
                max_content_height = 360
            };
            stack.add_titled (look, "look", _("Apparence"));
            stack.add_titled (alerts, "alerts", _("Notifications"));
            append (new Gtk.StackSwitcher () { stack = stack, halign = Gtk.Align.CENTER });
            append (stack);
            build ();
            build_alerts ();  // at once with the defaults, then with the daemon's answer
            load_alerts.begin ();
        }

        private void build () {
            Gtk.Widget? child;
            while ((child = page.get_first_child ()) != null) {
                page.remove (child);
            }

            if (thread != ThreadStyle.DEFAULTS) {
                build_names ();
            }
            build_look ();
        }

        private void build_names () {
            heading (_("Nom affiché"));
            var names = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var nickname = new Gtk.Entry () {
                text = style.nickname,
                placeholder_text = _("Surnom (seulement dans Boomerang)"),
                hexpand = true
            };
            nickname.activate.connect (() => {
                style.nickname = nickname.text.strip ();
                apply (false);
            });
            var leave = new Gtk.EventControllerFocus ();
            leave.leave.connect (() => {
                if (nickname.text.strip () != style.nickname) {
                    style.nickname = nickname.text.strip ();
                    apply (false);
                }
            });
            nickname.add_controller (leave);
            var chooser = new Gtk.EmojiChooser ();
            chooser.emoji_picked.connect ((emoji) => {
                style.emoji = emoji;
                apply ();
            });
            var emoji = new Gtk.MenuButton () {
                popover = chooser,
                tooltip_text = _("Emoji de la conversation")
            };
            if (style.emoji != "") {
                emoji.label = style.emoji;
            } else {
                emoji.icon_name = "face-smile-symbolic";
            }
            names.append (nickname);
            names.append (emoji);
            if (style.emoji != "") {
                var drop = new Gtk.Button.from_icon_name ("edit-clear-symbolic") {
                    tooltip_text = _("Retirer l'emoji")
                };
                drop.add_css_class ("flat");
                drop.clicked.connect (() => {
                    style.emoji = "";
                    apply ();
                });
                names.append (drop);
            }
            page.append (names);
        }

        private void build_look () {
            heading (_("Mes bulles"));
            var mine = swatches ();
            mine.append (swatch ("", _("Couleur du système"), style.bubble == "", () => style.bubble = ""));
            foreach (var colour in STYLE_COLOURS) {
                mine.append (swatch (colour, null, style.bubble == colour, () => style.bubble = colour));
            }
            page.append (mine);

            heading (_("Bulles reçues"));
            var theirs = swatches ();
            theirs.append (swatch ("", _("Gris neutre"), style.incoming == "", () => style.incoming = ""));
            foreach (var colour in STYLE_COLOURS) {
                theirs.append (swatch (colour, null, style.incoming == colour, () => style.incoming = colour, 0.35));
            }
            page.append (theirs);

            heading (_("Fond"));
            var plain = swatches ();
            plain.append (swatch ("", _("Aucun"), style.background == "", () => {
                style.drop_image ();
                style.background = "";
            }));
            foreach (var colour in STYLE_COLOURS) {
                var value = "colour:" + colour;
                plain.append (swatch (colour, null, style.background == value, () => {
                    style.drop_image ();
                    style.background = value;
                }, 0.3));
            }
            page.append (plain);
            var fancy = swatches ();
            foreach (var pair in STYLE_GRADIENTS) {
                var value = "gradient:" + pair;
                fancy.append (swatch (pair, null, style.background == value, () => {
                    style.drop_image ();
                    style.background = value;
                }, 0.6));
            }
            var picture = new Gtk.Button.with_label (style.background.has_prefix ("image:")
                                                     ? _("Changer l'image…") : _("Image…")) {
                valign = Gtk.Align.CENTER
            };
            picture.add_css_class (Granite.CssClass.SMALL);
            picture.clicked.connect (choose_image);
            fancy.append (picture);
            page.append (fancy);

            // Proposed pictures: Boomerang's own and the system wallpapers.
            var pictures = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                max_children_per_line = 5,
                min_children_per_line = 5,
                column_spacing = 4,
                row_spacing = 4,
                homogeneous = true
            };
            foreach (var path in ThreadStyle.proposed_images ()) {
                var value = "image:" + path;
                pictures.append (thumbnail (path, style.background == value, () => {
                    style.drop_image ();
                    style.background = value;
                }));
            }
            var pictures_scroll = new Gtk.ScrolledWindow () {
                child = pictures,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_height = true,
                max_content_height = 150
            };
            page.append (pictures_scroll);

            heading (_("Texte"));
            page.append (choices ({ "small", "", "large", "larger" },
                             { _("Petit"), _("Normal"), _("Grand"), _("Très grand") },
                             style.text_size, (v) => style.text_size = v));

            heading (_("Forme des bulles"));
            page.append (choices ({ "", "soft", "square" }, { _("Rondes"), _("Douces"), _("Carrées") },
                             style.shape, (v) => style.shape = v));

            var reset = new Gtk.Button.with_label (_("Rétablir l'apparence d'origine")) {
                margin_top = 6,
                sensitive = !style.is_default_look ()
            };
            reset.add_css_class ("flat");
            reset.clicked.connect (() => {
                style.drop_image ();
                style.bubble = style.incoming = style.background = style.text_size = style.shape = "";
                apply ();
            });
            page.append (reset);
        }

        // Thumbnails are decoded once per run: some wallpapers are large photos.
        private static HashTable<string, Gdk.Texture>? thumbnails = null;

        private Gtk.Widget thumbnail (string path, bool selected, owned VoidFunc pick) {
            if (thumbnails == null) {
                thumbnails = new HashTable<string, Gdk.Texture> (str_hash, str_equal);
            }
            var picture = new Gtk.Picture () {
                content_fit = Gtk.ContentFit.COVER,
                width_request = 52,
                height_request = 36,
                can_shrink = true
            };
            picture.add_css_class ("thumb-picture");
            var cached = thumbnails[path];
            if (cached != null) {
                picture.paintable = cached;
            } else {
                load_thumbnail.begin (path, picture);
            }
            var button = new Gtk.Button () { child = picture, tooltip_text = pretty_name (path) };
            button.add_css_class ("style-thumb");
            if (selected) {
                button.add_css_class ("selected");
            }
            button.clicked.connect (() => {
                pick ();
                apply ();
            });
            return button;
        }

        /* Decoded in a thread: a wallpaper photo takes a while, the popover must not wait. */
        private static async void load_thumbnail (string path, Gtk.Picture picture) {
            SourceFunc done = load_thumbnail.callback;
            uint8[]? png = null;
            new Thread<void*> ("thumbnail", () => {
                try {
                    var pixbuf = new Gdk.Pixbuf.from_file_at_scale (cached_thumbnail (path) ?? path, 120, -1, true);
                    uint8[] data;
                    pixbuf.save_to_buffer (out data, "png");
                    png = data;
                } catch (Error e) {
                    // unreadable picture: the button stays blank
                }
                Idle.add ((owned) done);
                return null;
            });
            yield;
            if (png == null) {
                return;
            }
            try {
                var texture = Gdk.Texture.from_bytes (new Bytes (png));
                thumbnails[path] = texture;
                picture.paintable = texture;
            } catch (Error e) {
                // not decodable
            }
        }

        /* The desktop's thumbnail of a file, when Files already made one. */
        private static string? cached_thumbnail (string path) {
            var uri = File.new_for_path (path).get_uri ();
            var name = Checksum.compute_for_string (ChecksumType.MD5, uri) + ".png";
            foreach (var size in new string[] { "normal", "large" }) {
                var candidate = Path.build_filename (Environment.get_user_cache_dir (), "thumbnails", size, name);
                if (FileUtils.test (candidate, FileTest.EXISTS)) {
                    return candidate;
                }
            }
            return null;
        }

        private static string pretty_name (string path) {
            var name = Path.get_basename (path);
            var dot = name.last_index_of (".");
            name = dot > 0 ? name.substring (0, dot) : name;
            return name.substring (0, 1).up () + name.substring (1);
        }

        private Gtk.Label heading (string text, Gtk.Box? box = null) {
            var label = new Gtk.Label (text) { xalign = 0, margin_top = 4 };
            label.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
            (box ?? page).append (label);
            return label;
        }

        private static Gtk.Box swatches () {
            return new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
        }

        /* rebuild = false while typing the nickname: the entry keeps the focus. */
        private void apply (bool rebuild = true) {
            style.save (thread);
            changed ();
            if (rebuild) {
                build ();
            }
        }

        // --- notifications (boomerangd keeps them) ---

        private async void load_alerts () {
            try {
                var reply = yield daemon.call_checked ("GetThreadNotify", new Variant ("(s)", thread));
                reply.get ("(ss)", out notify_mode, out notify_sound);
            } catch (Error e) {
                warning ("GetThreadNotify failed: %s", e.message);
            }
            build_alerts ();
            try {
                var reply = yield daemon.call_checked ("ListSounds");
                var array = reply.get_child_value (0);
                for (size_t i = 0; i < array.n_children (); i++) {
                    string value, label;
                    array.get_child (i, "(ss)", out value, out label);
                    sound_values += value;
                    sound_labels += label;
                }
            } catch (Error e) {
                warning ("ListSounds failed: %s", e.message);
            }
            build_alerts ();
        }

        private void build_alerts () {
            Gtk.Widget? child;
            while ((child = alerts.get_first_child ()) != null) {
                alerts.remove (child);
            }
            heading (_("Alertes"), alerts);
            alerts.append (choices ({ "", "priority", "mute" }, { _("Normales"), _("Prioritaires"), _("Muettes") },
                                    notify_mode, (v) => {
                notify_mode = v;
                save_alerts ();
                build_alerts ();
            }));
            var help = new Gtk.Label (
                notify_mode == "priority" ? _("Bannière et son même en mode Ne pas déranger.")
                : notify_mode == "mute" ? _("Ni bannière ni son. Les messages arrivent et restent non lus.")
                : _("Comme les autres conversations.")
            ) { xalign = 0, wrap = true, max_width_chars = 40 };
            help.add_css_class (Granite.CssClass.DIM);
            help.add_css_class (Granite.CssClass.SMALL);
            alerts.append (help);
            if (notify_mode == "mute") {
                return;
            }

            heading (_("Son"), alerts);
            string[] values = { "", "none" };
            var model = new Gtk.StringList ({ _("Son des messages (Réglages)"), _("Aucun") });
            for (int i = 0; i < sound_values.length; i++) {
                values += sound_values[i];
                model.append (sound_labels[i]);
            }
            uint selected = 0;
            for (uint i = 0; i < values.length; i++) {
                if (values[i] == notify_sound) {
                    selected = i;
                }
            }
            var choice = new Gtk.DropDown (model, null) { selected = selected, hexpand = true, enable_search = true };
            choice.notify["selected"].connect (() => {
                notify_sound = values[choice.selected];
                save_alerts ();
            });
            var play = new Gtk.Button.from_icon_name ("media-playback-start-symbolic") {
                tooltip_text = _("Écouter")
            };
            play.clicked.connect (() => {
                var value = notify_sound != "" ? notify_sound : daemon_sound ();
                daemon.call.begin ("PlaySound", new Variant ("(ss)", "messages", value));
            });
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            line.append (choice);
            line.append (play);
            alerts.append (line);
        }

        private string daemon_sound () {
            var sounds = daemon.get_value ("Sounds");  // a{ss}
            if (sounds != null) {
                var value = sounds.lookup_value ("messages", VariantType.STRING);
                if (value != null) {
                    return value.get_string ();
                }
            }
            return "default";
        }

        private void save_alerts () {
            daemon.call.begin ("SetThreadNotify", new Variant ("(sss)", thread, notify_mode, notify_sound));
        }

        private Gtk.Widget swatch (string colour, string? tip, bool selected, owned VoidFunc pick,
                                   double strength = 1) {
            var area = new Gtk.DrawingArea () { content_width = 18, content_height = 18 };
            area.set_draw_func ((a, cr, w, h) => draw_swatch (cr, w, h, colour, strength));
            var button = new Gtk.Button () { child = area, tooltip_text = tip };
            button.add_css_class ("style-swatch");
            if (selected) {
                button.add_css_class ("selected");
            }
            button.update_property (Gtk.AccessibleProperty.LABEL, tip ?? colour, -1);
            button.clicked.connect (() => {
                pick ();
                apply ();
            });
            return button;
        }

        private static void draw_swatch (Cairo.Context cr, int w, int h, string colour, double strength) {
            var r = double.min (w, h) / 2.0 - 1;
            cr.arc (w / 2.0, h / 2.0, r, 0, 2 * Math.PI);
            var parts = colour.split (",");
            var a = Gdk.RGBA ();
            if (colour == "") {
                // "Default": an empty ring with a slash.
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);
                cr.set_line_width (1.5);
                cr.stroke ();
                cr.move_to (w / 2.0 - r * 0.7, h / 2.0 + r * 0.7);
                cr.line_to (w / 2.0 + r * 0.7, h / 2.0 - r * 0.7);
                cr.stroke ();
                return;
            }
            if (parts.length == 2) {
                var b = Gdk.RGBA ();
                a.parse (parts[0]);
                b.parse (parts[1]);
                var gradient = new Cairo.Pattern.linear (0, 0, w, h);
                gradient.add_color_stop_rgba (0, a.red, a.green, a.blue, strength);
                gradient.add_color_stop_rgba (1, b.red, b.green, b.blue, strength);
                cr.set_source (gradient);
            } else {
                a.parse (colour);
                cr.set_source_rgba (a.red, a.green, a.blue, strength);
            }
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.18);
            cr.set_line_width (1);
            cr.stroke ();
        }

        private delegate void Pick (string value);

        private Gtk.Widget choices (string[] values, string[] labels, string current, owned Pick pick) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { homogeneous = true };
            box.add_css_class ("linked");
            for (int i = 0; i < values.length; i++) {
                var value = values[i];
                var button = new Gtk.ToggleButton.with_label (labels[i]) { active = value == current };
                button.clicked.connect (() => {
                    pick (value);
                    apply ();
                });
                box.append (button);
            }
            return box;
        }

        private void choose_image () {
            var filter = new Gtk.FileFilter () { name = _("Images") };
            filter.add_mime_type ("image/png");
            filter.add_mime_type ("image/jpeg");
            filter.add_mime_type ("image/webp");
            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            var dialog = new Gtk.FileDialog () { title = _("Image de fond"), filters = filters };
            var pictures = Environment.get_user_special_dir (UserDirectory.PICTURES);
            if (pictures != null) {
                dialog.initial_folder = File.new_for_path (pictures);
            }
            dialog.open.begin (window, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    style.set_image (thread, file);
                    apply ();
                } catch (Error e) {
                    // cancelled, or the copy failed: nothing changes
                }
            });
        }
    }
}
