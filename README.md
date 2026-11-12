<div align="center">

<img src="data/icons/io.github.melvincouwez.Boomerang.svg" width="128" alt="Icône de Boomerang">

# Boomerang

**Votre iPhone et votre compte Apple, chez eux sur elementary OS.**

[![Licence : GPL-3.0-or-later](https://img.shields.io/badge/licence-GPL--3.0--or--later-blue)](LICENSE)
![Version 2.0 alpha](https://img.shields.io/badge/version-2.0%20alpha-orange)
![elementary OS 8+](https://img.shields.io/badge/elementary%20OS-8%2B-64baff)

[Site](https://melvin-cwz.github.io/boomerang/fr/) ·
[Télécharger](https://github.com/Melvin-Cwz/boomerang/releases/latest) ·
[English](README.en.md)

<img src="docs/screenshots/fr/device.png" width="760" alt="Boomerang : aperçu de l'iPhone">

</div>

Boomerang intègre l'iPhone et iCloud à elementary OS : notifications, messages, appels,
contacts, AirPods, courriel, agendas, rappels, iCloud Drive et Photos. Boomerang fonctionne
entièrement sur votre ordinateur. L'iPhone communique avec l'ordinateur par Bluetooth, iCloud
par Internet, et aucune donnée ne transite par un serveur autre que ceux d'Apple.

*Boomerang s'appelait Covalence jusqu'à la version 0.6. La mise à jour vers Boomerang conserve
vos réglages, vos messages et vos comptes iCloud.*

> **Alpha.** La version 2.0 est un aperçu public. Son auteur l'utilise tous les
> jours sur son ordinateur, mais des anomalies restent possibles. L'interface est en français ;
> la traduction anglaise est en bêta.

Boomerang 2 garde un cœur fixe (Messages, Téléphone, Contacts, Notifications, Lecture en cours
et la page iPhone) et propose le reste en **modules** que vous ajoutez depuis l'app : AirPods,
son de l'iPhone, services iCloud, iCloud Drive et Photos, envoi de fichiers, partage de
connexion, verrouillage de proximité, recopie de l'écran, codes à usage unique. Un module
installe ses dépendances quand vous l'ajoutez, et s'arrête entièrement quand vous le retirez.

## Deux connexions

### Connexion iPhone (Bluetooth)

| | |
|---|---|
| **Notifications** | Toutes les notifications de l'iPhone sur le bureau, avec leurs actions et l'icône de l'app qui les envoie. Une notification effacée sur l'iPhone disparaît aussi du PC, même pendant une coupure, et une notification fermée sur le PC ne revient pas. Vous choisissez les apps dont les notifications s'affichent. |
| **Lecture en cours** | Ce que joue l'iPhone, avec pochette, progression et volume, dans sa page et dans un mini-lecteur au-dessus de Réglages. Le bouton Lecture relance la musique de l'iPhone, même lorsqu'elle est arrêtée. |
| **Batterie** | Niveau de batterie de l'iPhone dans le panneau, alertes à 20 % et à 10 %. |
| **Messages** | Lire vos conversations SMS, tout l'historique compris, répondre à un seul destinataire, enregistrer des brouillons, rechercher. Filtres Non lus et Inconnus, liens échangés dans les détails, raccourcis clavier façon Mac (Ctrl+? pour les voir), pièces jointes signalées. Un message supprimé sur l'iPhone disparaît de Boomerang ; une suppression faite dans Boomerang ne touche pas l'iPhone. |
| **Téléphone** | Répondre, refuser et passer des appels avec le micro et les haut-parleurs de l'ordinateur, double appel (mettre en attente et répondre, permuter, fusionner selon l'opérateur), choix de la sortie audio pendant l'appel, favoris, messagerie vocale, recherche et durée des appels dans les récents. Nécessite PipeWire 1.4 ou une version plus récente. |
| **Contacts** | Les contacts de l'iPhone en Bluetooth (lecture seule), ou vos contacts iCloud, modifiables. Fiches complètes (entreprise, adresses, anniversaire, sites, notes, photo), index alphabétique, export et import vCard. |
| **AirPods** | Batterie de chaque écouteur et du boîtier (aussi dans le panneau), alerte de batterie faible, contrôle du bruit, détection de conversation et du port, appui long par écouteur, volume par glissement sur la tige, renommage, d'après le protocole documenté par LibrePods. Expérimental : hocher la tête pour répondre à un appel, la secouer pour le refuser. |
| **Son de l'iPhone** | Recevoir sur l'ordinateur le son que l'iPhone envoie depuis le bouton AirPlay, ou refuser cette diffusion. |

<p align="center">
<img src="docs/screenshots/fr/messages.png" width="49%" alt="Messages">
<img src="docs/screenshots/nowplaying.png" width="49%" alt="Lecture en cours">
</p>

### Connexion Services Apple (Internet)

| | |
|---|---|
| **Courriel, agendas, rappels et contacts iCloud** | Evolution Data Server les ajoute aux apps Courriel, Tâches et agenda d'elementary. La connexion utilise un mot de passe pour app. |
| **iCloud Drive** | Un dossier dans Fichiers, grâce à [rclone](https://rclone.org). |
| **iCloud Photos** | Vos albums dans Fichiers, en lecture seule, grâce à rclone. |

<p align="center">
<img src="docs/screenshots/services.png" width="49%" alt="Services Apple">
<img src="docs/screenshots/headphones.png" width="49%" alt="AirPods">
</p>

> **À propos d'iCloud Drive et Photos.** rclone se connecte comme le site icloud.com, avec le
> mot de passe de votre compte Apple et la double authentification. Apple ne propose pas cet
> accès officiellement : ses conditions d'utilisation d'iCloud limitent l'accès automatisé et
> l'autorisent à suspendre un compte. Cette fonction demande aussi de désactiver la Protection
> avancée des données, ce qui réduit le chiffrement de bout en bout de vos données iCloud. Le jeton de
> connexion expire environ une fois par mois. Vous utilisez cette fonction à vos risques ;
> Boomerang vous demande d'accepter ces risques avant la connexion.

## Installation

### Depuis le paquet (conseillé)

1. Téléchargez le paquet `boomerang_…_amd64.deb` depuis la
   [dernière version](https://github.com/Melvin-Cwz/boomerang/releases/latest).
2. Installez-le dans un terminal, depuis le dossier du téléchargement :
   `sudo apt install ./boomerang_*_amd64.deb`. apt installe également les dépendances
   nécessaires. Sur Ubuntu, un double-clic sur le fichier l'ouvre aussi dans l'App Center.
3. Fermez puis rouvrez votre session (ou lancez `systemctl --user start boomerangd`), puis
   ouvrez Boomerang. L'assistant vous guide pour appairer l'iPhone et vous connecter à iCloud.

Si un composant manque par la suite, Boomerang le signale dans « Composants manquants » avec un
bouton « Installer » (PackageKit demande votre mot de passe). Pour iCloud Drive et Photos, le
bouton « Télécharger rclone » récupère la version officielle de rclone et vérifie son empreinte
SHA-256 (la commande `boomerangd --fetch-rclone` fait la même opération dans un terminal).

Désinstallation : `sudo apt remove boomerang`. Vos données restent dans
`~/.local/share/boomerang` et `~/.config/boomerang` tant que vous ne les supprimez pas (voir
[confidentialité](docs/confidentialite.md)).

### Compatibilité

| Système | État |
|---|---|
| elementary OS 9 | Tout fonctionne, avec Granite 9. Les appels demandent PipeWire 1.4 ou plus récent. |
| elementary OS 8 | Tout fonctionne, avec Granite 7. Avec un PipeWire antérieur à 1.4, Boomerang désactive les appels et en indique la raison. |
| Ubuntu 24.04 ou plus récent | Le paquet demande Granite 7.7 ou plus récent. Les appels demandent PipeWire 1.4 ou plus récent. Ubuntu 24.04 fournit rclone 1.60, trop ancien pour iCloud : utilisez le bouton « Télécharger rclone ». |

Matériel : un adaptateur Bluetooth compatible Bluetooth Low Energy (c'est le cas de presque
tous les modèles récents).

### Depuis les sources

```sh
meson setup build --prefix=$HOME/.local
ninja -C build && meson install -C build
systemctl --user daemon-reload && systemctl --user enable --now boomerangd
```

Dépendances de construction : `valac`, `meson`, `libgranite-9-dev` (ou `libgranite-7-dev` 7.7
ou plus récent, utilisé si Granite 9 est absent), `libgtk-4-dev`. Les dépendances d'exécution
sont listées dans `debian/control`. Tests hors ligne (démon et interface) :
`meson test -C build`. Paquet : `packaging/build-deb.sh`.

## Ce que Boomerang ne sait pas faire

Ces limites viennent surtout de ce qu'un iPhone accepte d'un ordinateur non Apple :

- Pas d'envoi d'iMessage, pas de réponse dans les groupes, pas de pièces jointes : par Bluetooth,
  l'iPhone permet seulement d'envoyer un SMS à une seule personne.
- Pas de presse-papiers universel, de Handoff, d'AirDrop ni de Caméra de continuité : ces
  fonctions exigent le chiffrement et la pile Wi-Fi propres à Apple.
- Supprimer un message dans Boomerang ne le retire pas de l'iPhone : iOS ignore les
  suppressions demandées par Bluetooth.
- Pas de FaceTime ni de messagerie vocale visuelle, pas de modification des favoris de
  l'iPhone, pas de mise en attente d'un appel seul (le profil mains libres de PipeWire ne
  le propose pas).
- L'iPhone ne rouvre pas toujours seul la connexion Bluetooth LE. Boomerang passe alors par la
  liaison classique ; si les notifications restent interrompues, « Appairer à nouveau » guide
  une réparation propre (voir le [guide](data/guide/fr/12-troubleshooting.md)).
- Le déverrouillage de l'ordinateur avec l'iPhone est volontairement exclu : la force du signal
  Bluetooth peut être falsifiée.

## Nouveautés de la 2.0

- Liaison : état explicite dans la barre d'en-tête, reconnexion plus rapide et plus économe,
  service d'arrière-plan surveillé (watchdog) qui tient bon quand le Bluetooth est occupé ou
  que le cache des messages est abîmé.
- Notifications fiables après une veille ou un redémarrage, sans fantômes ni doublons ;
  réparation guidée quand elles s'arrêtent.
- Messages : historique complet par pages, filtres, raccourcis, liens échangés, pièces jointes
  signalées, menus accessibles au clavier, suppressions faites sur l'iPhone reportées.
- Téléphone : double appel, sortie audio pendant l'appel, favoris, messagerie vocale, durées.
- Contacts : fiches complètes, éditeur iCloud avec photo, index alphabétique, vCard.
- AirPods et Recopie : alertes de batterie, réglages des tiges, touches et gestes de l'iPhone
  depuis la recopie, capture d'écran, dépôt de fichiers vers LocalSend.
- Modules ajoutés à la demande autour d'un cœur fixe.
- elementary OS 9 : construit avec Granite 9 (repli sur Granite 7 pour elementary OS 8).

## Aide

Boomerang contient un guide intégré, en français et en anglais (F1, ou Guide dans la barre latérale). Il
explique l'appairage, les réglages à activer sur l'iPhone, iCloud, les AirPods et le
dépannage. Questions et signalements :
[Issues](https://github.com/Melvin-Cwz/boomerang/issues).

## Auteur

Je ne suis pas développeur. Je suis un passionné d'elementary OS, utilisateur d'iPhone, avec
quelques idées, et je construis Boomerang en « vibe coding » avec Claude, l'assistant
d'Anthropic : je décris ce que je veux, je teste chaque jour sur mon propre ordinateur, et
nous corrigeons ensemble. Le code est ouvert pour que les personnes qui s'y connaissent mieux
puissent le lire, signaler les erreurs et aider. Contributions, signalements et conseils
bienveillants sont les bienvenus.

MelvinCwz

## Fonctionnement

- **boomerangd**, le service (Python, PyGObject) : il maintient la liaison Bluetooth et
  conserve les secrets. Il communique avec l'iPhone par BlueZ (ANCS et AMS en Bluetooth LE, MAP et PBAP par obexd,
  HFP par `org.pipewire.Telephony` de PipeWire), à iCloud par Evolution Data Server et
  libsecret, et lance rclone pour Drive et Photos.
- **L'application** (Vala, GTK 4, Granite) : une seule appli (Messages, Téléphone,
  Contacts, etc. en sont des pages), plus Écouteurs et Recopie en apps séparées. Elle communique avec le service par D-Bus
  (`io.github.melvincouwez.Boomerang.Daemon`).
- Les journaux ne contiennent jamais le texte des notifications ou des messages, ni les noms ni
  les numéros.

## Merci

Boomerang repose sur le travail de nombreux logiciels libres. La page **Contributeurs** de l'app, sous Réglages, les présente tous avec leurs auteurs, leurs licences et leurs liens :

| Projet | Sert à | Licence |
|---|---|---|
| [rclone](https://github.com/rclone/rclone) (Nick Craig-Wood et contributeurs) | iCloud Drive et Photos | MIT |
| [LibrePods](https://github.com/librepods-org/librepods) (Kavish Devar et contributeurs) | Protocole des AirPods et gestes de tête, portés en Python dans `boomerangd/headphones.py` | GPL-3.0-or-later |
| [BlueZ](https://github.com/bluez/bluez) et obexd | Bluetooth, messages et contacts | GPL-2.0-or-later (bibliothèques LGPL-2.1-or-later) |
| [PipeWire](https://gitlab.freedesktop.org/pipewire/pipewire) et [WirePlumber](https://gitlab.freedesktop.org/pipewire/wireplumber) | Appels et son de l'iPhone | MIT |
| [Evolution Data Server](https://gitlab.gnome.org/GNOME/evolution-data-server) | Comptes iCloud | LGPL |
| [libsecret](https://gitlab.gnome.org/GNOME/libsecret) | Mots de passe dans le trousseau | LGPL-2.1-or-later |
| [GTK](https://gitlab.gnome.org/GNOME/gtk), [Granite](https://github.com/elementary/granite), [Vala](https://gitlab.gnome.org/GNOME/vala), [PyGObject](https://gitlab.gnome.org/GNOME/pygobject) | L'application et le service | LGPL (Granite : LGPL-3.0-or-later) |
| [LocalSend](https://github.com/localsend/protocol) | Fichiers avec l'iPhone, protocole v2 | protocole public |
| [UxPlay](https://github.com/FDH2/UxPlay) | Recopie de l'écran, son enregistrement et sa balise Bluetooth (lancé par Boomerang, facultatif) | GPL-3.0 |
| [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) et [ifuse](https://github.com/libimobiledevice/ifuse) | Import des photos par câble USB (facultatif) | LGPL-2.1-or-later |
| [libheif](https://github.com/strukturag/libheif) | Photos HEIC converties en JPEG (facultatif) | LGPL-3.0 |
| [Icônes elementary](https://github.com/elementary/icons) | Objets à partir desquels les icônes de Boomerang sont dessinées | GPL-3.0 |
| [Inter](https://github.com/rsms/inter) (Rasmus Andersson) | Texte de l'icône Calendrier, en contours | SIL OFL 1.1 |
| Android Open Source Project et [Kenney](https://kenney.nl/assets/interface-sounds) | Sons des notifications (détail dans [docs/credits-sons.md](docs/credits-sons.md)) | Apache-2.0 / CC0 |

Boomerang installe deux applications compagnes depuis l'onglet Services Apple, chacune publiée
dans son propre dépôt avec ses versions : **Agenda**
([code source et téléchargements](https://github.com/Melvin-Cwz/agenda), GPL-3.0-or-later) et **Cassette**,
un client Apple Music issu de [Sidra](https://github.com/wimpysworld/sidra), de Martin Wimpress,
et construit sur [CastLabs Electron](https://github.com/castlabs/electron-releases)
([code source et téléchargements](https://github.com/Melvin-Cwz/cassette), Blue Oak Model License 1.0.0).

Un merci particulier à l'équipe de LibrePods pour son remarquable travail de rétro-ingénierie,
et à [nRF Connect](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile)
(Nordic Semiconductor), une app iPhone gratuite qui a servi aux premiers appairages et peut encore servir au besoin.

## Mentions légales

Boomerang est un logiciel libre sous [licence GNU GPL version 3 ou ultérieure](LICENSE). Il est
fourni sans aucune garantie.

Boomerang est un projet indépendant. Il n'est ni affilié à Apple Inc. ou à elementary, Inc., ni
approuvé, sponsorisé ou soutenu par eux. Apple, iPhone, iCloud, iMessage, AirPods, AirPlay et
Apple Music sont des marques d'Apple Inc., déposées aux États-Unis et dans d'autres pays et
régions. Ces noms sont cités uniquement pour indiquer les produits et services avec lesquels Boomerang
fonctionne.

Boomerang utilise des protocoles publiés (Bluetooth HFP, MAP, PBAP ; ANCS et AMS, spécifiés par
Apple ; CalDAV, CardDAV, IMAP). Deux fonctions reposent sur des interfaces non documentées : les
AirPods (protocole AAP décrit par LibrePods) et iCloud Drive et Photos (via rclone). Elles
peuvent cesser de fonctionner sans préavis. Boomerang n'a décompilé aucun logiciel Apple.

- Confidentialité : [français](docs/confidentialite.md) · [English](docs/privacy.md). Pas de
  télémétrie, pas de compte, pas de serveur.
- Mentions légales : [docs/mentions-legales.md](docs/mentions-legales.md).
