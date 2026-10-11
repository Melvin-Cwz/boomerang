// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Messages: conversations on the left, the selected thread as bubbles on the
 * right (sent on the right in the accent colour, received on the left), the
 * sender's name above received bubbles in group threads, and a reply field
 * when the iPhone lets the PC send, otherwise a line explaining why not.
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

        private Gtk.Label name_label;
        private Gtk.Image pin;
        private Gtk.Label time_label;
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
            time_label = new Gtk.Label ("");
            time_label.add_css_class (Granite.CssClass.DIM);
            time_label.add_css_class (Granite.CssClass.SMALL);
            snippet_label = new Gtk.Label ("") {
                xalign = 0,
                yalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                lines = 2,
                ellipsize = Pango.EllipsizeMode.END,
                width_chars = 20,
                max_width_chars = 30
            };
            snippet_label.add_css_class (Granite.CssClass.DIM);

            dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.CENTER
            };
            dot.add_css_class ("unread-dot");
            var dot_slot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { width_request = 12 };
            dot_slot.append (dot);

            avatar = new Avatar (40) { valign = Gtk.Align.START };

            pin = new Gtk.Image.from_icon_name ("view-pin-symbolic") {
                pixel_size = 12,
                visible = false,
                tooltip_text = _("Épinglée")
            };
            pin.add_css_class (Granite.CssClass.DIM);
            var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            top.append (name_label);
            top.append (pin);
            top.append (time_label);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true };
            text.append (top);
            text.append (snippet_label);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 6,
                margin_end = 12
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
            pin.visible = pinned;
            refresh_name ();
            avatar_path = dict_string (d, "avatar");
            avatar.show_person (title, avatar_path, is_group);
            time_label.label = short_time (dict_int64 (d, "time"));
            var snippet = dict_string (d, "snippet").replace ("\n", " ");
            draft = dict_string (d, "draft");
            var people = d.lookup_value ("participants", new VariantType ("as"));
            var list = people != null ? people.dup_strv () : new string[0];
            number = list.length == 1 && !list[0].contains ("@") && !list[0].has_prefix ("name:")
                     ? list[0] : "";
            if (draft != "") {
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
            update_property (Gtk.AccessibleProperty.LABEL, a11y, -1);
        }

        /* The nickname and emoji chosen in Personnaliser, else the contact's name. */
        public void refresh_name () {
            name_label.label = ThreadStyle.load (thread_id).shown_name (title);
        }
    }

    /* One search result: a conversation whose name matches, or a message with its excerpt. */
    public class SearchRow : Gtk.ListBoxRow {
        public string thread_id { get; private set; }
        public string message { get; private set; }
        public string title { get; private set; }
        private string avatar_path;
        private bool is_group;

        public SearchRow (VariantDict d) {
            thread_id = dict_string (d, "thread");
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
                update_property (Gtk.AccessibleProperty.LABEL, _("Conversation avec %s").printf (title), -1);
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

    public class MessagesView : Gtk.Box {
        public Daemon daemon { get; construct; }

        private Gtk.ListBox thread_list;
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
        private Gtk.MenuButton style_button;
        private Gtk.CssProvider style_css = new Gtk.CssProvider ();
        private string? applied_css = null;
        // The standalone Messages app: the panes carry elementary header bars with the window buttons.
        public bool standalone { get; construct; default = false; }
        private Gtk.HeaderBar thread_bar;
        private Gtk.Box thread_title_box;
        private Gtk.Box header_end;
        private Gtk.ToggleButton find_button;
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
        private int last_count = 0;
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
        private string current_number = "";  // opened from "new message", no message yet
        private Gtk.MenuButton new_button;
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

        public MessagesView (Daemon daemon, bool standalone = false) {
            Object (daemon: daemon, standalone: standalone, orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        }

        /* A button at the end of the conversation header (the standalone app's Guide). */
        public void add_header_end (Gtk.Widget widget) {
            header_end.append (widget);
        }

        construct {
            // --- conversation list ---
            thread_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.SINGLE };
            thread_list.add_css_class ("navigation-sidebar");
            thread_list.set_header_func ((row, before) => {
                var here = row as ThreadRow;
                var above = before as ThreadRow;
                if (here != null && here.pinned && above == null) {
                    var label = new Gtk.Label (_("Épinglées")) {
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
            thread_list.row_selected.connect ((row) => {
                var thread = row as ThreadRow;
                if (thread != null && (thread.thread_id != current || current_new)) {
                    show_thread (thread);
                }
            });
            var list_scroll = new Gtk.ScrolledWindow () {
                child = thread_list,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            var list_empty = new Granite.Placeholder (_("Aucune conversation")) {
                description = _("Les messages de l'iPhone apparaîtront ici."),
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
            var sidebar_title = new Gtk.Label (_("Conversations")) { xalign = 0, hexpand = true };
            sidebar_title.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
            Gtk.Widget sidebar_header;
            if (standalone) {
                // As in elementary's Mail: the sidebar's header holds the left window buttons.
                var bar = new Gtk.HeaderBar () {
                    show_title_buttons = true,
                    decoration_layout = MainWindow.split_layout (true),
                    title_widget = new Gtk.Label ("") { visible = false }
                };
                bar.add_css_class ("flat");
                bar.add_css_class ("brand");
                bar.pack_start (sidebar_title);
                bar.pack_end (new_button);
                bar.pack_end (build_sync_button ());
                Gtk.Settings.get_default ().notify["gtk-decoration-layout"].connect (() => {
                    bar.decoration_layout = MainWindow.split_layout (true);
                });
                sidebar_header = bar;
            } else {
                var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                    margin_top = 6,
                    margin_start = 12,
                    margin_end = 6
                };
                box.append (sidebar_title);
                box.append (build_sync_button ());
                box.append (new_button);
                sidebar_header = box;
            }

            search = new Gtk.SearchEntry () {
                placeholder_text = _("Rechercher"),
                margin_top = 6,
                margin_start = 12,
                margin_end = 12,
                margin_bottom = 6
            };
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
            add_controller (shortcuts);

            var sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 280 };
            sidebar.append (sidebar_header);
            sidebar.append (search);
            sidebar.add_css_class ("messages-sidebar");
            sidebar.append (banner);
            sidebar.append (list_stack);

            // --- thread ---
            thread_title = new Gtk.Label ("") { ellipsize = Pango.EllipsizeMode.END };
            thread_title.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
            thread_subtitle = new Gtk.Label ("") { ellipsize = Pango.EllipsizeMode.END };
            thread_subtitle.add_css_class (Granite.CssClass.DIM);
            thread_subtitle.add_css_class (Granite.CssClass.SMALL);
            // Conversation header: an elementary header bar, small picture and name in the middle.
            // In the Messages app this bar is the window's title bar: as low as the others.
            thread_avatar = new Avatar (standalone ? 24 : 32);
            // The app's bar is low: name and subtitle side by side there.
            var titles = new Gtk.Box (standalone ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL,
                                      standalone ? 8 : 0) { valign = Gtk.Align.CENTER };
            thread_title.xalign = 0;
            thread_subtitle.xalign = 0;
            titles.append (thread_title);
            titles.append (thread_subtitle);
            thread_title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { visible = false };
            thread_title_box.append (thread_avatar);
            thread_title_box.append (titles);
            thread_call = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
            thread_bar = new Gtk.HeaderBar () {
                visible = standalone,  // in the main window, only once a conversation is open
                show_title_buttons = standalone,
                title_widget = thread_title_box
            };
            thread_bar.add_css_class ("flat");
            thread_bar.add_css_class ("thread-bar");
            if (standalone) {
                thread_bar.add_css_class ("brand");
                thread_bar.decoration_layout = MainWindow.split_layout (false);
                Gtk.Settings.get_default ().notify["gtk-decoration-layout"].connect (() => {
                    thread_bar.decoration_layout = MainWindow.split_layout (false);
                });
            }

            bubbles = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 12,
                margin_end = 12,
                valign = Gtk.Align.END
            };
            bubble_scroll = new Gtk.ScrolledWindow () {
                child = bubbles,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            bubble_scroll.add_css_class ("thread-scroll");

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
            find_button = new Gtk.ToggleButton () {
                icon_name = "edit-find-symbolic",
                tooltip_text = _("Rechercher dans la conversation (Ctrl+F)"),
                valign = Gtk.Align.CENTER
            };
            find_button.add_css_class ("flat");
            find_button.bind_property ("active", find_bar, "search-mode-enabled",
                                       BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);

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
            style_button = new Gtk.MenuButton () {
                icon_name = "boomerang-palette-symbolic",
                tooltip_text = _("Personnaliser la conversation"),
                valign = Gtk.Align.CENTER,
                visible = false
            };
            style_button.add_css_class ("flat");
            style_button.set_create_popup_func ((button) => {
                if (current == null) {
                    return;
                }
                var editor = new ThreadStyleEditor (current, ThreadStyle.load_raw (current),
                                                    get_root () as Gtk.Window, daemon);
                editor.changed.connect (apply_style);
                button.popover = new Gtk.Popover () { child = editor };
            });
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), style_css,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
            // pack_end goes right to left: the app's Guide stays at the far end.
            header_end = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
            thread_bar.pack_start (style_button);
            thread_bar.pack_end (header_end);
            thread_bar.pack_end (thread_call);
            thread_bar.pack_end (find_button);
            find_button.visible = false;
            // Thin sending bar under the header, as in Apple's Messages.
            send_bar = new Gtk.ProgressBar () { visible = false };
            send_bar.add_css_class ("send-bar");
            send_bar.update_property (Gtk.AccessibleProperty.LABEL, _("Envoi du message"), -1);
            thread_box.append (find_bar);
            thread_box.append (scroll_overlay);
            thread_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            thread_box.append (compose_stack);

            var no_thread = new Granite.Placeholder (_("Messages")) {
                description = _("Choisissez une conversation."),
                icon = new ThemedIcon (Config.APP_ID + ".Messages")
            };
            content_stack = new Gtk.Stack () { hexpand = true };
            content_stack.add_named (no_thread, "none");
            content_stack.add_named (thread_box, "thread");

            toast = new Granite.Toast ("");
            var overlay = new Gtk.Overlay () { child = content_stack, hexpand = true, vexpand = true };
            overlay.add_overlay (toast);
            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
            right.add_css_class ("view");
            right.append (thread_bar);
            right.append (send_bar);
            right.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            right.append (overlay);

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
                if (stick_bottom) {
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
                stick_bottom = vadj.value >= vadj.upper - vadj.page_size - 24;
                if (stick_bottom) {
                    unseen = 0;
                }
                update_down ();
            });

            daemon.threads_changed.connect (() => reload_threads.begin ());
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

        /* Down to the newest message once the layout of this frame is done:
           a value set in the middle of an allocation is lost. */
        private void queue_stick () {
            if (stick_source != 0) {
                return;
            }
            stick_source = Idle.add (() => {
                stick_source = 0;
                if (stick_bottom) {
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
                style_css.load_from_string (css);
                applied_css = css;
            }
            // A conversation with its own colour tints its header bar (white text, as the brand bar).
            if (style.bubble != "") {
                thread_bar.add_css_class ("brand");
                thread_bar.add_css_class ("tinted");
            } else {
                thread_bar.remove_css_class ("tinted");
                if (!standalone) {
                    thread_bar.remove_css_class ("brand");
                }
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
            }
        }

        /* Title and subtitle of the open conversation, the nickname first when there is one. */
        private void show_names (ThreadStyle style) {
            thread_title.label = style.shown_name (current_title);
            thread_subtitle.label = current_group ? _("Conversation de groupe")
                                  : current_new ? _("Nouveau message")
                                  : style.nickname != "" ? current_title : "";
            thread_subtitle.visible = thread_subtitle.label != "";
        }

        /* Alt+↑/↓: the conversation above or below in the list. */
        private bool step_thread (int delta) {
            var selected = thread_list.get_selected_row ();
            var index = selected != null ? selected.get_index () + delta : 0;
            var row = thread_list.get_row_at_index (index) as ThreadRow;
            if (row == null) {
                return false;
            }
            thread_list.select_row (row);
            row.grab_focus ();
            return true;
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
            ThreadRow? to_select = null;
            var want = pending_open ?? current;

            // Reuse rows in order: keeps the selection and scrolling steady.
            int index = 0;
            foreach (var item in items) {
                var row = thread_list.get_row_at_index (index) as ThreadRow;
                if (row == null) {
                    row = new ThreadRow ();
                    var menu_row = row;
                    var click = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
                    click.pressed.connect ((n, x, y) => show_thread_menu (menu_row, x, y));
                    row.add_controller (click);
                    thread_list.append (row);
                }
                row.set_from (new VariantDict (item));
                if (row.thread_id == want) {
                    to_select = row;
                }
                index++;
            }
            Gtk.ListBoxRow? extra;
            while ((extra = thread_list.get_row_at_index (index)) != null) {
                thread_list.remove (extra);
            }
            thread_list.invalidate_headers ();
            if (search.text.strip () == "") {
                list_stack.visible_child_name = items.length > 0 ? "list" : "empty";
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

        // --- search ------------------------------------------------------------------

        private async void run_search () {
            var query = search.text.strip ();
            var serial = ++search_serial;
            if (query == "") {
                list_stack.visible_child_name = thread_list.get_row_at_index (0) != null ? "list" : "empty";
                return;
            }
            var items = yield daemon.call_list ("SearchMessages", new Variant ("(s)", query));
            if (serial != search_serial) {
                return;  // typed further in the meantime
            }
            Gtk.Widget? old;
            while ((old = search_list.get_first_child ()) != null) {
                search_list.remove (old);
            }
            foreach (var item in items) {
                search_list.append (new SearchRow (new VariantDict (item)));
            }
            if (items.length == 0) {
                search_empty.label = _("Aucun résultat pour « %s »").printf (query);
                list_stack.visible_child_name = "search-empty";
            } else {
                list_stack.visible_child_name = "search";
            }
        }

        /* Open the conversation of a result and bring the message into view. */
        private void open_search_hit (SearchRow hit) {
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
                    pending_scroll = null;
                    return Source.REMOVE;
                }
                Graphene.Point where = Graphene.Point () { x = 0, y = 0 };
                var placed = target.get_height () > 0
                             && target.compute_point (bubbles, Graphene.Point () { x = 0, y = 0 }, out where);
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
                adj.value = (where.y + bubbles.margin_top - adj.page_size / 3)
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
            var id = row.thread_id;
            var title = row.title;
            var pinned = row.pinned;
            var unread = row.unread > 0;

            var pin = menu_item (pinned ? _("Désépingler") : _("Épingler"));
            pin.clicked.connect (() => {
                popover.popdown ();
                daemon.call.begin ("PinThread", new Variant ("(sb)", id, !pinned));
            });
            box.append (pin);

            var read = menu_item (unread ? _("Marquer comme lu") : _("Marquer comme non lu"));
            read.tooltip_text = _("Dans Boomerang seulement : l'iPhone n'est pas modifié");
            read.clicked.connect (() => {
                popover.popdown ();
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

            var look = menu_item (_("Personnaliser…"));
            look.clicked.connect (() => {
                popover.popdown ();
                if (id != current) {
                    thread_list.select_row (row);
                    show_thread (row);
                }
                style_button.popup ();
            });
            box.append (look);

            var export = menu_item (_("Exporter…"));
            export.clicked.connect (() => {
                popover.popdown ();
                ConversationExport.run.begin (get_root () as Gtk.Window, daemon, id,
                                              ThreadStyle.load (id).shown_name (title));
            });
            box.append (export);

            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 3, margin_bottom = 3 });
            var remove = menu_item (_("Supprimer la conversation…"));
            remove.clicked.connect (() => {
                popover.popdown ();
                confirm_delete_thread (id, title);
            });
            box.append (remove);

            popover.set_parent (row);
            popover.closed.connect (() => Idle.add (() => {
                popover.unparent ();
                return Source.REMOVE;
            }));
            popover.popup ();
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
                last_count = 0;
                find_bar.search_mode_enabled = false;
            }
            next_unread = 0;
            thread_title_box.visible = true;
            thread_bar.visible = true;
            style_button.visible = true;
            find_button.visible = !is_new;
            thread_avatar.show_person (title, avatar, group);
            Gtk.Widget? old_call;
            while ((old_call = thread_call.get_first_child ()) != null) {
                thread_call.remove (old_call);
            }
            if (!group && can_send && current_number != "") {
                thread_call.append (new CallButton (daemon, current_number, toast));
            }
            content_stack.visible_child_name = "thread";
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
                thread_list.unselect_all ();
                var people = d.lookup_value ("participants", new VariantType ("as"));
                current_number = people != null && people.n_children () == 1
                                 ? people.get_child_value (0).get_string () : "";
                show_info (id, dict_string (d, "name"), dict_string (d, "avatar"), false,
                           dict_bool (d, "can_send"), true);
                entry.grab_focus ();
            });
        }

        private async void load_messages (string thread, bool group, bool changed) {
            bool ok;
            var items = yield daemon.try_list ("GetMessages", new Variant ("(s)", thread), out ok);
            if (thread != current || !ok) {
                return;  // (failed call: the bubbles on screen stay)
            }
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
            if (!changed && !stick_bottom && items.length > last_count) {
                for (int i = int.max (last_count, 0); i < items.length; i++) {
                    if (!dict_bool (new VariantDict (items[i]), "outgoing")) {
                        unseen++;
                    }
                }
            }
            last_count = items.length;

            // Redraw only what changed: a new message adds its bubble at the end, a change
            // further up redraws from there on. A redraw would also destroy an open context
            // menu (focus changes when it opens re-run this on Wayland).
            var head = "%s|%s|%s".printf (thread, group ? "g" : "1", unread_id);
            string[] sigs = {};
            foreach (var item in items) {
                var d = new VariantDict (item);
                // Everything a bubble shows: a reaction received, a note or a sender name
                // arriving later must redraw it.
                var reactions = d.lookup_value ("reactions", null);
                sigs += "%s:%s:%s:%s:%s:%s:%s:%s:%s".printf (dict_string (d, "id"),
                                   dict_string (d, "status"),
                                   dict_bool (d, "complete") ? "1" : "0",
                                   dict_string (d, "body").length.to_string (),
                                   dict_string (d, "avatar"), dict_string (d, "sender"),
                                   dict_int64 (d, "time").to_string (), dict_string (d, "note"),
                                   reactions != null ? reactions.print (false) : "");
            }
            var from = head == rendered ? first_change (rendered_items, sigs) : 0;
            if (from == sigs.length && from == rendered_items.length) {
                scroll_to_pending ();
                return;
            }
            rendered = head;
            rendered_items = sigs;
            debug ("bubbles redrawn from %d of %d", from, sigs.length);  // G_MESSAGES_DEBUG=all

            // Remove the bubbles from the first change on (all of them for another thread).
            Gtk.Widget? child = from == 0 ? bubbles.get_first_child ()
                              : from < item_starts.length ? item_starts[from] : null;
            while (child != null) {
                var next = child.get_next_sibling ();
                bubbles.remove (child);
                child = next;
            }
            if (from == 0) {
                bubble_index.remove_all ();
            } else {
                for (int i = from; i < thread_ids.length; i++) {
                    bubble_index.remove (thread_ids[i]);
                }
            }
            thread_ids = thread_ids[0:int.min (from, thread_ids.length)];
            thread_bodies = thread_bodies[0:int.min (from, thread_bodies.length)];
            item_starts = item_starts[0:int.min (from, item_starts.length)];
            // What the first redrawn bubble follows: the message before it.
            int64 previous_time = 0;
            string previous_sender = "";
            bool previous_outgoing = false;
            if (from > 0) {
                var before = new VariantDict (items[from - 1]);
                previous_time = dict_int64 (before, "time");
                previous_sender = dict_string (before, "sender");
                previous_outgoing = dict_bool (before, "outgoing");
            }
            for (int index = from; index < items.length; index++) {
                var d = new VariantDict (items[index]);
                var last_before = bubbles.get_last_child ();
                var time = dict_int64 (d, "time");
                var outgoing = dict_bool (d, "outgoing");
                var sender = dict_string (d, "sender");
                thread_ids += dict_string (d, "id");
                thread_bodies += dict_string (d, "body");
                if (index == unread_from) {
                    bubbles.append (unread_line ());
                }
                var new_block = time - previous_time > 3600;
                if (new_block) {
                    var stamp = new Gtk.Label (long_time (time)) { margin_top = 12, margin_bottom = 4 };
                    stamp.add_css_class (Granite.CssClass.DIM);
                    stamp.add_css_class (Granite.CssClass.SMALL);
                    bubbles.append (stamp);
                }
                var show_sender = group && !outgoing
                                  && (new_block || previous_outgoing || sender != previous_sender);
                var item_widget = bubble (d, outgoing, show_sender ? sender : null,
                                          !new_block && outgoing == previous_outgoing
                                          && sender == previous_sender);
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
                bubbles.append (item_widget);
                bubble_index[dict_string (d, "id")] = item_widget;
                item_starts += last_before != null ? last_before.get_next_sibling () : bubbles.get_first_child ();
                previous_time = time;
                previous_sender = sender;
                previous_outgoing = outgoing;
            }
            // The adjustment's handlers keep the view on the newest message.
            if (stick_bottom) {
                queue_stick ();
            }
            if (find_bar.search_mode_enabled && find_hits.length > 0) {
                find_mark ();  // the bubbles were rebuilt
            }
            update_down ();
            scroll_to_pending ();
        }

        private static Gtk.Widget unread_line () {
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { margin_top = 10, margin_bottom = 6 };
            line.add_css_class ("unread-marker");
            line.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { hexpand = true, valign = Gtk.Align.CENTER });
            line.append (new Gtk.Label (_("Non lus")));
            line.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { hexpand = true, valign = Gtk.Align.CENTER });
            return line;
        }

        private static bool warn_on_delete () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
                return prefs.get_boolean ("messages", "warn-on-delete");
            } catch (Error e) {
                return true;
            }
        }

        private static void stop_warning_on_delete () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
            } catch (Error e) {
                // first choice
            }
            prefs.set_boolean ("messages", "warn-on-delete", false);
            try {
                DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
                prefs.save_to_file (Setup.prefs_path ());
            } catch (Error e) {
                warning ("cannot save the delete warning choice: %s", e.message);
            }
        }

        /* Deletion only happens in Boomerang: say so, until the user no longer wants to be told. */
        private void confirm (string title, string detail, owned VoidFunc on_accept) {
            if (!warn_on_delete ()) {
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
                    stop_warning_on_delete ();
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

        private void confirm_delete_thread (string id, string title) {
            confirm (_("Supprimer la conversation avec %s ?").printf (title),
                     _("Les messages restent sur l'iPhone et ne réapparaîtront pas dans Boomerang. "
                     + "Les prochains messages s'afficheront normalement."),
                     () => daemon.call.begin ("DeleteConversation", new Variant ("(s)", id)));
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

        private static bool warn_on_reaction () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
                return prefs.get_boolean ("messages", "warn-on-reaction");
            } catch (Error e) {
                return true;
            }
        }

        private static void stop_warning_on_reaction () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
            } catch (Error e) {
                // first choice
            }
            prefs.set_boolean ("messages", "warn-on-reaction", false);
            try {
                DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
                prefs.save_to_file (Setup.prefs_path ());
            } catch (Error e) {
                warning ("cannot save the reaction warning choice: %s", e.message);
            }
        }

        private static bool warn_on_read_full () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
                return prefs.get_boolean ("messages", "warn-on-read-full");
            } catch (Error e) {
                return true;
            }
        }

        private static void stop_warning_on_read_full () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
            } catch (Error e) {
                // first choice
            }
            prefs.set_boolean ("messages", "warn-on-read-full", false);
            try {
                DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
                prefs.save_to_file (Setup.prefs_path ());
            } catch (Error e) {
                warning ("cannot save the read warning choice: %s", e.message);
            }
        }

        /* The iPhone lists only the first 120 characters of an unread message; the whole text
           comes by downloading it, which marks it read on the iPhone. */
        private void confirm_read_full (string id, Gtk.Button button) {
            if (!warn_on_read_full ()) {
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
                    stop_warning_on_read_full ();
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
            if (!warn_on_reaction ()) {
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
                    stop_warning_on_reaction ();
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

        /* Sync: list the iPhone's messages again, full texts, contacts and calls. */
        private Gtk.Widget build_sync_button () {
            var button = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = _("Synchroniser avec l'iPhone")
            };
            button.add_css_class ("flat");
            var spinner = new Gtk.Spinner () {
                spinning = false,
                tooltip_text = _("Synchronisation…"),
                width_request = 16,
                height_request = 16
            };
            var stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                valign = Gtk.Align.CENTER
            };
            stack.add_named (button, "button");
            stack.add_named (spinner, "spinner");
            button.clicked.connect (() => run_sync.begin (stack, spinner));
            return stack;
        }

        private async void run_sync (Gtk.Stack stack, Gtk.Spinner spinner) {
            stack.visible_child_name = "spinner";
            spinner.spinning = true;
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
            spinner.spinning = false;
            stack.visible_child_name = "button";
            yield reload_threads ();
        }

        private Gtk.Widget bubble (VariantDict d, bool outgoing, string? sender, bool follows) {
            if (dict_string (d, "note") != "") {
                return reaction_note (d);
            }
            var body = dict_string (d, "body");
            var complete = dict_bool (d, "complete");
            var label = new Gtk.Label (linkify (complete ? body : body + "…")) {
                use_markup = true,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                selectable = true,
                xalign = 0,
                max_width_chars = 46
            };
            label.add_css_class ("bubble");
            label.add_css_class (outgoing ? "outgoing" : "incoming");
            var bubble_id = dict_string (d, "id");
            if (dict_string (d, "status") != "sending") {
                // Own menu, caught before the label's (Cut/Paste/Delete make no sense here).
                var menu = new GLib.Menu ();
                var status = dict_string (d, "status");
                if (current_can_send && !current_group && status != "failed"
                    && daemon.get_bool ("ReactionsSend")) {
                    var react_menu = new GLib.Menu ();
                    foreach (var emoji in QUICK_REACTIONS) {
                        react_menu.append (emoji, "bubble.react('%s')".printf (emoji));
                    }
                    react_menu.append (_("Autre emoji…"), "bubble.react-other");
                    menu.append_submenu (_("Réagir"), react_menu);
                }
                menu.append (_("Copier"), "bubble.copy");
                menu.append (_("Supprimer de Boomerang…"), "bubble.delete");
                var actions = new SimpleActionGroup ();
                var react = new SimpleAction ("react", VariantType.STRING);
                react.activate.connect ((param) => react_to (bubble_id, param.get_string ()));
                actions.add_action (react);
                var react_other = new SimpleAction ("react-other", null);
                react_other.activate.connect (() => {
                    var chooser = new Gtk.EmojiChooser ();
                    chooser.set_parent (label);
                    chooser.emoji_picked.connect ((emoji) => react_to (bubble_id, emoji));
                    chooser.closed.connect (() => Idle.add (() => {
                        chooser.unparent ();
                        return Source.REMOVE;
                    }));
                    chooser.popup ();
                });
                actions.add_action (react_other);
                var copy = new SimpleAction ("copy", null);
                copy.activate.connect (() => label.get_clipboard ().set_text (body));
                actions.add_action (copy);
                var remove = new SimpleAction ("delete", null);
                remove.activate.connect (() => confirm_delete_message (bubble_id));
                actions.add_action (remove);
                label.insert_action_group ("bubble", actions);
                var click = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
                click.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
                click.pressed.connect ((n, x, y) => {
                    click.set_state (Gtk.EventSequenceState.CLAIMED);
                    var popover = new Gtk.PopoverMenu.from_model (menu) {
                        has_arrow = false,
                        pointing_to = { (int) x, (int) y, 1, 1 }
                    };
                    popover.set_parent (label);
                    popover.closed.connect (() => Idle.add (() => {
                        popover.unparent ();
                        return Source.REMOVE;
                    }));
                    popover.popup ();
                });
                label.add_controller (click);
            }
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
            label.tooltip_text = tip;

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
                margin_top = follows ? 0 : 6
            };
            if (sender != null && sender != "") {
                var name = new Gtk.Label (sender) { xalign = 0, margin_start = 12 };
                name.add_css_class (Granite.CssClass.DIM);
                name.add_css_class (Granite.CssClass.SMALL);
                column.append (name);
            }
            column.append (shown);
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
            if (outgoing && dict_string (d, "source") == "map") {
                // The iPhone lists it among its sent messages: Boomerang has checked it left.
                var sent = new Gtk.Image.from_icon_name ("object-select-symbolic") {
                    pixel_size = 12,
                    halign = Gtk.Align.END,
                    margin_end = 6,
                    tooltip_text = _("Envoyé : l'iPhone confirme l'envoi")
                };
                sent.add_css_class ("sent-check");
                sent.update_property (Gtk.AccessibleProperty.LABEL, _("Envoyé"), -1);
                column.append (sent);
            }
            if (!outgoing && !complete && dict_string (d, "source") == "map") {
                var more = new Gtk.Button.with_label (_("Tout lire")) {
                    halign = Gtk.Align.START,
                    tooltip_text = _("Récupérer le texte complet (le message sera marqué comme lu sur l'iPhone)")
                };
                more.add_css_class ("flat");
                more.add_css_class (Granite.CssClass.SMALL);
                more.clicked.connect (() => confirm_read_full (id, more));
                column.append (more);
            }
            if (status == "sending") {
                return column;
            }
            // Hover: reactions (received messages) with Copy and Delete below, beside the bubble.
            var can_react = !outgoing && current_can_send && !current_group && status != "failed"
                && daemon.get_bool ("ReactionsSend");
            var tools = hover_tools (id, body, label, can_react);
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                halign = column.halign,
                margin_top = column.margin_top
            };
            column.margin_top = 0;
            if (outgoing) {
                row.append (tools);
                row.append (column);
            } else {
                row.append (column);
                row.append (tools);
            }
            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect (() => {
                tools.opacity = 1;
                tools.can_target = true;
            });
            motion.leave.connect (() => {
                tools.opacity = 0;
                tools.can_target = false;
            });
            row.add_controller (motion);
            return row;
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
                var picture = new Gtk.Picture.for_filename (image) {
                    content_fit = Gtk.ContentFit.COVER,
                    height_request = 130,
                    can_shrink = true
                };
                picture.add_css_class ("link-picture");
                card.append (picture);
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

        private Gtk.Widget hover_tools (string id, string body, Gtk.Widget bubble, bool can_react) {
            var tools = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                valign = Gtk.Align.CENTER,
                opacity = 0,
                can_target = false
            };
            tools.add_css_class ("hover-tools");
            if (can_react) {
                var reactions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                reactions.add_css_class ("reaction-strip");
                foreach (var emoji in QUICK_REACTIONS) {
                    var button = new Gtk.Button.with_label (emoji) {
                        tooltip_text = _("Réagir %s").printf (emoji)
                    };
                    button.add_css_class ("flat");
                    button.add_css_class ("reaction-choice");
                    button.clicked.connect (() => react_to (id, button.label));
                    reactions.append (button);
                }
                var more = new Gtk.Button.from_icon_name ("list-add-symbolic") {
                    tooltip_text = _("Autre emoji…")
                };
                more.add_css_class ("flat");
                more.add_css_class ("reaction-choice");
                more.clicked.connect (() => {
                    var chooser = new Gtk.EmojiChooser ();
                    chooser.set_parent (bubble);
                    chooser.emoji_picked.connect ((emoji) => react_to (id, emoji));
                    chooser.closed.connect (() => Idle.add (() => {
                        chooser.unparent ();
                        return Source.REMOVE;
                    }));
                    chooser.popup ();
                });
                reactions.append (more);
                tools.append (reactions);
            }
            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                halign = can_react ? Gtk.Align.START : Gtk.Align.CENTER
            };
            var copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") { tooltip_text = _("Copier") };
            copy.add_css_class ("flat");
            copy.add_css_class (Granite.CssClass.SMALL);
            copy.clicked.connect (() => {
                bubble.get_clipboard ().set_text (body);
                toast.title = _("Copié");
                toast.send_notification ();
            });
            var remove = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                tooltip_text = _("Supprimer de Boomerang…")
            };
            remove.add_css_class ("flat");
            remove.add_css_class (Granite.CssClass.SMALL);
            remove.clicked.connect (() => confirm_delete_message (id));
            actions.append (copy);
            actions.append (remove);
            tools.append (actions);
            return tools;
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
