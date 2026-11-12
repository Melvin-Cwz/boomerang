title: Dépannage
icon: dialog-question
summary: Les problèmes courants et quoi essayer.
---
### « Le service Boomerang ne répond pas »
Le service d'arrière-plan est arrêté. Ouvrez le Terminal et exécutez `systemctl --user restart boomerangd`. Pour consulter le journal du service : `journalctl --user -u boomerangd`.

### L'iPhone ne se reconnecte pas
1. Vérifiez que le Bluetooth est activé sur l'ordinateur et sur l'iPhone.
2. Cliquez sur **Reconnecter** dans l'[Aperçu](app:device).
3. Si l'iPhone ne se reconnecte toujours pas, ouvrez Réglages › Bluetooth sur l'iPhone et touchez le nom de l'ordinateur.
4. Si l'Aperçu indique que l'iPhone ne reconnaît plus ce PC, cliquez sur **Appairer à nouveau…**
5. En dernier recours, cliquez sur **Oublier** dans l'Aperçu, oubliez aussi l'ordinateur sur l'iPhone, puis recommencez l'[appairage](guide:link).

### Pas de notifications
Boomerang reçoit les notifications par la liaison basse consommation ou, à défaut, par la liaison classique. S'il indique **Notifications interrompues** :

1. Vérifiez **Partager les notifications système** (Réglages › Bluetooth › ⓘ à côté de l'ordinateur).
2. Désactivez puis réactivez le Bluetooth de l'iPhone dans Réglages.
3. Si rien ne change, cliquez sur **Appairer à nouveau** dans l'Aperçu. Boomerang efface ses anciennes clés et vous guide : oubliez l'ordinateur sur l'iPhone (ⓘ › **Oublier cet appareil**), puis appairez-le de nouveau.

### Une notification reste ou revient
Une notification effacée sur l'iPhone disparaît du bureau, y compris quand elle a été effacée pendant une coupure : Boomerang fait le tri une vingtaine de secondes après la reconnexion. Une notification fermée sur l'ordinateur ne revient pas, même si l'iPhone la met à jour. Si l'une d'elles reste malgré tout, signalez-le sur la page du projet.

### Messages refusés par l'iPhone
Activez **Afficher les notifications** (Réglages › Bluetooth › ⓘ), puis cliquez sur **Vérifier** dans l'assistant.

### Un message apparaît en double
Supprimez la copie en double (clic droit, **Supprimer de Boomerang**). Si le problème se reproduit, signalez-le sur la page du projet.

### Un message n'affiche que son début
Ce comportement est normal tant que le message n'est pas lu sur l'iPhone. Voir [Messages](guide:messages).

### Appel sans son
Pendant l'appel, activez **Audio PC**. Vérifiez la sortie et le micro dans Paramètres système › Son.

### Pas d'appels du tout
Si votre PipeWire est antérieur à la version 1.4, les appels ne sont pas disponibles. Voir [Téléphone](guide:phone).

### iCloud Drive ou Photos vide
Apple demande probablement de confirmer de nouveau la connexion : cliquez sur **Reconnecter…** dans [Services Apple](app:services). Pour consulter le journal : `journalctl --user -u boomerang-icloud-drive`.

### « rclone introuvable » ou trop ancien
Boomerang nécessite rclone 1.69 ou une version plus récente. Suivez les indications de la carte **Composants manquants** dans les [Réglages](app:settings).

### Les écouteurs restent sur « lecture de l'état »
Remettez les écouteurs dans le boîtier, refermez-le, puis rouvrez-le près de l'ordinateur.

### Signaler un problème
Ouvrez un ticket sur la page du projet (onglet Issues). Décrivez ce que vous faisiez, sans y copier vos messages ni vos numéros.
