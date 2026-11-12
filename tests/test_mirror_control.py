# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Media keys and gestures of the iPhone control, picture size and screenshots of the
mirroring: pure logic, no Bluetooth, no UxPlay."""

import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from gi.repository import GLib  # noqa: E402

from boomerangd import hid, mirror  # noqa: E402
from tests.test_hid import FakeConfig, items  # noqa: E402


class ConsumerReportTest(unittest.TestCase):
    def test_report_map_has_the_consumer_collection(self):
        tags = items(hid.REPORT_MAP)
        ids = [data[0] for tag, data in tags if tag == 0x84]
        self.assertEqual(ids, [hid.KEYBOARD_ID, hid.MOUSE_ID, hid.CONSUMER_ID])
        pages = [data[0] for tag, data in tags if tag == 0x04]
        self.assertIn(0x0C, pages)  # Consumer page
        self.assertEqual(sum(1 for t, _ in tags if t == 0xA0), sum(1 for t, _ in tags if t == 0xC0))

    def test_consumer_input_is_16_bits(self):
        bits, current, size, count = {}, None, 0, 0
        for tag, data in items(hid.REPORT_MAP):
            if tag == 0x84:
                current = data[0]
            elif tag == 0x74:
                size = data[0]
            elif tag == 0x94:
                count = data[0]
            elif tag == 0x80:
                bits[current] = bits.get(current, 0) + size * count
        self.assertEqual(bits[hid.CONSUMER_ID], len(hid.consumer_report()) * 8)

    def test_usages_are_standard_consumer_codes(self):
        self.assertEqual(hid.consumer_report(hid.MEDIA["volume_up"]), bytes([0xE9, 0x00]))
        self.assertEqual(hid.MEDIA["volume_down"], 0xEA)
        self.assertEqual(hid.MEDIA["play_pause"], 0xCD)
        self.assertEqual(hid.consumer_report(0x223), bytes([0x23, 0x02]))

    def test_gatt_has_a_consumer_report_with_its_reference(self):
        objects = hid.gatt_objects()
        ref = objects[hid.APP_PATH + "/service0/consumer/ref"]
        self.assertEqual(ref[2], bytes([hid.CONSUMER_ID, 1]))  # id 3, input


class ControlKeysTest(unittest.TestCase):
    def setUp(self):
        self.control = hid.Control(None, FakeConfig(), lambda: None, lambda: None)
        self.control.registered = True
        self.control.timer = -1

    def queued(self, which):
        return [r for path, r in self.control.queue if path.endswith("/" + which)]

    def test_media_key_press_and_release(self):
        self.control.media("volume_down")
        self.assertEqual(self.queued("consumer"), [bytes([0xEA, 0]), bytes([0, 0])])
        with self.assertRaises(KeyError):
            self.control.media("eject")

    def test_gesture_presses_moves_and_releases(self):
        self.control.gesture("control_centre")
        mouse = self.queued("mouse")
        pressed = [r[0] & hid.BUTTON_LEFT for r in mouse]
        first = pressed.index(1)
        self.assertTrue(all(p == 0 for p in pressed[:first]))   # goes to the corner first
        self.assertEqual(pressed[-1], 0)                          # then lets go
        down = sum(int.from_bytes(r[2:3], "little", signed=True) for r in mouse[first:])
        width, height = self.control.size()
        self.assertEqual(down, round(0.45 * height))

    def test_app_switcher_holds_before_release(self):
        self.control.gesture("app_switcher")
        mouse = self.queued("mouse")
        held = [r for r in mouse if r == hid.mouse_report(hid.BUTTON_LEFT)]
        self.assertGreaterEqual(len(held), hid.GESTURES["app_switcher"][2])

    def test_gesture_moves_add_up(self):
        go, swipe = hid.gesture_moves((0.5, 1.0), (0.5, 0.6), 400, 870)
        self.assertEqual(sum(m[1] for m in swipe), round(-0.4 * 870))
        self.assertTrue(len(swipe) >= hid.GESTURE_STEPS)


class PointerSizeTest(unittest.TestCase):
    def setUp(self):
        self.changes = 0
        self.control = hid.Control(None, FakeConfig(), lambda: None, self.changed)

    def changed(self):
        self.changes += 1

    def test_portrait_and_landscape(self):
        self.assertEqual(hid.portrait_size(400, 1170, 2532), (400, 866))
        self.assertEqual(hid.portrait_size(400, 2532, 1170), (866, 400))
        self.assertIsNone(hid.portrait_size(400, 0, 0))

    def test_follows_the_picture_while_mirrored(self):
        self.assertEqual(self.control.size(), (400, 870))   # nothing mirrored: the tuned size
        self.control.set_video_size(888, 1920)
        self.assertEqual(self.control.size(), (400, 865))
        self.control.set_video_size(1920, 888)              # iPhone turned
        self.assertEqual(self.control.size(), (865, 400))
        self.assertEqual(self.control.state()["video_width"], 1920)
        self.control.set_video_size(0, 0)
        self.assertEqual(self.control.size(), (400, 870))

    def test_manual_size_when_turned_off(self):
        self.control.set_size(420, 900)
        self.control.set_video_size(888, 1920)
        self.control.set_auto_size(False)
        self.assertEqual(self.control.size(), (420, 900))
        self.assertFalse(self.control.state()["auto_size"])


class OutputLinesTest(unittest.TestCase):
    def test_sizes_from_uxplay_and_the_window(self):
        self.assertEqual(mirror.video_size(
            "*** codec is h264: geometry is (w,h)=(1170,2532) (source); (x,y)=(0,0); (w,h)=(888,1920)"),
            (1170, 2532))
        self.assertEqual(mirror.video_size(
            "begin video stream wxh = 888x1920; source 1170x2532"), (1170, 2532))
        self.assertEqual(mirror.video_size("boomerang-viewer: video 888x1920"), (888, 1920))
        self.assertIsNone(mirror.video_size("Accepted IPv4 client on socket 30"))
        self.assertIsNone(mirror.video_size("boomerang-viewer: video 0x0"))

    def test_tail_reads_only_new_complete_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "uxplay.log")
            tail = mirror.Tail(path)
            self.assertEqual(tail.lines(), [])  # not there yet
            with open(path, "w") as f:
                f.write("one\ntwo")
            self.assertEqual(tail.lines(), ["one"])
            with open(path, "a") as f:
                f.write(" halves\n")
            self.assertEqual(tail.lines(), ["two halves"])
            with open(path, "w") as f:  # a new run starts the file again
                f.write("new\n")
            self.assertEqual(tail.lines(), ["new"])

    def test_mirror_passes_the_size_and_the_screenshot_on(self):
        sizes, changes = [], []
        m = mirror.Mirror(lambda: changes.append(1))
        m.on_video_size = lambda w, h: sizes.append((w, h))
        with mock.patch.object(mirror, "log", lambda *_: None):
            m.output_line("boomerang-viewer: video 888x1920")
            m.output_line("boomerang-viewer: video 888x1920")  # same: said once
            self.assertTrue(m.viewer_ready)
            m.output_line("boomerang-viewer: screenshot /home/u/Images/Recopie iPhone.png")
            m._stop_tail()
        self.assertEqual(sizes, [(888, 1920), (0, 0)])
        self.assertEqual(m.screenshot_path, "/home/u/Images/Recopie iPhone.png")
        self.assertFalse(m.viewer_ready)

    def test_screenshot_needs_the_window(self):
        m = mirror.Mirror(lambda: None)
        self.assertFalse(m.screenshot())
        m.viewer = mock.Mock()
        self.assertFalse(m.screenshot())  # no picture yet: the window may not listen
        m.viewer_ready = True
        self.assertTrue(m.screenshot())
        m.viewer.send_signal.assert_called_once()


class ScreenshotPathTest(unittest.TestCase):
    def test_dated_and_never_overwritten(self):
        from boomerangd import mirror_viewer
        now = GLib.DateTime.new_local(2026, 11, 2, 21, 30, 5)
        with tempfile.TemporaryDirectory() as tmp:
            first = mirror_viewer.screenshot_path(now, tmp)
            self.assertTrue(first.endswith("2026-11-02 21-30-05.png"))
            open(first, "w").close()
            self.assertTrue(mirror_viewer.screenshot_path(now, tmp).endswith("21-30-05 (2).png"))


if __name__ == "__main__":
    unittest.main()
