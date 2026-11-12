# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Per-conversation alerts and quick replies on message notifications (offline)."""

import os
import tempfile
import time
import unittest
from unittest import mock

from boomerangd import messages, sounds, store
from tests.test_offline import FakeNotifier, MessagesHooks, listing
from tests.test_sounds import private_config


class HintsNotifier(FakeNotifier):
    def notify(self, app, icon, summary, body="", actions=(), hints=None, **kwargs):
        index = super().notify(app, icon, summary, body, actions, hints, **kwargs)
        self.shown[-1]["hints"] = dict(hints or {})
        return index


class Hooks(MessagesHooks):
    def __init__(self, config):
        super().__init__()
        self.config = config
        self.played = []

    def play_sound(self, kind, value=None, force=False):
        self.played.append((kind, value, force))
        return True


class ThreadNotifyTest(unittest.TestCase):
    NUMBER = "+33600000001"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.config = private_config(self.tmp.name)
        self.hooks = Hooks(self.config)
        self.notifier = HintsNotifier()
        self.m = messages.Messages(None, self.notifier, self.hooks)
        self.m.store = store.Store(os.path.join(self.tmp.name, "store"))
        self.m.enabled = True
        self.sent = []
        self.m.send = lambda tid, text, on_done, retry_key=None: self.sent.append((tid, text))
        self.seen = []
        self.m.mark_seen = self.seen.append
        self.handle = 10

    def tearDown(self):
        self.m.store.close()
        self.tmp.cleanup()

    def receive(self, text="On se voit demain ?", size=None):
        self.handle += 1
        self.m._merge({"inbox": dict([listing(
            str(self.handle), SenderAddress=self.NUMBER, Sender="Alice",
            RecipientAddress="+33600000009", Timestamp=time.strftime("%Y%m%dT%H%M%S"),
            Subject=text, Size=size or len(text), Read=False)])}, initial=False)
        return self.m.store.threads()[0]["id"]

    def test_round_trip(self):
        tid = "+33600000001 [sms]=x"  # characters a keyfile key cannot hold
        self.assertEqual(self.m.thread_notify(tid), ("", ""))
        self.m.set_thread_notify(tid, "priority", "none")
        self.assertEqual(self.m.thread_notify(tid), ("priority", "none"))
        key = messages.Messages._thread_key(tid)
        self.assertEqual(self.config.string("thread-notify-mode", key), "priority")
        with mock.patch.object(sounds, "resolve", return_value=None):
            with self.assertRaises(ValueError):
                self.m.set_thread_notify(tid, "mute", "missing-sound")
        with self.assertRaises(ValueError):
            self.m.set_thread_notify(tid, "loud", "")
        self.assertEqual(self.m.thread_notify(tid), ("priority", "none"))  # unchanged
        self.m.set_thread_notify(tid, "", "")
        self.assertEqual(self.m.thread_notify(tid), ("", ""))
        self.assertIsNone(self.config.string("thread-notify-mode", key, None))  # key removed

    def test_mute_suppresses_banner_and_sound(self):
        tid = self.receive()
        self.assertEqual(len(self.notifier.shown), 1)
        self.m.set_thread_notify(tid, "mute", "")
        self.hooks.played.clear()
        self.receive("Tu es là ?")
        self.assertEqual(len(self.notifier.shown), 1)  # no new banner
        self.assertEqual(self.hooks.played, [])
        unread = {t["id"]: t["unread"] for t in self.m.threads()}
        self.assertEqual(unread[tid], 2)  # still unread

    def test_priority_sets_urgency_and_forces_sound(self):
        tid = self.receive()
        self.assertNotIn("urgency", self.notifier.shown[-1]["hints"])
        self.assertEqual(self.hooks.played[-1], ("messages", None, False))
        with mock.patch.object(sounds, "resolve", return_value="/x/bell.oga"):
            self.m.set_thread_notify(tid, "priority", "bell")
        self.receive("Urgent")
        hints = self.notifier.shown[-1]["hints"]
        self.assertEqual(hints["urgency"].unpack(), 2)
        self.assertTrue(hints["suppress-sound"].unpack())
        self.assertEqual(self.hooks.played[-1], ("messages", "bell", True))

    def test_forced_sound_plays_under_do_not_disturb(self):
        s = sounds.Sounds(private_config(self.tmp.name))
        s._spawn = lambda path, on_exit=None: True
        with mock.patch.object(sounds, "do_not_disturb", return_value=True), \
                mock.patch.object(sounds, "resolve", return_value="/x/a.oga"):
            self.assertFalse(s.play("messages"))
            self.assertTrue(s.play("messages", force=True))
            self.assertFalse(s.play("messages", force=True))  # burst guard kept

    def test_quick_replies_validation(self):
        self.assertEqual(len(self.m.quick_replies()), 5)  # defaults
        long = "x" * 200
        saved = self.m.set_quick_replies(["  Oui  ", "", "Oui", long] + [f"r{i}" for i in range(10)])
        self.assertEqual(saved[0], "Oui")
        self.assertEqual(saved[1], "x" * messages.QUICK_MAX_CHARS)
        self.assertEqual(len(saved), messages.QUICK_MAX)
        self.assertEqual(self.m.quick_replies(), saved)
        self.m.set_quick_replies([])
        self.assertEqual(self.m.quick_replies(), [])  # emptied on purpose: no defaults back

    def test_inline_bubble(self):
        """A server with inline reply (patched elementary): history, Tout lire, resident."""
        self.notifier.capabilities = lambda: {"actions", "inline-reply"}
        self.notifier.close = lambda nid: self.closed.append(nid)
        self.closed = []
        self.receive("Premier")
        tid = self.receive("Deuxième, tronqué", size=400)
        note = self.notifier.shown[-1]
        keys = [k for k, _ in note["actions"]]
        self.assertEqual(keys[:3], ["default", "read-full", "inline-reply"])
        self.assertEqual(note["actions"][0][1], "Ouvrir")
        self.assertTrue(note["hints"]["resident"].unpack())
        self.assertEqual(note["hints"]["x-boomerang-history"].unpack(), [(False, "Premier")])
        asked = []
        self.m.read_full = lambda key: asked.append(key) or True
        note["on_action"]("read-full")  # stays open, refreshed once the text is here
        self.assertEqual(len(asked), 1)
        self.assertEqual(self.closed, [])
        note["on_action"]("inline-reply:Oui")
        self.assertEqual(self.sent, [(tid, "Oui")])
        self.assertEqual(self.closed, [])  # the server closed it itself

    def test_quick_reply_action_sends(self):
        self.m.set_quick_replies(["J'arrive", "Plus tard", "Merci"])
        tid = self.receive()
        note = self.notifier.shown[-1]
        keys = [k for k, _ in note["actions"]]
        self.assertEqual(keys, ["default", "quick:0", "quick:1"])
        self.assertEqual(note["actions"][2][1], "Plus tard")
        self.m.set_quick_replies(["Autre chose"])  # changed after the banner was shown
        note["on_action"]("quick:1")
        self.assertEqual(self.sent, [(tid, "Plus tard")])
        self.assertEqual(self.seen, [tid])
        note["on_action"]("quick:9")
        self.assertEqual(len(self.sent), 1)

    def test_no_quick_reply_with_a_code(self):
        self.receive("Votre code de vérification est 482913.")
        keys = [k for k, _ in self.notifier.shown[-1]["actions"]]
        self.assertFalse(any(k.startswith("quick:") for k in keys))


if __name__ == "__main__":
    unittest.main()
