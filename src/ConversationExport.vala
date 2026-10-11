// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Export of a conversation, from its right-click menu: plain text, or a PDF
 * laid out like the thread (my bubbles on the right, received ones on the left).
 */

namespace Boomerang.ConversationExport {
    private const double PAGE_W = 595;   // A4, in points
    private const double PAGE_H = 842;
    private const double MARGIN = 48;
    private const double BUBBLE_MAX = 330;
    private const double PAD_X = 10;
    private const double PAD_Y = 6;

    public async void run (Gtk.Window? parent, Daemon daemon, string thread, string title) {
        var pdf = new Gtk.FileFilter () { name = _("Document PDF") };
        pdf.add_suffix ("pdf");
        var text = new Gtk.FileFilter () { name = _("Texte") };
        text.add_suffix ("txt");
        var filters = new ListStore (typeof (Gtk.FileFilter));
        filters.append (pdf);
        filters.append (text);
        var dialog = new Gtk.FileDialog () {
            title = _("Exporter la conversation"),
            initial_name = _("Conversation avec %s.pdf").printf (title.replace ("/", "-")),
            filters = filters,
            default_filter = pdf
        };
        var documents = Environment.get_user_special_dir (UserDirectory.DOCUMENTS);
        if (documents != null) {
            dialog.initial_folder = File.new_for_path (documents);
        }
        File file;
        try {
            file = yield dialog.save (parent, null);
        } catch (Error e) {
            return;  // cancelled
        }
        bool ok;
        var items = yield daemon.try_list ("GetMessages", new Variant ("(s)", thread), out ok);
        var path = file.get_path ();
        if (!ok || path == null) {
            return;
        }
        try {
            if (path.down ().has_suffix (".txt")) {
                FileUtils.set_contents (path, as_text (items, title));
            } else {
                if (!path.down ().has_suffix (".pdf")) {
                    path += ".pdf";
                }
                as_pdf (items, title, path);
            }
            new Gtk.FileLauncher (File.new_for_path (path)).open_containing_folder.begin (parent, null);
        } catch (Error e) {
            warning ("export failed: %s", e.message);
        }
    }

    private string who (VariantDict d, string title) {
        if (dict_bool (d, "outgoing")) {
            return _("Moi");
        }
        var sender = dict_string (d, "sender");
        return sender != "" ? sender : title;
    }

    public string as_text (Variant[] items, string title) {
        var out = new StringBuilder ();
        out.append_printf ("%s\n", _("Conversation avec %s").printf (title));
        out.append_printf ("%s\n\n", _("Exportée de Boomerang le %s").printf (
            new DateTime.now_local ().format ("%d/%m/%Y %H:%M")));
        foreach (var item in items) {
            var d = new VariantDict (item);
            var when = new DateTime.from_unix_local (dict_int64 (d, "time")).format ("%d/%m/%Y %H:%M");
            var note = dict_string (d, "note");
            if (note != "") {
                out.append_printf ("[%s] %s\n", when, note);
                continue;
            }
            out.append_printf ("[%s] %s : %s\n", when, who (d, title), dict_string (d, "body"));
        }
        return out.str;
    }

    // "Sans": the fontconfig default, Inter is not always the font its name points to.
    private Pango.Layout layout (Cairo.Context cr, string text, string font, double width) {
        var l = Pango.cairo_create_layout (cr);
        l.set_font_description (Pango.FontDescription.from_string (font));
        l.set_width ((int) (width * Pango.SCALE));
        l.set_wrap (Pango.WrapMode.WORD_CHAR);
        l.set_text (text, -1);
        return l;
    }

    private void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
        cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
    }

    public void as_pdf (Variant[] items, string title, string path) throws Error {
        var surface = new Cairo.PdfSurface (path, PAGE_W, PAGE_H);
        var cr = new Cairo.Context (surface);
        double y = MARGIN;

        var head = layout (cr, title, "Sans Bold 16", PAGE_W - 2 * MARGIN);
        cr.set_source_rgb (0.1, 0.1, 0.12);
        cr.move_to (MARGIN, y);
        Pango.cairo_show_layout (cr, head);
        y += 26;
        var sub = layout (cr, _("Exportée de Boomerang le %s").printf (
            new DateTime.now_local ().format ("%d/%m/%Y %H:%M")), "Sans 9", PAGE_W - 2 * MARGIN);
        cr.set_source_rgb (0.45, 0.45, 0.5);
        cr.move_to (MARGIN, y);
        Pango.cairo_show_layout (cr, sub);
        y += 28;

        // Names over received bubbles only when several people write (a group).
        var senders = new GenericSet<string> (str_hash, str_equal);
        foreach (var item in items) {
            var d = new VariantDict (item);
            if (!dict_bool (d, "outgoing") && dict_string (d, "sender") != "") {
                senders.add (dict_string (d, "sender"));
            }
        }
        var group = senders.length > 1;
        int64 previous = 0;
        string previous_sender = "";
        foreach (var item in items) {
            var d = new VariantDict (item);
            var time = dict_int64 (d, "time");
            var outgoing = dict_bool (d, "outgoing");
            var note = dict_string (d, "note");
            Pango.Layout? stamp = null;
            if (time - previous > 3600) {
                stamp = layout (cr, long_time (time), "Sans 8", PAGE_W - 2 * MARGIN);
                stamp.set_alignment (Pango.Alignment.CENTER);
            }
            Pango.Layout? name = null;
            var sender = who (d, title);
            if (group && !outgoing && note == "" && (sender != previous_sender || stamp != null)) {
                name = layout (cr, sender, "Sans 8", BUBBLE_MAX);
            }
            var body = layout (cr, note != "" ? note : dict_string (d, "body"),
                               note != "" ? "Sans Italic 9" : "Sans 10", BUBBLE_MAX - 2 * PAD_X);
            int bw, bh;
            body.get_pixel_size (out bw, out bh);
            double needed = bh + 2 * PAD_Y + 6 + (stamp != null ? 24 : 0) + (name != null ? 14 : 0);
            if (y + needed > PAGE_H - MARGIN) {
                cr.show_page ();
                y = MARGIN;
            }
            if (stamp != null) {
                y += 8;
                cr.set_source_rgb (0.5, 0.5, 0.55);
                cr.move_to (MARGIN, y);
                Pango.cairo_show_layout (cr, stamp);
                y += 16;
            }
            if (name != null) {
                cr.set_source_rgb (0.5, 0.5, 0.55);
                cr.move_to (MARGIN + PAD_X, y);
                Pango.cairo_show_layout (cr, name);
                y += 14;
            }
            double w = bw + 2 * PAD_X;
            double h = bh + 2 * PAD_Y;
            double x = outgoing ? PAGE_W - MARGIN - w : MARGIN;
            if (note != "") {
                cr.set_source_rgb (0.5, 0.5, 0.55);
                cr.move_to (outgoing ? x + PAD_X : MARGIN + PAD_X, y);
                Pango.cairo_show_layout (cr, body);
            } else {
                rounded (cr, x, y, w, h, double.min (14, h / 2));
                if (outgoing) {
                    cr.set_source_rgb (0.21, 0.54, 0.90);  // elementary's blueberry
                } else {
                    cr.set_source_rgb (0.92, 0.92, 0.93);
                }
                cr.fill ();
                cr.set_source_rgb (outgoing ? 1 : 0.1, outgoing ? 1 : 0.1, outgoing ? 1 : 0.12);
                cr.move_to (x + PAD_X, y + PAD_Y);
                Pango.cairo_show_layout (cr, body);
            }
            y += h + 6;
            previous = time;
            previous_sender = outgoing ? "" : sender;
        }
        cr.show_page ();
        surface.finish ();
    }
}
