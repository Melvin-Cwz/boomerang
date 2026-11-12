// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Main window. First run: the setup assistant (Onboarding), full window.
 * Then (Boomerang 2) one app for the people of the iPhone, the iPhone link in the header
 * bar (LinkStatus), and a switcher with three positions at the top of the left column:
 * Personnes (MessagesView: each person's messages, calls and card), Pavé (PhoneView: the
 * keypad and the voicemail) and iPhone, the Centre: Le Fil, Notifications, Lecture en cours,
 * Répertoire, the modules, then the device (link and pairing, Réglages) in its sidebar.
 */

public class Boomerang.MainWindow : Gtk.ApplicationWindow {
    private Daemon daemon;
    private Gtk.Stack stack;
    private Gtk.Stack modes;  // Personnes, Pavé, iPhone
    private Gtk.StackSwitcher mode_switcher;
    private MessagesView people;
    private PhoneView keypad;
    private Gtk.Stack pages;
    private Gtk.Stack settings_nav;  // Réglages, Réglages avancés
    private Sidebar sidebar;
    private Gtk.HeaderBar main_header;
    private Onboarding onboarding;
    private Gtk.Label device_name;
    private Gtk.Label device_status;
    private Gtk.Label device_detail;
    private LinkArc device_arc;
    private Gtk.Button pair_button;
    private Gtk.Button reconnect_button;
    private Gtk.Button forget_button;
    private ModuleRow notifications_row;
    private ModuleRow media_row;
    private ModuleRow calls_row;
    private ModuleRow battery_row;
    private ModuleRow messages_row;
    private ModuleRow sound_row;
    private Gtk.DropDown sound_output;
    private string[] sound_outputs = {};
    private bool sound_updating = false;
    private string sound_state = "";
    private FilesView files_view;
    private string? pending_page = null;  // asked before the daemon answered
    private LinkBanner link_banner;
    // Module pages: shown in the sidebar once their module is added (catalog.py).
    private GenericArray<Gtk.Widget> gated = new GenericArray<Gtk.Widget> ();

    public MainWindow (Gtk.Application app) {
        Object (application: app, title: _("Boomerang"), default_width: 1080, default_height: 740);
        // Development (screenshots): BOOMERANG_SNAPSHOT_SIZE=1080x860.
        var size = Environment.get_variable ("BOOMERANG_SNAPSHOT_SIZE");
        if (size != null && size.contains ("x")) {
            var parts = size.split ("x");
            set_default_size (int.parse (parts[0]), int.parse (parts[1]));
        }
    }

    construct {
        // One header bar across the window in Boomerang's colour, its name in the middle,
        // like Cassette and the web apps.
        pages = new Gtk.Stack () { transition_type = Gtk.StackTransitionType.CROSSFADE, vhomogeneous = false };
        sidebar = new Sidebar (pages);
        daemon = new Daemon ();
        link_banner = new LinkBanner (daemon);
        link_banner.action_requested.connect ((action) => {
            if (action == "pair") {
                new PairingDialog (this, daemon).present ();
            }
        });
        var menu = new Menu ();
        menu.append (_("Réglages"), "win.show-page::settings");
        menu.append (_("Assistant de configuration"), "win.setup");
        menu.append (_("Guide"), "win.help");
        var about_section = new Menu ();
        about_section.append (_("Contributeurs"), "win.show-page::contributors");
        about_section.append (_("À propos de Boomerang"), "win.about");
        menu.append_section (null, about_section);
        var menu_button = new Gtk.MenuButton () {
            icon_name = "open-menu",
            menu_model = menu,
            primary = true,
            tooltip_markup = Granite.markup_accel_tooltip ({ "F10" }, _("Menu"))
        };
        menu_button.add_css_class ("large-icons");
        // The three positions in the middle, always there; the link shows only when it is missing.
        modes = new Gtk.Stack () { transition_type = Gtk.StackTransitionType.CROSSFADE, vexpand = true };
        mode_switcher = new Gtk.StackSwitcher () { stack = modes, valign = Gtk.Align.CENTER };
        mode_switcher.add_css_class ("mode-switcher");
        ((Gtk.BoxLayout) mode_switcher.layout_manager).homogeneous = true;
        main_header = new Gtk.HeaderBar () {
            show_title_buttons = true,
            title_widget = mode_switcher
        };
        main_header.pack_end (menu_button);
        main_header.add_css_class ("flat");
        main_header.add_css_class ("brand");
        titlebar = main_header;

        var setup_action = new SimpleAction ("setup", null);
        setup_action.activate.connect (() => show_page ("setup"));
        add_action (setup_action);
        var help_action = new SimpleAction ("help", null);
        help_action.activate.connect (open_help);
        add_action (help_action);
        // Ctrl+1, 2, 3: Personnes, Pavé, iPhone (accels in Application).
        var mode_action = new SimpleAction ("mode", VariantType.STRING);
        mode_action.activate.connect ((param) => {
            if (stack.visible_child_name == "main") {
                modes.visible_child_name = param.get_string ();
            }
        });
        add_action (mode_action);
        // Alt+1…8: sections in sidebar order.
        var section_action = new SimpleAction ("section", VariantType.INT32);
        section_action.activate.connect ((param) => {
            if (stack.visible_child_name == "main") {
                modes.visible_child_name = "iphone";
                sidebar.select_index (param.get_int32 ());
            }
        });
        add_action (section_action);
        var page_action = new SimpleAction ("show-page", VariantType.STRING);
        page_action.activate.connect ((param) => show_page (param.get_string ()));
        add_action (page_action);
        var about_action = new SimpleAction ("about", null);
        about_action.activate.connect (() => show_about (this));
        add_action (about_action);

        people = new MessagesView (daemon);
        keypad = new PhoneView (daemon);
        keypad.history.message_requested.connect (write_to);
        var contacts_book = new ContactsView (daemon);
        contacts_book.message_requested.connect (write_to);
        pages.add_titled (new FeedView (daemon), "feed", _("Le Fil"));
        pages.add_titled (contacts_book, "contacts-book", _("Répertoire"));
        pages.add_titled (new NotificationsView (daemon), "notifications", _("Notifications"));
        pages.add_titled (new NowPlayingView (daemon), "nowplaying", _("Lecture en cours"));
        files_view = new FilesView (daemon);
        pages.add_titled (files_view, "files", _("Envoi de fichiers"));
        pages.add_titled (new PhotosView (daemon), "photos", _("Import de photos"));
        pages.add_titled (new MirrorView (daemon), "mirror", _("Recopie d'écran"));
        pages.add_titled (titled (_("Écouteurs"), new HeadphonesView (daemon)), "headphones", _("AirPods"));
        pages.add_titled (new ServicesView (daemon), "services", _("Services iCloud"));  // its own big title
        pages.add_titled (build_settings_page (), "settings", _("Réglages"));
        pages.add_titled (new ContributorsView (), "contributors", _("Contributeurs"));
        var modules_view = new ModulesView (daemon);
        modules_view.open_page.connect ((page) => show_page (page));
        pages.add_titled (modules_view, "modules", _("Modules"));
        // The core, always there (PRODUCT.md), then the modules the user added, then the device.
        sidebar.add ("feed", "", "document-open-recent-symbolic", _("Le Fil"));
        sidebar.add ("notifications", "", "preferences-system-notifications-symbolic", _("Notifications"));
        sidebar.add ("nowplaying", "", "multimedia-audio-player-symbolic", _("Lecture en cours"));
        sidebar.add ("headphones", _("Modules"), "audio-headphones-symbolic", _("Écouteurs"));
        sidebar.add ("services", _("Modules"), "preferences-desktop-online-accounts-symbolic", _("Services iCloud"));
        sidebar.add ("files", _("Modules"), "document-send-symbolic", _("Envoi de fichiers"));
        sidebar.add ("photos", _("Modules"), "multimedia-photo-viewer-symbolic", _("Import de photos"));
        sidebar.add ("mirror", _("Modules"), "video-display-symbolic", _("Recopie d'écran"));
        sidebar.add ("modules", _("Modules"), "list-add-symbolic", _("Ajouter des modules…"));
        sidebar.add ("settings", "", "preferences-system-symbolic", _("Réglages"));
        var mini_player = new MiniPlayer (daemon);
        mini_player.open_requested.connect (() => pages.visible_child_name = "nowplaying");
        sidebar.set_player (mini_player);
        pages.notify["visible-child-name"].connect (() => {
            if (pages.visible_child_name == "settings") {  // back on top, or on the update waiting
                settings_nav.visible_child_name = UpdatesCard.pending (daemon) > 0 ? "advanced/updates" : "basic";
            }
        });

        onboarding = new Onboarding (daemon);
        onboarding.pair_requested.connect (() => new PairingDialog (this, daemon).present ());
        onboarding.finished.connect (() => {
            stack.visible_child_name = "main";
            select ("device");
            update_header ();
        });

        var offline = new Granite.Placeholder (_("Le service Boomerang ne répond pas")) {
            description = _("Démarrez-le avec « systemctl --user start boomerangd », "
                          + "ou consultez son journal avec « journalctl --user -u boomerangd »."),
            icon = new ThemedIcon ("dialog-warning")
        };
        var retry = offline.append_button (new ThemedIcon ("view-refresh"), _("Réessayer"),
                                           _("Relancer la connexion au service"));
        retry.clicked.connect (() => daemon.connect_bus.begin ());

        // iPhone: the section list, then the page.
        var side = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        side.add_css_class ("sidebar");
        side.append (sidebar);
        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
            start_child = side,
            end_child = pages,
            resize_start_child = false,
            shrink_start_child = false,
            shrink_end_child = false
        };
        sidebar.attach_paned (paned);

        modes.add_titled (people, "people", _("Personnes"));
        modes.add_titled (keypad, "keypad", _("Pavé"));
        modes.add_titled (paned, "iphone", "iPhone");
        modes.notify["visible-child-name"].connect (on_mode_shown);
        notify["is-active"].connect (on_mode_shown);
        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        content.append (link_banner);
        content.append (new CallBar (daemon));
        // A dot on « iPhone » while the link is missing, said in words for the tooltip and screen readers.
        link_banner.state_changed.connect ((summary, attention) => {
            modes.get_page (modes.get_child_by_name ("iphone")).needs_attention = attention;
            var button = mode_switcher.get_last_child ();  // « iPhone », the last of the three
            if (button != null) {
                button.tooltip_text = attention ? summary : null;
                button.update_property (Gtk.AccessibleProperty.DESCRIPTION, attention ? summary : "", -1);
            }
        });
        content.append (modes);

        stack = new Gtk.Stack () { transition_type = Gtk.StackTransitionType.CROSSFADE, vexpand = true };
        stack.add_named (full_page (offline), "offline");
        stack.add_named (full_page (onboarding), "onboarding");
        stack.add_named (content, "main");
        stack.visible_child_name = "offline";
        child = stack;
        update_header ();

        daemon.changed.connect (() => {
            if (daemon.touched ({ "Catalog" })) {
                apply_catalog ();
            }
        });
        daemon.changed.connect (() => {
            if (daemon.touched ({ "Paired", "Connected", "LinkState", "BluetoothAvailable", "Battery", "DeviceName", "LinkProblem", "Modules", "NotificationsLinked", "MediaLinked", "CallsLinked", "CallsSupported", "MessagesState", "MessagesSend", "PhoneAudio", "UnreadMessages", "MissedCalls", "Update" })) {
                update ();
            }
        });
        foreach (var row in new ModuleRow[] { notifications_row, media_row, calls_row,
                                             messages_row, battery_row }) {
            row.toggled.connect ((active) => daemon.set_module_enabled (row.module, active));
        }
        daemon.connect_bus.begin ();
    }

    /* Réglages, in two levels as on the iPhone: the iPhone and the few settings people change,
       then one row to Réglages avancés, where every other setting stays, in sections. */
    private Gtk.Widget build_settings_page () {
        var basic = settings_column ();
        var title = new Gtk.Label (_("Réglages")) { xalign = 0 };
        title.add_css_class ("title-1");
        basic.append (title);
        basic.append (build_device_card ());

        notifications_row = new ModuleRow ("notifications", "preferences-system-notifications",
                                           _("Notifications de l'iPhone"));
        media_row = new ModuleRow ("media", Config.APP_ID + ".NowPlaying", _("Lecture en cours"));
        calls_row = new ModuleRow ("calls", Config.APP_ID + ".Phone", _("Appels sur ce PC"));
        messages_row = new ModuleRow ("messages", Config.APP_ID + ".Messages", _("Messages et contacts"));
        battery_row = new ModuleRow ("battery", "battery-good", _("Alertes de batterie"));
        sound_row = build_sound_row ();
        gate ("audio", sound_row);
        var main_list = settings_list ();
        foreach (var row in new Gtk.Widget[] { notifications_row, messages_row, calls_row, build_calls_quiet_row (),
                                               sound_row, media_row, battery_row, IndicatorSetting.row () }) {
            main_list.append (row);
        }
        basic.append (main_list);

        settings_nav = new Gtk.Stack () { transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT, vexpand = true };
        var more = settings_list ();
        more.append (nav_row ("preferences-system", _("Réglages avancés"),
                              _("Connexion, messages, fiches, sons, affichage, mises à jour"), "advanced"));
        more.row_activated.connect (() => settings_nav.visible_child_name = "advanced");
        basic.append (more);
        settings_nav.add_named (scrolled (basic), "basic");

        // Réglages avancés: one row per section, each opening its own page, as on the iPhone.
        var advanced = settings_column ();
        advanced.append (back_button (_("Réglages"), "basic"));
        var advanced_title = new Gtk.Label (_("Réglages avancés")) { xalign = 0 };
        advanced_title.add_css_class ("title-1");
        advanced.append (advanced_title);
        var index = settings_list ();
        advanced.append (index);
        settings_nav.add_named (scrolled (advanced), "advanced");

        var guide = new PhoneGuide (daemon) { margin_top = 12 };
        guide.pair_requested.connect (() => new PairingDialog (this, daemon).present ());
        var privacy = new Gtk.Label (
            _("Tout passe directement entre ce PC et l'iPhone, en Bluetooth. Les journaux de Boomerang "
            + "ne contiennent jamais le texte des notifications ni des messages.")
        ) { wrap = true, xalign = 0 };
        privacy.add_css_class (Granite.CssClass.DIM);
        privacy.add_css_class (Granite.CssClass.SMALL);
        forget_button = new Gtk.Button.with_label (_("Oublier cet iPhone…")) { halign = Gtk.Align.START };
        forget_button.add_css_class (Granite.CssClass.DESTRUCTIVE);
        forget_button.clicked.connect (confirm_forget);
        section (index, "connection", "preferences-bluetooth", _("Connexion"),
                 _("Partage de connexion, verrouillage, guide, oubli"), {
            gate ("hotspot", new Granite.HeaderLabel (_("Internet via l'iPhone"))),
            gate ("hotspot", build_hotspot_card ()),
            gate ("proximity", new Granite.HeaderLabel (_("Verrouillage de proximité"))),
            gate ("proximity", build_proximity_card ()),
            new Gtk.Expander (_("Guide de connexion")) { child = guide },
            forget_button, privacy
        });
        section (index, "messages", Config.APP_ID + ".Messages", _("Messages"),
                 _("Lecture, codes SMS, liens, apparence"),
                 { new MessagesSettings (daemon, () => people.apply_style ()) });

        var book = settings_list ();
        book.append (action_row ("x-office-address-book", _("Répertoire"),
                                 _("Toutes les fiches : leur source (Bluetooth ou iCloud), l'ordre de tri, "
                                   + "l'import et l'export"),
                                 _("Ouvrir"), () => show_page ("contacts-book")));
        section (index, "contacts", "x-office-address-book", _("Fiches de contact"),
                 _("Source, tri, import et export"), { book });
        section (index, "sounds", "preferences-desktop-sound", _("Sons"), _("Sonnerie, messages, notifications"), {
            new Granite.HeaderLabel (_("Choix des sons")), new SoundsCard (daemon),
            new Granite.HeaderLabel (_("Sons de Boomerang")), new FreeSoundsCard (daemon, this)
        });

        var language = settings_list ();
        language.append (Language.settings_row (this));
        var detached = settings_list ();
        detached.append (launcher_row (Mode.HEADPHONES, _("Écouteurs"), _("Batterie et réglages de vos AirPods")));
        detached.append (launcher_row (Mode.MIRROR, _("Recopie"), _("L'écran de l'iPhone et son contrôle depuis le PC")));
        var detached_hint = new Gtk.Label (
            _("Chaque app a sa propre fenêtre et son icône. L'interrupteur affiche ou masque l'app dans le menu Applications.")
        ) { xalign = 0, wrap = true };
        detached_hint.add_css_class (Granite.CssClass.DIM);
        detached_hint.add_css_class (Granite.CssClass.SMALL);
        section (index, "display", "preferences-desktop-display", _("Affichage"),
                 _("Langue, colonne de gauche, apps séparées"), {
            new Granite.HeaderLabel (_("Langue")), language,
            new Granite.HeaderLabel (_("Colonne de gauche")), sidebar_card (),
            new Granite.HeaderLabel (_("Apps séparées")), detached, detached_hint
        });
        section (index, "updates", "system-software-update", _("Mises à jour"), _("Boomerang et ses composants"),
                 { new UpdatesCard (daemon), new ComponentsCard () });

        var alpha_hint = new Gtk.Label (
            _("Ces fonctionnalités reposent sur des comportements de l'iPhone qui ne sont pas "
              + "encore vérifiés. Elles peuvent rester sans effet. Elles sont désactivées par défaut.")
        ) { xalign = 0, wrap = true };
        alpha_hint.add_css_class (Granite.CssClass.DIM);
        alpha_hint.add_css_class (Granite.CssClass.SMALL);
        section (index, "experimental", "applications-development", _("Expérimental"),
                 _("Fonctions encore à l'essai, désactivées par défaut"), { build_alpha_card (), alpha_hint });

        var actions = settings_list ();
        actions.append (action_row ("system-run", _("Configuration initiale"),
                                    _("Relancer l'assistant pas à pas"), _("Ouvrir"), () => show_page ("setup")));
        actions.append (action_row ("help-contents", _("Guide"), _("Pas à pas, vie privée et dépannage (F1)"),
                                    _("Ouvrir"), open_help));
        actions.append (action_row ("starred-symbolic", _("Nouveautés"),
                                    _("Ce qui change dans la version %s").printf (Config.VERSION),
                                    _("Afficher"), () => WhatsNew.show (this)));
        actions.append (action_row (Config.APP_ID, _("À propos de Boomerang"),
                                    _("Version %s, licence, remerciements").printf (Config.VERSION),
                                    _("Afficher"), () => show_about (this)));
        section (index, "help", "system-help", _("Assistance"), _("Guide, nouveautés, à propos"), { actions });
        return settings_nav;
    }

    /* A page of the iPhone column under its big title, in the same column as Réglages. */
    private static Gtk.Widget titled (string title, Gtk.Widget page) {
        var label = new Gtk.Label (title) { xalign = 0 };
        label.add_css_class ("title-1");
        var head = new PageColumn () { margin_bottom = 0 };
        head.append (label);
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        box.append (head);
        box.append (page);
        page.vexpand = true;
        return box;
    }

    /* A column of Réglages: centred and bounded, on the 6/12/24 grid. */
    private static PageColumn settings_column () {
        return new PageColumn ();
    }

    private static Gtk.ListBox settings_list () {
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        list.add_css_class (Granite.CssClass.CARD);
        return list;
    }

    private static Gtk.Widget scrolled (Gtk.Widget child) {
        return new Gtk.ScrolledWindow () { child = child, hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true };
    }

    /* A row that opens a page of Réglages: icon, title, one line, chevron. */
    private Gtk.ListBoxRow nav_row (string icon, string title, string subtitle, string target) {
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (new Gtk.Label (title) { xalign = 0 });
        var detail = new Gtk.Label (subtitle) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        detail.add_css_class (Granite.CssClass.DIM);
        detail.add_css_class (Granite.CssClass.SMALL);
        text.append (detail);
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 6, margin_bottom = 6, margin_start = 12, margin_end = 12
        };
        box.append (new Gtk.Image.from_icon_name (icon) { pixel_size = 32 });
        box.append (text);
        box.append (new Gtk.Image.from_icon_name ("go-next-symbolic"));
        var row = new Gtk.ListBoxRow () { child = box };
        row.update_property (Gtk.AccessibleProperty.LABEL, title, Gtk.AccessibleProperty.DESCRIPTION, subtitle, -1);
        row.set_data<string> ("target", target);
        return row;
    }

    private Gtk.Widget back_button (string label, string target) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.append (new Gtk.Image.from_icon_name ("go-previous-symbolic"));
        box.append (new Gtk.Label (label));
        var back = new Gtk.Button () { child = box, halign = Gtk.Align.START };
        back.add_css_class ("flat");
        back.update_property (Gtk.AccessibleProperty.LABEL, _("Retour à %s").printf (label), -1);
        back.clicked.connect (() => settings_nav.visible_child_name = target);
        return back;
    }

    /* A section of Réglages avancés: its row in the list, and its own page with a way back. */
    private void section (Gtk.ListBox index, string id, string icon, string title, string subtitle,
                          Gtk.Widget[] children) {
        if (index.get_first_child () == null) {
            index.row_activated.connect ((row) => settings_nav.visible_child_name = row.get_data<string> ("target"));
        }
        index.append (nav_row (icon, title, subtitle, "advanced/" + id));
        var column = settings_column ();
        column.append (back_button (_("Réglages avancés"), "advanced"));
        var label = new Gtk.Label (title) { xalign = 0 };
        label.add_css_class ("title-1");
        column.append (label);
        foreach (var child in children) {
            column.append (child);
        }
        settings_nav.add_named (scrolled (column), "advanced/" + id);
    }

    /* Quiet calls (CallsQuiet): no ring, popup or audio on the PC, e.g. when Teams rings there too. */
    private Gtk.Widget build_calls_quiet_row () {
        var title_label = new Gtk.Label (_("Appels de l'iPhone en silence")) { xalign = 0 };
        var subtitle_label = new Gtk.Label (
            _("Ni sonnerie ni fenêtre sur ce PC, par exemple quand Teams y sonne déjà ; "
              + "l'appel reste visible dans Pavé")
        ) { xalign = 0, wrap = true };
        subtitle_label.add_css_class (Granite.CssClass.DIM);
        subtitle_label.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        text.append (subtitle_label);
        var sw = new Gtk.Switch () { valign = Gtk.Align.CENTER, active = daemon.get_bool ("CallsQuiet") };
        sw.update_property (Gtk.AccessibleProperty.LABEL, title_label.label, -1);
        bool updating = false;
        sw.state_set.connect ((wanted) => {
            if (!updating) {
                daemon.call.begin ("SetCallsQuiet", new Variant ("(b)", wanted));
            }
            return false;
        });
        daemon.changed.connect (() => {
            if (!daemon.touched ({ "CallsQuiet" })) {
                return;
            }
            var wanted = daemon.get_bool ("CallsQuiet");
            if (sw.active != wanted) {
                updating = true;
                sw.active = wanted;
                updating = false;
            }
        });
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9, margin_bottom = 9, margin_start = 12, margin_end = 12
        };
        box.append (new Gtk.Image.from_icon_name ("audio-volume-muted") { pixel_size = 32, valign = Gtk.Align.CENTER });
        box.append (text);
        box.append (sw);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }

    /* Whole text of unread messages (FetchUnread): downloading marks them read on the iPhone. */
    /* Réglages › Affichage: the section list folded to its icons, or not. */
    private Gtk.Widget sidebar_card () {
        var folded = new Gtk.Switch () { valign = Gtk.Align.CENTER };
        sidebar.bind_property ("collapsed", folded, "active",
                               BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
        var title = new Gtk.Label (_("Réduite aux icônes")) { xalign = 0 };
        var detail = new Gtk.Label (_("Les compteurs passent sur les icônes, comme dans le dock. "
                                      + "Vous pouvez aussi glisser le bord de la colonne, ou appuyer sur F9.")) {
            xalign = 0,
            wrap = true
        };
        detail.add_css_class (Granite.CssClass.DIM);
        detail.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title);
        text.append (detail);
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9, margin_bottom = 9, margin_start = 12, margin_end = 12
        };
        box.append (new Gtk.Image.from_icon_name ("preferences-desktop-workspaces") { pixel_size = 32, valign = Gtk.Align.START });
        box.append (text);
        box.append (folded);
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
        list.add_css_class (Granite.CssClass.CARD);
        list.append (new Gtk.ListBoxRow () { child = box, activatable = false });
        return list;
    }

    /* One switch per experimental feature (AlphaFeatures on the daemon). */
    private Gtk.Widget build_alpha_card () {
        var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, show_separators = true };
        list.add_css_class (Granite.CssClass.CARD);
        list.append (alpha_row ("map_history", _("Historique étendu des messages"),
                                _("Boomerang demande à l'iPhone les messages antérieurs à la "
                                  + "liste habituelle (pages suivantes, jusqu'à un an en arrière)")));
        list.append (alpha_row ("mark_read", _("Marquer comme lu sur l'iPhone"),
                                _("Ouvrir une conversation dans Boomerang la marque comme lue sur l'iPhone")));
        list.append (alpha_row ("ancs_actions", _("Actions des notifications"),
                                _("Boutons de l'iPhone (Marquer comme lu, Supprimer…) dans Notifications")));
        list.append (alpha_row ("pbap_favorites", _("Favoris de l'iPhone"),
                                _("Une étoile signale les contacts favoris, récupérés à la prochaine synchronisation")));
        list.append (alpha_row ("iphone_control", _("Contrôler l'iPhone depuis le PC"),
                                _("Le PC comme souris et clavier Bluetooth de l'iPhone (app Recopie)")));
        list.append (alpha_row ("head_gestures", _("Répondre d'un geste de tête"),
                                _("AirPods portés : hocher la tête répond à un appel entrant, la secouer "
                                  + "le refuse (d'après LibrePods)")));
        list.append (alpha_row ("mirror_ble", _("Balise Bluetooth pour la recopie"),
                                _("L'iPhone trouve le PC par Bluetooth quand le réseau bloque la découverte "
                                  + "(app Recopie, pendant la recopie seulement)")));
        return list;
    }

    private Gtk.Widget alpha_row (string feature, string title, string subtitle) {
        var title_label = new Gtk.Label (title) { xalign = 0 };
        var subtitle_label = new Gtk.Label (subtitle) { xalign = 0, wrap = true };
        subtitle_label.add_css_class (Granite.CssClass.DIM);
        subtitle_label.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        text.append (subtitle_label);
        var sw = new Gtk.Switch () { valign = Gtk.Align.CENTER, active = daemon.alpha_enabled (feature) };
        sw.update_property (Gtk.AccessibleProperty.LABEL, title, -1);
        bool updating = false;
        sw.notify["active"].connect (() => {
            if (!updating) {
                daemon.call.begin ("SetAlphaFeature", new Variant ("(sb)", feature, sw.active));
            }
        });
        daemon.changed.connect (() => {
            if (!daemon.touched ({ "AlphaFeatures" })) {
                return;
            }
            var wanted = daemon.alpha_enabled (feature);
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
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }

    private delegate void RowAction ();

    private static Gtk.Widget action_row (string icon, string title, string subtitle, string button_label,
                                          owned RowAction action) {
        var image = new Gtk.Image.from_icon_name (icon) { pixel_size = 32 };
        var title_label = new Gtk.Label (title) { xalign = 0 };
        var subtitle_label = new Gtk.Label (subtitle) { xalign = 0, wrap = true };
        subtitle_label.add_css_class (Granite.CssClass.DIM);
        subtitle_label.add_css_class (Granite.CssClass.SMALL);
        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true, valign = Gtk.Align.CENTER };
        text.append (title_label);
        text.append (subtitle_label);
        var button = new Gtk.Button.with_label (button_label) { valign = Gtk.Align.CENTER };
        button.clicked.connect (() => action ());
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 9,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };
        box.append (image);
        box.append (text);
        box.append (button);
        return new Gtk.ListBoxRow () { child = box, activatable = false };
    }

    private void update_header () {
        title = stack.visible_child_name == "onboarding" ? _("Configurer Boomerang") : _("Boomerang");
        mode_switcher.visible = stack.visible_child_name == "main";
        update_badges ();
    }

    private void update_badges () {
        sidebar.set_badge ("settings", UpdatesCard.pending (daemon));
    }

    /* Offline and first-run screens take the whole window, under the window's header. */
    private static Gtk.Widget full_page (Gtk.Widget page) {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        page.vexpand = true;
        box.append (page);
        return box;
    }

    /* Top of Réglages: the iPhone, its link and battery, and what to do about it. */
    private Gtk.Widget build_device_card () {
        var phone_icon = new Gtk.Image.from_icon_name (Config.APP_ID + ".Device") { pixel_size = 64, margin_start = 12 };
        device_name = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        device_name.add_css_class ("title-2");
        device_status = new Gtk.Label ("") { xalign = 0, wrap = true, hexpand = true };
        device_arc = new LinkArc ();
        var status_line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        status_line.append (device_arc);
        status_line.append (device_status);
        device_detail = new Gtk.Label ("") { xalign = 0, wrap = true };
        device_detail.add_css_class (Granite.CssClass.DIM);
        pair_button = new Gtk.Button.with_label (_("Appairer un iPhone…"));
        pair_button.clicked.connect (() => new PairingDialog (this, daemon).present ());
        reconnect_button = new Gtk.Button.with_label (_("Reconnecter"));
        reconnect_button.clicked.connect (() => daemon.call.begin ("Reconnect"));
        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { margin_top = 6 };
        buttons.append (pair_button);
        buttons.append (reconnect_button);
        buttons.append (Guide.help_button ("link", _("Comment relier l'iPhone")));
        var summary_text = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
            valign = Gtk.Align.CENTER, hexpand = true, margin_top = 12, margin_bottom = 12, margin_end = 12
        };
        summary_text.append (device_name);
        summary_text.append (status_line);
        summary_text.append (device_detail);
        summary_text.append (buttons);
        var card = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        card.add_css_class (Granite.CssClass.CARD);
        card.append (phone_icon);
        card.append (summary_text);
        return card;
    }

    /* The window's minimum height for no given width must be its minimum height at its minimum
       width (GTK's rule for height-for-width widgets). Its stacks break the rule: a homogeneous
       Gtk.Stack measures each page for no width, where the wrapping labels of a page narrower than
       the window (a Granite.Placeholder: Lecture en cours idle, no call…) fold word by word and get
       far taller than at any width the window can have. GTK 4.22 then measures the window's width
       for that smaller height and warns at every relayout (« Trying to measure BoomerangMainWindow
       for height of 318, but it needs at least 384 »), each second while a song plays. */
    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        if (orientation == Gtk.Orientation.VERTICAL && for_size < 0) {
            int min_width, nat_width, min_base, nat_base;
            base.measure (Gtk.Orientation.HORIZONTAL, -1, out min_width, out nat_width, out min_base, out nat_base);
            for_size = min_width;
        }
        base.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
        minimum_baseline = natural_baseline = -1;  // (Vala would hand back 0: a window has no baseline)
    }

    /* Removes the iPhone and its keys from this PC, to start pairing again from scratch. */
    private void confirm_forget () {
        var dialog = new Granite.MessageDialog.with_image_from_icon_name (
            _("Oublier cet iPhone ?"),
            _("Boomerang supprime l'appairage sur ce PC. Pour repartir de zéro, oubliez aussi ce "
              + "PC sur l'iPhone (Réglages › Bluetooth › ⓘ › Oublier cet appareil), puis appairez de "
              + "nouveau les deux appareils."),
            "bluetooth", Gtk.ButtonsType.CANCEL) {
            transient_for = this,
            modal = true
        };
        var go = dialog.add_button (_("Oublier"), Gtk.ResponseType.ACCEPT);
        go.add_css_class (Granite.CssClass.DESTRUCTIVE);
        dialog.response.connect ((response) => {
            dialog.destroy ();
            if (response == Gtk.ResponseType.ACCEPT) {
                daemon.call.begin ("Forget");
            }
        });
        dialog.present ();
    }

    /* Bluetooth tethering: a card of its own, shown on the overview and in Réglages. */
    private Gtk.Widget build_hotspot_card () {
        return new HotspotCard (daemon);
    }

    /* Proximity lock settings (Réglages, Général). */
    private Gtk.Widget build_proximity_card () {
        return new ProximityCard (daemon);
    }

    /* Sound of the iPhone (A2DP) played on this PC: allowed or not, and on which output. */
    private ModuleRow build_sound_row () {
        var row = new ModuleRow ("sound", "audio-speakers", _("Son de l'iPhone"));
        sound_output = new Gtk.DropDown.from_strings ({ _("Sortie par défaut") }) {
            valign = Gtk.Align.CENTER,
            tooltip_text = _("Sortie du PC pour le son de l'iPhone")
        };
        sound_output.notify["selected"].connect (() => {
            if (!sound_updating && sound_output.selected < sound_outputs.length) {
                daemon.call.begin ("SetPhoneAudioOutput",
                                   new Variant ("(s)", sound_outputs[sound_output.selected]));
            }
        });
        row.add_suffix (sound_output);
        row.toggled.connect ((active) => daemon.call.begin ("SetPhoneAudio", new Variant ("(b)", active)));
        return row;
    }

    private async void load_sound_outputs () {
        var items = yield daemon.call_list ("ListAudioOutputs");
        string[] names = { "" };
        string[] labels = { _("Sortie par défaut") };
        foreach (var item in items) {
            names += item.lookup_value ("name", VariantType.STRING).get_string ();
            labels += item.lookup_value ("description", VariantType.STRING).get_string ();
        }
        sound_updating = true;
        sound_outputs = names;
        sound_output.model = new Gtk.StringList (labels);
        var current = daemon.get_string ("PhoneAudioOutput");
        sound_output.selected = 0;
        for (int i = 0; i < names.length; i++) {
            if (names[i] == current) {
                sound_output.selected = i;
            }
        }
        sound_updating = false;
    }

    private void update_sound (bool connected) {
        var state = daemon.get_string ("PhoneAudio");
        if (state != sound_state) {
            // Outputs may have changed (headphones plugged in): reload on each change.
            sound_state = state;
            load_sound_outputs.begin ();
        }
        sound_output.sensitive = state != "off";
        string status;
        if (state == "off") {
            status = _("Désactivé : le son des vidéos et de la musique reste sur l'iPhone");
        } else if (state == "playing") {
            status = _("En lecture sur ce PC");
        } else if (connected) {
            status = _("Pour envoyer le son vers ce PC, choisissez-le avec le bouton AirPlay de l'iPhone");
        } else {
            status = _("iPhone absent");
        }
        sound_row.update (state != "off", status);
    }

    private void update () {
        update_badges ();
        link_banner.update ();
        if (!daemon.running) {
            stack.visible_child_name = "offline";
            return;
        }
        if (stack.visible_child_name == "offline") {
            if (pending_page == "setup" || (pending_page == null && !Setup.is_done ())) {
                onboarding.restart ();
                stack.visible_child_name = "onboarding";
            } else {
                stack.visible_child_name = "main";
                if (pending_page != null) {
                    select (pending_page);
                }
            }
            WhatsNew.maybe_show (this, !Setup.is_done ());
            pending_page = null;
            update_header ();
        }

        var paired = daemon.get_bool ("Paired");
        // LinkState is the one truth (Boomerang 2); Connected only with an older daemon.
        var state = daemon.get_string ("LinkState");
        var connected = state != "" ? state == "classic" || state == "complete" : daemon.get_bool ("Connected");
        var bluetooth = daemon.get_bool ("BluetoothAvailable");
        var battery = daemon.get_int ("Battery");
        var name = daemon.get_string ("DeviceName");
        var problem = daemon.get_string ("LinkProblem");
        var bond_lost = problem == "bond-lost";
        var le_missing = problem == "le-missing";

        device_name.label = name != "" ? name : _("Aucun iPhone");
        // Same sentence and arc as the header (LinkText.vala).
        var link = LinkText.describe (state != "" ? state : (connected ? "complete" : "absent"), problem, name);
        var level = connected && battery >= 0 ? LinkText.battery (battery) : "";
        // Under the name: the state in a few words (the name is already the title).
        var words = link.short != "" ? link.short.substring (0, link.short.index_of_nth_char (1)).up ()
                                       + link.short.substring (link.short.index_of_nth_char (1))
                                     : _("Relié");
        device_status.label = level != "" ? _("%s · batterie %s").printf (words, level) : words;
        device_detail.label = link.detail;
        device_detail.visible = link.detail != "";
        device_arc.filled = link.filled;
        device_arc.problem = link.problem;
        device_arc.pending = link.pending;
        pair_button.visible = bluetooth;
        pair_button.label = bond_lost || le_missing ? _("Appairer à nouveau…")
            : paired ? _("Appairer un autre iPhone…") : _("Appairer un iPhone…");
        if (paired && !bond_lost && !le_missing) {
            pair_button.remove_css_class (Granite.CssClass.SUGGESTED);
        } else {
            pair_button.add_css_class (Granite.CssClass.SUGGESTED);
        }
        reconnect_button.visible = paired && !connected && bluetooth && !bond_lost;
        forget_button.visible = name != "" && bluetooth;

        string waiting_le = connected
            ? _("En attente : l'iPhone doit se connecter à « Boomerang » en Bluetooth basse consommation")
            : _("iPhone absent");

        var on = daemon.module_enabled ("notifications");
        notifications_row.update (on, !on ? _("Désactivées")
            : daemon.get_bool ("NotificationsLinked") ? _("Reçues de l'iPhone, avec leurs actions")
            : paired ? waiting_le : _("iPhone non appairé"));

        on = daemon.module_enabled ("media");
        media_row.update (on, !on ? _("Désactivée")
            : daemon.get_bool ("MediaLinked") ? _("Pilotable depuis Lecture en cours et l'indicateur de son")
            : paired ? waiting_le : _("iPhone non appairé"));

        on = daemon.module_enabled ("calls");
        var calls_off = calls_unavailable (daemon);
        calls_row.update (on, calls_off ? _(CALLS_UNAVAILABLE)
            : !on ? _("Désactivés")
            : daemon.get_bool ("CallsLinked") ? _("Prêt : les appels entrants s'affichent ici")
            : connected ? _("Profil mains libres non connecté")
            : _("iPhone absent"), !calls_off);

        on = daemon.module_enabled ("messages");
        string messages_status;
        switch (daemon.get_string ("MessagesState")) {
            case "ready":
                messages_status = daemon.get_string ("MessagesSend") == "no"
                    ? _("Lecture depuis l'iPhone ; réponse sur l'iPhone seulement")
                    : _("Messages de l'iPhone lus en Bluetooth");
                break;
            case "forbidden":
                messages_status = _("Refusé : activez « Afficher les notifications » pour ce PC "
                                  + "dans les réglages Bluetooth de l'iPhone");
                break;
            case "no-obex":
                messages_status = _("Paquet bluez-obexd manquant");
                break;
            case "connecting":
                messages_status = _("Connexion…");
                break;
            case "error":
                messages_status = _("Messages momentanément illisibles");
                break;
            default:
                messages_status = connected ? _("En attente") : _("iPhone absent");
                break;
        }
        messages_row.update (on, on ? messages_status : _("Désactivés"));

        on = daemon.module_enabled ("battery");
        battery_row.update (on, !on ? _("Alertes désactivées")
            : battery >= 0 ? _("%d %% · alerte à 20 %% et 10 %%").printf (battery)
            : _("Niveau inconnu"));

        update_sound (connected);

    }

    /* « Envoyer à l'iPhone » from Fichiers: the Fichiers page with these files ready to go. */
    public void send_files (string[] paths) {
        files_view.queue (paths);
        show_page ("files");
    }

    /* Shown only while the module is added (ModulesView). */
    private Gtk.Widget gate (string module, Gtk.Widget widget) {
        widget.set_data<string> ("module", module);
        gated.add (widget);
        widget.visible = Catalog.added (daemon, module);
        return widget;
    }

    /* Modules added or removed: their pages and settings follow. */
    private void apply_catalog () {
        foreach (var widget in gated) {
            widget.visible = Catalog.added (daemon, widget.get_data<string> ("module"));
        }
        var catalog = daemon.get_value ("Catalog");
        if (catalog == null) {
            return;
        }
        foreach (var entry in catalog) {
            var page = Props.str (entry, "page");
            if (page == "") {
                continue;
            }
            var added = Props.flag (entry, "added");
            sidebar.set_shown (page, added);
            if (!added && pages.visible_child_name == page) {
                pages.visible_child_name = "modules";
            }
        }
    }

    public void show_page (string name) {
        if (name == "setup" && !daemon.running) {
            pending_page = name;
        } else if (name == "setup") {
            onboarding.restart ();
            stack.visible_child_name = "onboarding";
        } else if (!daemon.running) {
            pending_page = name;
        } else {
            stack.visible_child_name = "main";
            select (name);
        }
        update_header ();
    }

    /* A page by its name: messages and contacts are Personnes, phone the Pavé, the rest the Centre. */
    private void select (string name) {
        if (name == "device") {
            name = "settings";  // the iPhone card is at the top of Réglages
        }
        if (settings_nav.get_child_by_name (name) != null) {  // advanced, advanced/sounds…
            select ("settings");
            settings_nav.visible_child_name = name;
            return;
        }
        if (name == "people" || name == "messages" || name == "contacts") {
            modes.visible_child_name = "people";
        } else if (name == "keypad" || name == "phone") {
            modes.visible_child_name = "keypad";
        } else if (pages.get_child_by_name (name) != null) {
            pages.visible_child_name = name;
            modes.visible_child_name = "iphone";
        }
    }

    /* Personnes on screen: the open conversation is being read; calls are seen there and in Pavé. */
    private void on_mode_shown () {
        var mode = modes.visible_child_name;
        if (is_active && mode == "people") {
            people.window_activated ();
        } else {
            people.update_viewing ();
        }
        if (is_active && (mode == "people" || mode == "keypad")) {
            daemon.call.begin ("MarkCallsSeen");
        }
    }

    /* A conversation (Le Fil, a notification, --thread) in Personnes. */
    public void open_thread (string thread, bool reply) {
        show_page ("people");
        people.open_thread (thread, reply);
    }

    /* A number or address (--to, sms:, Message buttons) in Personnes: its person, or a new one. */
    public void write_to (string address) {
        show_page ("people");
        people.start_conversation (address);
    }

    /* tel: the keypad with the number ready; nothing is dialled until Appeler. */
    public void dial (string number) {
        show_page ("keypad");
        keypad.prefill (number);
    }

    private void open_help () {
        Guide.open (this);
    }

    /* One side of the system window-button layout, "close:minimize,maximize" → "close:" or
       ":minimize,maximize", for a window split in two header bars. */
    public static string split_layout (bool start) {
        var layout = Gtk.Settings.get_default ().gtk_decoration_layout ?? "close:maximize";
        var parts = layout.split (":", 2);
        var left = parts[0];
        var right = parts.length > 1 ? parts[1] : "";
        return start ? left + ":" : ":" + right;
    }
}
