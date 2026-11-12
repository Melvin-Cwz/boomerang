# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""iPhone notifications across reconnections: no ghost, no double, no reopening (offline).

Audit 2026-11-02: the link to the desktop notifications was lost at each reconnection,
notifications cleared on the iPhone during a cut stayed on the PC, and an update from
the iPhone reopened a notification closed on the PC."""

import struct
import tempfile
import unittest
from unittest import mock

from boomerangd import ancs, notifications
from tests.test_sounds import private_config

APP = "com.example.chat"


class Notifier:
    def __init__(self):
        self.next_id = 0
        self.open = {}  # id -> (summary, on_closed)
        self.shown = []
        self.closed = []

    def notify(self, app, icon, summary, body="", actions=(), hints=None, replaces=0,
               timeout=-1, on_action=None, on_closed=None, own=False):
        if replaces and replaces in self.open:
            nid = replaces
        else:
            self.next_id += 1
            nid = self.next_id
        self.open[nid] = (summary, on_closed)
        self.shown.append((nid, summary))
        return nid

    def close(self, nid):
        if nid:
            self.closed.append(nid)
            self.open.pop(nid, None)

    def user_dismisses(self, nid):
        _summary, on_closed = self.open.pop(nid)
        if on_closed:
            on_closed()


class Hooks:
    def __init__(self, notes):
        self.notes = notes

    def suppress_incoming_call(self, _title):
        return False

    def notification_seen(self, *args):
        return self.notes.seen(*args)

    def notification_removed(self, uid):
        self.notes.removed(uid)

    def notification_known(self, uid):
        return self.notes.known(uid)

    def notifications_present(self, uids):
        self.notes.keep_only(uids)


class ReliabilityTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.notes = notifications.Notifications(private_config(self.tmp.name), lambda: None)
        self.hooks = Hooks(self.notes)
        self.notifier = Notifier()
        self.memory = ancs.AncsMemory()
        self.client = self.new_client()

    def tearDown(self):
        self.tmp.cleanup()

    def new_client(self):
        """A reconnection: a fresh client, the same memory (as Link keeps it)."""
        client = ancs.AncsClient(None, {}, "iPhone", self.notifier, self.hooks, self.memory)
        client.requests = []
        client.write = lambda _uuid, data, **_kw: client.requests.append(data)
        client.response_complete = lambda: None
        client.app_names[APP] = "Chat"
        client.notifying = [ancs.NOTIFICATION_SOURCE]
        self.client = client
        return client

    def event(self, kind, uid, flags=0, category=4):
        self.client._on_notification_source(struct.pack("<BBBBI", kind, flags, category, 1, uid))

    def answer(self, uid, text="Salut"):
        attrs = [(0, APP.encode()), (1, b"Alice"), (2, b""), (3, text.encode()),
                 (5, b"20261102T101500"), (6, b""), (7, b"")]
        self.client.buffer = struct.pack("<BI", 0, uid) + b"".join(
            struct.pack("<BH", i, len(v)) + v for i, v in attrs)
        self.client._parse_data_source()

    def add(self, uid, flags=0, text="Salut"):
        self.event(ancs.EVENT_ADDED, uid, flags)
        if uid in self.client.pending:
            self.answer(uid, text)

    def test_removed_after_reconnection_closes_the_desktop_notification(self):
        self.add(1)
        nid = self.notifier.shown[-1][0]
        self.new_client()
        self.add(1, ancs.FLAG_PREEXISTING)  # replayed: not fetched, not shown again
        self.assertEqual(len(self.notifier.shown), 1)
        self.event(ancs.EVENT_REMOVED, 1)
        self.assertIn(nid, self.notifier.closed)
        self.assertFalse(self.notes.known(1))

    def test_cleared_during_the_cut_is_closed_after_the_replay(self):
        self.add(1)
        self.add(2)
        first, second = self.notifier.shown[0][0], self.notifier.shown[1][0]
        self.new_client()
        self.add(2, ancs.FLAG_PREEXISTING)  # only 2 is still on the iPhone
        self.client._reconcile()
        self.assertIn(first, self.notifier.closed)
        self.assertNotIn(second, self.notifier.closed)
        self.assertFalse(self.notes.known(1))
        self.assertTrue(self.notes.known(2))

    def test_no_conclusion_without_a_subscription(self):
        self.add(1)
        self.new_client()
        self.client.notifying = []  # the subscription failed: no replay came
        self.client._reconcile()
        self.assertEqual(self.notifier.closed, [])

    def test_update_does_not_reopen_a_dismissed_notification(self):
        self.add(1)
        self.notifier.user_dismisses(self.notifier.shown[-1][0])
        self.event(ancs.EVENT_MODIFIED, 1)
        self.answer(1, "Salut (modifié)")
        self.assertEqual(len(self.notifier.shown), 1)
        self.assertEqual(self.notes.items[1]["body"], "Salut (modifié)")  # list stays current

    def test_update_replaces_an_open_notification(self):
        self.add(1)
        self.event(ancs.EVENT_MODIFIED, 1)
        self.answer(1, "Salut !")
        self.assertEqual(len(self.notifier.open), 1)
        self.assertEqual(self.notifier.shown[0][0], self.notifier.shown[1][0])

    def test_unknown_preexisting_goes_to_the_list_only(self):
        self.add(7, ancs.FLAG_PREEXISTING, "Déjà là")
        self.assertTrue(self.notes.known(7))
        self.assertEqual(self.notifier.shown, [])

    def test_known_preexisting_is_not_fetched_again(self):
        self.add(1)
        self.new_client()
        self.event(ancs.EVENT_ADDED, 1, ancs.FLAG_PREEXISTING)
        self.assertEqual(self.client.requests, [])

    def test_reconcile_timer_starts_once_subscribed(self):
        with mock.patch.object(ancs.GLib, "timeout_add_seconds", return_value=42) as timer:
            self.client.reconcile_timer = 0
            self.client._subscribed()
            timer.assert_called_once()
        self.assertEqual(self.client.reconcile_timer, 42)


if __name__ == "__main__":
    unittest.main()
