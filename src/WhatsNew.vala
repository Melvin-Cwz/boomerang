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
            { "emblem-synchronizing-symbolic", _("Plus léger, nouvelle icône"),
              _("Boomerang et son démon consomment moins de ressources en arrière-plan : moins de commandes, "
                + "moins de rafraîchissements, conversations plus rapides. Nouvelle icône dessinée "
                + "comme celles d'elementary.") },
            { "mail-unread-symbolic", _("Messages au bon endroit"),
              _("Une conversation s'ouvre sur le dernier message. Un repère « Non lus » montre où "
                + "reprendre, et un bouton ramène en bas en comptant les nouveaux messages.") },
            { "preferences-color-symbolic", _("Conversations personnalisées"),
              _("Surnom, emoji, couleur des bulles, fond, taille du texte : bouton palette en haut "
                + "d'une conversation, ou clic droit › Personnaliser.") },
            { "preferences-system-notifications-symbolic", _("Notifications à la carte"),
              _("Par conversation et par appli de l'iPhone : prioritaires (même en Ne pas déranger), "
                + "discrètes ou muettes, avec leur propre son, et le contenu masqué si besoin.") },
            { "edit-find-symbolic", _("Chercher dans une conversation"),
              _("Ctrl+F cherche dans la conversation ouverte, Ctrl+Maj+F dans toutes. Alt+↑/↓ "
                + "change de conversation, Ctrl+N écrit un nouveau message.") },
            { "insert-link-symbolic", _("Liens et réponses rapides"),
              _("Aperçu des liens au choix, réponses rapides personnalisables, aussi dans les "
                + "notifications : Réglages › Messages. Clic droit › Exporter, en PDF ou en texte.") },
            { "preferences-desktop-theme-symbolic", _("Fenêtres aux couleurs de Boomerang"),
              _("Barres d'en-tête framboise comme Cassette, colonne de gauche repliable en icônes "
                + "avec pastilles (Réglages › Affichage ou en glissant son bord), images de fond proposées et apparence par défaut dans "
                + "Réglages › Messages.") },
            { "window-new-symbolic", _("Messages dans le style d'elementary"),
              _("L'app Messages séparée a des barres d'en-tête elementary.") },
            { "system-users-symbolic", _("Contributeurs"),
              _("Une nouvelle page, sous Réglages, présente chaque projet sur lequel Boomerang "
                + "s'appuie : ses auteurs, ce qu'il apporte, sa licence et son lien.") },
            { "audio-headphones-symbolic", _("Répondre d'un geste de tête"),
              _("Expérimental : avec les AirPods, hochez la tête pour répondre à un appel, "
                + "secouez-la pour le refuser. À activer dans Réglages › Expérimental.") },
            { "video-display-symbolic", _("Recopie enregistrée"),
              _("Pendant la recopie, l'écran reste allumé, et la recopie peut être enregistrée en MP4 dans Vidéos. "
                + "Expérimental : une balise Bluetooth aide l'iPhone à trouver le PC.") },
            { "emblem-synchronizing-symbolic", _("Covalence devient Boomerang"),
              _("Nouveau nom, nouvelle icône : comme un boomerang, tout part de l'iPhone et y "
                + "revient. Vos réglages, messages et comptes iCloud sont repris tels quels.") },
            { "audio-input-microphone-symbolic", _("Micro rétabli"),
              _("Un micro coupé pendant un appel est toujours rétabli à la fin, même si Boomerang "
                + "s'arrête en cours d'appel : vos correspondants vous entendent de nouveau.") },
            { "system-software-install-symbolic", _("Agenda et Cassette à part"),
              _("Les deux applications ont leur propre dépôt et leurs versions ; Boomerang les "
                + "installe et affiche leur vraie version.") },
            { "x-office-calendar-symbolic", _("Agenda"),
              _("Installez Agenda depuis Services Apple pour afficher vos agendas iCloud par mois, "
                + "par semaine ou en fil. Boomerang vérifie le paquet puis l'installe en un clic.") },
            { "audio-x-generic-symbolic", _("Cassette"),
              _("Apple Music dans une fenêtre elementary, à installer depuis Services Apple : "
                + "lecture, volume, paroles et file d'attente dans la barre d'en-tête.") },
            { "edit-copy-symbolic", _("Codes SMS copiés"),
              _("Boomerang copie le code d'un SMS dans le presse-papiers dès sa réception. "
                + "Ce réglage se trouve dans Réglages › Codes SMS.") },
            { "audio-volume-muted-symbolic", _("Appels en silence"),
              _("Aucune sonnerie, aucune fenêtre et aucun son sur le PC : l'appel reste sur "
                + "l'iPhone. Utile quand Teams sonne déjà. Ce réglage se trouve dans Réglages › "
                + "Connexion et dans la barre du haut.") },
            { "applications-graphics-symbolic", _("Icônes redessinées"),
              _("Boomerang, Messages, Téléphone, Contacts, Lecture en cours et Recopie, dessinées "
                + "pour chaque taille. Les notifications du Calendrier prennent l'icône d'Agenda.") },
            { "audio-headphones-symbolic", _("AirPods Pro 3"),
              _("Contrôle du bruit, audio adaptatif et détection de conversation sont reconnus. "
                + "Les écouteurs que Boomerang ne connaît pas encore gardent toutes leurs commandes.") },
            { "security-high-symbolic", _("Sécurité renforcée"),
              _("Le code d'appairage se confirme aussi sur le PC. Un autre programme doit obtenir votre accord "
                + "avant d'appeler, d'envoyer ou d'appairer. Mises à jour, fichiers "
                + "LocalSend et recopie mieux protégés ; codes SMS liés à leur site.") },
            { "emblem-ok-symbolic", _("Messages fiables"),
              _("Plus de doublons après une reconnexion, les groupes restent groupés, chaque "
                + "iPhone a son propre historique et les contacts se rechargent avec « Réessayer ».") },
            { "bluetooth-active-symbolic", _("Appairage simplifié"),
              _("L'iPhone trouve ce PC dans Réglages › Bluetooth, sans app supplémentaire. La reconnexion "
                + "est plus stable et un bouton « Oublier » permet de repartir de zéro.") },
            { "video-display-symbolic", _("Recopie et contrôle"),
              _("La recopie d'écran devient une app, plus fluide. Expérimental : pilotez l'iPhone "
                + "avec la souris et le clavier du PC (guide dans l'app).") },
            { "audio-volume-high-symbolic", _("19 sons libres"),
              _("Onze sons de plus pour les notifications et les appels (Réglages › Sons).") },
            { "network-cellular-symbolic", _("Internet via l'iPhone"),
              _("Un bouton dans l'Aperçu utilise le partage de connexion de l'iPhone, en Bluetooth.") },
            { "phone-apple-iphone-symbolic", _("Barre du haut"),
              _("Batterie, lecture en cours, appel et messages non lus à côté de l'horloge. "
                + "Fermez puis rouvrez votre session pour l'afficher.") },
            { "system-search-symbolic", _("Recherche et épingles"),
              _("Ctrl+F cherche dans les messages. Épinglez une conversation ou marquez-la non lue "
                + "d'un clic droit.") },
            { "folder-download-symbolic", _("Fichiers, recopie et photos"),
              _("Échangez des fichiers avec l'app LocalSend, affichez l'écran de l'iPhone "
                + "(expérimental) et importez les photos par câble USB.") },
            { "folder-remote-symbolic", _("iCloud"),
              _("État de synchronisation d'iCloud Drive dans Fichiers, raccourcis vers Localiser, Notes "
                + "et Masquer mon adresse e-mail.") },
            { "system-lock-screen-symbolic", _("Verrouillage de proximité"),
              _("Le PC se verrouille quand l'iPhone s'éloigne (désactivé par défaut, "
                + "jamais de déverrouillage).") },
            { "preferences-system-symbolic", _("Réglages en onglets"),
              _("Connexion, Messages, Sons, Affichage, Mises à jour, Expérimental, À propos ; un clic suffit "
                + "pour écouter les sons libres de Boomerang.") },
            { "face-smile-symbolic", _("Emojis automatiques"),
              _("« :) » devient 🙂 pendant la saisie. La touche Retour arrière annule la conversion ; le réglage se trouve dans Réglages.") },
            { "object-select-symbolic", _("Messages envoyés"),
              _("Une petite coche apparaît sous un message dès que l'iPhone confirme son envoi.") },
            { "emoji-body-symbolic", _("Réactions"),
              _("Les réactions reçues s'affichent sur le bon message, sans doublon, et se cumulent. "
                + "Au survol d'un message : réagir, copier ou supprimer.") },
            { "dialog-password-symbolic", _("Codes SMS"),
              _("Un code reçu par SMS se copie depuis la notification. Expérimental : remplissage "
                + "dans Chrome, Chromium, Edge et Firefox (Réglages › Codes SMS).") },
            { "format-justify-fill-symbolic", _("Messages en entier"),
              _("« Tout lire » récupère la suite d'un message long non lu, à la demande "
                + "ou systématiquement selon le choix fait dans Réglages. Le message est "
                + "alors marqué comme lu sur l'iPhone.") },
            { "view-refresh-symbolic", _("Synchroniser"),
              _("Un bouton dans Messages recharge les messages, les contacts et le journal d'appels.") },
            { "audio-volume-high-symbolic", _("Sons"),
              _("Choisissez le son des messages, des notifications de l'iPhone et la sonnerie "
                + "des appels, dont 8 sons libres fournis avec Boomerang (Réglages › Sons).") },
            { "system-software-update-symbolic", _("Mises à jour"),
              _("Boomerang recherche les nouvelles versions ; la mise à jour s'installe depuis Réglages.") },
            { "applications-science-symbolic", _("Fonctionnalités expérimentales"),
              _("À essayer dans Réglages : historique étendu, marquer comme lu sur l'iPhone, "
                + "actions des notifications, favoris des contacts.") }
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
