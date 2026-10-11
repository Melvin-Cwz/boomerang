# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Offline checks of the sounds chosen in Réglages (nothing is played): python3 -m unittest"""

import os
import tempfile
import unittest
from unittest import mock

from gi.repository import GLib

from boomerangd import calls, sounds
from boomerangd.config import Config


def private_config(tmp):
    config = Config()
    config.dir, config.path = tmp, os.path.join(tmp, "boomerangd.conf")
    config.keyfile = GLib.KeyFile()
    return config


class SilentSounds(sounds.Sounds):
    """Records what would be played instead of playing it."""

    def __init__(self, config):
        super().__init__(config)
        self.played = []

    def _spawn(self, path, on_exit=None):
        self.played.append(path)
        return bool(path)


class SoundsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.theme = os.path.join(self.tmp.name, "share", "sounds", "freedesktop", "stereo")
        os.makedirs(self.theme)
        for name in ("message-new-instant.oga", "dialog-information.oga",
                     "phone-incoming-call.oga", "bell.oga", "audio-channel-front-left.oga"):
            open(os.path.join(self.theme, name), "wb").close()
        self.dirs = mock.patch.object(sounds, "_theme_dirs", return_value=[self.theme])
        self.dirs.start()
        self.dnd = mock.patch.object(sounds, "do_not_disturb", return_value=False)
        self.dnd_on = self.dnd.start()
        self.s = SilentSounds(private_config(self.tmp.name))

    def tearDown(self):
        mock.patch.stopall()
        self.tmp.cleanup()

    def test_defaults_and_list(self):
        self.assertEqual(self.s.settings(), {"messages": "default", "notifications": "default",
                                             "calls": "default"})
        names = [value for value, _label in sounds.available()]
        self.assertIn("bell", names)
        self.assertNotIn("audio-channel-front-left", names)
        self.assertTrue(self.s.play("messages"))
        self.assertTrue(self.s.played[-1].endswith("message-new-instant.oga"))

    def test_choice_none_and_file(self):
        self.s.set("messages", "none")
        self.assertFalse(self.s.play("messages"))
        custom = os.path.join(self.tmp.name, "ding.wav")
        open(custom, "wb").close()
        self.s.set("notifications", custom)
        self.s.last_alert = 0
        self.assertTrue(self.s.play("notifications"))
        self.assertEqual(self.s.played[-1], custom)
        with self.assertRaises(ValueError):
            self.s.set("calls", "/nowhere/missing.ogg")
        with self.assertRaises(ValueError):
            self.s.set("alarm", "bell")

    def test_do_not_disturb_and_bursts(self):
        self.dnd_on.return_value = True
        self.assertFalse(self.s.play("messages"))
        self.s.start_ring()
        self.assertFalse(self.s.ringing)
        self.dnd_on.return_value = False
        self.assertTrue(self.s.play("messages"))
        self.assertFalse(self.s.play("notifications"))  # a burst gives one sound

    def test_ring_follows_the_call(self):
        c = calls.Calls.__new__(calls.Calls)
        c.calls, c.transport, c.ringer, c.quiet = {}, {}, self.s, lambda: False
        c.calls["/call1"] = {"State": "incoming"}
        c._update_ring()
        self.assertTrue(self.s.ringing)
        self.assertTrue(self.s.played[-1].endswith("phone-incoming-call.oga"))
        c.calls["/call1"]["State"] = "active"
        c._update_ring()
        self.assertFalse(self.s.ringing)
        # the iPhone rings in-band over the hands-free audio: Boomerang stays quiet
        c.calls["/call1"]["State"] = "incoming"
        c.transport["/gw"] = {"State": "active"}
        c._update_ring()
        self.assertFalse(self.s.ringing)


class PhoneAudioRouteTest(unittest.TestCase):
    def test_route_applies_the_output_from_one_dump(self):
        import json
        from boomerangd import audio
        dump = json.dumps([
            {"type": "PipeWire:Interface:Node", "id": 42,
             "info": {"props": {"node.name": "bluez_input.AA_BB.1"}}},
            {"type": "PipeWire:Interface:Node", "id": 7,
             "info": {"props": {"node.name": "speakers", "media.class": "Audio/Sink"}}}])
        runs = []

        def fake_run(argv, on_done, timeout=5):
            runs.append(argv)
            on_done(dump if argv[0] == "pw-dump" else "")

        a = audio.PhoneAudio.__new__(audio.PhoneAudio)
        a.device, a.routed, a.routing, a.reroute = "/org/bluez/hci0/dev_AA_BB", None, False, False
        a.config = mock.Mock()
        a.config.keyfile.get_string.return_value = "speakers"
        found = []
        with mock.patch.object(audio, "run_async", fake_run):
            a._route(found.append)
        self.assertEqual(found, [True])
        self.assertEqual(a.routed, 42)
        self.assertEqual(runs, [["pw-dump"],
                                ["pw-metadata", "-n", "default", "42", "target.object", "speakers"]])
        self.assertFalse(a.routing)


if __name__ == "__main__":
    unittest.main()
