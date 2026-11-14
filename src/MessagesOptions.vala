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

/* Réglages › Messages, in the hub's Réglages and in the Messages app's own window. */
public class Boomerang.MessagesSettings : Gtk.Box {
    public delegate void LookChanged ();

    public MessagesSettings (Daemon daemon, owned LookChanged look_changed) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
        append (new Granite.HeaderLabel (_("Lecture")));
        append (build_read_full_card (daemon));
        append (new Granite.HeaderLabel (_("Codes SMS")));
        append (new CodesCard (daemon));
        append (new Granite.HeaderLabel (_("Liens")));
        append (new MessagesOptionsCard (daemon));
        append (new Granite.HeaderLabel (_("Apparence des conversations")) {
            secondary_text = _("Pour toutes les conversations. Chacune peut garder la sienne : "
                               + "cliquez sur son nom en haut de la conversation.")
        });
        append (default_look_card (daemon, (owned) look_changed));
    }

    /* A window of its own, for the Messages app (Réglages in its menu). */
    public static void present (Gtk.Window parent, Daemon daemon, owned LookChanged look_changed) {
        var settings = new MessagesSettings (daemon, (owned) look_changed) {
            margin_top = 6,
            margin_bottom = 24,
            margin_start = 24,
            margin_end = 24
        };
        var header = new Gtk.HeaderBar ();
        header.add_css_class ("flat");
        var window = new Gtk.Window () {
            title = _("Réglages de Messages"),
            transient_for = parent,
            modal = true,
            titlebar = header,
            default_width = 600,
            default_height = 640,
            child = new Gtk.ScrolledWindow () { child = settings, hscrollbar_policy = Gtk.PolicyType.NEVER }
        };
        window.present ();
    }

    /* The default look of conversations: the same editor as a conversation's palette. */
    private static Gtk.Widget default_look_card (Daemon daemon, owned LookChanged look_changed) {
        var editor = new ThreadStyleEditor (ThreadStyle.DEFAULTS, ThreadStyle.load_raw (ThreadStyle.DEFAULTS),
                                            null, daemon) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12,
            halign = Gtk.Align.START
        };
        editor.changed.connect (() => look_changed ());
        var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        card.add_css_class (Granite.CssClass.CARD);
        card.append (editor);
        return card;
    }

    private static Gtk.Widget build_read_full_card (Daemon daemon) {
        var title_label = new Gtk.Label (_("Toujours récupérer le texte complet")) { xalign = 0 };
        var subtitle_label = new Gtk.Label (
            _("Boomerang récupère dès leur arrivée le texte complet des messages de plus de "
              + "120 caractères. Ces messages sont alors marqués comme lus sur l'iPhone.")
        ) { xalign = 0, wrap = true };
        subtitle_label.add_css_class (Granite.CssClass.DIM);
        subtitle_label.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        text.append (subtitle_label);
        var sw = new Gtk.Switch () { valign = Gtk.Align.CENTER, active = daemon.get_bool ("FetchUnread") };
        sw.update_property (Gtk.AccessibleProperty.LABEL, title_label.label, -1);
        bool updating = false;
        sw.state_set.connect ((wanted) => {
            if (updating) {
                return false;
            }
            if (!wanted) {
                daemon.call.begin ("SetFetchUnread", new Variant ("(b)", false));
                return false;
            }
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                _("Toujours récupérer le texte complet ?"),
                _("Pour obtenir le texte complet d'un message non lu, Boomerang doit le télécharger "
                  + ": le message sera marqué comme lu sur l'iPhone dès son arrivée, même si vous ne "
                  + "l'avez pas ouvert."),
                Config.APP_ID + ".Messages", Gtk.ButtonsType.CANCEL) {
                transient_for = sw.get_root () as Gtk.Window,
                modal = true
            };
            var go = dialog.add_button (_("Activer"), Gtk.ResponseType.ACCEPT);
            go.add_css_class (Granite.CssClass.SUGGESTED);
            dialog.response.connect ((response) => {
                dialog.destroy ();
                if (response == Gtk.ResponseType.ACCEPT) {
                    daemon.call.begin ("SetFetchUnread", new Variant ("(b)", true));
                } else {
                    updating = true;
                    sw.active = false;
                    updating = false;
                }
            });
            dialog.present ();
            return false;
        });
        daemon.changed.connect (() => {
            if (!daemon.touched ({ "FetchUnread" })) {
                return;
            }
            var wanted = daemon.get_bool ("FetchUnread");
            if (sw.active != wanted) {
                updating = true;
                sw.active = wanted;
                updating = false;
            }
        });
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };
        box.append (text);
        box.append (sw);
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        list.add_css_class (Granite.CssClass.CARD);
        list.append (new Gtk.ListBoxRow () { child = box, activatable = false });
        list.append (auto_emoji_row ());
        return list;
    }

    /* ":)" becomes 🙂 while typing (kept by the app in apps.conf, see ComposeField). */
    private static Gtk.Widget auto_emoji_row () {
        var title_label = new Gtk.Label (_("Emojis automatiques")) { xalign = 0 };
        var subtitle_label = new Gtk.Label (
            _("« :) » devient 🙂, « :D » devient 😃, « <3 » devient ❤️… La touche Retour arrière annule la conversion.")
        ) { xalign = 0, wrap = true };
        subtitle_label.add_css_class (Granite.CssClass.DIM);
        subtitle_label.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        text.append (subtitle_label);
        var sw = new Gtk.Switch () { valign = Gtk.Align.CENTER, active = ComposeField.auto_emoji_enabled () };
        sw.update_property (Gtk.AccessibleProperty.LABEL, title_label.label, -1);
        sw.notify["active"].connect (() => ComposeField.set_auto_emoji (sw.active));
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };
        box.append (text);
        box.append (sw);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }}
