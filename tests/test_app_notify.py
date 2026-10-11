# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Per-app settings of iPhone notifications: priority, quiet, own sound, hidden text (offline)."""

import struct
import tempfile
import unittest

from boomerangd import ancs, notifications
from tests.test_sounds import private_config
from tests.test_thread_notify import HintsNotifier


class Hooks:
    def __init__(self, settings):
        self.settings = settings
        self.played = []

    def suppress_incoming_call(self, _title):
        return False

    def notification_seen(self, *args):
        return self.settings.seen(*args)

    def notification_settings(self, app_id):
        return self.settings.app_settings(app_id)

    def play_sound(self, kind, value=None, force=False):
        self.played.append((kind, value, force))
        return True


class AppNotifyTest(unittest.TestCase):
    APP = "com.apple.mobilemail"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.config = private_config(self.tmp.name)
        self.notes = notifications.Notifications(self.config, lambda: None)
        self.hooks = Hooks(self.notes)
        self.notifier = HintsNotifier()
        self.client = ancs.AncsClient(None, {}, "iPhone", self.notifier, self.hooks)
        self.client.write = lambda *a, **k: None
        self.client.response_complete = lambda: None
        self.client.app_names[self.APP] = "Mail"
        self.uid = 0

    def tearDown(self):
        self.tmp.cleanup()

    def deliver(self, text="Votre facture est disponible"):
        self.uid += 1
        self.client.pending[self.uid] = (0, 0, False)
        attrs = [(0, self.APP.encode()), (1, b"Banque"), (2, b""), (3, text.encode()),
                 (5, b"20261005T101500"), (6, b""), (7, b"")]
        self.client.buffer = struct.pack("<BI", 0, self.uid) + b"".join(
            struct.pack("<BH", i, len(v)) + v for i, v in attrs)
        self.client._parse_data_source()
        return self.notifier.shown[-1]

    def test_defaults(self):
        self.assertEqual(self.notes.app_settings(self.APP), ("", "", False))
        shown = self.deliver()
        self.assertEqual(shown["body"], "Votre facture est disponible")
        self.assertNotIn("urgency", shown["hints"])
        self.assertEqual(self.hooks.played, [("notifications", None, False)])

    def test_round_trip_and_reset(self):
        self.notes.set_app_settings(self.APP, "priority", "none", True)
        self.assertEqual(self.notes.app_settings(self.APP), ("priority", "none", True))
        self.notes.set_app_settings(self.APP, "", "default", False)
        self.assertEqual(self.notes.app_settings(self.APP), ("", "", False))
        self.assertEqual(self.config._string("notification-app-mode", self.APP), "")

    def test_invalid_values_are_refused(self):
        with self.assertRaises(ValueError):
            self.notes.set_app_settings(self.APP, "loud", "", False)
        with self.assertRaises(ValueError):
            self.notes.set_app_settings(self.APP, "", "/nowhere/sound.oga", False)

    def test_priority_is_urgent_and_sounds_under_dnd(self):
        self.notes.set_app_settings(self.APP, "priority", "", False)
        shown = self.deliver()
        self.assertEqual(shown["hints"]["urgency"].unpack(), 2)
        self.assertEqual(self.hooks.played, [("notifications", None, True)])

    def test_quiet_has_no_sound(self):
        self.notes.set_app_settings(self.APP, "quiet", "", False)
        shown = self.deliver()
        self.assertEqual(self.hooks.played, [])
        self.assertTrue(shown["hints"]["suppress-sound"].unpack())

    def test_private_hides_the_text(self):
        self.notes.set_app_settings(self.APP, "", "", True)
        shown = self.deliver()
        self.assertEqual(shown["summary"], "Mail")
        self.assertNotIn("facture", shown["body"])
        self.assertNotIn("Banque", shown["summary"])
        # Kept as is in the Notifications tab of Boomerang.
        self.assertEqual(self.notes.listing()[0]["body"], "Votre facture est disponible")

    def test_listing_carries_the_mode(self):
        self.notes.set_app_settings(self.APP, "quiet", "", False)
        self.notes.seen(99, self.APP, "Mail", "T", "B", 0)
        self.assertEqual([a["mode"] for a in self.notes.apps() if a["id"] == self.APP], ["quiet"])


if __name__ == "__main__":
    unittest.main()
