// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * "Contributeurs" page: every project, library, protocol and asset Boomerang
 * uses or builds on, grouped by use, with its authors, what it brings, its
 * license and a link. Authors and licenses are the ones stated by each project
 * (its LICENSE file or the Debian copyright file of its package).
 */

public class Boomerang.ContributorsView : Gtk.Box {
    // Group, name, authors, what it brings, license, link.
    private const string[] ENTRIES = {
        N_("iPhone et Bluetooth"), "BlueZ, obexd", N_("Projet BlueZ"),
        N_("La pile Bluetooth de Linux. La liaison avec l'iPhone, les notifications, les messages et les contacts passent par elle."),
        N_("GPL-2.0-or-later, bibliothèques LGPL-2.1-or-later"), "https://github.com/bluez/bluez",

        N_("iPhone et Bluetooth"), "LibrePods", N_("Kavish Devar et contributeurs"),
        N_("Ont décrit le protocole des AirPods (batterie, réduction du bruit, port, gestes de tête). Boomerang en a réécrit une partie en Python."),
        "GPL-3.0-or-later", "https://github.com/librepods-org/librepods",

        N_("iPhone et Bluetooth"), "LocalSend", N_("Équipe LocalSend"),
        N_("Le protocole v2 que Boomerang reprend pour échanger des fichiers avec l'iPhone."),
        N_("Protocole public ; application Apache-2.0"), "https://github.com/localsend/protocol",

        N_("iPhone et Bluetooth"), "UxPlay", N_("F. Duncanh, Florian Draschbacher et contributeurs"),
        N_("Le récepteur AirPlay de la recopie d'écran, et sa balise Bluetooth."),
        "GPL-3.0-or-later", "https://github.com/FDH2/UxPlay",

        N_("iPhone et Bluetooth"), "Avahi", N_("Projet Avahi"),
        N_("Annonce l'ordinateur sur le réseau local, pour que l'iPhone le trouve pendant la recopie."),
        "LGPL-2.1-or-later", "https://github.com/avahi/avahi",

        N_("iPhone et Bluetooth"), "libimobiledevice, ifuse", N_("Projet libimobiledevice"),
        N_("L'import des photos de l'iPhone par câble USB."),
        "LGPL-2.1-or-later", "https://github.com/libimobiledevice/libimobiledevice",

        N_("iPhone et Bluetooth"), "nRF Connect", "Nordic Semiconductor",
        N_("Une app iPhone gratuite qui a servi aux premiers appairages, au début du développement de Boomerang."),
        N_("Application gratuite, non libre"),
        "https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile",

        N_("iCloud"), "rclone", N_("Nick Craig-Wood et contributeurs"),
        N_("iCloud Drive et vos photos iCloud dans Fichiers."),
        "MIT", "https://github.com/rclone/rclone",

        N_("iCloud"), "Evolution Data Server", N_("Projet GNOME"),
        N_("Le courriel, les agendas, les rappels et les contacts iCloud dans les apps d'elementary."),
        "LGPL-2.0-or-later", "https://gitlab.gnome.org/GNOME/evolution-data-server",

        N_("iCloud"), "libsecret", N_("Projet GNOME"),
        N_("Garde les mots de passe dans le trousseau du système, jamais dans un fichier."),
        "LGPL-2.1-or-later", "https://gitlab.gnome.org/GNOME/libsecret",

        N_("iCloud"), "libcloudproviders", N_("Projet GNOME"),
        N_("La méthode standard pour afficher l'état de synchronisation d'iCloud Drive dans Fichiers."),
        "LGPL-3.0-or-later", "https://gitlab.gnome.org/GNOME/libcloudproviders",

        N_("iCloud"), "FUSE (libfuse)", N_("Projet libfuse"),
        N_("Monte iCloud Drive et Photos comme des dossiers."),
        N_("LGPL-2.1, outils GPL-2.0"), "https://github.com/libfuse/libfuse",

        N_("Son et appels"), "PipeWire", N_("Projet PipeWire"),
        N_("Le son des appels et de l'iPhone sur l'ordinateur."),
        N_("MIT, certaines parties LGPL-2.1-or-later"), "https://gitlab.freedesktop.org/pipewire/pipewire",

        N_("Son et appels"), "WirePlumber", N_("Projet PipeWire"),
        N_("Connecte l'iPhone, le micro et les haut-parleurs au moment voulu."),
        "MIT", "https://gitlab.freedesktop.org/pipewire/wireplumber",

        N_("Interface"), "GTK", N_("Projet GTK"),
        N_("La boîte à outils de toutes les fenêtres de Boomerang."),
        "LGPL-2.1-or-later", "https://gitlab.gnome.org/GNOME/gtk",

        N_("Interface"), "Granite", "elementary",
        N_("Les éléments d'interface d'elementary OS, pour que Boomerang s'intègre au bureau."),
        "LGPL-3.0-or-later", "https://github.com/elementary/granite",

        N_("Interface"), N_("Icônes elementary"), "elementary",
        N_("Les éléments graphiques qui composent les icônes de Boomerang."),
        "GPL-3.0", "https://github.com/elementary/icons",

        N_("Interface"), "Inter", "Rasmus Andersson",
        N_("La police du texte de l'icône Calendrier, convertie en tracés."),
        "SIL OFL 1.1", "https://github.com/rsms/inter",

        N_("Interface"), "libheif", N_("Dirk Farin, struktur AG et contributeurs"),
        N_("Convertit les photos HEIC de l'iPhone en JPEG."),
        N_("LGPL-3.0-or-later, outil heif-convert MIT"), "https://github.com/strukturag/libheif",

        N_("Sons"), "Android Open Source Project", "The Android Open Source Project",
        N_("Quatorze sons de messages et sonneries (Rosée, Envol, Aurore…)."),
        "Apache-2.0", "https://android.googlesource.com/platform/frameworks/base/+/main/data/sounds",

        N_("Sons"), "Kenney", "Kenney",
        N_("Cinq sons de notification (Carillon, Cristal, Pop, Bulle, Givre)."),
        "CC0 1.0", "https://kenney.nl/assets/interface-sounds",

        N_("Protocoles publiés"), N_("Bluetooth HFP, MAP, PBAP, HID"), "Bluetooth SIG",
        N_("Les profils standard qui font de l'ordinateur un accessoire de l'iPhone : appels, messages, contacts, contrôle."),
        N_("Spécifications publiques"), "https://www.bluetooth.com/specifications/specs/",

        N_("Protocoles publiés"), "ANCS, AMS", "Apple",
        N_("Les services Bluetooth documentés par Apple pour les notifications et la musique de l'iPhone."),
        N_("Spécifications publiques"),
        "https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Introduction/Introduction.html",

        N_("Protocoles publiés"), "CalDAV, CardDAV, IMAP", "IETF",
        N_("Les normes ouvertes par lesquelles passent les agendas, les contacts et le courriel iCloud."),
        N_("Normes ouvertes (RFC)"), "https://www.rfc-editor.org/",

        N_("Outils"), "Python", "Python Software Foundation",
        N_("Le langage du démon de Boomerang."),
        "PSF License", "https://www.python.org/",

        N_("Outils"), "PyGObject", N_("Projet GNOME"),
        N_("Relie le démon en Python à GLib et D-Bus."),
        "LGPL-2.1-or-later", "https://gitlab.gnome.org/GNOME/pygobject",

        N_("Outils"), "Vala", N_("Projet GNOME"),
        N_("Le langage de l'app et de l'indicateur."),
        "LGPL-2.1-or-later", "https://gitlab.gnome.org/GNOME/vala",

        N_("Outils"), "Meson", N_("Projet Meson"),
        N_("Construit Boomerang à partir de ses sources."),
        "Apache-2.0", "https://github.com/mesonbuild/meson",

        N_("Outils"), "SQLite", N_("Projet SQLite"),
        N_("Le cache des messages, sur votre ordinateur."),
        N_("Domaine public"), "https://www.sqlite.org/",

        N_("Outils"), "OpenSSL", N_("Projet OpenSSL"),
        N_("Le certificat qui chiffre les échanges de fichiers avec l'iPhone."),
        "Apache-2.0", "https://www.openssl.org/",

        N_("Outils"), "GnuPG", N_("Projet GnuPG"),
        N_("Vérifie la signature de rclone avant de l'installer."),
        "GPL-3.0-or-later", "https://gnupg.org/",

        N_("Outils"), "dconf", N_("Projet GNOME"),
        N_("Reprend vos réglages lors des changements de nom de l'app."),
        "LGPL-2.0-or-later", "https://gitlab.gnome.org/GNOME/dconf",

        N_("Applications compagnes"), "Sidra", "Martin Wimpress",
        N_("Le client Apple Music dont Cassette est issue."),
        "BlueOak-1.0.0", "https://github.com/wimpysworld/sidra",

        N_("Applications compagnes"), "CastLabs Electron", "castLabs",
        N_("Le moteur de Cassette, avec la lecture des contenus protégés."),
        "MIT", "https://github.com/castlabs/electron-releases"
    };
    private const int FIELDS = 6;

    construct {
        orientation = Gtk.Orientation.VERTICAL;

        var image = new Gtk.Image.from_icon_name ("system-users") { pixel_size = 64 };
        var title = new Gtk.Label (_("Contributeurs")) { xalign = 0 };
        title.add_css_class (Granite.HeaderLabel.Size.H1.to_string ());
        var intro = new Gtk.Label (
            _("Boomerang n'existerait pas sans eux. Chaque projet ci-dessous a été écrit, documenté "
              + "et partagé par d'autres, souvent bénévolement. Boomerang s'appuie sur leur travail ; "
              + "merci à toutes celles et ceux qui le rendent possible.")
        ) { xalign = 0, wrap = true };
        intro.add_css_class (Granite.CssClass.DIM);
        var titles = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) { valign = Gtk.Align.CENTER, hexpand = true };
        titles.append (title);
        titles.append (intro);
        var head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16) { margin_bottom = 6 };
        head.append (image);
        head.append (titles);

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 18,
            margin_bottom = 24,
            margin_start = 24,
            margin_end = 24,
            width_request = 560,
            halign = Gtk.Align.CENTER
        };
        content.append (head);

        string group = "";
        Gtk.ListBox? list = null;
        for (int i = 0; i + FIELDS <= ENTRIES.length; i += FIELDS) {
            if (ENTRIES[i] != group) {
                group = ENTRIES[i];
                content.append (new Granite.HeaderLabel (_(group)));
                list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
                list.add_css_class (Granite.CssClass.CARD);
                content.append (list);
            }
            list.append (entry_row (_(ENTRIES[i + 1]), _(ENTRIES[i + 2]), _(ENTRIES[i + 3]),
                                    _(ENTRIES[i + 4]), ENTRIES[i + 5]));
        }

        var note = new Gtk.Label (
            _("Boomerang n'est affilié à aucun de ces projets. Les licences indiquées sont celles que "
              + "chaque projet publie. Un oubli ou une erreur ? Signalez-le sur la page du code source.")
        ) { xalign = 0, wrap = true, margin_top = 6 };
        note.add_css_class (Granite.CssClass.DIM);
        note.add_css_class (Granite.CssClass.SMALL);
        content.append (note);

        append (new Gtk.ScrolledWindow () {
            child = content,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        });
    }

    private Gtk.Widget entry_row (string name, string authors, string role, string license, string url) {
        var name_label = new Gtk.Label ("<b>%s</b>".printf (Markup.escape_text (name))) {
            xalign = 0, wrap = true, use_markup = true
        };
        var authors_label = new Gtk.Label (authors) { xalign = 0, wrap = true };
        authors_label.add_css_class (Granite.CssClass.DIM);
        var role_label = new Gtk.Label (role) { xalign = 0, wrap = true };
        var license_label = new Gtk.Label (license) { xalign = 0, wrap = true };
        license_label.add_css_class (Granite.CssClass.DIM);
        license_label.add_css_class (Granite.CssClass.SMALL);

        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (name_label);
        text.append (authors_label);
        text.append (role_label);
        text.append (license_label);

        var link = new Gtk.Button.from_icon_name ("web-browser-symbolic") {
            valign = Gtk.Align.CENTER,
            tooltip_text = url
        };
        link.add_css_class ("flat");
        link.update_property (Gtk.AccessibleProperty.LABEL, _("Ouvrir la page de %s").printf (name), -1);
        link.clicked.connect (() => {
            new Gtk.UriLauncher (url).launch.begin (get_root () as Gtk.Window, null);
        });

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };
        box.append (text);
        box.append (link);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }
}
