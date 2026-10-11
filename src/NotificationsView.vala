// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Notifications tab: what the iPhone shows (ANCS), newest first, and one switch
 * per app to have its notifications pop up on this PC or not. The list is kept
 * in memory by the daemon only.
 */

public class Boomerang.NotificationsView : Gtk.Box {
    public Daemon daemon { get; construct; }

    private Gtk.ListBox apps;
    private Gtk.ListBox items;
    private Gtk.Stack items_stack;
    private Gtk.Stack apps_stack;
    private string? filter = null;

    public NotificationsView (Daemon daemon) {
        Object (daemon: daemon, orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
    }

    private Gtk.Box sidebar;
    private Gtk.Separator separator;
    private Gtk.Button clear;

    construct {
        // Apps
        apps = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.SINGLE };
        apps.add_css_class ("navigation-sidebar");
        apps.row_selected.connect ((row) => {
            filter = row != null ? row.get_data<string> ("app") : null;
            items.invalidate_filter ();
            update_empty ();
        });
        var apps_empty = new Gtk.Label (_("Les apps apparaissent ici dès leur première notification.")) {
            wrap = true,
            justify = Gtk.Justification.CENTER,
            margin_top = 24,
            margin_start = 12,
            margin_end = 12
        };
        apps_empty.add_css_class (Granite.CssClass.DIM);
        apps_stack = new Gtk.Stack ();
        apps_stack.add_named (new Gtk.ScrolledWindow () {
            child = apps,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        }, "list");
        apps_stack.add_named (apps_empty, "empty");
        var apps_title = new Gtk.Label (_("Apps de l'iPhone")) { xalign = 0, margin_start = 12, margin_top = 12 };
        apps_title.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
        var apps_hint = new Gtk.Label (_("Choisissez celles qui s'affichent sur ce PC")) {
            xalign = 0,
            margin_start = 12,
            margin_bottom = 6
        };
        apps_hint.add_css_class (Granite.CssClass.DIM);
        apps_hint.add_css_class (Granite.CssClass.SMALL);
        sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { width_request = 280 };
        sidebar.append (apps_title);
        sidebar.append (apps_hint);
        sidebar.append (apps_stack);

        // Notifications
        items = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            show_separators = true,
            valign = Gtk.Align.START,
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 18,
            margin_end = 18
        };
        items.add_css_class (Granite.CssClass.CARD);
        items.set_filter_func ((row) => filter == null || row.get_data<string> ("app") == filter);
        var empty = new Granite.Placeholder (_("Aucune notification")) {
            description = _("Les notifications de l'iPhone s'afficheront ici, tant que l'iPhone est relié "
                          + "à « Boomerang » en Bluetooth basse consommation. Elles ne sont jamais "
                          + "enregistrées sur le disque."),
            icon = new ThemedIcon ("preferences-system-notifications")
        };
        items_stack = new Gtk.Stack () { hexpand = true };
        items_stack.add_css_class ("view");
        items_stack.add_named (new Gtk.ScrolledWindow () {
            child = items,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        }, "list");
        items_stack.add_named (empty, "empty");

        clear = new Gtk.Button.with_label (_("Effacer la liste")) { halign = Gtk.Align.END };
        clear.add_css_class ("flat");
        clear.tooltip_text = _("Vide la liste de Boomerang ; rien ne change sur l'iPhone");
        clear.clicked.connect (() => daemon.call.begin ("ClearNotifications"));
        var right_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_top = 6,
            margin_end = 12,
            halign = Gtk.Align.END
        };
        right_bar.append (clear);
        var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        right.append (right_bar);
        right.append (items_stack);

        separator = new Gtk.Separator (Gtk.Orientation.VERTICAL);
        append (sidebar);
        append (separator);
        append (right);

        daemon.notifications_changed.connect (() => {
            if (get_mapped ()) {  // hidden: map reloads it
                reload.begin ();
            }
        });
        map.connect (() => reload.begin ());
    }

    private void update_empty () {
        bool any = false;
        for (int i = 0; items.get_row_at_index (i) != null; i++) {
            var row = items.get_row_at_index (i);
            if (filter == null || row.get_data<string> ("app") == filter) {
                any = true;
                break;
            }
        }
        items_stack.visible_child_name = any ? "list" : "empty";
        // Nothing received yet: one calm placeholder instead of two empty columns.
        var has_items = items.get_row_at_index (0) != null;
        clear.visible = has_items;
        sidebar.visible = has_items || apps_stack.visible_child_name == "list";
        separator.visible = sidebar.visible;
    }

    private async void reload () {
        var app_items = yield daemon.call_list ("ListNotificationApps");
        var note_items = yield daemon.call_list ("ListNotifications");

        var selected = filter;
        Gtk.Widget? child;
        while ((child = apps.get_first_child ()) != null) {
            apps.remove (child);
        }
        var all = app_row (null, _("Toutes les apps"), 0, false);
        apps.append (all);
        Gtk.ListBoxRow? to_select = all;
        foreach (var item in app_items) {
            var d = new VariantDict (item);
            var id = dict_string (d, "id");
            var row = app_row (id, dict_string (d, "name"), dict_uint (d, "count"), dict_bool (d, "enabled"), d);
            apps.append (row);
            if (id == selected) {
                to_select = row;
            }
        }
        apps.select_row (to_select);
        apps_stack.visible_child_name = app_items.length > 0 ? "list" : "empty";

        while ((child = items.get_first_child ()) != null) {
            items.remove (child);
        }
        foreach (var item in note_items) {
            items.append (note_row (new VariantDict (item)));
        }
        update_empty ();
    }

    /* Icon of the iPhone app: App Store artwork, a local icon, or a generic phone. */
    private static Gtk.Image app_image (VariantDict? d, int size) {
        var image = d != null ? dict_string (d, "image") : "";
        var icon = d != null ? dict_string (d, "icon") : "";
        Gtk.Image widget;
        if (image != "") {
            widget = new Gtk.Image.from_file (image);
        } else {
            widget = new Gtk.Image.from_icon_name (icon != "" ? icon : "phone");
        }
        widget.pixel_size = size;
        return widget;
    }

    private Gtk.ListBoxRow app_row (string? id, string name, uint count, bool enabled,
                                    VariantDict? d = null) {
        var label = new Gtk.Label (name) { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            margin_top = 4,
            margin_bottom = 4,
            margin_start = 6,
            margin_end = 6
        };
        if (id != null) {
            box.append (app_image (d, 24));
        }
        box.append (label);
        if (count > 0) {
            var badge = new Gtk.Label (count.to_string ());
            badge.add_css_class (Granite.CssClass.DIM);
            badge.add_css_class (Granite.CssClass.SMALL);
            box.append (badge);
        }
        if (id != null) {
            // How this app alerts: a mark in the row, the details behind the button.
            var mode = d != null ? dict_string (d, "mode") : "";
            if (mode != "") {
                var mark = new Gtk.Image.from_icon_name (mode == "priority" ? "starred-symbolic"
                                                                             : "notifications-disabled-symbolic") {
                    tooltip_text = mode == "priority" ? _("Prioritaires") : _("Discrètes, sans son")
                };
                mark.add_css_class (Granite.CssClass.DIM);
                box.append (mark);
            }
            var app_id = id;
            var more = new Gtk.MenuButton () {
                icon_name = "view-more-symbolic",
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Réglages des notifications de %s").printf (name),
                sensitive = enabled
            };
            more.add_css_class ("flat");
            more.set_create_popup_func ((button) => {
                button.popover = new Gtk.Popover () { child = new AppNotifyEditor (daemon, app_id, name) };
            });
            box.append (more);
            var sw = new Gtk.Switch () {
                active = enabled,
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Afficher les notifications de %s sur ce PC").printf (name)
            };
            sw.notify["active"].connect (() => {
                more.sensitive = sw.active;
                daemon.call.begin ("SetNotificationApp", new Variant ("(sb)", id, sw.active));
            });
            box.append (sw);
        }
        var row = new Gtk.ListBoxRow () { child = box };
        row.set_data<string> ("app", id);
        return row;
    }

    private Gtk.ListBoxRow note_row (VariantDict d) {
        var app = new Gtk.Label (dict_string (d, "app_name")) { xalign = 0, hexpand = true };
        app.add_css_class (Granite.CssClass.DIM);
        app.add_css_class (Granite.CssClass.SMALL);
        var time = new Gtk.Label (short_time (dict_int64 (d, "time")));
        time.add_css_class (Granite.CssClass.DIM);
        time.add_css_class (Granite.CssClass.SMALL);
        var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        top.append (app_image (d, 16));
        top.append (app);
        top.append (time);
        var title = new Gtk.Label (dict_string (d, "title")) {
            xalign = 0,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD_CHAR
        };
        title.add_css_class ("setup-step-title");
        var body = new Gtk.Label (dict_string (d, "body")) {
            xalign = 0,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD_CHAR,
            selectable = true
        };
        body.visible = body.label != "";
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
            margin_top = 8,
            margin_bottom = 8,
            margin_start = 12,
            margin_end = 12
        };
        text.append (top);
        text.append (title);
        text.append (body);
        // Alpha: the iPhone's own actions (e.g. « Marquer comme lu », « Supprimer »).
        var uid = d.lookup_value ("uid", VariantType.UINT32);
        if (uid != null && daemon.alpha_enabled ("ancs_actions")) {
            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { margin_top = 4 };
            foreach (var key in new string[] { "positive", "negative" }) {
                var label = dict_string (d, key);
                if (label == "") {
                    continue;
                }
                var button = new Gtk.Button.with_label (label) {
                    tooltip_text = _("Action envoyée à l'iPhone (expérimental)")
                };
                button.add_css_class (Granite.CssClass.SMALL);
                if (key == "negative") {
                    button.add_css_class ("destructive-action");
                }
                var action = key;
                button.clicked.connect (() => {
                    button.sensitive = false;
                    daemon.call.begin ("NotificationAction",
                                       new Variant ("(us)", uid.get_uint32 (), action));
                });
                actions.append (button);
            }
            if (actions.get_first_child () != null) {
                text.append (actions);
            }
        }
        var row = new Gtk.ListBoxRow () { child = text, activatable = false };
        row.set_data<string> ("app", dict_string (d, "app"));
        return row;
    }
}

/*
 * One iPhone app's notifications on this PC: normal, priority (banner and sound
 * under Do Not Disturb) or quiet (no sound), its own sound, and its text hidden
 * from the banner. boomerangd keeps the choice.
 */
public class Boomerang.AppNotifyEditor : Gtk.Box {
    private Daemon daemon;
    private string app;
    private string mode = "";
    private string sound = "";
    private bool hidden = false;
    private string[] sound_values = {};
    private string[] sound_labels = {};

    public AppNotifyEditor (Daemon daemon, string app, string name) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        this.daemon = daemon;
        this.app = app;
        margin_top = margin_bottom = margin_start = margin_end = 9;
        width_request = 320;
        var title = new Gtk.Label (name) { xalign = 0 };
        title.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
        append (title);
        build ();
        load.begin ();
    }

    private async void load () {
        try {
            var reply = yield daemon.call_checked ("GetNotificationAppSettings", new Variant ("(s)", app));
            reply.get ("(ssb)", out mode, out sound, out hidden);
        } catch (Error e) {
            warning ("GetNotificationAppSettings failed: %s", e.message);
        }
        build ();
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
        build ();
    }

    private void build () {
        Gtk.Widget? child = get_first_child ().get_next_sibling ();
        while (child != null) {
            var next = child.get_next_sibling ();
            remove (child);
            child = next;
        }
        string[] modes = { "", "priority", "quiet" };
        string[] labels = { _("Normales"), _("Prioritaires"), _("Discrètes") };
        var choice = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { homogeneous = true, margin_top = 4 };
        choice.add_css_class ("linked");
        for (int i = 0; i < modes.length; i++) {
            var value = modes[i];
            var button = new Gtk.ToggleButton.with_label (labels[i]) { active = value == mode };
            button.clicked.connect (() => {
                mode = value;
                save ();
                build ();
            });
            choice.append (button);
        }
        append (choice);
        var help = new Gtk.Label (
            mode == "priority" ? _("Bannière et son même en mode Ne pas déranger.")
            : mode == "quiet" ? _("Bannière sans son.")
            : _("Comme les autres applications.")
        ) { xalign = 0, wrap = true, max_width_chars = 40 };
        help.add_css_class (Granite.CssClass.DIM);
        help.add_css_class (Granite.CssClass.SMALL);
        append (help);

        if (mode != "quiet") {
            var sound_title = new Gtk.Label (_("Son")) { xalign = 0, margin_top = 6 };
            sound_title.add_css_class (Granite.HeaderLabel.Size.H4.to_string ());
            append (sound_title);
            string[] values = { "", "none" };
            var model = new Gtk.StringList ({ _("Son des notifications (Réglages)"), _("Aucun") });
            for (int i = 0; i < sound_values.length; i++) {
                values += sound_values[i];
                model.append (sound_labels[i]);
            }
            uint selected = 0;
            for (uint i = 0; i < values.length; i++) {
                if (values[i] == sound) {
                    selected = i;
                }
            }
            var drop = new Gtk.DropDown (model, null) { selected = selected, hexpand = true, enable_search = true };
            drop.notify["selected"].connect (() => {
                sound = values[drop.selected];
                save ();
            });
            var play = new Gtk.Button.from_icon_name ("media-playback-start-symbolic") { tooltip_text = _("Écouter") };
            play.clicked.connect (() => {
                if (sound != "none") {
                    daemon.call.begin ("PlaySound", new Variant ("(ss)", "notifications", sound != "" ? sound : "default"));
                }
            });
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            line.append (drop);
            line.append (play);
            append (line);
        }

        var privacy = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { margin_top = 8 };
        var texts = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true };
        texts.append (new Gtk.Label (_("Masquer le contenu")) { xalign = 0 });
        var detail = new Gtk.Label (_("La bannière indique seulement le nom de l'application. Le texte reste lisible dans Boomerang.")) {
            xalign = 0, wrap = true, max_width_chars = 36
        };
        detail.add_css_class (Granite.CssClass.DIM);
        detail.add_css_class (Granite.CssClass.SMALL);
        texts.append (detail);
        var hide = new Gtk.Switch () { active = hidden, valign = Gtk.Align.CENTER };
        hide.notify["active"].connect (() => {
            hidden = hide.active;
            save ();
        });
        privacy.append (texts);
        privacy.append (hide);
        append (privacy);
    }

    private void save () {
        daemon.call.begin ("SetNotificationAppSettings", new Variant ("(sssb)", app, mode, sound, hidden));
    }
}
