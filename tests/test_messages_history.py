# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Messages, offline: paging through a long conversation (GetMessagesPage), messages deleted
on the iPhone, the cadence of the periodic reads."""

import tempfile
import unittest
from unittest import mock

from gi.repository import GLib

from boomerangd import messages, store
from tests.test_offline import FakeNotifier, MessagesHooks, listing


class PagingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = messages.Messages(None, FakeNotifier(), MessagesHooks())
        self.m.store = store.Store(self.tmp.name)
        self.m.enabled = True
        self.tid = self.m.store.ensure_thread(["+33600000001"])
        # 1 200 messages, three per second: page boundaries fall inside one second.
        for i in range(1200):
            self.m.store.upsert(f"map:{i}", self.tid, i % 2 == 0, "+33600000001", "", 1000 + i // 3,
                                f"message {i}", True)
        self.m.store.commit()

    def tearDown(self):
        self.m.store.close()
        self.tmp.cleanup()

    def test_whole_history_reachable_beyond_500(self):
        page, more = self.m.messages_page(self.tid, count=200)
        self.assertTrue(more)
        self.assertEqual(page[-1]["body"], "message 1199")
        seen = [p["id"] for p in page]
        while more:
            oldest = page[0]
            page, more = self.m.messages_page(self.tid, oldest["time"], oldest["id"], 200)
            seen = [p["id"] for p in page] + seen
        self.assertEqual(seen, [f"map:{i}" for i in range(1200)])  # no repeat, no gap

    def test_order_and_end(self):
        page, more = self.m.messages_page(self.tid, count=5000)
        self.assertFalse(more)
        self.assertEqual(len(page), 1200)
        times = [p["time"] for p in page]
        self.assertEqual(times, sorted(times))

    def test_deleted_cursor_falls_back_to_its_time(self):
        page, _ = self.m.messages_page(self.tid, count=10)
        oldest = page[0]
        self.m.delete_message(oldest["id"])
        older, _ = self.m.messages_page(self.tid, oldest["time"], oldest["id"], 10)
        self.assertTrue(all(p["time"] < oldest["time"] for p in older))

    def test_old_call_keeps_the_latest_500(self):
        latest = self.m.messages(self.tid)
        self.assertEqual(len(latest), 500)
        self.assertEqual(latest[-1]["body"], "message 1199")

    def test_unknown_thread(self):
        self.assertEqual(self.m.messages_page("nope"), ([], False))


class PhoneDeletionTest(unittest.TestCase):
    """M3: a message deleted on the iPhone leaves Boomerang too (Message1 object removed)."""
    SESSION = "/org/bluez/obex/client/session0"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.hooks = MessagesHooks()
        self.m = messages.Messages(None, FakeNotifier(), self.hooks)
        self.m.store = store.Store(self.tmp.name)
        self.m.enabled = True
        self.m.session = self.SESSION
        self.inbox = {"inbox": dict(
            listing(str(i), SenderAddress="+33600000001", Sender="Alice",
                    RecipientAddress="+33600000009", Timestamp=f"20260926T1000{i:02d}",
                    Subject=f"texte {i}", Size=7, Read=True) for i in range(1, 31))}
        self.m._merge(self.inbox, initial=True)
        self.tid = self.m.threads()[0]["id"]
        self.timers = []
        patcher = mock.patch.object(messages.GLib, "timeout_add",
                                    side_effect=lambda ms, fn: self.timers.append(fn) or 7)
        patcher.start()
        self.addCleanup(patcher.stop)
        remover = mock.patch.object(messages.GLib, "source_remove")
        remover.start()
        self.addCleanup(remover.stop)

    def tearDown(self):
        self.m.store.close()
        self.tmp.cleanup()

    def removed(self, path, interfaces=(messages.MESSAGE,)):
        self.m._on_removed(None, None, None, None, None,
                           GLib.Variant("(oas)", (path, list(interfaces))))

    def bodies(self):
        return [m["body"] for m in self.m.messages(self.tid)]

    def test_deleted_on_phone_is_hidden_for_good(self):
        self.removed(f"{self.SESSION}/message3")
        self.assertEqual(len(self.timers), 1)
        self.timers.pop()()
        self.assertNotIn("texte 3", self.bodies())
        self.assertEqual(len(self.bodies()), 29)
        self.m._merge(self.inbox, initial=False)  # listed again by a stale listing: stays gone
        self.assertNotIn("texte 3", self.bodies())

    def test_session_teardown_deletes_nothing(self):
        for i in range(1, 31):
            self.removed(f"{self.SESSION}/message{i}")
        self.removed(self.SESSION, (messages.SESSION,))
        for fire in self.timers:
            fire()
        self.assertEqual(len(self.bodies()), 30)

    def test_burst_is_ignored(self):
        for i in range(1, 31):
            self.removed(f"{self.SESSION}/message{i}")
        self.timers.pop()()
        self.assertEqual(len(self.bodies()), 30)

    def test_other_session_or_unlisted_handle(self):
        self.removed("/org/bluez/obex/client/session9/message3")
        self.removed(f"{self.SESSION}/message99")
        for fire in self.timers:
            fire()
        self.assertEqual(len(self.bodies()), 30)


class CadenceTest(unittest.TestCase):
    """Lot 6: fewer periodic reads of the iPhone."""

    def test_listing_every_5_min_then_30_once_mns_works(self):
        due = messages.periodic_due
        self.assertTrue(due(1000 + 300, 1000, False, 1000)[0])
        self.assertFalse(due(1000 + 300, 1000, True, 1000)[0])
        self.assertFalse(due(1000 + 1500, 1000, True, 1000)[0])
        self.assertTrue(due(1000 + 1800, 1000, True, 1000)[0])

    def test_call_history_hourly(self):
        due = messages.periodic_due
        self.assertFalse(due(1000 + 900, 0, False, 1000)[1])  # was every 15 min
        self.assertTrue(due(1000 + 3600, 0, False, 1000)[1])

    def test_periodic_tick_follows_the_decision(self):
        m = messages.Messages(None, FakeNotifier(), MessagesHooks())
        m.session = "/s"
        calls = []
        m.sync = lambda count=20, **_: calls.append(("map", count))
        m._maybe_pull_contacts = lambda calls_only=False, force=False: calls.append(("pbap",))
        with mock.patch.object(messages.time, "monotonic", return_value=10000.0):
            m.last_listing, m.last_calls, m.mns_seen = 10000 - 600, 10000 - 600, True
            m._periodic()
            self.assertEqual(calls, [])
            m.mns_seen = False
            m._periodic()
            self.assertEqual(calls, [("map", 50)])

    def test_mns_event_marks_the_session(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        m = messages.Messages(None, FakeNotifier(), MessagesHooks())
        m.store = store.Store(tmp.name)
        self.addCleanup(m.store.close)
        m.session = "/s"
        with mock.patch.object(messages.GLib, "timeout_add", return_value=1):
            m.syncing = True  # an object made by our own listing
            m._on_added(None, None, None, None, None,
                        GLib.Variant("(oa{sa{sv}})", ("/s/message1", {messages.MESSAGE: {}})))
            self.assertFalse(m.mns_seen)
            m.syncing = False
            m._on_added(None, None, None, None, None,
                        GLib.Variant("(oa{sa{sv}})", ("/s/message2", {messages.MESSAGE: {}})))
            self.assertTrue(m.mns_seen)

    def test_missed_calls_getter_writes_nothing(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        m = messages.Messages(None, FakeNotifier(), MessagesHooks())
        m.store = store.Store(tmp.name)
        self.addCleanup(m.store.close)
        self.assertEqual(m.missed_unseen(), 0)
        self.assertEqual(m.store.meta("calls_seen"), "")


class RichnessTest(unittest.TestCase):
    """Attachments, links exchanged, senders outside the contacts."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = messages.Messages(None, FakeNotifier(), MessagesHooks())
        self.m.store = store.Store(self.tmp.name)
        self.m.enabled = True

    def tearDown(self):
        self.m.store.close()
        self.tmp.cleanup()

    def test_attachment_from_listing_and_notification(self):
        me = "+33600000009"
        self.m._merge({"inbox": dict([
            listing("1", SenderAddress="+33600000001", RecipientAddress=me,
                    Timestamp="20260926T100000", Subject="", Size=0, Read=True, Type="mms"),
            listing("2", SenderAddress="+33600000001", RecipientAddress=me,
                    Timestamp="20260926T100100", Subject="regarde", Size=7, Read=True,
                    Type="mms", AttachmentSize=120000),
            listing("3", SenderAddress="+33600000001", RecipientAddress=me,
                    Timestamp="20260926T100200", Subject="sans", Size=4, Read=True,
                    Type="sms-gsm")])}, initial=True)
        tid = self.m.threads()[0]["id"]
        flags = [(m["body"], m["attachment"]) for m in self.m.messages(tid)]
        self.assertEqual(flags, [("", True), ("regarde", True), ("sans", False)])
        self.m.store.upsert("ancs:x", tid, False, "+33600000001", "", 2000000000,
                            "Pièce jointe : 1 image", True, source="ancs")
        last = self.m.messages(tid)[-1]
        self.assertEqual((last["body"], last["attachment"]), ("", True))
        self.assertIn("Pièce jointe", self.m.threads()[0]["snippet"])
        self.assertTrue(messages.attachment_note("Attachment: 1 Image"))
        self.assertTrue(messages.attachment_note("Pièces jointes : 2 photos"))
        self.assertFalse(messages.attachment_note("Pièce jointe : voir le mail de Paul"))

    def test_links_exchanged(self):
        tid = self.m.store.ensure_thread(["+33600000001"])
        for i, body in enumerate(["vu sur https://example.org/a, top", "rien",
                                  "et www.example.net/b !", "encore https://example.org/a"]):
            self.m.store.upsert(f"map:{i}", tid, i % 2 == 1, "+33600000001", "", 1000 + i,
                                body, True)
        self.assertEqual([link["url"] for link in self.m.links(tid)],
                         ["https://example.org/a", "https://www.example.net/b"])
        self.assertEqual(self.m.links(tid)[0]["message"], "map:3")  # the newest mention

    def test_unknown_senders(self):
        self.m.store.replace_contacts([{"name": "Alice", "addresses": ["+33600000001"],
                                        "photo": None}])
        for n, address in enumerate(["+33600000001", "+33600000002"]):
            tid = self.m.store.ensure_thread([address])
            self.m.store.upsert(f"map:{n}", tid, False, address, "", 1000 + n, "x", True)
        known = {t["name"]: t["known"] for t in self.m.threads()}
        self.assertEqual(known["Alice"], True)
        self.assertEqual([k for name, k in known.items() if name != "Alice"], [False])


if __name__ == "__main__":
    unittest.main()
