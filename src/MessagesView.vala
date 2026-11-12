// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Personnes: one line per person on the left (the conversation, the latest call and the
 * contact card together), the person's thread in the middle: bubbles, and the calls as
 * pills at their place in time; the person's card on the right (ConversationDetails).
 * Sent bubbles on the right, received on the left, the sender's name above received
 * bubbles in group threads, and a reply field when the iPhone lets the PC send,
 * otherwise a line explaining why not.
 */

namespace Boomerang {
    private string dict_string (VariantDict d, string key) {
        var v = d.lookup_value (key, VariantType.STRING);
        return v != null ? v.get_string () : "";
    }

    private bool dict_bool (VariantDict d, string key) {
        var v = d.lookup_value (key, VariantType.BOOLEAN);
        return v != null && v.get_boolean ();
    }

    private int64 dict_int64 (VariantDict d, string key) {
        var v = d.lookup_value (key, VariantType.INT64);
        return v != null ? v.get_int64 () : 0;
    }

    private uint dict_uint (VariantDict d, string key) {
        var v = d.lookup_value (key, VariantType.UINT32);
        return v != null ? v.get_uint32 () : 0;
    }

    /* "14:05" today, "Hier", the weekday within a week, else the date. */
    public string short_time (int64 stamp) {
        var when = new DateTime.from_unix_local (stamp);
        var now = new DateTime.now_local ();
        var today = new DateTime.local (now.get_year (), now.get_month (), now.get_day_of_month (), 0, 0, 0);
        if (when.compare (today) >= 0) {
            return when.format ("%H:%M");
        }
        if (when.compare (today.add_days (-1)) >= 0) {
            return _("Hier");
        }
        if (when.compare (today.add_days (-6)) >= 0) {
            return when.format ("%A");
        }
        return when.format ("%d/%m/%Y");
    }

    public string long_time (int64 stamp) {
        var when = new DateTime.from_unix_local (stamp);
        var label = short_time (stamp);
        return label.contains (":") ? _("Aujourd'hui %s").printf (label)
                                    : "%s %s".printf (label, when.format ("%H:%M"));
    }

    /* Escaped text with web links, e-mail addresses and phone numbers made clickable. */
    public string linkify (string text) {
        try {
            var re = new Regex (
                "(https?://[^\\s<>\"]+[^\\s<>\".,;:!?)\\]]|www\\.[^\\s<>\"]+[^\\s<>\".,;:!?)\\]]"
                + "|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
                + "|\\+?[0-9][0-9 .-]{7,}[0-9])");
            var result = new StringBuilder ();
            MatchInfo info;
            int last = 0;
            re.match (text, 0, out info);
            while (info.matches ()) {
                int start, end;
                info.fetch_pos (0, out start, out end);
                var found = info.fetch (0);
                result.append (Markup.escape_text (text.substring (last, start - last)));
                string uri;
                if (found.contains ("@") && !found.has_prefix ("http")) {
                    uri = "mailto:" + found;
                } else if (found.has_prefix ("http")) {
                    uri = found;
                } else if (found.has_prefix ("www.")) {
                    uri = "https://" + found;
                } else {
                    var digits = only_digits (found);
                    if (digits.length < 9 || digits.length > 15) {
                        result.append (Markup.escape_text (found));
                        last = end;
                        info.next ();
                        continue;
                    }
                    uri = "tel:" + (found.has_prefix ("+") ? "+" : "") + digits;
                }
                result.append ("<a href=\"%s\">%s</a>".printf (Markup.escape_text (uri),
                                                                Markup.escape_text (found)));
                last = end;
                info.next ();
            }
            result.append (Markup.escape_text (text.substring (last)));
            return result.str;
        } catch (Error e) {
            return Markup.escape_text (text);
        }
    }

    public class ThreadRow : Gtk.ListBoxRow {
        public string thread_id { get; private set; }
        public bool can_send { get; private set; }
        public bool is_group { get; private set; }
        public string title { get; private set; }
        public uint unread { get; private set; }
        public string draft { get; set; default = ""; }
        public string number { get; private set; default = ""; }
        public bool pinned { get; private set; }
        public bool marked_unread { get; private set; }
        public bool known { get; private set; default = true; }  // a participant is in the contacts

        private Gtk.Label name_label;
        private Gtk.Image pin;
        private Gtk.Label snippet_label;
        private Gtk.Box dot;
        private Avatar avatar;
        public string avatar_path { get; private set; default = ""; }

        public ThreadRow () {
            name_label = new Gtk.Label ("") {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END
            };
            name_label.add_css_class ("person-name");
            snippet_label = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            snippet_label.add_css_class (Granite.CssClass.DIM);

            dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.CENTER
            };
            dot.add_css_class ("unread-dot");
            var dot_slot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { width_request = 12 };
            dot_slot.append (dot);

            avatar = new Avatar (44);

            pin = new Gtk.Image.from_icon_name ("starred-symbolic") {
                pixel_size = 12,
                visible = false,
                tooltip_text = _("Favori")
            };
            pin.add_css_class (Granite.CssClass.DIM);
            var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            top.append (name_label);
            top.append (pin);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
            text.append (top);
            text.append (snippet_label);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 0,
                margin_end = 10
            };
            box.append (dot_slot);
            box.append (avatar);
            box.append (text);
            child = box;
        }

        public void set_from (VariantDict d) {
            thread_id = dict_string (d, "id");
            can_send = dict_bool (d, "can_send");
            is_group = dict_bool (d, "group");
            title = dict_string (d, "name");
            unread = dict_uint (d, "unread");
            pinned = dict_bool (d, "pinned");
            marked_unread = dict_bool (d, "marked_unread");
            var is_known = d.lookup_value ("known", VariantType.BOOLEAN);
            known = is_known == null || is_known.get_boolean ();  // (older daemon: not told)
            pin.visible = pinned;
            refresh_name ();
            avatar_path = dict_string (d, "avatar");
            refresh_avatar ();
            var snippet = dict_string (d, "snippet").replace ("\n", " ");
            draft = dict_string (d, "draft");
            number = number_of (d);
            var call = dict_string (d, "call_kind");  // the person's latest call, newer than the messages
            snippet_label.remove_css_class ("event-missed");
            if (call != "" && draft == "") {
                var length = d.lookup_value ("call_duration", VariantType.INT32);
                snippet_label.use_markup = false;
                snippet_label.label = call_summary (call, length != null ? length.get_int32 () : -1,
                                                    dict_int64 (d, "time"), false);
                if (call == "missed") {
                    snippet_label.add_css_class ("event-missed");
                }
            } else if (draft != "") {
                snippet_label.use_markup = true;
                snippet_label.label = _("<i>Brouillon :</i> ") + Markup.escape_text (draft.replace ("\n", " "));
            } else {
                snippet_label.use_markup = false;
                snippet_label.label = dict_bool (d, "outgoing") ? _("Vous : %s").printf (snippet) : snippet;
            }
            dot.visible = unread > 0;
            if (unread > 0) {
                name_label.add_css_class ("unread");
            } else {
                name_label.remove_css_class ("unread");
            }
            var a11y = unread > 0 ? ngettext ("%s, %u non lu", "%s, %u non lus", unread).printf (title, unread) : title;
            update_property (Gtk.AccessibleProperty.LABEL, "%s, %s".printf (a11y, snippet_label.get_text ()), -1);
        }

        /* The one phone number of a conversation with one person, else "". */
        public static string number_of (VariantDict d) {
            var people = d.lookup_value ("participants", new VariantType ("as"));
            var list = people != null ? people.dup_strv () : new string[0];
            return list.length == 1 && !list[0].contains ("@") && !list[0].has_prefix ("name:") ? list[0] : "";
        }

        /* The nickname and emoji chosen in Personnaliser, else the contact's name. */
        public void refresh_name () {
            name_label.label = ThreadStyle.load (thread_id).shown_name (title);
            refresh_avatar ();
        }

        private void refresh_avatar () {
            avatar.show_person (title, ThreadStyle.load (thread_id).picture (avatar_path), is_group);
        }
    }

    /* One search result: a conversation whose name matches, or a message with its excerpt. */
    public class SearchRow : Gtk.ListBoxRow {
        public string thread_id { get; private set; }
        public string message { get; private set; }
        public string title { get; private set; }
        public string address { get; private set; }  // a contact with no conversation yet
        private string avatar_path;
        private bool is_group;

        public SearchRow (VariantDict d) {
            thread_id = dict_string (d, "thread");
            address = dict_string (d, "address");
            message = dict_string (d, "message");
            title = dict_string (d, "name");
            avatar_path = dict_string (d, "avatar");
            is_group = dict_bool (d, "group");
            var marked = Markup.escape_text (dict_string (d, "before"))
                         + "<b>" + Markup.escape_text (dict_string (d, "match")) + "</b>"
                         + Markup.escape_text (dict_string (d, "after"));
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 6,
                margin_end = 12
            };
            if (message == "") {
                // The conversation itself: its name, the matching part in bold.
                var face = new Avatar (32);
                face.show_person (title, avatar_path, is_group);
                box.append (face);
                var name = new Gtk.Label (marked) {
                    use_markup = true,
                    xalign = 0,
                    hexpand = true,
                    ellipsize = Pango.EllipsizeMode.END
                };
                box.append (name);
                update_property (Gtk.AccessibleProperty.LABEL,
                                 thread_id == "" ? title : _("Conversation avec %s").printf (title), -1);
            } else {
                var text = dict_bool (d, "outgoing") ? _("Vous : %s").printf (marked) : marked;
                var excerpt = new Gtk.Label (text) {
                    use_markup = true,
                    xalign = 0,
                    hexpand = true,
                    wrap = true,
                    wrap_mode = Pango.WrapMode.WORD_CHAR,
                    lines = 3,
                    ellipsize = Pango.EllipsizeMode.END,
                    max_width_chars = 30,
                    margin_start = 6
                };
                var time = new Gtk.Label (short_time (dict_int64 (d, "time"))) { valign = Gtk.Align.START };
                time.add_css_class (Granite.CssClass.DIM);
                time.add_css_class (Granite.CssClass.SMALL);
                box.append (excerpt);
                box.append (time);
                update_property (Gtk.AccessibleProperty.LABEL,
                                 "%s : %s".printf (title, dict_string (d, "before") + dict_string (d, "match")
                                                   + dict_string (d, "after")), -1);
            }
            child = box;
        }

        /* Above the first message found in a conversation: who it is with. */
        public Gtk.Widget group_header () {
            var face = new Avatar (24);
            face.show_person (title, avatar_path, is_group);
            var name = new Gtk.Label (title) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            name.add_css_class ("heading");
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 8,
                margin_start = 12,
                margin_end = 12
            };
            box.append (face);
            box.append (name);
            return box;
        }
    }

    public delegate void VoidFunc ();

    /* The « Ne plus m'avertir » choices of Messages, read once from apps.conf and read again
       only when the file changes (they used to be parsed at every delete or reaction). */
    private class MessagesPrefs {
        private static HashTable<string, bool>? cache = null;
        private static FileMonitor? monitor = null;

        public static bool warns (string key) {
            if (cache == null) {
                cache = new HashTable<string, bool> (str_hash, str_equal);
                follow_file ();
            }
            if (!cache.contains (key)) {
                var prefs = new KeyFile ();
                bool value = true;
                try {
                    prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
                    value = prefs.get_boolean ("messages", key);
                } catch (Error e) {
                    // never chosen: warn
                }
                cache[key] = value;
            }
            return cache[key];
        }

        /* Written at once; other parts of Boomerang share the file, so it is read fresh first. */
        public static void stop_warning (string key) {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.KEEP_COMMENTS);
            } catch (Error e) {
                // first choice
            }
            prefs.set_boolean ("messages", key, false);
            try {
                DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
                prefs.save_to_file (Setup.prefs_path ());
            } catch (Error e) {
                warning ("cannot save the choice %s: %s", key, e.message);
            }
            warns (key);
            cache[key] = false;
        }

        private static void follow_file () {
            try {
                monitor = File.new_for_path (Setup.prefs_path ()).monitor_file (FileMonitorFlags.NONE);
                monitor.changed.connect (() => cache.remove_all ());
            } catch (Error e) {
                // no monitor: the choices are read once per run
            }
        }
    }

    public class MessagesView : Gtk.Box {
        public Daemon daemon { get; construct; }

        private Gtk.ListBox thread_list;
        private int list_filter = 0;           // 0 all, 1 unread, 2 senders outside the contacts
        private Gtk.Label filter_empty;
        private Gtk.Stack list_stack;
        private Gtk.Box banner;
        private Gtk.Label banner_label;
        private Gtk.Button banner_button;
        private Gtk.Stack content_stack;
        private Avatar thread_avatar;
        private Gtk.Box thread_call;
        private Gtk.Label thread_title;
        private Gtk.Label thread_subtitle;
        private Gtk.ProgressBar send_bar;
        private uint send_bar_hide = 0;
        private Gtk.Box bubbles;
        private Gtk.ScrolledWindow bubble_scroll;
        private Gtk.Stack compose_stack;
        private ComposeField entry;
        private bool stick_bottom = true;
        private double seen_upper = 0;     // layout size the last scroll position was judged against
        private double seen_page = 0;
        private uint stick_source = 0;
        private Gtk.ToggleButton details_button;
        private Gtk.Revealer details_panel;
        private Gtk.ScrolledWindow details_scroll;
        private Gtk.CssProvider style_css = new Gtk.CssProvider ();
        private string? applied_css = null;
        private Gtk.HeaderBar thread_bar;
        private Gtk.Box sidebar;
        private Variant[] calls = {};          // ListCalls, newest first
        private Gtk.Box call_tail;             // calls newer than the last message
        private bool details_wide = true;      // the window has room for the card on the right
        private Gtk.Box thread_title_box;
        private Gtk.SearchBar find_bar;
        private Gtk.SearchEntry find_entry;
        private Gtk.Label find_count;
        private string[] find_hits = {};
        private int find_index = -1;
        private string[] thread_ids = {};      // messages of the open thread, for the in-thread search
        private string[] thread_bodies = {};
        private Gtk.Button down_button;
        private Gtk.Label down_count;
        private uint unseen = 0;               // arrived while the user reads older messages
        private string last_id = "";           // newest message shown, for the ↓ count
        private const uint PAGE = 120;         // messages read at a time (GetMessagesPage)
        private Variant[] shown_items = {};    // the messages on screen, oldest first
        private bool more_older = false;       // the daemon has older ones than those shown
        private bool loading_older = false;
        private uint load_serial = 0;
        private string older_for = "";         // message searched for in older pages
        private uint older_tries = 0;
        private double keep_from_bottom = -1;  // older bubbles added above: hold the view
        private Gtk.Button older_button;
        private Gtk.Box bubble_column;
        private uint unread_mark = 0;          // unread when the thread was opened: "Non lus" line
        private string unread_id = "";         // the message the line goes above, once found
        private uint next_unread = 0;
        private bool pending_flash = true;
        private HashTable<string, Variant> previews = new HashTable<string, Variant> (str_hash, str_equal);
        private Gtk.Label send_hint;
        private Gtk.Label limit_label;
        private Granite.Toast toast;

        private string? current = null;
        private string rendered = "";           // thread, group and unread line of the bubbles shown
        private string[] rendered_items = {};   // one signature per message shown
        private Gtk.Widget[] item_starts = {};  // first widget of each (unread line, time, bubble)
        private string current_title = "";
        private bool current_group = false;
        private bool current_can_send = false;
        private bool current_new = false;
        private string current_avatar = "";
        private string current_number = "";  // opened from "new message", no message yet
        private Gtk.MenuButton new_button;
        private Gtk.MenuButton filter_menu;
        private Gtk.SearchEntry search;
        private Gtk.ListBox search_list;
        private Gtk.Label search_empty;
        private uint search_serial = 0;
        private string? pending_scroll = null;  // message to show once its thread is laid out
        private HashTable<string, Gtk.Widget> bubble_index =
            new HashTable<string, Gtk.Widget> (str_hash, str_equal);
        private uint draft_timer = 0;
        private bool loading_draft = false;
        private ContactList picker;
        private string? pending_open = null;
        private bool pending_reply = false;
        private bool loading_threads = false;
        private bool threads_loaded = false;  // the list came from the daemon at least once
        private bool reload_again = false;

        public MessagesView (Daemon daemon) {
            Object (daemon: daemon, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        }

        construct {
            // --- conversation list ---
            thread_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.SINGLE };
            thread_list.add_css_class ("navigation-sidebar");
            thread_list.set_header_func ((row, before) => {
                var here = row as ThreadRow;
                var above = before as ThreadRow;
                if (here != null && here.pinned && above == null) {
                    var label = new Gtk.Label (_("Favoris")) {
                        xalign = 0,
                        margin_start = 12,
                        margin_top = 6,
                        margin_bottom = 2
                    };
                    label.add_css_class (Granite.CssClass.DIM);
                    label.add_css_class (Granite.CssClass.SMALL);
                    row.set_header (label);
                } else if (here != null && !here.pinned && above != null && above.pinned) {
                    row.set_header (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) {
                        margin_top = 3,
                        margin_bottom = 3
                    });
                } else {
                    row.set_header (null);
                }
            });
            // One right-click gesture and one Menu key handler for every row (a gesture per row
            // held its row in a closure: a cycle never freed).
            var thread_click = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
            thread_click.pressed.connect (on_thread_list_pressed);
            thread_list.add_controller (thread_click);
            var thread_keys = new Gtk.EventControllerKey ();
            thread_keys.key_pressed.connect (on_thread_list_key);
            thread_list.add_controller (thread_keys);
            thread_list.set_filter_func (keep_row);
            filter_empty = new Gtk.Label ("") {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                margin_top = 24,
                margin_start = 12,
                margin_end = 12
            };
            filter_empty.add_css_class (Granite.CssClass.DIM);
            thread_list.set_placeholder (filter_empty);
            thread_list.row_selected.connect ((row) => {
                var thread = row as ThreadRow;
                if (thread != null && thread.thread_id == "" && current_new
                    && number_tail (thread.number) == number_tail (current_number)) {
                    return;  // the person with calls only, already open
                }
                if (thread != null && (thread.thread_id != current || current_new)) {
                    show_thread (thread);
                }
            });
            var list_scroll = new Gtk.ScrolledWindow () {
                child = thread_list,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            var list_empty = new Granite.Placeholder (_("Personne pour l'instant")) {
                description = _("Les messages et les appels de l'iPhone apparaîtront ici."),
                icon = new ThemedIcon (Config.APP_ID + ".Messages")
            };
            list_stack = new Gtk.Stack ();
            list_stack.add_named (list_scroll, "list");
            list_stack.add_named (list_empty, "empty");

            banner_label = new Gtk.Label ("") {
                wrap = true,
                xalign = 0,
                max_width_chars = 30
            };
            banner_label.add_css_class (Granite.CssClass.SMALL);
            banner_button = new Gtk.Button.with_label (_("Réessayer")) { halign = Gtk.Align.START };
            banner_button.add_css_class (Granite.CssClass.SMALL);
            banner_button.clicked.connect (() => daemon.call.begin ("SyncMessages"));
            banner = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 12,
                margin_end = 12
            };
            banner.add_css_class ("messages-banner");
            banner.append (banner_label);
            banner.append (banner_button);

            // New message: pick a contact of the iPhone or type a number.
            picker = new ContactList (daemon, true) {
                width_request = 320,
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 6,
                margin_end = 6
            };
            var picker_popover = new Gtk.Popover () { child = picker };
            picker_popover.show.connect (() => {
                picker.search.text = "";
                picker.reload.begin ();
                picker.search.grab_focus ();
            });
            picker.contact_selected.connect ((contact) => {
                picker_popover.popdown ();
                string? phone = null;
                foreach (var a in contact.addresses) {
                    if (contact.is_phone (a)) {
                        phone = a;
                        break;
                    }
                }
                start_conversation (phone ?? contact.addresses[0]);
            });
            picker.address_chosen.connect ((address) => {
                picker_popover.popdown ();
                start_conversation (address);
            });
            new_button = new Gtk.MenuButton () {
                icon_name = "mail-message-new-symbolic",
                popover = picker_popover,
                tooltip_text = _("Nouveau message"),
                halign = Gtk.Align.END
            };
            new_button.add_css_class ("flat");
            search = new Gtk.SearchEntry () {
                placeholder_text = _("Nom, numéro ou mot"),
                hexpand = true
            };
            search.update_property (Gtk.AccessibleProperty.LABEL, _("Rechercher une personne"), -1);
            search.search_changed.connect (() => run_search.begin ());
            search.stop_search.connect (() => {
                search.text = "";
            });
            search.activate.connect (() => {
                var first = search_list.get_row_at_index (0) as SearchRow;
                if (first != null) {
                    open_search_hit (first);
                }
            });

            // Search results: conversations whose name matches, then messages by conversation.
            search_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
            search_list.add_css_class ("navigation-sidebar");
            search_list.row_activated.connect ((row) => open_search_hit ((SearchRow) row));
            search_list.set_header_func ((row, before) => {
                var here = (SearchRow) row;
                var above = before as SearchRow;
                if (here.message != "" && (above == null || above.thread_id != here.thread_id
                                           || above.message == "")) {
                    row.set_header (here.group_header ());
                } else {
                    row.set_header (null);
                }
            });
            var search_scroll = new Gtk.ScrolledWindow () {
                child = search_list,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            search_empty = new Gtk.Label ("") {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                margin_top = 24,
                margin_start = 12,
                margin_end = 12,
                valign = Gtk.Align.START
            };
            search_empty.add_css_class (Granite.CssClass.DIM);
            list_stack.add_named (search_scroll, "search");
            list_stack.add_named (search_empty, "search-empty");

            // Ctrl+F: in the open conversation, Ctrl+Maj+F: every conversation,
            // Alt+↑/↓: previous/next conversation, Ctrl+N: new message.
            var shortcuts = new Gtk.ShortcutController () { scope = Gtk.ShortcutScope.MANAGED };
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Control>f"),
                new Gtk.CallbackAction (() => {
                    if (!get_mapped ()) {
                        return false;
                    }
                    if (current != null && content_stack.visible_child_name == "thread") {
                        find_bar.search_mode_enabled = true;
                        find_entry.grab_focus ();
                        find_entry.select_region (0, -1);
                    } else {
                        search.grab_focus ();
                        search.select_region (0, -1);
                    }
                    return true;
                })));
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Control><Shift>f"),
                new Gtk.CallbackAction (() => {
                    if (!get_mapped ()) {
                        return false;
                    }
                    search.grab_focus ();
                    search.select_region (0, -1);
                    return true;
                })));
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Control>r"),
                new Gtk.CallbackAction (() => {
                    if (!get_mapped ()) {
                        return false;
                    }
                    run_sync.begin ();
                    return true;
                })));
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Alt>Up"),
                new Gtk.CallbackAction (() => get_mapped () && step_thread (-1))));
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Alt>Down"),
                new Gtk.CallbackAction (() => get_mapped () && step_thread (1))));
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Control>n"),
                new Gtk.CallbackAction (() => {
                    if (!get_mapped ()) {
                        return false;
                    }
                    new_button.popup ();
                    return true;
                })));
            // As in Messages on the Mac: Ctrl+Tab and Ctrl+↓/↑ through the conversations, Ctrl+I
            // details, Ctrl+Suppr delete (always confirmed), Échap closes, Ctrl+? lists them all.
            foreach (var trigger in new string[] { "<Control>Tab", "<Control>Down", "<Control>Page_Down" }) {
                shortcuts.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string (trigger),
                                                          new Gtk.CallbackAction (next_thread_shortcut)));
            }
            foreach (var trigger in new string[] { "<Control><Shift>Tab", "<Control><Shift>ISO_Left_Tab",
                                                   "<Control>Up", "<Control>Page_Up" }) {
                shortcuts.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string (trigger),
                                                          new Gtk.CallbackAction (previous_thread_shortcut)));
            }
            shortcuts.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("<Control>i"),
                                                      new Gtk.CallbackAction (details_shortcut)));
            shortcuts.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("<Control>Delete"),
                                                      new Gtk.CallbackAction (delete_shortcut)));
            shortcuts.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("Escape"),
                                                      new Gtk.CallbackAction (escape_shortcut)));
            shortcuts.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("<Control>question"),
                                                      new Gtk.CallbackAction (help_shortcut)));
            add_controller (shortcuts);

            var search_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3) {
                margin_top = 6,
                margin_start = 12,
                margin_end = 6,
                margin_bottom = 6
            };
            search_row.append (search);
            search_row.append (filter_button ());
            search_row.append (new_button);
            sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 280 };
            sidebar.add_css_class ("people-sidebar");
            sidebar.append (search_row);
            sidebar.add_css_class ("messages-sidebar");
            sidebar.append (banner);
            sidebar.append (list_stack);

            // --- thread ---
            thread_title = new Gtk.Label ("") { ellipsize = Pango.EllipsizeMode.END };
            thread_title.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
            thread_subtitle = new Gtk.Label ("") { ellipsize = Pango.EllipsizeMode.END };
            thread_subtitle.add_css_class (Granite.CssClass.DIM);
            thread_subtitle.add_css_class (Granite.CssClass.SMALL);
            // The person's header: the name over a discreet line, Appeler at the end.
            thread_avatar = new Avatar (24) { visible = false };  // the card on the right shows it big
            var titles = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
            thread_title.xalign = 0;
            thread_subtitle.xalign = 0;
            titles.append (thread_title);
            titles.append (thread_subtitle);
            thread_title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            thread_title_box.append (thread_avatar);
            thread_title_box.append (titles);
            // As on the iPhone: the name opens the conversation's details.
            var title_button = new Gtk.Button () {
                child = thread_title_box,
                tooltip_text = _("Fiche de la personne"),
                visible = false
            };
            title_button.add_css_class ("flat");
            title_button.add_css_class ("thread-title");
            title_button.clicked.connect (() => details_button.active = !details_button.active);
            thread_call = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
            thread_bar = new Gtk.HeaderBar () {
                visible = false,  // once a person is open
                show_title_buttons = false,
                title_widget = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0)
            };
            thread_bar.pack_start (title_button);
            thread_bar.add_css_class ("flat");
            thread_bar.add_css_class ("thread-bar");

            bubbles = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 12,
                margin_end = 12,
                valign = Gtk.Align.END
            };
            // Above the bubbles while older messages remain (also read on scrolling up).
            older_button = new Gtk.Button.with_label (_("Afficher les messages plus anciens")) {
                halign = Gtk.Align.CENTER,
                margin_top = 12,
                visible = false
            };
            older_button.add_css_class ("flat");
            older_button.add_css_class (Granite.CssClass.SMALL);
            older_button.clicked.connect (on_older_clicked);
            bubble_column = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.END };
            bubble_column.append (older_button);
            bubble_column.append (bubbles);
            call_tail = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { margin_start = 12, margin_end = 12, margin_bottom = 12 };
            bubble_column.append (call_tail);
            bubble_scroll = new Gtk.ScrolledWindow () {
                child = bubble_column,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            bubble_scroll.add_css_class ("thread-scroll");
            install_bubble_menu ();

            // Back to the newest message, with how many arrived meanwhile.
            down_count = new Gtk.Label ("") { visible = false };
            down_count.add_css_class ("down-count");
            var down_inner = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            down_inner.append (new Gtk.Image.from_icon_name ("go-down-symbolic"));
            down_inner.append (down_count);
            down_button = new Gtk.Button () {
                child = down_inner,
                halign = Gtk.Align.END,
                valign = Gtk.Align.END,
                margin_end = 18,
                margin_bottom = 12,
                visible = false,
                tooltip_text = _("Aller au dernier message")
            };
            down_button.add_css_class ("scroll-down");
            down_button.clicked.connect (() => {
                stick_bottom = true;
                unseen = 0;
                queue_stick ();
                update_down ();
            });
            var scroll_overlay = new Gtk.Overlay () { child = bubble_scroll, vexpand = true };
            scroll_overlay.add_overlay (down_button);

            // Search in the open conversation (Ctrl+F).
            find_entry = new Gtk.SearchEntry () {
                placeholder_text = _("Rechercher dans la conversation"),
                hexpand = true
            };
            find_count = new Gtk.Label ("") { width_chars = 10 };
            find_count.add_css_class (Granite.CssClass.DIM);
            find_count.add_css_class (Granite.CssClass.SMALL);
            var older = new Gtk.Button.from_icon_name ("go-up-symbolic") { tooltip_text = _("Plus ancien (Entrée)") };
            var newer = new Gtk.Button.from_icon_name ("go-down-symbolic") { tooltip_text = _("Plus récent (Maj+Entrée)") };
            older.clicked.connect (() => find_step (-1));
            newer.clicked.connect (() => find_step (1));
            var steps = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            steps.add_css_class ("linked");
            steps.append (older);
            steps.append (newer);
            var find_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { width_request = 380 };
            find_box.append (find_entry);
            find_box.append (find_count);
            find_box.append (steps);
            find_bar = new Gtk.SearchBar () { child = find_box, show_close_button = true };
            find_bar.connect_entry (find_entry);
            find_entry.search_changed.connect (find_run);
            find_entry.activate.connect (() => find_step (-1));
            var find_keys = new Gtk.EventControllerKey ();
            find_keys.key_pressed.connect ((keyval, code, state) => {
                if ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter)
                    && (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    find_step (1);
                    return true;
                }
                return false;
            });
            find_entry.add_controller (find_keys);
            find_bar.notify["search-mode-enabled"].connect (() => {
                if (!find_bar.search_mode_enabled) {
                    find_clear ();
                }
            });

            entry = new ComposeField ();
            entry.submitted.connect (send);
            entry.buffer.changed.connect (() => {
                if (loading_draft || current == null) {
                    return;
                }
                if (draft_timer != 0) {
                    Source.remove (draft_timer);
                }
                draft_timer = Timeout.add (700, () => {
                    draft_timer = 0;
                    save_draft ();
                    return Source.REMOVE;
                });
            });
            var compose_row = entry;
            send_hint = new Gtk.Label (
                _("Premier envoi depuis ce PC : cet envoi indique à Boomerang si l'iPhone accepte "
                + "l'envoi par Bluetooth. Boomerang demande un envoi en SMS, pas en iMessage.")
            ) { wrap = true, xalign = 0 };
            send_hint.add_css_class (Granite.CssClass.DIM);
            send_hint.add_css_class (Granite.CssClass.SMALL);
            var compose = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            compose.append (compose_row);
            compose.append (send_hint);

            limit_label = new Gtk.Label ("") { wrap = true, xalign = 0.5f, justify = Gtk.Justification.CENTER };
            limit_label.add_css_class (Granite.CssClass.DIM);
            limit_label.add_css_class (Granite.CssClass.SMALL);

            compose_stack = new Gtk.Stack () {
                margin_top = 8,
                margin_bottom = 12,
                margin_start = 12,
                margin_end = 12,
                vhomogeneous = false
            };
            compose_stack.add_named (compose, "compose");
            compose_stack.add_named (limit_label, "limit");

            var thread_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            thread_box.add_css_class ("thread-styled");
            // Dropped on the conversation: text goes into the reply field, a file to LocalSend.
            var drop = new Gtk.DropTarget (GLib.Type.INVALID, Gdk.DragAction.COPY);
            drop.set_gtypes ({ typeof (Gdk.FileList), typeof (string) });
            drop.drop.connect (on_drop);
            thread_box.add_controller (drop);
            details_button = new Gtk.ToggleButton () {
                icon_name = "dialog-information-symbolic",
                tooltip_text = _("Fiche de la personne (Ctrl+I)"),
                valign = Gtk.Align.CENTER,
                visible = false,
                active = true
            };
            details_button.add_css_class ("flat");
            details_scroll = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                width_request = 280,
                vexpand = true
            };
            var details_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            details_box.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));
            details_box.append (details_scroll);
            details_panel = new Gtk.Revealer () {
                child = details_box,
                transition_type = Gtk.RevealerTransitionType.SLIDE_LEFT,
                reveal_child = true
            };
            details_button.toggled.connect (() => {
                if (details_button.active) {
                    fill_details ();
                }
                details_panel.reveal_child = details_button.active;
            });
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), style_css,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
            // pack_end goes right to left: details at the far end, as Apple's ⓘ.
            thread_bar.pack_end (details_button);
            thread_bar.pack_end (thread_call);
            // Thin sending bar under the header, as in Apple's Messages.
            send_bar = new Gtk.ProgressBar () { visible = false };
            send_bar.add_css_class ("send-bar");
            send_bar.update_property (Gtk.AccessibleProperty.LABEL, _("Envoi du message"), -1);
            thread_box.append (find_bar);
            thread_box.append (scroll_overlay);
            thread_box.append (compose_stack);

            var no_thread = new Granite.Placeholder (_("Personnes")) {
                description = _("Choisissez une personne : ses messages et ses appels s'affichent ici, dans l'ordre."),
                icon = new ThemedIcon (Config.APP_ID + ".Messages")
            };
            content_stack = new Gtk.Stack () { hexpand = true, vhomogeneous = false };
            // Scrolled: its wrapping text would otherwise make the row's minimum height exceed the natural one.
            content_stack.add_named (new Gtk.ScrolledWindow () {
                child = no_thread, hscrollbar_policy = Gtk.PolicyType.NEVER
            }, "none");
            content_stack.add_named (thread_box, "thread");
            details_panel.visible = false;  // no card while nobody is open
            content_stack.notify["visible-child-name"].connect (() => {
                details_panel.visible = content_stack.visible_child_name == "thread";
            });

            toast = new Granite.Toast ("");
            var overlay = new Gtk.Overlay () { child = content_stack, hexpand = true, vexpand = true };
            overlay.add_overlay (toast);
            var thread_and_details = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { vexpand = true };
            thread_and_details.append (overlay);
            thread_and_details.append (details_panel);
            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
            right.add_css_class ("view");
            right.append (thread_bar);
            right.append (send_bar);
            right.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            right.append (thread_and_details);

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = sidebar,
                end_child = right,
                resize_start_child = false,
                shrink_start_child = false,
                shrink_end_child = false,
                hexpand = true
            };
            append (paned);

            // Open on the latest messages and stay there as bubbles are laid out,
            // unless the user scrolled up to read older ones. Wrapped bubbles take
            // several layout passes, and GTK moves the value itself while the size
            // changes: only a move at an unchanged size is the user's.
            var vadj = bubble_scroll.vadjustment;
            vadj.changed.connect (() => {
                if (keep_from_bottom >= 0) {
                    queue_stick ();  // older bubbles laid out above: the same messages stay in view
                } else if (stick_bottom) {
                    queue_stick ();
                }
            });
            vadj.value_changed.connect (() => {
                if (vadj.upper != seen_upper || vadj.page_size != seen_page) {
                    seen_upper = vadj.upper;
                    seen_page = vadj.page_size;
                    if (stick_bottom) {
                        queue_stick ();
                    }
                    return;
                }
                keep_from_bottom = -1;  // the user's own move
                stick_bottom = vadj.value >= vadj.upper - vadj.page_size - 24;
                if (stick_bottom) {
                    unseen = 0;
                }
                if (vadj.value < vadj.lower + 400 && more_older) {
                    load_older.begin ();
                }
                update_down ();
            });

            daemon.threads_changed.connect (() => reload_threads.begin ());
            daemon.calls_changed.connect (() => reload_threads.begin ());
            daemon.send_progress.connect ((thread, id, fraction) => {
                if (thread == current) {
                    show_send_progress (fraction);
                }
            });
            daemon.changed.connect (() => {
                if (!daemon.touched ({ "MessagesState", "ContactsState", "MessagesSend" })) {
                    return;
                }
                update_state ();
                // The window can show before the daemon connection is up: load once it is.
                if (!threads_loaded && !loading_threads && daemon.running && get_mapped ()) {
                    reload_threads.begin ();
                }
            });
            unmap.connect (() => {
                save_draft ();
                daemon.call.begin ("SetViewing", new Variant ("(s)", ""));
            });
            map.connect (() => {
                reload_threads.begin ();
                mark_current_seen ();
            });
        }

        /* Down to the newest message (or, older bubbles just added above, back to the messages
           being read) once the layout of this frame is done: a value set in the middle of an
           allocation is lost. */
        private void queue_stick () {
            if (stick_source != 0) {
                return;
            }
            stick_source = Idle.add (() => {
                stick_source = 0;
                if (keep_from_bottom >= 0) {
                    var adj = bubble_scroll.vadjustment;
                    seen_upper = adj.upper;
                    seen_page = adj.page_size;
                    adj.value = (adj.upper - keep_from_bottom).clamp (adj.lower, adj.upper - adj.page_size);
                } else if (stick_bottom) {
                    var adj = bubble_scroll.vadjustment;
                    seen_upper = adj.upper;
                    seen_page = adj.page_size;
                    adj.value = adj.upper - adj.page_size;
                    unseen = 0;
                }
                update_down ();
                return Source.REMOVE;
            });
        }

        private void update_down () {
            down_button.visible = current != null && !stick_bottom && pending_scroll == null
                                  && content_stack.visible_child_name == "thread";
            down_count.visible = unseen > 0;
            down_count.label = unseen.to_string ();
            down_button.tooltip_text = unseen > 0
                ? ngettext ("%u nouveau message", "%u nouveaux messages", unseen).printf (unseen)
                : _("Aller au dernier message");
        }

        public void apply_style () {
            var style = current != null ? ThreadStyle.load (current) : new ThreadStyle ();
            var css = style.css ();
            if (css != applied_css) {  // a display-wide provider: reloading restyles every window
                style_css.load_from_string (Style.colors (css));
                applied_css = css;
            }
            // A conversation with its own colour tints its header bar (white text).
            if (style.bubble != "") {
                thread_bar.add_css_class ("tinted");
            } else {
                thread_bar.remove_css_class ("tinted");
            }
            for (int i = 0; ; i++) {
                var row = thread_list.get_row_at_index (i) as ThreadRow;
                if (row == null) {
                    break;
                }
                row.refresh_name ();
            }
            if (current != null) {
                show_names (style);
                thread_avatar.show_person (current_title, style.picture (current_avatar), current_group);
            }
        }

        /* The details panel, rebuilt for the conversation on screen. */
        private void fill_details () {
            if (current == null) {
                return;
            }
            var row = find_row (current);
            var details = new ConversationDetails (daemon, current, current_title, current_avatar,
                                                   current_group, current_group ? "" : current_number, toast,
                                                   current_new ? (bool?) null : row != null && row.pinned);
            details.changed.connect (apply_style);
            details_scroll.child = details;
        }

        /* The card on the right folds away when the window gets narrow, and comes back. */
        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            var wide = width >= 900;
            if (wide != details_wide) {
                details_wide = wide;
                Idle.add (() => {  // not while allocating
                    details_button.active = details_wide;
                    return Source.REMOVE;
                });
            }
        }

        /* Title and subtitle of the open conversation, the nickname first when there is one. */
        private void show_names (ThreadStyle style) {
            thread_title.label = style.shown_name (current_title);
            var number = format_address (current_number);
            thread_subtitle.label = current_group ? _("Conversation de groupe")
                                  : style.nickname != "" && number != "" ? "%s · %s".printf (current_title, number)
                                  : style.nickname != "" ? current_title : number;
            thread_subtitle.visible = thread_subtitle.label != "";
        }

        /* Alt+↑/↓: the conversation above or below in the list. */
        private bool step_thread (int delta) {
            var selected = thread_list.get_selected_row ();
            var index = selected != null ? selected.get_index () + delta : 0;
            var row = thread_list.get_row_at_index (index) as ThreadRow;
            while (row != null && !row.get_child_visible ()) {  // left out by the list's filter
                index += delta != 0 ? delta : 1;
                row = thread_list.get_row_at_index (index) as ThreadRow;
            }
            if (row == null) {
                return false;
            }
            thread_list.select_row (row);
            row.grab_focus ();
            return true;
        }

        // --- drag and drop ---

        private bool on_drop (Gtk.DropTarget target, Value value, double x, double y) {
            if (current == null) {
                return false;
            }
            if (value.holds (typeof (string))) {
                var text = (string) value;
                if (text == null || text.strip () == "" || compose_stack.visible_child_name != "compose") {
                    return false;
                }
                entry.buffer.insert_at_cursor (text, -1);
                entry.grab_focus ();
                return true;
            }
            if (!value.holds (typeof (Gdk.FileList))) {
                return false;
            }
            string[] paths = {};
            foreach (var file in ((Gdk.FileList) value.get_boxed ()).get_files ()) {
                if (file.get_path () != null) {
                    paths += file.get_path ();
                }
            }
            if (paths.length == 0) {
                return false;
            }
            offer_localsend (paths);
            return true;
        }

        /* The iPhone accepts no attachment in a message over Bluetooth: say so, and offer
           LocalSend (module « Envoi de fichiers ») when it is added. */
        private void offer_localsend (string[] paths) {
            var added = Catalog.added (daemon, "files");
            var name = paths.length == 1 ? Path.get_basename (paths[0]) : "";
            var title = !added ? _("Fichier non envoyé")
                      : paths.length == 1 ? _("Envoyer « %s » avec LocalSend ?").printf (name)
                      : ngettext ("Envoyer %d fichier avec LocalSend ?", "Envoyer %d fichiers avec LocalSend ?",
                                  paths.length).printf (paths.length);
            var detail = added
                ? _("Par Bluetooth, l'iPhone n'accepte pas de pièce jointe dans un message : le fichier "
                  + "ne part pas dans la conversation. LocalSend l'envoie à l'app LocalSend de l'iPhone, "
                  + "sur le même Wi-Fi ; choisissez ensuite l'iPhone dans Envoi de fichiers.")
                : _("Par Bluetooth, l'iPhone n'accepte pas de pièce jointe dans un message. Pour envoyer "
                  + "des fichiers à l'iPhone, ajoutez le module « Envoi de fichiers » (LocalSend) dans "
                  + "Modules ; le fichier ne part pas dans la conversation.");
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                title, detail, added ? "document-send" : "dialog-information",
                added ? Gtk.ButtonsType.CANCEL : Gtk.ButtonsType.CLOSE) {
                transient_for = get_root () as Gtk.Window,
                modal = true
            };
            if (added) {
                var send = dialog.add_button (_("Envoyer avec LocalSend"), Gtk.ResponseType.ACCEPT);
                send.add_css_class (Granite.CssClass.SUGGESTED);
            }
            dialog.response.connect ((response) => {
                dialog.destroy ();
                if (response == Gtk.ResponseType.ACCEPT) {
                    GLib.Application.get_default ().activate_action ("send-files", new Variant.strv (paths));
                }
            });
            dialog.present ();
        }

        // --- list filters: all, unread, unknown senders ---

        /* A small menu by the search, as in Apple's Messages: the list itself stays bare. */
        private Gtk.Widget filter_button () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6
            };
            filter_menu = new Gtk.MenuButton () {
                icon_name = "view-sort-descending-symbolic",
                tooltip_text = _("Filtrer la liste"),
                popover = new Gtk.Popover () { child = box }
            };
            filter_menu.add_css_class ("flat");
            Gtk.CheckButton? first = null;
            string[] names = { _("Toutes les personnes"), _("Messages non lus"), _("Expéditeurs inconnus") };
            for (int i = 0; i < names.length; i++) {
                var button = new Gtk.CheckButton.with_label (names[i]) { group = first, active = i == 0 };
                button.set_data<int> ("filter", i);
                button.toggled.connect (on_filter_toggled);
                first = first ?? button;
                box.append (button);
            }
            return filter_menu;
        }

        private void on_filter_toggled (Gtk.CheckButton button) {
            if (!button.active) {
                return;
            }
            list_filter = button.get_data<int> ("filter");
            // Not by colour alone: a filter on shows its name by the icon.
            filter_menu.label = list_filter == 0 ? null : list_filter == 1 ? _("Non lus") : _("Inconnus");
            if (list_filter == 0) {
                filter_menu.icon_name = "view-sort-descending-symbolic";
            }
            filter_menu.popdown ();
            filter_empty.label = list_filter == 1 ? _("Aucune conversation non lue")
                               : list_filter == 2 ? _("Aucun expéditeur inconnu") : "";
            thread_list.invalidate_filter ();
            thread_list.invalidate_headers ();
        }

        /* The open conversation stays listed: reading it must not make it vanish under the pointer. */
        private bool keep_row (Gtk.ListBoxRow row) {
            var thread = row as ThreadRow;
            if (thread == null || list_filter == 0 || thread.thread_id == current) {
                return true;
            }
            return list_filter == 1 ? thread.unread > 0 : !thread.known;
        }

        // --- keyboard shortcuts ---

        private bool next_thread_shortcut (Gtk.Widget widget, Variant? args) {
            return get_mapped () && step_thread (1);
        }

        private bool previous_thread_shortcut (Gtk.Widget widget, Variant? args) {
            return get_mapped () && step_thread (-1);
        }

        private bool details_shortcut (Gtk.Widget widget, Variant? args) {
            if (!get_mapped () || current == null || !details_button.visible) {
                return false;
            }
            details_button.active = !details_button.active;
            return true;
        }

        /* In a text field Ctrl+Suppr deletes the next word, as everywhere. */
        private bool delete_shortcut (Gtk.Widget widget, Variant? args) {
            var focus = (get_root () as Gtk.Window)?.get_focus ();
            if (!get_mapped () || current == null || current_new || focus is Gtk.Text || focus is Gtk.TextView) {
                return false;
            }
            confirm_delete_thread (current, ThreadStyle.load (current).shown_name (current_title), true);
            return true;
        }

        /* Échap: the search of the list (the person's card stays: Ctrl+I folds it). */
        private bool escape_shortcut (Gtk.Widget widget, Variant? args) {
            if (!get_mapped ()) {
                return false;
            }
            if (search.text != "") {
                search.text = "";
                return true;
            }
            return false;
        }

        private bool help_shortcut (Gtk.Widget widget, Variant? args) {
            if (!get_mapped ()) {
                return false;
            }
            show_shortcuts ();
            return true;
        }

        /* Ctrl+?: the shortcuts of Messages. */
        private void show_shortcuts () {
            // (Built from properties: the bindings keep these constructors private.)
            var section = (Gtk.ShortcutsSection) Object.@new (typeof (Gtk.ShortcutsSection),
                                                              "section-name", "messages", "title", _("Messages"));
            add_shortcut_group (section, _("Conversations"), {
                "<Control>n", _("Nouveau message"),
                "<Control>Tab", _("Conversation suivante"),
                "<Control><Shift>Tab", _("Conversation précédente"),
                "<Control>Down", _("Conversation suivante"),
                "<Control>Up", _("Conversation précédente"),
                "<Control>i", _("Afficher ou masquer la fiche de la personne"),
                "<Control>Delete", _("Supprimer la conversation de Boomerang"),
                "Menu", _("Menu du message ou de la conversation sélectionnés"),
                "Escape", _("Effacer la recherche")
            });
            add_shortcut_group (section, _("Recherche et synchronisation"), {
                "<Control>f", _("Rechercher dans la conversation"),
                "<Control><Shift>f", _("Rechercher dans toutes les conversations"),
                "<Control>r", _("Synchroniser avec l'iPhone")
            });
            add_shortcut_group (section, _("Saisie"), {
                "Return", _("Envoyer le message"),
                "<Shift>Return", _("Aller à la ligne"),
                "<Control>question", _("Afficher les raccourcis")
            });
            var window = (Gtk.ShortcutsWindow) Object.@new (typeof (Gtk.ShortcutsWindow),
                                                            "transient-for", get_root () as Gtk.Window,
                                                            "modal", true);
            window.add_section (section);
            window.present ();
        }

        private static void add_shortcut_group (Gtk.ShortcutsSection section, string title, string[] pairs) {
            var group = (Gtk.ShortcutsGroup) Object.@new (typeof (Gtk.ShortcutsGroup), "title", title);
            for (int i = 0; i + 1 < pairs.length; i += 2) {
                group.add_shortcut ((Gtk.ShortcutsShortcut) Object.@new (typeof (Gtk.ShortcutsShortcut),
                                                                         "accelerator", pairs[i],
                                                                         "title", pairs[i + 1]));
            }
            section.add_group (group);
        }

        // --- search in the open conversation ---

        private void find_run () {
            find_unmark ();
            find_hits = {};
            var query = find_entry.text.strip ().casefold ();
            if (query != "") {
                for (int i = 0; i < thread_ids.length; i++) {
                    if (thread_bodies[i].casefold ().contains (query)) {
                        find_hits += thread_ids[i];
                    }
                }
            }
            find_index = find_hits.length - 1;  // the most recent match first
            find_mark ();
            find_show ();
        }

        private void find_step (int delta) {
            if (find_hits.length == 0) {
                return;
            }
            find_index = (find_index + delta + find_hits.length) % find_hits.length;
            find_show ();
        }

        private void find_show () {
            if (find_entry.text.strip () == "") {
                find_count.label = "";
            } else if (find_hits.length == 0) {
                find_count.label = _("Aucun résultat");
            } else {
                find_count.label = _("%d sur %d").printf (find_index + 1, find_hits.length);
                pending_scroll = find_hits[find_index];
                pending_flash = true;
                scroll_to_pending ();
            }
        }

        private void find_mark () {
            foreach (var id in find_hits) {
                var widget = bubble_index[id];
                if (widget != null) {
                    widget.add_css_class ("find-match");
                }
            }
        }

        private void find_unmark () {
            foreach (var id in find_hits) {
                var widget = bubble_index[id];
                if (widget != null) {
                    widget.remove_css_class ("find-match");
                }
            }
        }

        private void find_clear () {
            find_unmark ();
            find_hits = {};
            find_entry.text = "";
            find_count.label = "";
        }

        public void window_activated () {
            update_viewing ();
            mark_current_seen ();
            reload_threads.begin ();
        }

        public void open_thread (string id, bool reply) {
            pending_open = id;
            pending_reply = reply;
            reload_threads.begin ();
        }

        private void mark_current_seen () {
            var window = get_root () as Gtk.Window;
            if (current != null && get_mapped () && window != null && window.is_active) {
                daemon.call.begin ("MarkThreadSeen", new Variant ("(s)", current));
            }
        }

        // --- state banner ------------------------------------------------------------

        private void update_state () {
            var state = daemon.get_string ("MessagesState");
            var contacts = daemon.get_string ("ContactsState");
            string text = "";
            bool retry = false;
            switch (state) {
                case "disabled":
                    text = _("Le module Messages et contacts est désactivé dans la page iPhone.");
                    break;
                case "no-obex":
                    text = _("Le service Bluetooth OBEX (paquet bluez-obexd) est absent : "
                           + "installez-le pour lire les messages de l'iPhone.");
                    break;
                case "absent":
                    text = _("iPhone absent. Les messages déjà reçus restent consultables.");
                    break;
                case "connecting":
                    text = _("Connexion aux messages de l'iPhone…");
                    break;
                case "forbidden":
                    text = _("L'iPhone refuse l'accès aux messages. Sur l'iPhone, ouvrez Réglages › "
                           + "Bluetooth, touchez ⓘ à côté de ce PC et activez « Afficher les "
                           + "notifications », puis réessayez.");
                    retry = true;
                    break;
                case "error":
                    text = _("Les messages de l'iPhone sont momentanément illisibles.");
                    retry = true;
                    break;
                default:
                    if (contacts == "forbidden") {
                        text = _("Pour afficher les noms, activez « Synchroniser les contacts » "
                               + "dans les réglages Bluetooth de l'iPhone pour ce PC. Boomerang "
                               + "renouvelle la demande automatiquement pendant 10 minutes.");
                        retry = true;
                    }
                    break;
            }
            banner_label.label = text;
            banner_button.visible = retry;
            banner.visible = text != "";
            update_compose ();
        }

        // --- conversation list -------------------------------------------------------

        private async void reload_threads () {
            if (loading_threads) {
                reload_again = true;
                return;
            }
            loading_threads = true;
            bool ok;
            var items = yield daemon.try_list ("ListThreads", null, out ok);
            if (!ok) {
                // Daemon restarting or slow: keep the list and the open conversation.
                loading_threads = false;
                reload_again = false;
                return;
            }
            threads_loaded = true;
            bool calls_ok;
            var loaded_calls = yield daemon.try_list ("ListCalls", null, out calls_ok);
            if (calls_ok) {
                calls = loaded_calls;  // (failed call: the calls known stay)
            }
            ThreadRow? to_select = null;
            var want = pending_open ?? current;
            var people = people_of (items);

            // Reuse rows in order: keeps the selection and scrolling steady.
            int index = 0;
            foreach (var person in people) {
                var row = thread_list.get_row_at_index (index) as ThreadRow;
                if (row == null) {
                    row = new ThreadRow ();
                    thread_list.append (row);
                }
                row.set_from (person);
                if (row.thread_id == want && want != null) {
                    to_select = row;
                } else if (row.thread_id == "" && current_new && pending_open == null
                           && number_tail (row.number) == number_tail (current_number)) {
                    thread_list.select_row (row);  // the person with calls only, open (row_selected skips it)
                }
                index++;
            }
            Gtk.ListBoxRow? extra;
            while ((extra = thread_list.get_row_at_index (index)) != null) {
                thread_list.remove (extra);
            }
            thread_list.invalidate_filter ();
            thread_list.invalidate_headers ();
            if (current != null) {
                load_messages.begin (current, current_group, false);  // calls may have changed
            }
            if (search.text.strip () == "") {
                list_stack.visible_child_name = people.length > 0 ? "list" : "empty";
            }

            if (to_select != null) {
                var reply = pending_reply && to_select.thread_id == pending_open;
                pending_open = null;
                pending_reply = false;
                if (thread_list.get_selected_row () != to_select) {
                    current = null;
                    thread_list.select_row (to_select);
                } else {
                    show_thread (to_select);
                }
                if (reply && compose_stack.visible_child_name == "compose") {
                    entry.grab_focus ();
                }
            } else if (current != null && !current_new) {
                current = null;
                content_stack.visible_child_name = "none";
            }
            loading_threads = false;
            if (reload_again) {
                reload_again = false;
                reload_threads.begin ();
            }
        }

        /* One entry per person: the conversations, each with the person's latest call when it is
           newer than the messages, then the people known only from the call history; favourites
           (pinned) first, then the latest event first. */
        private VariantDict[] people_of (Variant[] threads) {
            var latest = new HashTable<string, Variant> (str_hash, str_equal);  // number tail -> newest call
            foreach (var call in calls) {
                var tail = number_tail (Props.str (call, "address"));
                var known = latest[tail];
                if (tail != "" && (known == null || call_time (call) > call_time (known))) {
                    latest[tail] = call;
                }
            }
            var people = new GenericArray<VariantDict> ();
            foreach (var item in threads) {
                var d = new VariantDict (item);
                var tail = number_tail (ThreadRow.number_of (d));
                var call = tail != "" && !dict_bool (d, "group") ? latest[tail] : null;
                if (call != null) {
                    latest.remove (tail);
                    if (call_time (call) > dict_int64 (d, "time")) {
                        add_call (d, call);
                    }
                }
                people.add (d);
            }
            foreach (var call in latest.get_values ()) {
                var address = Props.str (call, "address");
                var name = Props.str (call, "name");
                var d = new VariantDict ();
                d.insert_value ("id", new Variant.string (""));
                d.insert_value ("name", new Variant.string (name != "" ? name : format_address (address)));
                d.insert_value ("participants", new Variant.strv ({ address }));
                d.insert_value ("avatar", new Variant.string (Props.str (call, "avatar")));
                d.insert_value ("known", new Variant.boolean (name != ""));
                d.insert_value ("can_send", new Variant.boolean (true));
                add_call (d, call);
                people.add (d);
            }
            people.sort_with_data ((a, b) => {
                var pinned = (int) dict_bool (b, "pinned") - (int) dict_bool (a, "pinned");
                return pinned != 0 ? pinned : (int) (dict_int64 (b, "time") - dict_int64 (a, "time")).clamp (-1, 1);
            });
            return people.data;
        }

        private static int64 call_time (Variant call) {
            var time = call.lookup_value ("time", VariantType.INT64);
            return time != null ? time.get_int64 () : 0;
        }

        private static void add_call (VariantDict d, Variant call) {
            d.insert_value ("call_kind", new Variant.string (Props.str (call, "kind")));
            var length = call.lookup_value ("duration", VariantType.INT32);
            d.insert_value ("call_duration", new Variant.int32 (length != null ? length.get_int32 () : -1));
            d.insert_value ("time", new Variant.int64 (call_time (call)));
        }

        /* The calls with the open person, oldest first (none in a group conversation). */
        private Variant[] person_calls () {
            var found = new GenericArray<Variant> ();
            var tail = number_tail (current_number);
            foreach (var call in calls) {
                if (!current_group && tail != "" && number_tail (Props.str (call, "address")) == tail) {
                    found.add (call);
                }
            }
            found.sort_with_data ((a, b) => (int) (call_time (a) - call_time (b)).clamp (-1, 1));
            return found.data;
        }

        // --- search ------------------------------------------------------------------

        private async void run_search () {
            var query = search.text.strip ();
            var serial = ++search_serial;
            if (query == "") {
                list_stack.visible_child_name = thread_list.get_row_at_index (0) != null ? "list" : "empty";
                return;
            }
            var items = yield daemon.call_list ("SearchMessages", new Variant ("(s)", query));
            var cards = yield daemon.call_list ("ListContacts");
            if (serial != search_serial) {
                return;  // typed further in the meantime
            }
            Gtk.Widget? old;
            while ((old = search_list.get_first_child ()) != null) {
                search_list.remove (old);
            }
            // People whose name matches, then the contacts with no exchange yet, then the messages.
            int shown = 0;
            foreach (var item in items) {
                if (Props.str (item, "message") == "") {
                    search_list.append (new SearchRow (new VariantDict (item)));
                    shown++;
                }
            }
            var listed = new GenericSet<string> (str_hash, str_equal);
            for (int i = 0; thread_list.get_row_at_index (i) != null; i++) {
                listed.add (number_tail (((ThreadRow) thread_list.get_row_at_index (i)).number));
            }
            foreach (var card in cards) {
                var contact = Contact.from_variant (card);
                string? phone = null;
                foreach (var a in contact.addresses) {
                    if (contact.is_phone (a) && phone == null) {
                        phone = a;
                    }
                }
                if (phone == null || listed.contains (number_tail (phone)) || !contact.matches (query)) {
                    continue;
                }
                var d = new VariantDict ();
                d.insert_value ("name", new Variant.string (contact.name));
                d.insert_value ("before", new Variant.string (contact.name));
                d.insert_value ("avatar", new Variant.string (contact.photo));
                d.insert_value ("address", new Variant.string (phone));
                search_list.append (new SearchRow (d));
                shown++;
            }
            foreach (var item in items) {
                if (Props.str (item, "message") != "") {
                    search_list.append (new SearchRow (new VariantDict (item)));
                    shown++;
                }
            }
            if (shown == 0) {
                search_empty.label = _("Aucun résultat pour « %s »").printf (query);
                list_stack.visible_child_name = "search-empty";
            } else {
                list_stack.visible_child_name = "search";
            }
        }

        /* Open the conversation of a result and bring the message into view. */
        private void open_search_hit (SearchRow hit) {
            if (hit.thread_id == "") {
                start_conversation (hit.address);
                return;
            }
            for (int i = 0; ; i++) {
                var row = thread_list.get_row_at_index (i) as ThreadRow;
                if (row == null) {
                    return;
                }
                if (row.thread_id != hit.thread_id) {
                    continue;
                }
                pending_scroll = hit.message != "" ? hit.message : null;
                pending_flash = true;
                if (current == row.thread_id && !current_new) {
                    scroll_to_pending ();
                } else if (thread_list.get_selected_row () == row) {
                    show_thread (row);
                } else {
                    thread_list.select_row (row);
                }
                return;
            }
        }

        private void scroll_to_pending (int tries = 0) {
            if (pending_scroll == null) {
                return;
            }
            stick_bottom = false;
            Timeout.add (tries == 0 ? 60 : 120, () => {
                var target = pending_scroll != null ? bubble_index[pending_scroll] : null;
                if (target == null) {
                    // Older than the pages read: read further back (up to 5 000 messages).
                    if (pending_scroll != null && pending_scroll != older_for) {
                        older_for = pending_scroll;
                        older_tries = 0;
                    }
                    if (pending_scroll != null && more_older && older_tries < 25) {
                        older_tries++;
                        load_older.begin ();  // shows them, then comes back here
                    } else if (!loading_older) {
                        pending_scroll = null;
                    }
                    return Source.REMOVE;
                }
                Graphene.Point where = Graphene.Point () { x = 0, y = 0 };
                var placed = target.get_height () > 0
                             && target.compute_point (bubble_column, Graphene.Point () { x = 0, y = 0 }, out where);
                if (!placed) {
                    if (tries < 10) {
                        scroll_to_pending (tries + 1);
                    } else {
                        pending_scroll = null;
                    }
                    return Source.REMOVE;
                }
                pending_scroll = null;
                var adj = bubble_scroll.vadjustment;
                stick_bottom = false;
                keep_from_bottom = -1;
                adj.value = (where.y - adj.page_size / 3)
                            .clamp (adj.lower, adj.upper - adj.page_size);
                if (pending_flash) {
                    target.add_css_class ("search-flash");
                    Timeout.add (1800, () => {
                        target.remove_css_class ("search-flash");
                        return Source.REMOVE;
                    });
                }
                pending_flash = true;
                update_down ();
                return Source.REMOVE;
            });
        }

        private void on_thread_list_pressed (Gtk.GestureClick click, int n, double x, double y) {
            var row = thread_list.get_row_at_y ((int) y) as ThreadRow;
            if (row == null) {
                return;
            }
            click.set_state (Gtk.EventSequenceState.CLAIMED);
            Graphene.Point at;
            if (!thread_list.compute_point (row, Graphene.Point () { x = (float) x, y = (float) y }, out at)) {
                at = Graphene.Point () { x = 0, y = 0 };
            }
            show_thread_menu (row, at.x, at.y);
        }

        /* Menu key or Maj+F10 on a conversation: the same menu as the right click. */
        private bool on_thread_list_key (Gtk.EventControllerKey keys, uint keyval, uint code,
                                         Gdk.ModifierType state) {
            if (!is_menu_key (keyval, state)) {
                return false;
            }
            var focus = (get_root () as Gtk.Window)?.get_focus ();
            var row = focus as ThreadRow ?? (focus != null ? focus.get_ancestor (typeof (ThreadRow)) as ThreadRow : null)
                      ?? thread_list.get_selected_row () as ThreadRow;
            if (row == null) {
                return false;
            }
            show_thread_menu (row, row.get_width () / 2, row.get_height () / 2);
            return true;
        }

        private static bool is_menu_key (uint keyval, Gdk.ModifierType state) {
            return keyval == Gdk.Key.Menu
                   || (keyval == Gdk.Key.F10 && (state & Gdk.ModifierType.SHIFT_MASK) != 0);
        }

        /* Right click on a conversation: pin, read state (Boomerang only), delete. */
        private void show_thread_menu (ThreadRow row, double x, double y) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                margin_top = 3,
                margin_bottom = 3
            };
            var popover = new Gtk.Popover () {
                child = box,
                has_arrow = false,
                pointing_to = { (int) x, (int) y, 1, 1 }
            };
            popover.add_css_class ("menu");
            // The buttons live inside the popover: held strongly, it would never be freed.
            unowned Gtk.Popover menu = popover;
            var id = row.thread_id;
            var title = row.title;
            var pinned = row.pinned;
            var unread = row.unread > 0;

            var pin = menu_item (pinned ? _("Retirer des favoris") : _("Ajouter aux favoris"));
            pin.clicked.connect (() => {
                menu.popdown ();
                daemon.call.begin ("PinThread", new Variant ("(sb)", id, !pinned));
            });
            box.append (pin);

            var read = menu_item (unread ? _("Marquer comme lu") : _("Marquer comme non lu"));
            read.tooltip_text = _("Dans Boomerang seulement : l'iPhone n'est pas modifié");
            read.clicked.connect (() => {
                menu.popdown ();
                if (unread) {
                    daemon.call.begin ("MarkThreadSeen", new Variant ("(s)", id));
                    return;
                }
                if (id == current) {
                    // Leave it, or opening it would mark it read again at once.
                    thread_list.unselect_all ();
                    current = null;
                    rendered = "";
                    content_stack.visible_child_name = "none";
                    update_viewing ();
                }
                daemon.call.begin ("MarkThreadUnread", new Variant ("(sb)", id, true));
            });
            box.append (read);

            var look = menu_item (_("Fiche de la personne"));
            look.clicked.connect (() => {
                menu.popdown ();
                if (id != current) {
                    var target = find_row (id);
                    if (target != null) {
                        thread_list.select_row (target);
                        show_thread (target);
                    }
                }
                details_button.active = true;
            });
            box.append (look);

            var export = menu_item (_("Exporter…"));
            export.clicked.connect (() => {
                menu.popdown ();
                ConversationExport.run.begin (get_root () as Gtk.Window, daemon, id,
                                              ThreadStyle.load (id).shown_name (title));
            });
            box.append (export);

            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 3, margin_bottom = 3 });
            var remove = menu_item (_("Supprimer la conversation…"));
            remove.clicked.connect (() => {
                menu.popdown ();
                confirm_delete_thread (id, title);
            });
            box.append (remove);

            popover.set_parent (row);
            popover.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            popover.popup ();
        }

        private ThreadRow? find_row (string id) {
            for (int i = 0; ; i++) {
                var row = thread_list.get_row_at_index (i) as ThreadRow;
                if (row == null || row.thread_id == id) {
                    return row;
                }
            }
        }

        private static Gtk.Button menu_item (string text) {
            var button = new Gtk.Button () {
                child = new Gtk.Label (text) { xalign = 0 }
            };
            button.add_css_class ("flat");
            return button;
        }

        // --- thread ------------------------------------------------------------------

        private void show_thread (ThreadRow row) {
            if (row.thread_id == "") {
                start_conversation (row.number);  // calls only so far: the person's thread, empty
                return;
            }
            current_number = row.number;
            next_unread = row.thread_id != current ? row.unread : 0;
            show_info (row.thread_id, row.title, row.avatar_path, row.is_group, row.can_send, false);
            if (row.unread > 0) {
                mark_current_seen ();
            }
        }

        private void save_draft () {
            if (draft_timer != 0) {
                Source.remove (draft_timer);
                draft_timer = 0;
            }
            if (current != null) {
                daemon.call.begin ("SetDraft", new Variant ("(ss)", current, entry.buffer.text));
            }
        }

        private string draft_of (string id) {
            for (int i = 0; ; i++) {
                var row = thread_list.get_row_at_index (i) as ThreadRow;
                if (row == null) {
                    return "";
                }
                if (row.thread_id == id) {
                    return row.draft;
                }
            }
        }

        /* Tell the daemon which thread is on screen, so it does not pop a banner for it. */
        public void update_viewing () {
            var window = get_root () as Gtk.Window;
            var on_screen = current != null && get_mapped () && window != null && window.is_active;
            daemon.call.begin ("SetViewing", new Variant ("(s)", on_screen ? current : ""));
        }

        private void show_info (string id, string title, string avatar, bool group, bool can_send,
                                bool is_new) {
            var changed = current != id;
            if (changed) {
                save_draft ();
                loading_draft = true;
                entry.buffer.text = draft_of (id);
                loading_draft = false;
            }
            current = id;
            current_title = title;
            current_group = group;
            current_can_send = can_send;
            current_new = is_new;
            if (changed) {
                unread_mark = next_unread;
                unread_id = "";
                unseen = 0;
                last_id = "";
                shown_items = {};
                more_older = false;
                keep_from_bottom = -1;
                older_button.visible = false;
                find_bar.search_mode_enabled = false;
            }
            next_unread = 0;
            if (changed && list_filter != 0) {
                thread_list.invalidate_filter ();  // the conversation left goes if it no longer matches
            }
            thread_title_box.get_parent ().visible = true;
            thread_bar.visible = true;
            details_button.visible = true;
            current_avatar = avatar;
            thread_avatar.show_person (title, ThreadStyle.load (id).picture (avatar), group);
            Gtk.Widget? old_call;
            while ((old_call = thread_call.get_first_child ()) != null) {
                thread_call.remove (old_call);
            }
            if (!group && current_number != "") {
                var call = new CallButton (daemon, current_number, toast);  // flat phone; the card has Appeler
                call.update_property (Gtk.AccessibleProperty.LABEL, _("Appeler %s").printf (title), -1);
                thread_call.append (call);
            }
            content_stack.visible_child_name = "thread";
            if (changed && details_button.active) {
                fill_details ();
            }
            apply_style ();
            update_compose ();
            load_messages.begin (id, group, changed);
            update_viewing ();
        }

        /* Existing conversation with this address, or a new empty one. */
        public void start_conversation (string address) {
            daemon.call_dict.begin ("OpenConversation", new Variant ("(s)", address), (obj, res) => {
                var result = daemon.call_dict.end (res);
                if (result == null) {
                    toast.title = _("Adresse non reconnue");
                    toast.send_notification ();
                    return;
                }
                var d = new VariantDict (result);
                var id = dict_string (d, "id");
                for (int i = 0; ; i++) {
                    var row = thread_list.get_row_at_index (i) as ThreadRow;
                    if (row == null) {
                        break;
                    }
                    if (row.thread_id == id) {
                        thread_list.select_row (row);
                        show_thread (row);
                        entry.grab_focus ();
                        return;
                    }
                }
                var chosen = thread_list.get_selected_row () as ThreadRow;
                if (chosen == null || chosen.thread_id != "") {  // a person with calls only stays chosen
                    thread_list.unselect_all ();
                }
                var people = d.lookup_value ("participants", new VariantType ("as"));
                current_number = people != null && people.n_children () == 1
                                 ? people.get_child_value (0).get_string () : "";
                show_info (id, dict_string (d, "name"), dict_string (d, "avatar"), false,
                           dict_bool (d, "can_send"), true);
                entry.grab_focus ();
            });
        }

        /* The conversation's latest messages, again after each change. The history is read in
           pages of PAGE: the first page on opening, older ones on scrolling up; a reload keeps
           the oldest message on screen, so the pages already read stay. */
        private async void load_messages (string thread, bool group, bool changed) {
            var serial = ++load_serial;
            var anchor = changed || shown_items.length == 0 ? ""
                         : dict_string (new VariantDict (shown_items[0]), "id");
            // Room for the messages arrived since: the oldest one shown stays first.
            uint count = changed ? PAGE : uint.max (PAGE, (uint) shown_items.length + 50);
            bool ok, more;
            var items = yield daemon.get_messages_page (thread, 0, "", count, out ok, out more);
            if (thread != current || !ok || serial != load_serial) {
                return;  // (failed call: the bubbles on screen stay)
            }
            if (!changed && shown_items.length > 0) {
                var oldest = dict_string (new VariantDict (shown_items[0]), "id");
                if (oldest != anchor) {
                    load_messages.begin (thread, group, false);  // older page added meanwhile
                    return;
                }
                for (int i = 1; i < items.length; i++) {
                    if (dict_string (new VariantDict (items[i]), "id") == anchor) {
                        items = items[i:items.length];
                        more = true;
                        break;
                    }
                }
            }
            more_older = more;
            show_messages (thread, group, changed, items);
        }

        /* Scrolled near the top (or « Messages plus anciens »): the page before the oldest shown. */
        private async void load_older () {
            if (loading_older || !more_older || current == null || shown_items.length == 0) {
                return;
            }
            loading_older = true;
            update_older_button ();
            var thread = current;
            var oldest = new VariantDict (shown_items[0]);
            var cursor = dict_string (oldest, "id");
            bool ok, more;
            var older = yield daemon.get_messages_page (thread, dict_int64 (oldest, "time"), cursor, PAGE,
                                                        out ok, out more);
            loading_older = false;
            if (thread != current || !ok || shown_items.length == 0
                || dict_string (new VariantDict (shown_items[0]), "id") != cursor) {
                update_older_button ();
                return;
            }
            more_older = more;
            Variant[] items = older;
            foreach (var item in shown_items) {
                items += item;
            }
            // Bubbles added above: the messages being read stay where they are.
            var adj = bubble_scroll.vadjustment;
            keep_from_bottom = adj.upper - adj.value;
            show_messages (thread, current_group, false, items);
        }

        private void update_older_button () {
            older_button.visible = current != null && more_older;
            older_button.sensitive = !loading_older;
            older_button.label = loading_older ? _("Chargement des messages plus anciens…")
                                               : _("Afficher les messages plus anciens");
        }

        private void show_messages (string thread, bool group, bool changed, Variant[] items) {
            // "Non lus": the line goes above the first of the messages unread at opening.
            // Found once, then kept on that message: a message arriving later does not move it.
            int unread_from = -1;
            if (unread_id != "") {
                for (int i = 0; i < items.length; i++) {
                    if (dict_string (new VariantDict (items[i]), "id") == unread_id) {
                        unread_from = i;
                        break;
                    }
                }
            } else if (unread_mark > 0) {
                uint seen = 0;
                for (int i = items.length - 1; i >= 0; i--) {
                    var d = new VariantDict (items[i]);
                    if (!dict_bool (d, "outgoing") && dict_string (d, "note") == "") {
                        seen++;
                        if (seen == unread_mark) {
                            unread_from = i;
                            break;
                        }
                    }
                }
            }
            if (unread_from >= 0) {
                unread_id = dict_string (new VariantDict (items[unread_from]), "id");
            }
            if (changed && unread_from >= 0 && unread_mark >= 3 && pending_scroll == null) {
                pending_scroll = dict_string (new VariantDict (items[unread_from]), "id");
                pending_flash = false;
            }
            if (changed) {
                stick_bottom = pending_scroll == null;
            }
            // New messages while the user reads older ones: counted on the ↓ button.
            if (!changed && !stick_bottom && last_id != "") {
                bool after = false;
                foreach (var item in items) {
                    var d = new VariantDict (item);
                    if (after && !dict_bool (d, "outgoing")) {
                        unseen++;
                    }
                    after = after || dict_string (d, "id") == last_id;
                }
            }
            last_id = items.length > 0 ? dict_string (new VariantDict (items[items.length - 1]), "id") : "";

            // Redraw only what changed: a new message adds its bubble at the end, older messages
            // add theirs at the start, a change in the middle redraws that part. A redraw would
            // also destroy an open context menu (focus changes when it opens re-run this on Wayland).
            var head = "%s|%s|%s".printf (thread, group ? "g" : "1", unread_id);
            // The person's calls go just before the first message that follows them; those older
            // than the pages read wait for these pages, the newest ones follow the last message.
            var person = person_calls ();
            var call_start = new int[items.length + 1];
            int next_call = 0;
            if (more_older && items.length > 0) {
                var oldest = dict_int64 (new VariantDict (items[0]), "time");
                while (next_call < person.length && call_time (person[next_call]) < oldest) {
                    next_call++;
                }
            }
            for (int i = 0; i < items.length; i++) {
                call_start[i] = next_call;
                var time = dict_int64 (new VariantDict (items[i]), "time");
                while (next_call < person.length && call_time (person[next_call]) <= time) {
                    next_call++;
                }
            }
            call_start[items.length] = next_call;
            Gtk.Widget? old_call;
            while ((old_call = call_tail.get_first_child ()) != null) {
                call_tail.remove (old_call);
            }
            var tail_after = items.length > 0 ? dict_int64 (new VariantDict (items[items.length - 1]), "time") : 0;
            for (int k = next_call; k < person.length; k++) {
                call_tail.append (call_pill (person[k], tail_after));
                tail_after = call_time (person[k]);
            }
            string[] sigs = {};
            var last_sent = -1;
            for (int i = 0; i < items.length; i++) {
                if (dict_bool (new VariantDict (items[i]), "outgoing")) {
                    last_sent = i;
                }
            }
            for (int i = 0; i < items.length; i++) {
                var d = new VariantDict (items[i]);
                // Everything a bubble shows: a reaction received, a note or a sender name
                // arriving later must redraw it.
                var reactions = d.lookup_value ("reactions", null);
                sigs += "%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s".printf (
                    run_end (items, i) ? (i == last_sent ? "E" : "e") : "-",
                    dict_string (d, "id"),
                    dict_string (d, "status"),
                    dict_bool (d, "complete") ? "1" : "0",
                    dict_string (d, "body").length.to_string (),
                    dict_string (d, "avatar"), dict_string (d, "sender"),
                    dict_int64 (d, "time").to_string (), dict_string (d, "note"),
                    reactions != null ? reactions.print (false) : "",
                    dict_bool (d, "attachment") ? "a" : "");
                for (int k = call_start[i]; k < call_start[i + 1]; k++) {
                    sigs[i] += ":c" + call_time (person[k]).to_string ();
                }
            }
            int start, shown_end, now_end;
            if (head == rendered) {
                if (!redraw_range (rendered_items, sigs, out start, out shown_end, out now_end)) {
                    shown_items = items;
                    update_older_button ();
                    scroll_to_pending ();
                    return;
                }
            } else {
                // Another conversation (or its unread line moved): everything.
                Gtk.Widget? old;
                while ((old = bubbles.get_first_child ()) != null) {
                    bubbles.remove (old);
                }
                bubble_index.remove_all ();
                thread_ids = {};
                thread_bodies = {};
                item_starts = {};
                start = shown_end = 0;
                now_end = sigs.length;
            }
            rendered = head;
            debug ("bubbles redrawn: %d to %d of %d (were %d to %d)",  // G_MESSAGES_DEBUG=all
                   start, now_end, sigs.length, start, shown_end);

            // The widgets of messages [start, shown_end) go; the new ones take their place.
            Gtk.Widget? anchor = start == 0 ? null
                               : start < item_starts.length ? item_starts[start].get_prev_sibling ()
                               : bubbles.get_last_child ();
            Gtk.Widget? stop = shown_end < item_starts.length ? item_starts[shown_end] : null;
            Gtk.Widget? child = start < item_starts.length ? item_starts[start] : null;
            while (child != null && child != stop) {
                var next = child.get_next_sibling ();
                bubbles.remove (child);
                child = next;
            }
            for (int i = start; i < shown_end && i < thread_ids.length; i++) {
                bubble_index.remove (thread_ids[i]);
            }
            string[] ids = {};
            string[] bodies = {};
            Gtk.Widget[] starts = {};
            for (int i = 0; i < start; i++) {
                ids += thread_ids[i];
                bodies += thread_bodies[i];
                starts += item_starts[i];
            }
            // What the first redrawn bubble follows: the message before it.
            int64 previous_time = 0;
            string previous_sender = "";
            bool previous_outgoing = false;
            if (start > 0) {
                var before = new VariantDict (items[start - 1]);
                previous_time = dict_int64 (before, "time");
                previous_sender = dict_string (before, "sender");
                previous_outgoing = dict_bool (before, "outgoing");
            }
            for (int index = start; index < now_end; index++) {
                var d = new VariantDict (items[index]);
                var time = dict_int64 (d, "time");
                var outgoing = dict_bool (d, "outgoing");
                var sender = dict_string (d, "sender");
                ids += dict_string (d, "id");
                bodies += dict_string (d, "body");
                Gtk.Widget? first = null;
                for (int k = call_start[index]; k < call_start[index + 1]; k++) {
                    var pill = call_pill (person[k], k > call_start[index] ? call_time (person[k - 1]) : previous_time);
                    bubbles.insert_child_after (pill, anchor);
                    anchor = pill;
                    first = first ?? pill;
                }
                var new_block = time - previous_time > 3600;
                if (new_block) {
                    var stamp = new Gtk.Label (long_time (time)) { margin_top = 12, margin_bottom = 4 };
                    stamp.add_css_class (Granite.CssClass.DIM);
                    stamp.add_css_class (Granite.CssClass.SMALL);
                    bubbles.insert_child_after (stamp, anchor);
                    anchor = stamp;
                    first = first ?? stamp;
                }
                var show_sender = group && !outgoing
                                  && (new_block || previous_outgoing || sender != previous_sender);
                var item_widget = bubble (d, outgoing, show_sender ? sender : null,
                                          !new_block && outgoing == previous_outgoing
                                          && sender == previous_sender,
                                          run_end (items, index), index == last_sent);
                if (group && !outgoing) {
                    // Apple-style: the sender's picture next to the first bubble of a run.
                    var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                    if (show_sender) {
                        var face = new Avatar (28) { valign = Gtk.Align.END };
                        face.show_person (sender, dict_string (d, "avatar"));
                        line.append (face);
                    } else {
                        line.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { width_request = 28 });
                    }
                    line.append (item_widget);
                    item_widget = line;
                }
                bubbles.insert_child_after (item_widget, anchor);
                anchor = item_widget;
                bubble_index[dict_string (d, "id")] = item_widget;
                starts += first ?? item_widget;
                previous_time = time;
                previous_sender = sender;
                previous_outgoing = outgoing;
            }
            for (int i = shown_end; i < thread_ids.length; i++) {
                ids += thread_ids[i];
                bodies += thread_bodies[i];
                starts += item_starts[i];
            }
            thread_ids = ids;
            thread_bodies = bodies;
            item_starts = starts;
            rendered_items = sigs;
            shown_items = items;
            // The adjustment's handlers keep the view on the newest message.
            if (stick_bottom) {
                queue_stick ();
            }
            if (find_bar.search_mode_enabled && find_hits.length > 0) {
                find_mark ();  // the bubbles were rebuilt
            }
            update_older_button ();
            update_down ();
            scroll_to_pending ();
        }

        private void on_older_clicked () {
            load_older.begin ();
        }

        /* A call in the thread: a pill in the middle, green when it went through, red when missed,
           with Rappeler. The icon and the words say which, not only the colour. The day goes
           above it when it is not the day of what comes before (previous: that time). */
        private Gtk.Widget call_pill (Variant call, int64 previous) {
            var kind = Props.str (call, "kind");
            var missed = kind == "missed";
            var length = call.lookup_value ("duration", VariantType.INT32);
            var entry = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) { margin_top = 8, margin_bottom = 4 };
            var day = short_time (call_time (call));
            var day_before = previous > 0 ? short_time (previous) : "";
            if (day != day_before && !(day.contains (":") && day_before.contains (":"))) {
                var label = new Gtk.Label (day.contains (":") ? _("Aujourd'hui") : day);
                label.add_css_class (Granite.CssClass.DIM);
                label.add_css_class (Granite.CssClass.SMALL);
                entry.append (label);
            }
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) { halign = Gtk.Align.CENTER };
            entry.append (box);
            box.add_css_class ("call-pill");
            box.add_css_class (missed ? "missed" : "done");
            box.append (new Gtk.Image.from_icon_name (missed ? "call-missed-symbolic"
                                                     : kind == "dialed" ? "call-outgoing-symbolic"
                                                     : "call-incoming-symbolic"));
            box.append (new Gtk.Label (call_summary (kind, length != null ? length.get_int32 () : -1,
                                                     call_time (call), true)));
            var address = Props.str (call, "address");
            if (missed && address != "") {
                var again = new CallButton (daemon, address, toast) { label = _("Rappeler") };
                again.remove_css_class ("flat");
                again.update_property (Gtk.AccessibleProperty.LABEL, _("Rappeler %s").printf (current_title), -1);
                box.append (again);
                box.add_css_class ("with-button");
            }
            return entry;
        }

        /* Last bubble of a run (same side and sender, within the hour): it gets the tail. */
        private static bool run_end (Variant[] items, int i) {
            if (i + 1 >= items.length) {
                return true;
            }
            var d = new VariantDict (items[i]);
            var next = new VariantDict (items[i + 1]);
            return dict_bool (d, "outgoing") != dict_bool (next, "outgoing")
                || dict_string (d, "sender") != dict_string (next, "sender")
                || dict_int64 (next, "time") - dict_int64 (d, "time") > 3600
                || dict_string (next, "note") != "";
        }

        /* Deletion only happens in Boomerang: say so, until the user no longer wants to be told. */
        private void confirm (string title, string detail, owned VoidFunc on_accept, bool always = false) {
            if (!always && !MessagesPrefs.warns ("warn-on-delete")) {
                on_accept ();
                toast.title = _("Supprimé de Boomerang, toujours sur l'iPhone");
                toast.send_notification ();
                return;
            }
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                title, detail, "edit-delete", Gtk.ButtonsType.CANCEL) {
                transient_for = get_root () as Gtk.Window,
                modal = true
            };
            var quiet = new Gtk.CheckButton.with_label (_("Ne plus m'avertir"));
            dialog.custom_bin.append (quiet);
            var remove = dialog.add_button (_("Supprimer"), Gtk.ResponseType.ACCEPT);
            remove.add_css_class (Granite.CssClass.DESTRUCTIVE);
            dialog.response.connect ((response) => {
                var accepted = response == Gtk.ResponseType.ACCEPT;
                if (accepted && quiet.active) {
                    MessagesPrefs.stop_warning ("warn-on-delete");
                }
                dialog.destroy ();
                if (accepted) {
                    on_accept ();
                }
            });
            dialog.present ();
        }

        private void confirm_delete_message (string id) {
            confirm (_("Supprimer ce message de Boomerang ?"),
                     _("Le message reste sur l'iPhone, car iOS ne permet pas de supprimer un "
                     + "message par Bluetooth. Il ne réapparaîtra pas dans Boomerang."),
                     () => daemon.call.begin ("DeleteMessage", new Variant ("(s)", id)));
        }

        private void confirm_delete_thread (string id, string title, bool always = false) {
            confirm (_("Supprimer la conversation avec %s ?").printf (title),
                     _("Les messages restent sur l'iPhone et ne réapparaîtront pas dans Boomerang. "
                     + "Les prochains messages s'afficheront normalement."),
                     () => daemon.call.begin ("DeleteConversation", new Variant ("(s)", id)), always);
        }

        private const string[] QUICK_REACTIONS = { "❤️", "👍", "👎", "😂", "‼️", "❓" };

        /* Reactions on a message: emojis grouped with a count, who reacted in the tooltip. */
        private Gtk.Widget? reaction_badge (VariantDict d, bool outgoing) {
            var list = d.lookup_value ("reactions", new VariantType ("a(ssbb)"));
            if (list == null || list.n_children () == 0) {
                return null;
            }
            var order = new GenericArray<string> ();
            var counts = new HashTable<string, int> (str_hash, str_equal);
            var tip = new StringBuilder ();
            bool pending = false;
            for (size_t i = 0; i < list.n_children (); i++) {
                string emoji, name;
                bool mine, waiting;
                list.get_child (i, "(ssbb)", out emoji, out name, out mine, out waiting);
                if (!counts.contains (emoji)) {
                    order.add (emoji);
                    counts[emoji] = 0;
                }
                counts[emoji] = counts[emoji] + 1;
                if (tip.len > 0) {
                    tip.append ("\n");
                }
                tip.append (waiting ? _("%s : %s (envoi…)").printf (name, emoji)
                                    : _("%s : %s").printf (name, emoji));
                pending = pending || waiting;
            }
            var text = new StringBuilder ();
            foreach (var emoji in order.data) {
                if (text.len > 0) {
                    text.append (" ");
                }
                text.append (emoji);
                if (counts[emoji] > 1) {
                    text.append ("\u2009%d".printf (counts[emoji]));
                }
            }
            var pill = new Gtk.Label (text.str) {
                valign = Gtk.Align.START,
                halign = outgoing ? Gtk.Align.START : Gtk.Align.END,
                tooltip_text = tip.str,
                can_target = true
            };
            pill.add_css_class ("reaction-badge");
            if (pending) {
                pill.add_css_class ("pending");
            }
            pill.update_property (Gtk.AccessibleProperty.LABEL, tip.str, -1);
            return pill;
        }

        /* The iPhone lists only the first 120 characters of an unread message; the whole text
           comes by downloading it, which marks it read on the iPhone. */
        private void confirm_read_full (string id, Gtk.Button button) {
            if (!MessagesPrefs.warns ("warn-on-read-full")) {
                read_full.begin (id, button);
                return;
            }
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                _("Lire le message en entier ?"),
                _("L'iPhone transmet seulement les 120 premiers caractères d'un message non lu. "
                  + "Pour récupérer la suite, Boomerang doit télécharger le message : il sera "
                  + "alors marqué comme lu sur l'iPhone."),
                Config.APP_ID + ".Messages", Gtk.ButtonsType.CANCEL) {
                transient_for = get_root () as Gtk.Window,
                modal = true
            };
            var quiet = new Gtk.CheckButton.with_label (_("Ne plus afficher"));
            dialog.custom_bin.append (quiet);
            var go = dialog.add_button (_("Tout lire"), Gtk.ResponseType.ACCEPT);
            go.add_css_class (Granite.CssClass.SUGGESTED);
            dialog.response.connect ((response) => {
                var accepted = response == Gtk.ResponseType.ACCEPT;
                if (accepted && quiet.active) {
                    MessagesPrefs.stop_warning ("warn-on-read-full");
                }
                dialog.destroy ();
                if (accepted) {
                    read_full.begin (id, button);
                }
            });
            dialog.present ();
        }

        private async void read_full (string id, Gtk.Button button) {
            button.sensitive = false;
            button.label = _("Récupération…");
            var ok = yield daemon.call ("ReadFullText", new Variant ("(s)", id));
            if (!ok) {
                button.sensitive = true;
                button.label = _("Tout lire");
                toast.title = _("Texte complet indisponible pour l'instant");
                toast.send_notification ();
            }
        }

        /* A reaction leaves as an SMS in the iPhone's words: say so until told not to. */
        private void react_to (string id, string emoji) {
            if (!MessagesPrefs.warns ("warn-on-reaction")) {
                send_reaction.begin (id, emoji);
                return;
            }
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                _("Réagir par SMS ?"),
                _("Le Bluetooth transmet seulement du texte : Boomerang envoie la réaction en "
                  + "SMS, par exemple « A adoré « à demain » ». Un iPhone récent peut l'afficher "
                  + "comme une réaction ; les autres téléphones affichent ce texte tel quel."),
                Config.APP_ID + ".Messages", Gtk.ButtonsType.CANCEL) {
                transient_for = get_root () as Gtk.Window,
                modal = true
            };
            var quiet = new Gtk.CheckButton.with_label (_("Ne plus afficher"));
            dialog.custom_bin.append (quiet);
            var go = dialog.add_button (_("Réagir %s").printf (emoji), Gtk.ResponseType.ACCEPT);
            go.add_css_class (Granite.CssClass.SUGGESTED);
            dialog.response.connect ((response) => {
                var accepted = response == Gtk.ResponseType.ACCEPT;
                if (accepted && quiet.active) {
                    MessagesPrefs.stop_warning ("warn-on-reaction");
                }
                dialog.destroy ();
                if (accepted) {
                    send_reaction.begin (id, emoji);
                }
            });
            dialog.present ();
        }

        private async void send_reaction (string id, string emoji) {
            var ok = yield daemon.call_send ("SendReaction", new Variant ("(ss)", id, emoji));
            if (!ok) {
                toast.title = _("Réaction non envoyée");
                toast.send_notification ();
            }
        }

        /* A reaction to a message Boomerang does not have (sent from the iPhone): one short line. */
        private Gtk.Widget reaction_note (VariantDict d) {
            var note = new Gtk.Label (dict_string (d, "note")) {
                halign = Gtk.Align.CENTER,
                wrap = true,
                justify = Gtk.Justification.CENTER,
                margin_top = 6,
                margin_bottom = 2,
                tooltip_text = long_time (dict_int64 (d, "time"))
            };
            note.add_css_class (Granite.CssClass.DIM);
            note.add_css_class (Granite.CssClass.SMALL);
            return note;
        }

        /* Sync (Ctrl+R): list the iPhone's messages again, full texts, contacts and calls. */
        private async void run_sync () {
            try {
                var count = yield daemon.sync_all ();
                toast.title = count == 0 ? _("Synchronisé : aucun nouveau message")
                    : ngettext ("Synchronisé : %u nouveau message", "Synchronisé : %u nouveaux messages",
                                count).printf (count);
            } catch (Error e) {
                DBusError.strip_remote_error (e);
                toast.title = _("Synchronisation impossible : %s").printf (e.message);
            }
            toast.send_notification ();
            yield reload_threads ();
        }

        private static string attachment_text () {
            return "📎 " + _("Pièce jointe, visible sur l'iPhone");
        }

        private static string attachment_hint () {
            return _("Par Bluetooth, l'iPhone transmet le texte des messages, pas les photos ni les fichiers.");
        }

        private const string MESSAGE_KEY = "boomerang-message";
        private const string STATUS_KEY = "boomerang-status";

        /* One action group, one right-click gesture and one key handler on the conversation for
           all its bubbles, the message id as the actions' parameter. Handlers are methods (no
           closure holds the view or a bubble), so a bubble removed from the view is freed. */
        private void install_bubble_menu () {
            var actions = new SimpleActionGroup ();
            var react = new SimpleAction ("react", new VariantType ("(ss)"));
            react.activate.connect (on_react_action);
            actions.add_action (react);
            var react_other = new SimpleAction ("react-other", VariantType.STRING);
            react_other.activate.connect (on_react_other_action);
            actions.add_action (react_other);
            var copy = new SimpleAction ("copy", VariantType.STRING);
            copy.activate.connect (on_copy_action);
            actions.add_action (copy);
            var remove = new SimpleAction ("delete", VariantType.STRING);
            remove.activate.connect (on_delete_action);
            actions.add_action (remove);
            bubbles.insert_action_group ("bubble", actions);

            // Caught before the label's own menu (Cut/Paste/Delete make no sense here).
            var click = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
            click.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            click.pressed.connect (on_bubbles_pressed);
            bubbles.add_controller (click);
            var keys = new Gtk.EventControllerKey ();
            keys.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            keys.key_pressed.connect (on_bubbles_key);
            bubbles.add_controller (keys);
        }

        /* The bubble label a widget belongs to (itself, or a parent up to the conversation). */
        private Gtk.Widget? bubble_of (Gtk.Widget? widget) {
            for (var w = widget; w != null && w != bubbles; w = w.get_parent ()) {
                if (w.get_data<string> (MESSAGE_KEY) != null) {
                    return w;
                }
            }
            return null;
        }

        private void on_bubbles_pressed (Gtk.GestureClick click, int n, double x, double y) {
            var label = bubble_of (bubbles.pick (x, y, Gtk.PickFlags.DEFAULT));
            if (label == null) {
                return;
            }
            click.set_state (Gtk.EventSequenceState.CLAIMED);
            Graphene.Point at;
            if (!bubbles.compute_point (label, Graphene.Point () { x = (float) x, y = (float) y }, out at)) {
                at = Graphene.Point () { x = 0, y = 0 };
            }
            open_bubble_menu (label, (int) at.x, (int) at.y);
        }

        private bool on_bubbles_key (Gtk.EventControllerKey keys, uint keyval, uint code,
                                     Gdk.ModifierType state) {
            if (!is_menu_key (keyval, state)) {
                return false;
            }
            var label = bubble_of ((get_root () as Gtk.Window)?.get_focus ());
            if (label == null) {
                return false;
            }
            open_bubble_menu (label, label.get_width () / 2, label.get_height () / 2);
            return true;
        }

        private void open_bubble_menu (Gtk.Widget label, int x, int y) {
            var id = label.get_data<string> (MESSAGE_KEY);
            var status = label.get_data<string> (STATUS_KEY) ?? "";
            if (status == "sending") {
                return;
            }
            var target = new Variant.string (id);
            var menu = new GLib.Menu ();
            if (current_can_send && !current_group && status != "failed"
                && daemon.get_bool ("ReactionsSend")) {
                var react_menu = new GLib.Menu ();
                foreach (var emoji in QUICK_REACTIONS) {
                    var item = new GLib.MenuItem (emoji, null);
                    item.set_action_and_target_value ("bubble.react", new Variant ("(ss)", id, emoji));
                    react_menu.append_item (item);
                }
                var other = new GLib.MenuItem (_("Autre emoji…"), null);
                other.set_action_and_target_value ("bubble.react-other", target);
                react_menu.append_item (other);
                menu.append_submenu (_("Réagir"), react_menu);
            }
            var copy = new GLib.MenuItem (_("Copier"), null);
            copy.set_action_and_target_value ("bubble.copy", target);
            menu.append_item (copy);
            var remove = new GLib.MenuItem (_("Supprimer de Boomerang…"), null);
            remove.set_action_and_target_value ("bubble.delete", target);
            menu.append_item (remove);
            var popover = new Gtk.PopoverMenu.from_model (menu) {
                has_arrow = false,
                pointing_to = { x, y, 1, 1 }
            };
            popover.set_parent (label);
            popover.closed.connect (unparent_later);
            popover.popup ();
        }

        /* A popover closed: off its parent once its closing is over. */
        private static void unparent_later (Gtk.Popover popover) {
            Idle.add (() => {
                popover.unparent ();
                return Source.REMOVE;
            });
        }

        private void on_react_action (SimpleAction action, Variant? param) {
            string id, emoji;
            param.get ("(ss)", out id, out emoji);
            react_to (id, emoji);
        }

        private void on_react_other_action (SimpleAction action, Variant? param) {
            var id = param.get_string ();
            var shown = bubble_index[id];
            var anchor = shown != null ? find_label (shown, id) : null;
            if (anchor == null) {
                return;
            }
            var chooser = new Gtk.EmojiChooser ();
            chooser.set_data<string> (MESSAGE_KEY, id);
            chooser.set_parent (anchor);
            chooser.emoji_picked.connect (on_emoji_picked);
            chooser.closed.connect (unparent_later);
            chooser.popup ();
        }

        private void on_emoji_picked (Gtk.EmojiChooser chooser, string emoji) {
            react_to (chooser.get_data<string> (MESSAGE_KEY), emoji);
        }

        /* The label of message id inside the widget shown for it. */
        private static Gtk.Widget? find_label (Gtk.Widget widget, string id) {
            if (widget.get_data<string> (MESSAGE_KEY) == id) {
                return widget;
            }
            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var found = find_label (child, id);
                if (found != null) {
                    return found;
                }
            }
            return null;
        }

        private void on_copy_action (SimpleAction action, Variant? param) {
            var id = param.get_string ();
            for (int i = 0; i < thread_ids.length; i++) {
                if (thread_ids[i] == id) {
                    get_clipboard ().set_text (thread_bodies[i]);
                    return;
                }
            }
        }

        private void on_delete_action (SimpleAction action, Variant? param) {
            confirm_delete_message (param.get_string ());
        }

        private Gtk.Widget bubble (VariantDict d, bool outgoing, string? sender, bool follows,
                                   bool ends_run, bool last_sent) {
            if (dict_string (d, "note") != "") {
                return reaction_note (d);
            }
            var body = dict_string (d, "body");
            var complete = dict_bool (d, "complete");
            // A photo, a video or a file: Bluetooth (MAP) carries the text only.
            var attachment = dict_bool (d, "attachment");
            var only_file = attachment && body.strip () == "";
            if (only_file) {
                complete = true;
            }
            var label = new Gtk.Label (only_file ? "<i>%s</i>".printf (Markup.escape_text (attachment_text ()))
                                                 : linkify (complete ? body : body + "…")) {
                use_markup = true,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                selectable = true,
                xalign = 0
            };
            label.add_css_class ("bubble");
            label.add_css_class (outgoing ? "outgoing" : "incoming");
            if (ends_run) {
                label.add_css_class ("run-end");
            }
            // The menu (right click, Menu key, Maj+F10) is handled once for every bubble by the
            // conversation itself (install_bubble_menu): the label only says which message it shows.
            label.set_data<string> (MESSAGE_KEY, dict_string (d, "id"));
            label.set_data<string> (STATUS_KEY, dict_string (d, "status"));
            label.activate_link.connect ((uri) => {
                if (uri.has_prefix ("tel:")) {
                    start_conversation (uri.substring (4));
                    return true;
                }
                return false;  // web and mail links: the default handler opens them
            });
            var time = dict_int64 (d, "time");
            var tip = long_time (time);
            if (!complete) {
                tip += _("\nDébut du message : le texte complet sera récupéré une fois le message "
                       + "lu sur l'iPhone.");
            }
            if (dict_string (d, "source") == "ancs") {
                tip += _("\nReçu par notification");
            }
            if (only_file) {
                tip += "\n" + attachment_hint ();
            }
            label.tooltip_text = tip;
            // Orca reads the text, then who wrote it and when.
            var who = outgoing ? _("Vous") : dict_string (d, "sender");
            label.update_property (Gtk.AccessibleProperty.DESCRIPTION,
                                   who != "" ? _("%s, %s").printf (who, long_time (time)) : long_time (time), -1);

            Gtk.Widget shown = label;
            var badge = reaction_badge (d, outgoing);
            if (badge != null) {
                // iMessage-like: a small pill over the top corner of the bubble.
                label.margin_top = 12;
                var overlay = new Gtk.Overlay () { child = label };
                overlay.add_overlay (badge);
                shown = overlay;
            }

            var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                halign = outgoing ? Gtk.Align.END : Gtk.Align.START,
                margin_top = follows ? 0 : 6,
                // Long messages wrap at the width of the thread, short of the other side.
                margin_start = outgoing ? 80 : 0,
                margin_end = outgoing ? 0 : 80
            };
            if (sender != null && sender != "") {
                var name = new Gtk.Label (sender) { xalign = 0, margin_start = 12 };
                name.add_css_class (Granite.CssClass.DIM);
                name.add_css_class (Granite.CssClass.SMALL);
                column.append (name);
            }
            column.append (shown);
            if (only_file) {
                label.add_css_class ("attachment");
            } else if (attachment) {
                var file = new Gtk.Label (attachment_text ()) {
                    halign = outgoing ? Gtk.Align.END : Gtk.Align.START,
                    margin_start = 6,
                    margin_end = 6,
                    tooltip_text = attachment_hint ()
                };
                file.add_css_class (Granite.CssClass.DIM);
                file.add_css_class (Granite.CssClass.SMALL);
                column.append (file);
            }
            var url = first_url (body);
            if (url != null && daemon.get_bool ("LinkPreviews")) {
                var slot = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                    halign = outgoing ? Gtk.Align.END : Gtk.Align.START
                };
                column.append (slot);
                fill_preview.begin (url, slot);
            }
            var status = dict_string (d, "status");
            var id = dict_string (d, "id");
            if (outgoing && status == "sending") {
                label.add_css_class ("sending");
                var state = new Gtk.Label (_("Envoi…")) { xalign = 1, margin_end = 6 };
                state.add_css_class (Granite.CssClass.SMALL);
                state.add_css_class (Granite.CssClass.DIM);
                column.append (state);
            } else if (outgoing && status == "failed") {
                label.add_css_class ("failed");
                var state = new Gtk.Label (_("Non envoyé")) { margin_end = 6 };
                state.add_css_class (Granite.CssClass.SMALL);
                state.add_css_class (Granite.CssClass.ERROR);
                var again = new Gtk.Button.with_label (_("Réessayer"));
                again.add_css_class ("flat");
                again.add_css_class (Granite.CssClass.SMALL);
                again.clicked.connect (() => retry_message (id));
                var drop = new Gtk.Button.with_label (_("Supprimer"));
                drop.add_css_class ("flat");
                drop.add_css_class (Granite.CssClass.SMALL);
                drop.clicked.connect (() => daemon.call.begin ("DiscardMessage", new Variant ("(s)", id)));
                var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { halign = Gtk.Align.END };
                line.append (state);
                line.append (again);
                line.append (drop);
                column.append (line);
            }
            if (last_sent && status != "failed" && dict_string (d, "source") == "map") {
                // The iPhone lists it among its sent messages: Boomerang has checked it left.
                var sent = new Gtk.Label (_("Envoyé")) {
                    halign = Gtk.Align.END,
                    margin_end = 6,
                    tooltip_text = _("L'iPhone confirme l'envoi")
                };
                sent.add_css_class (Granite.CssClass.DIM);
                sent.add_css_class (Granite.CssClass.SMALL);
                column.append (sent);
            }
            if (!outgoing && !complete && dict_string (d, "source") == "map") {
                var more = new Gtk.Button.with_label (_("Tout lire")) {
                    halign = Gtk.Align.START,
                    tooltip_text = _("Récupérer le texte complet (le message sera marqué comme lu sur l'iPhone)")
                };
                more.add_css_class ("flat");
                more.add_css_class (Granite.CssClass.SMALL);
                more.clicked.connect ((button) => confirm_read_full (id, button));
                column.append (more);
            }
            return column;
        }

        private static string? first_url (string text) {
            try {
                MatchInfo info;
                if (new Regex ("https?://[^\\s<>\"]+").match (text, 0, out info)) {
                    var url = info.fetch (0);
                    while (url.length > 0 && ".,;:!?)]»'".contains (url.substring (url.length - 1))) {
                        url = url.substring (0, url.length - 1);
                    }
                    return url;
                }
            } catch (Error e) {
                // no link
            }
            return null;
        }

        /* Title, site and picture of a link, asked once to boomerangd (opt-in in Réglages). */
        private async void fill_preview (string url, Gtk.Box slot) {
            var preview = previews[url];
            if (preview == null) {
                preview = yield daemon.call_dict ("GetLinkPreview", new Variant ("(s)", url));
                if (preview == null) {
                    return;
                }
                previews[url] = preview;
            }
            var d = new VariantDict (preview);
            var title = dict_string (d, "title");
            if (title == "") {
                return;
            }
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 260 };
            var image = dict_string (d, "image");
            if (image != "" && FileUtils.test (image, FileTest.EXISTS)) {
                var picture = new Gtk.Picture () {
                    content_fit = Gtk.ContentFit.COVER,
                    height_request = 130,
                    can_shrink = true
                };
                picture.add_css_class ("link-picture");
                card.append (picture);
                var texture = preview_textures[image];
                if (texture != null) {
                    picture.paintable = texture;
                } else {
                    load_preview_picture.begin (image, picture);
                }
            }
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                margin_top = 6, margin_bottom = 8, margin_start = 10, margin_end = 10
            };
            var name = new Gtk.Label (title) {
                xalign = 0, wrap = true, lines = 2, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 36
            };
            name.add_css_class ("link-title");
            text.append (name);
            var site = new Gtk.Label (dict_string (d, "site")) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            site.add_css_class (Granite.CssClass.DIM);
            site.add_css_class (Granite.CssClass.SMALL);
            text.append (site);
            card.append (text);
            var button = new Gtk.Button () { child = card, tooltip_text = url };
            button.add_css_class ("link-card");
            button.clicked.connect (() => new Gtk.UriLauncher (url).launch.begin (get_root () as Gtk.Window, null));
            slot.append (button);
        }

        // Link pictures decoded once, reduced to the card's width (twice, for HiDPI screens),
        // away from the main thread: a page's picture can be several megapixels.
        private const int PREVIEW_WIDTH = 520;
        private const uint PREVIEW_CACHE = 64;
        private static HashTable<string, Gdk.Texture> preview_textures =
            new HashTable<string, Gdk.Texture> (str_hash, str_equal);

        private static async void load_preview_picture (string path, Gtk.Picture picture) {
            SourceFunc done = load_preview_picture.callback;
            Gdk.Texture? texture = null;
            new Thread<void*> ("link-picture", () => {
                try {
                    int width, height;
                    Gdk.Pixbuf.get_file_info (path, out width, out height);
                    // Decoded straight at the reduced size; a smaller picture is never enlarged.
                    var pixbuf = width > PREVIEW_WIDTH
                                 ? new Gdk.Pixbuf.from_file_at_scale (path, PREVIEW_WIDTH, -1, true)
                                 : new Gdk.Pixbuf.from_file (path);
                    texture = new Gdk.MemoryTexture (
                        pixbuf.width, pixbuf.height,
                        pixbuf.has_alpha ? Gdk.MemoryFormat.R8G8B8A8 : Gdk.MemoryFormat.R8G8B8,
                        pixbuf.read_pixel_bytes (), pixbuf.rowstride);
                } catch (Error e) {
                    // unreadable picture: the card shows its text only
                }
                Idle.add ((owned) done);
                return null;
            });
            yield;
            if (texture == null) {
                picture.visible = false;
                return;
            }
            if (preview_textures.size () >= PREVIEW_CACHE) {
                preview_textures.remove_all ();  // a long scroll through many links: start again
            }
            preview_textures[path] = texture;
            picture.paintable = texture;
        }

        // --- compose -----------------------------------------------------------------

        private void update_compose () {
            if (current == null) {
                return;
            }
            var state = daemon.get_string ("MessagesState");
            var send = daemon.get_string ("MessagesSend");
            string limit = "";
            if (current_group) {
                limit = _("Vous pouvez lire les conversations de groupe ici, mais il faut y répondre "
                        + "depuis l'iPhone : par Bluetooth, l'iPhone envoie un SMS à un seul "
                        + "destinataire.");
            } else if (!current_can_send) {
                limit = _("Pas de numéro de téléphone connu pour cette conversation : "
                        + "répondez depuis l'iPhone.");
            }
            limit_label.label = limit;
            compose_stack.visible_child_name = limit == "" ? "compose" : "limit";
            // Hints only: the field always stays usable; a message that cannot
            // leave is kept in the thread with "Réessayer".
            if (state != "ready") {
                send_hint.label = _("L'iPhone n'est pas connecté pour les messages : les messages que "
                                  + "vous écrivez sont conservés ici et pourront être renvoyés.");
            } else if (send == "no") {
                send_hint.label = _("Le dernier envoi a été refusé par l'iPhone. Vous pouvez réessayer.");
            } else if (send == "unknown") {
                send_hint.label = _("Premier envoi depuis ce PC : l'iPhone envoie ce message en SMS.");
            } else {
                send_hint.label = "";
            }
            send_hint.visible = send_hint.label != "";
        }

        private string entry_text () {
            return entry.text ();
        }

        private void show_send_progress (double fraction) {
            if (send_bar_hide != 0) {
                Source.remove (send_bar_hide);
                send_bar_hide = 0;
            }
            send_bar.visible = true;
            send_bar.fraction = fraction.clamp (0.0, 1.0);
            if (fraction >= 1.0) {
                send_bar_hide = Timeout.add (600, () => {
                    send_bar.visible = false;
                    send_bar_hide = 0;
                    return Source.REMOVE;
                });
            }
        }

        private void send_finished (bool ok) {
            if (!ok) {
                if (send_bar_hide != 0) {
                    Source.remove (send_bar_hide);
                    send_bar_hide = 0;
                }
                send_bar.visible = false;
                toast.title = _("Message non envoyé mais conservé : cliquez sur « Réessayer »");
                toast.send_notification ();
            }
        }

        private void retry_message (string id) {
            show_send_progress (0.02);
            daemon.call_send.begin ("RetryMessage", new Variant ("(s)", id), (obj, res) => {
                send_finished (daemon.call_send.end (res));
            });
        }

        private void send () {
            var text = entry_text ();
            if (text == "" || current == null) {
                return;
            }
            if (text.char_count () > 2000) {
                toast.title = _("Message trop long (2 000 caractères au plus)");
                toast.send_notification ();
                return;
            }
            // The daemon stores the message before sending it: the field can be
            // cleared at once, the text survives in the thread even on failure.
            loading_draft = true;
            entry.buffer.text = "";
            loading_draft = false;
            if (draft_timer != 0) {
                Source.remove (draft_timer);
                draft_timer = 0;
            }
            daemon.call.begin ("SetDraft", new Variant ("(ss)", current, ""));
            show_send_progress (0.02);
            daemon.call_send.begin ("SendMessage", new Variant ("(ss)", current, text), (obj, res) => {
                send_finished (daemon.call_send.end (res));
            });
            entry.grab_focus ();
        }
    }
}
