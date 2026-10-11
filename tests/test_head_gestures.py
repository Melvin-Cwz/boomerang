# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""AirPods head gestures (nod / shake), from LibrePods: pure logic, no Bluetooth."""

import math
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from boomerangd import headphones  # noqa: E402


def packet(horizontal, vertical):
    """A head-tracking packet as the AirPods send it (70 bytes, values at 51 and 53)."""
    data = bytearray(headphones.HEADER + bytes([headphones.OP_HEAD, 0x00]) + bytes(64))
    data[51:53] = int(horizontal).to_bytes(2, "little", signed=True)
    data[53:55] = int(vertical).to_bytes(2, "little", signed=True)
    return bytes(data)


class Clock:
    def __init__(self):
        self.t = 100.0

    def __call__(self):
        return self.t


def run(detector, clock, horizontal, vertical, steps=80, period=0.6, step=0.02):
    """Feed a head movement (amplitudes in sensor units) until a gesture is recognised."""
    for i in range(steps):
        clock.t += step
        phase = 2 * math.pi * i * step / period
        result = detector.feed(horizontal * math.sin(phase), vertical * math.sin(phase))
        if result is not None:
            return result
    return None


class HeadMotionTest(unittest.TestCase):
    def test_values_read_little_endian_signed(self):
        self.assertEqual(headphones.head_motion(packet(-1234, 2500)), (-1234, 2500))

    def test_other_packets_ignored(self):
        self.assertIsNone(headphones.head_motion(packet(1, 2)[:60]))
        battery = bytearray(packet(1, 2))
        battery[4] = headphones.OP_BATTERY
        self.assertIsNone(headphones.head_motion(bytes(battery)))

    def test_start_and_stop_packets(self):
        for p in (headphones.HEAD_START, headphones.HEAD_STOP):
            self.assertTrue(p.startswith(headphones.HEADER + bytes([0x17, 0x00])))
        self.assertNotEqual(headphones.HEAD_START, headphones.HEAD_STOP)


class GesturesTest(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.detector = headphones.HeadGestures(self.clock)

    def test_nod_is_yes(self):
        self.assertIs(run(self.detector, self.clock, 0, 1500), True)

    def test_shake_is_no(self):
        self.assertIs(run(self.detector, self.clock, 1500, 0), False)

    def test_still_head_is_nothing(self):
        self.assertIsNone(run(self.detector, self.clock, 30, 30))

    def test_small_movements_are_nothing(self):
        self.assertIsNone(run(self.detector, self.clock, 0, 300))

    def test_calibration_values_ignored(self):
        self.assertIsNone(self.detector.feed(9000, 9000))
        self.assertEqual(self.detector.v, [])


class PodsGesturesTest(unittest.TestCase):
    def setUp(self):
        patch = mock.patch.object(headphones, "log", lambda *_: None)
        patch.start()
        self.addCleanup(patch.stop)
        owner = mock.Mock()
        self.pods = headphones.Pods(owner, "/dev", {"Address": "AA", "Connected": True})
        self.pods.sock = mock.Mock()
        self.pods.linked = True
        self.sent = []
        self.pods._send = lambda p: self.sent.append(p) or True

    def test_nod_answers_once_then_stops_tracking(self):
        answers = []
        self.assertTrue(self.pods.start_gestures(answers.append))
        self.assertEqual(self.sent, [headphones.HEAD_START])
        for i in range(80):
            self.pods._parse(packet(0, 1500 * math.sin(2 * math.pi * i * 0.02 / 0.6)))
            if answers:
                break
        # without a fake clock, the rhythm term is 0: a clean nod still passes
        self.assertEqual(answers, [True])
        self.assertEqual(self.sent[-1], headphones.HEAD_STOP)
        self.assertIsNone(self.pods.gestures)

    def test_head_packets_do_not_wake_the_app(self):
        self.pods._parse(packet(0, 0))
        self.pods.owner.changed.assert_not_called()

    def test_not_started_without_link(self):
        self.pods.linked = False
        self.assertFalse(self.pods.start_gestures(lambda _yes: None))
        self.assertEqual(self.sent, [])


if __name__ == "__main__":
    unittest.main()
