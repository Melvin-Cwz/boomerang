// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * The person's card, on the right of Personnes (folded with ⓘ or Ctrl+I), as on the iPhone:
 * Modifier at the top (iCloud, ContactEditor), picture and name, round Appeler, Message and
 * Courriel, the contact's numbers, mail and birthday, Ajouter aux favoris; then, folded,
 * the links exchanged and Personnaliser (photo, look and alerts of the conversation).
 */

public class Boomerang.ConversationDetails : Gtk.Box {
    public signal void changed ();

    private Daemon daemon;
    private string thread;
    private string title;
    private string contact_photo;
    private bool group;
    private string number;
    private Granite.Toast toast;
    private ThreadStyleEditor editor;
    private Avatar picture;
    private Gtk.Label name;
    private Gtk.Button remove_photo;
    private Gtk.Box actions;
    private Gtk.ListBox addresses;
    private Gtk.Box links;
    private Gtk.ListBox link_list;
    private Gtk.Button edit_card;
    private Gtk.Label read_only;

    /* pinned: null for a person with no conversation yet (nothing to keep among the favourites). */
    public ConversationDetails (Daemon daemon, string thread, string title, string photo, bool group,
                                string number, Granite.Toast toast, bool? pinned) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
        this.daemon = daemon;
        this.thread = thread;
        this.title = title;
        this.contact_photo = photo;
        this.group = group;
        this.number = number;
        this.toast = toast;
        margin_top = 6;
        margin_bottom = 12;

        editor = new ThreadStyleEditor (thread, ThreadStyle.load_raw (thread), null, daemon);
        editor.changed.connect (() => {
            show_person ();
            changed ();
        });

        // Modifier, discreet, at the top right; shown once the contact card is found.
        edit_card = new Gtk.Button.with_label (_("Modifier")) {
            visible = false, halign = Gtk.Align.END, margin_end = 6
        };
        edit_card.add_css_class ("flat");
        edit_card.update_property (Gtk.AccessibleProperty.LABEL, _("Modifier la fiche"), -1);
        // In its place when the card comes from the iPhone over Bluetooth.
        read_only = new Gtk.Label (_("Fiche de l'iPhone, lecture seule")) {
            visible = false, halign = Gtk.Align.END, margin_end = 12, margin_top = 6,
            tooltip_text = _("Pour la modifier, choisissez « Gestion via iCloud » dans Réglages avancés › Répertoire")
        };
        read_only.add_css_class (Granite.CssClass.DIM);
        read_only.add_css_class (Granite.CssClass.SMALL);
        append (edit_card);
        append (read_only);

        picture = new Avatar (88) { halign = Gtk.Align.CENTER };
        name = new Gtk.Label ("") {
            wrap = true,
            justify = Gtk.Justification.CENTER,
            margin_start = 12,
            margin_end = 12
        };
        name.add_css_class (Granite.HeaderLabel.Size.H2.to_string ());
        var change_photo = new Gtk.Button.with_label (_("Modifier la photo"));
        change_photo.clicked.connect (() => editor.choose_photo ());
        remove_photo = new Gtk.Button.with_label (_("Retirer"));
        remove_photo.clicked.connect (() => editor.remove_photo ());
        var photo_buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { halign = Gtk.Align.CENTER };
        foreach (var b in new Gtk.Button[] { change_photo, remove_photo }) {
            b.add_css_class ("flat");
            b.add_css_class (Granite.CssClass.SMALL);
            photo_buttons.append (b);
        }
        append (picture);
        append (name);

        // Round buttons under the name; Courriel joins them once the card gives a mail.
        actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { halign = Gtk.Align.CENTER };
        if (!group && number != "") {
            var call = new CallButton (daemon, number, toast) { child = action_child ("call-start-symbolic", _("Appeler")) };
            call.remove_css_class ("flat");
            call.add_css_class ("details-action");
            call.update_property (Gtk.AccessibleProperty.LABEL, _("Appeler %s").printf (title), -1);
            var write = new Gtk.Button () { child = action_child ("mail-message-new-symbolic", _("Message")) };
            write.add_css_class ("details-action");
            write.update_property (Gtk.AccessibleProperty.LABEL, _("Écrire à %s").printf (title), -1);
            write.clicked.connect (() => activate_action_variant ("app.write-to", new Variant.string (number)));
            actions.append (call);
            actions.append (write);
        }
        append (actions);

        addresses = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            show_separators = true,
            margin_start = 12,
            margin_end = 12,
            visible = false
        };
        addresses.add_css_class (Granite.CssClass.CARD);
        append (addresses);
        if (group) {
            var hint = new Gtk.Label (_("Conversation de groupe")) { halign = Gtk.Align.CENTER };
            hint.add_css_class (Granite.CssClass.DIM);
            append (hint);
        } else if (number != "") {
            add_address (number);  // until the contact is found
            load_contact.begin ();
        }

        // Favourites are the people pinned at the top of Personnes; the card is edited in iCloud.
        var card_buttons = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) { margin_start = 12, margin_end = 12 };
        if (pinned != null) {
            bool on = pinned;
            var favorite = new Gtk.Button.with_label (on ? _("Retirer des favoris") : _("Ajouter aux favoris"));
            favorite.clicked.connect (() => {
                on = !on;
                favorite.label = on ? _("Retirer des favoris") : _("Ajouter aux favoris");
                daemon.call.begin ("PinThread", new Variant ("(sb)", thread, on));
            });
            card_buttons.append (favorite);
        }
        append (card_buttons);

        // Links exchanged in the conversation, newest first (from the messages Boomerang keeps).
        // Rarely needed: folded under two lines, closed.
        links = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) { visible = false };
        link_list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE, show_separators = true, margin_top = 6
        };
        link_list.add_css_class (Granite.CssClass.CARD);
        link_list.row_activated.connect (open_link);
        links.append (new Gtk.Expander (_("Liens partagés")) { child = link_list });
        load_links.begin ();

        var personalise = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) { margin_top = 6 };
        personalise.append (photo_buttons);
        personalise.append (editor);
        var expanders = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) { margin_start = 12, margin_end = 12 };
        expanders.append (links);
        expanders.append (new Gtk.Expander (_("Personnaliser")) { child = personalise });
        append (expanders);
        show_person ();
    }

    private const int LINKS_SHOWN = 20;

    private async void load_links () {
        bool ok;
        var items = yield daemon.try_list ("ListLinks", new Variant ("(s)", thread), out ok);
        if (!ok) {
            return;  // an older daemon: no section
        }
        int count = 0;
        foreach (var item in items) {
            if (count++ >= LINKS_SHOWN) {
                break;
            }
            var url = Props.str (item, "url");
            var time = item.lookup_value ("time", VariantType.INT64);
            link_list.append (link_row (url, time != null ? time.get_int64 () : 0,
                                        Props.flag (item, "outgoing")));
        }
        links.visible = count > 0;
    }

    private Gtk.ListBoxRow link_row (string url, int64 time, bool outgoing) {
        var uri = url;
        try {
            uri = Uri.parse (url, UriFlags.NONE).get_host () ?? url;
        } catch (Error e) {
            // shown as written
        }
        if (uri.has_prefix ("www.")) {
            uri = uri.substring (4);
        }
        var site = new Gtk.Label (uri) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        var address = new Gtk.Label (url) { xalign = 0, ellipsize = Pango.EllipsizeMode.MIDDLE };
        address.add_css_class (Granite.CssClass.DIM);
        address.add_css_class (Granite.CssClass.SMALL);
        var day = time > 0 ? short_time (time) : "";
        if (day == _("Hier")) {
            day = day.down ();
        }
        var when = new Gtk.Label (day != "" ? (outgoing ? _("Envoyé : %s") : _("Reçu : %s")).printf (day) : "") {
            xalign = 0
        };
        when.add_css_class (Granite.CssClass.DIM);
        when.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        text.append (site);
        text.append (address);
        text.append (when);
        var icon = new Gtk.Image.from_icon_name ("web-browser-symbolic") { valign = Gtk.Align.CENTER };
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 9) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 12,
            margin_end = 12
        };
        box.append (icon);
        box.append (text);
        var row = new Gtk.ListBoxRow () { child = box, tooltip_text = url };
        row.set_data<string> ("url", url);
        row.update_property (Gtk.AccessibleProperty.LABEL, url, -1);
        return row;
    }

    private void open_link (Gtk.ListBoxRow row) {
        var url = row.get_data<string> ("url");
        if (url != null) {
            new Gtk.UriLauncher (url).launch.begin (get_root () as Gtk.Window, null);
        }
    }

    private void show_person () {
        var style = ThreadStyle.load (thread);
        picture.show_person (title, style.picture (contact_photo), group);
        name.label = style.shown_name (title);
        remove_photo.visible = editor.has_photo ();
    }

    private static Gtk.Widget action_child (string icon, string label) {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
        box.append (new Gtk.Image.from_icon_name (icon));
        var text = new Gtk.Label (label);
        text.add_css_class (Granite.CssClass.SMALL);
        box.append (text);
        return box;
    }

    /* The contact card behind the number: all its addresses, and mail when it has one. */
    private async void load_contact () {
        bool ok;
        var items = yield daemon.try_list ("ListContacts", null, out ok);
        if (!ok) {
            return;
        }
        var digits = only_digits (number);
        var tail = digits.length > 9 ? digits.substring (digits.length - 9) : digits;
        foreach (var item in items) {
            var contact = Contact.from_variant (item);
            foreach (var a in contact.addresses) {
                if (contact.is_phone (a) && tail.length >= 6 && only_digits (a).has_suffix (tail)) {
                    show_contact (contact);
                    return;
                }
            }
        }
    }

    private void show_contact (Contact contact) {
        clear_addresses ();
        if (contact_photo == "" && contact.photo != "") {
            contact_photo = contact.photo;
            show_person ();
        }
        string? mail = null;
        foreach (var a in contact.addresses) {
            add_address (a, contact.is_phone (a));
            if (mail == null && !contact.is_phone (a)) {
                mail = a;
            }
        }
        // Read only from the iPhone; editable once contacts are managed through iCloud (Répertoire).
        var editable = daemon.get_string ("ContactsSource") == "icloud" && daemon.get_string ("ContactsBook") == "ready";
        edit_card.visible = editable && contact.uid != "";
        read_only.visible = !edit_card.visible;
        edit_card.clicked.connect (() => {
            var parent = get_root () as Gtk.Window;
            var editor = new ContactEditor (parent, daemon, contact.uid);
            if (parent != null) {
                editor.application = parent.application;
            }
            editor.present ();
        });
        if (contact.key != "") {
            load_details.begin (contact.key);
        }
        if (mail != null) {
            var write = new Gtk.Button () { child = action_child ("mail-send-symbolic", _("Courriel")) };
            write.add_css_class ("details-action");
            write.tooltip_text = mail;
            write.clicked.connect (() => {
                new Gtk.UriLauncher ("mailto:" + mail).launch.begin (get_root () as Gtk.Window, null);
            });
            actions.append (write);
        }
    }

    private void clear_addresses () {
        Gtk.Widget? row;
        while ((row = addresses.get_first_child ()) != null) {
            addresses.remove (row);
        }
    }

    /* The whole card: each number and mail with its label, and the birthday. */
    private async void load_details (string key) {
        var reply = yield daemon.call_dict ("GetContactDetails", new Variant ("(s)", key));
        if (reply == null) {
            return;  // what the contact list knows stays
        }
        var d = new VariantDict (reply);
        var phones = pairs (d, "phones");
        var mails = pairs (d, "emails");
        if (phones.length + mails.length == 0) {
            return;
        }
        clear_addresses ();
        for (int i = 0; i < phones.length; i += 2) {
            add_address (phones[i + 1], true, phone_label (phones[i]));
        }
        for (int i = 0; i < mails.length; i += 2) {
            add_address (mails[i + 1], false, mail_label (mails[i]));
        }
        var birthday = dict_string (d, "birthday");
        if (birthday != "") {
            add_address (format_date (birthday), false, _("anniversaire"));
        }
    }

    private void add_address (string address, bool phone = true, string? label = null) {
        var kind = new Gtk.Label (label ?? (phone ? _("téléphone") : _("courriel"))) { xalign = 0 };
        kind.add_css_class (Granite.CssClass.DIM);
        kind.add_css_class (Granite.CssClass.SMALL);
        var value = new Gtk.Label (format_address (address)) {
            xalign = 0,
            selectable = true,
            ellipsize = Pango.EllipsizeMode.END
        };
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        text.append (kind);
        text.append (value);
        var copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
            tooltip_text = _("Copier"),
            valign = Gtk.Align.CENTER
        };
        copy.add_css_class ("flat");
        copy.clicked.connect (() => {
            get_clipboard ().set_text (address);
            toast.title = _("Copié");
            toast.send_notification ();
        });
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 12,
            margin_end = 6
        };
        box.append (text);
        box.append (copy);
        addresses.append (new Gtk.ListBoxRow () { child = box, activatable = false });
        addresses.visible = true;
    }
}
