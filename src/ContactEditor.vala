// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Edit or create a contact card in iCloud (Contacts managed through iCloud): photo,
 * names, company, numbers, e-mails, postal addresses, web sites, birthday, other
 * dates, notes. iCloud then brings the change to the iPhone. Deleting asks first.
 */

public class Boomerang.ContactEditor : Gtk.Window {
    public Daemon daemon { get; construct; }
    public string uid { get; construct; }

    public signal void saved (string uid);

    private const string[] PHONE_KEYS = { "mobile", "iphone", "domicile", "travail", "principal", "autre" };
    private const string[] PHONE_NAMES = { N_("mobile"), "iPhone", N_("domicile"), N_("travail"), N_("principal"), N_("autre") };
    private const string[] EMAIL_KEYS = { "domicile", "travail", "autre" };
    private const string[] EMAIL_NAMES = { N_("domicile"), N_("travail"), N_("autre") };
    private const string[] ADDRESS_KEYS = { "domicile", "travail", "autre" };
    private const string[] ADDRESS_NAMES = { N_("domicile"), N_("travail"), N_("autre") };
    private const string[] URL_KEYS = { "accueil", "domicile", "travail", "autre" };
    private const string[] URL_NAMES = { N_("page d'accueil"), N_("personnel"), N_("professionnel"), N_("autre") };
    private const string[] DATE_KEYS = { "anniversaire", "autre" };
    private const string[] DATE_NAMES = { N_("date anniversaire"), N_("autre") };

    private Avatar avatar;
    private Gtk.Button remove_photo;
    private Gtk.Entry given;
    private Gtk.Entry family;
    private Gtk.Entry nickname;
    private Gtk.Entry org;
    private Gtk.Entry title_entry;
    private Gtk.Entry birthday;
    private Gtk.TextView note;
    private Gtk.ListBox phones;
    private Gtk.ListBox emails;
    private Gtk.ListBox addresses;
    private Gtk.ListBox urls;
    private Gtk.ListBox dates;
    private Gtk.Button save_button;
    private Gtk.Label error;
    private Gtk.Stack stack;

    private string photo_path = "";       // the card's photo when the editor opened
    private uint8[]? new_photo = null;    // chosen and cropped here, JPEG
    private bool photo_removed = false;

    public ContactEditor (Gtk.Window? parent, Daemon daemon, string uid) {
        Object (transient_for: parent, modal: true, daemon: daemon, uid: uid,
                title: uid == "" ? _("Nouveau contact") : _("Modifier le contact"),
                default_width: 480, default_height: 680);
    }

    construct {
        var header = new Gtk.HeaderBar ();
        header.add_css_class ("flat");
        titlebar = header;

        avatar = new Avatar (96) { margin_top = 6 };
        avatar.show_person ("", "");
        var choose_photo = new Gtk.Button.with_label (_("Choisir une photo…"));
        choose_photo.clicked.connect (() => pick_photo.begin ());
        remove_photo = new Gtk.Button.with_label (_("Retirer la photo")) { visible = false };
        remove_photo.clicked.connect (() => {
            new_photo = null;
            photo_removed = true;
            update_avatar ();
        });
        var photo_buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { halign = Gtk.Align.CENTER };
        foreach (var b in new Gtk.Button[] { choose_photo, remove_photo }) {
            b.add_css_class ("flat");
            b.add_css_class (Granite.CssClass.SMALL);
            photo_buttons.append (b);
        }

        given = new Gtk.Entry ();
        family = new Gtk.Entry ();
        nickname = new Gtk.Entry ();
        org = new Gtk.Entry ();
        title_entry = new Gtk.Entry ();
        foreach (var entry in new Gtk.Entry[] { given, family, nickname, org, title_entry }) {
            entry.changed.connect (update_avatar);
        }
        // Labels beside the fields: once filled, a placeholder no longer says which is which.
        var names = new Gtk.Grid () { column_spacing = 12, row_spacing = 6, margin_top = 6 };
        string[] captions = { _("Prénom"), _("Nom"), _("Surnom"), _("Entreprise"), _("Fonction") };
        Gtk.Entry[] fields = { given, family, nickname, org, title_entry };
        for (int i = 0; i < fields.length; i++) {
            var caption = new Gtk.Label (captions[i]) { xalign = 1 };
            caption.add_css_class (Granite.CssClass.DIM);
            fields[i].hexpand = true;
            fields[i].update_property (Gtk.AccessibleProperty.LABEL, captions[i], -1);
            names.attach (caption, 0, i);
            names.attach (fields[i], 1, i);
        }

        phones = list_box ();
        emails = list_box ();
        addresses = list_box ();
        urls = list_box ();
        dates = list_box ();
        birthday = new Gtk.Entry () {
            placeholder_text = _("jj/mm/aaaa, ou jj/mm sans l'année"),
            input_purpose = Gtk.InputPurpose.DIGITS
        };

        note = new Gtk.TextView () {
            wrap_mode = Gtk.WrapMode.WORD_CHAR,
            top_margin = 6,
            bottom_margin = 6,
            left_margin = 6,
            right_margin = 6,
            height_request = 64
        };
        note.add_css_class (Granite.CssClass.CARD);

        error = new Gtk.Label ("") { wrap = true, xalign = 0, visible = false };
        error.add_css_class (Granite.CssClass.ERROR);

        var hint = new Gtk.Label (
            _("La fiche est enregistrée dans iCloud, qui la transmet à l'iPhone en quelques secondes.")
        ) { wrap = true, xalign = 0 };
        hint.add_css_class (Granite.CssClass.DIM);
        hint.add_css_class (Granite.CssClass.SMALL);

        var form = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
            margin_start = 24,
            margin_end = 24,
            margin_bottom = 12
        };
        form.append (avatar);
        form.append (photo_buttons);
        form.append (names);
        section (form, _("Téléphone"), phones, _("Ajouter un numéro"),
                 () => add_entry (phones, PHONE_KEYS, PHONE_NAMES, "mobile", "", true));
        section (form, _("Courriel"), emails, _("Ajouter une adresse de courriel"),
                 () => add_entry (emails, EMAIL_KEYS, EMAIL_NAMES, "domicile", "", true));
        section (form, _("Adresse postale"), addresses, _("Ajouter une adresse"),
                 () => add_address ("domicile", "", "", "", "", "", true));
        section (form, _("Site web"), urls, _("Ajouter un site"),
                 () => add_entry (urls, URL_KEYS, URL_NAMES, "accueil", "", true));
        form.append (new Granite.HeaderLabel (_("Anniversaire")));
        form.append (birthday);
        section (form, _("Autres dates"), dates, _("Ajouter une date"),
                 () => add_entry (dates, DATE_KEYS, DATE_NAMES, "anniversaire", "", true));
        form.append (new Granite.HeaderLabel (_("Notes")));
        form.append (note);
        form.append (hint);
        form.append (error);

        var cancel = new Gtk.Button.with_label (_("Annuler"));
        cancel.clicked.connect (() => close ());
        save_button = new Gtk.Button.with_label (_("Enregistrer"));
        save_button.add_css_class (Granite.CssClass.SUGGESTED);
        save_button.clicked.connect (() => save.begin ());
        var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_start = 24,
            margin_end = 24,
            margin_top = 6,
            margin_bottom = 24
        };
        if (uid != "") {
            var delete_button = new Gtk.Button.with_label (_("Supprimer"));
            delete_button.add_css_class (Granite.CssClass.DESTRUCTIVE);
            delete_button.clicked.connect (confirm_delete);
            actions.append (delete_button);
        }
        var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true };
        actions.append (spacer);
        actions.append (cancel);
        actions.append (save_button);

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        content.append (new Gtk.ScrolledWindow () {
            child = form,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        });
        content.append (actions);

        var spinner = new Gtk.Spinner () { spinning = true, halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER };
        stack = new Gtk.Stack ();
        stack.add_named (spinner, "loading");
        stack.add_named (content, "form");
        child = stack;

        if (uid == "") {
            add_entry (phones, PHONE_KEYS, PHONE_NAMES, "mobile", "", false);
            stack.visible_child_name = "form";
        } else {
            load.begin ();
        }
    }

    private delegate void AddRow ();

    private void section (Gtk.Box form, string title, Gtk.ListBox list, string add_label, owned AddRow add) {
        var button = new Gtk.Button.with_label (add_label) { halign = Gtk.Align.START };
        button.add_css_class ("flat");
        button.clicked.connect (() => add ());
        form.append (new Granite.HeaderLabel (title));
        form.append (list);
        form.append (button);
    }

    private static Gtk.ListBox list_box () {
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
        list.add_css_class (Granite.CssClass.CARD);
        return list;
    }

    private static string full_name (string first, string second) {
        return (first.strip () + " " + second.strip ()).strip ();
    }

    private void update_avatar () {
        var name = full_name (given.text, family.text);
        if (name == "") {
            name = org.text.strip ();
        }
        if (new_photo != null) {
            try {
                var texture = Gdk.Texture.from_bytes (new Bytes (new_photo));
                avatar.show_paintable (name, texture);
            } catch (Error e) {
                avatar.show_person (name, "");
            }
        } else {
            avatar.show_person (name, photo_removed ? "" : photo_path);
        }
        remove_photo.visible = new_photo != null || (!photo_removed && photo_path != "");
    }

    /* A label drop-down for a row; a label of the card's own (Apple custom label) is added. */
    private static Gtk.DropDown label_dropdown (string[] base_keys, string[] names, string label,
                                                out string[] keys) {
        string[] own = base_keys;
        var shown = new Gtk.StringList (null);
        foreach (var name in names) {
            shown.append (_(name));
        }
        bool known = false;
        foreach (var key in own) {
            known = known || key == label;
        }
        if (!known && label != "") {
            own += label;
            shown.append (label);
        }
        keys = own;
        var dropdown = new Gtk.DropDown (shown, null) { valign = Gtk.Align.START };
        for (int i = 0; i < keys.length; i++) {
            if (keys[i] == label) {
                dropdown.selected = i;
            }
        }
        dropdown.update_property (Gtk.AccessibleProperty.LABEL, _("Libellé"), -1);
        return dropdown;
    }

    private static Gtk.Button remove_button () {
        var remove = new Gtk.Button.from_icon_name ("list-remove-symbolic") {
            valign = Gtk.Align.START,
            tooltip_text = _("Retirer")
        };
        remove.add_css_class ("flat");
        return remove;
    }

    /* A row: label drop-down, value entry, remove button. */
    private void add_entry (Gtk.ListBox list, string[] keys, string[] names, string label, string value,
                            bool focus) {
        string[] row_keys;
        var dropdown = label_dropdown (keys, names, label, out row_keys);
        dropdown.valign = Gtk.Align.CENTER;
        var entry = new Gtk.Entry () { text = value, hexpand = true };
        if (list == phones) {
            entry.input_purpose = Gtk.InputPurpose.PHONE;
        } else if (list == emails) {
            entry.input_purpose = Gtk.InputPurpose.EMAIL;
        } else if (list == urls) {
            entry.input_purpose = Gtk.InputPurpose.URL;
            entry.placeholder_text = "https://";
        } else if (list == dates) {
            entry.placeholder_text = _("jj/mm/aaaa");
        }
        entry.changed.connect (() => entry.remove_css_class (Granite.CssClass.ERROR));
        var remove = remove_button ();
        remove.valign = Gtk.Align.CENTER;
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_top = 4,
            margin_bottom = 4,
            margin_start = 6,
            margin_end = 4
        };
        box.append (dropdown);
        box.append (entry);
        box.append (remove);
        var row = new EntryRow (row_keys, dropdown, entry) { child = box, activatable = false };
        remove.clicked.connect (() => list.remove (row));
        list.append (row);
        if (focus) {
            entry.grab_focus ();
        }
    }

    /* A postal address: label, street, postcode and city, region, country. */
    private void add_address (string label, string street, string city, string region, string postcode,
                              string country, bool focus) {
        string[] keys;
        var dropdown = label_dropdown (ADDRESS_KEYS, ADDRESS_NAMES, label, out keys);
        var street_entry = new Gtk.Entry () {
            text = street.replace ("\n", ", "), placeholder_text = _("Rue"), hexpand = true
        };
        var postcode_entry = new Gtk.Entry () {
            text = postcode, placeholder_text = _("Code postal"), width_chars = 8, max_width_chars = 8
        };
        var city_entry = new Gtk.Entry () { text = city, placeholder_text = _("Ville"), hexpand = true };
        var region_entry = new Gtk.Entry () { text = region, placeholder_text = _("Région") };
        var country_entry = new Gtk.Entry () { text = country, placeholder_text = _("Pays") };
        var city_line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        city_line.append (postcode_entry);
        city_line.append (city_entry);
        var fields = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) { hexpand = true };
        fields.append (street_entry);
        fields.append (city_line);
        fields.append (region_entry);
        fields.append (country_entry);
        var remove = remove_button ();
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 6,
            margin_end = 4
        };
        box.append (dropdown);
        box.append (fields);
        box.append (remove);
        var row = new AddressRow (keys, dropdown, { street_entry, city_entry, region_entry, postcode_entry,
                                                    country_entry }) { child = box, activatable = false };
        remove.clicked.connect (() => addresses.remove (row));
        addresses.append (row);
        if (focus) {
            street_entry.grab_focus ();
        }
    }

    private Variant entries (Gtk.ListBox list) {
        var builder = new VariantBuilder (new VariantType ("a(ss)"));
        for (int i = 0; ; i++) {
            var row = list.get_row_at_index (i) as EntryRow;
            if (row == null) {
                break;
            }
            var value = row.entry.text.strip ();
            if (value == "") {
                continue;
            }
            if (list == urls && !value.contains ("://")) {
                value = "https://" + value;
            } else if (list == dates) {
                value = parse_date (value);
            }
            builder.add ("(ss)", row.keys[row.dropdown.selected], value);
        }
        return builder.end ();
    }

    private Variant postal_entries () {
        var builder = new VariantBuilder (new VariantType ("a(ssssss)"));
        for (int i = 0; ; i++) {
            var row = addresses.get_row_at_index (i) as AddressRow;
            if (row == null) {
                break;
            }
            string[] v = {};
            bool any = false;
            foreach (var entry in row.entries) {
                v += entry.text.strip ();
                any = any || entry.text.strip () != "";
            }
            if (any) {
                builder.add ("(ssssss)", row.keys[row.dropdown.selected], v[0], v[1], v[2], v[3], v[4]);
            }
        }
        return builder.end ();
    }

    private async void load () {
        stack.visible_child_name = "loading";
        try {
            var reply = yield daemon.call_checked ("GetContact", new Variant ("(s)", uid));
            var card = new VariantDict (reply.get_child_value (0));
            given.text = dict_string (card, "given");
            family.text = dict_string (card, "family");
            nickname.text = dict_string (card, "nickname");
            org.text = dict_string (card, "org");
            title_entry.text = dict_string (card, "title");
            note.buffer.text = dict_string (card, "note");
            birthday.text = show_date (dict_string (card, "birthday"));
            photo_path = dict_string (card, "photo");
            fill (card, "phones", phones, PHONE_KEYS, PHONE_NAMES);
            fill (card, "emails", emails, EMAIL_KEYS, EMAIL_NAMES);
            fill (card, "urls", urls, URL_KEYS, URL_NAMES);
            fill (card, "dates", dates, DATE_KEYS, DATE_NAMES);
            var postal = card.lookup_value ("addresses", new VariantType ("a(ssssss)"));
            if (postal != null) {
                for (size_t i = 0; i < postal.n_children (); i++) {
                    string label, street, city, region, postcode, country;
                    postal.get_child (i, "(ssssss)", out label, out street, out city, out region, out postcode,
                                      out country);
                    add_address (label != "" ? label : "autre", street, city, region, postcode, country, false);
                }
            }
            update_avatar ();
            stack.visible_child_name = "form";
        } catch (Error e) {
            stack.visible_child_name = "form";
            show_error (_("Fiche illisible : %s").printf (clean (e)));
            save_button.sensitive = false;
        }
    }

    private void fill (VariantDict card, string key, Gtk.ListBox list, string[] keys, string[] names) {
        var items = card.lookup_value (key, new VariantType ("a(ss)"));
        if (items == null) {
            return;
        }
        for (size_t i = 0; i < items.n_children (); i++) {
            string label, value;
            items.get_child (i, "(ss)", out label, out value);
            if (list == dates) {
                value = show_date (value);
            }
            add_entry (list, keys, names, label != "" ? label : keys[keys.length - 1], value, false);
        }
    }

    /* --- photo -------------------------------------------------------------------------- */

    private async void pick_photo () {
        var filter = new Gtk.FileFilter () { name = _("Images") };
        filter.add_mime_type ("image/png");
        filter.add_mime_type ("image/jpeg");
        filter.add_mime_type ("image/webp");
        filter.add_mime_type ("image/heif");
        var filters = new ListStore (typeof (Gtk.FileFilter));
        filters.append (filter);
        var dialog = new Gtk.FileDialog () { title = _("Photo du contact"), filters = filters, modal = true };
        var pictures = Environment.get_user_special_dir (UserDirectory.PICTURES);
        if (pictures != null) {
            dialog.initial_folder = File.new_for_path (pictures);
        }
        File file;
        try {
            file = yield dialog.open (this, null);
        } catch (Error e) {
            return;  // dismissed
        }
        Gdk.Pixbuf pixbuf;
        try {
            // Large photos are brought down first: the crop keeps 512 pixels at most.
            pixbuf = new Gdk.Pixbuf.from_file_at_scale (file.get_path (), 2048, 2048, true);
            pixbuf = pixbuf.apply_embedded_orientation () ?? pixbuf;
        } catch (Error e) {
            show_error (_("Image illisible : %s").printf (e.message));
            return;
        }
        var crop = new PhotoCropDialog (this, pixbuf);
        crop.chosen.connect ((jpeg) => {
            new_photo = jpeg;
            photo_removed = false;
            update_avatar ();
        });
        crop.present ();
    }

    /* --- validation and saving ---------------------------------------------------------- */

    /* « 12/05/1990 », « 12.5.1990 », « 1990-05-12 » -> « 1990-05-12 »; « 12/05 » -> « --05-12 »;
       "" when it is not a date. */
    public static string parse_date (string text) {
        var t = text.strip ();
        int day = 0, month = 0, year = 0;
        MatchInfo match;
        if (/^(\d{4})-(\d{1,2})-(\d{1,2})$/.match (t, 0, out match)) {
            year = int.parse (match.fetch (1));
            month = int.parse (match.fetch (2));
            day = int.parse (match.fetch (3));
        } else if (/^(\d{1,2})[\/.\- ](\d{1,2})(?:[\/.\- ](\d{4}))?$/.match (t, 0, out match)) {
            day = int.parse (match.fetch (1));
            month = int.parse (match.fetch (2));
            var y = match.fetch (3);
            year = y != null && y != "" ? int.parse (y) : 0;
        } else {
            return "";
        }
        if (month < 1 || month > 12 || day < 1
            || !Date.valid_dmy ((DateDay) day, (DateMonth) month, (DateYear) (year > 0 ? year : 2000))
            || (year > 0 && (year < 1800 || year > 2200))) {
            return "";
        }
        return year > 0 ? "%04d-%02d-%02d".printf (year, month, day) : "--%02d-%02d".printf (month, day);
    }

    /* The card's « 1990-05-12 » or « --05-12 » as typed in the editor. */
    public static string show_date (string date) {
        if (date.has_prefix ("--") && date.length == 7) {
            return "%s/%s".printf (date.substring (5, 2), date.substring (2, 2));
        }
        if (date.length == 10) {
            return "%s/%s/%s".printf (date.substring (8, 2), date.substring (5, 2), date.substring (0, 4));
        }
        return date;
    }

    public static bool valid_phone (string number) {
        return only_digits (number).length >= 2 && /^[0-9+()\-.\/ *#pPwW,;]+$/.match (number.strip ());
    }

    public static bool valid_email (string address) {
        var at = address.index_of ("@");
        return at > 0 && address.last_index_of (".") > at + 1 && !address.contains (" ")
               && !address.has_suffix (".");
    }

    /* First problem of the form, the faulty field marked; null when it can be saved. */
    private string? check () {
        if (given.text.strip () == "" && family.text.strip () == "" && org.text.strip () == "") {
            given.add_css_class (Granite.CssClass.ERROR);
            given.grab_focus ();
            return _("Indiquez au moins un prénom, un nom ou une entreprise.");
        }
        given.remove_css_class (Granite.CssClass.ERROR);
        string? problem = null;
        problem = problem ?? check_list (phones, (v) => valid_phone (v),
                                         _("Numéro de téléphone non valable : « %s »."));
        problem = problem ?? check_list (emails, (v) => valid_email (v),
                                         _("Adresse de courriel non valable : « %s »."));
        problem = problem ?? check_list (urls, (v) => !v.contains (" ") && v.length > 3,
                                         _("Adresse de site non valable : « %s »."));
        problem = problem ?? check_list (dates, (v) => parse_date (v) != "",
                                         _("Date non valable : « %s ». Écrivez jj/mm/aaaa, ou jj/mm."));
        if (problem == null && birthday.text.strip () != "" && parse_date (birthday.text) == "") {
            birthday.add_css_class (Granite.CssClass.ERROR);
            birthday.grab_focus ();
            problem = _("Anniversaire non valable : « %s ». Écrivez jj/mm/aaaa, ou jj/mm.")
                .printf (birthday.text.strip ());
        } else {
            birthday.remove_css_class (Granite.CssClass.ERROR);
        }
        return problem;
    }

    private delegate bool Valid (string value);

    private string? check_list (Gtk.ListBox list, Valid valid, string message) {
        for (int i = 0; ; i++) {
            var row = list.get_row_at_index (i) as EntryRow;
            if (row == null) {
                return null;
            }
            var value = row.entry.text.strip ();
            if (value != "" && !valid (value)) {
                row.entry.add_css_class (Granite.CssClass.ERROR);
                row.entry.grab_focus ();
                return message.printf (value);
            }
        }
    }

    private async void save () {
        var problem = check ();
        if (problem != null) {
            show_error (problem);
            return;
        }
        var card = new VariantBuilder (new VariantType ("a{sv}"));
        card.add ("{sv}", "uid", new Variant.string (uid));
        card.add ("{sv}", "given", new Variant.string (given.text.strip ()));
        card.add ("{sv}", "family", new Variant.string (family.text.strip ()));
        card.add ("{sv}", "nickname", new Variant.string (nickname.text.strip ()));
        card.add ("{sv}", "org", new Variant.string (org.text.strip ()));
        card.add ("{sv}", "title", new Variant.string (title_entry.text.strip ()));
        card.add ("{sv}", "note", new Variant.string (note.buffer.text.strip ()));
        card.add ("{sv}", "birthday", new Variant.string (parse_date (birthday.text)));
        card.add ("{sv}", "phones", entries (phones));
        card.add ("{sv}", "emails", entries (emails));
        card.add ("{sv}", "addresses", postal_entries ());
        card.add ("{sv}", "urls", entries (urls));
        card.add ("{sv}", "dates", entries (dates));
        if (new_photo != null) {
            card.add ("{sv}", "photo_data", new Variant.from_bytes (new VariantType ("ay"), new Bytes (new_photo), true));
        } else if (photo_removed) {
            card.add ("{sv}", "photo_remove", new Variant.boolean (true));
        }
        save_button.sensitive = false;
        error.visible = false;
        try {
            var reply = yield daemon.call_checked ("SaveContact", new Variant.tuple ({ card.end () }));
            string new_uid;
            reply.get ("(s)", out new_uid);
            saved (new_uid);
            close ();
        } catch (Error e) {
            show_error (_("Non enregistré : %s").printf (clean (e)));
            save_button.sensitive = true;
        }
    }

    private void confirm_delete () {
        var name = (given.text + " " + family.text).strip ();
        var dialog = new Granite.MessageDialog.with_image_from_icon_name (
            _("Supprimer %s ?").printf (name != "" ? name : _("ce contact")),
            _("La fiche est supprimée d'iCloud, donc aussi de l'iPhone et de vos autres appareils."),
            "edit-delete", Gtk.ButtonsType.CANCEL) {
            transient_for = this,
            modal = true
        };
        var remove = dialog.add_button (_("Supprimer"), Gtk.ResponseType.ACCEPT);
        remove.add_css_class (Granite.CssClass.DESTRUCTIVE);
        dialog.response.connect ((response) => {
            dialog.destroy ();
            if (response == Gtk.ResponseType.ACCEPT) {
                delete_card.begin ();
            }
        });
        dialog.present ();
    }

    private async void delete_card () {
        try {
            yield daemon.call_checked ("DeleteContact", new Variant ("(s)", uid));
            saved ("");
            close ();
        } catch (Error e) {
            show_error (_("Non supprimé : %s").printf (clean (e)));
        }
    }

    private void show_error (string text) {
        error.label = text;
        error.visible = true;
    }

    private static string clean (Error e) {
        DBusError.strip_remote_error (e);
        return e.message;
    }
}

/* A label + value line of the editor. */
private class Boomerang.EntryRow : Gtk.ListBoxRow {
    public string[] keys;
    public Gtk.DropDown dropdown;
    public Gtk.Entry entry;

    public EntryRow (string[] keys, Gtk.DropDown dropdown, Gtk.Entry entry) {
        this.keys = keys;
        this.dropdown = dropdown;
        this.entry = entry;
    }
}

/* A postal address of the editor: street, city, region, postcode, country (D-Bus order). */
private class Boomerang.AddressRow : Gtk.ListBoxRow {
    public string[] keys;
    public Gtk.DropDown dropdown;
    public Gtk.Entry[] entries;

    public AddressRow (string[] keys, Gtk.DropDown dropdown, Gtk.Entry[] entries) {
        this.keys = keys;
        this.dropdown = dropdown;
        this.entries = entries;
    }
}

/* Square crop of a chosen photo: drag to move, slider or wheel to zoom. The circle shows
   what the round avatars will show. */
private class Boomerang.PhotoCropDialog : Gtk.Window {
    public signal void chosen (uint8[] jpeg);

    private PhotoCropper cropper;

    public PhotoCropDialog (Gtk.Window parent, Gdk.Pixbuf pixbuf) {
        Object (transient_for: parent, modal: true, title: _("Recadrer la photo"), resizable: false);
        cropper = new PhotoCropper (pixbuf) { halign = Gtk.Align.CENTER };
        var zoom = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 1, 4, 0.01) {
            draw_value = false, hexpand = true
        };
        zoom.update_property (Gtk.AccessibleProperty.LABEL, _("Agrandissement"), -1);
        zoom.value_changed.connect (() => cropper.set_zoom (zoom.get_value ()));
        cropper.zoomed.connect ((value) => zoom.set_value (value));
        var smaller = new Gtk.Image.from_icon_name ("zoom-out-symbolic");
        var larger = new Gtk.Image.from_icon_name ("zoom-in-symbolic");
        var zoom_line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        zoom_line.append (smaller);
        zoom_line.append (zoom);
        zoom_line.append (larger);
        var hint = new Gtk.Label (_("Faites glisser l'image pour choisir la partie gardée.")) { wrap = true };
        hint.add_css_class (Granite.CssClass.DIM);
        hint.add_css_class (Granite.CssClass.SMALL);

        var cancel = new Gtk.Button.with_label (_("Annuler"));
        cancel.clicked.connect (() => close ());
        var use = new Gtk.Button.with_label (_("Utiliser cette photo"));
        use.add_css_class (Granite.CssClass.SUGGESTED);
        use.clicked.connect (() => {
            var jpeg = cropper.crop_jpeg ();
            if (jpeg != null) {
                chosen (jpeg);
            }
            close ();
        });
        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { halign = Gtk.Align.END, margin_top = 6 };
        buttons.append (cancel);
        buttons.append (use);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 9) {
            margin_top = 12, margin_bottom = 18, margin_start = 18, margin_end = 18
        };
        box.append (cropper);
        box.append (zoom_line);
        box.append (hint);
        box.append (buttons);
        var header = new Gtk.HeaderBar ();
        header.add_css_class ("flat");
        titlebar = header;
        child = box;
        default_widget = use;
    }
}

private class Boomerang.PhotoCropper : Gtk.Widget {
    private const int VIEW = 280;
    private const int OUTPUT = 512;

    public signal void zoomed (double zoom);

    private Gdk.Pixbuf source;
    private Gdk.Texture? texture = null;
    private double zoom = 1;
    private double cx;
    private double cy;
    private double drag_x;
    private double drag_y;

    public PhotoCropper (Gdk.Pixbuf source) {
        this.source = source;
        cx = source.width / 2.0;
        cy = source.height / 2.0;
        focusable = true;
        overflow = Gtk.Overflow.HIDDEN;
        update_property (Gtk.AccessibleProperty.LABEL,
                         _("Photo à recadrer : flèches pour déplacer, plus et moins pour agrandir"), -1);
        try {
            uint8[] png;
            source.save_to_bufferv (out png, "png", null, null);
            texture = Gdk.Texture.from_bytes (new Bytes (png));
        } catch (Error e) {
            warning ("photo preview: %s", e.message);
        }

        var drag = new Gtk.GestureDrag ();
        drag.drag_begin.connect (() => {
            drag_x = cx;
            drag_y = cy;
            grab_focus ();
        });
        drag.drag_update.connect ((dx, dy) => {
            cx = drag_x - dx / scale ();
            cy = drag_y - dy / scale ();
            clamp ();
        });
        add_controller (drag);
        var wheel = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
        wheel.scroll.connect ((dx, dy) => {
            set_zoom (zoom * (dy < 0 ? 1.1 : 1 / 1.1));
            zoomed (zoom);
            return true;
        });
        add_controller (wheel);
        var keys = new Gtk.EventControllerKey ();
        keys.key_pressed.connect ((keyval, code, state) => {
            var step = 12 / scale ();
            switch (keyval) {
                case Gdk.Key.Left: cx -= step; break;
                case Gdk.Key.Right: cx += step; break;
                case Gdk.Key.Up: cy -= step; break;
                case Gdk.Key.Down: cy += step; break;
                case Gdk.Key.plus: case Gdk.Key.KP_Add: case Gdk.Key.equal:
                    set_zoom (zoom * 1.1);
                    zoomed (zoom);
                    return true;
                case Gdk.Key.minus: case Gdk.Key.KP_Subtract:
                    set_zoom (zoom / 1.1);
                    zoomed (zoom);
                    return true;
                default: return false;
            }
            clamp ();
            return true;
        });
        add_controller (keys);
    }

    /* Screen pixels per source pixel: at zoom 1 the short side fills the square. */
    private double scale () {
        return VIEW * zoom / double.min (source.width, source.height);
    }

    public void set_zoom (double value) {
        zoom = value.clamp (1, 4);
        clamp ();
    }

    private void clamp () {
        var half = VIEW / (2 * scale ());
        cx = cx.clamp (half, source.width - half);
        cy = cy.clamp (half, source.height - half);
        queue_draw ();
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        minimum = natural = VIEW;
        minimum_baseline = natural_baseline = -1;
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        if (texture != null) {
            var s = scale ();
            var x = VIEW / 2.0 - cx * s;
            var y = VIEW / 2.0 - cy * s;
            snapshot.append_texture (texture, Graphene.Rect () {
                origin = { (float) x, (float) y },
                size = { (float) (source.width * s), (float) (source.height * s) }
            });
        }
        // Outside the circle the avatars will show: dimmed.
        var cr = snapshot.append_cairo (Graphene.Rect () { origin = { 0, 0 }, size = { VIEW, VIEW } });
        cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
        cr.rectangle (0, 0, VIEW, VIEW);
        cr.arc (VIEW / 2.0, VIEW / 2.0, VIEW / 2.0, 0, 2 * Math.PI);
        cr.set_source_rgba (0, 0, 0, 0.45);
        cr.fill ();
        cr.arc (VIEW / 2.0, VIEW / 2.0, VIEW / 2.0 - 0.5, 0, 2 * Math.PI);
        cr.set_source_rgba (1, 1, 1, 0.8);
        cr.set_line_width (1);
        cr.stroke ();
    }

    /* The square shown, at most 512 pixels, as JPEG (transparency on white). */
    public uint8[]? crop_jpeg () {
        var side = (int) Math.round (VIEW / scale ());
        side = int.min (side, int.min (source.width, source.height));
        var x = ((int) Math.round (cx - side / 2.0)).clamp (0, source.width - side);
        var y = ((int) Math.round (cy - side / 2.0)).clamp (0, source.height - side);
        var square = new Gdk.Pixbuf.subpixbuf (source, x, y, side, side);
        var size = int.min (side, OUTPUT);
        Gdk.Pixbuf? result = square.has_alpha
            ? square.composite_color_simple (size, size, Gdk.InterpType.HYPER, 255, 8, 0xffffff, 0xffffff)
            : square.scale_simple (size, size, Gdk.InterpType.HYPER);
        if (result == null) {
            return null;
        }
        try {
            uint8[] jpeg;
            result.save_to_bufferv (out jpeg, "jpeg", { "quality", null }, { "90", null });
            return jpeg;
        } catch (Error e) {
            warning ("photo not encoded: %s", e.message);
            return null;
        }
    }
}
