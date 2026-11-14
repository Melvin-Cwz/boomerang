/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 MelvinCwz
 *
 * « Nouveautés »: what changed in this version, shown once after an update and from Réglages.
 * The version last shown is kept in apps.conf [general] whats-new.
 */

namespace Boomerang.WhatsNew {

    private struct Item {
        string icon;
        string title;
        string text;
    }

    private static Item[] items () {
        return {
            { "view-grid-symbolic", _("Un menu qui dit où vous êtes"),
              _("Dans l'onglet iPhone, le menu de gauche est en trois groupes et la page courante est "
                + "bien visible. La nouvelle « Vue d'ensemble » réunit l'iPhone et ses raccourcis.") },
            { "preferences-system-symbolic", _("Des réglages en deux onglets"),
              _("Les réglages d'usage courant sont dans « Essentiels », tout le reste dans « Avancés ».") },
            { "preferences-desktop-notification-symbolic", _("Un panneau de la barre du haut refait"),
              _("Raccourcis, messages et appels à rattraper, appel en cours ou entrant, et un état "
                + "clair quand l'iPhone est hors de portée.") },
            { "system-users-symbolic", _("Une personne, un fil"),
              _("Les messages et les appels d'une même personne se suivent dans un seul fil, avec "
                + "sa fiche à droite. Trois onglets : Contacts, Composer et iPhone.") },
            { "mail-unread-symbolic", _("Messages plus complets"),
              _("L'historique plus ancien se charge en remontant, les filtres isolent les non-lus et "
                + "les inconnus, et Ctrl+? affiche tous les raccourcis.") },
            { "call-start-symbolic", _("Le double appel"),
              _("Mettez un appel en attente pour répondre au second, permutez ou réunissez-les, et "
                + "choisissez où passe le son. Favoris et messagerie vocale sont dans l'onglet Composer.") },
            { "x-office-address-book-symbolic", _("Des fiches de contact complètes"),
              _("Adresses, sites, anniversaires et photo, modifiables avec iCloud ; import et export "
                + "de fichiers vCard.") },
            { "audio-headphones-symbolic", _("AirPods et recopie"),
              _("Alerte de batterie faible, pause quand vous retirez un écouteur, captures d'écran "
                + "de la recopie dans le dossier Images.") },
            { "edit-clear-all-symbolic", _("Fini les notifications fantômes"),
              _("Une notification effacée sur l'iPhone disparaît aussi de ce PC, même si elle a été "
                + "effacée pendant une coupure, et une notification fermée ici ne revient plus.") },
            { "emblem-synchronizing-symbolic", _("Une réparation guidée"),
              _("Quand les notifications s'arrêtent, « Appairer à nouveau » efface les anciennes clés "
                + "et vous guide pas à pas pour refaire un appairage propre.") },
            { "preferences-system-notifications-symbolic", _("Des notifications plus fiables"),
              _("Les notifications de l'iPhone reviennent seules après une reconnexion ou un "
                + "redémarrage : plus besoin d'appairer à nouveau.") },
            { "bluetooth-active-symbolic", _("L'iPhone en haut de la fenêtre"),
              _("Son nom, sa batterie et un arc en trois parties qui se remplit à mesure que la "
                + "liaison s'établit. Un clic explique ce qui se passe et propose quoi faire.") },
            { "view-refresh-symbolic", _("Reconnexion plus rapide"),
              _("Dès qu'un appareil Apple est capté à proximité, Boomerang tente de reconnecter l'iPhone "
                + "sans attendre son prochain essai. Le service redémarre seul s'il se fige.") },
            { "list-add-symbolic", _("Modules à la demande"),
              _("Messages, appels, contacts, notifications et lecture en cours restent toujours là. "
                + "AirPods, iCloud, fichiers, recopie et le reste s'ajoutent depuis « Ajouter des "
                + "modules… ». Les modules que vous utilisiez déjà restent en place.") },
            { "open-menu-symbolic", _("Une colonne plus courte"),
              _("Réglages, guide, contributeurs et À propos passent dans le menu de la barre d'en-tête.") },
            { "call-missed-symbolic", _("Appels manqués d'un clic"),
              _("Dans l'onglet Composer, la liste des appels montre tous les appels ou seulement les manqués.") },
        };
    }

    private static string last_shown () {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.NONE);
            return prefs.get_string ("general", "whats-new");
        } catch (Error e) {
            return "";
        }
    }

    private static void remember () {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (Setup.prefs_path (), KeyFileFlags.KEEP_COMMENTS);
        } catch (Error e) {
            // first choice
        }
        prefs.set_string ("general", "whats-new", Config.VERSION);
        try {
            DirUtils.create_with_parents (Path.get_dirname (Setup.prefs_path ()), 0700);
            prefs.save_to_file (Setup.prefs_path ());
        } catch (Error e) {
            warning ("cannot save the version shown: %s", e.message);
        }
    }

    /* Once per version, after an update (not on a first install: the setup assistant runs then). */
    public void maybe_show (Gtk.Window parent, bool first_run) {
        if (last_shown () == Config.VERSION) {
            return;
        }
        remember ();
        if (!first_run) {
            Idle.add (() => {
                show (parent);
                return Source.REMOVE;
            });
        }
    }

    public void show (Gtk.Window? parent) {
        var list = new Gtk.Box (Gtk.Orientation.VERTICAL, 14) {
            margin_top = 6,
            margin_bottom = 6
        };
        foreach (var item in items ()) {
            var icon = new Gtk.Image.from_icon_name (item.icon) {
                pixel_size = 24,
                valign = Gtk.Align.START
            };
            icon.add_css_class (Granite.CssClass.ACCENT);
            var title = new Gtk.Label (item.title) { xalign = 0 };
            title.add_css_class ("heading");
            var text = new Gtk.Label (item.text) {
                xalign = 0,
                wrap = true,
                max_width_chars = 48
            };
            text.add_css_class (Granite.CssClass.DIM);
            var words = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true };
            words.append (title);
            words.append (text);
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            row.append (icon);
            row.append (words);
            list.append (row);
        }
        var scrolled = new Gtk.ScrolledWindow () {
            child = list,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            propagate_natural_height = true,
            max_content_height = 420
        };
        var dialog = new Granite.MessageDialog.with_image_from_icon_name (
            _("Nouveautés de Boomerang %s").printf (Config.VERSION),
            _("Ce qui change dans cette version."),
            Config.APP_ID, Gtk.ButtonsType.NONE) {
            transient_for = parent,
            modal = true
        };
        dialog.custom_bin.append (scrolled);
        var ok = dialog.add_button (_("Continuer"), Gtk.ResponseType.CLOSE);
        ok.add_css_class (Granite.CssClass.SUGGESTED);
        dialog.response.connect (() => dialog.destroy ());
        dialog.present ();
    }
}
