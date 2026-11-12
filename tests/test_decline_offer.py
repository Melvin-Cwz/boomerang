# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""« Refuser avec un message », the sharing offer when the network drops, and the
desktop-entry hint, all offline: python3 -m unittest tests.test_decline_offer"""

import unittest
from unittest import mock

from gi.repository import GLib

from boomerangd import calls, hotspot, util

GW = "/org/pipewire/Telephony/ag0"
A = GW + "/call1"
PHONE = "AA:BB:CC:DD:EE:FF"


class DeclineTest(unittest.TestCase):
    def setUp(self):
        for patch in (mock.patch.object(calls, "log", lambda *_: None),
                      mock.patch.object(calls, "call_async", self.hangup),
                      mock.patch.object(calls.GLib, "idle_add", lambda *_: 0)):
            patch.start()
            self.addCleanup(patch.stop)
        self.notifier, self.sent, self.hung = mock.Mock(), [], []
        self.c = calls.Calls(None, None, self.notifier, lambda: None)
        self.c.owner, self.c.gateways = ":1.1", {GW: PHONE}
        self.c.can_text = lambda: True
        self.c.decline_text = lambda: "Je te rappelle dans un instant."
        self.c.send_sms = lambda number, text, done: (self.sent.append((number, text)), done(None))
        self.c.calls = {A: {"State": "incoming", "LineIdentification": "+33600000001"}}

    def hangup(self, _bus, _owner, path, _iface, method, args=None, on_done=None, **_kw):
        self.hung.append((path, method))
        on_done(None, None)

    def decline(self, text=""):
        errors = []
        self.c.decline_with_message(A, text, errors.append)
        return errors

    def test_hangs_up_then_texts_the_caller(self):
        self.assertEqual(self.decline(), [None])
        self.assertEqual(self.hung, [(A, "Hangup")])
        self.assertEqual(self.sent, [("+33600000001", "Je te rappelle dans un instant.")])

    def test_chosen_text_replaces_the_default(self):
        self.decline("  En réunion.  ")
        self.assertEqual(self.sent[0][1], "En réunion.")

    def test_hidden_number_neither_hangs_up_nor_texts(self):
        self.c.calls[A]["LineIdentification"] = ""
        self.assertTrue(self.decline()[0])
        self.assertEqual((self.hung, self.sent), ([], []))

    def test_no_text_when_hangup_fails(self):
        self.c.call_action = lambda _p, _a, done: done("InvalidState")
        self.assertEqual(self.decline(), ["InvalidState"])
        self.assertEqual(self.sent, [])

    def test_action_offered_only_with_number_and_map(self):
        def keys():
            self.notifier.notify.reset_mock()
            self.c._refresh(A)
            return [k for k, _l in self.notifier.notify.call_args[0][4]]

        self.assertIn("decline-text", keys())
        self.c.can_text = lambda: False
        self.assertNotIn("decline-text", keys())
        self.c.can_text = lambda: True
        self.c.calls[A]["LineIdentification"] = ""
        self.assertNotIn("decline-text", keys())

    def test_call_notification_belongs_to_boomerang(self):
        self.c._refresh(A)
        self.assertIs(self.notifier.notify.call_args[1]["own"], True)  # True = main launcher


class OfferTest(unittest.TestCase):
    def make(self, state="off"):
        h = hotspot.Hotspot(None, lambda: (PHONE, [hotspot.NAP_UUID]), client=mock.Mock(spec=[]))
        h.state = lambda: {"state": state, "error": ""}
        h.on_offer = mock.Mock()
        return h

    def test_one_offer_per_loss(self):
        h = self.make()
        for value in (1, 3, 1):
            h.connectivity(value)
        self.assertEqual(h.on_offer.call_count, 1)
        h.connectivity(hotspot.CONNECTIVITY_FULL)
        h.connectivity(1)
        self.assertEqual(h.on_offer.call_count, 2)

    def test_no_offer_when_sharing_already_on_or_for_a_portal(self):
        for state in ("on", "connecting"):
            h = self.make(state)
            h.connectivity(1)
            h.on_offer.assert_not_called()
        h = self.make()
        h.connectivity(2)
        h.on_offer.assert_not_called()


class DesktopEntryTest(unittest.TestCase):
    def hint(self, own):
        notifier = util.Notifier.__new__(util.Notifier)
        notifier.handlers, notifier._caps, notifier.bus = {}, set(), mock.Mock()
        with mock.patch.object(util, "call_sync") as call:
            call.return_value.unpack.return_value = (1,)
            notifier.notify("a", "i", "s", own=own)
        return call.call_args[0][5].unpack()[6].get("desktop-entry")

    def test_own_may_name_another_launcher(self):
        self.assertEqual(self.hint(True), util.APP_ID)
        self.assertEqual(self.hint(util.APP_ID + ".Messages"), util.APP_ID + ".Messages")
        self.assertIsNone(self.hint(False))


class BadgeTest(unittest.TestCase):
    def test_one_badge_on_the_main_launcher(self):
        from boomerangd import daemon
        d = daemon.Daemon.__new__(daemon.Daemon)
        d.config, d.session = mock.Mock(), mock.Mock()
        d.config.module_enabled.return_value = True
        d.messages = mock.Mock(**{"unread_total.return_value": 3, "missed_unseen.return_value": 2})
        d._update_badge()
        (call,) = d.session.emit_signal.call_args_list
        uri, props = call[0][4].unpack()[0], call[0][4].unpack()[1]
        self.assertEqual(uri, "application://io.github.melvincouwez.Boomerang.desktop")
        self.assertEqual(props["count"], 5)


if __name__ == "__main__":
    unittest.main()
