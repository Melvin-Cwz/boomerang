// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Contacts: the iPhone's phone book as read over PBAP (read only) or the iCloud address
 * book (editable), with search, sections by letter, an index, the whole card in a detail
 * pane, vCard export and import. ContactList is also the body of the new-message picker
 * in the Messages page.
 */

namespace Boomerang {
    public class Contact : Object {
        public string name { get; construct; }
        public string photo { get; construct; }
        public string[] addresses { get; construct; }
        public string uid { get; construct; }  /* iCloud card id, "" for the iPhone's */
        public bool favorite { get; set; default = false; }  /* alpha: iPhone favourites (PBAP) */
        /* Key of GetContactDetails and ExportContacts (iCloud uid or « pbap: » and an address). */
        public string key { get; set; default = ""; }
        public string given { get; set; default = ""; }
        public string family { get; set; default = ""; }
        public string org { get; set; default = ""; }

        public Contact (string name, string photo, string[] addresses, string uid = "") {
            Object (name: name, photo: photo, addresses: addresses, uid: uid);
        }

        public static Contact from_variant (Variant item) {
            var d = new VariantDict (item);
            var list = d.lookup_value ("addresses", new VariantType ("as"));
            string[] addresses = list != null ? list.dup_strv () : new string[0];
            var contact = new Contact (dict_string (d, "name"), dict_string (d, "photo"), addresses,
                                       dict_string (d, "uid"));
            contact.favorite = dict_bool (d, "favorite");
            contact.key = dict_string (d, "key");
            contact.given = dict_string (d, "given");
            contact.family = dict_string (d, "family");
            contact.org = dict_string (d, "org");
            return contact;
        }

        public bool is_phone (string address) {
            return !address.contains ("@");
        }

        public string summary () {
            foreach (var a in addresses) {
                if (is_phone (a)) {
                    return format_address (a);
                }
            }
            return addresses.length > 0 ? addresses[0] : org;
        }

        /* What the list is sorted on: family name first (« Martin Alice ») or given name
           first. Without separate names (a phone book read before this version) the name. */
        public string sort_key (bool by_family) {
            if (given == "" && family == "") {
                return search_fold (name);
            }
            var first = by_family ? (family != "" ? family : given) : (given != "" ? given : family);
            var second = by_family ? (family != "" ? given : "") : (given != "" ? family : "");
            return search_fold ((first + " " + second).strip ());
        }

        /* Section letter: A to Z, « # » for the rest (digits, other scripts). */
        public string letter (bool by_family) {
            var text = sort_key (by_family).up ();
            unichar c = text.get_char (0);
            return c >= 'A' && c <= 'Z' ? c.to_string () : "#";
        }

        public bool matches (string query) {
            if (query == "") {
                return true;
            }
            var q = search_fold (query);
            if (search_fold (name).contains (q) || (org != "" && search_fold (org).contains (q))) {
                return true;
            }
            var digits = only_digits (query);
            foreach (var a in addresses) {
                if (search_fold (a).contains (q)
                    || (digits.length >= 3 && only_digits (a).contains (digits))
                    || (digits.length >= 3 && digits.has_prefix ("0")
                        && only_digits (a).contains (digits.substring (1)))) {
                    return true;
                }
            }
            return false;
        }
    }

    /* Comparable form for search: accents dropped, case folded ("Élodie" -> "elodie"). */
    public string search_fold (string text) {
        var builder = new StringBuilder ();
        var decomposed = text.normalize (-1, NormalizeMode.ALL);
        unichar c;
        int i = 0;
        while (decomposed.get_next_char (ref i, out c)) {
            var type = c.type ();
            if (type != UnicodeType.NON_SPACING_MARK && type != UnicodeType.SPACING_MARK
                && type != UnicodeType.ENCLOSING_MARK) {
                builder.append_unichar (c);
            }
        }
        return builder.str.casefold ();
    }

    public string only_digits (string text) {
        var builder = new StringBuilder ();
        unichar c;
        int i = 0;
        while (text.get_next_char (ref i, out c)) {
            if (c.isdigit ()) {
                builder.append_unichar (c);
            }
        }
        return builder.str;
    }

    /* +33612345678 -> 06 12 34 56 78; other numbers and e-mails unchanged. */
    public string format_address (string address) {
        if (address.has_prefix ("+33") && address.length == 12) {
            var national = "0" + address.substring (3);
            var builder = new StringBuilder ();
            for (int i = 0; i < national.length; i += 2) {
                if (i > 0) {
                    builder.append (" ");
                }
                builder.append (national.substring (i, 2));
            }
            return builder.str;
        }
        return address;
    }

    /* Something the user typed that can be written to directly. */
    public bool looks_like_address (string text) {
        var t = text.strip ();
        if (t.contains ("@")) {
            return t.index_of ("@") > 0 && t.contains (".");
        }
        var digits = only_digits (t);
        return digits.length >= 3 && digits.length + 6 >= t.length;
    }

    /* Sort order of the contact lists, kept in apps.conf [contacts] sort. */
    namespace ContactSort {
        public bool by_family () {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
                return prefs.get_string ("contacts", "sort") == "family";
            } catch (Error e) {
                return false;  // given name first, as the iPhone does by default
            }
        }

        public void set_by_family (bool family) {
            var prefs = new KeyFile ();
            try {
                prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.KEEP_COMMENTS);
            } catch (Error e) {
                // first setting
            }
            prefs.set_string ("contacts", "sort", family ? "family" : "given");
            try {
                DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
                prefs.save_to_file (Setup.prefs_path ());
            } catch (Error e) {
                warning ("contacts sort not saved: %s", e.message);
            }
        }
    }

    public class ContactRow : Gtk.ListBoxRow {
        public Contact contact { get; construct; }

        public ContactRow (Contact contact, int avatar_size = 32) {
            Object (contact: contact);
            var avatar = new Avatar (avatar_size);
            avatar.show_person (contact.name, contact.photo);
            var name = new Gtk.Label (contact.name) {
                xalign = 0,
                ellipsize = Pango.EllipsizeMode.END
            };
            var detail = new Gtk.Label (contact.summary ()) {
                xalign = 0,
                ellipsize = Pango.EllipsizeMode.END
            };
            detail.add_css_class (Granite.CssClass.DIM);
            detail.add_css_class (Granite.CssClass.SMALL);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                valign = Gtk.Align.CENTER,
                hexpand = true
            };
            text.append (name);
            text.append (detail);
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 9) {
                margin_top = 5,
                margin_bottom = 5,
                margin_start = 6,
                margin_end = 6
            };
            box.append (avatar);
            box.append (text);
            if (contact.favorite) {
                var star = new Gtk.Image.from_icon_name ("starred-symbolic") {
                    tooltip_text = _("Favori sur l'iPhone"),
                    valign = Gtk.Align.CENTER
                };
                star.add_css_class ("favorite-star");
                box.append (star);
            }
            child = box;
        }
    }

    /* Searchable contact list in sections by letter; "activated" gives the contact or a
       typed address. With show_index, a column of letters jumps to a section. */
    public class ContactList : Gtk.Box {
        public Daemon daemon { get; construct; }
        public bool offer_typed { get; construct; }
        public bool show_index { get; construct; }

        public signal void contact_selected (Contact contact);
        public signal void address_chosen (string address);
        public signal void reloaded ();

        public Gtk.SearchEntry search { get; private set; }
        private Gtk.ListBox list;
        private Gtk.ListBoxRow typed_row;
        private Gtk.Label typed_label;
        private Gtk.Stack stack;
        private Gtk.ScrolledWindow scroll;
        private Gtk.Box index;
        private Granite.Placeholder empty;
        private int count = 0;
        private bool by_family = ContactSort.by_family ();

        public ContactList (Daemon daemon, bool offer_typed, bool show_index = false) {
            Object (daemon: daemon, offer_typed: offer_typed, show_index: show_index,
                    orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        }

        construct {
            search = new Gtk.SearchEntry () {
                placeholder_text = offer_typed ? _("Nom, numéro ou adresse") : _("Rechercher")
            };
            typed_label = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            var typed_icon = new Gtk.Image.from_icon_name ("mail-message-new-symbolic");
            var typed_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 9) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 12,
                margin_end = 6
            };
            typed_box.append (typed_icon);
            typed_box.append (typed_label);
            typed_row = new Gtk.ListBoxRow () { child = typed_box, visible = false };

            list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.SINGLE };
            list.add_css_class ("navigation-sidebar");
            list.append (typed_row);
            list.set_filter_func ((row) => {
                var contact_row = row as ContactRow;
                return contact_row == null ? typed_row.visible
                                           : contact_row.contact.matches (search.text.strip ());
            });
            list.set_sort_func ((a, b) => {
                var ca = a as ContactRow;
                var cb = b as ContactRow;
                if (ca == null || cb == null) {
                    return ca == null ? -1 : 1;  // the typed address stays on top
                }
                var la = ca.contact.letter (by_family);
                var lb = cb.contact.letter (by_family);
                if (la != lb) {
                    return la == "#" ? 1 : lb == "#" ? -1 : strcmp (la, lb);
                }
                var order = strcmp (ca.contact.sort_key (by_family), cb.contact.sort_key (by_family));
                return order != 0 ? order : strcmp (ca.contact.name, cb.contact.name);
            });
            list.set_header_func ((row, before) => {
                var contact_row = row as ContactRow;
                if (contact_row == null) {
                    row.set_header (null);
                    return;
                }
                var letter = contact_row.contact.letter (by_family);
                var previous = before as ContactRow;
                if (previous != null && previous.contact.letter (by_family) == letter) {
                    row.set_header (null);
                    return;
                }
                var current = row.get_header () as Gtk.Label;
                if (current != null && current.label == letter) {
                    return;
                }
                var header = new Gtk.Label (letter) {
                    xalign = 0,
                    margin_start = 12,
                    margin_top = 9,
                    margin_bottom = 3
                };
                header.add_css_class ("contact-section");
                header.add_css_class (Granite.CssClass.DIM);
                header.update_property (Gtk.AccessibleProperty.LABEL, _("Lettre %s").printf (letter), -1);
                row.set_header (header);
            });
            list.row_activated.connect (on_row);
            if (!offer_typed) {
                list.row_selected.connect ((row) => {
                    var contact_row = row as ContactRow;
                    if (contact_row != null) {
                        contact_selected (contact_row.contact);
                    }
                });
            }
            search.search_changed.connect (() => {
                var text = search.text.strip ();
                typed_row.visible = offer_typed && looks_like_address (text);
                typed_label.label = _("Écrire à %s").printf (text);
                list.invalidate_filter ();
                list.invalidate_headers ();
                update_empty ();
                update_index ();
            });
            search.activate.connect (() => {
                var text = search.text.strip ();
                if (typed_row.visible) {
                    address_chosen (text);
                    return;
                }
                for (int i = 0; ; i++) {
                    var row = list.get_row_at_index (i);
                    if (row == null) {
                        break;
                    }
                    var contact_row = row as ContactRow;
                    if (contact_row != null && contact_row.contact.matches (text)) {
                        on_row (contact_row);
                        break;
                    }
                }
            });

            scroll = new Gtk.ScrolledWindow () {
                child = list,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true,
                hexpand = true,
                propagate_natural_height = offer_typed,
                max_content_height = 420
            };
            index = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                valign = Gtk.Align.CENTER,
                visible = show_index
            };
            index.add_css_class ("contact-index");
            index.update_property (Gtk.AccessibleProperty.LABEL, _("Index alphabétique"), -1);
            var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#";
            for (int i = 0; i < letters.length; i++) {
                var letter = letters.substring (i, 1);
                var jump = new Gtk.Button.with_label (letter) {
                    tooltip_text = _("Aller à la lettre %s").printf (letter),
                    focus_on_click = false
                };
                jump.add_css_class ("flat");
                jump.set_data<string> ("letter", letter);
                jump.clicked.connect (() => scroll_to (letter));
                index.append (jump);
            }
            var body = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            body.append (scroll);
            body.append (index);

            empty = new Granite.Placeholder (_("Aucun contact")) {
                description = _("Les contacts viennent de l'iPhone. Activez « Synchroniser les "
                              + "contacts » pour ce PC dans les réglages Bluetooth de l'iPhone."),
                icon = new ThemedIcon (Config.APP_ID + ".Contacts")
            };
            stack = new Gtk.Stack () { vhomogeneous = false };
            stack.add_named (body, "list");
            stack.add_named (empty, "empty");
            append (search);
            append (stack);
        }

        /* Sort on the family name (true) or the given name (false). */
        public void set_order (bool family) {
            by_family = family;
            list.invalidate_sort ();
            list.invalidate_headers ();
            update_index ();
        }

        private void scroll_to (string letter) {
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) {
                    return;
                }
                var contact_row = row as ContactRow;
                if (contact_row == null || !contact_row.get_child_visible ()) {
                    continue;
                }
                if (contact_row.contact.letter (by_family) == letter) {
                    Graphene.Rect bounds;
                    var target = row.get_header () ?? row;
                    if (target.compute_bounds (list, out bounds)) {
                        scroll.vadjustment.value = bounds.origin.y;
                    }
                    return;
                }
            }
        }

        /* Letters with no contact (after the search) are greyed out in the index. */
        private void update_index () {
            if (!show_index) {
                return;
            }
            var present = new GenericSet<string> (str_hash, str_equal);
            var query = search.text.strip ();
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) {
                    break;
                }
                var contact_row = row as ContactRow;
                if (contact_row != null && contact_row.contact.matches (query)) {
                    present.add (contact_row.contact.letter (by_family));
                }
            }
            for (var child = index.get_first_child (); child != null; child = child.get_next_sibling ()) {
                child.sensitive = present.contains (child.get_data<string> ("letter"));
            }
        }

        private void on_row (Gtk.ListBoxRow row) {
            if (row == typed_row) {
                address_chosen (search.text.strip ());
                return;
            }
            var contact_row = row as ContactRow;
            if (contact_row != null) {
                contact_selected (contact_row.contact);
            }
        }

        private void update_empty () {
            stack.visible_child_name = count > 0 || typed_row.visible ? "list" : "empty";
        }

        public bool loaded { get; private set; default = false; }

        /* The row of the contact with this key, to keep it selected across a reload. */
        public void select_key (string key) {
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) {
                    return;
                }
                var contact_row = row as ContactRow;
                if (contact_row != null && key != "" && contact_row.contact.key == key) {
                    list.select_row (row);
                    return;
                }
            }
        }

        /* Development (screenshots): select the first contact whose name holds this text. */
        public void select_matching (string text) {
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) {
                    return;
                }
                var contact_row = row as ContactRow;
                if (contact_row != null && contact_row.contact.name.contains (text)) {
                    list.select_row (row);
                    return;
                }
            }
        }

        public async void reload () {
            if (!daemon.running) {
                return;
            }
            loaded = true;
            bool ok;
            var items = yield daemon.try_list ("ListContacts", null, out ok);
            if (!ok) {
                return;  // failed call: keep the contacts shown
            }
            var selected = list.get_selected_row () as ContactRow;
            var selected_key = selected != null ? selected.contact.key : "";
            Gtk.ListBoxRow? row;
            while ((row = list.get_row_at_index (1)) != null) {
                list.remove (row);
            }
            count = 0;
            foreach (var item in items) {
                list.append (new ContactRow (Contact.from_variant (item)));
                count++;
            }
            update_empty ();
            update_index ();
            if (selected_key != "") {
                select_key (selected_key);
            }
            reloaded ();
        }
    }

    /* The Contacts page: list on the left, the selected card on the right. */
    public class ContactsView : Gtk.Box {
        public Daemon daemon { get; construct; }
        public signal void message_requested (string address);

        // Section letters, the index, the action buttons under the name (own frame: the
        // round tinted shape is the point, Granite 9 draws plain buttons without one).
        private const string CSS = """
            .contact-section {
                font-weight: 700;
                font-size: 0.85em;
            }
            .contact-index button {
                min-height: 0;
                min-width: 0;
                padding: 0 5px;
                border: none;
                border-radius: 4px;
                background: none;
                box-shadow: none;
                font-size: 0.75em;
                font-weight: 700;
                color: @accent_color;
            }
            .contact-index button:hover {
                background-color: alpha(@accent_color, 0.12);
            }
            .contact-index button:disabled {
                color: alpha(@fg_color, 0.3);
            }
            button.contact-action {
                min-width: 64px;
                padding: 8px 6px;
                border-radius: 12px;
                border: none;
                background-color: alpha(@accent_color, 0.1);
                color: @accent_color;
                box-shadow: none;
            }
            button.contact-action:hover {
                background-color: alpha(@accent_color, 0.18);
            }
            button.contact-action:active {
                background-color: alpha(@accent_color, 0.26);
            }
            button.contact-action:disabled {
                background-color: alpha(@fg_color, 0.05);
                color: alpha(@fg_color, 0.35);
            }
            .contact-drop {
                box-shadow: inset 0 0 0 2px @accent_color;
                background-color: alpha(@accent_color, 0.06);
            }
        """;
        private static bool styled = false;
        // Same C call as Gtk.StyleContext.add_provider_for_display, without the class deprecated in 4.10.
        [CCode (cname = "gtk_style_context_add_provider_for_display")]
        private static extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider,
                                                             uint priority);

        private ContactList contacts;
        private Gtk.Stack detail_stack;
        private Avatar detail_avatar;
        private Gtk.Label detail_name;
        private Gtk.Label detail_subtitle;
        private Gtk.Label detail_nickname;
        private Gtk.Box actions;
        private Gtk.ListBox detail_list;
        private Gtk.Box notes_box;
        private Gtk.Label notes_label;
        private Gtk.Label source_label;
        private Gtk.Button new_button;
        private Gtk.Button edit_button;
        private Gtk.Button export_button;
        private Gtk.MenuButton share_button;
        private Gtk.Label note;
        private SimpleAction source_action;
        private SimpleAction import_action;
        private Granite.Toast toast;
        private Contact? shown = null;
        private uint shown_token = 0;
        private bool updating = false;
        private bool loaded {
            get { return contacts.loaded; }
        }

        public ContactsView (Daemon daemon) {
            Object (daemon: daemon, orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        }

        construct {
            if (!styled) {
                styled = true;
                var provider = new Gtk.CssProvider ();
                provider.load_from_string (Style.colors (CSS));
                add_provider_for_display (Gdk.Display.get_default (), provider,
                                          Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            }
            contacts = new ContactList (daemon, false, true) {
                margin_top = 6,
                margin_start = 6,
                margin_end = 6
            };
            contacts.contact_selected.connect (show_contact);
            contacts.reloaded.connect (on_reloaded);

            // Source of the cards and how they are managed (Bluetooth or iCloud)
            source_label = new Gtk.Label ("") { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
            source_label.add_css_class (Granite.CssClass.DIM);
            source_label.add_css_class (Granite.CssClass.SMALL);
            new_button = new Gtk.Button.from_icon_name ("list-add-symbolic") { tooltip_text = _("Nouveau contact") };
            new_button.add_css_class ("flat");
            new_button.clicked.connect (() => edit (""));
            var options = new Gtk.MenuButton () {
                icon_name = "open-menu-symbolic",
                tooltip_text = _("Gestion des fiches de contact"),
                menu_model = build_options ()
            };
            options.add_css_class ("flat");
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3) { margin_start = 6, margin_end = 6 };
            bar.append (source_label);
            bar.append (new_button);
            bar.append (options);
            var side = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 280 };
            side.append (contacts);
            side.append (bar);
            contacts.vexpand = true;

            detail_avatar = new Avatar (96) { margin_top = 24 };
            detail_name = new Gtk.Label ("") {
                wrap = true, justify = Gtk.Justification.CENTER, selectable = true, max_width_chars = 32
            };
            detail_name.add_css_class (Granite.HeaderLabel.Size.H2.to_string ());
            detail_subtitle = new Gtk.Label ("") {
                wrap = true, justify = Gtk.Justification.CENTER, max_width_chars = 44, visible = false
            };
            detail_subtitle.add_css_class (Granite.CssClass.DIM);
            detail_nickname = new Gtk.Label ("") { visible = false };
            detail_nickname.add_css_class (Granite.CssClass.DIM);
            detail_nickname.add_css_class (Granite.CssClass.SMALL);
            actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { halign = Gtk.Align.CENTER, margin_top = 12 };

            detail_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                show_separators = true,
                margin_top = 12
            };
            detail_list.add_css_class (Granite.CssClass.CARD);
            notes_label = new Gtk.Label ("") {
                xalign = 0, wrap = true, selectable = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                margin_top = 6, margin_bottom = 9, margin_start = 12, margin_end = 12
            };
            var notes_title = new Gtk.Label (_("notes")) { xalign = 0, margin_top = 9, margin_start = 12 };
            notes_title.add_css_class (Granite.CssClass.DIM);
            notes_title.add_css_class (Granite.CssClass.SMALL);
            notes_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { margin_top = 12, visible = false };
            notes_box.add_css_class (Granite.CssClass.CARD);
            notes_box.append (notes_title);
            notes_box.append (notes_label);

            edit_button = new Gtk.Button.with_label (_("Modifier"));
            edit_button.clicked.connect (() => {
                if (shown != null) {
                    edit (shown.uid);
                }
            });
            export_button = new Gtk.Button.with_label (_("Exporter la fiche…")) {
                tooltip_text = _("Enregistrer la fiche dans un fichier vCard (.vcf)")
            };
            export_button.clicked.connect (() => {
                if (shown != null) {
                    export_cards.begin ({ shown.key }, vcard_name (shown.name));
                }
            });
            share_button = new Gtk.MenuButton () {
                label = _("Envoyer…"),
                tooltip_text = _("Envoyer la fiche à un appareil LocalSend"),
                popover = new Gtk.Popover ()
            };
            share_button.popover.show.connect (() => fill_share_popover.begin ());
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { halign = Gtk.Align.CENTER, margin_top = 12 };
            footer.append (edit_button);
            footer.append (export_button);
            footer.append (share_button);
            note = new Gtk.Label ("") {
                wrap = true, justify = Gtk.Justification.CENTER, max_width_chars = 50, margin_top = 12
            };
            note.add_css_class (Granite.CssClass.DIM);
            note.add_css_class (Granite.CssClass.SMALL);
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                halign = Gtk.Align.CENTER,
                width_request = 380,
                margin_start = 18,
                margin_end = 18,
                margin_bottom = 24
            };
            card.append (detail_avatar);
            card.append (detail_name);
            card.append (detail_subtitle);
            card.append (detail_nickname);
            card.append (actions);
            card.append (detail_list);
            card.append (notes_box);
            card.append (footer);
            card.append (note);
            var card_scroll = new Gtk.ScrolledWindow () {
                child = card,
                hscrollbar_policy = Gtk.PolicyType.NEVER
            };

            var none = new Granite.Placeholder (_("Contacts")) {
                description = _("Choisissez un contact."),
                icon = new ThemedIcon (Config.APP_ID + ".Contacts")
            };
            detail_stack = new Gtk.Stack () { hexpand = true };
            detail_stack.add_css_class ("view");
            detail_stack.add_named (none, "none");
            detail_stack.add_named (card_scroll, "card");

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = side,
                end_child = detail_stack,
                resize_start_child = false,
                shrink_start_child = false,
                shrink_end_child = false,
                hexpand = true
            };
            toast = new Granite.Toast ("");
            var overlay = new Gtk.Overlay () { child = paned, hexpand = true };
            overlay.add_overlay (toast);
            append (overlay);

            // vCard files dropped on the page: imported into iCloud after a confirmation.
            var drop = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.enter.connect (() => {
                overlay.add_css_class ("contact-drop");
                return Gdk.DragAction.COPY;
            });
            drop.leave.connect (() => overlay.remove_css_class ("contact-drop"));
            drop.drop.connect ((value) => {
                overlay.remove_css_class ("contact-drop");
                File[] files = {};
                foreach (var file in ((Gdk.FileList) value).get_files ()) {
                    files += file;
                }
                import_files.begin (files);
                return true;
            });
            add_controller (drop);

            map.connect (() => contacts.reload.begin ());
            daemon.contacts_changed.connect (() => {
                if (get_mapped ()) {  // hidden: map reloads it
                    contacts.reload.begin ();
                }
            });
            daemon.changed.connect (() => {
                if (daemon.touched ({ "ContactsSource", "ContactsBook", "Files", "Catalog" })) {
                    update_source ();
                }
            });
            update_source ();
            // The detached Contacts app is mapped before it reaches the daemon: load once it does.
            daemon.changed.connect (() => {
                if (!loaded && daemon.touched ({}) && daemon.running && get_mapped ()) {
                    contacts.reload.begin ();
                }
            });
        }

        /* Box reports a natural height below its minimum when a wrapping label gets less
           width for the minimum than for the natural size; GTK warns. Keep natural >= min. */
        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum,
                                      out int natural, out int minimum_baseline, out int natural_baseline) {
            base.measure (orientation, for_size, out minimum, out natural, out minimum_baseline,
                          out natural_baseline);
            if (natural < minimum) {
                natural = minimum;
            }
        }

        /* The list's menu: where the cards come from, their order, import and export. */
        private GLib.Menu build_options () {
            var actions = new SimpleActionGroup ();
            source_action = new SimpleAction.stateful ("source", VariantType.STRING, new Variant.string (""));
            source_action.change_state.connect ((action, value) => {
                action.set_state (value);
                if (!updating) {
                    daemon.call.begin ("SetContactsSource", new Variant ("(s)", value.get_string ()));
                }
            });
            actions.add_action (source_action);
            var order = new SimpleAction.stateful ("order", VariantType.STRING,
                                                   new Variant.string (ContactSort.by_family () ? "family" : "given"));
            order.change_state.connect ((action, value) => {
                action.set_state (value);
                var by_family = value.get_string () == "family";
                ContactSort.set_by_family (by_family);
                contacts.set_order (by_family);
            });
            actions.add_action (order);
            import_action = new SimpleAction ("import", null);
            import_action.activate.connect (() => choose_import.begin ());
            actions.add_action (import_action);
            var export_all = new SimpleAction ("export-all", null);
            export_all.activate.connect (() => export_cards.begin ({}, _("Contacts") + ".vcf"));
            actions.add_action (export_all);
            insert_action_group ("contacts", actions);

            var source = new GLib.Menu ();
            source.append (_("Lecture via Bluetooth et cache local"), "contacts.source::bluetooth");
            source.append (_("Gestion via iCloud"), "contacts.source::icloud");
            var sort = new GLib.Menu ();
            sort.append (_("Prénom, puis nom"), "contacts.order::given");
            sort.append (_("Nom, puis prénom"), "contacts.order::family");
            var files = new GLib.Menu ();
            files.append (_("Importer des fiches vCard…"), "contacts.import");
            files.append (_("Exporter tous les contacts…"), "contacts.export-all");
            var menu = new GLib.Menu ();
            menu.append_section (_("Gestion des fiches de contact"), source);
            menu.append_section (_("Ordre de tri"), sort);
            menu.append_section (null, files);
            return menu;
        }

        private static Gtk.Button menu_button (string text) {
            var button = new Gtk.Button () { child = new Gtk.Label (text) { xalign = 0 } };
            button.add_css_class ("flat");
            return button;
        }

        private bool editable () {
            return daemon.get_string ("ContactsSource") == "icloud" && daemon.get_string ("ContactsBook") == "ready";
        }

        private bool can_share () {
            return Catalog.added (daemon, "files") && Props.flag (daemon.get_value ("Files"), "enabled");
        }

        private void update_source () {
            var icloud = daemon.get_string ("ContactsSource") == "icloud";
            updating = true;
            source_action.change_state (new Variant.string (icloud ? "icloud" : "bluetooth"));
            updating = false;
            string text;
            switch (icloud ? daemon.get_string ("ContactsBook") : "bluetooth") {
                case "ready":
                    text = _("Contacts iCloud, modifiables");
                    break;
                case "connecting":
                    text = _("Ouverture des contacts iCloud…");
                    break;
                case "no-account":
                    text = _("Compte iCloud non connecté (Services iCloud)");
                    break;
                case "missing":
                    text = _("Composant EBook manquant (gir1.2-ebook-1.2)");
                    break;
                case "error":
                    text = _("Contacts iCloud momentanément illisibles");
                    break;
                default:
                    text = _("Contacts de l'iPhone, lecture seule");
                    break;
            }
            source_label.label = text;
            new_button.visible = editable ();
            import_action.set_enabled (editable ());
            if (shown != null) {
                edit_button.visible = editable () && shown.uid != "";
            }
            share_button.visible = can_share ();
            note.label = icloud
                ? _("Les modifications sont enregistrées dans iCloud, qui les transmet à l'iPhone.")
                : _("Contacts lus sur l'iPhone en Bluetooth, en lecture seule. Pour les modifier, "
                  + "choisissez « Gestion via iCloud » dans le menu de la liste.");
        }

        private void edit (string uid) {
            var parent = get_root () as Gtk.Window;
            var editor = new ContactEditor (parent, daemon, uid);
            if (parent != null) {
                editor.application = parent.application;  // one of the app's windows (active_window)
            }
            editor.saved.connect ((new_uid) => {
                if (new_uid == "") {
                    shown = null;
                    detail_stack.visible_child_name = "none";
                }
                // The daemon reloads the book and emits ContactsChanged.
            });
            editor.present ();
        }

        private void on_reloaded () {
            // Development (screenshots): BOOMERANG_CONTACT_SELECT=Alice shows that card,
            // BOOMERANG_CONTACT_EDIT=1 opens its editor too.
            var wanted = Environment.get_variable ("BOOMERANG_CONTACT_SELECT");
            if (wanted != null && shown == null) {
                contacts.select_matching (wanted);
                if (shown != null && Environment.get_variable ("BOOMERANG_CONTACT_EDIT") == "1") {
                    edit (shown.uid);
                }
            }
            // A card still in the list was selected again by ContactList.reload, which shows
            // it afresh (it may have changed in the editor or in iCloud).
        }

        /* --- the card ------------------------------------------------------------------- */

        private void clear_card () {
            Gtk.Widget? child;
            while ((child = detail_list.get_first_child ()) != null) {
                detail_list.remove (child);
            }
            while ((child = actions.get_first_child ()) != null) {
                actions.remove (child);
            }
        }

        private void show_contact (Contact contact) {
            shown = contact;
            var token = ++shown_token;
            edit_button.visible = editable () && contact.uid != "";
            export_button.sensitive = contact.key != "";
            share_button.sensitive = contact.key != "";
            show_header (contact.name, "", "", contact.photo);
            clear_card ();
            detail_list.visible = false;
            notes_box.visible = false;
            detail_stack.visible_child_name = "card";
            if (contact.key == "") {
                show_listed (contact);
                return;
            }
            // The whole card from the daemon; what the list knows if it cannot say more.
            daemon.call_dict.begin ("GetContactDetails", new Variant ("(s)", contact.key), (obj, res) => {
                var reply = daemon.call_dict.end (res);
                if (token != shown_token) {
                    return;  // another contact was chosen meanwhile
                }
                if (reply != null) {
                    fill_card (contact, new VariantDict (reply));
                } else {
                    show_listed (contact);
                }
            });
        }

        private void show_listed (Contact contact) {
            clear_card ();
            string[] phones = {};
            string[] mails = {};
            foreach (var address in contact.addresses) {
                if (contact.is_phone (address)) {
                    phones += address;
                    add_phone ("", address);
                } else {
                    mails += address;
                    add_mail ("", address);
                }
            }
            add_actions (phones.length > 0 ? phones[0] : "", mails.length > 0 ? mails[0] : "");
            notes_box.visible = false;
            detail_list.visible = contact.addresses.length > 0;
        }

        private void show_header (string name, string subtitle, string nickname, string photo) {
            detail_avatar.show_person (name, photo);
            detail_name.label = name;
            detail_subtitle.label = subtitle;
            detail_subtitle.visible = subtitle != "";
            detail_nickname.label = nickname != "" ? _("« %s »").printf (nickname) : "";
            detail_nickname.visible = nickname != "";
        }

        private void fill_card (Contact contact, VariantDict d) {
            var name = dict_string (d, "name");
            string[] job = {};
            foreach (var part in new string[] { dict_string (d, "title"), dict_string (d, "org"),
                                                dict_string (d, "department") }) {
                if (part != "") {
                    job += part;
                }
            }
            var photo = dict_string (d, "photo");
            show_header (name != "" ? name : contact.name, string.joinv (" · ", job),
                         dict_string (d, "nickname"), photo != "" ? photo : contact.photo);
            clear_card ();
            string first_phone = "", first_mail = "";
            var phones = pairs (d, "phones");
            for (int i = 0; i < phones.length; i += 2) {
                add_phone (phones[i], phones[i + 1]);
                if (first_phone == "") {
                    first_phone = phones[i + 1];
                }
            }
            var mails = pairs (d, "emails");
            for (int i = 0; i < mails.length; i += 2) {
                add_mail (mails[i], mails[i + 1]);
                if (first_mail == "") {
                    first_mail = mails[i + 1];
                }
            }
            var addresses = d.lookup_value ("addresses", new VariantType ("a(ssssss)"));
            if (addresses != null) {
                for (size_t i = 0; i < addresses.n_children (); i++) {
                    string label, street, city, region, postcode, country;
                    addresses.get_child (i, "(ssssss)", out label, out street, out city, out region,
                                         out postcode, out country);
                    add_postal (label, street, city, region, postcode, country);
                }
            }
            var urls = pairs (d, "urls");
            for (int i = 0; i < urls.length; i += 2) {
                add_url (urls[i], urls[i + 1]);
            }
            var birthday = dict_string (d, "birthday");
            if (birthday != "") {
                add_field (_("anniversaire"), format_date (birthday), null);
            }
            var dates = pairs (d, "dates");
            for (int i = 0; i < dates.length; i += 2) {
                add_field (date_label (dates[i]), format_date (dates[i + 1]), null);
            }
            add_actions (first_phone, first_mail);
            detail_list.visible = detail_list.get_first_child () != null;
            var notes = dict_string (d, "note");
            notes_label.label = notes;
            notes_box.visible = notes != "";
        }

        /* Message, call and mail as round buttons under the name, as in macOS Contacts. */
        private void add_actions (string phone, string mail) {
            var write = new Gtk.Button () {
                child = action_child ("internet-chat-symbolic", _("message")),
                tooltip_text = phone != "" ? _("Envoyer un message au %s").printf (format_address (phone))
                                           : _("Aucun numéro de téléphone"),
                sensitive = phone != ""
            };
            write.clicked.connect (() => message_requested (phone));
            var call = new CallButton (daemon, phone, toast);
            call.remove_css_class ("flat");
            call.child = action_child ("call-start-symbolic", _("appeler"));
            if (phone == "") {
                call.number_source = () => "";
            }
            var mail_button = new Gtk.Button () {
                child = action_child ("mail-send-symbolic", _("courriel")),
                tooltip_text = mail != "" ? _("Écrire à %s").printf (mail) : _("Aucune adresse de courriel"),
                sensitive = mail != ""
            };
            mail_button.clicked.connect (() => open_uri ("mailto:" + mail));
            foreach (var button in new Gtk.Button[] { write, call, mail_button }) {
                button.add_css_class ("contact-action");
                actions.append (button);
            }
            if (phone == "") {
                Idle.add (() => {  // CallButton turns itself on with the hands-free link
                    call.sensitive = false;
                    return Source.REMOVE;
                });
            }
        }

        private static Gtk.Widget action_child (string icon, string label) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            box.append (new Gtk.Image.from_icon_name (icon));
            var text = new Gtk.Label (label);
            text.add_css_class (Granite.CssClass.SMALL);
            box.append (text);
            return box;
        }

        /* One line of the card: label above, value below, buttons at the end. */
        private void add_field (string label, string value, Gtk.Widget[]? buttons, bool wrap = false) {
            var kind = new Gtk.Label (label) { xalign = 0 };
            kind.add_css_class (Granite.CssClass.DIM);
            kind.add_css_class (Granite.CssClass.SMALL);
            var text = new Gtk.Label (value) {
                xalign = 0,
                selectable = true,
                wrap = wrap,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                ellipsize = wrap ? Pango.EllipsizeMode.NONE : Pango.EllipsizeMode.END
            };
            var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
            column.append (kind);
            column.append (text);
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 12,
                margin_end = 6
            };
            box.append (column);
            if (buttons != null) {
                foreach (var button in buttons) {
                    box.append (button);
                }
            }
            detail_list.append (new Gtk.ListBoxRow () { child = box, activatable = false });
        }

        private static Gtk.Button row_button (string icon, string tooltip) {
            var button = new Gtk.Button.from_icon_name (icon) { tooltip_text = tooltip, valign = Gtk.Align.CENTER };
            button.add_css_class ("flat");
            return button;
        }

        private void add_phone (string label, string number) {
            var write = row_button ("internet-chat-symbolic", _("Envoyer un message"));
            write.clicked.connect (() => message_requested (number));
            add_field (phone_label (label), format_address (number),
                       { write, new CallButton (daemon, number, toast) });
        }

        private void add_mail (string label, string address) {
            var write = row_button ("mail-send-symbolic", _("Écrire un courriel"));
            write.clicked.connect (() => open_uri ("mailto:" + address));
            add_field (mail_label (label), address, { write });
        }

        private void add_postal (string label, string street, string city, string region,
                                 string postcode, string country) {
            // French order: street, then postcode and city, region, country.
            string[] lines = {};
            foreach (var line in new string[] { street, (postcode + " " + city).strip (), region, country }) {
                if (line.strip () != "") {
                    lines += line.strip ();
                }
            }
            var text = string.joinv ("\n", lines);
            var copy = row_button ("edit-copy-symbolic", _("Copier l'adresse"));
            copy.clicked.connect (() => {
                get_clipboard ().set_text (text);
                toast.title = _("Adresse copiée");
                toast.send_notification ();
            });
            add_field (postal_label (label), text, { copy }, true);
        }

        private void add_url (string label, string url) {
            var target = url.contains ("://") ? url : "https://" + url;
            var open = row_button ("web-browser-symbolic", _("Ouvrir dans le navigateur"));
            open.clicked.connect (() => open_uri (target));
            add_field (url_label (label), url, { open });
        }

        private void open_uri (string uri) {
            new Gtk.UriLauncher (uri).launch.begin (get_root () as Gtk.Window, null);
        }

        /* --- export and sending ------------------------------------------------------- */

        private static string vcard_name (string name) {
            var clean = name.replace ("/", " ").replace ("\\", " ").strip ();
            return (clean != "" ? clean : _("Contact")) + ".vcf";
        }

        private async string? export_text (string[] keys) {
            try {
                var reply = yield daemon.call_slow ("ExportContacts", new Variant ("(^as)", keys));
                string text;
                reply.get ("(s)", out text);
                return text;
            } catch (Error e) {
                show_problem (_("Export impossible"), clean_error (e));
                return null;
            }
        }

        private async void export_cards (string[] keys, string file_name) {
            var dialog = new Gtk.FileDialog () {
                title = keys.length == 1 ? _("Exporter la fiche") : _("Exporter tous les contacts"),
                initial_name = file_name,
                modal = true
            };
            File file;
            try {
                file = yield dialog.save (get_root () as Gtk.Window, null);
            } catch (Error e) {
                return;  // dismissed
            }
            var text = yield export_text (keys);
            if (text == null) {
                return;
            }
            try {
                yield file.replace_contents_bytes_async (new Bytes (text.data), null, false,
                                                         FileCreateFlags.REPLACE_DESTINATION, null, null);
                var count = text.up ().split ("BEGIN:VCARD").length - 1;
                toast.title = ngettext ("%d fiche exportée", "%d fiches exportées", count).printf (count);
                toast.send_notification ();
            } catch (Error e) {
                show_problem (_("Export impossible"), e.message);
            }
        }

        /* LocalSend devices of the network, each a button sending the card to it. */
        private async void fill_share_popover () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3) {
                margin_top = 9, margin_bottom = 9, margin_start = 9, margin_end = 9, width_request = 240
            };
            var title = new Gtk.Label (_("Envoyer par LocalSend")) { xalign = 0, margin_bottom = 3 };
            title.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
            box.append (title);
            share_button.popover.child = box;
            var peers = yield daemon.call_list ("ListFilePeers");
            if (peers.length == 0) {
                var none = new Gtk.Label (_("Aucun appareil LocalSend trouvé sur le réseau. Ouvrez LocalSend sur l'iPhone.")) {
                    xalign = 0, wrap = true, max_width_chars = 30
                };
                none.add_css_class (Granite.CssClass.DIM);
                box.append (none);
                return;
            }
            foreach (var item in peers) {
                var peer = new VariantDict (item);
                var id = dict_string (peer, "id");
                var button = menu_button (dict_string (peer, "alias"));
                button.clicked.connect (() => {
                    share_button.popover.popdown ();
                    send_card.begin (id);
                });
                box.append (button);
            }
        }

        private async void send_card (string peer) {
            if (shown == null) {
                return;
            }
            var name = vcard_name (shown.name);
            var text = yield export_text ({ shown.key });
            if (text == null) {
                return;
            }
            var folder = Path.build_filename (Environment.get_user_cache_dir (), "boomerang", "contacts-export");
            DirUtils.create_with_parents (folder, 0700);
            var path = Path.build_filename (folder, name);
            try {
                FileUtils.set_contents_full (path, text, -1, FileSetContentsFlags.CONSISTENT, 0600);
                yield daemon.call_checked ("SendFiles", new Variant ("(s^as)", peer, new string[] { path }));
                toast.title = _("Fiche envoyée par LocalSend");
                toast.send_notification ();
            } catch (Error e) {
                show_problem (_("Envoi impossible"), clean_error (e));
            }
        }

        /* --- import ------------------------------------------------------------------- */

        private async void choose_import () {
            var filter = new Gtk.FileFilter () { name = _("Fiches de contact (vCard)") };
            filter.add_mime_type ("text/vcard");
            filter.add_mime_type ("text/x-vcard");
            filter.add_mime_type ("text/directory");
            filter.add_suffix ("vcf");
            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            var dialog = new Gtk.FileDialog () {
                title = _("Importer des fiches vCard"), filters = filters, modal = true
            };
            try {
                var chosen = yield dialog.open_multiple (get_root () as Gtk.Window, null);
                File[] files = {};
                for (uint i = 0; i < chosen.get_n_items (); i++) {
                    files += (File) chosen.get_item (i);
                }
                yield import_files (files);
            } catch (Error e) {
                // dismissed
            }
        }

        private async void import_files (File[] files) {
            if (files.length == 0) {
                return;
            }
            if (!editable ()) {
                show_problem (_("Import dans iCloud seulement"),
                    _("Les fiches importées sont enregistrées dans iCloud, qui les transmet à l'iPhone. "
                    + "Choisissez « Gestion via iCloud » dans le menu de la liste, puis recommencez."));
                return;
            }
            var text = new StringBuilder ();
            foreach (var file in files) {
                try {
                    var info = yield file.query_info_async (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                    if (info.get_size () > 20 * 1024 * 1024) {
                        show_problem (_("Fichier trop volumineux"),
                                      _("%s dépasse 20 Mo.").printf (file.get_basename ()));
                        return;
                    }
                    uint8[] contents;
                    yield file.load_contents_async (null, out contents, null);
                    text.append ((string) contents);
                    text.append ("\r\n");
                } catch (Error e) {
                    show_problem (_("Fichier illisible"), e.message);
                    return;
                }
            }
            var data = text.str.make_valid ();
            Variant[] found;
            try {
                var reply = yield daemon.call_checked ("PreviewContactsImport", new Variant ("(s)", data));
                var array = reply.get_child_value (0);
                found = {};
                for (size_t i = 0; i < array.n_children (); i++) {
                    found += array.get_child_value (i);
                }
            } catch (Error e) {
                show_problem (_("Import impossible"), clean_error (e));
                return;
            }
            confirm_import (data, found);
        }

        private void confirm_import (string data, Variant[] found) {
            string[] names = {};
            int fresh = 0, duplicates = 0;
            foreach (var item in found) {
                var card = new VariantDict (item);
                if (dict_bool (card, "duplicate")) {
                    duplicates++;
                } else {
                    fresh++;
                    if (names.length < 3) {
                        names += dict_string (card, "name");
                    }
                }
            }
            if (found.length == 0) {
                show_problem (_("Aucune fiche à importer"),
                              _("Ce fichier ne contient aucune fiche de contact au format vCard."));
                return;
            }
            if (fresh == 0) {
                show_problem (_("Fiches déjà présentes"),
                    ngettext ("La fiche de ce fichier est déjà dans vos contacts iCloud.",
                              "Les %d fiches de ce fichier sont déjà dans vos contacts iCloud.",
                              duplicates).printf (duplicates));
                return;
            }
            var list = string.joinv (", ", names);
            if (fresh > names.length) {
                list = ngettext ("%s et %d autre", "%s et %d autres", fresh - names.length)
                    .printf (list, fresh - names.length);
            }
            var body = list + ".";
            if (duplicates > 0) {
                body += " " + ngettext ("%d fiche déjà présente sera ignorée.",
                                        "%d fiches déjà présentes seront ignorées.", duplicates).printf (duplicates);
            }
            body += " " + _("iCloud transmet les nouvelles fiches à l'iPhone.");
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                ngettext ("Importer %d fiche dans iCloud ?", "Importer %d fiches dans iCloud ?", fresh).printf (fresh),
                body, "document-import", Gtk.ButtonsType.CANCEL) {
                transient_for = get_root () as Gtk.Window,
                modal = true
            };
            var accept = dialog.add_button (_("Importer"), Gtk.ResponseType.ACCEPT);
            accept.add_css_class (Granite.CssClass.SUGGESTED);
            dialog.response.connect ((response) => {
                dialog.destroy ();
                if (response == Gtk.ResponseType.ACCEPT) {
                    run_import.begin (data);
                }
            });
            dialog.present ();
        }

        private async void run_import (string data) {
            toast.title = _("Import en cours…");
            toast.send_notification ();
            try {
                var reply = yield daemon.call_slow ("ImportContacts", new Variant ("(s)", data));
                var report = new VariantDict (reply.get_child_value (0));
                uint added = 0, duplicates = 0, failed = 0;
                report.lookup ("added", "u", out added);
                report.lookup ("duplicates", "u", out duplicates);
                report.lookup ("failed", "u", out failed);
                string[] lines = {
                    ngettext ("%u fiche ajoutée dans iCloud.", "%u fiches ajoutées dans iCloud.", added).printf (added)
                };
                if (duplicates > 0) {
                    lines += ngettext ("%u fiche déjà présente, ignorée.", "%u fiches déjà présentes, ignorées.",
                                       duplicates).printf (duplicates);
                }
                if (failed > 0) {
                    lines += ngettext ("%u fiche refusée par iCloud.", "%u fiches refusées par iCloud.",
                                       failed).printf (failed);
                }
                var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                    _("Import terminé"), string.joinv ("\n", lines),
                    failed > 0 ? "dialog-warning" : "process-completed", Gtk.ButtonsType.CLOSE) {
                    transient_for = get_root () as Gtk.Window,
                    modal = true
                };
                dialog.response.connect (() => dialog.destroy ());
                dialog.present ();
            } catch (Error e) {
                show_problem (_("Import interrompu"), clean_error (e));
            }
        }

        private void show_problem (string title, string text) {
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                title, text, "dialog-information", Gtk.ButtonsType.CLOSE) {
                transient_for = get_root () as Gtk.Window,
                modal = true
            };
            dialog.response.connect (() => dialog.destroy ());
            dialog.present ();
        }

        private static string clean_error (Error e) {
            if (e is DBusError) {
                DBusError.strip_remote_error (e);
            }
            return e.message;
        }
    }

    /* (label, value) pairs of a card field (a(ss)), flattened: label, value, label, value… */
    public string[] pairs (VariantDict d, string key) {
        string[] result = {};
        var items = d.lookup_value (key, new VariantType ("a(ss)"));
        if (items != null) {
            for (size_t i = 0; i < items.n_children (); i++) {
                string label, value;
                items.get_child (i, "(ss)", out label, out value);
                result += label;
                result += value;
            }
        }
        return result;
    }

    /* Labels of the card's lines: Boomerang's keys in words, the user's own labels as written. */
    public string phone_label (string key) {
        switch (key) {
            case "": return _("téléphone");
            case "mobile": return _("mobile");
            case "iphone": return "iPhone";
            case "domicile": return _("domicile");
            case "travail": return _("travail");
            case "principal": return _("principal");
            case "autre": return _("autre");
            default: return key;
        }
    }

    public string mail_label (string key) {
        switch (key) {
            case "": return _("courriel");
            case "domicile": return _("courriel personnel");
            case "travail": return _("courriel professionnel");
            case "autre": return _("autre courriel");
            default: return key;
        }
    }

    public string postal_label (string key) {
        switch (key) {
            case "": return _("adresse");
            case "domicile": return _("adresse personnelle");
            case "travail": return _("adresse professionnelle");
            case "autre": return _("autre adresse");
            default: return key;
        }
    }

    public string url_label (string key) {
        switch (key) {
            case "": return _("site web");
            case "accueil": return _("page d'accueil");
            case "domicile": return _("site personnel");
            case "travail": return _("site professionnel");
            case "autre": return _("autre site");
            default: return key;
        }
    }

    public string date_label (string key) {
        switch (key) {
            case "anniversaire": return _("date anniversaire");
            case "": case "autre": return _("autre date");
            default: return key;
        }
    }

    /* "1990-05-12" -> "12 mai 1990", "--05-12" -> "12 mai" (the system's month names). */
    public string format_date (string date) {
        var no_year = date.has_prefix ("--");
        var parts = (no_year ? date.substring (2) : date).split ("-");
        if ((no_year && parts.length != 2) || (!no_year && parts.length != 3)) {
            return date;
        }
        var year = no_year ? 2000 : int.parse (parts[0]);
        var month = int.parse (parts[no_year ? 0 : 1]);
        var day = int.parse (parts[no_year ? 1 : 2]);
        var when = new DateTime.local (year, month, day, 0, 0, 0);
        if (when == null) {
            return date;
        }
        return when.format (no_year ? "%-d %B" : "%-d %B %Y");
    }
}
