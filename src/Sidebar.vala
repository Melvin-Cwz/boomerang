// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Navigation of the main window: sections grouped by where they come from
 * (the iPhone over Bluetooth, accessories, the Apple account over the
 * Internet), with the app's own colour icons and unread / missed badges.
 *
 * It can be folded down to its icons (Réglages › Affichage, F9, or by dragging its
 * edge): the counts then sit on the icons as red pills, like the badges of the dock.
 * The state and the width are kept in apps.conf [general] sidebar-collapsed and
 * sidebar-width.
 */

public class Boomerang.Sidebar : Gtk.Box {
    public Gtk.Stack pages { get; construct; }

    private Gtk.ListBox list;
    private Gtk.ListBox footer;
    private HashTable<string, Entry> entries = new HashTable<string, Entry> (str_hash, str_equal);
    private HashTable<string, string> sections = new HashTable<string, string> (str_hash, str_equal);
    private GenericSet<string> actions = new GenericSet<string> (str_hash, str_equal);
    private bool syncing = false;

    /* A bottom entry added by add_footer_action () was clicked. */
    public signal void action_activated (string id);
    private Gtk.Box player_slot;

    /* Icons only, with the counts on them. */
    public bool collapsed { get; set; default = false; }
    public const int COLLAPSED_WIDTH = 64;

    public const int MIN_WIDTH = 180;
    public const int MAX_WIDTH = 360;
    private Gtk.Paned? paned = null;
    private int expanded_width = 210;
    private bool placing = false;  // the position is being set by the code, not dragged

    /* The parts of one row that change with the folded state and the count. */
    [Compact]
    private class Entry {
        public Gtk.ListBoxRow row;
        public Gtk.Box box;
        public Gtk.Label label;
        public Gtk.Label badge;
        public Gtk.Label dock_badge;
        public string title;
        public string count = "";
    }

    private static bool css_added = false;
    // Same C call as Gtk.StyleContext.add_provider_for_display, without the class deprecated in 4.10.
    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    private static extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider,
                                                         uint priority);
    private const string CSS = """
        label.sidebar-dock-badge {
            background-color: #c6262e;
            color: white;
            font-weight: bold;
            font-size: 10px;
            border: 1px solid alpha(white, 0.85);
            border-radius: 999px;
            min-height: 14px;
            min-width: 8px;
            padding: 0 3px;
            box-shadow: 0 1px 2px alpha(black, 0.35);
            transform: translate(7px, -6px);
        }
        separator.sidebar-section-separator {
            margin: 6px 12px;
        }
    """;

    public Sidebar (Gtk.Stack pages) {
        Object (pages: pages, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
    }

    construct {
        list = new Gtk.ListBox () { vexpand = true };
        list.add_css_class ("navigation-sidebar");
        list.set_header_func ((row, before) => {
            var name = row.get_data<string> ("page");
            var section = sections[name];
            var previous = before != null ? sections[before.get_data<string> ("page")] : null;
            if (section != previous && collapsed) {
                if (before != null) {
                    var line = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
                    line.add_css_class ("sidebar-section-separator");
                    row.set_header (line);
                } else {
                    row.set_header (null);
                }
            } else if (section != previous) {
                var label = new Gtk.Label (section) { xalign = 0, margin_start = 9, margin_top = 12 };
                label.add_css_class (Granite.CssClass.DIM);
                label.add_css_class (Granite.CssClass.SMALL);
                label.add_css_class ("sidebar-section");
                row.set_header (label);
            } else {
                row.set_header (null);
            }
        });
        list.row_selected.connect ((row) => {
            if (row != null && !syncing) {
                pages.visible_child_name = row.get_data<string> ("page");
            }
        });
        // Réglages stay at the bottom, apart from the sections.
        footer = new Gtk.ListBox ();
        footer.add_css_class ("navigation-sidebar");
        footer.row_selected.connect ((row) => {
            if (row == null || syncing) {
                return;
            }
            var page = row.get_data<string> ("page");
            if (actions.contains (page)) {
                // Opens a window rather than a page: keep the current page selected.
                sync ();
                action_activated (page);
            } else {
                pages.visible_child_name = page;
            }
        });
        pages.notify["visible-child-name"].connect (sync);

        var scroll = new Gtk.ScrolledWindow () {
            child = list,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        };
        append (scroll);
        player_slot = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        append (player_slot);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        append (footer);

        if (!css_added) {
            css_added = true;
            var provider = new Gtk.CssProvider ();
            provider.load_from_string (CSS);
            add_provider_for_display (Gdk.Display.get_default (), provider,
                                      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        // F9 folds or unfolds the sidebar from anywhere in the window.
        var shortcuts = new Gtk.ShortcutController () { scope = Gtk.ShortcutScope.GLOBAL };
        shortcuts.add_shortcut (new Gtk.Shortcut (
            Gtk.ShortcutTrigger.parse_string ("F9"),
            new Gtk.CallbackAction (() => {
                collapsed = !collapsed;
                return true;
            })
        ));
        add_controller (shortcuts);

        collapsed = load_collapsed ();
        notify["collapsed"].connect (() => {
            apply_collapsed ();
            save_collapsed ();
        });
    }

    /*
     * The pane holding the sidebar: its edge can be dragged. Narrower than the
     * smallest width folds the sidebar to its icons, a drag from the icons
     * unfolds it; in between, the width is the user's and is kept.
     */
    public void attach_paned (Gtk.Paned holder) {
        paned = holder;
        expanded_width = load_width ();
        paned.notify["position"].connect (() => {
            if (placing) {
                return;
            }
            var position = paned.position;
            if (!collapsed && position < MIN_WIDTH - 30) {
                collapsed = true;
            } else if (collapsed && position > COLLAPSED_WIDTH + 40) {
                expanded_width = int.max (position, MIN_WIDTH);
                collapsed = false;
            } else if (!collapsed) {
                expanded_width = position.clamp (MIN_WIDTH, MAX_WIDTH);
                queue_save_width ();
            } else {
                place (COLLAPSED_WIDTH);  // folded: stays at the icons' width
            }
        });
        apply_collapsed ();
    }

    private void place (int width) {
        if (paned == null) {
            return;
        }
        placing = true;
        paned.position = width;
        placing = false;
    }

    private uint width_timer = 0;

    private void queue_save_width () {
        if (width_timer != 0) {
            Source.remove (width_timer);
        }
        width_timer = Timeout.add (500, () => {
            width_timer = 0;
            save_collapsed ();
            return Source.REMOVE;
        });
    }

    private void apply_collapsed () {
        list.invalidate_headers ();
        player_slot.visible = !collapsed;
        foreach (var entry in entries.get_values ()) {
            update_entry (entry);
        }
        width_request = COLLAPSED_WIDTH;
        place (collapsed ? COLLAPSED_WIDTH : expanded_width.clamp (MIN_WIDTH, MAX_WIDTH));
    }

    private void update_entry (Entry entry) {
        var count = entry.count;
        entry.label.visible = !collapsed;
        entry.box.halign = collapsed ? Gtk.Align.CENTER : Gtk.Align.FILL;
        entry.badge.label = count;
        entry.badge.visible = !collapsed && count != "";
        entry.dock_badge.label = count;
        entry.dock_badge.visible = collapsed && count != "";
        entry.row.tooltip_text = collapsed ? (count != "" ? "%s (%s)".printf (entry.title, count) : entry.title)
                                           : null;
        entry.row.update_property (Gtk.AccessibleProperty.LABEL,
                                   count != "" ? "%s, %s".printf (entry.title, count) : entry.title, -1);
    }

    private static int load_width () {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
            return prefs.get_integer ("general", "sidebar-width").clamp (MIN_WIDTH, MAX_WIDTH);
        } catch (Error e) {
            return 210;
        }
    }

    private static bool load_collapsed () {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
            return prefs.get_boolean ("general", "sidebar-collapsed");
        } catch (Error e) {
            return false;
        }
    }

    private void save_collapsed () {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.KEEP_COMMENTS);
        } catch (Error e) {
            // first choice
        }
        prefs.set_boolean ("general", "sidebar-collapsed", collapsed);
        prefs.set_integer ("general", "sidebar-width", expanded_width);
        try {
            DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
            prefs.save_to_file (Setup.prefs_path ());
        } catch (Error e) {
            warning ("cannot save the sidebar state: %s", e.message);
        }
    }

    /* A widget shown just above Réglages (the Now Playing mini player). */
    public void set_player (Gtk.Widget player) {
        player_slot.append (player);
    }

    public void add (string page, string section, string icon, string title) {
        sections[page] = section;
        list.append (make_row (page, icon, title));
        sync ();
    }

    public void add_footer (string page, string icon, string title) {
        footer.append (make_row (page, icon, title));
        sync ();
    }

    /* A bottom entry that runs an action (opens a window) instead of showing a page. */
    public void add_footer_action (string id, string icon, string title) {
        actions.add (id);
        footer.append (make_row (id, icon, title));
    }

    private Gtk.ListBoxRow make_row (string page, string icon, string title) {
        var image = new Gtk.Image.from_icon_name (icon) { pixel_size = 24 };
        var label = new Gtk.Label (title) { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
        var badge = new Gtk.Label ("") { visible = false, valign = Gtk.Align.CENTER };
        badge.add_css_class (Granite.STYLE_CLASS_BADGE);
        // Folded: the count on the icon's top-right corner, as on the dock.
        var dock_badge = new Gtk.Label ("") {
            visible = false,
            halign = Gtk.Align.END,
            valign = Gtk.Align.START,
            can_target = false
        };
        dock_badge.add_css_class ("sidebar-dock-badge");
        var icon_box = new Gtk.Overlay () { child = image, valign = Gtk.Align.CENTER };
        icon_box.add_overlay (dock_badge);
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 9) {
            margin_top = 3,
            margin_bottom = 3,
            margin_start = 3,
            margin_end = 3
        };
        box.append (icon_box);
        box.append (label);
        box.append (badge);
        var row = new Gtk.ListBoxRow () { child = box };
        row.set_data<string> ("page", page);
        var entry = new Entry () {
            row = row, box = box, label = label, badge = badge, dock_badge = dock_badge, title = title
        };
        update_entry (entry);
        entries[page] = (owned) entry;
        return row;
    }

    /* Page shown by Ctrl+1…9: the n-th entry of the list. */
    public void select_index (int index) {
        var row = list.get_row_at_index (index);
        if (row != null) {
            pages.visible_child_name = row.get_data<string> ("page");
        }
    }

    /* A number next to the page name (0 hides it). */
    public void set_badge (string page, uint count) {
        unowned Entry? entry = entries[page];
        if (entry == null) {
            return;
        }
        entry.count = count == 0 ? "" : (count > 99 ? "99+" : count.to_string ());
        update_entry (entry);
    }

    private void sync () {
        var name = pages.visible_child_name;
        syncing = true;
        foreach (var box in new Gtk.ListBox[] { list, footer }) {
            Gtk.ListBoxRow? match = null;
            for (int i = 0; box.get_row_at_index (i) != null; i++) {
                var row = box.get_row_at_index (i);
                if (row.get_data<string> ("page") == name) {
                    match = row;
                }
            }
            if (match == null) {
                box.unselect_all ();
            } else if (box.get_selected_row () != match) {
                box.select_row (match);
            }
        }
        syncing = false;
    }
}
