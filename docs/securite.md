# Sécurité de Boomerang

Ce document résume les protections en place et les limites connues. Il complète la page
« Vie privée » du guide intégré.

## Protections

- **Appairage Bluetooth** (`boomerangd/link.py`) : pendant la fenêtre d'appairage, le code
  de comparaison attend la confirmation de l'utilisateur (« Le code correspond », dans l'app
  ou la notification, 60 s au plus). Les appairages sans code (« Just Works ») sont refusés.
  `AuthorizeService` n'accepte que les profils d'un iPhone (mains libres, audio, contacts,
  messages…) pour l'appareil confirmé, jamais le HID.
- **API D-Bus de session** (`boomerangd/callers.py`, `service.GUARDED`) : seul l'exécutable de
  l'app Boomerang (`/proc/<pid>/exe`, binaire installé par le paquet ou à côté du démon) peut
  déclencher sans confirmation les actions faites au nom de l'utilisateur. Tout autre programme
  déclenche une notification « Autoriser / Refuser ». Les commandes clavier/souris vers
  l'iPhone et `ConfirmPairing` sont réservées à l'app. `SendFiles` refuse, pour un autre
  programme, les fichiers hors du dossier personnel ou dans un dossier caché.
- **Codes SMS** : `LatestCode("copy")` ne répond qu'à l'app, une seule fois, dans les
  20 secondes qui suivent un clic sur « Copier le code ». L'extension ne travaille que sur les
  pages HTTPS de premier niveau et respecte les codes liés à un domaine (`@site #code`).
- **LocalSend** : Boomerang demande l'accord de l'utilisateur avant chaque réception. Il n'y a
  pas d'acceptation automatique, faute de preuve d'identité côté réception. La taille reçue est
  plafonnée et l'espace disque libre est préservé. À l'envoi, HTTPS est obligatoire et
  l'empreinte du certificat est vérifiée à chaque connexion. Boomerang associe chaque pair aux
  adresses où il l'a vu : une fausse annonce peut seulement faire échouer l'envoi.
- **Mises à jour** : téléchargement depuis GitHub, SHA-256 publié par GitHub, puis
  `pkexec boomerang-install-update` : copie dans un dossier réservé à root, nouveau calcul
  du SHA-256, contrôle du nom de paquet, installation de la copie.
- **bMessage** : le texte d'un SMS est lu d'après `LENGTH` ; rien après `BEGIN:BBODY` n'est
  pris pour une enveloppe (pas de faux destinataires).
- **Contrôle de l'iPhone (HID)** : les rapports clavier ne sont envoyés qu'à bluetoothd, et
  seuls ses appels sont acceptés sur les objets GATT.
- **Notifications** : le corps est échappé quand le serveur interprète le balisage.
- **Recopie** : code AirPlay à quatre chiffres, tiré à chaque démarrage.
- **rclone** : SHA256SUMS vérifié par signature PGP (clés de publication de rclone livrées
  avec Boomerang) quand GnuPG est présent ; sinon SHA-256 seul, signalé (« unsigned »).

## Limites connues et suites prévues

- Les paquets .deb ne sont pas signés : le SHA-256 vient de la même réponse GitHub que
  l'adresse de téléchargement. Il protège d'un téléchargement corrompu ou remplacé, pas d'un
  compte GitHub compromis. Suite prévue : signer les .deb et épingler la clé dans Boomerang.
- Un programme de la même session peut lancer le vrai binaire de l'app avec ses propres
  arguments. L'app n'agit qu'après un clic de l'utilisateur, mais ce cas n'est pas couvert
  par le contrôle d'appelant.
- Identifiants de l'extension navigateur : voir `docs/navigateurs.md`.
- LocalSend : si le client LocalSend présentait un jour un certificat client, une
  acceptation automatique vérifiée par TLS mutuel deviendrait possible.
