# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Sound of the iPhone on the PC (A2DP: the iPhone is the source, the PC the sink).

PipeWire plays the iPhone's stream (bluez_input.<address>) on the default
output. Boomerang adds two settings:

- receive: when off, the A2DP link is dropped whenever the iPhone opens it,
  so video or music stays on the iPhone. HFP (calls) is left alone.
- output: a PipeWire sink name, or "" for the default output. It is applied
  through the "default" metadata (target.object) each time the stream appears,
  since the node is created again on every connection.

The iPhone can also pick its output itself (AirPlay button in Control Center).
"""

import json
import subprocess

from gi.repository import Gio, GLib

from .util import BLUEZ, call_async, log

TRANSPORT = "org.bluez.MediaTransport1"
A2DP_SINK = "0000110b-0000-1000-8000-00805f9b34fb"    # our endpoint: we receive
A2DP_SOURCE = "0000110a-0000-1000-8000-00805f9b34fb"  # the iPhone's role
ROUTE_ATTEMPTS = 10  # the PipeWire node shows up a moment after the transport


def _nodes(dump):
    try:
        objects = json.loads(dump or "[]")
    except ValueError:
        return []
    return [o for o in objects if o.get("type") == "PipeWire:Interface:Node"]


def pw_nodes():
    try:
        out = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    return _nodes(out)


def _sinks(nodes):
    """PipeWire sinks of the PC (not Bluetooth ones): [(name, description)]."""
    found = []
    for node in nodes:
        props = node.get("info", {}).get("props", {})
        if props.get("media.class") == "Audio/Sink" and props.get("device.api") != "bluez5":
            name = props.get("node.name", "")
            found.append((name, props.get("node.description") or name))
    return found


def run_async(argv, on_done, timeout=5):
    """Run a command off the main loop: on_done(stdout) once it exits, None if it could not
    run or took more than timeout seconds (it is then killed)."""
    try:
        process = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE
                                     | Gio.SubprocessFlags.STDERR_SILENCE)
    except GLib.Error:
        on_done(None)
        return
    cancel = Gio.Cancellable()
    timer = GLib.timeout_add_seconds(timeout, lambda: cancel.cancel() or process.force_exit()
                                     or False)

    def finished(proc, result):
        if not cancel.is_cancelled():
            GLib.source_remove(timer)
        try:
            _ok, out, _err = proc.communicate_utf8_finish(result)
        except GLib.Error:
            out = None
        on_done(out)

    process.communicate_utf8_async(None, cancel, finished)


def default_sink_name():
    try:
        out = subprocess.run(["pw-metadata", "-n", "default", "0", "default.audio.sink"],
                             capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""
    # update: id:0 key:'default.audio.sink' value:'{"name":"..."}' type:'Spa:String:JSON'
    start = out.find("value:'")
    if start < 0:
        return ""
    try:
        return json.loads(out[start + 7:out.index("'", start + 7)]).get("name", "")
    except ValueError:
        return ""


class PhoneAudio:
    def __init__(self, system, config, on_change):
        self.bus = system
        self.config = config
        self.on_change = on_change
        self.transports = {}  # path -> MediaTransport1 properties (our A2DP sink only)
        self.device = None    # BlueZ path of the iPhone
        self.routed = None    # node id the output was applied to
        self.route_timer = 0
        self.routing = False  # a pw-dump / pw-metadata is running
        self.reroute = False  # the output changed while it ran
        for member, handler in (("InterfacesAdded", self._on_added),
                                ("InterfacesRemoved", self._on_removed)):
            system.signal_subscribe(BLUEZ, "org.freedesktop.DBus.ObjectManager", member,
                                    None, None, Gio.DBusSignalFlags.NONE, handler)
        system.signal_subscribe(BLUEZ, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                None, TRANSPORT, Gio.DBusSignalFlags.NONE, self._on_changed)
        call_async(system, BLUEZ, "/", "org.freedesktop.DBus.ObjectManager",
                   "GetManagedObjects", None, self._on_objects)

    # --- settings ----------------------------------------------------------------------

    @property
    def receive(self):
        return self.config.boolean("audio", "receive", True)

    @property
    def output(self):
        try:
            return self.config.keyfile.get_string("audio", "output")
        except GLib.Error:
            return ""

    def set_receive(self, receive):
        self.config.keyfile.set_boolean("audio", "receive", receive)
        self.config.save()
        log(f"son de l'iPhone sur le PC {'autorisé' if receive else 'refusé'}")
        if self.device:
            method = "ConnectProfile" if receive else "DisconnectProfile"
            call_async(self.bus, BLUEZ, self.device, "org.bluez.Device1", method,
                       GLib.Variant("(s)", (A2DP_SOURCE,)), what=f"son de l'iPhone ({method})")
        self.on_change()

    def set_output(self, name):
        self.config.keyfile.set_string("audio", "output", name)
        self.config.save()
        self.routed = None
        if self.routing:
            self.reroute = True  # applied once the running attempt is over
        else:
            self._route()
        self.on_change()

    def outputs(self):
        """Sinks of the PC (not Bluetooth ones), the default first."""
        default = default_sink_name()
        sinks = [{"name": name, "description": description, "default": name == default}
                 for name, description in _sinks(pw_nodes())]
        sinks.sort(key=lambda s: (not s["default"], s["description"]))
        return sinks

    def state(self):
        """off (refused), idle (allowed, nothing playing) or playing."""
        if not self.receive:
            return "off"
        return "playing" if any(p.get("State") == "active" for p in self._mine()) else "idle"

    # --- device ------------------------------------------------------------------------

    def set_device(self, path):
        self.device = path
        self._enforce()
        self.on_change()

    def _mine(self):
        return [p for p in self.transports.values() if p.get("Device") == self.device]

    def _enforce(self):
        """Receiving refused: drop the A2DP link as soon as the iPhone opens it."""
        if not self.receive and self.device and self._mine():
            log("son de l'iPhone refusé : liaison A2DP fermée")
            call_async(self.bus, BLUEZ, self.device, "org.bluez.Device1", "DisconnectProfile",
                       GLib.Variant("(s)", (A2DP_SOURCE,)), what="son de l'iPhone")

    # --- BlueZ signals -----------------------------------------------------------------

    def _on_objects(self, value, error):
        if error:
            return
        for path, interfaces in value.unpack()[0].items():
            self._add(path, interfaces)

    def _on_added(self, _conn, _sender, _path, _iface, _signal, params):
        path, interfaces = params.unpack()
        self._add(path, interfaces)

    def _add(self, path, interfaces):
        props = interfaces.get(TRANSPORT)
        if props is None or props.get("UUID") != A2DP_SINK:
            return
        self.transports[path] = props
        if props.get("Device") == self.device:
            self._enforce()
            self._schedule_route()
        self.on_change()

    def _on_removed(self, _conn, _sender, path, _iface, _signal, params):
        _path, interfaces = params.unpack()
        if TRANSPORT in interfaces and self.transports.pop(path, None) is not None:
            self.routed = None
            self.on_change()

    def _on_changed(self, _conn, _sender, path, _iface, _signal, params):
        if path not in self.transports:
            return
        _iface_name, changed, _invalid = params.unpack()
        self.transports[path].update(changed)
        if "State" in changed:
            if changed["State"] in ("pending", "active"):
                self._schedule_route()
            self.on_change()

    # --- routing -----------------------------------------------------------------------

    def _schedule_route(self):
        """Look for the iPhone's PipeWire node every 500 ms, ten times at most. pw-dump and
        pw-metadata run off the main loop: one attempt at a time."""
        if self.route_timer or self.routing:
            return

        def attempt(left):
            self.route_timer = 0

            def done(found):
                if not found and left > 1:
                    self.route_timer = GLib.timeout_add(500, lambda: attempt(left - 1) or False)

            self._route(done)

        self.route_timer = GLib.timeout_add(500, lambda: attempt(ROUTE_ATTEMPTS) or False)

    def _stream_node(self, nodes):
        if not self.device:
            return None
        address = self.device.rsplit("dev_", 1)[-1]  # AA_BB_CC_...
        for node in nodes:
            name = node.get("info", {}).get("props", {}).get("node.name", "")
            if name.startswith("bluez_input." + address):
                return node["id"]
        return None

    def _route(self, on_done=lambda found: None):
        """Point the iPhone stream at the chosen output; on_done(True) once the node was found."""
        self.routing = True

        def finish(found):
            self.routing = False
            if self.reroute:
                self.reroute, self.routed = False, None
                self._route(on_done)
            else:
                on_done(found)

        def dumped(out):
            nodes = _nodes(out)
            node = self._stream_node(nodes)
            if node is None:
                return finish(False)
            if node == self.routed:
                return finish(True)
            output = self.output
            if output and output not in (name for name, _desc in _sinks(nodes)):
                output = ""  # unplugged device: fall back to the default output
            if output:
                args = ["pw-metadata", "-n", "default", str(node), "target.object", output]
            else:
                args = ["pw-metadata", "-n", "default", "-d", str(node), "target.object"]

            def applied(result):
                if result is None:
                    log("son de l'iPhone : sortie non appliquée")
                else:
                    self.routed = node
                finish(True)

            run_async(args, applied)

        run_async(["pw-dump"], dumped)
