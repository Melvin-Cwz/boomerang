// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Calls: the iPhone's call history read over PBAP (read only), newest first,
 * with missed calls in red, and buttons to call back (HFP, on click only) or
 * to write a message.
 */

namespace Boomerang {
    public const string CALLS_UNAVAILABLE =
        N_("Les appels demandent PipeWire 1.4 ou plus récent.");

    /* PipeWire before 1.4 has no hands-free telephony API. */
    public bool calls_unavailable (Daemon daemon) {
        return daemon.running && !daemon.get_bool ("CallsSupported");
    }

    /* Length of a finished call: "48 s", "3 min 12 s", "1 h 02 min". */
    public string call_length (int seconds) {
        if (seconds < 60) {
            return _("%d s").printf (seconds);
        }
        if (seconds < 3600) {
            return _("%d min %02d s").printf (seconds / 60, seconds % 60);
        }
        return _("%d h %02d min").printf (seconds / 3600, (seconds / 60) % 60);
    }

    /* Same in a narrow list: "48 s", "12 min", "1 h 02". */
    public string call_length_short (int seconds) {
        if (seconds < 60) {
            return _("%d s").printf (seconds);
        }
        if (seconds < 3600) {
            return _("%d min").printf (seconds / 60);
        }
        return _("%d h %02d").printf (seconds / 3600, (seconds / 60) % 60);
    }

    /* The same number written two ways (+33 6…, 06…) has the same last nine digits; "" if too short.
       shortcut: nine digits suit French and most national numbers, compare whole E.164 numbers
       once the daemon gives them normalised everywhere. */
    public string number_tail (string address) {
        var digits = only_digits (address);
        return digits.length < 6 ? "" : digits.length > 9 ? digits.substring (digits.length - 9) : digits;
    }

    /* "14:02" today, "hier 18:40", "lundi 18:40", else the date and the hour. */
    public string event_time (int64 stamp) {
        var day = short_time (stamp);
        if (day.contains (":")) {
            return day;
        }
        return "%s %s".printf (day == _("Hier") ? day.down () : day,
                               new DateTime.from_unix_local (stamp).format ("%H:%M"));
    }

    /* A call in Personnes: "Appel manqué · 14:02", "Appel sortant · 1 min" in the list,
       "Appel sortant · 12 min · hier 18:40" in the thread (with_time). */
    public string call_summary (string kind, int seconds, int64 stamp, bool with_time) {
        string[] parts = { kind == "missed" ? _("Appel manqué") : kind == "dialed" ? _("Appel sortant")
                                                                                   : _("Appel reçu") };
        if (seconds >= 0 && kind != "missed") {
            parts += call_length_short (seconds);
        }
        if (with_time || parts.length == 1) {
            parts += event_time (stamp);
        }
        return string.joinv (" · ", parts);
    }

    /* Search in Téléphone: a name (accents and case ignored) or digits of a number
       ("06 12", "+33 6 12" and "612" all find +33612…). */
    public bool call_matches (string query, string name, string address) {
        var q = query.strip ();
        if (q == "") {
            return true;
        }
        if (search_fold (name).contains (search_fold (q))) {
            return true;
        }
        var digits = only_digits (q);
        if (digits.length < 2) {
            return false;
        }
        if (digits.has_prefix ("0") && digits.length > 1) {
            digits = digits.substring (1);  // national form: 06… is +336…
        }
        return only_digits (address).contains (digits);
    }
}

public class Boomerang.CallsView : Gtk.Box {
    public Daemon daemon { get; construct; }
    public bool with_dialer { get; construct; }
    public signal void message_requested (string address);
    public signal void number_chosen (string address);  // a row clicked: its number on the keypad

    private Gtk.ListBox list;
    private Gtk.Stack stack;
    private Granite.Toast toast;
    private Gtk.Label unavailable;
    private Gtk.MenuButton compose;
    private Variant[] items = {};
    private Gtk.Stack empty_kind;

    /* Only the missed calls (Téléphone › Récents › Manqués). */
    public bool missed_only { get; set; default = false; }

    /* Search text (Téléphone): names and numbers. */
    public string query { get; set; default = ""; }
    private Granite.Placeholder no_match;

    /* A list column (Téléphone, between the sidebar and the keypad), like Messages and Contacts. */
    public bool column { get; construct; }

    public CallsView (Daemon daemon, bool with_dialer = true, bool column = false) {
        Object (daemon: daemon, with_dialer: with_dialer, column: column,
                orientation: Gtk.Orientation.VERTICAL, spacing: 0);
    }

    construct {
        list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            show_separators = true,
            valign = Gtk.Align.START
        };
        list.row_activated.connect ((row) => number_chosen (row.get_data<string> ("address")));
        if (!column) {
            list.width_request = 440;
            list.halign = Gtk.Align.CENTER;
            list.margin_top = list.margin_bottom = 18;
            list.add_css_class (Granite.CssClass.CARD);
        }
        var scroll = new Gtk.ScrolledWindow () {
            child = list,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        };
        var empty = new Granite.Placeholder (_("Aucun appel")) {
            description = _("Le journal d'appels vient de l'iPhone. Activez « Synchroniser les "
                          + "contacts » pour ce PC dans les réglages Bluetooth de l'iPhone."),
            icon = new ThemedIcon (Config.APP_ID + ".Phone")
        };
        var no_missed = new Granite.Placeholder (_("Aucun appel manqué")) {
            icon = new ThemedIcon (Config.APP_ID + ".Phone")
        };
        no_match = new Granite.Placeholder (_("Aucun résultat")) {
            icon = new ThemedIcon ("edit-find-symbolic")
        };
        empty_kind = new Gtk.Stack ();
        empty_kind.add_named (empty, "all");
        empty_kind.add_named (no_missed, "missed");
        empty_kind.add_named (no_match, "search");
        stack = new Gtk.Stack ();
        stack.add_named (scroll, "list");
        stack.add_named (empty_kind, "empty");
        notify["missed-only"].connect (fill);
        notify["query"].connect (fill);
        unavailable = new Gtk.Label (_(CALLS_UNAVAILABLE)) {
            wrap = true,
            justify = Gtk.Justification.CENTER,
            margin_top = 12,
            margin_start = 12,
            margin_end = 12,
            visible = false
        };
        unavailable.add_css_class (Granite.CssClass.DIM);
        append (unavailable);
        compose = new Gtk.MenuButton () {
            popover = new DialPopover (daemon),
            halign = Gtk.Align.CENTER,
            margin_top = 12
        };
        var compose_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        compose_box.append (new Gtk.Image.from_icon_name ("input-dialpad-symbolic"));
        compose_box.append (new Gtk.Label (_("Composer un numéro")));
        compose.child = compose_box;
        if (with_dialer) {
            append (compose);
        }

        toast = new Granite.Toast ("");
        var overlay = new Gtk.Overlay () { child = stack, vexpand = true };
        overlay.add_overlay (toast);
        append (overlay);

        daemon.calls_changed.connect (() => {
            if (get_mapped ()) {  // hidden: map reloads it
                reload.begin ();
            }
        });
        daemon.changed.connect (() => {
            if (daemon.touched ({ "CallsSupported" })) {
                update_buttons ();
            }
        });
        map.connect (() => reload.begin ());
    }

    private async void reload () {
        bool ok;
        var loaded = yield daemon.try_list ("ListCalls", null, out ok);
        if (!ok) {
            return;  // failed call: keep the history shown
        }
        items = loaded;
        fill ();
    }

    private void fill () {
        Gtk.Widget? child;
        while ((child = list.get_first_child ()) != null) {
            list.remove (child);
        }
        int shown = 0;
        foreach (var item in items) {
            var d = new VariantDict (item);
            if (missed_only && dict_string (d, "kind") != "missed") {
                continue;
            }
            if (!call_matches (query, dict_string (d, "name"), dict_string (d, "address"))) {
                continue;
            }
            list.append (row (d));
            shown++;
        }
        if (query.strip () != "") {
            no_match.description = _("Aucun appel ne correspond à « %s ».").printf (query.strip ());
            empty_kind.visible_child_name = "search";
        } else {
            empty_kind.visible_child_name = missed_only ? "missed" : "all";
        }
        stack.visible_child_name = shown > 0 ? "list" : "empty";
        update_buttons ();
    }

    private Gtk.Widget row (VariantDict d) {
        var address = dict_string (d, "address");
        var name = dict_string (d, "name");
        var kind = dict_string (d, "kind");

        var avatar = new Avatar (36);
        avatar.show_person (name, dict_string (d, "avatar"));
        var name_label = new Gtk.Label (name) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        if (kind == "missed") {
            name_label.add_css_class (Granite.CssClass.ERROR);
        }
        string kind_text = kind == "missed" ? _("Manqué") : kind == "dialed" ? _("Sortant") : _("Entrant");
        var icon = new Gtk.Image.from_icon_name (
            kind == "missed" ? "call-missed-symbolic"
            : kind == "dialed" ? "call-outgoing-symbolic" : "call-incoming-symbolic");
        icon.add_css_class (Granite.CssClass.DIM);
        icon.tooltip_text = kind_text;
        var stamp = dict_int64 (d, "time");
        var when = column ? short_time (stamp) : long_time (stamp);
        // Length measured on this PC when it followed the call; the iPhone's history has none.
        var length = d.lookup_value ("duration", VariantType.INT32);
        var seconds = length != null && kind != "missed" ? length.get_int32 () : -1;
        // The narrow column drops the word the icon already says, and the seconds.
        var detail_text = column ? when : "%s · %s".printf (kind_text, when);
        if (seconds >= 0) {
            detail_text += " · " + (column ? call_length_short (seconds) : call_length (seconds));
        }
        var detail = new Gtk.Label (detail_text) {
            xalign = 0,
            ellipsize = Pango.EllipsizeMode.END
        };
        var spoken = "%s, %s, %s".printf (name, kind_text, long_time (stamp));
        if (seconds >= 0) {
            spoken += ", " + call_length (seconds);
        }
        detail.add_css_class (Granite.CssClass.DIM);
        detail.add_css_class (Granite.CssClass.SMALL);
        var detail_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        detail_box.append (icon);
        detail_box.append (detail);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (name_label);
        text.append (detail_box);

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 12,
            margin_end = 8
        };
        box.append (avatar);
        box.append (text);
        var row = new Gtk.ListBoxRow () { child = box, activatable = address != "" };
        if (address != "") {
            var dial = new CallButton (daemon, address, toast);
            dial.update_property (Gtk.AccessibleProperty.LABEL, _("Appeler %s").printf (name), -1);
            box.append (dial);
            row.set_data<string> ("address", address);
            message_menu (row, () => message_requested (address));
        }
        row.update_property (Gtk.AccessibleProperty.LABEL, spoken, -1);
        return row;
    }

    private void update_buttons () {
        // CallButton widgets follow CallsLinked themselves.
        var off = calls_unavailable (daemon);
        unavailable.visible = off;
        compose.sensitive = !off;
    }
}

/*
 * Favoris (Téléphone): the iPhone's favourite contacts, read with the contacts when
 * the experimental « Favoris de l'iPhone » is on (PBAP « fav » folder, read only: they
 * are changed on the iPhone). Call or write in one click.
 */
public class Boomerang.FavoritesView : Gtk.Box {
    public Daemon daemon { get; construct; }
    public signal void message_requested (string address);
    public signal void number_chosen (string address);  // a row clicked: its number on the keypad
    public string query { get; set; default = ""; }

    private Gtk.ListBox list;
    private Gtk.Stack stack;
    private Granite.Placeholder empty;
    private Granite.Toast toast;
    private Variant[] cards = {};

    public FavoritesView (Daemon daemon) {
        Object (daemon: daemon, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
    }

    construct {
        list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            show_separators = true,
            valign = Gtk.Align.START
        };
        list.row_activated.connect ((row) => number_chosen (row.get_data<string> ("address")));
        var scroll = new Gtk.ScrolledWindow () {
            child = list,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        };
        empty = new Granite.Placeholder (_("Aucun favori")) {
            icon = new ThemedIcon ("starred-symbolic")
        };
        stack = new Gtk.Stack ();
        stack.add_named (scroll, "list");
        stack.add_named (empty, "empty");
        toast = new Granite.Toast ("");
        var overlay = new Gtk.Overlay () { child = stack, vexpand = true };
        overlay.add_overlay (toast);
        append (overlay);

        notify["query"].connect (fill);
        daemon.contacts_changed.connect (() => {
            if (get_mapped ()) {
                reload.begin ();
            }
        });
        daemon.changed.connect (() => {
            if (daemon.touched ({ "AlphaFeatures" }) && get_mapped ()) {
                reload.begin ();
            }
        });
        map.connect (() => reload.begin ());
    }

    private async void reload () {
        bool ok;
        var loaded = yield daemon.try_list ("ListContacts", null, out ok);
        if (!ok) {
            return;
        }
        Variant[] kept = {};
        foreach (var item in loaded) {
            if (dict_bool (new VariantDict (item), "favorite")) {
                kept += item;
            }
        }
        cards = kept;
        fill ();
    }

    /* First phone number of a card (its addresses may hold e-mail addresses too). */
    private static string phone_of (VariantDict d) {
        var addresses = d.lookup_value ("addresses", VariantType.STRING_ARRAY);
        if (addresses != null) {
            foreach (var address in addresses.get_strv ()) {
                if (!address.contains ("@") && only_digits (address).length >= 2) {
                    return address;
                }
            }
        }
        return "";
    }

    private void fill () {
        Gtk.Widget? child;
        while ((child = list.get_first_child ()) != null) {
            list.remove (child);
        }
        int shown = 0;
        foreach (var item in cards) {
            var d = new VariantDict (item);
            var number = phone_of (d);
            if (number == "" || !call_matches (query, dict_string (d, "name"), number)) {
                continue;
            }
            list.append (row (d, number));
            shown++;
        }
        if (query.strip () != "") {
            empty.title = _("Aucun résultat");
            empty.description = _("Aucun favori ne correspond à « %s ».").printf (query.strip ());
        } else if (!daemon.alpha_enabled ("pbap_favorites")) {
            empty.title = _("Favoris non lus");
            empty.description = _("La lecture des favoris de l'iPhone est expérimentale : activez "
                                  + "« Favoris de l'iPhone » dans Réglages › Avancés › Expérimental. "
                                  + "Ils apparaissent à la synchronisation suivante.");
        } else {
            empty.title = _("Aucun favori");
            empty.description = _("Les favoris viennent de l'app Téléphone de l'iPhone et se modifient "
                                  + "sur l'iPhone. L'iPhone ne les communique pas toujours.");
        }
        stack.visible_child_name = shown > 0 ? "list" : "empty";
    }

    private Gtk.Widget row (VariantDict d, string number) {
        var name = dict_string (d, "name");
        var avatar = new Avatar (36);
        avatar.show_person (name, dict_string (d, "photo"));
        var name_label = new Gtk.Label (name) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        var number_label = new Gtk.Label (format_address (number)) {
            xalign = 0,
            ellipsize = Pango.EllipsizeMode.END
        };
        number_label.add_css_class (Granite.CssClass.DIM);
        number_label.add_css_class (Granite.CssClass.SMALL);
        number_label.add_css_class ("numeric");
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (name_label);
        text.append (number_label);
        var dial = new CallButton (daemon, number, toast);
        dial.update_property (Gtk.AccessibleProperty.LABEL, _("Appeler %s").printf (name), -1);
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 12,
            margin_end = 8
        };
        box.append (avatar);
        box.append (text);
        box.append (dial);
        var row = new Gtk.ListBoxRow () { child = box };
        row.set_data<string> ("address", number);
        message_menu (row, () => message_requested (number));
        return row;
    }
}

/* Calls a number from the iPhone through the hands-free link, only when clicked. */
public class Boomerang.CallButton : Gtk.Button {
    public delegate string NumberSource ();

    public Daemon daemon { get; construct; }
    public string number { get; construct; }
    public Granite.Toast? toast { get; construct; }
    public NumberSource? number_source = null;
    public signal void dialled ();

    public CallButton (Daemon daemon, string number, Granite.Toast? toast) {
        Object (daemon: daemon, number: number, toast: toast, icon_name: "call-start-symbolic",
                valign: Gtk.Align.CENTER);
    }

    construct {
        add_css_class ("flat");
        clicked.connect (() => {
            var target = number_source != null ? number_source () : number;
            if (only_digits (target).length < 2) {
                return;
            }
            sensitive = false;
            daemon.call_send.begin ("Dial", new Variant ("(s)", target), (obj, res) => {
                var ok = daemon.call_send.end (res);
                if (ok) {
                    dialled ();
                } else if (toast != null) {
                    toast.title = _("Appel impossible : le profil mains libres de l'iPhone n'est pas connecté");
                    toast.send_notification ();
                }
                update ();
            });
        });
        daemon.changed.connect (on_daemon_changed);  // a method: no reference kept on the row
        update ();
    }

    private void on_daemon_changed () {
        if (daemon.touched ({ "CallsLinked", "CallsSupported" })) {
            update ();
        }
    }

    private void update () {
        var ready = daemon.get_bool ("CallsLinked");
        sensitive = ready;
        tooltip_text = ready ? _("Appeler depuis l'iPhone")
                     : calls_unavailable (daemon) ? _(CALLS_UNAVAILABLE)
                     : _("Appel indisponible : le profil mains libres de l'iPhone n'est pas connecté");
    }
}

namespace Boomerang {
    public delegate void RowWrite ();

    /* Right click, Shift+F10 or the Menu key on a call: Envoyer un message, out of the way. */
    public void message_menu (Gtk.Widget row, owned RowWrite write) {
        var actions = new SimpleActionGroup ();
        var action = new SimpleAction ("write", null);
        action.activate.connect (() => write ());
        actions.add_action (action);
        row.insert_action_group ("call", actions);
        var click = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
        click.pressed.connect ((n, x, y) => show_message_menu (row, { (int) x, (int) y, 1, 1 }));
        row.add_controller (click);
        var keys = new Gtk.ShortcutController ();
        keys.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("<Shift>F10|Menu"),
                                             new Gtk.CallbackAction (() => {
            show_message_menu (row, null);
            return true;
        })));
        row.add_controller (keys);
    }

    private void show_message_menu (Gtk.Widget row, Gdk.Rectangle? at) {
        var menu = new GLib.Menu ();
        menu.append (_("Envoyer un message"), "call.write");
        var popover = new Gtk.PopoverMenu.from_model (menu) { has_arrow = false };
        if (at != null) {
            popover.pointing_to = at;
        }
        popover.set_parent (row);
        // Made at each opening and dropped at closing: a removed row keeps no popover child.
        popover.closed.connect (() => Idle.add (() => {
            popover.unparent ();
            return Source.REMOVE;
        }));
        popover.popup ();
    }
}
