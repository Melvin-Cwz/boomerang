# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Offline checks of the iPhone link's connection handling: python3 -m unittest

BlueZ is a fake: nothing here touches the real Bluetooth adapter."""

import os
import tempfile
import unittest
from unittest import mock

from gi.repository import GLib

from boomerangd import link
from boomerangd.config import Config

ADAPTER = "/org/bluez/hci0"
PHONE = ADAPTER + "/dev_B8_01_1F_20_DB_5E"
SHADOW = ADAPTER + "/dev_77_D8_78_8E_88_24"  # LE object of the same iPhone


def private_config(tmp):
    config = Config()
    config.dir, config.path = tmp, os.path.join(tmp, "boomerangd.conf")
    config.keyfile = GLib.KeyFile()
    return config


class Owner:
    def __init__(self):
        self.connected = []

    def __getattr__(self, name):
        return lambda *args, **kwargs: None

    def device_connected(self, path, address):
        self.connected.append(path)


class FakeBlueZ:
    """Records the calls a Link makes; answers GetAll from a small object table."""

    def __init__(self, phone, shadow=None):
        self.phone = dict(phone)
        self.shadow = shadow
        self.calls = []
        self.props = []

    def objects(self):
        objects = {ADAPTER: {"org.bluez.Adapter1": {"Alias": "PC", "Powered": True}},
                   PHONE: {"org.bluez.Device1": self.phone}}
        if self.shadow:
            objects[SHADOW] = {"org.bluez.Device1": self.shadow}
        return objects

    def call_async(self, _bus, _name, path, _iface, method, args=None, on_done=None, **_kw):
        self.calls.append((path, method))

    def set_prop(self, _bus, _name, path, _iface, prop, value, what=None):
        self.props.append((path, prop, value.unpack()))

    def get_all(self, _bus, _name, path, _iface):
        return self.objects()[path].get(_iface, {})


def error(message):
    return GLib.Error(message)


class LinkTest(unittest.TestCase):
    def make(self, shadow=None, **phone):
        base = {"Address": "B8:01:1F:20:DB:5E", "AddressType": "public", "Paired": True,
                "Trusted": True, "Connected": False, "Icon": "phone", "Modalias": "bluetooth:v004Cp1"}
        base.update(phone)
        fake = FakeBlueZ(base, shadow)
        tmp = tempfile.mkdtemp()
        patches = [mock.patch.object(link, name, getattr(fake, name))
                   for name in ("call_async", "set_prop", "get_all")]
        patches.append(mock.patch.object(link.Gio, "bus_watch_name_on_connection", lambda *a: 0))
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        lk = link.Link(None, mock.Mock(), private_config(tmp), Owner())
        lk._objects = fake.objects
        lk.adapter = ADAPTER
        return lk, fake

    def test_untrusted_bond_is_trusted(self):
        lk, fake = self.make(Trusted=False)
        lk._pick_device(fake.objects())
        self.assertIn((PHONE, "Trusted", True), fake.props)

    def test_key_missing_stops_every_retry(self):
        lk, fake = self.make()
        lk._pick_device(fake.objects())
        lk.connect_failed(error("br-connection-key-missing"))
        self.assertTrue(lk.bond_lost)
        self.assertEqual(lk.problem, "bond-lost")
        self.assertFalse(lk._should_reconnect())
        lk._reconnect_tick()
        self.assertNotIn((PHONE, "Connect"), fake.calls)

    def test_ordinary_failure_backs_off(self):
        lk, fake = self.make()
        lk._pick_device(fake.objects())
        for _ in range(3):
            lk.connect_failed(error("Page Timeout"))
        self.assertFalse(lk.bond_lost)
        self.assertEqual(lk.reconnect_failures, 3)
        self.assertTrue(lk._should_reconnect())

    def test_no_gatt_subscription_on_cached_services(self):
        lk, fake = self.make(Connected=False, ServicesResolved=True)
        with mock.patch.object(link, "find_service") as find:
            lk._pick_device(fake.objects())
            find.assert_not_called()

    def test_pairing_window_asks_pair_once(self):
        lk, fake = self.make()
        lk.pairing = True
        other = ADAPTER + "/dev_11_22_33_44_55_66"
        lk._pair(other)
        lk._pair(other)
        self.assertEqual(fake.calls.count((other, "Pair")), 1)

    def test_accessory_paired_meanwhile_is_ignored(self):
        lk, fake = self.make()
        lk.pairing = True
        lk._pairing_done(PHONE + "x", {"Paired": True, "Icon": "input-mouse"})
        self.assertIsNone(lk.device)
        self.assertTrue(lk.pairing)

    def test_shadow_is_the_same_iphone(self):
        shadow = {"Address": "B8:01:1F:20:DB:5E", "AddressType": "public", "Paired": False,
                  "Connected": True, "ServicesResolved": True, "Icon": "phone"}
        lk, fake = self.make(shadow=shadow)
        lk.config.device_address = "B8:01:1F:20:DB:5E"
        lk._pick_device(fake.objects())
        self.assertEqual(lk.device, PHONE)  # the bonded object, not the LE one
        self.assertTrue(lk.connected)
        lk.pairing = True
        lk._pair(SHADOW)
        self.assertNotIn((SHADOW, "Pair"), fake.calls)

    def test_bond_lost_error_matching(self):
        self.assertTrue(link.bond_lost_error(error("org.bluez.Error.Failed: br-connection-key-missing")))
        self.assertTrue(link.bond_lost_error(error("org.bluez.Error.AuthenticationFailed")))
        self.assertFalse(link.bond_lost_error(error("br-connection-page-timeout")))
        self.assertFalse(link.bond_lost_error(None))


if __name__ == "__main__":
    unittest.main()


class Lot1Test(LinkTest):
    """Audit 2026-11-02: classic fallback, BlueZ busy, HFP failures."""

    def test_classic_att_tried_without_resolved_services(self):
        lk, fake = self.make(Connected=True, ServicesResolved=False)
        lk.props = dict(fake.phone)
        lk.device = PHONE
        with mock.patch.object(lk, "_attach_classic") as classic:
            lk._attach(fake.objects())
            classic.assert_called_once()

    def test_in_progress_does_not_grow_backoff(self):
        lk, fake = self.make()
        lk._pick_device(fake.objects())
        for _ in range(5):
            lk._connect_busy()
        self.assertEqual(lk.reconnect_failures, 0)
        self.assertNotIn((PHONE, "Disconnect"), fake.calls)  # not long enough yet

    def test_lasting_in_progress_cancels_with_disconnect(self):
        lk, fake = self.make()
        lk._pick_device(fake.objects())
        lk._connect_busy()
        lk.busy_since -= (link.BUSY_RESET_SECONDS + 1) * 1e6
        lk._connect_busy()
        lk._connect_busy()
        self.assertIn((PHONE, "Disconnect"), fake.calls)
        self.assertEqual(lk.busy_count, 0)

    def test_hfp_failure_leaves_backoff_alone(self):
        lk, fake = self.make()
        lk._pick_device(fake.objects())
        lk.profile_failed(error("Page Timeout"))
        self.assertEqual(lk.reconnect_failures, 0)
        lk.profile_failed(error("br-connection-key-missing"))
        self.assertTrue(lk.bond_lost)

    def test_stranger_nudges_only_after_backoff_grew(self):
        lk, fake = self.make()
        lk._pick_device(fake.objects())
        with mock.patch.object(lk, "_schedule_reconnect") as sched, \
                mock.patch.object(lk, "_is_ours", return_value=False):
            lk._on_seen(ADAPTER + "/dev_AA_BB_CC_DD_EE_FF")
            sched.assert_not_called()
            lk.reconnect_failures = 3  # next delay 120 s
            lk._on_seen(ADAPTER + "/dev_AA_BB_CC_DD_EE_FF")
            sched.assert_called_once_with(0)


class DamagedStoreTest(unittest.TestCase):
    def test_damaged_database_is_put_aside(self):
        from boomerangd import store
        tmp = tempfile.mkdtemp()
        with open(os.path.join(tmp, "messages.db"), "wb") as f:
            f.write(b"ceci n'est pas une base SQLite" * 200)
        st = store.Store(tmp)
        self.assertTrue(st.recovered)
        self.assertTrue(os.path.exists(st.recovered))
        self.assertEqual(st.db.execute("PRAGMA quick_check").fetchone()[0], "ok")


class RepairTest(LinkTest):
    def test_repair_drops_stale_keys_when_notifications_stopped(self):
        lk, fake = self.make(Connected=True)
        lk._pick_device(fake.objects())
        lk.connected_since -= (link.LE_GRACE_SECONDS + 1) * 1e6
        self.assertTrue(lk.le_missing)
        with mock.patch.object(link, "call_sync"):
            lk.start_pairing()
        self.assertIn((ADAPTER, "RemoveDevice"), fake.calls)

    def test_plain_pairing_keeps_a_working_bond(self):
        lk, fake = self.make(Connected=True)
        lk._pick_device(fake.objects())
        with mock.patch.object(link, "call_sync"):
            lk.start_pairing()
        self.assertNotIn((ADAPTER, "RemoveDevice"), fake.calls)
