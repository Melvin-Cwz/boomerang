# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""The microphone muted for a call is always given back (no PipeWire touched): python3 -m unittest"""

import os
import tempfile
import unittest
from unittest import mock

from boomerangd import calls


class CallMuteTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.mkdtemp()
        self.mark = os.path.join(tmp, "boomerang", "microphone-muted")
        self.commands = []
        patches = [
            mock.patch.object(calls, "MUTE_MARK", self.mark),
            mock.patch.object(calls.GLib, "spawn_command_line_sync", self._spawn),
            mock.patch.object(calls, "log", lambda *_: None),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def _spawn(self, command):
        self.commands.append(command)
        return True, b"Volume: 0.50", b"", 0

    def _calls(self):
        c = calls.Calls(None, None, mock.Mock(), lambda: None)
        c.notifications = {}
        return c

    def test_late_mute_after_call_is_ignored(self):
        c = self._calls()
        c.set_muted(True)
        self.assertFalse(c.muted)
        self.assertEqual(self.commands, [])

    def test_mute_then_end_restores_in_order(self):
        c = self._calls()
        c.calls["/call"] = {"State": "active"}
        c.set_muted(True)
        self.assertTrue(os.path.exists(self.mark))
        c.calls["/call"]["State"] = "disconnected"
        c._call_gone("/call")
        self.assertEqual(self.commands[-1], "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0")
        self.assertFalse(os.path.exists(self.mark))

    def test_stale_mute_undone_at_start(self):
        os.makedirs(os.path.dirname(self.mark))
        with open(self.mark, "w") as mark:
            mark.write("0")
        self._calls()
        self.assertEqual(self.commands, ["wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0"])
        self.assertFalse(os.path.exists(self.mark))

    def test_already_muted_microphone_stays_muted(self):
        os.makedirs(os.path.dirname(self.mark))
        with open(self.mark, "w") as mark:
            mark.write("1")
        self._calls()
        self.assertEqual(self.commands, [])


class CallWindowTest(unittest.TestCase):
    def test_a_finished_call_path_opens_the_window_again(self):
        from boomerangd import daemon
        d = daemon.Daemon.__new__(daemon.Daemon)
        d.calls, d.config, d.service = mock.Mock(), mock.Mock(), mock.Mock()
        d.calls.calls = {"/call1": {}}
        d.config.boolean.side_effect = lambda group, key, default=False: key == "window"
        d.call_windows, d.link_changed, d._open_call_window = set(), mock.Mock(), mock.Mock()
        d._call_started("/call1")
        d.calls.calls = {}
        d._calls_state_changed()  # the call is over
        d.calls.calls = {"/call1": {}}
        d._call_started("/call1")  # a later call under the same path
        self.assertEqual(d._open_call_window.call_count, 2)


if __name__ == "__main__":
    unittest.main()
