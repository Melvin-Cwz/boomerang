# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Two calls at once, call lengths and the call audio output, against a fake PipeWire
telephony (no D-Bus, no Bluetooth, no call): python3 -m unittest tests.test_call_actions"""

import os
import tempfile
import unittest
from unittest import mock

from boomerangd import calls

GW = "/org/pipewire/Telephony/ag0"
A, B = GW + "/call1", GW + "/call2"


class FakeTelephony:
    """Stands in for org.pipewire.Telephony: records the methods called, answers like
    libspa-bluez5 (InvalidState when its own checks fail)."""

    def __init__(self, c):
        self.c = c
        self.sent = []

    def call_async(self, _bus, _owner, path, interface, method, args=None, on_done=None, **_kw):
        self.sent.append((path, interface, method))
        if on_done:
            on_done(None, None)


class ActionRulesTest(unittest.TestCase):
    def test_waiting_during_a_call(self):
        actions = calls.available_actions({A: "active", B: "waiting"}, B)
        self.assertIn("hold-and-answer", actions)
        self.assertIn("release-and-answer", actions)
        self.assertIn("hangup", actions)          # refuse the waiting call
        self.assertNotIn("answer", actions)       # Call1.Answer refuses a waiting call
        self.assertNotIn("swap", actions)
        self.assertNotIn("merge", actions)

    def test_active_and_held(self):
        actions = calls.available_actions({A: "active", B: "held"}, A)
        for action in ("swap", "merge", "release-and-swap", "hangup-all", "hangup"):
            self.assertIn(action, actions)
        self.assertNotIn("hold-and-answer", actions)

    def test_a_lone_call_cannot_be_held(self):
        # PipeWire has no Hold, and SwapCalls needs a held call.
        self.assertEqual(calls.available_actions({A: "active"}, A), ["hangup"])

    def test_a_lone_held_call_can_be_resumed(self):
        self.assertEqual(calls.available_actions({A: "held"}, A), ["hangup", "resume"])

    def test_waiting_blocks_merge_and_swap(self):
        actions = calls.available_actions({A: "active", B: "held", GW + "/call3": "waiting"})
        self.assertNotIn("merge", actions)
        self.assertNotIn("swap", actions)
        self.assertIn("hold-and-answer", actions)

    def test_incoming_answers(self):
        self.assertEqual(calls.available_actions({A: "incoming"}, A), ["answer", "hangup"])

    def test_ended_calls_do_not_count(self):
        self.assertEqual(calls.available_actions({A: "active", B: "disconnected"}, A), ["hangup"])


class TransitionTest(unittest.TestCase):
    def test_hold_and_answer_then_swap_then_merge(self):
        states, conf = calls.demo_transition({A: "active", B: "waiting"}, "hold-and-answer", B)
        self.assertEqual(states, {A: "held", B: "active"})
        states, conf = calls.demo_transition(states, "swap")
        self.assertEqual(states, {A: "active", B: "held"})
        states, conf = calls.demo_transition(states, "merge")
        self.assertEqual(states, {A: "active", B: "active"})
        self.assertEqual(conf, {A, B})
        states, conf = calls.demo_transition(states, "hangup-all", None, conf)
        self.assertEqual(states, {})

    def test_release_and_answer(self):
        states, _ = calls.demo_transition({A: "active", B: "waiting"}, "release-and-answer", B)
        self.assertEqual(states, {B: "active"})

    def test_hanging_up_the_active_call_brings_the_held_one_back(self):
        states, _ = calls.demo_transition({A: "active", B: "held"}, "hangup", A)
        self.assertEqual(states, {B: "active"})

    def test_refusing_the_waiting_call_keeps_the_first(self):
        states, _ = calls.demo_transition({A: "active", B: "waiting"}, "hangup", B)
        self.assertEqual(states, {A: "active"})

    def test_conference_shrinks_to_a_plain_call(self):
        states, conf = calls.demo_transition({A: "active", B: "held"}, "merge")
        states, conf = calls.demo_transition(dict(states, **{GW + "/call3": "waiting"}),
                                             "hangup", GW + "/call3", conf)
        self.assertEqual(conf, {A, B})


class CallActionTest(unittest.TestCase):
    def setUp(self):
        patches = [mock.patch.object(calls, "log", lambda *_: None),
                   mock.patch.object(calls.GLib, "idle_add", lambda *_: 0)]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.c = calls.Calls(None, None, mock.Mock(), lambda: None)
        self.c.owner = ":1.42"
        self.c.gateways = {GW: "00:11:22:33:44:55"}
        self.fake = FakeTelephony(self.c)
        patch = mock.patch.object(calls, "call_async", self.fake.call_async)
        patch.start()
        self.addCleanup(patch.stop)
        self.errors = []

    def act(self, path, action):
        self.c.call_action(path, action, self.errors.append)

    def test_gateway_actions_reach_audiogateway1(self):
        self.c.calls = {A: {"State": "active"}, B: {"State": "waiting"}}
        self.act(B, "hold-and-answer")
        self.assertEqual(self.fake.sent, [(GW, calls.GATEWAY, "HoldAndAnswer")])
        self.assertEqual(self.errors, [None])

    def test_swap_merge_and_hangup_all(self):
        self.c.calls = {A: {"State": "active"}, B: {"State": "held"}}
        for action in ("swap", "merge", "release-and-swap", "hangup-all"):
            self.act(A, action)
        self.assertEqual([m for _p, _i, m in self.fake.sent],
                         ["SwapCalls", "CreateMultiparty", "ReleaseAndSwap", "HangupAll"])

    def test_refused_before_pipewire_when_impossible(self):
        self.c.calls = {A: {"State": "active"}}
        self.act(A, "swap")
        self.act(A, "hold")
        self.assertEqual(self.fake.sent, [])
        self.assertTrue(all(self.errors))

    def test_answer_and_hangup_stay_on_the_call(self):
        self.c.calls = {A: {"State": "incoming"}}
        self.act(A, "answer")
        self.assertEqual(self.fake.sent, [(A, calls.CALL, "Answer")])

    def test_waiting_notification_answers_by_holding(self):
        self.c.calls = {A: {"State": "active"}, B: {"State": "waiting", "LineIdentification": "+33600000002"}}
        self.c._refresh(B)
        actions = self.c.notifier.notify.call_args[0][4]
        self.assertEqual(actions[0][0], "hold-and-answer")
        on_action = self.c.notifier.notify.call_args[1]["on_action"]
        on_action("hold-and-answer")
        self.assertEqual(self.fake.sent, [(GW, calls.GATEWAY, "HoldAndAnswer")])

    def test_active_calls_carry_actions_and_conference(self):
        self.c.calls = {A: {"State": "active", "Multiparty": True}, B: {"State": "active", "Multiparty": True}}
        listed = {c["path"]: c for c in self.c.active_calls()}
        self.assertTrue(listed[A]["multiparty"])
        self.assertIn("hangup-all", listed[A]["actions"])


class DemoCallsTest(unittest.TestCase):
    def setUp(self):
        patches = [mock.patch.object(calls, "log", lambda *_: None),
                   mock.patch.object(calls.GLib, "idle_add", lambda *_: 0),
                   mock.patch.object(calls.GLib, "timeout_add_seconds", lambda *_: 0)]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.c = calls.Calls(None, None, mock.Mock(), lambda: None)
        self.c.state_file = os.path.join(tempfile.mkdtemp(), "calls.json")

    def test_simulated_waiting_call_then_hold_and_answer(self):
        second = self.c.simulate("waiting")
        first = next(p for p in self.c.calls if p != second)
        self.assertEqual(self.c.calls[first]["State"], "active")
        self.assertEqual(self.c.calls[second]["State"], "waiting")
        done = []
        self.c.call_action(second, "hold-and-answer", done.append)
        self.assertEqual(done, [None])
        self.assertEqual(self.c.calls[first]["State"], "held")
        self.assertEqual(self.c.calls[second]["State"], "active")
        self.c.call_action(second, "merge", done.append)
        self.assertTrue(self.c.calls[first]["Multiparty"])

    def test_no_demonstration_inside_a_real_call(self):
        self.c.calls = {A: {"State": "active"}}
        self.assertIsNone(self.c.simulate("waiting"))

    def test_demonstration_lengths_are_not_recorded(self):
        path = self.c.simulate("incoming")
        self.c.call_action(path, "answer", lambda _e: None)
        self.c.call_action(path, "hangup", lambda _e: None)
        self.assertFalse(os.path.exists(self.c.state_file))


class LengthTest(unittest.TestCase):
    def setUp(self):
        patches = [mock.patch.object(calls, "log", lambda *_: None),
                   mock.patch.object(calls.GLib, "idle_add", lambda *_: 0)]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.c = calls.Calls(None, None, mock.Mock(), lambda: None)
        self.c.state_file = os.path.join(tempfile.mkdtemp(), "boomerang", "calls.json")

    def test_answered_call_is_recorded_and_matched(self):
        self.c.calls = {A: {"State": "active", "LineIdentification": "06 00 00 00 01"}}
        self.c.first_seen[A] = 1_000_000
        with mock.patch.object(calls.time, "monotonic", side_effect=[100.0, 225.0]):
            self.c.started[A] = calls.time.monotonic()
            self.c._call_gone(A)
        self.assertEqual(os.stat(self.c.state_file).st_mode & 0o777, 0o600)
        history = [{"address": "+33600000001", "time": 1_000_030, "kind": "received"},
                   {"address": "+33600000001", "time": 900_000, "kind": "dialed"},
                   {"address": "+33600000009", "time": 1_000_000, "kind": "missed"}]
        merged = self.c.history_with_durations(history)
        self.assertEqual([m["duration"] for m in merged], [125, -1, -1])

    def test_unanswered_or_hidden_calls_leave_no_record(self):
        self.c.calls = {A: {"State": "incoming", "LineIdentification": "+33600000001"},
                        B: {"State": "active", "LineIdentification": ""}}
        self.c.started[B] = 0.0
        self.c._call_gone(A)
        self.c._call_gone(B)
        self.assertFalse(os.path.exists(self.c.state_file))

    def test_one_record_matches_one_call(self):
        records = [{"address": "+331", "time": 100, "duration": 60}]
        history = [{"address": "+331", "time": 110}, {"address": "+331", "time": 120}]
        self.assertEqual([h["duration"] for h in calls.with_durations(history, records)], [60, -1])

    def test_call_output_is_kept(self):
        with mock.patch.object(self.c, "_route_output"):
            self.c.set_call_output("alsa_output.usb-headset")
        self.assertEqual(self.c.call_output, "alsa_output.usb-headset")
        with mock.patch("boomerangd.audio.pw_nodes", return_value=[]), \
                mock.patch("boomerangd.audio.default_sink_name", return_value=""):
            self.assertEqual(self.c.call_outputs(), [])


if __name__ == "__main__":
    unittest.main()
