// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Modules (Boomerang 2): everything outside the core, added on demand. One row per
 * module of the daemon's Catalog property; adding one installs what it needs first
 * (PackageKit), then SetModuleAdded. Its page then joins the sidebar.
 */

namespace Boomerang.Catalog {
    /* The catalogue entry for a module id, or null. */
    public Variant? find (Daemon daemon, string id) {
        var list = daemon.get_value ("Catalog");
        if (list == null) {
            return null;
        }
        foreach (var entry in list) {
            if (Props.str (entry, "id") == id) {
                return entry;
            }
        }
        return null;
    }

    public bool added (Daemon daemon, string id) {
        return Props.flag (find (daemon, id), "added");
    }
}

public class Boomerang.ModulesView : Gtk.Box {
    /* A module with a page was just added: show it. */
    public signal void open_page (string page);

    private Daemon daemon;
    private Gtk.ListBox added_list;
    private Gtk.ListBox available_list;
    private Granite.HeaderLabel added_title;
    private Granite.HeaderLabel available_title;
    private string busy = "";  // module being installed or added
    private string failure = "";
    private string failed_module = "";

    public ModulesView (Daemon daemon) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.daemon = daemon;
        daemon.changed.connect (() => {
            if (daemon.touched ({ "Catalog" })) {
                fill ();
            }
        });
        fill ();
    }

    construct {
        var title = new Gtk.Label (_("Modules")) { xalign = 0 };
        title.add_css_class (Granite.HeaderLabel.Size.H1.to_string ());
        var intro = new Gtk.Label (
            _("Les personnes (messages, appels et contacts), les notifications et la lecture en cours font partie de Boomerang. "
            + "Les modules s'ajoutent à la demande ; un module retiré est arrêté et ses réglages "
            + "sont conservés.")
        ) { xalign = 0, wrap = true };
        intro.add_css_class (Granite.CssClass.DIM);
        added_title = new Granite.HeaderLabel (_("Ajoutés"));
        available_title = new Granite.HeaderLabel (_("Disponibles"));
        added_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        added_list.add_css_class (Granite.CssClass.CARD);
        available_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        available_list.add_css_class (Granite.CssClass.CARD);
        var content = new PageColumn ();  // the column of Réglages and Le Fil
        content.append (title);
        content.append (intro);
        content.append (added_title);
        content.append (added_list);
        content.append (available_title);
        content.append (available_list);
        append (new Gtk.ScrolledWindow () {
            child = content,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        });
    }

    private void fill () {
        foreach (var list in new Gtk.ListBox[] { added_list, available_list }) {
            while (list.get_first_child () != null) {
                list.remove (list.get_first_child ());
            }
        }
        int added = 0, available = 0;
        var catalog = daemon.get_value ("Catalog");
        if (catalog != null) {
            foreach (var entry in catalog) {
                if (Props.flag (entry, "added")) {
                    added_list.append (build_row (entry));
                    added++;
                } else {
                    available_list.append (build_row (entry));
                    available++;
                }
            }
        }
        added_title.visible = added_list.visible = added > 0;
        available_title.visible = available_list.visible = available > 0;
    }

    private Gtk.Widget build_row (Variant entry) {
        var id = Props.str (entry, "id");
        var added = Props.flag (entry, "added");
        var missing = Props.strings (entry, "missing");
        var page = Props.str (entry, "page");

        var icon = new Gtk.Image.from_icon_name (Props.str (entry, "icon")) { pixel_size = 32 };
        var name = new Gtk.Label (Props.str (entry, "title")) { xalign = 0 };
        name.add_css_class ("heading");
        var summary = new Gtk.Label (Props.str (entry, "summary")) { xalign = 0, wrap = true };
        summary.add_css_class (Granite.CssClass.DIM);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (name);
        text.append (summary);
        if (!added && missing.length > 0) {
            var needs = new Gtk.Label (_("Installe aussi : %s").printf (string.joinv (", ", missing))) {
                xalign = 0, wrap = true
            };
            needs.add_css_class (Granite.CssClass.SMALL);
            needs.add_css_class (Granite.CssClass.DIM);
            text.append (needs);
        }
        if (id == failed_module && failure != "") {
            var error = new Gtk.Label (failure) { xalign = 0, wrap = true };
            error.add_css_class (Granite.CssClass.ERROR);
            error.add_css_class (Granite.CssClass.SMALL);
            text.append (error);
        }

        Gtk.Widget control;
        if (busy == id) {
            control = new Gtk.Spinner () { spinning = true, valign = Gtk.Align.CENTER };
        } else {
            var button = new Gtk.Button.with_label (added ? _("Retirer") : _("Ajouter")) {
                valign = Gtk.Align.CENTER,
                sensitive = busy == ""
            };
            button.clicked.connect (() => toggle.begin (id, !added, missing, page));
            button.update_property (Gtk.AccessibleProperty.LABEL,
                                    "%s %s".printf (button.label, Props.str (entry, "title")), -1);
            control = button;
        }

        var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };
        line.append (icon);
        line.append (text);
        line.append (control);
        return new Gtk.ListBoxRow () { child = line, activatable = false };
    }

    private async void toggle (string id, bool add, string[] missing, string page) {
        busy = id;
        failure = failed_module = "";
        fill ();
        if (add && missing.length > 0) {
            try {
                yield new PackageInstaller ().install (missing);
            } catch (Error e) {
                failure = _("L'installation n'a pas abouti : %s").printf (e.message);
                failed_module = id;
                busy = "";
                fill ();
                return;
            }
        }
        var ok = yield daemon.call ("SetModuleAdded", new Variant ("(sb)", id, add));
        busy = "";
        fill ();
        if (ok && add && page != "") {
            open_page (page);
        }
    }
}
