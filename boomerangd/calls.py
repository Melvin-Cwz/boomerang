# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Phone calls through PipeWire's native HFP hands-free role.

PipeWire (WirePlumber) publishes org.pipewire.Telephony on the session bus once
the iPhone's Hands-Free Audio Gateway profile is connected: one object per
audio gateway (AudioGateway1, oFono-compatible VoiceCallManager) and one per
call (Call1: Answer, Hangup, State, LineIdentification, Name).

This module dials only on an explicit click in the app; otherwise it follows calls,
and answers or hangs up on the user's request from the notification buttons.

Two calls at once (checked against PipeWire 1.6's libspa-bluez5, AT+CHLD 0 to 3):
the gateway offers HoldAndAnswer and ReleaseAndAnswer (an active call and a waiting
one), SwapCalls (needs a held call: it also resumes a lone held call), ReleaseAndSwap
and CreateMultiparty (an active call and a held one, nothing waiting) and HangupAll.
Call1.Answer only answers an "incoming" call, never a "waiting" one. Call1.Hangup on
the active call while another is held sends AT+CHLD=1: the held call comes back.
PipeWire has no Hold for a lone call, no PrivateChat, no HangupMultiparty and no
transfer: Boomerang offers none of them. available_actions() mirrors these rules.
"""

import json
import os
import time

from gi.repository import Gio, GLib

from .i18n import N_, _, pgettext
from .util import BLUEZ, call_async, log

TELEPHONY = "org.pipewire.Telephony"
ROOT = "/org/pipewire/Telephony"
GATEWAY = "org.pipewire.Telephony.AudioGateway1"
TRANSPORT = "org.pipewire.Telephony.AudioGatewayTransport1"
CALL = "org.pipewire.Telephony.Call1"
HFP_AG_UUID = "0000111f-0000-1000-8000-00805f9b34fb"
# Present while this PC's microphone is muted by Boomerang for a call, so the
# mute is undone at the next start if the daemon stopped in the middle.
MUTE_MARK = os.path.join(GLib.get_user_state_dir(), "boomerang", "microphone-muted")

STATE_LABELS = {
    "incoming": N_("Appel entrant"), "waiting": N_("Double appel"),
    "dialing": N_("Appel sortant"), "alerting": N_("Appel sortant"),
    "active": N_("Appel en cours"), "held": N_("Appel en attente"),
}
# Local record of the calls followed here: their length (the iPhone's history has none)
# and the output chosen for call audio. Numbers stay on this PC, never in the journal.
STATE_FILE = os.path.join(GLib.get_user_state_dir(), "boomerang", "calls.json")
LOG_SIZE = 500
MATCH_SECONDS = 180  # a call of the iPhone's history and a local record of the same call

# Actions on the audio gateway (AudioGateway1), as named by the app.
GATEWAY_METHODS = {
    "hold-and-answer": "HoldAndAnswer", "release-and-answer": "ReleaseAndAnswer",
    "swap": "SwapCalls", "resume": "SwapCalls", "release-and-swap": "ReleaseAndSwap",
    "merge": "CreateMultiparty", "hangup-all": "HangupAll",
}
CALL_METHODS = {"answer": "Answer", "hangup": "Hangup"}


def available_actions(states, path=None):
    """What PipeWire accepts now, from {call path: state}: the gateway's actions,
    plus answer / hangup for the call at path. Same checks as libspa-bluez5."""
    live = [s for s in states.values() if s in STATE_LABELS]
    active, held, waiting = "active" in live, "held" in live, "waiting" in live
    actions = set()
    if active and waiting:
        actions |= {"hold-and-answer", "release-and-answer"}
    if active and held and not waiting:
        actions |= {"swap", "merge", "release-and-swap"}
    if held and not active and not waiting:
        actions.add("resume")
    if len(live) > 1:
        actions.add("hangup-all")
    state = states.get(path)
    if state == "incoming":
        actions.add("answer")
    if state in STATE_LABELS:
        actions.add("hangup")
    return sorted(actions)


def demo_transition(states, action, path=None, multiparty=()):
    """The iPhone's answer to an action, for demonstrations and tests: the new
    {path: state} (ended calls left out) and the paths in a conference."""
    states, multiparty = dict(states), set(multiparty)

    def drop(state):
        for p in [p for p, s in states.items() if s == state]:
            del states[p]

    def turn(old, new):
        for p, s in list(states.items()):
            if s == old:
                states[p] = new

    held = "held" in states.values()
    if action == "answer" and states.get(path) == "incoming":
        states[path] = "active"
    elif action == "hangup" and path in states:
        state = states[path]
        if state == "held":
            drop("held")  # AT+CHLD=0: every held call
        elif state == "waiting":
            del states[path]
        else:
            for p in (multiparty if path in multiparty else {path}):
                states.pop(p, None)
            if held and state == "active":
                turn("held", "active")  # AT+CHLD=1: the held call comes back
    elif action == "hold-and-answer":
        turn("active", "held")
        turn("waiting", "active")
    elif action == "release-and-answer":
        drop("active")
        turn("waiting", "active")
    elif action in ("swap", "resume"):
        states = {p: {"active": "held", "held": "active"}.get(s, s) for p, s in states.items()}
    elif action == "release-and-swap":
        drop("active")
        turn("held", "active")
    elif action == "merge":
        turn("held", "active")
        multiparty = {p for p, s in states.items() if s == "active"}
    elif action == "hangup-all":
        states = {}
    multiparty &= set(states)
    return states, (multiparty if len(multiparty) > 1 else set())


def with_durations(history, records):
    """The iPhone's call history with "duration" (seconds, -1 when unknown) from the
    local records: same number, started within MATCH_SECONDS of each other."""
    used = set()
    result = []
    for call in history:
        duration = -1
        for i, record in enumerate(records):
            if i in used or not call.get("address") or record.get("address") != call["address"]:
                continue
            if abs(int(record.get("time", 0)) - int(call.get("time", 0))) <= MATCH_SECONDS:
                used.add(i)
                duration = int(record.get("duration", -1))
                break
        result.append(dict(call, duration=duration))
    return result


class Calls:
    def __init__(self, session, system, notifier, on_state):
        self.session = session
        self.system = system
        self.notifier = notifier
        self.on_state = on_state  # callable() when gateways change
        self.enabled = False
        self.owner = None
        self.gateways = {}  # path -> address
        self.calls = {}  # path -> properties
        self.notifications = {}  # call path -> notification id
        self.subscriptions = []
        self.watch_id = 0
        self.caller_hint = ("", 0.0)  # name from ANCS, monotonic time
        self.device_name = "iPhone"
        self.on_ended = None  # callable() once a call is over
        self.on_calls = None  # callable() when calls, audio route or mute change
        self.on_started = None  # callable(path) when a call starts ringing out or is answered
        self.on_show = None  # callable() to bring the call window up
        self.on_ringing = None  # callable(path) once when an incoming call starts ringing here
        self.rung = set()  # incoming call paths already passed to on_ringing
        self.ringer = None  # sounds.Sounds: the ringtone chosen in Réglages
        self.quiet = lambda: False  # callable() -> True: no ring, popup or audio taken on this PC
        self.can_text = lambda: False  # callable() -> True: MAP is linked, an SMS can go out
        self.decline_text = lambda: ""  # callable() -> the default text of « Refuser avec un message »
        self.send_sms = None  # callable(number, text, on_done(error | None)), set by the daemon
        self.started = {}  # call path -> monotonic time it became active
        self.first_seen = {}  # call path -> wall-clock time it appeared (matches the history)
        self.recorded = set()  # call paths whose length is already in the local record
        self.state_file = STATE_FILE
        self.transport = {}  # gateway path -> {"State", "RejectSCO"}
        # org.pipewire.Telephony first shipped in PipeWire 1.4;
        # with an older PipeWire, calls are shown as unavailable.
        from .components import PIPEWIRE_MIN, _pipewire_version
        version = _pipewire_version()
        self.supported = version is None or version >= PIPEWIRE_MIN
        self.muted = False
        self.mute_restore = None  # default source mute state before a call
        self._undo_stale_mute()
        # Demonstration calls: shown like real ones, but nothing reaches the
        # iPhone, PipeWire or the microphone.
        self.demo = set()
        self.demo_audio_on_pc = True
        self.demo_counter = 0

    # --- lifecycle ------------------------------------------------------------

    def enable(self):
        if self.enabled:
            return
        self.enabled = True
        self.watch_id = Gio.bus_watch_name_on_connection(
            self.session, TELEPHONY, Gio.BusNameWatcherFlags.NONE,
            self._on_appeared, self._on_vanished)

    def disable(self):
        if not self.enabled:
            return
        self.enabled = False
        Gio.bus_unwatch_name(self.watch_id)
        self._on_vanished(None, None)

    def _on_appeared(self, _conn, _name, owner):
        self.owner = owner
        self.supported = True
        # Calls are children of each gateway (/org/pipewire/Telephony/agN), which is an
        # ObjectManager of its own: listen on every path, not only the root.
        for member, handler in (("InterfacesAdded", self._on_added),
                                ("InterfacesRemoved", self._on_removed)):
            self.subscriptions.append(self.session.signal_subscribe(
                owner, "org.freedesktop.DBus.ObjectManager", member, None, None,
                Gio.DBusSignalFlags.NONE, handler))
        # oFono-style signals too, in case a PipeWire version only emits these.
        self.subscriptions.append(self.session.signal_subscribe(
            owner, "org.ofono.VoiceCallManager", "CallAdded", None, None,
            Gio.DBusSignalFlags.NONE, self._on_call_added))
        self.subscriptions.append(self.session.signal_subscribe(
            owner, "org.ofono.VoiceCallManager", "CallRemoved", None, None,
            Gio.DBusSignalFlags.NONE, self._on_call_removed))
        self.subscriptions.append(self.session.signal_subscribe(
            owner, "org.freedesktop.DBus.Properties", "PropertiesChanged", None, CALL,
            Gio.DBusSignalFlags.NONE, self._on_call_changed))
        self.subscriptions.append(self.session.signal_subscribe(
            owner, "org.freedesktop.DBus.Properties", "PropertiesChanged", None, TRANSPORT,
            Gio.DBusSignalFlags.NONE, self._on_transport_changed))
        call_async(self.session, owner, ROOT, "org.freedesktop.DBus.ObjectManager",
                   "GetManagedObjects", on_done=self._on_objects)

    def _on_vanished(self, _conn, _name):
        for sub in self.subscriptions:
            self.session.signal_unsubscribe(sub)
        self.subscriptions = []
        self.owner = None
        for path in list(self.calls):
            self._call_gone(path)
        if self.gateways:
            self.gateways = {}
            self.on_state()

    def _on_objects(self, value, error):
        if error:
            log(f"téléphonie PipeWire illisible : {error.message}")
            return
        for path, interfaces in value.unpack()[0].items():
            self._add(path, interfaces)

    def _on_added(self, _conn, _sender, _path, _iface, _signal, params):
        path, interfaces = params.unpack()
        self._add(path, interfaces)

    def _on_call_added(self, _conn, _sender, _path, _iface, _signal, params):
        path, props = params.unpack()
        self._add(path, {CALL: props})

    def _on_call_removed(self, _conn, _sender, _path, _iface, _signal, params):
        self._call_gone(params.unpack()[0])

    def _on_removed(self, _conn, _sender, _path, _iface, _signal, params):
        path, interfaces = params.unpack()
        if TRANSPORT in interfaces:
            self.transport.pop(path, None)
        if GATEWAY in interfaces and path in self.gateways:
            del self.gateways[path]
            log("appels : passerelle mains libres retirée")
            self.on_state()
        if CALL in interfaces:
            self._call_gone(path)

    def _add(self, path, interfaces):
        if TRANSPORT in interfaces:
            self.transport[path] = dict(interfaces[TRANSPORT])
            if self.quiet() and self.owner:
                # Quiet mode: leave the call audio on the iPhone (another app, e.g. Teams, owns it here).
                call_async(self.session, self.owner, path, "org.freedesktop.DBus.Properties", "Set",
                           GLib.Variant("(ssv)", (TRANSPORT, "RejectSCO", GLib.Variant("b", True))))
        if GATEWAY in interfaces and path not in self.gateways:
            self.gateways[path] = interfaces[GATEWAY].get("Address", "")
            log("appels : passerelle mains libres de l'iPhone disponible")
            self.on_state()
            # Calls already in progress when Boomerang starts are listed by the gateway.
            if self.owner:
                call_async(self.session, self.owner, path, "org.freedesktop.DBus.ObjectManager",
                           "GetManagedObjects", on_done=self._on_objects)
        if CALL in interfaces:
            known = path in self.calls
            self.calls.setdefault(path, {}).update(interfaces[CALL])
            state = self.calls[path].get("State", "?")
            if not known:
                log(f"appels : nouvel appel ({state})")
                self.first_seen.setdefault(path, time.time())
                self.recorded.discard(path)
            self._refresh(path)
            self._state_entered(path, state)
            self._changed()

    def _on_call_changed(self, _conn, _sender, path, _iface, _signal, params):
        _interface, changed, _invalid = params.unpack()
        if path not in self.calls:
            return
        previous = self.calls[path].get("State")
        self.calls[path].update(changed)
        state = self.calls[path].get("State")
        if state != previous:
            log(f"appels : état {previous} → {state}")
            self._state_entered(path, state)
        self._refresh(path)
        self._changed()

    # --- HFP link ---------------------------------------------------------------

    def ready_for(self, address):
        return any(a.upper() == address.upper() for a in self.gateways.values())

    def ensure_hfp(self, device_path, address, on_error=None):
        """Connect the iPhone's hands-free gateway if PipeWire has not done it."""
        if not self.enabled or not address or self.ready_for(address):
            return
        log("appels : connexion du profil mains libres")

        def done(_value, error):
            if error:
                log(f"appels : profil mains libres non connecté : {error.message}")
                if on_error:
                    on_error(error)

        call_async(self.system, BLUEZ, device_path, "org.bluez.Device1", "ConnectProfile",
                   GLib.Variant("(s)", (HFP_AG_UUID,)), timeout=30000, on_done=done)

    def dial(self, number, on_done):
        """Call a number from the iPhone. Only ever on an explicit click in the app."""
        if not self.enabled or not self.owner or not self.gateways:
            on_done("hands-free link to the iPhone not connected")
            return
        path = next(iter(self.gateways))
        log("appels : appel sortant demandé")

        def done(_value, error):
            on_done(error.message if error else None)

        call_async(self.session, self.owner, path, "org.ofono.VoiceCallManager", "Dial",
                   GLib.Variant("(s)", (number,)), on_done=done, timeout=30000)

    # --- notifications ------------------------------------------------------------

    def set_caller_hint(self, name):
        self.caller_hint = (name, time.monotonic())
        for path, props in self.calls.items():
            if props.get("State") in ("incoming", "waiting"):
                self._refresh(path)

    def has_ringing_call(self):
        return any(c.get("State") in ("incoming", "waiting") for c in self.calls.values())

    def _caller(self, props):
        name = props.get("Name") or ""
        hint, stamp = self.caller_hint
        if not name and hint and time.monotonic() - stamp < 60:
            name = hint
        number = props.get("LineIdentification") or ""
        if name and number and name != number:
            return f"{name} ({number})"
        return name or number or _("Numéro masqué")

    def _refresh(self, path):
        props = self.calls[path]
        state = props.get("State", "")
        if state not in STATE_LABELS:
            self._call_gone(path, keep_record=True)
            return
        if self.quiet() and state in ("incoming", "waiting"):
            self.notifier.close(self.notifications.pop(path, 0))
            self._update_ring()
            return
        summary = f"{_(STATE_LABELS[state])} · {self._caller(props)}"
        body = _("Sur {device}").format(device=self.device_name)
        if state == "incoming" and path not in self.rung and path not in self.demo:
            self.rung.add(path)
            if self.on_ringing:
                self.on_ringing(path)
        if state == "waiting":
            # Call1.Answer refuses a waiting call: answering puts the other call on hold.
            actions = [("hold-and-answer", pgettext("call", "Répondre")), ("hangup", _("Refuser"))]
            body = _("Répondre met l'appel en cours en attente · sur {device}").format(
                device=self.device_name)
        elif state == "incoming":
            actions = [("answer", pgettext("call", "Répondre")), ("hangup", _("Refuser"))]
        if state in ("incoming", "waiting") and self._number(props) and self.can_text():
            actions.append(("decline-text", _("Refuser avec un message")))
        if state in ("incoming", "waiting"):
            hints = {"urgency": GLib.Variant("y", 2),
                     "category": GLib.Variant("s", "call.incoming"),
                     "resident": GLib.Variant("b", True),
                     "suppress-sound": GLib.Variant("b", True)}
            timeout = 0
        else:
            actions = [("show", _("Afficher")), ("hangup", _("Raccrocher"))]
            hints = {"urgency": GLib.Variant("y", 1),
                     "resident": GLib.Variant("b", True),
                     "suppress-sound": GLib.Variant("b", True)}
            timeout = 0
        self._update_ring()
        self.notifications[path] = self.notifier.notify(
            f"Boomerang ({self.device_name})", "io.github.melvincouwez.Boomerang", summary, body, actions, hints,
            replaces=self.notifications.get(path, 0), timeout=timeout, own=True,
            on_action=lambda key, p=path: self._on_action(p, key))

    def _update_ring(self):
        """Ring while a call is incoming (not a second call waiting during one), unless the
        iPhone already rings in-band: its ringtone then comes over the hands-free audio."""
        if self.ringer is None:
            return
        if self.quiet():
            self.ringer.stop_ring()
            return
        incoming = any(c.get("State") == "incoming" for c in self.calls.values())
        in_band = any(t.get("State") == "active" for t in self.transport.values())
        if incoming and not in_band:
            self.ringer.start_ring()
        else:
            self.ringer.stop_ring()

    @staticmethod
    def _number(props):
        return props.get("LineIdentification") or ""

    def decline_with_message(self, path, text, on_done):
        """Hang up a ringing call, then send an SMS to its number through MAP (the text
        defaults to the one in boomerangd.conf). Nothing is sent when the number is hidden."""
        props = self.calls.get(path) or {}
        number = self._number(props)
        if props.get("State") not in ("incoming", "waiting") or not number:
            on_done("no ringing call with a known number")
            return
        if not self.send_sms or not self.can_text():
            on_done("messages are not linked")
            return
        text = (text or "").strip() or self.decline_text()

        def hung_up(error):
            if error:
                on_done(error)
            else:
                self.send_sms(number, text, on_done)

        self.call_action(path, "hangup", hung_up)

    def _on_action(self, path, key):
        if key == "decline-text":
            self.decline_with_message(path, "", lambda error: error and log(
                f"appels : refus avec message impossible ({error})"))
            return
        if key in ("show", "default"):
            if self.on_show:
                self.on_show()
            return
        if key in CALL_METHODS or key in GATEWAY_METHODS:
            self.call_action(path, key, lambda error: error and log(f"appels : {key} refusé ({error})"))

    def _state_entered(self, path, state):
        if state == "active" and path not in self.started:
            self.started[path] = time.monotonic()
        # A second call during a call opens the call window too: its banner offers the choices.
        if state in ("active", "dialing", "alerting", "waiting") and self.on_started:
            self.on_started(path)

    def _log_audio_graph(self):
        """Journal aid: which nodes carry the call audio once the SCO link is up."""
        try:
            out = GLib.spawn_command_line_sync("wpctl status")[1].decode("utf-8", "replace")
            lines = [l.strip(" │├└─") for l in out.splitlines()
                     if "bluez" in l.lower() or "iphone" in l.lower() or "*" in l.split("[")[0]]
            log("appels : graphe audio : " + " | ".join(l for l in lines if l)[:600])
        except GLib.Error as error:
            log(f"appels : graphe audio illisible ({error.message})")
        return False

    def _on_transport_changed(self, _conn, _sender, path, _iface, _signal, params):
        _interface, changed, _invalid = params.unpack()
        self.transport.setdefault(path, {}).update(changed)
        if "State" in changed:
            log(f"appels : audio {'sur ce PC' if changed['State'] == 'active' else 'hors du PC'}")
            if changed["State"] == "active":
                GLib.timeout_add_seconds(2, self._log_audio_graph)
                self._schedule_output_route()
            self._update_ring()
        self._changed()

    def _changed(self):
        if self.on_calls:
            self.on_calls()

    # --- in-call controls (always on an explicit request from the app) -----------

    # --- local record: call lengths and the call audio output ------------------------

    def _load_state(self):
        try:
            with open(self.state_file, encoding="utf-8") as f:
                state = json.load(f)
            return state if isinstance(state, dict) else {}
        except (OSError, ValueError):
            return {}

    def _save_state(self, state):
        try:
            os.makedirs(os.path.dirname(self.state_file), mode=0o700, exist_ok=True)
            temporary = self.state_file + ".tmp"
            with open(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w",
                      encoding="utf-8") as f:
                json.dump(state, f)
            os.replace(temporary, self.state_file)
        except OSError as error:
            log(f"appels : relevé local non enregistré ({error.strerror})")

    def _record_length(self, path):
        """Once a call that was answered is over: its number, start and length, kept locally."""
        if path in self.recorded or path in self.demo or path not in self.started:
            return
        self.recorded.add(path)
        from .bmsg import normalize_address
        address = normalize_address(self.calls.get(path, {}).get("LineIdentification") or "")
        if not address:
            return  # hidden number: nothing to match in the history
        state = self._load_state()
        records = [r for r in state.get("log", []) if isinstance(r, dict)]
        records.insert(0, {"address": address,
                           "time": int(self.first_seen.get(path, time.time())),
                           "duration": int(time.monotonic() - self.started[path])})
        state["log"] = records[:LOG_SIZE]
        self._save_state(state)

    def history_with_durations(self, history):
        return with_durations(history, self._load_state().get("log", []))

    @property
    def call_output(self):
        """PipeWire sink for call audio on this PC, "" for the system's default output."""
        return str(self._load_state().get("output", ""))

    def call_outputs(self):
        """This PC's outputs (not Bluetooth ones), each with "current" when chosen for calls."""
        from .audio import _sinks, default_sink_name, pw_nodes
        default, chosen = default_sink_name(), self.call_output
        sinks = _sinks(pw_nodes())
        if chosen not in (name for name, _d in sinks):
            chosen = ""  # unplugged: the default output plays the call
        result = [{"name": name, "description": description, "default": name == default,
                   "current": name == chosen} for name, description in sinks]
        result.sort(key=lambda s: (not s["default"], s["description"]))
        return result

    def set_call_output(self, name):
        state = self._load_state()
        state["output"] = name
        self._save_state(state)
        log(f"appels : sortie audio {'choisie' if name else 'par défaut'}")
        if not self._only_demo():
            self._route_output()
        self._changed()

    def _schedule_output_route(self):
        # The node of the call audio shows up a moment after the SCO link.
        for delay in (1, 3):
            GLib.timeout_add_seconds(delay, lambda: self._route_output() and False)

    def _route_output(self):
        """Point the call audio (the iPhone's stream on this PC) at the chosen output,
        through PipeWire's "default" metadata, as audio.py does for the iPhone's music."""
        from .audio import _nodes, _sinks, run_async
        addresses = {a.replace(":", "_").upper() for a in self.gateways.values() if a}
        if not addresses:
            return

        def dumped(out):
            nodes = _nodes(out)
            output = self.call_output
            if output and output not in (name for name, _d in _sinks(nodes)):
                output = ""
            for node in nodes:
                props = node.get("info", {}).get("props", {})
                name = props.get("node.name", "")
                if "a2dp" in str(props.get("api.bluez5.profile", "")):
                    continue  # the iPhone's music: Réglages › Son de l'iPhone
                if not any(name.upper().startswith("BLUEZ_INPUT." + a) for a in addresses):
                    continue
                if output:
                    args = ["pw-metadata", "-n", "default", str(node["id"]), "target.object", output]
                else:
                    args = ["pw-metadata", "-n", "default", "-d", str(node["id"]), "target.object"]
                run_async(args, lambda result: result is None and log("appels : sortie audio non appliquée"))

        run_async(["pw-dump"], dumped)

    # --- demonstration ---------------------------------------------------------------

    DEMO_PATH = "/io/github/melvincouwez/Boomerang/demo/call"

    def simulate(self, kind="outgoing", number="+33600000000", name=None):
        """Fake call for trying the interface: no number is dialled."""
        name = name or _("Appel de démonstration")
        if kind == "waiting" and not self._only_demo():
            # A second call needs a first one: a demonstration call, answered at once.
            if any(c.get("State") in STATE_LABELS for c in self.calls.values()):
                return None  # a real call is going on: never mix a demonstration into it
            first_path = self.simulate("incoming")
            self._demo_state(first_path, "active")
        self.demo_counter += 1
        path = f"{self.DEMO_PATH}{self.demo_counter}"
        self.demo.add(path)
        if kind != "waiting":
            self.demo_audio_on_pc = True
        first = {"outgoing": "dialing", "waiting": "waiting"}.get(kind, "incoming")
        log(f"appels : simulation d'un appel {'sortant' if kind == 'outgoing' else 'entrant'} "
            "(aucun numéro composé)")
        self._add(path, {CALL: {"State": first, "LineIdentification": number, "Name": name}})
        if kind == "outgoing":
            GLib.timeout_add_seconds(3, lambda: self._demo_state(path, "alerting") and False)
            GLib.timeout_add_seconds(7, lambda: self._demo_state(path, "active") and False)
        GLib.timeout_add_seconds(90, lambda: self._demo_end(path) and False)
        return path

    def _demo_state(self, path, state):
        if path not in self.calls:
            return
        previous = self.calls[path].get("State")
        if previous == state:
            return
        self.calls[path]["State"] = state
        log(f"appels : simulation {previous} → {state}")
        self._state_entered(path, state)
        self._refresh(path)
        self._changed()

    def _demo_end(self, path):
        if path in self.calls:
            log("appels : simulation terminée")
            self.calls[path]["State"] = "disconnected"
            self._refresh(path)  # unknown state: closes the notification, keeps the record
            self.calls.pop(path, None)
            self._call_gone(path, keep_record=True)
        self.first_seen.pop(path, None)
        self.demo.discard(path)

    def _only_demo(self):
        live = [p for p, c in self.calls.items() if c.get("State") in STATE_LABELS]
        return bool(live) and all(p in self.demo for p in live)

    def _demo_action(self, path, action):
        """A demonstration call answers like the iPhone would (demo_transition)."""
        states = {p: c.get("State") for p, c in self.calls.items()
                  if p in self.demo and c.get("State") in STATE_LABELS}
        multiparty = {p for p in states if self.calls[p].get("Multiparty")}
        after, conference = demo_transition(states, action, path, multiparty)
        for p in states:
            if p in self.calls:
                self.calls[p]["Multiparty"] = p in conference
        for p in states:
            if p not in after:
                self._demo_end(p)
            else:
                self._demo_state(p, after[p])
        self._changed()

    def _states(self):
        return {p: c.get("State", "") for p, c in self.calls.items()}

    def active_calls(self):
        now = time.monotonic()
        states = self._states()
        result = []
        for path, props in self.calls.items():
            state = props.get("State", "")
            if state not in STATE_LABELS:
                continue
            result.append({
                "path": path, "state": state,
                "number": props.get("LineIdentification") or "",
                "name": props.get("Name") or "",
                "duration": int(now - self.started[path]) if path in self.started else -1,
                "multiparty": bool(props.get("Multiparty")),
                "actions": available_actions(states, path),
            })
        return result

    def audio_on_pc(self):
        if self._only_demo():
            return self.demo_audio_on_pc
        return any(t.get("State") == "active" for t in self.transport.values())

    def call_action(self, path, action, on_done):
        """answer / hangup on the call at path, or an action on two calls (GATEWAY_METHODS);
        refused here, with a clear reason, when PipeWire would refuse it."""
        if action not in CALL_METHODS and action not in GATEWAY_METHODS:
            on_done(f"unknown action {action}")
            return
        if path not in self.calls:
            on_done("no such call")
            return
        if action not in available_actions(self._states(), path):
            on_done(f"{action} is not possible with the calls going on now")
            return
        if path in self.demo:
            self._demo_action(path, action)
            on_done(None)
            return
        if not self.owner:
            on_done("PipeWire telephony unavailable")
            return
        done = lambda _v, e: on_done(e.message if e else None)  # noqa: E731
        if action in CALL_METHODS:
            log(f"appels : {'réponse' if action == 'answer' else 'raccrochage'} demandé")
            call_async(self.session, self.owner, path, CALL, CALL_METHODS[action], on_done=done)
            return
        gateway = self._gateway_of(path)
        if not gateway:
            on_done("hands-free link to the iPhone not connected")
            return
        log(f"appels : {GATEWAY_METHODS[action]} demandé")
        call_async(self.session, self.owner, gateway, GATEWAY, GATEWAY_METHODS[action],
                   on_done=done, timeout=30000)

    def _gateway_of(self, path):
        """The audio gateway a call belongs to (calls are its children: .../ag0/call1)."""
        for gateway in self.gateways:
            if path.startswith(gateway.rstrip("/") + "/"):
                return gateway
        return next(iter(self.gateways), None)

    def set_audio_on_pc(self, on_pc, on_done):
        """Audio of the call on this PC (SCO link up) or on the iPhone (SCO refused)."""
        if self._only_demo():
            self.demo_audio_on_pc = on_pc
            self._changed()
            on_done(None)
            return
        if not self.owner or not self.transport:
            on_done("no hands-free audio link")
            return
        path = next(iter(self.transport))
        log(f"appels : audio demandé {'sur ce PC' if on_pc else 'sur l’iPhone'}")
        call_async(self.session, self.owner, path, "org.freedesktop.DBus.Properties", "Set",
                   GLib.Variant("(ssv)", (TRANSPORT, "RejectSCO", GLib.Variant("b", not on_pc))))
        if on_pc:
            call_async(self.session, self.owner, path, TRANSPORT, "Activate",
                       on_done=lambda _v, e: on_done(e.message if e else None))
        else:
            on_done(None)

    def send_tones(self, tones, on_done):
        tones = "".join(c for c in tones if c in "0123456789*#ABCD")
        if self._only_demo():
            on_done(None)  # a demonstration sends nothing
            return
        if not tones or not self.owner or not self.gateways:
            on_done("nothing to send")
            return
        path = next(iter(self.gateways))
        call_async(self.session, self.owner, path, "org.ofono.VoiceCallManager", "SendTones",
                   GLib.Variant("(s)", (tones,)),
                   on_done=lambda _v, e: on_done(e.message if e else None))

    def set_muted(self, muted):
        """Mute this PC's microphone for the call (default PipeWire source)."""
        if muted == self.muted:
            return
        if self._only_demo():
            self.muted = muted  # shown in the interface, the real microphone is untouched
            self._changed()
            return
        if muted and not any(c.get("State") in STATE_LABELS for c in self.calls.values()):
            return  # a late click after the call ended: nothing would unmute it
        self.muted = muted
        if muted and self.mute_restore is None:
            try:
                out = GLib.spawn_command_line_sync("wpctl get-volume @DEFAULT_AUDIO_SOURCE@")[1]
            except GLib.Error:
                out = b""
            self.mute_restore = b"MUTED" in (out or b"")
            self._write_mute_mark(self.mute_restore)
        self._set_source_mute(muted)
        log(f"appels : micro {'coupé' if muted else 'rétabli'}")
        self._changed()

    @staticmethod
    def _set_source_mute(muted):
        # Synchronous on purpose: two quick clicks then the end of the call must
        # reach PipeWire in this order, or the last "mute" can land after the restore.
        try:
            GLib.spawn_command_line_sync(f"wpctl set-mute @DEFAULT_AUDIO_SOURCE@ {1 if muted else 0}")
        except GLib.Error as error:
            log(f"appels : micro non modifié ({error.message})")

    @staticmethod
    def _write_mute_mark(was_muted):
        try:
            os.makedirs(os.path.dirname(MUTE_MARK), exist_ok=True)
            with open(MUTE_MARK, "w", encoding="utf-8") as mark:
                mark.write("1" if was_muted else "0")
        except OSError:
            pass

    def _undo_stale_mute(self):
        """Give the microphone back if the daemon stopped while a call had it muted."""
        try:
            with open(MUTE_MARK, encoding="utf-8") as mark:
                was_muted = mark.read().strip() == "1"
            os.remove(MUTE_MARK)
        except OSError:
            return
        if not was_muted:
            self._set_source_mute(False)
            log("appels : micro rétabli (coupé lors d'un appel précédent)")

    def _restore_microphone(self):
        if self.mute_restore is not None:
            self._set_source_mute(self.mute_restore)
            try:
                os.remove(MUTE_MARK)
            except OSError:
                pass
        self.mute_restore = None
        self.muted = False

    def _call_gone(self, path, keep_record=False):
        self.rung.discard(path)
        self.notifier.close(self.notifications.pop(path, 0))
        if self.ringer is not None and not any(
                p != path and c.get("State") == "incoming" for p, c in self.calls.items()):
            self.ringer.stop_ring()
        self._record_length(path)
        self.started.pop(path, None)
        if not any(p != path and c.get("State") in STATE_LABELS for p, c in self.calls.items()):
            if path in self.demo:
                self.muted = False
            else:
                self._restore_microphone()
        GLib.idle_add(lambda: self._changed() and False)
        if not keep_record:
            self.first_seen.pop(path, None)
            self.recorded.discard(path)
            if self.calls.pop(path, None) is not None:
                log("appels : appel terminé")
                if self.on_ended and path not in self.demo:
                    self.on_ended()
