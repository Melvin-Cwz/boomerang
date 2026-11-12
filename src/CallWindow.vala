// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Phone calls on this PC through the iPhone (HFP): the in-call window, the
 * keypad and the Téléphone tab. The daemon opens the window when a call rings
 * out, is answered, or when a second call arrives during a call; incoming calls
 * ring in a notification (Répondre / Refuser) and here if open.
 *
 * Two calls at once follow what PipeWire offers (see boomerangd/calls.py): put
 * the call on hold and answer, hang up and answer, swap, merge, hang up all.
 * Each call listed by the daemon carries the actions possible right now, and the
 * window only shows those: a lone call cannot be put on hold through PipeWire.
 *
 * Audio goes through this PC's speakers and microphone while the hands-free
 * audio link is up; the Sortie audio menu picks an output of the PC or hands
 * the audio back to the iPhone.
 */

namespace Boomerang {
    /* 0-9, * and # as a 3 x 4 grid of round buttons, with letters like a phone. */
    public class Keypad : Gtk.Grid {
        public signal void pressed (string key);

        private const string[] KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" };
        private const string[] LETTERS = { "", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ",
                                           "", "+", "" };

        construct {
            row_spacing = 10;
            column_spacing = 16;
            halign = Gtk.Align.CENTER;
            for (int i = 0; i < KEYS.length; i++) {
                var key = KEYS[i];
                var digit = new Gtk.Label (key);
                digit.add_css_class ("keypad-digit");
                var letters = new Gtk.Label (LETTERS[i]);
                letters.add_css_class ("keypad-letters");
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
                box.append (digit);
                box.append (letters);
                var button = new Gtk.Button () { child = box };
                button.add_css_class ("keypad-key");
                button.add_css_class ("circular");
                button.update_property (Gtk.AccessibleProperty.LABEL, key, -1);
                button.clicked.connect (() => pressed (key));
                attach (button, i % 3, i / 3);
            }
        }
    }

    /* Number field over the keypad, then Appeler (calls from the iPhone, on click only). */
    public class DialPad : Gtk.Box {
        public Daemon daemon { get; construct; }
        public signal void dialled ();
        private Gtk.Entry number;

        public DialPad (Daemon daemon) {
            Object (daemon: daemon, orientation: Gtk.Orientation.VERTICAL, spacing: 14);
        }

        construct {
            number = new Gtk.Entry () {
                placeholder_text = _("Numéro"),
                input_purpose = Gtk.InputPurpose.PHONE,
                xalign = 0.5f
            };
            number.add_css_class ("dial-number");
            number.update_property (Gtk.AccessibleProperty.LABEL, _("Numéro à appeler"), -1);
            var keypad = new Keypad ();
            keypad.pressed.connect ((key) => {
                number.text += key;
                number.set_position (-1);
            });
            var call = new CallButton (daemon, "", null) { halign = Gtk.Align.CENTER };
            call.remove_css_class ("flat");
            call.add_css_class ("call-green");
            call.add_css_class ("circular");
            call.number_source = () => number.text.strip ();
            call.dialled.connect (() => {
                number.text = "";
                dialled ();
            });
            number.activate.connect (() => call.clicked ());
            append (number);
            append (keypad);
            append (call);
        }

        public void focus_number () {
            number.grab_focus ();
        }

        /* A tel: link: the number ready, nothing dialled until Appeler. */
        public void set_number (string text) {
            number.text = text;
            number.grab_focus ();
            number.set_position (-1);
        }
    }

    /* "Composer un numéro" button in the call list: the dial pad in a popover. */
    public class DialPopover : Gtk.Popover {
        public Daemon daemon { get; construct; }

        public DialPopover (Daemon daemon) {
            Object (daemon: daemon);
        }

        construct {
            var pad = new DialPad (daemon) {
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 12,
                margin_end = 12
            };
            pad.dialled.connect (() => popdown ());
            child = pad;
            show.connect (() => pad.focus_number ());
        }
    }

    /*
     * Messagerie vocale: dials the operator's voicemail number from the iPhone, like
     * any call. The iPhone's visual voicemail never reaches a computer: the popover
     * says so, and keeps the number in the app's settings.
     */
    public class VoicemailButton : Gtk.Box {
        public Daemon daemon { get; construct; }
        private Gtk.Entry number;
        private Gtk.Button call;
        private Gtk.Label failed;
        private Gtk.MenuButton menu;

        public VoicemailButton (Daemon daemon) {
            Object (daemon: daemon, halign: Gtk.Align.CENTER);
        }

        construct {
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            content.append (new Gtk.Image.from_icon_name ("media-tape-symbolic"));
            content.append (new Gtk.Label (_("Messagerie vocale")));
            menu = new Gtk.MenuButton () { child = content };
            append (menu);
            menu.add_css_class ("flat");
            menu.tooltip_text = _("Appeler le numéro de messagerie de l'opérateur");

            var title = new Gtk.Label (_("Messagerie vocale")) { xalign = 0 };
            title.add_css_class ("heading");
            var explain = new Gtk.Label (_("Boomerang compose le numéro de messagerie de votre "
                                           + "opérateur depuis l'iPhone. La messagerie visuelle de "
                                           + "l'iPhone n'est pas accessible depuis un ordinateur.")) {
                wrap = true,
                max_width_chars = 34,
                xalign = 0
            };
            explain.add_css_class (Granite.CssClass.DIM);
            number = new Gtk.Entry () {
                placeholder_text = _("Numéro de messagerie"),
                input_purpose = Gtk.InputPurpose.PHONE,
                text = saved_number ()
            };
            number.update_property (Gtk.AccessibleProperty.LABEL, _("Numéro de messagerie"), -1);
            var hint = new Gtk.Label (_("Orange : 888 · SFR : 123 · Bouygues Telecom : 660 · Free : 666")) {
                wrap = true,
                max_width_chars = 34,
                xalign = 0
            };
            hint.add_css_class (Granite.CssClass.SMALL);
            hint.add_css_class (Granite.CssClass.DIM);
            failed = new Gtk.Label (_("Appel impossible : le profil mains libres de l'iPhone n'est pas connecté")) {
                wrap = true,
                max_width_chars = 34,
                xalign = 0,
                visible = false
            };
            failed.add_css_class (Granite.CssClass.ERROR);
            call = new Gtk.Button.with_label (_("Appeler la messagerie"));
            call.add_css_class (Granite.CssClass.SUGGESTED);
            call.clicked.connect (dial);
            number.activate.connect (dial);
            number.changed.connect (() => call.sensitive = only_digits (number.text).length >= 2);
            call.sensitive = only_digits (number.text).length >= 2;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 9) {
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 12,
                margin_end = 12
            };
            box.append (title);
            box.append (explain);
            box.append (number);
            box.append (hint);
            box.append (failed);
            box.append (call);
            var popover = new Gtk.Popover () { child = box };
            popover.show.connect (() => {
                failed.visible = false;
                if (number.text != "") {
                    call.grab_focus ();
                } else {
                    number.grab_focus ();
                }
            });
            menu.set_popover (popover);
        }

        private static string saved_number () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
                return prefs.get_string ("phone", "voicemail");
            } catch (Error e) {
                return "";
            }
        }

        private void save_number (string value) {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.KEEP_COMMENTS);
            } catch (Error e) {
                // first setting
            }
            prefs.set_string ("phone", "voicemail", value);
            try {
                DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
                prefs.save_to_file (Setup.prefs_path ());
            } catch (Error e) {
                warning ("cannot save the voicemail number: %s", e.message);
            }
        }

        private void dial () {
            var target = number.text.strip ();
            if (only_digits (target).length < 2) {
                return;
            }
            save_number (target);
            call.sensitive = false;
            daemon.call_send.begin ("Dial", new Variant ("(s)", target), (obj, res) => {
                var ok = daemon.call_send.end (res);
                call.sensitive = true;
                failed.visible = !ok;
                if (ok) {
                    menu.popover.popdown ();
                }
            });
        }
    }

    /* Pavé: Récents, Manqués or Favoris in the list column, the keypad and the voicemail on the right. */
    public class PhoneView : Gtk.Box {
        public Daemon daemon { get; construct; }
        public CallsView history { get; private set; }
        public FavoritesView favorites { get; private set; }
        private Gtk.Box recents;
        private DialPad pad;

        public void prefill (string number) {
            pad.set_number (number);
        }

        public PhoneView (Daemon daemon) {
            Object (daemon: daemon, orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        }

        construct {
            // The list column has the width of Messages and Contacts; like Phone on the Mac,
            // all calls, the missed ones only, or the iPhone's favourites.
            history = new CallsView (daemon, false, true) { vexpand = true };
            favorites = new FavoritesView (daemon) { vexpand = true };
            favorites.message_requested.connect ((address) => history.message_requested (address));
            history.number_chosen.connect ((number) => pad.set_number (number));
            favorites.number_chosen.connect ((number) => pad.set_number (number));
            var search = new Gtk.SearchEntry () {
                placeholder_text = _("Rechercher un nom ou un numéro"),
                hexpand = true
            };
            search.update_property (Gtk.AccessibleProperty.LABEL, _("Rechercher dans les appels"), -1);
            search.search_changed.connect (() => {
                history.query = search.text;
                favorites.query = search.text;
            });
            var all = new Gtk.ToggleButton.with_label (_("Tous")) { active = true, hexpand = true };
            var missed = new Gtk.ToggleButton.with_label (_("Manqués")) { group = all, hexpand = true };
            var starred = new Gtk.ToggleButton.with_label (_("Favoris")) { group = all, hexpand = true };
            missed.bind_property ("active", history, "missed-only", BindingFlags.SYNC_CREATE);
            var lists = new Gtk.Stack ();
            lists.add_named (history, "recents");
            lists.add_named (favorites, "favorites");
            starred.toggled.connect (() => {
                lists.visible_child_name = starred.active ? "favorites" : "recents";
            });
            var filter = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { homogeneous = true };
            filter.add_css_class ("linked");
            filter.append (all);
            filter.append (missed);
            filter.append (starred);
            var top = new Gtk.Box (Gtk.Orientation.VERTICAL, 9) {
                margin_top = 9,
                margin_bottom = 9,
                margin_start = 12,
                margin_end = 12
            };
            top.append (search);
            top.append (filter);
            recents = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 280 };
            recents.append (top);
            recents.append (lists);

            pad = new DialPad (daemon);
            var voicemail = new VoicemailButton (daemon);
            var detail = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.CENTER,
                hexpand = true,
                width_request = 280
            };
            detail.append (pad);
            detail.append (voicemail);
            // The big title of the pages, then the keypad in the middle of what is left.
            var title = new Gtk.Label (_("Pavé")) { xalign = 0, margin_top = 24, margin_start = 24, margin_end = 24 };
            title.add_css_class ("title-1");
            detail.vexpand = true;
            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            right.append (title);
            right.append (detail);
            // A pane like Messages and Contacts: the list column keeps its width.
            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = recents,
                end_child = right,
                resize_start_child = false,
                shrink_start_child = false,
                shrink_end_child = false,
                position = 280,
                hexpand = true
            };
            append (paned);
        }
    }

    /* "04:32", "1:02:07": the clock of a call going on. */
    public string call_clock (int seconds) {
        return seconds >= 3600
            ? "%d:%02d:%02d".printf (seconds / 3600, (seconds / 60) % 60, seconds % 60)
            : "%02d:%02d".printf (seconds / 60, seconds % 60);
    }

    /* The calls going on, as listed by the daemon, sorted out for the call window and bar. */
    public class CallSet : Object {
        public VariantDict? main = null;      // the call shown big
        public VariantDict? waiting = null;   // a second call ringing during main
        public VariantDict? held = null;      // a call on hold beside main
        public string[] actions = {};         // possible now (union over the calls)
        public string[] conference = {};      // names of the calls merged together

        public CallSet (Variant[] calls) {
            VariantDict? active = null, ringing = null, dialing = null, on_hold = null;
            string[] possible = {};
            string[] merged = {};
            foreach (var item in calls) {
                var d = new VariantDict (item);
                var state = dict_string (d, "state");
                var listed = d.lookup_value ("actions", VariantType.STRING_ARRAY);
                if (listed != null) {
                    foreach (var action in listed.get_strv ()) {
                        if (!(action in possible)) {
                            possible += action;
                        }
                    }
                }
                if (state == "active" && dict_bool (d, "multiparty")) {
                    merged += dict_string (d, "name");
                }
                switch (state) {
                    case "active":
                        active = active ?? d;
                        break;
                    case "incoming":
                        ringing = ringing ?? d;
                        break;
                    case "dialing":
                    case "alerting":
                        dialing = dialing ?? d;
                        break;
                    case "held":
                        on_hold = on_hold ?? d;
                        break;
                    case "waiting":
                        waiting = waiting ?? d;
                        break;
                }
            }
            main = active ?? ringing ?? dialing ?? on_hold;
            if (main == null) {
                main = waiting;  // the first call just ended: the second one rings alone
                waiting = null;
            }
            if (on_hold != null && on_hold != main) {
                held = on_hold;
            }
            actions = possible;
            conference = merged.length >= 2 ? merged : new string[0];
        }

        public bool can (string action) {
            return action in actions;
        }

        public static string? path_of (VariantDict? d) {
            if (d == null) {
                return null;
            }
            var v = d.lookup_value ("path", VariantType.OBJECT_PATH);
            return v != null ? v.get_string () : null;
        }
    }

    public class CallWindow : Gtk.Window {
        private Daemon daemon;
        private Avatar avatar;
        private Gtk.Label name_label;
        private Gtk.Label number_label;
        private Gtk.Label status_label;
        private Gtk.Label error_label;
        private Gtk.Stack actions;
        private Gtk.ToggleButton mute;
        private Gtk.ToggleButton keypad_toggle;
        private Gtk.MenuButton output;
        private Gtk.Label output_label;
        private Gtk.Box output_list;
        private Gtk.Widget swap_option;
        private Gtk.Widget merge_option;
        private Gtk.Widget resume_option;
        private Gtk.Revealer keypad_revealer;
        private Gtk.Revealer waiting_revealer;
        private Avatar waiting_avatar;
        private Gtk.Label waiting_name;
        private Gtk.Button hold_answer;
        private Gtk.Button end_answer;
        private Gtk.Button refuse;
        private Gtk.Revealer held_revealer;
        private Gtk.Label held_name;
        private Gtk.Button held_swap;
        private Gtk.Button answer;
        private Gtk.Button hangup;
        private CallSet calls = new CallSet ({});
        private string? call_path = null;
        private string? waiting_path = null;
        private int duration = -1;
        private bool updating = false;
        private bool ended = false;
        private uint tick = 0;
        private uint error_timer = 0;
        private string announced = "";

        public CallWindow (Gtk.Application app) {
            Object (application: app, title: _("Appel"), default_width: 360, resizable: false);
        }

        construct {
            add_css_class ("call-window");
            var header = new Gtk.HeaderBar ();
            header.add_css_class ("flat");
            header.title_widget = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            titlebar = header;

            // A second call during a call: the three choices of the iPhone, the safest first.
            waiting_avatar = new Avatar (40);
            var waiting_title = new Gtk.Label (_("Double appel")) { xalign = 0 };
            waiting_title.add_css_class (Granite.CssClass.SMALL);
            waiting_title.add_css_class (Granite.CssClass.DIM);
            waiting_name = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            waiting_name.add_css_class ("heading");
            var waiting_text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
            waiting_text.append (waiting_title);
            waiting_text.append (waiting_name);
            var waiting_head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            waiting_head.append (waiting_avatar);
            waiting_head.append (waiting_text);
            hold_answer = choice (_("Mettre en attente et répondre"), "answer");
            hold_answer.tooltip_markup = Granite.markup_accel_tooltip ({ "<Control>Return" },
                                                                     _("L'appel en cours est mis en attente"));
            hold_answer.clicked.connect (() => act ("hold-and-answer"));
            end_answer = choice (_("Raccrocher et répondre"), null);
            end_answer.tooltip_text = _("L'appel en cours est terminé");
            end_answer.clicked.connect (() => act ("release-and-answer"));
            refuse = choice (_("Refuser"), "decline");
            refuse.clicked.connect (() => act ("hangup", waiting_path));
            var waiting_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            waiting_card.add_css_class (Granite.CssClass.CARD);
            waiting_card.add_css_class ("call-banner");
            waiting_card.append (waiting_head);
            waiting_card.append (hold_answer);
            waiting_card.append (end_answer);
            waiting_card.append (refuse);
            waiting_revealer = new Gtk.Revealer () { child = waiting_card, margin_bottom = 6 };

            // The other call, on hold.
            var held_icon = new Gtk.Image.from_icon_name ("media-playback-pause-symbolic");
            held_icon.add_css_class (Granite.CssClass.DIM);
            var held_title = new Gtk.Label (_("En attente")) { xalign = 0 };
            held_title.add_css_class (Granite.CssClass.SMALL);
            held_title.add_css_class (Granite.CssClass.DIM);
            held_name = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            var held_text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
            held_text.append (held_title);
            held_text.append (held_name);
            held_swap = choice (_("Permuter"), null);
            held_swap.valign = Gtk.Align.CENTER;
            held_swap.tooltip_text = _("Reprendre cet appel et mettre l'autre en attente");
            held_swap.clicked.connect (() => act ("swap"));
            var held_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            held_row.add_css_class (Granite.CssClass.CARD);
            held_row.add_css_class ("call-banner");
            held_row.append (held_icon);
            held_row.append (held_text);
            held_row.append (held_swap);
            held_revealer = new Gtk.Revealer () { child = held_row, margin_bottom = 6 };

            avatar = new Avatar (96) { margin_top = 6 };
            name_label = new Gtk.Label ("") {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                max_width_chars = 24
            };
            name_label.add_css_class (Granite.HeaderLabel.Size.H2.to_string ());
            number_label = new Gtk.Label ("") {
                justify = Gtk.Justification.CENTER,
                wrap = true,
                max_width_chars = 30,
                visible = false
            };
            number_label.add_css_class (Granite.CssClass.DIM);
            status_label = new Gtk.Label ("") { justify = Gtk.Justification.CENTER };
            status_label.add_css_class (Granite.CssClass.DIM);
            status_label.add_css_class ("numeric");
            var who = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            who.append (name_label);
            who.append (number_label);
            who.append (status_label);

            mute = new Gtk.ToggleButton () { icon_name = "microphone-sensitivity-muted-symbolic" };
            round_option (mute, _("Couper le micro"), "<Control>m");
            mute.toggled.connect (() => {
                if (!updating) {
                    daemon.call.begin ("SetMuted", new Variant ("(b)", mute.active));
                }
            });
            keypad_toggle = new Gtk.ToggleButton () { icon_name = "input-dialpad-symbolic" };
            round_option (keypad_toggle, _("Afficher le clavier"), "<Control>k");
            output = build_output_menu ();
            var swap = new Gtk.Button.from_icon_name ("system-switch-user-symbolic");
            round_option (swap, _("Reprendre l'appel en attente et mettre l'appel en cours en attente"), null);
            swap.clicked.connect (() => act ("swap"));
            var merge = new Gtk.Button.from_icon_name ("object-group-symbolic");
            round_option (merge, _("Réunir les deux appels en conférence (selon l'opérateur)"), null);
            merge.clicked.connect (() => act ("merge"));
            var resume = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
            round_option (resume, _("Reprendre l'appel"), null);
            resume.clicked.connect (() => act ("resume"));
            output_label = new Gtk.Label (_("Sortie audio"));
            swap_option = labelled (swap, new Gtk.Label (_("Permuter")));
            merge_option = labelled (merge, new Gtk.Label (_("Fusionner")));
            resume_option = labelled (resume, new Gtk.Label (_("Reprendre")));
            // Everyday controls, then the actions on two calls, each row centred.
            var main_options = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18) {
                halign = Gtk.Align.CENTER,
                homogeneous = true
            };
            main_options.append (labelled (mute, new Gtk.Label (_("Silence"))));
            main_options.append (labelled (keypad_toggle, new Gtk.Label (_("Clavier"))));
            main_options.append (labelled (output, output_label));
            var two_calls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18) {
                halign = Gtk.Align.CENTER,
                homogeneous = true
            };
            two_calls.append (swap_option);
            two_calls.append (merge_option);
            two_calls.append (resume_option);
            var options = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            options.append (main_options);
            options.append (two_calls);

            var keypad = new Keypad () { margin_top = 6 };
            keypad.pressed.connect (send_tone);
            keypad_revealer = new Gtk.Revealer () { child = keypad };
            keypad_toggle.bind_property ("active", keypad_revealer, "reveal-child");

            hangup = round ("call-stop-symbolic", "call-red", _("Raccrocher"), "<Control><Shift>r");
            hangup.clicked.connect (hang_up);
            var decline = round ("call-stop-symbolic", "call-red", _("Refuser"), "<Control><Shift>r");
            decline.clicked.connect (() => act ("hangup"));
            answer = round ("call-start-symbolic", "call-green", C_("call", "Répondre"), "<Control>Return");
            answer.clicked.connect (() => act ("answer"));
            var ringing = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 64) { halign = Gtk.Align.CENTER };
            ringing.append (labelled (decline, new Gtk.Label (_("Refuser"))));
            ringing.append (labelled (answer, new Gtk.Label (C_("call", "Répondre"))));
            var in_call = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { halign = Gtk.Align.CENTER };
            in_call.append (labelled (hangup, new Gtk.Label (_("Raccrocher"))));
            actions = new Gtk.Stack () { vhomogeneous = false };
            actions.add_named (ringing, "ringing");
            actions.add_named (in_call, "call");
            actions.add_named (new Gtk.Box (Gtk.Orientation.VERTICAL, 0), "none");

            error_label = new Gtk.Label ("") {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                max_width_chars = 34,
                visible = false
            };
            error_label.add_css_class (Granite.CssClass.ERROR);
            error_label.add_css_class (Granite.CssClass.SMALL);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_start = 24,
                margin_end = 24,
                margin_bottom = 24
            };
            content.append (waiting_revealer);
            content.append (held_revealer);
            content.append (avatar);
            content.append (who);
            content.append (new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { height_request = 6 });
            content.append (options);
            content.append (keypad_revealer);
            content.append (new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { height_request = 6 });
            content.append (actions);
            content.append (error_label);
            child = content;

            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect (on_key);
            ((Gtk.Widget) this).add_controller (keys);

            daemon = new Daemon ();
            daemon.active_calls_changed.connect (() => reload.begin ());
            daemon.changed.connect (() => {
                if (daemon.touched ({ "MicMuted", "AudioOnPC" })) {
                    update_toggles ();
                }
            });
            daemon.connect_bus.begin ((obj, res) => {
                daemon.connect_bus.end (res);
                reload.begin ();
            });
            // Off-screen captures (BOOMERANG_SNAPSHOT) keep the clock still: a label changing
            // after the first frame leaves the window unpainted there.
            var still = Environment.get_variable ("BOOMERANG_SNAPSHOT") != null;
            tick = Timeout.add_seconds (1, () => {
                if (duration >= 0 && !still) {
                    duration++;
                    status_label.label = running_status ();
                }
                return Source.CONTINUE;
            });
            close_request.connect (() => {
                if (tick != 0) {
                    Source.remove (tick);
                    tick = 0;
                }
                if (error_timer != 0) {
                    Source.remove (error_timer);
                    error_timer = 0;
                }
                return false;
            });
        }

        /*
         * Keyboard: Ctrl+Entrée answers (puts the call on hold first when a second call rings),
         * Ctrl+Maj+R hangs up or declines, Ctrl+M mutes, Ctrl+K shows the keypad, digits send
         * tones while the keypad is shown, Échap closes the window and the call goes on.
         * Hanging up needs two modifiers: no single key ends a call.
         */
        private bool on_key (uint keyval, uint keycode, Gdk.ModifierType state) {
            var mods = state & Gtk.accelerator_get_default_mod_mask ();
            var key = Gdk.keyval_to_lower (keyval);
            var ctrl = Gdk.ModifierType.CONTROL_MASK;
            var ctrl_shift = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK;
            if (mods == 0 && keyval == Gdk.Key.Escape) {
                close ();
                return true;
            }
            if (mods == ctrl && (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter)) {
                if (waiting_revealer.reveal_child && calls.can ("hold-and-answer")) {
                    act ("hold-and-answer");
                } else if (actions.visible_child_name == "ringing" && answer.sensitive) {
                    act ("answer");
                }
                return true;
            }
            if (mods == ctrl_shift && key == Gdk.Key.r) {
                if (actions.visible_child_name == "ringing") {
                    act ("hangup");
                } else if (actions.visible_child_name == "call") {
                    hang_up ();
                }
                return true;
            }
            if (mods == ctrl && key == Gdk.Key.m && mute.get_mapped () && mute.sensitive) {
                mute.active = !mute.active;
                return true;
            }
            if (mods == ctrl && key == Gdk.Key.k && keypad_toggle.get_mapped ()) {
                keypad_toggle.active = !keypad_toggle.active;
                return true;
            }
            if ((mods & ~Gdk.ModifierType.SHIFT_MASK) == 0 && keypad_revealer.reveal_child) {
                var c = (unichar) Gdk.keyval_to_unicode (keyval);
                if (c.isdigit () || c == '*' || c == '#') {
                    send_tone (c.to_string ());
                    return true;
                }
            }
            return false;
        }

        private void send_tone (string key) {
            daemon.call_send.begin ("SendTones", new Variant ("(s)", key));
        }

        /* A round button of the options row: own frame (Granite 9 draws none), a name for Orca. */
        private void round_option (Gtk.Widget button, string tip, string? accel) {
            button.add_css_class ("circular");
            button.add_css_class ("call-option");
            button.tooltip_markup = accel != null ? Granite.markup_accel_tooltip ({ accel }, tip)
                                                  : Markup.escape_text (tip);
            button.update_property (Gtk.AccessibleProperty.LABEL, tip, -1);
        }

        /* A full-width choice in the double call banner: answer (green), decline (red text) or plain. */
        private Gtk.Button choice (string text, string? kind) {
            var button = new Gtk.Button.with_label (text);
            button.add_css_class ("call-choice");
            if (kind != null) {
                button.add_css_class (kind);
            }
            return button;
        }

        private Gtk.Button round (string icon, string css, string tip, string accel) {
            var button = new Gtk.Button.from_icon_name (icon) {
                tooltip_markup = Granite.markup_accel_tooltip ({ accel }, tip)
            };
            button.add_css_class ("circular");
            button.add_css_class (css);
            button.update_property (Gtk.AccessibleProperty.LABEL, tip, -1);
            return button;
        }

        private Gtk.Widget labelled (Gtk.Widget button, Gtk.Label label) {
            label.add_css_class (Granite.CssClass.SMALL);
            label.add_css_class (Granite.CssClass.DIM);
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) { halign = Gtk.Align.CENTER };
            button.halign = Gtk.Align.CENTER;
            box.append (button);
            box.append (label);
            return box;
        }

        /* Sortie audio: the iPhone, or one of this PC's outputs for the call. */
        private Gtk.MenuButton build_output_menu () {
            var button = new Gtk.MenuButton () { icon_name = "audio-speakers-symbolic" };
            button.add_css_class ("call-option");
            button.tooltip_text = _("Choisir la sortie audio de l'appel");
            button.update_property (Gtk.AccessibleProperty.LABEL, _("Sortie audio"), -1);
            var title = new Gtk.Label (_("Sortie audio de l'appel")) { xalign = 0, margin_bottom = 3 };
            title.add_css_class ("heading");
            output_list = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 12,
                margin_end = 12,
                width_request = 240
            };
            box.append (title);
            box.append (output_list);
            var popover = new Gtk.Popover () { child = box };
            popover.show.connect (() => fill_outputs.begin ());
            button.popover = popover;
            return button;
        }

        private async void fill_outputs () {
            var outputs = yield daemon.call_list ("ListCallAudioOutputs");
            Gtk.Widget? child;
            while ((child = output_list.get_first_child ()) != null) {
                output_list.remove (child);
            }
            var on_pc = daemon.get_bool ("AudioOnPC");
            var phone = new Gtk.CheckButton.with_label ("iPhone") { active = !on_pc };
            phone.toggled.connect (() => {
                if (phone.active && !updating) {
                    daemon.call_send.begin ("SetCallAudio", new Variant ("(b)", false));
                    output.popover.popdown ();
                }
            });
            output_list.append (phone);
            bool any_current = false;
            foreach (var item in outputs) {
                any_current = any_current || dict_bool (new VariantDict (item), "current");
            }
            updating = true;
            foreach (var item in outputs) {
                var d = new VariantDict (item);
                var is_default = dict_bool (d, "default");
                var label = is_default ? _("%s (sortie par défaut)").printf (dict_string (d, "description"))
                                       : dict_string (d, "description");
                // The default output is stored as "" so that it follows the system's choice.
                var name = is_default ? "" : dict_string (d, "name");
                var radio = new Gtk.CheckButton.with_label (label) {
                    group = phone,
                    active = on_pc && (dict_bool (d, "current") || (!any_current && is_default))
                };
                radio.toggled.connect (() => {
                    if (!radio.active || updating) {
                        return;
                    }
                    daemon.call.begin ("SetCallAudioOutput", new Variant ("(s)", name));
                    if (!daemon.get_bool ("AudioOnPC")) {
                        daemon.call_send.begin ("SetCallAudio", new Variant ("(b)", true));
                    }
                    output.popover.popdown ();
                });
                output_list.append (radio);
            }
            if (outputs.length == 0) {
                var none = new Gtk.Label (_("Aucune sortie audio de ce PC n'est disponible")) {
                    wrap = true,
                    max_width_chars = 30,
                    xalign = 0
                };
                none.add_css_class (Granite.CssClass.DIM);
                output_list.append (none);
            }
            updating = false;
        }

        private void act (string action, string? path = null) {
            var target = path ?? call_path;
            if (target == null) {
                return;
            }
            daemon.call_send.begin ("CallAction", new Variant ("(os)", target, action), (obj, res) => {
                if (!daemon.call_send.end (res)) {
                    show_error (_("L'iPhone a refusé cette action"));
                }
            });
        }

        /* The red button: one call ends; in a conference, every call of it. */
        private void hang_up () {
            act (calls.conference.length > 0 && calls.can ("hangup-all") ? "hangup-all" : "hangup");
        }

        private void show_error (string text) {
            error_label.label = text;
            error_label.visible = true;
            announce_text (text);
            if (error_timer != 0) {
                Source.remove (error_timer);
            }
            error_timer = Timeout.add_seconds (5, () => {
                error_label.visible = false;
                error_timer = 0;
                return Source.REMOVE;
            });
        }

        private void announce_text (string text) {
            if (text == announced || !get_mapped ()) {
                return;
            }
            announced = text;
            // Only the AT-SPI context implements announcements: GTK's fallback context (no
            // accessibility bus, or the off-screen captures) crashes on them.
            var context = get_at_context ();
            if (context != null && context.get_type ().name () == "GtkAtSpiContext") {
                announce (text, Gtk.AccessibleAnnouncementPriority.MEDIUM);
            }
        }

        private void update_toggles () {
            updating = true;
            mute.active = daemon.get_bool ("MicMuted");
            var on_pc = daemon.get_bool ("AudioOnPC");
            output.icon_name = on_pc ? "audio-speakers-symbolic" : "phone-symbolic";
            output_label.label = on_pc ? _("Sortie audio") : "iPhone";
            updating = false;
        }

        private string running_status () {
            var clock = call_clock (int.max (duration, 0));
            return _("Appel en cours · %s").printf (clock);
        }

        private async void reload () {
            calls = new CallSet (yield daemon.call_list ("ListActiveCalls"));
            update_toggles ();
            var main = calls.main;
            if (main == null) {
                waiting_revealer.reveal_child = false;
                held_revealer.reveal_child = false;
                if (call_path != null && !ended) {
                    ended = true;
                    duration = -1;
                    status_label.label = _("Appel terminé");
                    announce_text (_("Appel terminé"));
                    actions.visible_child_name = "none";
                    Timeout.add_seconds (2, () => {
                        close ();
                        return Source.REMOVE;
                    });
                } else if (call_path == null) {
                    status_label.label = _("Aucun appel");
                    actions.visible_child_name = "none";
                }
                return;
            }
            ended = false;
            call_path = CallSet.path_of (main);
            var state = dict_string (main, "state");
            var name = dict_string (main, "name");
            var number = format_address (dict_string (main, "number"));
            if (calls.conference.length > 0) {
                name_label.label = _("Conférence");
                number_label.label = string.joinv (", ", calls.conference);
                number_label.visible = true;
                avatar.show_person (_("Conférence"), "", true);
                title = _("Conférence");
            } else {
                name_label.label = name;
                number_label.label = number;
                number_label.visible = number != "" && number != name;
                avatar.show_person (name, dict_string (main, "avatar"));
                title = _("Appel avec %s").printf (name);
            }

            // Second call ringing during this one.
            waiting_revealer.reveal_child = calls.waiting != null;
            if (calls.waiting != null) {
                waiting_path = CallSet.path_of (calls.waiting);
                var other = dict_string (calls.waiting, "name");
                waiting_name.label = other;
                waiting_avatar.show_person (other, dict_string (calls.waiting, "avatar"));
                hold_answer.sensitive = calls.can ("hold-and-answer");
                end_answer.sensitive = calls.can ("release-and-answer");
                announce_text (_("Double appel : %s").printf (other));
            } else {
                waiting_path = null;
            }
            held_revealer.reveal_child = calls.held != null;
            if (calls.held != null) {
                held_name.label = dict_string (calls.held, "name");
                held_swap.sensitive = calls.can ("swap");
            }
            // The held call's row already offers Permuter.
            swap_option.visible = calls.can ("swap") && calls.held == null;
            merge_option.visible = calls.can ("merge");
            resume_option.visible = calls.can ("resume");

            var dur = main.lookup_value ("duration", VariantType.INT32);
            string spoken;
            switch (state) {
                case "incoming":
                case "waiting":
                    duration = -1;
                    status_label.label = _("Appel entrant");
                    spoken = _("Appel entrant : %s").printf (name);
                    actions.visible_child_name = "ringing";
                    answer.sensitive = calls.can ("answer");
                    break;
                case "dialing":
                case "alerting":
                    duration = -1;
                    status_label.label = _("Appel en cours de numérotation…");
                    spoken = _("Appel de %s en cours de numérotation").printf (name);
                    actions.visible_child_name = "call";
                    break;
                case "held":
                    duration = -1;
                    status_label.label = _("En attente");
                    spoken = _("%s en attente").printf (name);
                    actions.visible_child_name = "call";
                    break;
                default:
                    duration = dur != null ? int.max (dur.get_int32 (), 0) : 0;
                    status_label.label = running_status ();
                    spoken = calls.conference.length > 0 ? _("Conférence en cours")
                                                         : _("En communication avec %s").printf (name);
                    actions.visible_child_name = "call";
                    break;
            }
            if (calls.waiting == null) {
                announce_text (spoken);
            }
            mute.sensitive = state != "incoming" && state != "waiting";
            hangup.tooltip_markup = Granite.markup_accel_tooltip (
                { "<Control><Shift>r" },
                calls.conference.length > 0 ? _("Raccrocher tous les appels de la conférence")
                : calls.held != null ? _("Raccrocher ; l'appel en attente reprend")
                : _("Raccrocher"));
        }
    }
}

namespace Boomerang {
    /*
     * Green bar at the top of Boomerang's windows while a call is going on: who,
     * how long, and the everyday controls (mute, audio on this PC, keypad in the
     * call window, hang up; answer or decline while it rings; with a second call
     * ringing during the call, answer puts the first one on hold).
     */
    public class CallBar : Gtk.Box {
        public Daemon daemon { get; construct; }

        private Gtk.Revealer revealer;
        private Avatar avatar;
        private Gtk.Label name_label;
        private Gtk.Label status_label;
        private Gtk.ToggleButton mute;
        private Gtk.ToggleButton audio;
        private Gtk.Button answer;
        private Gtk.Button hangup;
        private string? path = null;
        private string answer_action = "answer";
        private string hangup_action = "hangup";
        private string status_prefix = "";
        private int duration = -1;
        private uint tick = 0;  // the call clock, only while a call is active
        private bool updating = false;
        private bool loaded = false;

        public CallBar (Daemon daemon) {
            Object (daemon: daemon, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        }

        construct {
            avatar = new Avatar (32);
            name_label = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            name_label.add_css_class ("call-bar-name");
            status_label = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            status_label.add_css_class ("numeric");
            status_label.add_css_class (Granite.CssClass.SMALL);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
            text.append (name_label);
            text.append (status_label);

            mute = new Gtk.ToggleButton () { icon_name = "microphone-sensitivity-muted-symbolic",
                                             tooltip_text = _("Couper le micro") };
            mute.toggled.connect (() => {
                if (!updating) {
                    daemon.call.begin ("SetMuted", new Variant ("(b)", mute.active));
                }
            });
            audio = new Gtk.ToggleButton () { icon_name = "audio-speakers-symbolic",
                                              tooltip_text = _("Son sur ce PC (sinon sur l'iPhone)") };
            audio.toggled.connect (() => {
                if (!updating) {
                    daemon.call_send.begin ("SetCallAudio", new Variant ("(b)", audio.active));
                }
            });
            var show = new Gtk.Button.from_icon_name ("input-dialpad-symbolic") {
                tooltip_text = _("Afficher l'appel et le clavier")
            };
            show.clicked.connect (() => {
                var app = GLib.Application.get_default ();
                if (app != null) {
                    app.activate_action ("show-call", null);
                }
            });
            answer = new Gtk.Button.from_icon_name ("call-start-symbolic") { tooltip_text = C_("call", "Répondre") };
            answer.add_css_class ("call-green-small");
            answer.clicked.connect (() => act (answer_action));
            hangup = new Gtk.Button.from_icon_name ("call-stop-symbolic") { tooltip_text = _("Raccrocher") };
            hangup.add_css_class ("call-red-small");
            hangup.clicked.connect (() => act (hangup_action));
            foreach (var b in new Gtk.Widget[] { mute, audio, show, answer, hangup }) {
                b.add_css_class ("circular");
                b.valign = Gtk.Align.CENTER;
                b.update_property (Gtk.AccessibleProperty.LABEL, b.tooltip_text, -1);
            }

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 12,
                margin_end = 12
            };
            box.add_css_class ("call-bar-content");
            box.append (avatar);
            box.append (text);
            box.append (mute);
            box.append (audio);
            box.append (show);
            box.append (answer);
            box.append (hangup);
            var bar = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            bar.add_css_class ("call-bar");
            bar.append (box);
            revealer = new Gtk.Revealer () { child = bar, reveal_child = false };
            append (revealer);

            daemon.active_calls_changed.connect (() => reload.begin ());
            daemon.changed.connect (() => {
                if (!daemon.touched ({ "MicMuted", "AudioOnPC" })) {
                    return;
                }
                // First contact with the daemon: a call may already be going on.
                if (!loaded && daemon.running) {
                    loaded = true;
                    reload.begin ();
                }
                updating = true;
                mute.active = daemon.get_bool ("MicMuted");
                audio.active = daemon.get_bool ("AudioOnPC");
                updating = false;
            });
            map.connect (() => reload.begin ());
        }

        private void act (string action) {
            if (path != null) {
                daemon.call_send.begin ("CallAction", new Variant ("(os)", path, action));
            }
        }

        private void set_tip (Gtk.Widget button, string tip) {
            button.tooltip_text = tip;
            button.update_property (Gtk.AccessibleProperty.LABEL, tip, -1);
        }

        private async void reload () {
            var calls = new CallSet (yield daemon.call_list ("ListActiveCalls"));
            var chosen = calls.main;
            revealer.reveal_child = chosen != null;
            if (chosen == null) {
                path = null;
                duration = -1;
                return;
            }
            path = CallSet.path_of (chosen);
            var conference = calls.conference.length > 0;
            var name = conference ? _("Conférence") : dict_string (chosen, "name");
            name_label.label = name;
            avatar.show_person (name, conference ? "" : dict_string (chosen, "avatar"), conference);
            var state = dict_string (chosen, "state");
            var ringing = state == "incoming" || state == "waiting";
            var second = calls.waiting != null && calls.can ("hold-and-answer");
            answer.visible = (ringing && calls.can ("answer")) || second;
            answer_action = second ? "hold-and-answer" : "answer";
            set_tip (answer, second ? _("Mettre en attente et répondre") : C_("call", "Répondre"));
            mute.visible = !ringing;
            audio.visible = !ringing;
            hangup_action = conference && calls.can ("hangup-all") ? "hangup-all" : "hangup";
            set_tip (hangup, ringing ? _("Refuser") : _("Raccrocher"));
            status_prefix = second ? _("Double appel : %s").printf (dict_string (calls.waiting, "name"))
                          : calls.held != null ? _("%s en attente").printf (dict_string (calls.held, "name"))
                          : conference ? string.joinv (", ", calls.conference)
                          : "";
            if (state == "active") {
                var dur = chosen.lookup_value ("duration", VariantType.INT32);
                duration = dur != null ? int.max (dur.get_int32 (), 0) : 0;
                status_label.label = running_status ();
                if (tick == 0) {
                    tick = Timeout.add_seconds (1, () => {
                        if (duration < 0) {
                            tick = 0;
                            return Source.REMOVE;
                        }
                        duration++;
                        status_label.label = running_status ();
                        return Source.CONTINUE;
                    });
                }
            } else {
                duration = -1;
                status_label.label = ringing ? _("Appel entrant")
                                   : state == "held" ? _("En attente") : _("Appel sortant…");
            }
        }

        private string running_status () {
            var clock = _("En cours · %s").printf (call_clock (duration));
            return status_prefix != "" ? "%s · %s".printf (clock, status_prefix) : clock;
        }
    }
}
