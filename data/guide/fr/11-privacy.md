title: Vie privée
icon: preferences-system-privacy
summary: Ce que Boomerang garde, où, et comment l'effacer.
---
Boomerang fonctionne entièrement sur votre ordinateur. Son auteur n'exploite aucun serveur et ne reçoit aucune donnée : pas de compte Boomerang, pas de télémétrie, pas de statistiques, pas de rapport de plantage envoyé.

## Données traitées
- Reçues de l'iPhone par Bluetooth : notifications, messages (texte, expéditeur, date), contacts, journal d'appels, état de la musique et de la batterie.
- Échangées directement avec Apple : courriel, agendas, rappels, contacts, fichiers et photos iCloud.

## Où elles sont gardées
- Cache des messages et des contacts : `~/.local/share/boomerang/`, lisible uniquement par votre compte utilisateur.
- Réglages : `~/.config/boomerang/`. La configuration d'iCloud Drive y est chiffrée.
- Mots de passe et clés : le trousseau de votre session.
- Comptes iCloud : gérés par le système (Evolution Data Server).
- Les journaux de Boomerang ne contiennent jamais le texte d'un message ni un numéro.

## Accès au réseau
En dehors d'iCloud, Boomerang se connecte uniquement à des services publics d'Apple, sans compte :
- icônes des apps de l'iPhone qui envoient des notifications : seul l'identifiant de l'app est envoyé (par exemple `net.whatsapp.WhatsApp`), jamais le contenu d'une notification. Cache : `~/.cache/boomerang/app-icons/`. Pour désactiver cette fonction : `app-icons=false` dans le groupe `[notifications]` de `~/.config/boomerang/boomerangd.conf` ;
- pochettes de la [lecture en cours](guide:sound) : seuls l'artiste et le titre sont envoyés. Cache : `~/.cache/boomerang/artwork/`. Pour désactiver cette fonction : `artwork=false` dans le groupe `[media]` du même fichier ;
- téléchargement de rclone, seulement quand vous le demandez.

## Sécurité
- Appairage : aucun appareil n'est appairé sans votre clic sur **Le code correspond**. Pendant les trois minutes où l'ordinateur est visible, Boomerang refuse les appairages sans code et accepte uniquement les profils d'un iPhone (jamais un clavier ou une souris).
- Autres programmes : seule l'app Boomerang peut, sans demander de confirmation, appeler, envoyer un message ou des fichiers, appairer ou oublier l'iPhone, installer une mise à jour, supprimer ou modifier des données. Si un autre programme demande l'une de ces actions, une notification vous propose de l'autoriser ou de la refuser ; sans réponse au bout d'une minute, la demande est refusée. Taper sur l'iPhone et confirmer un code d'appairage restent réservés à l'app Boomerang.
- Fichiers (LocalSend) : Boomerang demande votre accord dans une notification pour chaque réception, même quand l'envoi vient de votre iPhone. Sur le réseau, rien ne prouve l'identité de l'expéditeur. La taille est limitée à 20 Go par envoi, et une réception ne peut jamais remplir le disque.
- Codes SMS dans le navigateur : quand un SMS lie un code à un site (`@exemple.fr #482913`), Boomerang remplit ce code automatiquement sur ce site et ne le propose jamais ailleurs. Les autres codes demandent un clic sur la pastille, qui indique l'expéditeur du SMS. Cette fonction est limitée aux pages HTTPS.
- Mises à jour : Boomerang vérifie le paquet (SHA-256) une première fois après le téléchargement. Le programme d'installation le vérifie de nouveau, sur une copie que seul l'administrateur peut modifier.
- Recopie de l'écran : Boomerang demande à l'iPhone un code à quatre chiffres à chaque démarrage.

## Tout effacer
1. Dans la page Services iCloud, déconnectez iCloud Drive et iCloud Photos (icône de corbeille de chaque ligne).
2. Dans un terminal, lancez `boomerang-icloud-signin --remove` pour retirer le compte iCloud, puis supprimez le mot de passe pour app sur account.apple.com.
3. Supprimez les dossiers `~/.local/share/boomerang/`, `~/.config/boomerang/` et `~/.cache/boomerang/`.
4. Dans l'app Mots de passe et clés, supprimez les entrées Boomerang et iCloud.

Désinstaller le paquet ne supprime pas ces fichiers. Les messages et contacts de vos correspondants restent sous votre responsabilité : ne partagez pas ces dossiers.
