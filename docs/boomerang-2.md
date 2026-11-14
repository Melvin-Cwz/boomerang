# Boomerang 2.0 · feuille de route

Branche `boomerang-2`. On avance par étapes, chaque étape laisse Boomerang utilisable.
Version en cours : 2.0.0~beta2. Tests : `meson test -C <dossier de build>` (interface en Vala et démon en Python).
Captures hors écran : `tools/snapshots.sh` (démon de démo, Broadway). Démon depuis les sources : `tools/dev-daemon.sh` (`stop` pour revenir au démon installé).

## Étape 1 : liaison

- [x] État de liaison explicite (`LinkState` sur D-Bus) : `off`, `unpaired`, `bond-lost`, `absent`, `seen`, `classic`, `complete`.
- [x] Présence : moniteur d'annonces Apple (BlueZ `AdvertisementMonitorManager1`, filtré par la puce). Actif seulement quand l'iPhone est absent. Demande `Experimental = true` dans `/etc/bluetooth/main.conf`, sinon retour au délai progressif seul.
- [x] Constat du 2026-10-16 : les adresses des annonces de l'iPhone ne se résolvent pas avec l'IRK du bond (11 adresses testées, calcul `ah()` validé sur le vecteur de la spec). Un appareil Apple capté au-dessus de -75 dBm (même pièce) sert donc d'indice : un essai de reconnexion, au plus un par minute.
- [x] Essai réel, déconnexion côté PC avec l'iPhone à côté : 1,7 s au lieu de 9,4 s.
- [ ] Essai après une longue absence (délai progressif à 5 min) et au retour de veille.
- [x] Fenêtre et indicateur lisent `LinkState` (`src/LinkText.vala`, mêmes mots partout).
- [x] Diagnostic : la fenêtre surgissante de l'en-tête dit ce qui se passe et propose l'action utile (appairer, reconnecter, réglages Bluetooth).

## Étape 2 : démarrage et surveillance

- [x] `WatchdogSec=30` : le démon ping systemd depuis sa boucle principale ; un démon figé (essai SIGSTOP) est tué et relancé en 24 s.
- [x] L'interface n'est pas résidente (déjà le cas en 0.8 : activée par D-Bus, l'indicateur parle au démon).

## Étape 3 : cœur réduit et modules à la demande

- [x] Catalogue dans le démon (`boomerangd/catalog.py`, propriété `Catalog`, méthode `SetModuleAdded`). Un module retiré arrête son travail de fond (LocalSend, surveillance des codes par courriel, iCloud, fournisseur Drive).
- [x] Migration : à la première exécution, les modules déjà utilisés restent ajoutés.
- [x] Page « Ajouter des modules… » avec installation des paquets par PackageKit.
- [x] Paquets iCloud passés en Recommends ; le démon démarre sans eux.
- [x] Colonne : Messages, Téléphone, Contacts, Notifications, Lecture en cours, iPhone, puis les modules ajoutés. Réglages, guide et À propos dans le menu de l'en-tête.
- [x] Une seule appli (`io.github.melvincouwez.Boomerang`) remplace Messages, Téléphone et Contacts : un lanceur, une pastille de Dock (non lus + appels manqués), notifications sous l'identifiant principal. Écouteurs et Recopie restent séparées.
- [x] Téléphone › Récents : filtre Tous / Manqués.
- [x] AirPods : le suivi BlueZ s'arrête quand le module est retiré.
- [x] Mettre à jour le guide intégré et le README pour la 2.0.

## Étape 4 : démon natif (reportée)

- [ ] Réécriture du démon en Vala, module par module, derrière la même interface D-Bus.
  Reportée après l'audit du 2026-11-02 : aucun défaut grave relevé ne tenait au langage, le gain
  serait d'environ 20 Mo de mémoire pour un fort risque sur la liaison. À reconsidérer seulement
  pour `link.py`, `att.py` et `ancs.py` si la mémoire devient un sujet.

## Étape 5 : audit du 2026-11-02 (rapport : `.impeccable/audit-2026-11/rapport.html`)

- [x] Lot 1, liaison : repli ATT classique tenté sans services LE résolus, « InProgress » sans
  allonger le délai, `Disconnect()` si BlueZ reste bloqué, échecs HFP à part, cache des messages
  endommagé mis de côté (WAL), sonde des composants et `Notify` hors de la boucle.
- [x] Notifications : mémoire ANCS entre reconnexions, tri après une coupure, pas de réaffichage
  d'une notification fermée, « Appairer à nouveau » qui répare vraiment (2.0.0~alpha3).
- [x] Lot 2, Granite 9 avec repli Granite 7 : `Style.colors ()`, pastilles et cadres propres.
- [x] Lot 3, Messages : bulles libérées, historique par pages, images d'aperçu hors fil
  principal, menus au clavier, suppressions de l'iPhone reportées, filtres, raccourcis, liens,
  pièces jointes signalées, glisser-déposer.
- [x] Lot 4, AirPods et Recopie : alertes de batterie, réglages des tiges (octets à confirmer sur
  un vrai modèle), touches et gestes HID, capture, dépôt LocalSend, pointeur qui suit l'image.
- [x] Lot 5, Téléphone : double appel, sortie audio pendant l'appel, favoris, messagerie vocale,
  recherche et durées.
- [x] Lot 6, sobriété : signaux BlueZ filtrés, rattachements GATT regroupés, Drive réveillé par
  systemd, MAP et PBAP espacés, indicateur sans appel synchrone.
- [x] Lot 7, Contacts : fiches complètes, éditeur avec photo, index, vCard ; README et guide.
- [ ] Essais réels : retour de veille et longue absence, double appel avec un second téléphone,
  réglages AirPods, touches HID (réappairer l'accessoire), suppression d'un message sur
  l'iPhone, champs PBAP renvoyés par iOS, nœud audio HFP pour la sortie d'appel.
- [ ] Avertissement GTK de mesure dans `NotificationsView` (sans effet visible).
