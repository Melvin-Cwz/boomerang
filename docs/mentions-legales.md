# Mentions légales

## Licence

Boomerang est un logiciel libre : vous pouvez le redistribuer et le modifier selon les termes de la
**GNU General Public License**, version 3 ou (à votre choix) toute version ultérieure, publiée par
la Free Software Foundation. Le texte complet est dans le fichier `LICENSE`.

Ce logiciel est distribué dans l'espoir qu'il sera utile, mais **sans aucune garantie**, sans même la
garantie implicite de qualité marchande ou d'adéquation à un usage particulier.

Identifiant SPDX : `GPL-3.0-or-later`. Copyright © 2026 MelvinCwz et les contributeurs de Boomerang.

## Indépendance

Boomerang est un projet indépendant. Il **n'est ni affilié à Apple Inc., ni approuvé, sponsorisé ou
soutenu par Apple Inc.**, ni par elementary, Inc.

## Marques

Apple, iPhone, iPad, iCloud, iCloud Drive, iMessage, Apple Music, AirPods, FaceTime et le logo Apple sont
des marques d'Apple Inc., déposées aux États-Unis et dans d'autres pays et régions.
elementary est une marque d'elementary, Inc.

Ces noms sont employés uniquement pour indiquer avec quels produits et services Boomerang est
compatible (usage descriptif). Boomerang n'utilise aucun logo, icône, son ni police d'Apple ; son nom et ses icônes sont propres au
projet (certaines reprennent des objets du thème d'icônes d'elementary, sous GPL-3.0). Conformément aux règles de marque d'elementary, le nom « elementary »
n'apparaît pas dans le nom de l'application.

## Fonctionnement et données

- Boomerang utilise des protocoles publiés : Bluetooth HFP, MAP et PBAP ; ANCS et AMS, spécifiés
  par Apple pour les accessoires ; CalDAV, CardDAV et IMAP avec iCloud.
- Deux fonctions reposent sur des interfaces non documentées et peuvent cesser de fonctionner sans
  préavis : les écouteurs (protocole AAP décrit par LibrePods, voir plus bas) et iCloud Drive et
  iCloud Photos, atteints par [rclone](https://rclone.org) comme le site icloud.com, avec le mot de
  passe du compte Apple saisi par l'utilisateur. Les conditions d'utilisation d'iCloud limitent
  l'accès automatisé au service et permettent à Apple de suspendre un compte ; cette fonction
  demande aussi de désactiver la Protection avancée des données. L'utilisateur l'active à ses
  risques, après un avertissement explicite dans l'application.
- rclone n'est pas distribué avec Boomerang : l'application utilise le rclone du système s'il est
  assez récent, sinon elle propose de télécharger, à la demande de l'utilisateur, le binaire
  officiel publié sur <https://downloads.rclone.org> (licence MIT, © Nick Craig-Wood et les
  contributeurs de rclone), dont l'empreinte SHA-256 est vérifiée.
- Aucune donnée ne transite par un serveur de Boomerang : il n'y en a pas. Les échanges se font
  directement entre l'ordinateur, l'iPhone et les serveurs d'Apple.
- Les messages, contacts et photos mis en cache restent sur l'ordinateur, dans des fichiers
  lisibles par le seul compte de l'utilisateur. Les secrets sont conservés dans le trousseau de la
  session (libsecret).
- L'utilisation des services iCloud reste soumise aux conditions générales d'Apple, que
  l'utilisateur a acceptées auprès d'Apple.

## Écouteurs (AirPods)

La gestion des AirPods (batterie, détection d'oreille, contrôle du bruit, détection de conversation,
nom) suit le protocole décrit par **LibrePods** (<https://github.com/librepods-org/librepods>,
licence GPL-3.0-or-later), projet créé par **Kavish Devar** et enrichi par ses nombreux
contributeurs. Le module `boomerangd/headphones.py` reprend la séquence de connexion et le format des
paquets de sa documentation (`docs/AAP Definitions.md`, `docs/control_commands.md`) et de son
implémentation Linux (`linux/airpods_packets.h`, `linux/main.cpp`), réécrits en Python. Les deux
projets partagent la même licence. Un grand merci à Kavish Devar et à tous les contributeurs de
LibrePods pour ce travail remarquable, sans lequel cette fonction n'existerait pas.

Boomerang n'est affilié ni à LibrePods ni à Apple. « AirPods » et « Apple » sont des marques
d'Apple Inc. ; ces noms indiquent seulement avec quels écouteurs Boomerang fonctionne, et Boomerang ne
reprend aucun logo, dessin ni code d'Apple.

L'étude d'un protocole pour permettre l'interopérabilité d'un logiciel créé indépendamment est
permise dans l'Union européenne (directive 2009/24/CE, articles 5 et 6 ; en France, article
L.122-6-1 III et IV du Code de la propriété intellectuelle). Boomerang n'a décompilé aucun logiciel
Apple : il s'appuie sur la description publiée par LibrePods.

Boomerang n'utilise que la liaison Bluetooth ordinaire des écouteurs : il ne se fait pas passer pour
un appareil Apple. Les fonctions qui l'exigeraient (multipoint, réduction des sons forts) ne sont
pas proposées.

## Confidentialité

Voir [confidentialite.md](confidentialite.md) ([privacy.md](privacy.md) en anglais).

## Projets utilisés

En dehors de la logique de protocole reprise de LibrePods (voir ci-dessus), Boomerang ne reprend le
code d'aucun projet tiers. Il s'appuie sur les projets suivants, chacun sous sa propre licence.
Merci à leurs auteurs.

| Projet | Rôle dans Boomerang | Licence | Dépôt |
|---|---|---|---|
| LibrePods (Kavish Devar et contributeurs) | Protocole des écouteurs AirPods, réécrit en Python | GPL-3.0-or-later | <https://github.com/librepods-org/librepods> |
| rclone (Nick Craig-Wood et contributeurs) | iCloud Drive et iCloud Photos, téléchargé à la demande | MIT | <https://github.com/rclone/rclone> |
| BlueZ, obexd | Bluetooth, messages et contacts | GPL-2.0-or-later (bibliothèques LGPL-2.1-or-later) | <https://github.com/bluez/bluez> |
| PipeWire | Audio et téléphonie mains libres | MIT | <https://gitlab.freedesktop.org/pipewire/pipewire> |
| WirePlumber | Gestion des périphériques audio | MIT | <https://gitlab.freedesktop.org/pipewire/wireplumber> |
| Evolution Data Server | Comptes iCloud : courriel, agendas, contacts | LGPL | <https://gitlab.gnome.org/GNOME/evolution-data-server> |
| libsecret | Trousseau | LGPL-2.1-or-later | <https://gitlab.gnome.org/GNOME/libsecret> |
| GTK 4 | Interface | LGPL-2.1-or-later | <https://gitlab.gnome.org/GNOME/gtk> |
| Granite 7 | Interface elementary | LGPL-3.0-or-later | <https://github.com/elementary/granite> |
| elementary icons (elementary, Inc.) | Écran et téléphone de l'icône de Boomerang | GPL-3.0 | <https://github.com/elementary/icons> |
| Vala | Langage de l'application | LGPL-2.1-or-later | <https://gitlab.gnome.org/GNOME/vala> |
| PyGObject | Service en Python | LGPL-2.1-or-later | <https://gitlab.gnome.org/GNOME/pygobject> |
| UxPlay | Recopie de l'écran, lancé par Boomerang s'il est installé | GPL-3.0 | <https://github.com/FDH2/UxPlay> |
| libimobiledevice, ifuse | Import des photos par câble USB (facultatif) | LGPL-2.1-or-later | <https://github.com/libimobiledevice/libimobiledevice> |
| libheif | Conversion des photos HEIC (facultatif) | LGPL-3.0 | <https://github.com/strukturag/libheif> |
| LocalSend (protocole v2) | Échange de fichiers avec l'iPhone | protocole publié | <https://github.com/localsend/protocol> |
| Inter (Rasmus Andersson) | Texte de l'icône Calendrier, converti en contours | SIL OFL 1.1 | <https://github.com/rsms/inter> |
| Sons de l'Android Open Source Project et de Kenney | Sons de notification et sonneries, détail dans [credits-sons.md](credits-sons.md) | Apache-2.0, CC0 1.0 | <https://android.googlesource.com/platform/frameworks/base/+/main/data/sounds> |

Outil conseillé, sans lien avec Boomerang : l'application gratuite **nRF Connect for Mobile** de
Nordic Semiconductor peut servir en dernier recours à ouvrir la liaison Bluetooth depuis l'iPhone.
Ce n'est pas une dépendance de Boomerang.

Les licences de ce tableau sont indiquées d'après les projets eux-mêmes ; en cas de doute, le
fichier de licence du projet concerné fait foi.
