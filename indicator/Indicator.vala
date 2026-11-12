/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 MelvinCwz
 *
 * Boomerang in the top bar (Wingpanel): the iPhone's state at a glance, with a dot for
 * unread messages or missed calls, and a popover with battery, what is playing, the call
 * in progress and shortcuts to the apps. Everything comes from the Boomerang daemon over
 * D-Bus; the indicator hides itself when the daemon is not running or when the user turns
 * it off in Boomerang (apps.conf [general] indicator=false).
 */

[CCode (cname = "GETTEXT_PACKAGE")]
extern const string GETTEXT_PACKAGE;
[CCode (cname = "LOCALEDIR")]
extern const string LOCALEDIR;

public class Boomerang.Indicator : Wingpanel.Indicator {
    private const string BUS_NAME = "io.github.melvincouwez.Boomerang.Daemon";
    private const string[] SHOWN = { "Paired", "Connected", "UnreadMessages", "MissedCalls", "DeviceName",
                                     "Battery", "NowPlaying", "Tethering", "CallsQuiet", "LinkProblem", "LinkState", "Catalog" };
    private const string OBJECT_PATH = "/io/github/melvincouwez/Boomerang/Daemon";
    private const string INTERFACE = "io.github.melvincouwez.Boomerang1";
    private const string APP_ID = "io.github.melvincouwez.Boomerang";

    private DBusProxy? proxy = null;
    // The daemon's interface as it describes itself, read once per appearance (asynchronously:
    // nothing may block the panel) and forgotten when it goes away.
    private DBusInterfaceInfo? daemon_info = null;
    private uint daemon_generation = 0;
    private uint watch = 0;
    private FileMonitor? prefs_monitor = null;
    private bool wanted = true;

    private Gtk.Box display_widget;
    private Gtk.Overlay phone_overlay;
    private Gtk.Image phone_icon;
    private Gtk.Image headphones_icon;
    private Gtk.Box dot;
    private Variant? headphones_list = null;

    private Gtk.Box? popover_widget = null;
    private Gtk.Label title;
    private Gtk.Label status;
    private Gtk.Box media_box;
    private Gtk.Label media_title;
    private Gtk.Label media_artist;
    private Gtk.Button play_button;
    private Gtk.Box call_box;
    private Gtk.Label call_label;
    private string call_path = "";
    private Gtk.Button messages_button;
    private Gtk.Button tethering_button;
    private bool tethering_on = false;
    private Gtk.Button quiet_button;
    private bool quiet_on = false;
    private Gtk.Box headphones_box;
    private bool headphones_updating = false;
    // Noise control as in Boomerang's AirPods page: values and the feature each one needs.
    private const int[] MODE_VALUES = { 1, 2, 3, 4 };
    private const string[] MODE_LABELS = { N_("Désactivé"), N_("Réduction du bruit"), N_("Transparence"), N_("Adaptatif") };
    private const string[] MODE_FEATURES = { "anc", "anc", "anc", "adaptive" };

    public Indicator () {
        Object (code_name: "boomerang");
    }

    construct {
        GLib.Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
        GLib.Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");

        phone_icon = new Gtk.Image.from_icon_name ("phone-apple-iphone-symbolic");
        dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.START,
            width_request = 6,
            height_request = 6,
            visible = false,
            can_target = false
        };
        dot.add_css_class ("boomerang-indicator-dot");
        phone_overlay = new Gtk.Overlay () { child = phone_icon };
        phone_overlay.add_overlay (dot);
        // Connected AirPods: their icon beside the iPhone's, red when a part is nearly empty.
        headphones_icon = new Gtk.Image.from_icon_name ("audio-headphones-symbolic") { visible = false };
        display_widget = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        display_widget.append (phone_overlay);
        display_widget.append (headphones_icon);

        var css = new Gtk.CssProvider ();
        css.load_from_string ("""
            .boomerang-indicator-dot {
                background-color: @accent_color;
                border-radius: 9999px;
                min-width: 6px;
                min-height: 6px;
            }
            .boomerang-indicator-off { opacity: 0.5; }
            .boomerang-indicator-low { color: @STRAWBERRY_500; }
        """);
        Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css,
                                                   Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        visible = false;
        watch_prefs ();
        watch = Bus.watch_name (BusType.SESSION, BUS_NAME, BusNameWatcherFlags.NONE,
                                on_daemon_appeared, on_daemon_vanished);
    }

    public override Gtk.Widget get_display_widget () {
        return display_widget;
    }

    public override Gtk.Widget? get_widget () {
        if (popover_widget == null) {
            build_popover ();
            refresh ();
            update_headphones ();
        }
        return popover_widget;
    }

    public override void opened () {
        refresh ();
        refresh_call.begin ();
        refresh_headphones.begin ();
    }

    public override void closed () {}

    /* --- the daemon ----------------------------------------------------------------------- */

    private void on_daemon_appeared (DBusConnection connection, string name, string owner) {
        connect_daemon.begin (connection);
    }

    private async void connect_daemon (DBusConnection connection) {
        var generation = ++daemon_generation;
        daemon_info = null;
        try {
            var created = yield new DBusProxy (connection, DBusProxyFlags.NONE, null, BUS_NAME, OBJECT_PATH,
                                               INTERFACE, null);
            if (generation != daemon_generation) {
                return;  // the daemon went away (or came back) meanwhile
            }
            proxy = created;
            proxy.g_properties_changed.connect ((changed, invalidated) => {
                // The panel only shows these: a battery or a track change, not a transfer's progress.
                foreach (var key in SHOWN) {
                    if (changed.lookup_value (key, null) != null || key in invalidated) {
                        refresh ();
                        return;
                    }
                }
            });
            proxy.g_signal.connect ((sender, signal_name, parameters) => {
                if (signal_name == "ActiveCallsChanged") {
                    refresh_call.begin ();
                } else if (signal_name == "HeadphonesChanged") {
                    refresh_headphones.begin ();
                }
            });
        } catch (Error e) {
            warning ("Boomerang daemon unreachable: %s", e.message);
            if (generation == daemon_generation) {
                proxy = null;
                refresh ();
            }
            return;
        }
        refresh ();
        refresh_call.begin ();
        // What the daemon offers (an older one lacks some methods): asked once, without waiting.
        try {
            var reply = yield connection.call (BUS_NAME, OBJECT_PATH, "org.freedesktop.DBus.Introspectable",
                                               "Introspect", null, new VariantType ("(s)"),
                                               DBusCallFlags.NONE, 5000, null);
            var node = new DBusNodeInfo.for_xml (reply.get_child_value (0).get_string ());
            if (generation == daemon_generation) {
                daemon_info = node.lookup_interface (INTERFACE);
            }
        } catch (Error e) {
            debug ("introspection failed: %s", e.message);
        }
        if (generation == daemon_generation) {
            refresh ();
            refresh_headphones.begin ();
        }
    }

    private void on_daemon_vanished (DBusConnection? connection, string name) {
        daemon_generation++;
        proxy = null;
        daemon_info = null;
        call_path = "";
        headphones_list = null;
        refresh ();
        update_headphones ();
    }

    /* A module of the catalogue (Boomerang 2) the user added; true with an older daemon. */
    private bool module_added (string id) {
        var catalog = prop ("Catalog");
        if (catalog == null) {
            return true;
        }
        foreach (var entry in catalog) {
            var mid = entry.lookup_value ("id", VariantType.STRING);
            if (mid != null && mid.get_string () == id) {
                var added = entry.lookup_value ("added", VariantType.BOOLEAN);
                return added != null && added.get_boolean ();
            }
        }
        return false;
    }

    private Variant? prop (string name) {
        return proxy != null ? proxy.get_cached_property (name) : null;
    }

    private bool prop_bool (string name) {
        var v = prop (name);
        return v != null && v.is_of_type (VariantType.BOOLEAN) && v.get_boolean ();
    }

    private string prop_string (string name) {
        var v = prop (name);
        return v != null && v.is_of_type (VariantType.STRING) ? v.get_string () : "";
    }

    private int64 prop_number (string name, int64 fallback = 0) {
        var v = prop (name);
        if (v == null) {
            return fallback;
        }
        if (v.is_of_type (VariantType.INT32)) {
            return v.get_int32 ();
        }
        if (v.is_of_type (VariantType.UINT32)) {
            return v.get_uint32 ();
        }
        return fallback;
    }

    private string media_string (string key) {
        var v = prop ("NowPlaying");
        if (v == null) {
            return "";
        }
        var value = v.lookup_value (key, VariantType.STRING);
        return value != null ? value.get_string () : "";
    }

    /* The daemon may not offer every method (older versions): look before calling. Until the
       introspection of connect_daemon () has answered, nothing optional is offered. */
    private bool has_method (string method) {
        return proxy != null && daemon_info != null && daemon_info.lookup_method (method) != null;
    }

    private void call_daemon (string method, Variant? args = null) {
        if (proxy == null) {
            return;
        }
        proxy.call.begin (method, args, DBusCallFlags.NONE, 10000, null, (obj, res) => {
            try {
                proxy.call.end (res);
            } catch (Error e) {
                warning ("%s failed: %s", method, e.message);
            }
        });
    }

    private async void refresh_call () {
        if (proxy == null) {
            call_path = "";
            update_call ("");
            return;
        }
        try {
            var reply = yield proxy.call ("ListActiveCalls", null, DBusCallFlags.NONE, 3000, null);
            var calls = reply.get_child_value (0);
            call_path = "";
            var text = "";
            for (size_t i = 0; i < calls.n_children (); i++) {
                var call = calls.get_child_value (i);
                var path = call.lookup_value ("path", VariantType.OBJECT_PATH);  // "o" in service.py
                var state = call.lookup_value ("state", VariantType.STRING);
                if (path == null) {
                    continue;
                }
                var who_name = call.lookup_value ("name", VariantType.STRING);
                var who_number = call.lookup_value ("number", VariantType.STRING);
                var who = who_name != null && who_name.get_string () != "" ? who_name.get_string ()
                    : who_number != null ? who_number.get_string () : "";
                call_path = path.get_string ();
                var label = state != null && state.get_string () == "incoming"
                    ? _("Appel entrant") : _("Appel en cours");
                text = who != "" ? "%s · %s".printf (label, who) : label;
                break;
            }
            update_call (text);
        } catch (Error e) {
            call_path = "";
            update_call ("");
        }
    }

    /* Connected AirPods, as in the Mac's Control Center: battery of each part and noise control. */
    private async void refresh_headphones () {
        Variant? list = null;
        if (proxy != null && has_method ("ListHeadphones")) {
            var generation = daemon_generation;
            try {
                var reply = yield proxy.call ("ListHeadphones", null, DBusCallFlags.NONE, 3000, null);
                list = reply.get_child_value (0);
            } catch (Error e) {
                debug ("ListHeadphones failed: %s", e.message);
            }
            if (generation != daemon_generation) {
                return;
            }
        }
        headphones_list = list;
        update_headphones ();
    }

    /* The AirPods icon in the panel and their rows in the popover, from the last list. */
    private void update_headphones () {
        var list = headphones_list;
        string[] tips = {};
        var low = false;
        for (size_t i = 0; list != null && i < list.n_children (); i++) {
            var hp = list.get_child_value (i);
            if (!hp_flag (hp, "connected")) {
                continue;
            }
            var name_v = hp.lookup_value ("name", VariantType.STRING);
            var name = name_v != null && name_v.get_string () != "" ? name_v.get_string () : "AirPods";
            var levels = battery_text (hp);
            tips += levels != "" ? "%s : %s".printf (name, levels) : name;
            foreach (var key in BATTERY_KEYS) {
                var level = hp_int (hp, key);
                if (level >= 0 && level <= 10 && !hp_flag (hp, key + "_charging")) {
                    low = true;
                }
            }
        }
        headphones_icon.visible = tips.length > 0;
        headphones_icon.tooltip_text = tips.length > 0 ? string.joinv ("\n", tips) : null;
        if (low) {
            headphones_icon.add_css_class ("boomerang-indicator-low");
        } else {
            headphones_icon.remove_css_class ("boomerang-indicator-low");
        }

        if (popover_widget == null) {
            return;
        }
        headphones_updating = true;
        for (var child = headphones_box.get_first_child (); child != null; child = headphones_box.get_first_child ()) {
            headphones_box.remove (child);
        }
        for (size_t i = 0; list != null && i < list.n_children (); i++) {
            var hp = list.get_child_value (i);
            var connected = hp.lookup_value ("connected", VariantType.BOOLEAN);
            if (connected != null && connected.get_boolean ()) {
                if (headphones_box.get_first_child () == null) {
                    headphones_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 3, margin_bottom = 3 });
                }
                headphones_box.append (headphones_row (hp));
            }
        }
        headphones_box.visible = headphones_box.get_first_child () != null;
        headphones_updating = false;
    }

    private const string[] BATTERY_KEYS = { "left", "right", "case" };
    private const string[] BATTERY_LABELS = { N_("Gauche"), N_("Droite"), N_("Boîtier") };

    private static int hp_int (Variant hp, string key) {
        var v = hp.lookup_value (key, VariantType.INT32);
        return v != null ? v.get_int32 () : -1;
    }

    private static bool hp_flag (Variant hp, string key) {
        var v = hp.lookup_value (key, VariantType.BOOLEAN);
        return v != null && v.get_boolean ();
    }

    /* « Gauche 80 % · Droite 75 % · Boîtier 40 % », parts with no known level left out. */
    private static string battery_text (Variant hp) {
        string[] parts = {};
        for (int i = 0; i < BATTERY_KEYS.length; i++) {
            var level = hp_int (hp, BATTERY_KEYS[i]);
            if (level >= 0) {
                parts += "%s %d %%".printf (_(BATTERY_LABELS[i]), level);
            }
        }
        return string.joinv (" · ", parts);
    }

    /* The theme's battery icons, by level as the system's power indicator draws them. */
    private static string battery_icon (int level, bool charging) {
        var name = level >= 90 ? "battery-full" : level >= 50 ? "battery-good"
                 : level > 20 ? "battery-low" : level > 10 ? "battery-caution" : "battery-empty";
        return name + (charging ? "-charging-symbolic" : "-symbolic");
    }

    private Gtk.Widget headphones_row (Variant hp) {
        var name_v = hp.lookup_value ("name", VariantType.STRING);
        var address_v = hp.lookup_value ("address", VariantType.STRING);
        var address = address_v != null ? address_v.get_string () : "";
        var open = menu_button (name_v != null && name_v.get_string () != "" ? name_v.get_string () : "AirPods");
        open.clicked.connect (() => launch (APP_ID + ".Headphones"));
        var battery = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { margin_start = 12, margin_bottom = 3 };
        for (int i = 0; i < BATTERY_KEYS.length; i++) {
            var level = hp_int (hp, BATTERY_KEYS[i]);
            if (level < 0) {
                continue;
            }
            var charging = hp_flag (hp, BATTERY_KEYS[i] + "_charging");
            var icon = new Gtk.Image.from_icon_name (battery_icon (level, charging));
            if (level <= 10 && !charging) {
                icon.add_css_class ("boomerang-indicator-low");
            }
            var text = new Gtk.Label ("%s %d %%".printf (_(BATTERY_LABELS[i]), level));
            text.add_css_class (Granite.CssClass.DIM);
            text.add_css_class (Granite.CssClass.SMALL);
            text.add_css_class ("numeric");
            var part = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
            part.append (icon);
            part.append (text);
            battery.append (part);
        }
        battery.update_property (Gtk.AccessibleProperty.LABEL, battery_text (hp), -1);
        var row = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        row.append (open);
        row.append (battery);

        var features = hp.lookup_value ("features", new VariantType ("as"));
        var features_list = features != null ? features.get_strv () : new string[0];
        var mode = hp_int (hp, "mode");
        Gtk.CheckButton? group = null;
        for (int i = 0; i < MODE_VALUES.length; i++) {
            if (!(MODE_FEATURES[i] in features_list)) {
                continue;
            }
            var check = new Gtk.CheckButton.with_label (_(MODE_LABELS[i])) {
                active = MODE_VALUES[i] == mode,
                margin_start = 12
            };
            if (group == null) {
                group = check;
            } else {
                check.group = group;
            }
            var value = MODE_VALUES[i];
            check.toggled.connect (() => {
                if (check.active && !headphones_updating) {
                    call_daemon ("SetHeadphones", new Variant ("(ssv)", address, "mode", new Variant.int32 (value)));
                }
            });
            row.append (check);
        }
        return row;
    }

    /* --- the user's choice in Boomerang ---------------------------------------------------- */

    private static string prefs_path () {
        return Path.build_filename (Environment.get_user_config_dir (), "boomerang", "apps.conf");
    }

    private void read_prefs () {
        var prefs = new KeyFile ();
        try {
            prefs.load_from_file (prefs_path (), KeyFileFlags.NONE);
            wanted = prefs.get_boolean ("general", "indicator");
        } catch (Error e) {
            wanted = true;  // shown unless turned off
        }
    }

    private void watch_prefs () {
        read_prefs ();
        try {
            prefs_monitor = File.new_for_path (prefs_path ()).monitor_file (FileMonitorFlags.NONE);
            // The app saves apps.conf for many other things (window sizes, drafts…).
            prefs_monitor.changed.connect (() => {
                var was = wanted;
                read_prefs ();
                if (wanted != was) {
                    refresh ();
                }
            });
        } catch (Error e) {
            debug ("cannot watch apps.conf: %s", e.message);
        }
    }

    /* --- display ----------------------------------------------------------------------------- */

    private void refresh () {
        visible = wanted && proxy != null && prop_bool ("Paired");
        if (!visible) {
            return;
        }
        var connected = prop_bool ("Connected");
        if (connected) {
            phone_icon.remove_css_class ("boomerang-indicator-off");
        } else {
            phone_icon.add_css_class ("boomerang-indicator-off");
        }
        var unread = prop_number ("UnreadMessages");
        var missed = prop_number ("MissedCalls");
        dot.visible = unread > 0 || missed > 0;
        var name = prop_string ("DeviceName");
        display_widget.tooltip_text = connected
            ? _("%s connecté").printf (name != "" ? name : "iPhone")
            : _("%s non connecté").printf (name != "" ? name : "iPhone");

        if (popover_widget == null) {
            return;
        }
        title.label = name != "" ? name : "iPhone";
        // Same words as the app's header (LinkText.vala), from the daemon's LinkState.
        var link = Boomerang.LinkText.describe (prop_string ("LinkState"), prop_string ("LinkProblem"), name);
        var battery = connected ? Boomerang.LinkText.battery ((int) prop_number ("Battery", -1)) : "";
        status.label = battery != "" ? "%s · %s".printf (link.title, battery) : link.title;

        var track = media_string ("title");
        var playing = media_string ("status") == "playing";
        media_box.visible = connected && track != "";
        media_title.label = track;
        media_artist.label = media_string ("artist");
        media_artist.visible = media_artist.label != "";
        play_button.icon_name = playing ? "media-playback-pause-symbolic"
                                        : "media-playback-start-symbolic";
        play_button.tooltip_text = playing ? _("Pause") : _("Lecture");

        messages_button.label = unread > 0
            ? ngettext ("Messages · %u non lu", "Messages · %u non lus", (ulong) unread).printf ((uint) unread)
            : _("Messages");

        tethering_button.visible = connected && has_method ("SetTethering") && module_added ("hotspot");
        var tether = prop ("Tethering");
        tethering_on = tether != null && tether.is_of_type (VariantType.BOOLEAN) && tether.get_boolean ();
        tethering_button.label = tethering_on ? _("Couper la connexion via l'iPhone")
                                              : _("Se connecter via l'iPhone");

        quiet_button.visible = connected && has_method ("SetCallsQuiet");
        var quiet = prop ("CallsQuiet");
        quiet_on = quiet != null && quiet.is_of_type (VariantType.BOOLEAN) && quiet.get_boolean ();
        quiet_button.label = quiet_on ? _("Appels : rétablir la sonnerie")
                                      : _("Appels : passer en silence");
    }

    private void update_call (string text) {
        if (popover_widget == null) {
            return;
        }
        call_box.visible = text != "";
        call_label.label = text;
    }

    private Gtk.Button menu_button (string label) {
        var button = new Gtk.Button.with_label (label);
        button.add_css_class ("menuitem");
        var child = button.child as Gtk.Label;
        if (child != null) {
            child.xalign = 0;
        }
        return button;
    }

    private Gtk.Button media_control (string icon, string tooltip, string command) {
        var button = new Gtk.Button.from_icon_name (icon) { tooltip_text = tooltip };
        button.add_css_class ("flat");
        button.clicked.connect (() => call_daemon ("MediaCommand", new Variant ("(s)", command)));
        return button;
    }

    private void build_popover () {
        title = new Gtk.Label ("") { xalign = 0 };
        title.add_css_class ("heading");
        status = new Gtk.Label ("") { xalign = 0 };
        status.add_css_class (Granite.CssClass.DIM);
        var header = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
            margin_start = 12,
            margin_end = 12,
            margin_top = 6,
            margin_bottom = 6
        };
        header.append (title);
        header.append (status);

        // What is playing on the iPhone (AMS), with the three usual buttons.
        media_title = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 28 };
        media_artist = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 28 };
        media_artist.add_css_class (Granite.CssClass.DIM);
        var words = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        words.append (media_title);
        words.append (media_artist);
        play_button = media_control ("media-playback-start-symbolic", _("Lecture"), "toggle");
        var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
        controls.append (media_control ("media-skip-backward-symbolic", _("Précédent"), "previous"));
        controls.append (play_button);
        controls.append (media_control ("media-skip-forward-symbolic", _("Suivant"), "next"));
        media_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_start = 12,
            margin_end = 6,
            margin_top = 3,
            margin_bottom = 3
        };
        media_box.append (words);
        media_box.append (controls);

        // A call in progress or ringing: who, and hang up.
        call_label = new Gtk.Label ("") { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
        var hangup = new Gtk.Button.from_icon_name ("call-stop-symbolic") { tooltip_text = _("Raccrocher") };
        hangup.add_css_class (Granite.CssClass.DESTRUCTIVE);
        hangup.add_css_class (Granite.CssClass.CIRCULAR);
        hangup.clicked.connect (() => {
            if (call_path != "") {
                call_daemon ("CallAction", new Variant ("(os)", call_path, "hangup"));
            }
        });
        call_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_start = 12,
            margin_end = 12,
            margin_top = 3,
            margin_bottom = 3,
            visible = false
        };
        call_box.append (call_label);
        call_box.append (hangup);

        messages_button = menu_button (_("Messages"));
        messages_button.clicked.connect (() => launch (APP_ID));
        tethering_button = menu_button (_("Se connecter via l'iPhone"));
        tethering_button.visible = false;
        tethering_button.clicked.connect (() => {
            call_daemon ("SetTethering", new Variant ("(b)", !tethering_on));
            close ();
        });
        quiet_button = menu_button (_("Appels : passer en silence"));
        quiet_button.visible = false;
        quiet_button.clicked.connect (() => {
            call_daemon ("SetCallsQuiet", new Variant ("(b)", !quiet_on));
            close ();
        });
        var open = menu_button (_("Ouvrir Boomerang"));
        open.clicked.connect (() => launch (APP_ID));

        popover_widget = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 260 };
        popover_widget.append (header);
        popover_widget.append (media_box);
        popover_widget.append (call_box);
        headphones_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        popover_widget.append (headphones_box);
        popover_widget.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 3, margin_bottom = 3 });
        popover_widget.append (messages_button);
        popover_widget.append (tethering_button);
        popover_widget.append (quiet_button);
        popover_widget.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 3, margin_bottom = 3 });
        popover_widget.append (open);
    }

    private void launch (string desktop_id) {
        close ();
        var info = new DesktopAppInfo (desktop_id + ".desktop");
        if (info == null) {
            info = new DesktopAppInfo (APP_ID + ".desktop");
        }
        if (info == null) {
            return;
        }
        try {
            info.launch (null, null);
        } catch (Error e) {
            warning ("cannot open %s: %s", desktop_id, e.message);
        }
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.ServerType server_type) {
    if (server_type != Wingpanel.ServerType.SESSION) {
        return null;
    }
    return new Boomerang.Indicator ();
}
