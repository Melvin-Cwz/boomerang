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
                                     "Battery", "NowPlaying", "Tethering", "CallsQuiet", "LinkProblem", "LinkState", "Catalog",
                                     "Proximity", "Mirror", "MicMuted", "AudioOnPC", "QuickReplies" };
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
    private Gtk.Label badge;
    private Gtk.Label panel_call;
    private Variant? headphones_list = null;

    private Gtk.Box? popover_widget = null;
    private Gtk.Label title;
    private Gtk.Label status;
    private Gtk.Label battery_label;
    private Gtk.LevelBar battery_bar;
    private Gtk.Box status_dot;
    private Gtk.Box header_box;
    private Gtk.Box banner_box;
    private Gtk.Label banner_label;
    private Gtk.Box tiles_box;
    private Gtk.Box tethering_tile;
    private Gtk.Box quiet_tile;
    private Gtk.Box mirror_tile;
    private Gtk.Box proximity_tile;
    private Gtk.Button tethering_button;
    private Gtk.Button quiet_button;
    private Gtk.Button mirror_button;
    private Gtk.Button proximity_button;
    private bool tethering_on = false;
    private bool quiet_on = false;
    private bool mirror_on = false;
    private bool proximity_on = false;
    private Gtk.Box media_box;
    private Gtk.Label media_title;
    private Gtk.Label media_artist;
    private Gtk.Button play_button;
    private Gtk.Box feed_box;
    private Gtk.Box feed_list;
    private Variant? feed_threads = null;
    private Variant? feed_calls = null;
    // The call in progress or ringing (ListActiveCalls), its length counted here second by second.
    private string call_path = "";
    private string call_state = "";
    private string call_who = "";
    private int call_seconds = 0;
    private uint call_tick = 0;
    private Gtk.Box incoming_box;
    private Gtk.Label incoming_avatar;
    private Gtk.Label incoming_name;
    private Gtk.Label incoming_kind;
    private Gtk.CheckButton incoming_pc_sound;
    private Gtk.Box replies_box;
    private Gtk.Box call_box;
    private Gtk.Label call_avatar;
    private Gtk.Label call_name;
    private Gtk.Label call_status;
    private Gtk.Box call_mic_circle;
    private Gtk.Box call_pc_circle;
    private Gtk.Box outputs_box;
    private bool outputs_updating = false;
    private Gtk.Box headphones_box;
    private bool headphones_updating = false;
    // Noise control as in Boomerang's AirPods page: values and the feature each one needs.
    private const int[] MODE_VALUES = { 1, 2, 3, 4 };
    private const string[] MODE_LABELS = { N_("Désactivé"), N_("Réduction"), N_("Transparence"), N_("Adaptatif") };
    private const string[] MODE_FEATURES = { "anc", "anc", "anc", "adaptive" };

    public Indicator () {
        Object (code_name: "boomerang");
    }

    construct {
        GLib.Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
        GLib.Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");

        phone_icon = new Gtk.Image.from_icon_name ("phone-apple-iphone-symbolic");
        // Yellow dot when the iPhone is out of reach.
        dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.START,
            width_request = 7,
            height_request = 7,
            visible = false,
            can_target = false
        };
        dot.add_css_class ("boomerang-indicator-dot");
        phone_overlay = new Gtk.Overlay () { child = phone_icon };
        phone_overlay.add_overlay (dot);
        // What is new (unread messages and missed calls) as a count, as on the mockup.
        badge = new Gtk.Label ("") { visible = false };
        badge.add_css_class ("boomerang-badge");
        // A call: the pill turns green and shows who is ringing, then how long it lasts.
        panel_call = new Gtk.Label ("") { visible = false };
        panel_call.add_css_class ("numeric");
        // Connected AirPods: their icon beside the iPhone's, red when a part is nearly empty.
        headphones_icon = new Gtk.Image.from_icon_name ("audio-headphones-symbolic") { visible = false };
        display_widget = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        display_widget.append (phone_overlay);
        display_widget.append (badge);
        display_widget.append (panel_call);
        display_widget.append (headphones_icon);

        var css = new Gtk.CssProvider ();
        css.load_from_string ("""
            .boomerang-indicator-dot {
                background-color: #f9c440;
                border-radius: 9999px;
                min-width: 7px;
                min-height: 7px;
            }
            .boomerang-indicator-off { opacity: 0.5; }
            .boomerang-indicator-low { color: #c6262e; }
            .boomerang-badge {
                background-color: #3689e6;
                color: #ffffff;
                border-radius: 9999px;
                min-width: 16px;
                min-height: 16px;
                padding: 0 4px;
                font-size: 11px;
                font-weight: 700;
            }
            .boomerang-pill-call {
                background-color: #3a9104;
                color: #ffffff;
                border-radius: 9999px;
                padding: 0 8px;
                font-weight: 700;
            }
            .boomerang-pill-ringing { box-shadow: 0 0 0 3px alpha(#68b723, 0.45); }
            .boomerang-circle {
                background-color: alpha(currentColor, 0.1);
                border-radius: 9999px;
                min-width: 44px;
                min-height: 44px;
            }
            .boomerang-circle-on { background-color: #3689e6; color: #ffffff; }
            .boomerang-circle-red { background-color: #c6262e; color: #ffffff; }
            .boomerang-circle-green { background-color: #3a9104; color: #ffffff; }
            .boomerang-avatar {
                background-color: alpha(#3689e6, 0.18);
                border-radius: 9999px;
                font-weight: 700;
            }
            .boomerang-section {
                font-size: 11px;
                font-weight: 700;
                letter-spacing: 0.04em;
            }
            .boomerang-banner {
                background-color: alpha(#f9c440, 0.25);
                border-radius: 8px;
            }
            .boomerang-in-call { background-color: alpha(#68b723, 0.22); }
            .boomerang-status-dot { border-radius: 9999px; min-width: 8px; min-height: 8px; }
            .boomerang-circle-green { background-color: #3a9104; color: #ffffff; }
            .boomerang-circle-orange { background-color: #d48e15; }
            .boomerang-pill-button { border-radius: 9999px; min-height: 32px; padding: 0 12px; }
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
        refresh_feed.begin ();
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
                } else if (signal_name == "ThreadsChanged" || signal_name == "CallsChanged"
                           || signal_name == "NotificationsChanged") {
                    refresh_feed.begin ();
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
        call_state = "";
        feed_threads = null;
        feed_calls = null;
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
            call_state = "";
            update_call ();
            return;
        }
        try {
            var reply = yield proxy.call ("ListActiveCalls", null, DBusCallFlags.NONE, 3000, null);
            var calls = reply.get_child_value (0);
            call_path = "";
            call_state = "";
            call_who = "";
            call_seconds = 0;
            for (size_t i = 0; i < calls.n_children (); i++) {
                var call = calls.get_child_value (i);
                var path = call.lookup_value ("path", VariantType.OBJECT_PATH);  // "o" in service.py
                var state = call.lookup_value ("state", VariantType.STRING);
                if (path == null) {
                    continue;
                }
                var who_name = call.lookup_value ("name", VariantType.STRING);
                var who_number = call.lookup_value ("number", VariantType.STRING);
                call_who = who_name != null && who_name.get_string () != "" ? who_name.get_string ()
                    : who_number != null ? who_number.get_string () : "";
                call_path = path.get_string ();
                call_state = state != null ? state.get_string () : "active";
                var length = call.lookup_value ("duration", VariantType.INT32);
                call_seconds = length != null && length.get_int32 () > 0 ? length.get_int32 () : 0;
                break;
            }
        } catch (Error e) {
            call_path = "";
            call_state = "";
        }
        update_call ();
        if (call_state != "" && call_state != "incoming") {
            refresh_outputs.begin ();
        }
    }

    /* Where the call's sound can go (this PC, the AirPods, the iPhone), as the daemon lists it. */
    private async void refresh_outputs () {
        if (proxy == null || !has_method ("ListCallAudioOutputs") || popover_widget == null) {
            return;
        }
        var generation = daemon_generation;
        try {
            var reply = yield proxy.call ("ListCallAudioOutputs", null, DBusCallFlags.NONE, 3000, null);
            if (generation != daemon_generation) {
                return;
            }
            var list = reply.get_child_value (0);
            outputs_updating = true;
            for (var child = outputs_box.get_first_child (); child != null; child = outputs_box.get_first_child ()) {
                outputs_box.remove (child);
            }
            Gtk.CheckButton? group = null;
            for (size_t i = 0; i < list.n_children (); i++) {
                var output = list.get_child_value (i);
                var id = output.lookup_value ("name", VariantType.STRING);
                var text = output.lookup_value ("description", VariantType.STRING);
                var current = output.lookup_value ("current", VariantType.BOOLEAN);
                if (id == null) {
                    continue;
                }
                var radio = new Gtk.CheckButton.with_label (text != null && text.get_string () != ""
                                                            ? text.get_string () : id.get_string ()) {
                    active = current != null && current.get_boolean ()
                };
                if (group == null) {
                    group = radio;
                } else {
                    radio.group = group;
                }
                var output_id = id.get_string ();
                radio.toggled.connect (() => {
                    if (radio.active && !outputs_updating) {
                        call_daemon ("SetCallAudioOutput", new Variant ("(s)", output_id));
                    }
                });
                outputs_box.append (radio);
            }
            outputs_box.visible = outputs_box.get_first_child () != null;
            outputs_updating = false;
        } catch (Error e) {
            outputs_updating = false;
            debug ("ListCallAudioOutputs failed: %s", e.message);
        }
    }

    /* « À rattraper »: the unread conversations and the missed calls, newest first, three at most. */
    private async void refresh_feed () {
        if (proxy == null) {
            return;
        }
        var generation = daemon_generation;
        Variant? threads = null;
        Variant? calls = null;
        try {
            var reply = yield proxy.call ("ListThreads", null, DBusCallFlags.NONE, 3000, null);
            threads = reply.get_child_value (0);
        } catch (Error e) {
            debug ("ListThreads failed: %s", e.message);
        }
        if (generation == daemon_generation && has_method ("ListCalls")) {
            try {
                var reply = yield proxy.call ("ListCalls", null, DBusCallFlags.NONE, 3000, null);
                calls = reply.get_child_value (0);
            } catch (Error e) {
                debug ("ListCalls failed: %s", e.message);
            }
        }
        if (generation != daemon_generation) {
            return;
        }
        feed_threads = threads;
        feed_calls = calls;
        update_feed ();
    }

    private static string initials (string name) {
        string result = "";
        foreach (var word in name.split (" ")) {
            if (word != "" && result.char_count () < 2 && word.get_char ().isalpha ()) {
                result += word.get_char ().toupper ().to_string ();
            }
        }
        return result != "" ? result : "#";
    }

    private static int64 now_seconds () {
        return new DateTime.now_local ().to_unix ();
    }

    private static string time_text (int64 when) {
        var then = new DateTime.from_unix_local (when);
        var now = new DateTime.now_local ();
        return then.get_day_of_year () == now.get_day_of_year () && then.get_year () == now.get_year ()
            ? then.format ("%H:%M") : then.format ("%e %b").strip ();
    }

    private static string length_text (int seconds) {
        return "%d:%02d".printf (seconds / 60, seconds % 60);
    }

    private void update_feed () {
        if (popover_widget == null) {
            return;
        }
        for (var child = feed_list.get_first_child (); child != null; child = feed_list.get_first_child ()) {
            feed_list.remove (child);
        }
        // (time, name, line, action label, action)
        var items = new GenericArray<FeedItem> ();
        for (size_t i = 0; feed_threads != null && i < feed_threads.n_children (); i++) {
            var thread = feed_threads.get_child_value (i);
            var unread = thread.lookup_value ("unread", VariantType.UINT32);
            var when = thread.lookup_value ("time", VariantType.INT64);
            var name = thread.lookup_value ("name", VariantType.STRING);
            var snippet = thread.lookup_value ("snippet", VariantType.STRING);
            if (unread == null || unread.get_uint32 () == 0 || when == null || name == null) {
                continue;
            }
            items.add (new FeedItem () {
                time = when.get_int64 (),
                name = name.get_string (),
                line = snippet != null ? snippet.get_string ().replace ("\n", " ") : "",
                action = _("Répondre"),
                number = ""
            });
        }
        var missed_wanted = (int) prop_number ("MissedCalls");
        for (size_t i = 0; feed_calls != null && missed_wanted > 0 && i < feed_calls.n_children (); i++) {
            var call = feed_calls.get_child_value (i);
            var kind = call.lookup_value ("kind", VariantType.STRING);
            var when = call.lookup_value ("time", VariantType.INT64);
            var name = call.lookup_value ("name", VariantType.STRING);
            var address = call.lookup_value ("address", VariantType.STRING);
            if (kind == null || kind.get_string () != "missed" || when == null) {
                continue;
            }
            missed_wanted--;
            var who = name != null && name.get_string () != "" ? name.get_string ()
                : address != null ? address.get_string () : "";
            items.add (new FeedItem () {
                time = when.get_int64 (),
                name = who,
                line = _("Appel manqué"),
                missed = true,
                action = _("Rappeler"),
                number = address != null ? address.get_string () : ""
            });
        }
        items.sort ((a, b) => (int) (b.time - a.time));
        for (int i = 0; i < items.length && i < 3; i++) {
            feed_list.append (feed_row (items[i]));
        }
        feed_box.visible = items.length > 0;
    }

    private class FeedItem : Object {
        public int64 time { get; set; }
        public string name { get; set; default = ""; }
        public string line { get; set; default = ""; }
        public string action { get; set; default = ""; }
        public string number { get; set; default = ""; }
        public bool missed { get; set; default = false; }
    }

    private Gtk.Widget feed_row (FeedItem item) {
        var avatar = new Gtk.Label (initials (item.name)) { width_request = 36, height_request = 36, valign = Gtk.Align.CENTER };
        avatar.add_css_class ("boomerang-avatar");
        var name = new Gtk.Label (item.name) { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
        name.add_css_class ("heading");
        var when = new Gtk.Label (time_text (item.time));
        when.add_css_class (Granite.CssClass.DIM);
        when.add_css_class (Granite.CssClass.SMALL);
        var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        top.append (name);
        top.append (when);
        var line = new Gtk.Label (item.line) { xalign = 0, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 24 };
        line.add_css_class (item.missed ? Granite.CssClass.ERROR : Granite.CssClass.DIM);
        var words = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
        words.append (top);
        words.append (line);
        var act = new Gtk.Button.with_label (item.action) { valign = Gtk.Align.CENTER };
        act.add_css_class ("boomerang-pill-button");
        act.add_css_class (item.missed ? "suggested-action" : "flat");
        var number = item.number;
        act.clicked.connect (() => {
            if (item.missed && number != "") {
                call_daemon ("Dial", new Variant ("(s)", number));
                close ();
            } else {
                launch (APP_ID);
            }
        });
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) { margin_top = 6, margin_bottom = 6 };
        row.append (avatar);
        row.append (words);
        row.append (act);
        return row;
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
            tips += levels != "" ? "%s : %s".printf (name, levels) : name;
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
        var segments = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { homogeneous = true, margin_start = 12, margin_end = 12, margin_top = 6 };
        segments.add_css_class ("linked");
        Gtk.ToggleButton? group = null;
        for (int i = 0; i < MODE_VALUES.length; i++) {
            if (!(MODE_FEATURES[i] in features_list)) {
                continue;
            }
            var check = new Gtk.ToggleButton.with_label (_(MODE_LABELS[i])) { active = MODE_VALUES[i] == mode };
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
            segments.append (check);
        }
        if (segments.get_first_child () != null) {
            row.append (segments);
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
        dot.visible = !connected;
        update_pill ();
        var name = prop_string ("DeviceName");
        display_widget.tooltip_text = call_state != "" ? null
            : connected ? _("%s connecté").printf (name != "" ? name : "iPhone")
                        : _("%s non connecté").printf (name != "" ? name : "iPhone");

        if (popover_widget == null) {
            return;
        }
        title.label = name != "" ? name : "iPhone";
        // Same words as the app's header (LinkText.vala), from the daemon's LinkState.
        var link = Boomerang.LinkText.describe (prop_string ("LinkState"), prop_string ("LinkProblem"), name);
        status.label = link.title;
        var level = connected ? (int) prop_number ("Battery", -1) : -1;
        battery_label.label = Boomerang.LinkText.battery (level);
        battery_label.visible = battery_bar.visible = level >= 0;
        battery_bar.value = level >= 0 ? level : 0;
        if (connected) {
            status_dot.remove_css_class ("boomerang-circle-orange");
            status_dot.add_css_class ("boomerang-circle-green");
        } else {
            status_dot.remove_css_class ("boomerang-circle-green");
            status_dot.add_css_class ("boomerang-circle-orange");
        }

        // Out of reach: what Boomerang does about it, in the words of the app's header.
        banner_box.visible = !connected;
        banner_label.label = link.detail != "" ? link.detail
            : _("Boomerang reconnecte l'iPhone dès qu'il revient près du PC. Vos messages déjà reçus restent consultables.");

        tiles_box.visible = connected;
        var tether = prop ("Tethering");
        tethering_on = tether != null && tether.is_of_type (VariantType.BOOLEAN) && tether.get_boolean ();
        tethering_button.visible = connected && has_method ("SetTethering") && module_added ("hotspot");
        set_tile (tethering_button, tethering_tile, tethering_on);
        var quiet = prop ("CallsQuiet");
        quiet_on = quiet != null && quiet.is_of_type (VariantType.BOOLEAN) && quiet.get_boolean ();
        quiet_button.visible = connected && has_method ("SetCallsQuiet");
        set_tile (quiet_button, quiet_tile, quiet_on);
        var mirror = prop ("Mirror");
        var running = mirror != null ? mirror.lookup_value ("running", VariantType.BOOLEAN) : null;
        mirror_on = running != null && running.get_boolean ();
        mirror_button.visible = connected && has_method ("StartMirror") && module_added ("mirror");
        set_tile (mirror_button, mirror_tile, mirror_on);
        var near = prop ("Proximity");
        var enabled = near != null ? near.lookup_value ("enabled", VariantType.BOOLEAN) : null;
        proximity_on = enabled != null && enabled.get_boolean ();
        proximity_button.visible = connected && has_method ("SetProximity") && module_added ("proximity")
                                   && near != null;
        set_tile (proximity_button, proximity_tile, proximity_on);
        tiles_box.visible = connected && (tethering_button.visible || quiet_button.visible
                                          || mirror_button.visible || proximity_button.visible);

        var track = media_string ("title");
        var playing = media_string ("status") == "playing";
        media_box.visible = connected && track != "";
        media_title.label = track;
        media_artist.label = media_string ("artist");
        media_artist.visible = media_artist.label != "";
        play_button.icon_name = playing ? "media-playback-pause-symbolic"
                                        : "media-playback-start-symbolic";
        play_button.tooltip_text = playing ? _("Pause") : _("Lecture");

        update_replies ();
        update_call_buttons ();
    }

    private void set_tile (Gtk.Button button, Gtk.Box circle, bool on) {
        if (on) {
            circle.add_css_class ("boomerang-circle-on");
        } else {
            circle.remove_css_class ("boomerang-circle-on");
        }
        button.update_state (Gtk.AccessibleState.PRESSED,
                             on ? Gtk.AccessibleTristate.TRUE : Gtk.AccessibleTristate.FALSE, -1);
    }

    /* The pill in the panel: the count of what is new, or the call (green, ringing or counting). */
    private void update_pill () {
        var calling = call_state != "";
        var news = (int) (prop_number ("UnreadMessages") + prop_number ("MissedCalls"));
        badge.visible = !calling && news > 0 && prop_bool ("Connected");
        badge.label = news > 99 ? "99+" : news.to_string ();
        panel_call.visible = calling;
        if (calling) {
            display_widget.add_css_class ("boomerang-pill-call");
            panel_call.label = ringing () ? (call_who != "" ? call_who : _("Appel entrant")) : length_text (call_seconds);
            display_widget.tooltip_text = ringing ()
                ? _("Appel entrant : %s").printf (call_who) : _("Appel en cours : %s").printf (call_who);
        } else {
            display_widget.remove_css_class ("boomerang-pill-call");
        }
        if (calling && ringing ()) {
            display_widget.add_css_class ("boomerang-pill-ringing");
        } else {
            display_widget.remove_css_class ("boomerang-pill-ringing");
        }
    }

    private bool ringing () {
        return call_state == "incoming" || call_state == "waiting";
    }

    /* The call's views: ringing, in progress, or none (the usual panel). */
    private void update_call () {
        if (call_state != "" && call_tick == 0) {
            call_tick = Timeout.add_seconds (1, () => {
                if (call_state == "") {
                    call_tick = 0;
                    return Source.REMOVE;
                }
                if (!ringing ()) {
                    call_seconds++;
                }
                update_pill ();
                update_call_texts ();
                return Source.CONTINUE;
            });
        }
        update_pill ();
        if (popover_widget == null) {
            return;
        }
        var is_ringing = ringing ();
        var in_call = call_state != "" && !is_ringing;
        normal_box.visible = call_state == "";
        incoming_box.visible = is_ringing;
        call_box.visible = in_call;
        headphones_box.visible = call_state == "" && headphones_box.get_first_child () != null;
        footer_call.visible = in_call;
        incoming_avatar.label = initials (call_who);
        incoming_name.label = call_who != "" ? call_who : "iPhone";
        incoming_kind.label = call_state == "waiting" ? _("Double appel") : _("Appel entrant");
        call_avatar.label = initials (call_who);
        call_name.label = call_who != "" ? call_who : "iPhone";
        update_call_texts ();
        update_call_buttons ();
        update_replies ();
    }

    private void update_call_texts () {
        if (popover_widget == null || call_state == "") {
            return;
        }
        call_status.label = ringing () ? "" : _("En communication · %s").printf (length_text (call_seconds));
    }

    private void update_call_buttons () {
        if (popover_widget == null) {
            return;
        }
        var muted = prop_bool ("MicMuted");
        var on_pc = prop_bool ("AudioOnPC");
        if (muted) {
            call_mic_circle.add_css_class ("boomerang-circle-on");
        } else {
            call_mic_circle.remove_css_class ("boomerang-circle-on");
        }
        if (on_pc) {
            call_pc_circle.add_css_class ("boomerang-circle-on");
        } else {
            call_pc_circle.remove_css_class ("boomerang-circle-on");
        }
        if (incoming_pc_sound.active != on_pc) {
            incoming_pc_sound.active = on_pc;
        }
    }

    /* « Refuser avec un message »: the quick replies of the Messages app, as the daemon has them. */
    private void update_replies () {
        if (popover_widget == null) {
            return;
        }
        for (var child = replies_box.get_first_child (); child != null; child = replies_box.get_first_child ()) {
            replies_box.remove (child);
        }
        var replies = prop ("QuickReplies");
        var shown = 0;
        for (size_t i = 0; replies != null && i < replies.n_children () && shown < 2; i++) {
            var text = replies.get_child_value (i).get_string ();
            if (text == "") {
                continue;
            }
            shown++;
            var button = new Gtk.Button.with_label (text);
            button.add_css_class ("boomerang-pill-button");
            button.clicked.connect (() => {
                if (call_path != "") {
                    call_daemon ("DeclineWithMessage", new Variant ("(os)", call_path, text));
                }
                close ();
            });
            replies_box.append (button);
        }
        var other = new Gtk.Button.with_label (_("Autre…"));
        other.add_css_class ("boomerang-pill-button");
        other.clicked.connect (() => launch (APP_ID));
        replies_box.append (other);
        replies_label.visible = replies_box.visible = has_method ("DeclineWithMessage");
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

    private Gtk.Label section_label (string text) {
        var label = new Gtk.Label (text.up ()) { xalign = 0, margin_start = 16, margin_end = 16, margin_bottom = 4 };
        label.add_css_class ("boomerang-section");
        label.add_css_class (Granite.CssClass.DIM);
        return label;
    }

    private Gtk.Separator rule () {
        return new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 6, margin_bottom = 6 };
    }

    /* A round button with its caption underneath; `circle` is the coloured disc to light up. */
    private Gtk.Button make_tile (string icon, string label, out Gtk.Box circle) {
        circle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { halign = Gtk.Align.CENTER };
        circle.add_css_class ("boomerang-circle");
        circle.append (new Gtk.Image.from_icon_name (icon) { pixel_size = 20, hexpand = true, halign = Gtk.Align.CENTER });
        var caption = new Gtk.Label (label) {
            wrap = true, justify = Gtk.Justification.CENTER, max_width_chars = 12, lines = 2
        };
        caption.add_css_class (Granite.CssClass.SMALL);
        var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        column.append (circle);
        column.append (caption);
        var button = new Gtk.Button () { child = column, hexpand = true };
        button.add_css_class ("flat");
        button.update_property (Gtk.AccessibleProperty.LABEL, label, -1);
        return button;
    }

    private Gtk.Box normal_box;
    private Gtk.Box footer_call;
    private Gtk.Label replies_label;

    private void build_popover () {
        // --- the usual panel: who, how the link is, then what can be done ---------------------
        var avatar = new Gtk.Image.from_icon_name ("phone-apple-iphone-symbolic") { pixel_size = 22, halign = Gtk.Align.CENTER, hexpand = true };
        var avatar_circle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER, width_request = 44, height_request = 44 };
        avatar_circle.add_css_class ("boomerang-avatar");
        avatar_circle.append (avatar);
        title = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        title.add_css_class ("heading");
        status_dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER, width_request = 8, height_request = 8 };
        status_dot.add_css_class ("boomerang-status-dot");
        status = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        status.add_css_class (Granite.CssClass.DIM);
        battery_label = new Gtk.Label ("") { visible = false };
        battery_label.add_css_class (Granite.CssClass.DIM);
        battery_label.add_css_class ("numeric");
        battery_bar = new Gtk.LevelBar.for_interval (0, 100) { width_request = 26, valign = Gtk.Align.CENTER, visible = false };
        var state_line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        state_line.append (status_dot);
        state_line.append (status);
        state_line.append (battery_label);
        state_line.append (battery_bar);
        var names = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
        names.append (title);
        names.append (state_line);
        var open_icon = new Gtk.Button.from_icon_name ("document-open-symbolic") { tooltip_text = _("Ouvrir Boomerang"), valign = Gtk.Align.CENTER };
        open_icon.add_css_class ("flat");
        open_icon.add_css_class (Granite.CssClass.CIRCULAR);
        open_icon.clicked.connect (() => launch (APP_ID));
        header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { margin_start = 16, margin_end = 12, margin_top = 14, margin_bottom = 10 };
        header_box.append (avatar_circle);
        header_box.append (names);
        header_box.append (open_icon);

        banner_label = new Gtk.Label ("") { xalign = 0, wrap = true, max_width_chars = 36 };
        var reconnect = new Gtk.Button.with_label (_("Reconnecter maintenant"));
        reconnect.add_css_class ("boomerang-pill-button");
        reconnect.clicked.connect (() => call_daemon ("Reconnect"));
        var what = new Gtk.Button.with_label (_("Que se passe-t-il ?"));
        what.add_css_class ("boomerang-pill-button");
        what.add_css_class ("flat");
        what.clicked.connect (() => launch (APP_ID));
        var banner_buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { margin_top = 8 };
        banner_buttons.append (reconnect);
        banner_buttons.append (what);
        banner_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { margin_start = 16, margin_end = 16, margin_bottom = 10, visible = false };
        banner_box.add_css_class ("boomerang-banner");
        banner_label.margin_start = banner_label.margin_end = banner_label.margin_top = 12;
        banner_buttons.margin_start = banner_buttons.margin_end = banner_buttons.margin_bottom = 12;
        banner_box.append (banner_label);
        banner_box.append (banner_buttons);

        tethering_button = make_tile ("network-wireless-hotspot-symbolic", _("Partage de connexion"), out tethering_tile);
        tethering_button.visible = false;
        tethering_button.clicked.connect (() => {
            call_daemon ("SetTethering", new Variant ("(b)", !tethering_on));
            close ();
        });
        quiet_button = make_tile ("notification-disabled-symbolic", _("Appels en silence"), out quiet_tile);
        quiet_button.visible = false;
        quiet_button.clicked.connect (() => call_daemon ("SetCallsQuiet", new Variant ("(b)", !quiet_on)));
        mirror_button = make_tile ("video-display-symbolic", _("Recopie de l'écran"), out mirror_tile);
        mirror_button.visible = false;
        mirror_button.clicked.connect (() => {
            call_daemon (mirror_on ? "StopMirror" : "StartMirror");
            close ();
        });
        proximity_button = make_tile ("changes-prevent-symbolic", _("Verrouillage de proximité"), out proximity_tile);
        proximity_button.visible = false;
        proximity_button.clicked.connect (() => {
            var near = prop ("Proximity");
            var distance = near != null ? near.lookup_value ("distance", VariantType.STRING) : null;
            var delay = near != null ? near.lookup_value ("delay", VariantType.UINT32) : null;
            if (distance != null && delay != null) {
                call_daemon ("SetProximity", new Variant ("(bsu)", !proximity_on, distance.get_string (), delay.get_uint32 ()));
            }
        });
        tiles_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) { homogeneous = true, margin_start = 12, margin_end = 12, margin_bottom = 10, visible = false };
        tiles_box.append (tethering_button);
        tiles_box.append (quiet_button);
        tiles_box.append (mirror_button);
        tiles_box.append (proximity_button);

        // What is playing on the iPhone (AMS), with the three usual buttons.
        media_title = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 28 };
        media_title.add_css_class ("heading");
        media_artist = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 28 };
        media_artist.add_css_class (Granite.CssClass.DIM);
        var words = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
        words.append (media_title);
        words.append (media_artist);
        play_button = media_control ("media-playback-start-symbolic", _("Lecture"), "toggle");
        var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
        controls.append (media_control ("media-skip-backward-symbolic", _("Précédent"), "previous"));
        controls.append (play_button);
        controls.append (media_control ("media-skip-forward-symbolic", _("Suivant"), "next"));
        var media_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { margin_start = 16, margin_end = 10 };
        media_row.append (words);
        media_row.append (controls);
        media_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        media_box.append (rule ());
        media_box.append (section_label (_("Lecture en cours")));
        media_box.append (media_row);

        var see_all = new Gtk.Button.with_label (_("Tout voir"));
        see_all.add_css_class ("flat");
        see_all.add_css_class (Granite.CssClass.SMALL);
        see_all.clicked.connect (() => launch (APP_ID));
        var feed_head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { margin_end = 10 };
        var feed_title = section_label (_("À rattraper"));
        feed_title.hexpand = true;
        feed_title.margin_bottom = 0;
        feed_head.append (feed_title);
        feed_head.append (see_all);
        feed_list = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { margin_start = 16, margin_end = 16 };
        feed_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        feed_box.append (rule ());
        feed_box.append (feed_head);
        feed_box.append (feed_list);

        normal_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        normal_box.append (header_box);
        normal_box.append (banner_box);
        normal_box.append (tiles_box);
        normal_box.append (media_box);
        normal_box.append (feed_box);

        // --- a call ringing: who, answer or decline, decline with a message ---------------------
        incoming_avatar = new Gtk.Label ("") { width_request = 64, height_request = 64, halign = Gtk.Align.CENTER };
        incoming_avatar.add_css_class ("boomerang-avatar");
        incoming_avatar.add_css_class ("title-2");
        incoming_name = new Gtk.Label ("") { margin_top = 10 };
        incoming_name.add_css_class ("title-3");
        incoming_kind = new Gtk.Label ("");
        incoming_kind.add_css_class (Granite.CssClass.DIM);
        var decline = new Gtk.Button.with_label (_("Refuser")) { hexpand = true, height_request = 44 };
        decline.add_css_class (Granite.CssClass.DESTRUCTIVE);
        decline.add_css_class ("boomerang-pill-button");
        decline.clicked.connect (() => {
            if (call_path != "") {
                call_daemon ("CallAction", new Variant ("(os)", call_path, "hangup"));
            }
        });
        var answer = new Gtk.Button.with_label (_("Répondre")) { hexpand = true, height_request = 44 };
        answer.add_css_class ("suggested-action");
        answer.add_css_class ("boomerang-pill-button");
        answer.clicked.connect (() => {
            if (call_path != "") {
                call_daemon ("CallAction", new Variant ("(os)", call_path, "answer"));
            }
        });
        var answer_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) { margin_top = 18, homogeneous = true };
        answer_row.append (decline);
        answer_row.append (answer);
        incoming_pc_sound = new Gtk.CheckButton.with_label (_("Son sur ce PC")) { halign = Gtk.Align.CENTER, margin_top = 12 };
        incoming_pc_sound.toggled.connect (() => {
            if (incoming_pc_sound.active != prop_bool ("AudioOnPC")) {
                call_daemon ("SetCallAudio", new Variant ("(b)", incoming_pc_sound.active));
            }
        });
        var incoming_top = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { margin_start = 16, margin_end = 16, margin_top = 20, margin_bottom = 12 };
        incoming_top.append (incoming_avatar);
        incoming_top.append (incoming_name);
        incoming_top.append (incoming_kind);
        incoming_top.append (answer_row);
        incoming_top.append (incoming_pc_sound);
        replies_label = section_label (_("Refuser avec un message"));
        replies_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { margin_start = 16, margin_end = 16, margin_bottom = 14 };
        incoming_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        incoming_box.append (incoming_top);
        incoming_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        incoming_box.append (replies_label);
        incoming_box.append (replies_box);

        // --- a call in progress: who and how long, mute, sound on this PC, hang up -----------------
        call_avatar = new Gtk.Label ("") { width_request = 48, height_request = 48 };
        call_avatar.add_css_class ("boomerang-avatar");
        call_avatar.add_css_class ("title-4");
        call_name = new Gtk.Label ("") { xalign = 0 };
        call_name.add_css_class ("title-4");
        call_status = new Gtk.Label ("") { xalign = 0 };
        call_status.add_css_class ("numeric");
        var call_words = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
        call_words.append (call_name);
        call_words.append (call_status);
        var call_head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        call_head.append (call_avatar);
        call_head.append (call_words);
        var mic = make_tile ("microphone-sensitivity-muted-symbolic", _("Couper le micro"), out call_mic_circle);
        mic.clicked.connect (() => call_daemon ("SetMuted", new Variant ("(b)", !prop_bool ("MicMuted"))));
        Gtk.Box pc_circle;
        var on_pc = make_tile ("audio-speakers-symbolic", _("Son sur ce PC"), out pc_circle);
        call_pc_circle = pc_circle;
        on_pc.clicked.connect (() => call_daemon ("SetCallAudio", new Variant ("(b)", !prop_bool ("AudioOnPC"))));
        Gtk.Box stop_circle;
        var stop = make_tile ("call-stop-symbolic", _("Raccrocher"), out stop_circle);
        stop_circle.add_css_class ("boomerang-circle-red");
        stop.clicked.connect (() => {
            if (call_path != "") {
                call_daemon ("CallAction", new Variant ("(os)", call_path, "hangup"));
            }
        });
        var call_tiles = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) { homogeneous = true, margin_top = 14 };
        call_tiles.append (mic);
        call_tiles.append (on_pc);
        call_tiles.append (stop);
        var call_top = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { margin_start = 16, margin_end = 16, margin_top = 16, margin_bottom = 12 };
        call_top.add_css_class ("boomerang-in-call");
        call_top.append (call_head);
        call_top.append (call_tiles);
        // The wrapper keeps the green band edge to edge while the contents keep their margins.
        outputs_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { margin_start = 16, margin_end = 16, margin_top = 4, margin_bottom = 8, visible = false };
        call_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        call_box.append (call_top);
        call_box.append (rule ());
        call_box.append (section_label (_("Sortie du son")));
        call_box.append (outputs_box);

        headphones_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };

        var open = menu_button (_("Ouvrir Boomerang"));
        open.clicked.connect (() => launch (APP_ID));
        var show_call = menu_button (_("Afficher la fenêtre d'appel"));
        show_call.clicked.connect (() => launch (APP_ID));
        footer_call = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        footer_call.append (show_call);

        popover_widget = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 360 };
        popover_widget.append (normal_box);
        popover_widget.append (incoming_box);
        popover_widget.append (call_box);
        popover_widget.append (headphones_box);
        popover_widget.append (rule ());
        popover_widget.append (footer_call);
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
