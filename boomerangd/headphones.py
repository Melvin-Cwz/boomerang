# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
# SPDX-FileCopyrightText: 2025 LibrePods contributors
#
# Contains a Python rewrite (modified by MelvinCwz, 2026) of parts of
# LibrePods (https://github.com/librepods-org/librepods): linux/airpods_packets.h,
# linux/main.cpp, docs/AAP Definitions.md, docs/control_commands.md, and of the
# head gestures of the Android app (utils/GestureDetector.kt, utils/HeadOrientation.kt,
# bluetooth/AACPManager.kt).
"""AirPods (and compatible Apple headphones) control: battery, ear detection,
listening modes, conversation awareness, name, and head gestures to answer a
call (experimental: nod to answer, shake to decline).

The protocol (AAP, over L2CAP PSM 0x1001 of the classic Bluetooth link) and
the packet formats come from LibrePods (https://github.com/librepods-org/librepods,
GPL-3.0-or-later), by Kavish Devar and the LibrePods contributors, whose
documentation (docs/AAP Definitions.md, docs/control_commands.md) and Linux
implementation (linux/airpods_packets.h, linux/main.cpp) this module follows.
Thank you to them for this remarkable work. Boomerang is not affiliated with
LibrePods nor with Apple; "AirPods" only names the headphones it works with.

Only the regular Bluetooth link is used: no root, no change to BlueZ's
configuration, no impersonation of an Apple device (features that need it,
such as multipoint or loud sound reduction, are left out).

Settings the AirPods cannot report back (long-press cycle) are kept in
boomerangd.conf and written again on each connection, as LibrePods advises.
"""

import socket
import threading
import time

from gi.repository import Gio, GLib

from .i18n import N_
from .util import BLUEZ, log

PSM = 0x1001
AAP_UUID = "74ec2172-0bad-4d01-8f77-997b2be0722a"
APPLE = "v004C"

# Connection sequence (linux/airpods_packets.h)
HANDSHAKE = bytes.fromhex("00000400010002000000000000000000")
SET_SPECIFIC_FEATURES = bytes.fromhex("040004004d00d700000000000000")
REQUEST_NOTIFICATIONS = bytes.fromhex("040004000f00ffffffffff")
HANDSHAKE_ACK = bytes.fromhex("01000400")
FEATURES_ACK = bytes.fromhex("040004002b00")

HEADER = bytes.fromhex("04000400")
OP_BATTERY, OP_EAR, OP_CONTROL, OP_METADATA, OP_CONVERSATION = 0x04, 0x06, 0x09, 0x1D, 0x4B
OP_HEAD = 0x17

# Head tracking (LibrePods, bluetooth/AACPManager.kt: the "alternate" start and stop
# packets, the ones the Android app sends by default). While it runs, the AirPods
# stream motion packets of 70 bytes or more; the accelerations used for gestures are
# little-endian signed 16-bit values at offsets 51 (horizontal) and 53 (vertical).
HEAD_START = HEADER + bytes.fromhex("170000001000 0f00 0873 420b 0810 1002 1a05 0140 9c00 00".replace(" ", ""))
HEAD_STOP = HEADER + bytes.fromhex("170000001000 0f00 0875 420b 0810 1002 1a05 0100 0000 00".replace(" ", ""))
HEAD_PACKET_MIN = 70

# Control command identifiers (docs/control_commands.md)
CMD_MODE = 0x0D          # 1 off, 2 noise cancellation, 3 transparency, 4 adaptive
CMD_CYCLE = 0x1A         # long-press cycle bitmask: 1 off, 2 ANC, 4 transparency, 8 adaptive
CMD_ONE_BUD = 0x1B       # 1 on, 2 off
CMD_CONVERSATION = 0x28  # 1 on, 2 off
CMD_ADAPTIVE = 0x2E      # 0..100

EAR = {0x00: "in", 0x01: "out", 0x02: "case"}
LEFT, RIGHT, CASE = 0x04, 0x02, 0x08

# Model numbers (linux/enums.h, from https://support.apple.com/en-us/109525)
MODELS = {
    # Shown translated by the app (_(model)); features_for() needs the French names.
    "A1523": N_("AirPods (1re génération)"), "A1722": N_("AirPods (1re génération)"),
    "A2032": N_("AirPods (2e génération)"), "A2031": N_("AirPods (2e génération)"),
    "A2565": N_("AirPods (3e génération)"), "A2564": N_("AirPods (3e génération)"),
    "A2084": "AirPods Pro", "A2083": "AirPods Pro",
    "A3063": "AirPods Pro 3", "A3064": "AirPods Pro 3", "A3065": "AirPods Pro 3",
    "A2931": "AirPods Pro 2", "A2699": "AirPods Pro 2", "A2698": "AirPods Pro 2",
    "A3047": "AirPods Pro 2 (USB-C)", "A3048": "AirPods Pro 2 (USB-C)",
    "A3049": "AirPods Pro 2 (USB-C)",
    "A2096": "AirPods Max", "A3184": "AirPods Max (USB-C)",
    "A3053": "AirPods 4", "A3050": "AirPods 4", "A3054": "AirPods 4",
    "A3056": "AirPods 4 (ANC)", "A3055": "AirPods 4 (ANC)", "A3057": "AirPods 4 (ANC)",
}
# What each family can do: noise control, adaptive audio, conversation awareness,
# ear detection, one-bud noise cancellation.
FEATURES = {
    "AirPods Pro 3": {"anc", "adaptive", "conversation", "ear", "one_bud"},
    "AirPods Pro 2": {"anc", "adaptive", "conversation", "ear", "one_bud"},
    "AirPods 4 (ANC)": {"anc", "adaptive", "conversation", "ear"},
    "AirPods Pro": {"anc", "ear", "one_bud"},
    "AirPods Max": {"anc"},
    "AirPods": {"ear"},
}


def features_for(model):
    for prefix in ("AirPods Pro 3", "AirPods Pro 2", "AirPods 4 (ANC)", "AirPods Pro", "AirPods Max"):
        if model.startswith(prefix):
            return FEATURES[prefix]
    return FEATURES["AirPods"] if model else {"anc", "adaptive", "conversation", "ear", "one_bud"}


def control(identifier, value1, value2=0):
    return HEADER + bytes([OP_CONTROL, 0x00, identifier, value1 & 0xFF, value2 & 0xFF, 0, 0])


def rename_packet(name):
    data = name.encode("utf-8")[:32]
    return HEADER + bytes([0x1A, 0x00, 0x01, len(data), 0x00]) + data


def head_motion(data):
    """(horizontal, vertical) from a head-tracking packet, or None if it is not one."""
    if len(data) < HEAD_PACKET_MIN or not data.startswith(HEADER) or data[4] != OP_HEAD:
        return None
    horizontal = int.from_bytes(data[51:53], "little", signed=True)
    vertical = int.from_bytes(data[53:55], "little", signed=True)
    return horizontal, vertical


class HeadGestures:
    """A nod ("yes") or a shake ("no") in a stream of head motion values.

    Python rewrite of LibrePods' GestureDetector.kt (GPL-3.0-or-later): values are
    smoothed over 3 samples, direction changes beyond a threshold become peaks and
    troughs, and a gesture is a run of 3 or 4 alternating extremes (4 when the head
    moves fast) whose confidence (amplitude, rhythm, alternation, and the other axis
    staying still) reaches 0.7. Vertical motion means yes, horizontal means no.
    `feed()` returns True, False, or None while nothing is recognised; `clock` is
    injectable for the tests.
    """

    MAX_VALID = 6000         # larger values are calibration data
    PEAK = 400               # an extreme must go beyond this
    DIRECTION_CHANGE = 150   # upper bound of the dynamic direction-change threshold
    FAST = 300.0             # ms between extremes below which a gesture needs 4 of them
    MIN_EXTREMES, MAX_EXTREMES = 3, 4
    RHYTHM = 0.5
    CONFIDENCE = 0.7

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.reset()

    def reset(self):
        self.h, self.v = [], []                  # smoothed values (last 100)
        self.h_avg, self.v_avg = [0.0] * 3, [0.0] * 3
        self.h_extremes, self.v_extremes = [], []  # (index, value, ms)
        self.h_up = self.v_up = None
        self.last_extreme = 0.0
        self.intervals = []                      # seconds between extremes (last 5)
        self.speeds = []                         # ms between extremes (last 5)

    @staticmethod
    def _smooth(value, window):
        window.append(value)
        del window[:-3]
        return sum(window) / len(window)

    def feed(self, horizontal, vertical):
        if abs(horizontal) > self.MAX_VALID or abs(vertical) > self.MAX_VALID:
            return None
        self.h.append(self._smooth(float(horizontal), self.h_avg))
        self.v.append(self._smooth(float(vertical), self.v_avg))
        del self.h[:-100]
        del self.v[:-100]
        if len(self.h) >= 4:
            self.h_up = self._direction(self.h, self.h_up, self.h_extremes)
            self.v_up = self._direction(self.v, self.v_up, self.v_extremes)
        return self.detect()

    @staticmethod
    def _variance(values):
        mean = sum(values) / len(values)
        return sum((x - mean) ** 2 for x in values) / len(values)

    def _direction(self, buffer, increasing, extremes):
        current, prev = buffer[-1], buffer[-2]
        if increasing is None:
            increasing = current > prev
        threshold = max(50.0, min(float(self.DIRECTION_CHANGE), self._variance(buffer[-4:]) / 3))
        if increasing and current < prev - threshold or not increasing and current > prev + threshold:
            if abs(prev) > self.PEAK:
                now = self.clock() * 1000.0
                extremes.append((len(buffer) - 1, prev, now))
                if self.last_extreme > 0:
                    self.intervals = (self.intervals + [(now - self.last_extreme) / 1000.0])[-5:]
                    self.speeds = (self.speeds + [now - self.last_extreme])[-5:]
                self.last_extreme = now
            increasing = not increasing
        return increasing

    def _required(self):
        if not self.speeds:
            return self.MIN_EXTREMES
        fast = sum(self.speeds) / len(self.speeds) < self.FAST
        return self.MAX_EXTREMES if fast else self.MIN_EXTREMES

    def _rhythm(self):
        if len(self.intervals) < 2:
            return 0.0
        mean = sum(self.intervals) / len(self.intervals)
        if mean == 0:
            return 0.0
        spread = sum((i / mean - 1.0) ** 2 for i in self.intervals) / len(self.intervals)
        return max(0.0, 1.0 - min(1.0, spread / self.RHYTHM))

    def _confidence(self, extremes, other):
        needed = self._required()
        if len(extremes) < needed:
            return 0.0
        recent = sorted(extremes)[-needed:]
        amplitude = sum(abs(e[1]) for e in recent) / len(recent)
        signs = [e[1] > 0 for e in recent]
        alternating = all(signs[i] != signs[i - 1] for i in range(1, len(signs)))
        tail = other[-len(recent) * 2:]
        other_amplitude = sum(abs(x) for x in tail) / len(tail) if tail else 0.0
        return (min(1.0, amplitude / 600) * 0.4 + self._rhythm() * 0.2
                + (1.0 if alternating else 0.5) * 0.2
                + min(1.0, amplitude / (other_amplitude + 0.1) * 1.2) * 0.2)

    def detect(self):
        needed = self._required()
        if len(self.v_extremes) >= needed and self._confidence(self.v_extremes, self.h) >= self.CONFIDENCE:
            return True
        if len(self.h_extremes) >= needed and self._confidence(self.h_extremes, self.v) >= self.CONFIDENCE:
            return False
        return None


class Pods:
    """One pair of AirPods and its AAP session."""

    def __init__(self, owner, path, props):
        self.owner = owner
        self.path = path
        self.address = props.get("Address", "")
        self.alias = props.get("Alias") or props.get("Name") or "AirPods"
        self.connected = bool(props.get("Connected"))
        self.sock = None
        self.watch = 0
        self.linked = False
        self.retry = 0
        self.gestures = None      # HeadGestures while waiting for a nod or a shake
        self.on_gesture = None    # callable(bool) for that wait
        self.reset()

    def reset(self):
        self.battery = {LEFT: -1, RIGHT: -1, CASE: -1}
        self.charging = {LEFT: False, RIGHT: False, CASE: False}
        self.order = []          # pods in battery-report order: primary first
        self.ear = ["", ""]      # primary, secondary
        self.mode = 0
        self.conversation = 0
        self.adaptive = -1
        self.one_bud = 0
        self.model = ""
        self.firmware = ""

    # --- state for the app ---------------------------------------------------------------

    def ear_of(self, component):
        """in/out/case for the left or right pod ('' when unknown)."""
        if component in self.order:
            return self.ear[self.order.index(component)]
        return ""

    def as_dict(self):
        cycle = self.owner.cycle(self.address)
        return {
            "address": self.address, "name": self.alias, "model": self.model,
            "firmware": self.firmware, "connected": self.connected, "linked": self.linked,
            "left": self.battery[LEFT], "right": self.battery[RIGHT], "case": self.battery[CASE],
            "left_charging": self.charging[LEFT], "right_charging": self.charging[RIGHT],
            "case_charging": self.charging[CASE],
            "ear_left": self.ear_of(LEFT), "ear_right": self.ear_of(RIGHT),
            "mode": self.mode, "cycle": cycle, "conversation": self.conversation,
            "adaptive": self.adaptive, "one_bud": self.one_bud,
            "features": sorted(features_for(self.model)),
            "auto_pause": self.owner.auto_pause,
        }

    # --- session -----------------------------------------------------------------------

    def open(self):
        if self.sock or not self.connected:
            return
        address = self.address

        def work():
            sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
            sock.settimeout(10)
            try:
                sock.connect((address, PSM))
            except OSError as error:
                sock.close()
                GLib.idle_add(lambda: self._open_failed(error) or False)
                return
            sock.setblocking(False)
            GLib.idle_add(lambda: self._opened(sock) or False)

        threading.Thread(target=work, daemon=True, name="boomerang-aap").start()

    def _open_failed(self, error):
        log(f"écouteurs : liaison de contrôle refusée ({error.strerror or error})")
        if self.connected and self.retry < 3:
            self.retry += 1
            GLib.timeout_add_seconds(5 * self.retry, lambda: self.open() and False)

    def _opened(self, sock):
        if not self.connected:
            sock.close()
            return
        self.sock = sock
        self.retry = 0
        self.watch = GLib.io_add_watch(sock.fileno(), GLib.PRIORITY_DEFAULT,
                                       GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self._on_data)
        log("écouteurs : liaison de contrôle ouverte")
        self._send(HANDSHAKE)
        # Not every model acknowledges the features packet: ask for notifications anyway.
        GLib.timeout_add(1500, lambda: (self._send(REQUEST_NOTIFICATIONS)
                                        if self.sock and not self.linked else None) and False)

    def close(self):
        self.stop_gestures()
        if self.watch:
            GLib.source_remove(self.watch)
            self.watch = 0
        if self.sock:
            self.sock.close()
            self.sock = None
            log("écouteurs : liaison de contrôle fermée")
        self.linked = False
        self.reset()

    def _send(self, packet):
        if not self.sock:
            return False
        try:
            self.sock.send(packet)
            return True
        except OSError as error:
            log(f"écouteurs : envoi impossible ({error.strerror or error})")
            return False

    def _on_data(self, _fd, condition):
        if condition & (GLib.IO_HUP | GLib.IO_ERR):
            self.watch = 0
            self.close()
            self.owner.changed()
            return False
        try:
            data = self.sock.recv(1024)
        except BlockingIOError:
            return True
        except OSError:
            self.watch = 0
            self.close()
            self.owner.changed()
            return False
        if not data:
            self.watch = 0
            self.close()
            self.owner.changed()
            return False
        self._parse(data)
        return True

    # --- packets -----------------------------------------------------------------------

    def _parse(self, data):
        if data.startswith(HANDSHAKE_ACK):
            self._send(SET_SPECIFIC_FEATURES)
            return
        if data.startswith(FEATURES_ACK):
            self._send(REQUEST_NOTIFICATIONS)
            return
        if not data.startswith(HEADER) or len(data) < 6:
            return
        opcode = data[4] | (data[5] << 8)
        if opcode == OP_HEAD:
            self._head(data)
            return  # a stream of motion packets: nothing for the app
        if opcode == OP_BATTERY and len(data) >= 7:
            self._battery(data)
        elif opcode == OP_EAR and len(data) >= 8:
            self._ear(EAR.get(data[6], ""), EAR.get(data[7], ""))
        elif opcode == OP_CONTROL and len(data) >= 8:
            self._control(data[6], data[7])
        elif opcode == OP_METADATA:
            self._metadata(data)
        elif opcode == OP_CONVERSATION:
            return  # live "speaking" levels: the AirPods lower the volume themselves
        else:
            return
        if not self.linked:
            self.linked = True
            self.owner.linked(self)
        self.owner.changed()

    def _battery(self, data):
        count = data[6]
        order = []
        for i in range(count):
            at = 7 + i * 5
            if at + 3 >= len(data):
                break
            component, level, status = data[at], data[at + 2], data[at + 3]
            if component in self.battery:
                disconnected = status == 0x04
                self.battery[component] = -1 if disconnected else level
                self.charging[component] = status == 0x01
                if component in (LEFT, RIGHT) and not disconnected:
                    order.append(component)
        if order:
            self.order = order

    def _ear(self, primary, secondary):
        before = list(self.ear)
        self.ear = [primary, secondary]
        self.owner.ear_changed(self, before)

    def _control(self, identifier, value):
        if identifier == CMD_MODE:
            self.mode = value
        elif identifier == CMD_CONVERSATION:
            self.conversation = value
        elif identifier == CMD_ADAPTIVE:
            self.adaptive = value
        elif identifier == CMD_ONE_BUD:
            self.one_bud = value

    def _metadata(self, data):
        # 04 00 04 00 1d 00 + a few bytes, then null-terminated strings:
        # name, model number, manufacturer, serial, firmware...
        body = data[6:]
        start = next((i for i, b in enumerate(body) if 0x20 <= b < 0x7F), 0)
        fields = [f.decode("utf-8", "replace") for f in body[start:].split(b"\x00")]
        model_number = next((f for f in fields if f.startswith("A") and f[1:].isdigit()
                             and len(f) == 5), "")
        # A number missing from MODELS is a model newer than this list: leave the model
        # empty so that every control stays offered instead of hiding them all.
        self.model = MODELS.get(model_number, "")
        if len(fields) > 4:
            self.firmware = fields[4]
        log(f"écouteurs : {self.model or f'modèle inconnu ({model_number or '?'})'} reconnus")

    # --- head gestures -------------------------------------------------------------------

    def worn(self):
        return "in" in self.ear

    def start_gestures(self, on_gesture):
        """Stream head motion and call on_gesture(True for a nod, False for a shake) once."""
        if not self.sock or not self.linked:
            return False
        self.gestures = HeadGestures()
        self.on_gesture = on_gesture
        if not self._send(HEAD_START):
            self.gestures = self.on_gesture = None
            return False
        log("écouteurs : gestes de tête attendus")
        return True

    def stop_gestures(self):
        if self.gestures is None:
            return
        self.gestures = self.on_gesture = None
        self._send(HEAD_STOP)
        log("écouteurs : gestes de tête arrêtés")

    def _head(self, data):
        motion = head_motion(data)
        if motion is None or self.gestures is None:
            return
        result = self.gestures.feed(*motion)
        if result is not None:
            callback = self.on_gesture
            self.stop_gestures()
            log(f"écouteurs : geste {'oui (hochement)' if result else 'non (secousse)'} reconnu")
            if callback:
                callback(result)

    # --- commands ------------------------------------------------------------------------

    def set(self, key, value):
        if key == "mode":
            ok = self._send(control(CMD_MODE, int(value)))
        elif key == "conversation":
            ok = self._send(control(CMD_CONVERSATION, 1 if value else 2))
            if ok:
                self.conversation = 1 if value else 2
        elif key == "adaptive":
            ok = self._send(control(CMD_ADAPTIVE, max(0, min(100, int(value)))))
            if ok:
                self.adaptive = int(value)
        elif key == "one_bud":
            ok = self._send(control(CMD_ONE_BUD, 1 if value else 2))
            if ok:
                self.one_bud = 1 if value else 2
        elif key == "cycle":
            ok = self._send(control(CMD_CYCLE, int(value)))
        elif key == "name":
            name = str(value).strip()
            ok = bool(name) and self._send(rename_packet(name))
            if ok:
                self.alias = name
                self.owner.set_alias(self.path, name)
        else:
            raise KeyError(key)
        return ok


class Headphones:
    def __init__(self, system, session, config, on_change):
        self.bus = system
        self.session = session
        self.config = config
        self.on_change = on_change
        self.pods = {}        # BlueZ path -> Pods
        self.paused = set()   # MPRIS players Boomerang paused on ear removal
        for member, handler in (("InterfacesAdded", self._on_added),
                                ("InterfacesRemoved", self._on_removed)):
            system.signal_subscribe(BLUEZ, "org.freedesktop.DBus.ObjectManager", member,
                                    None, None, Gio.DBusSignalFlags.NONE, handler)
        system.signal_subscribe(BLUEZ, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                None, "org.bluez.Device1", Gio.DBusSignalFlags.NONE,
                                self._on_device_changed)
        system.call(BLUEZ, "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                    None, None, Gio.DBusCallFlags.NONE, -1, None, self._on_objects, None)

    # --- settings ---------------------------------------------------------------------

    @property
    def auto_pause(self):
        return self.config.boolean("headphones", "auto_pause", True)

    def cycle(self, address):
        try:
            return self.config.keyfile.get_integer("headphones", "cycle-" + address.replace(":", ""))
        except GLib.Error:
            return 0  # never set here: the AirPods keep their own

    def set(self, address, key, value):
        if key == "auto_pause":
            self.config.keyfile.set_boolean("headphones", "auto_pause", bool(value))
            self.config.save()
            self.changed()
            return True
        pods = next((p for p in self.pods.values() if p.address == address), None)
        if pods is None or not pods.sock:
            return False
        if key == "cycle":
            value = int(value) & 0x0F
            if bin(value).count("1") < 2:
                return False  # the stem needs at least two modes to switch between
            self.config.keyfile.set_integer("headphones", "cycle-" + address.replace(":", ""), value)
            self.config.save()
        ok = pods.set(key, value)
        self.changed()
        return ok

    def listing(self):
        return [p.as_dict() for p in self.pods.values()]

    def changed(self):
        self.on_change()

    def set_alias(self, path, name):
        self.bus.call(BLUEZ, path, "org.freedesktop.DBus.Properties", "Set",
                      GLib.Variant("(ssv)", ("org.bluez.Device1", "Alias", GLib.Variant("s", name))),
                      None, Gio.DBusCallFlags.NONE, -1, None, None, None)

    def linked(self, pods):
        cycle = self.cycle(pods.address)
        if cycle:
            pods.set("cycle", cycle)

    # --- head gestures for calls (experimental) ---------------------------------------------

    def listen_for_answer(self, on_answer, timeout=30):
        """While a call rings: a nod calls on_answer(True), a shake on_answer(False).
        Only AirPods that are worn and linked are asked; False when there are none."""
        self.stop_listening()
        pods = next((p for p in self.pods.values() if p.sock and p.linked and p.worn()), None)
        if pods is None or not pods.start_gestures(on_answer):
            return False
        self.listening = pods
        self.listen_timeout = GLib.timeout_add_seconds(timeout, lambda: self.stop_listening() and False)
        return True

    def stop_listening(self):
        if getattr(self, "listen_timeout", 0):
            GLib.source_remove(self.listen_timeout)
            self.listen_timeout = 0
        pods = getattr(self, "listening", None)
        self.listening = None
        if pods is not None:
            pods.stop_gestures()

    # --- BlueZ ------------------------------------------------------------------------

    @staticmethod
    def _is_airpods(props):
        uuids = [u.lower() for u in props.get("UUIDs", [])]
        return AAP_UUID in uuids or (APPLE in props.get("Modalias", "")
                                     and props.get("Icon", "").startswith("audio-"))

    def _on_objects(self, bus, result, _data):
        try:
            objects = bus.call_finish(result).unpack()[0]
        except GLib.Error:
            return
        for path, interfaces in objects.items():
            self._add(path, interfaces)

    def _on_added(self, _conn, _sender, _path, _iface, _signal, params):
        path, interfaces = params.unpack()
        self._add(path, interfaces)

    def _add(self, path, interfaces):
        props = interfaces.get("org.bluez.Device1")
        if not props or path in self.pods or not props.get("Paired") or not self._is_airpods(props):
            return
        pods = Pods(self, path, props)
        self.pods[path] = pods
        log("écouteurs : AirPods appairés trouvés")
        if pods.connected:
            GLib.timeout_add_seconds(2, lambda: pods.open() and False)
        self.changed()

    def _on_removed(self, _conn, _sender, path, _iface, _signal, params):
        _path, interfaces = params.unpack()
        if "org.bluez.Device1" in interfaces and path in self.pods:
            self.pods.pop(path).close()
            self.changed()

    def _on_device_changed(self, _conn, _sender, path, _iface, _signal, params):
        _name, changed, _invalid = params.unpack()
        pods = self.pods.get(path)
        if pods is None:
            if changed.get("Paired"):
                self.bus.call(BLUEZ, "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                              None, None, Gio.DBusCallFlags.NONE, -1, None, self._on_objects, None)
            return
        if "Alias" in changed:
            pods.alias = changed["Alias"]
        if "Connected" in changed:
            pods.connected = bool(changed["Connected"])
            if pods.connected:
                GLib.timeout_add_seconds(2, lambda: pods.open() and False)
            else:
                pods.close()
                self._resume_all(False)
        self.changed()

    # --- automatic pause -----------------------------------------------------------------

    def ear_changed(self, pods, before):
        if not self.auto_pause:
            return
        was = before.count("in")
        now = pods.ear.count("in")
        # Like iOS: taking one pod out pauses, putting it back resumes what Boomerang paused.
        if now < was and was > 0:
            self._pause_playing()
        elif now > was and now == sum(1 for e in pods.ear if e in ("in", "out")):
            self._resume_all(True)

    def _players(self):
        try:
            names = self.session.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                           "org.freedesktop.DBus", "ListNames", None, None,
                                           Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
        except GLib.Error:
            return []
        return [n for n in names if n.startswith("org.mpris.MediaPlayer2.")]

    def _mpris(self, name, method):
        self.session.call(name, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", method,
                          None, None, Gio.DBusCallFlags.NONE, 2000, None, None, None)

    def _pause_playing(self):
        for name in self._players():
            try:
                status = self.session.call_sync(
                    name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "Get",
                    GLib.Variant("(ss)", ("org.mpris.MediaPlayer2.Player", "PlaybackStatus")),
                    None, Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
            except GLib.Error:
                continue
            if status == "Playing":
                self._mpris(name, "Pause")
                self.paused.add(name)
        if self.paused:
            log("écouteurs : lecture mise en pause (écouteur retiré)")

    def _resume_all(self, play):
        if play and self.paused:
            log("écouteurs : lecture reprise")
            for name in self.paused:
                self._mpris(name, "Play")
        self.paused.clear()

    def stop(self):
        for pods in self.pods.values():
            pods.close()
