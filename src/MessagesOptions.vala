// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Réglages › Messages: link previews (off by default: showing one contacts the
 * site) and the quick replies offered in notifications and in the quick reply
 * window. boomerangd keeps both.
 */

public class Boomerang.MessagesOptionsCard : Gtk.Box {
    private const int MAX_REPLIES = 8;

    private Daemon daemon;
    private Gtk.Switch previews;
    private Gtk.ListBox replies;
    private Gtk.Button add_button;
    private bool updating = false;
    private bool editing = false;  // an entry has the focus: the list is not rebuilt under it
    private uint save_timer = 0;

    public MessagesOptionsCard (Daemon daemon) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
        this.daemon = daemon;

        previews = new Gtk.Switch () { valign = Gtk.Align.CENTER };
        previews.notify["active"].connect (() => {
            if (!updating) {
                daemon.call.begin ("SetLinkPreviews", new Variant ("(b)", previews.active));
            }
        });
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
        list.add_css_class (Granite.CssClass.CARD);
        list.append (row ("insert-link", _("Aperçu des liens"),
                          _("Titre, site et image sous les messages qui contiennent un lien. "
                            + "Pour les afficher, Boomerang contacte le site."), previews));
        append (list);

        var title = new Granite.HeaderLabel (_("Réponses rapides")) {
            secondary_text = _("Proposées dans les notifications (les deux premières) et dans la fenêtre de réponse rapide.")
        };
        append (title);
        replies = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        replies.add_css_class (Granite.CssClass.CARD);
        append (replies);
        add_button = new Gtk.Button.with_label (_("Ajouter une réponse")) { halign = Gtk.Align.START };
        add_button.clicked.connect (() => {
            var texts = current ();
            texts += "";
            rebuild (texts, true);
        });
        append (add_button);

        daemon.changed.connect (() => {
            if (daemon.touched ({ "LinkPreviews", "QuickReplies" })) {
                update ();
            }
        });
        update ();
    }

    private string[] stored () {
        var value = daemon.get_value ("QuickReplies");
        return value != null ? value.dup_strv () : new string[0];
    }

    private void update () {
        updating = true;
        previews.active = daemon.get_bool ("LinkPreviews");
        updating = false;
        previews.sensitive = daemon.running;
        var texts = stored ();
        var shown = current ();
        // Any daemon property change lands here: rebuild only when the replies differ.
        if (!editing && save_timer == 0
                && (texts.length != shown.length || string.joinv ("\n", texts) != string.joinv ("\n", shown))) {
            rebuild (texts, false);
        }
    }

    private string[] current () {
        string[] texts = {};
        for (int i = 0; ; i++) {
            var row = replies.get_row_at_index (i);
            if (row == null) {
                break;
            }
            texts += ((Gtk.Entry) row.get_data<Gtk.Entry> ("entry")).text;
        }
        return texts;
    }

    private void rebuild (string[] texts, bool focus_last) {
        Gtk.Widget? child;
        while ((child = replies.get_first_child ()) != null) {
            replies.remove (child);
        }
        Gtk.Entry? last = null;
        for (int i = 0; i < texts.length; i++) {
            var index = i;
            var entry = new Gtk.Entry () { text = texts[i], hexpand = true, max_length = 120 };
            entry.add_css_class ("flat");
            entry.changed.connect (() => queue_save ());
            var focus = new Gtk.EventControllerFocus ();
            focus.enter.connect (() => editing = true);
            focus.leave.connect (() => {
                editing = false;
                save_now ();
            });
            entry.add_controller (focus);
            var remove = new Gtk.Button.from_icon_name ("edit-delete-symbolic") {
                tooltip_text = _("Retirer"),
                valign = Gtk.Align.CENTER
            };
            remove.add_css_class ("flat");
            remove.clicked.connect (() => {
                var all = current ();
                string[] kept = {};
                for (int j = 0; j < all.length; j++) {
                    if (j != index) {
                        kept += all[j];
                    }
                }
                rebuild (kept, false);
                save_now ();
            });
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 3, margin_bottom = 3, margin_start = 6, margin_end = 6
            };
            box.append (entry);
            box.append (remove);
            var row = new Gtk.ListBoxRow () { child = box, activatable = false };
            row.set_data<Gtk.Entry> ("entry", entry);
            replies.append (row);
            last = entry;
        }
        replies.visible = texts.length > 0;
        add_button.sensitive = texts.length < MAX_REPLIES;
        if (focus_last && last != null) {
            last.grab_focus ();
        }
    }

    private void queue_save () {
        if (save_timer != 0) {
            Source.remove (save_timer);
        }
        save_timer = Timeout.add (800, () => {
            save_timer = 0;
            save_now ();
            return Source.REMOVE;
        });
    }

    private void save_now () {
        if (save_timer != 0) {
            Source.remove (save_timer);
            save_timer = 0;
        }
        string[] texts = {};
        foreach (var text in current ()) {
            if (text.strip () != "") {
                texts += text.strip ();
            }
        }
        daemon.call.begin ("SetQuickReplies", new Variant.tuple ({ new Variant.strv (texts) }));
    }

    private static Gtk.Widget row (string icon, string title, string subtitle, Gtk.Widget end) {
        var image = new Gtk.Image.from_icon_name (icon) { pixel_size = 32, valign = Gtk.Align.START };
        var title_label = new Gtk.Label (title) { xalign = 0 };
        var detail = new Gtk.Label (subtitle) { xalign = 0, wrap = true };
        detail.add_css_class (Granite.CssClass.DIM);
        detail.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        text.append (detail);
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9, margin_bottom = 9, margin_start = 12, margin_end = 12
        };
        box.append (image);
        box.append (text);
        box.append (end);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }
}
