# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""AirPods: low battery warnings, the BlueZ watch on and off, stem settings (no Bluetooth)."""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from gi.repository import GLib  # noqa: E402

from boomerangd import headphones as h  # noqa: E402


class LowBatteryTest(unittest.TestCase):
    def setUp(self):
        self.low = h.LowBattery()

    def levels(self, left, right=100, case=-1, charging=False):
        return {h.LEFT: (left, charging), h.RIGHT: (right, False), h.CASE: (case, False)}

    def test_once_per_threshold_while_going_down(self):
        self.assertEqual(self.low.check(self.levels(50)), [])
        self.assertEqual(self.low.check(self.levels(20)), [(h.LEFT, 20)])
        self.assertEqual(self.low.check(self.levels(19)), [])
        self.assertEqual(self.low.check(self.levels(15)), [])
        self.assertEqual(self.low.check(self.levels(10)), [(h.LEFT, 10)])
        self.assertEqual(self.low.check(self.levels(5)), [])

    def test_straight_to_ten_is_one_warning(self):
        self.assertEqual(self.low.check(self.levels(9)), [(h.LEFT, 9)])
        self.assertEqual(self.low.check(self.levels(8)), [])

    def test_bouncing_around_a_threshold_does_not_repeat(self):
        self.low.check(self.levels(20))
        self.assertEqual(self.low.check(self.levels(22)), [])
        self.assertEqual(self.low.check(self.levels(20)), [])

    def test_charging_or_climbing_arms_again(self):
        self.low.check(self.levels(10))
        self.assertEqual(self.low.check(self.levels(12, charging=True)), [])
        self.assertEqual(self.low.check(self.levels(10)), [(h.LEFT, 10)])
        self.assertEqual(self.low.check(self.levels(40)), [])
        self.assertEqual(self.low.check(self.levels(20)), [(h.LEFT, 20)])

    def test_case_only_at_ten_and_unknown_ignored(self):
        self.assertEqual(self.low.check(self.levels(100, case=15)), [])
        self.assertEqual(self.low.check(self.levels(100, case=-1)), [])
        self.assertEqual(self.low.check(self.levels(100, case=10)), [(h.CASE, 10)])

    def test_both_pods_together(self):
        self.assertEqual(sorted(self.low.check(self.levels(18, 19))), [(h.RIGHT, 19), (h.LEFT, 18)])


class FakeBus:
    def __init__(self):
        self.next = 1
        self.subscribed = {}
        self.calls = []

    def signal_subscribe(self, *args):
        sid = self.next
        self.next += 1
        self.subscribed[sid] = args
        return sid

    def signal_unsubscribe(self, sid):
        del self.subscribed[sid]

    def call(self, *args):
        self.calls.append(args)


class FakeConfig:
    def __init__(self):
        self.values = {}
        self.keyfile = GLib.KeyFile()

    def boolean(self, group, key, default=False):
        return self.values.get((group, key), default)


class FakeNotifier:
    def __init__(self):
        self.shown = []
        self.closed = []

    def notify(self, app, icon, summary, body="", replaces=0, own=False, **_kw):
        self.shown.append((summary, body, replaces))
        return 40 + len(self.shown)

    def close(self, note):
        self.closed.append(note)


DEVICE = {"org.bluez.Device1": {"Address": "AA:BB:CC:DD:EE:FF", "Alias": "AirPods Pro",
                                "Paired": True, "Connected": False,
                                "UUIDs": [h.AAP_UUID]}}


class WatchTest(unittest.TestCase):
    def setUp(self):
        quiet = mock.patch.object(h, "log", lambda *_: None)
        quiet.start()
        self.addCleanup(quiet.stop)
        self.bus = FakeBus()
        self.config = FakeConfig()
        self.notifier = FakeNotifier()
        self.changes = 0
        self.phones = h.Headphones(self.bus, None, self.config, self.changed, self.notifier)

    def changed(self):
        self.changes += 1

    def test_nothing_watched_until_started(self):
        self.assertEqual(self.bus.subscribed, {})
        self.assertEqual(self.bus.calls, [])
        self.phones.start()
        self.assertEqual(len(self.bus.subscribed), 3)
        self.assertEqual(len(self.bus.calls), 1)
        self.phones.start()  # twice: still one watch
        self.assertEqual(len(self.bus.subscribed), 3)

    def test_stop_unsubscribes_and_forgets_the_pods(self):
        self.phones.start()
        self.phones._add("/org/bluez/hci0/dev_AA", DEVICE)
        self.assertEqual(len(self.phones.pods), 1)
        pods = self.phones.pods["/org/bluez/hci0/dev_AA"]
        pods.connected = True
        self.phones.stop()
        self.assertEqual(self.bus.subscribed, {})
        self.assertEqual(self.phones.pods, {})
        self.assertFalse(self.phones.running)
        self.assertEqual(self.phones.listing(), [])
        # A timer armed before the stop would open the control link: it gives up.
        with mock.patch.object(h.threading, "Thread") as thread:
            pods.open()
        thread.assert_not_called()

    def test_late_bluez_reply_after_stop_is_ignored(self):
        self.phones.start()
        self.phones.stop()

        class Reply:
            def call_finish(self, _result):
                return GLib.Variant("(a{oa{sa{sv}}})", ({
                    "/org/bluez/hci0/dev_AA": {"org.bluez.Device1": {
                        "Paired": GLib.Variant("b", True),
                        "UUIDs": GLib.Variant("as", [h.AAP_UUID])}}},))

        self.phones._on_objects(Reply(), None, None)
        self.assertEqual(self.phones.pods, {})

    def battery(self, pods, left, right, case):
        # 04 00 04 00 04 00, count, then per part: component, 01, level, status, 01
        data = h.HEADER + bytes([h.OP_BATTERY, 0x00, 3])
        for component, level in ((h.RIGHT, right), (h.LEFT, left), (h.CASE, case)):
            data += bytes([component, 0x01, level, 0x02, 0x01])
        pods._parse(data)

    def test_low_battery_notification_once(self):
        self.phones.start()
        self.phones._add("/dev_AA", DEVICE)
        pods = self.phones.pods["/dev_AA"]
        self.battery(pods, 60, 60, 80)
        self.assertEqual(self.notifier.shown, [])
        self.battery(pods, 19, 60, 80)
        self.assertEqual(len(self.notifier.shown), 1)
        summary, body, replaces = self.notifier.shown[0]
        self.assertIn("AirPods Pro", summary)
        self.assertIn("19", body)
        self.battery(pods, 18, 60, 80)
        self.assertEqual(len(self.notifier.shown), 1)
        self.battery(pods, 9, 60, 80)
        self.assertEqual(len(self.notifier.shown), 2)
        self.assertEqual(self.notifier.shown[1][2], 41)  # replaces the first one
        self.phones.stop()
        self.assertEqual(self.notifier.closed, [42])

    def test_alerts_can_be_turned_off(self):
        self.config.values[("headphones", "battery_alerts")] = False
        self.phones.start()
        self.phones._add("/dev_AA", DEVICE)
        self.battery(self.phones.pods["/dev_AA"], 5, 5, 5)
        self.assertEqual(self.notifier.shown, [])


class StemSettingsTest(unittest.TestCase):
    class Owner:
        auto_pause = False

        def cycle(self, _address):
            return 0

        def changed(self):
            pass

        def linked(self, _pods):
            pass

        def set_alias(self, *_):
            pass

    def setUp(self):
        self.pods = h.Pods(self.Owner(), "/dev", {"Address": "AA", "Connected": True})
        self.sent = []
        self.pods.sock = object()
        self.pods._send = lambda packet: self.sent.append(packet) or True

    def test_packets_follow_librepods_control_commands(self):
        self.pods.set("ear_detection", False)
        self.assertEqual(self.sent[-1], bytes.fromhex("0400040009000a02000000"))
        self.pods.set("swipe", True)
        self.assertEqual(self.sent[-1], bytes.fromhex("04000400090025010000 00".replace(" ", "")))
        self.pods.set("swipe_interval", 2)
        self.assertEqual(self.sent[-1], bytes.fromhex("0400040009002302000000"))
        self.pods.set("hold_interval", 1)
        self.assertEqual(self.sent[-1], bytes.fromhex("0400040009001801000000"))

    def test_hold_sends_both_buds_right_first(self):
        self.pods._parse(bytes.fromhex("040004000900160101000000"))  # reported: noise, noise
        self.assertEqual(self.pods.hold, (1, 1))
        self.pods.set("hold_left", h.HOLD_SIRI)
        self.assertEqual(self.sent[-1], bytes.fromhex("0400040009001601050000"))
        self.assertEqual(self.pods.hold, (1, 5))
        with self.assertRaises(ValueError):
            self.pods.set("hold_right", 3)

    def test_settings_reported_by_the_airpods(self):
        for packet in ("0400040009000a01000000", "04000400090025020000 00", "0400040009002301000000"):
            self.pods._parse(bytes.fromhex(packet.replace(" ", "")))
        state = self.pods.as_dict()
        self.assertEqual((state["ear_detection"], state["swipe"], state["swipe_interval"]), (1, 2, 1))

    def test_features(self):
        self.assertIn("swipe", h.features_for("AirPods Pro 2 (USB-C)"))
        self.assertNotIn("swipe", h.features_for("AirPods Pro"))
        self.assertIn("hold", h.features_for("AirPods 4 (ANC)"))
        self.assertNotIn("hold", h.features_for("AirPods Max"))
        self.assertEqual(h.features_for(""), h.ALL_FEATURES)


if __name__ == "__main__":
    unittest.main()
