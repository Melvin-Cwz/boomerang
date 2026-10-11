// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Client of the boomerangd session bus API. Properties are read from the proxy
 * cache, which GDBus keeps current from PropertiesChanged.
 *
 * changed is emitted once per PropertiesChanged (and when the daemon comes or goes).
 * A handler that follows a few properties starts with touched ({ ... }): the battery,
 * media position or a transfer's progress no longer run every view's update.
 */

public class Boomerang.Daemon : Object {
    public const string NAME = "io.github.melvincouwez.Boomerang.Daemon";
    public const string PATH = "/io/github/melvincouwez/Boomerang/Daemon";
    public const string IFACE = "io.github.melvincouwez.Boomerang1";

    public signal void changed ();
    public signal void pairing_code (uint passkey);
    public signal void pairing_code_answered (bool matches);
    public signal void threads_changed ();
    public signal void calls_changed ();
    public signal void active_calls_changed ();
    public signal void notifications_changed ();
    public signal void contacts_changed ();
    public signal void headphones_changed ();
    public signal void message_received (string thread, string id);
    public signal void send_progress (string thread, string id, double fraction);

    private DBusProxy? proxy = null;
    // Properties of the PropertiesChanged being handled; null: all of them (daemon came or went).
    private GenericSet<string>? batch = null;

    /* Inside a changed handler: whether one of these properties may have changed. An empty
       list answers true only when the daemon itself came or went. */
    public bool touched (string[] names) {
        if (batch == null) {
            return true;
        }
        foreach (var name in names) {
            if (batch.contains (name)) {
                return true;
            }
        }
        return false;
    }

    public bool running {
        get { return proxy != null && proxy.g_name_owner != null; }
    }

    public async void connect_bus () {
        try {
            // Without DO_NOT_AUTO_START the bus starts boomerangd through its service file.
            // Development: BOOMERANG_DAEMON_NAME points the app at a stand-in daemon (demo screenshots).
            var name = Environment.get_variable ("BOOMERANG_DAEMON_NAME") ?? NAME;
            proxy = yield new DBusProxy.for_bus (
                BusType.SESSION, DBusProxyFlags.NONE, null, name, PATH, IFACE, null
            );
            proxy.g_properties_changed.connect ((changed_properties, invalidated) => {
                batch = new GenericSet<string> (str_hash, str_equal);
                var iter = changed_properties.iterator ();
                string key;
                Variant value;
                while (iter.next ("{sv}", out key, out value)) {
                    batch.add (key);
                }
                foreach (var gone in invalidated) {
                    batch.add (gone);
                }
                changed ();
                batch = null;
            });
            proxy.notify["g-name-owner"].connect (() => changed ());
            proxy.g_signal.connect ((sender, signal_name, parameters) => {
                if (signal_name == "PairingCode") {
                    uint32 passkey;
                    parameters.get ("(u)", out passkey);
                    pairing_code (passkey);
                } else if (signal_name == "PairingCodeAnswered") {
                    bool matches;
                    parameters.get ("(b)", out matches);
                    pairing_code_answered (matches);
                } else if (signal_name == "ThreadsChanged") {
                    threads_changed ();
                } else if (signal_name == "CallsChanged") {
                    calls_changed ();
                } else if (signal_name == "ActiveCallsChanged") {
                    active_calls_changed ();
                } else if (signal_name == "HeadphonesChanged") {
                    headphones_changed ();
                } else if (signal_name == "ContactsChanged") {
                    contacts_changed ();
                } else if (signal_name == "NotificationsChanged") {
                    notifications_changed ();
                } else if (signal_name == "SendProgress") {
                    string thread, id;
                    double fraction;
                    parameters.get ("(ssd)", out thread, out id, out fraction);
                    send_progress (thread, id, fraction);
                } else if (signal_name == "MessageReceived") {
                    string thread, id;
                    parameters.get ("(ss)", out thread, out id);
                    message_received (thread, id);
                }
            });
        } catch (Error e) {
            warning ("boomerangd unreachable: %s", e.message);
        }
        changed ();
    }

    private Variant? prop (string name) {
        return proxy != null ? proxy.get_cached_property (name) : null;
    }

    /* A dictionary property (a{sv}), or null. */
    public Variant? get_value (string name) {
        return prop (name);
    }

    public bool get_bool (string name) {
        var v = prop (name);
        return v != null && v.get_boolean ();
    }

    public string get_string (string name) {
        var v = prop (name);
        return v != null ? v.get_string () : "";
    }

    public uint get_uint (string name) {
        var v = prop (name);
        return v != null ? v.get_uint32 () : 0;
    }

    public int get_int (string name, int fallback = -1) {
        var v = prop (name);
        return v != null ? v.get_int32 () : fallback;
    }

    public bool module_enabled (string module) {
        var v = prop ("Modules");
        if (v == null) {
            return false;
        }
        var enabled = v.lookup_value (module, VariantType.BOOLEAN);
        return enabled == null || enabled.get_boolean ();
    }

    /* Experimental features chosen in Réglages (AlphaFeatures), all off by default. */
    public bool alpha_enabled (string feature) {
        var v = prop ("AlphaFeatures");
        if (v == null) {
            return false;
        }
        var enabled = v.lookup_value (feature, VariantType.BOOLEAN);
        return enabled != null && enabled.get_boolean ();
    }

    /* The Sync button: number of new messages, or the daemon's error. */
    public async uint sync_all () throws Error {
        if (proxy == null) {
            throw new IOError.NOT_CONNECTED ("Boomerang ne répond pas");
        }
        var reply = yield proxy.call ("Sync", null, DBusCallFlags.NONE, 180000, null);
        return reply.get_child_value (0).get_uint32 ();
    }

    public async bool call (string method, Variant? args = null) {
        if (proxy == null) {
            return false;
        }
        try {
            yield proxy.call (method, args, DBusCallFlags.NONE, 10000, null);
            return true;
        } catch (Error e) {
            warning ("%s failed: %s", method, e.message);
            return false;
        }
    }

    /* Methods returning an array of a{sv} (ListThreads, GetMessages). */
    public async Variant[] call_list (string method, Variant? args = null) {
        bool ok;
        return yield try_list (method, args, out ok);
    }

    /* Same, telling a failed call (daemon restarting, timeout: ok = false) from an empty
       list, so a view keeps what it shows instead of wiping it. */
    public async Variant[] try_list (string method, Variant? args, out bool ok) {
        Variant[] items = {};
        ok = false;
        if (proxy == null) {
            return items;
        }
        try {
            var reply = yield proxy.call (method, args, DBusCallFlags.NONE, 15000, null);
            var array = reply.get_child_value (0);
            for (size_t i = 0; i < array.n_children (); i++) {
                items += array.get_child_value (i);
            }
            ok = true;
        } catch (Error e) {
            warning ("%s failed: %s", method, e.message);
        }
        return items;
    }

    /* Any method, errors passed on to the caller (contact editing shows them). */
    public async Variant call_checked (string method, Variant? args = null) throws Error {
        if (proxy == null) {
            throw new IOError.NOT_CONNECTED ("Boomerang ne répond pas");
        }
        return yield proxy.call (method, args, DBusCallFlags.NONE, 60000, null);
    }

    /* Methods returning one a{sv} (OpenConversation). */
    public async Variant? call_dict (string method, Variant? args = null) {
        if (proxy == null) {
            return null;
        }
        try {
            var reply = yield proxy.call (method, args, DBusCallFlags.NONE, 15000, null);
            return reply.get_child_value (0);
        } catch (Error e) {
            warning ("%s failed: %s", method, e.message);
            return null;
        }
    }

    /* SendMessage / RetryMessage: true on success. They can take a while. */
    public async bool call_send (string method, Variant args) {
        if (proxy == null) {
            return false;
        }
        try {
            yield proxy.call (method, args, DBusCallFlags.NONE, 90000, null);
            return true;
        } catch (Error e) {
            warning ("%s failed: %s", method, e.message);
            return false;
        }
    }

    public void set_module_enabled (string module, bool enabled) {
        call.begin ("SetModuleEnabled", new Variant ("(sb)", module, enabled));
    }
}
