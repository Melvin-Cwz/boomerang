/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 MelvinCwz
 *
 * « Afficher dans la barre du haut »: the Boomerang indicator in Wingpanel reads
 * apps.conf [general] indicator (true unless turned off) and follows changes live.
 */

namespace Boomerang.IndicatorSetting {

    public bool enabled () {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
            return prefs.get_boolean ("general", "indicator");
        } catch (Error e) {
            return true;
        }
    }

    public void set_enabled (bool enabled) {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.KEEP_COMMENTS);
        } catch (Error e) {
            // first choice
        }
        prefs.set_boolean ("general", "indicator", enabled);
        try {
            DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
            prefs.save_to_file (Setup.prefs_path ());
        } catch (Error e) {
            warning ("cannot save the top bar choice: %s", e.message);
        }
    }

    /* Is the indicator installed? (Built only when the Wingpanel development files were there.) */
    public bool installed () {
        foreach (var dir in new string[] { "/usr/lib/x86_64-linux-gnu/wingpanel-9", "/usr/lib/wingpanel-9",
                                           "/usr/lib64/wingpanel-9" }) {
            if (FileUtils.test (Path.build_filename (dir, "libboomerang-indicator.so"), FileTest.EXISTS)) {
                return true;
            }
        }
        return false;
    }

    /* A card row for Réglages: title, explanation, then one control: Installer while the add-on is
       missing, the switch once it is there (with a discreet Retirer). */
    public Gtk.Widget row () {
        var title_label = new Gtk.Label (_("Afficher dans la barre du haut")) { xalign = 0 };
        var subtitle_label = new Gtk.Label ("") { xalign = 0, wrap = true };
        subtitle_label.add_css_class (Granite.CssClass.DIM);
        subtitle_label.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        text.append (subtitle_label);
        var sw = new Gtk.Switch () { valign = Gtk.Align.CENTER, active = enabled () };
        var install_button = new Gtk.Button () { valign = Gtk.Align.CENTER };
        show_installed (install_button, sw);
        set_subtitle (subtitle_label, installed ());
        sw.update_property (Gtk.AccessibleProperty.LABEL, title_label.label, -1);
        sw.notify["active"].connect (() => set_enabled (sw.active));
        install_button.clicked.connect (() => toggle_addon.begin (install_button, sw, subtitle_label));
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };
        box.append (new Gtk.Image.from_icon_name ("preferences-desktop") { pixel_size = 32, valign = Gtk.Align.CENTER });
        box.append (text);
        box.append (install_button);
        box.append (sw);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }

    private void show_installed (Gtk.Button button, Gtk.Switch sw) {
        var is_installed = installed ();
        sw.visible = is_installed;
        button.label = is_installed ? _("Retirer") : _("Installer");
        if (is_installed) {
            button.remove_css_class (Granite.CssClass.SUGGESTED);
            button.add_css_class ("flat");
        } else {
            button.add_css_class (Granite.CssClass.SUGGESTED);
            button.remove_css_class ("flat");
        }
    }

    private void set_subtitle (Gtk.Label label, bool is_installed) {
        label.label = is_installed
            ? _("Batterie de l'iPhone, lecture en cours, appel et messages non lus, à côté de l'horloge.")
            : _("Module facultatif : ajouté à Wingpanel seulement si vous le demandez.");
    }

    /* Installs or removes the add-on through the root helper (polkit asks for the password). */
    private async void toggle_addon (Gtk.Button button, Gtk.Switch sw, Gtk.Label subtitle) {
        var adding = !installed ();
        var helper = Path.build_filename (Config.LIBEXECDIR, "boomerang-wingpanel-addon");
        button.sensitive = false;
        try {
            var process = new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE,
                                          "pkexec", helper, adding ? "install" : "remove");
            string output;
            string errors;
            yield process.communicate_utf8_async (null, null, out output, out errors);
            if (!process.get_successful ()) {
                var reason = (errors ?? "").strip ();
                throw new IOError.FAILED (reason != "" ? reason : _("Opération annulée."));
            }
            sw.active = adding;
            show_installed (button, sw);
            subtitle.label = adding
                ? _("Installé. Relancez Wingpanel (ou la session) pour afficher l'indicateur.")
                : _("Retiré. Relancez Wingpanel pour le masquer.");
        } catch (Error e) {
            subtitle.label = _("Opération impossible : %s").printf (e.message);
        }
        button.sensitive = true;
    }
}
