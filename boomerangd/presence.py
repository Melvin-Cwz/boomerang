# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Presence: notice the iPhone coming back in range.

An iPhone keeps sending Apple LE advertisements (manufacturer data 0x004C) whenever
Bluetooth is on. Their private addresses do not resolve with the IRK of the bond
(checked: none matched), so BlueZ cannot tell our iPhone from another
Apple device. An Apple device close by is therefore only a hint: the link tries to
reconnect then (at most once a minute) instead of waiting for the next tick of the
back-off (up to 5 min). Should the address ever resolve, the bonded device path
comes back and the link treats it as a sure sighting.

The monitor runs only while the iPhone is away: once linked, it is unregistered and
the radio no longer scans. BlueZ exposes AdvertisementMonitorManager1 only with
« Experimental = true » in /etc/bluetooth/main.conf; without it, presence stays off
and the back-off alone brings the iPhone back.
"""

from gi.repository import Gio, GLib

from .util import BLUEZ, call_async, log

ROOT_PATH = "/io/github/melvincouwez/Boomerang/monitors"
MONITOR_PATH = ROOT_PATH + "/apple"
MANAGER = "org.bluez.AdvertisementMonitorManager1"
APPLE_PATTERN = (0, 0xFF, b"\x4c\x00")  # start, AD type (manufacturer data), Apple id
# Found above -75 dBm (same room) for 1 s; lost under -100 dBm (or silent) for 30 s.
RSSI = {"RSSIHighThreshold": ("n", -75), "RSSIHighTimeout": ("q", 1),
        "RSSILowThreshold": ("n", -100), "RSSILowTimeout": ("q", 30)}

MONITOR_XML = """
<node>
  <interface name="org.bluez.AdvertisementMonitor1">
    <method name="Release"/>
    <method name="Activate"/>
    <method name="DeviceFound"><arg type="o" direction="in"/></method>
    <method name="DeviceLost"><arg type="o" direction="in"/></method>
    <property name="Type" type="s" access="read"/>
    <property name="Patterns" type="a(yyay)" access="read"/>
    <property name="RSSIHighThreshold" type="n" access="read"/>
    <property name="RSSIHighTimeout" type="q" access="read"/>
    <property name="RSSILowThreshold" type="n" access="read"/>
    <property name="RSSILowTimeout" type="q" access="read"/>
  </interface>
</node>
"""

MANAGER_XML = """
<node>
  <interface name="org.freedesktop.DBus.ObjectManager">
    <method name="GetManagedObjects">
      <arg type="a{oa{sa{sv}}}" direction="out"/>
    </method>
  </interface>
</node>
"""


def supported(bus, adapter):
    """True when bluetoothd exposes advertisement monitors on this adapter."""
    try:
        bus.call_sync(BLUEZ, adapter, "org.freedesktop.DBus.Properties", "Get",
                      GLib.Variant("(ss)", (MANAGER, "SupportedMonitorTypes")),
                      None, Gio.DBusCallFlags.NONE, 2000, None)
        return True
    except GLib.Error:
        return False


class Presence:
    """on_found(path) / on_lost(path) receive BlueZ device paths of Apple devices."""

    def __init__(self, bus, on_found, on_lost):
        self.bus = bus
        self.on_found = on_found
        self.on_lost = on_lost
        self.adapter = None
        self.registrations = []
        self.active = False  # registered with BlueZ (or registration in progress)
        self.unsupported = False  # checked once per adapter

    def _props(self):
        values = {"Type": GLib.Variant("s", "or_patterns"),
                  "Patterns": GLib.Variant("a(yyay)", [APPLE_PATTERN])}
        values.update({k: GLib.Variant(t, v) for k, (t, v) in RSSI.items()})
        return values

    def _export(self):
        if self.registrations:
            return
        monitor = Gio.DBusNodeInfo.new_for_xml(MONITOR_XML).interfaces[0]
        manager = Gio.DBusNodeInfo.new_for_xml(MANAGER_XML).interfaces[0]
        self.registrations = [
            self.bus.register_object(MONITOR_PATH, monitor, self._monitor_method,
                                     lambda *a: self._props()[a[-1]], None),
            self.bus.register_object(ROOT_PATH, manager, self._manager_method, None, None),
        ]

    def _manager_method(self, _conn, _sender, _path, _iface, _method, _params, invocation):
        invocation.return_value(GLib.Variant(
            "(a{oa{sa{sv}}})", ({MONITOR_PATH: {"org.bluez.AdvertisementMonitor1": self._props()}},)))

    def _monitor_method(self, _conn, _sender, _path, _iface, method, params, invocation):
        if method == "DeviceFound":
            self.on_found(params.unpack()[0])
        elif method == "DeviceLost":
            self.on_lost(params.unpack()[0])
        elif method == "Release":
            self.active = False  # BlueZ dropped us (adapter off): start() registers again
        invocation.return_value(None)

    def start(self, adapter):
        if adapter == self.adapter and (self.active or self.unsupported):
            return
        self.adapter = adapter
        self.unsupported = not supported(self.bus, adapter)
        if self.unsupported:
            log("présence : indisponible (Experimental = true absent de /etc/bluetooth/main.conf)")
            return
        self._export()
        self.active = True

        def done(_value, error):
            if error and "AlreadyExists" in error.message:
                self.active = True  # an earlier call registered it meanwhile
            elif error:
                self.active = False
                log(f"présence : moniteur refusé ({error.message})")
            else:
                log("présence : à l'écoute de l'iPhone")

        call_async(self.bus, BLUEZ, adapter, MANAGER, "RegisterMonitor",
                   GLib.Variant("(o)", (ROOT_PATH,)), on_done=done)

    def stop(self):
        if self.active and self.adapter:
            call_async(self.bus, BLUEZ, self.adapter, MANAGER, "UnregisterMonitor",
                       GLib.Variant("(o)", (ROOT_PATH,)))
        self.active = False

    def forget_bus(self):
        """BlueZ went away: our registration died with it."""
        self.active = self.unsupported = False
        self.adapter = None
