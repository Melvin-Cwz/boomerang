// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Le Fil: the Centre iPhone's home page. What came back from the iPhone today, in order:
 * calls, received messages, notifications; Rappeler, Répondre and Message open the person in
 * Personnes. Only what boomerangd already lists (ListCalls, ListThreads, ListNotifications);
 * nothing is kept here.
 */

public class Boomerang.FeedView : Gtk.Box {
    private Daemon daemon;
    private Gtk.Button share_button;
    private Gtk.ListBox list;
    private Gtk.Stack list_stack;
    private bool loading = false;

    private const string CSS = """
        .feed-dot.call { color: @LIME_700; }
        .feed-dot.missed { color: @STRAWBERRY_500; }
        .feed-dot.message { color: @BLUEBERRY_500; }
        .feed-dot.notification { opacity: 0.6; }
    """;
    private static bool css_added = false;

    private class Item {
        public int64 time;
        public string source;  // CSS class of the dot
        public string title;
        public string subtitle;
        public Gtk.Widget[] actions = {};
    }

    public FeedView (Daemon daemon) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.daemon = daemon;
        vexpand = true;
        if (!css_added) {
            css_added = true;
            var provider = new Gtk.CssProvider ();
            provider.load_from_string (Style.colors (CSS));
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        var content = new PageColumn ();
        var heading = new Granite.HeaderLabel (_("Aujourd'hui")) {
            secondary_text = _("Tout ce qui est revenu de l'iPhone, dans l'ordre"),
            hexpand = true,
            size = Granite.HeaderLabel.Size.H1
        };
        var heading_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        heading_row.append (heading);
        build_quick_actions (heading_row);
        content.append (heading_row);
        list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        list.add_css_class (Granite.CssClass.CARD);
        var empty = new Granite.Placeholder (_("Rien pour le moment")) {
            description = _("Les appels, les messages et les notifications de l'iPhone arrivent ici au fil de la journée."),
            icon = new ThemedIcon ("mail-inbox")
        };
        list_stack = new Gtk.Stack ();
        list_stack.add_named (list, "list");
        list_stack.add_named (empty, "empty");
        content.append (list_stack);
        append (new Gtk.ScrolledWindow () {
            child = content,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        });

        daemon.calls_changed.connect (queue_reload);
        daemon.threads_changed.connect (queue_reload);
        daemon.notifications_changed.connect (queue_reload);
        daemon.changed.connect (() => {
            if (daemon.touched ({ "TetheringState" })) {
                refresh_status ();
            }
        });
        map.connect (() => {
            refresh_status ();
            queue_reload ();
        });
        refresh_status ();
    }

    private void build_quick_actions (Gtk.Box row) {
        share_button = new Gtk.Button.with_label (_("Partager la connexion")) { valign = Gtk.Align.END };
        share_button.clicked.connect (() => {
            share_button.sensitive = false;
            daemon.call.begin ("SetTethering", new Variant ("(b)", daemon.get_string ("TetheringState") != "on"),
                               (obj, res) => {
                daemon.call.end (res);
                refresh_status ();
            });
        });
        var mirror_button = new Gtk.Button.with_label (_("Recopier l'écran")) { valign = Gtk.Align.END };
        mirror_button.clicked.connect (() => launch (Mode.MIRROR));
        row.append (share_button);
        row.append (mirror_button);
    }

    private void refresh_status () {
        var tethering = daemon.get_string ("TetheringState");
        share_button.label = tethering == "on" ? _("Arrêter le partage") : _("Partager la connexion");
        share_button.sensitive = tethering != "unavailable" && tethering != "connecting";
    }

    private void queue_reload () {
        if (get_mapped ()) {  // hidden: map reloads it
            reload.begin ();
        }
    }

    private async void reload () {
        if (loading) {
            return;
        }
        loading = true;
        var now = new DateTime.now_local ();
        var midnight = new DateTime.local (now.get_year (), now.get_month (), now.get_day_of_month (), 0, 0, 0)
                           .to_unix ();
        var calls = yield daemon.call_list ("ListCalls");
        var threads = yield daemon.call_list ("ListThreads");
        var notes = yield daemon.call_list ("ListNotifications");

        var items = new GenericArray<Item> ();
        foreach (var variant in calls) {
            var d = new VariantDict (variant);
            if (dict_int64 (d, "time") >= midnight) {
                items.add (call_item (d));
            }
        }
        foreach (var variant in threads) {
            var d = new VariantDict (variant);
            if (dict_int64 (d, "time") >= midnight && !dict_bool (d, "outgoing")) {
                items.add (thread_item (d));
            }
        }
        foreach (var variant in notes) {
            var d = new VariantDict (variant);
            if (dict_int64 (d, "time") >= midnight) {
                items.add (note_item (d));
            }
        }
        items.sort ((a, b) => a.time > b.time ? -1 : a.time < b.time ? 1 : 0);

        Gtk.Widget? old;
        while ((old = list.get_first_child ()) != null) {
            list.remove (old);
        }
        for (int i = 0; i < items.length; i++) {
            list.append (item_row (items[i]));
        }
        list_stack.visible_child_name = items.length > 0 ? "list" : "empty";
        loading = false;
    }

    private Item call_item (VariantDict d) {
        var address = dict_string (d, "address");
        var name = dict_string (d, "name") != "" ? dict_string (d, "name") : address;
        var kind = dict_string (d, "kind");
        var item = new Item () { time = dict_int64 (d, "time"), source = kind == "missed" ? "missed" : "call" };
        item.title = (kind == "missed" ? _("Appel manqué · %s") : kind == "dialed" ? _("Appel sortant · %s")
                                       : _("Appel reçu · %s")).printf (name);
        item.subtitle = _("Téléphone");
        if (address != "") {
            item.actions += action_button (_("Rappeler"), _("Rappeler %s").printf (name), () => {
                daemon.call.begin ("Dial", new Variant ("(s)", address));
                GLib.Application.get_default ().activate_action ("write-to", new Variant.string (address));
            });
            item.actions += action_button (_("Message"), _("Écrire à %s").printf (name), () => {
                GLib.Application.get_default ().activate_action ("write-to", new Variant.string (address));
            });
        }
        return item;
    }

    private Item thread_item (VariantDict d) {
        var thread = dict_string (d, "id");
        var name = dict_string (d, "name");
        var item = new Item () { time = dict_int64 (d, "time"), source = "message", title = name };
        item.subtitle = dict_string (d, "snippet");
        item.actions += action_button (_("Répondre"), _("Répondre à %s").printf (name), () => {
            GLib.Application.get_default ().activate_action ("open-thread", new Variant ("(sb)", thread, false));
        });
        return item;
    }

    private Item note_item (VariantDict d) {
        var item = new Item () { time = dict_int64 (d, "time"), source = "notification" };
        var app = dict_string (d, "app_name");
        var title = dict_string (d, "title");
        item.title = app != "" && title != "" ? "%s · %s".printf (app, title) : app + title;
        item.subtitle = dict_string (d, "body") != "" ? dict_string (d, "body") : _("Notification de l'iPhone");
        // The iPhone's own « negative » action, when the daemon has it (experimental ANCS actions).
        var uid = d.lookup_value ("uid", VariantType.UINT32);
        if (uid != null && dict_string (d, "negative") != "" && daemon.alpha_enabled ("ancs_actions")) {
            var id = uid.get_uint32 ();
            item.actions += action_button (_("Effacer sur l'iPhone"), _("Effacer cette notification sur l'iPhone"),
                                           () => daemon.call.begin ("NotificationAction", new Variant ("(us)", id, "negative")));
        }
        return item;
    }

    private delegate void Act ();

    private static Gtk.Widget action_button (string label, string spoken, owned Act act) {
        var button = new Gtk.Button.with_label (label) { valign = Gtk.Align.CENTER };
        button.update_property (Gtk.AccessibleProperty.LABEL, spoken, -1);
        button.clicked.connect (() => {
            act ();
            if (label == _("Effacer sur l'iPhone")) {
                button.sensitive = false;
            }
        });
        return button;
    }

    private static Gtk.Widget item_row (Item item) {
        var time = new Gtk.Label (short_time (item.time)) { width_chars = 5, xalign = 0 };
        time.add_css_class (Granite.CssClass.DIM);
        string[] icons = { "call", "call-start-symbolic", "missed", "call-start-symbolic",
                           "message", "internet-chat-symbolic", "notification", "notification-symbolic" };
        string icon = "notification-symbolic";
        for (int i = 0; i < icons.length; i += 2) {
            if (icons[i] == item.source) {
                icon = icons[i + 1];
            }
        }
        var dot = new Gtk.Image.from_icon_name (icon) { valign = Gtk.Align.CENTER };
        dot.add_css_class ("feed-dot");
        dot.add_css_class (item.source);
        var title = new Gtk.Label (item.title) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        var subtitle = new Gtk.Label (item.subtitle) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        subtitle.add_css_class (Granite.CssClass.DIM);
        subtitle.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title);
        text.append (subtitle);
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 6, margin_bottom = 6, margin_start = 12, margin_end = 12
        };
        box.append (time);
        box.append (dot);
        box.append (text);
        foreach (var action in item.actions) {
            box.append (action);
        }
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }
}
