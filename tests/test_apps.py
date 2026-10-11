# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Optional apps (boomerangd/apps.py) and the package filter they rely on."""

import os
import sys
import unittest
import unittest.mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from boomerangd import apps, updates  # noqa: E402

SHA_C = "a" * 64
SHA_A = "b" * 64
SHA_M = "c" * 64


def asset(name, sha):
    return {"name": name, "browser_download_url": f"https://github.com/Melvin-Cwz/boomerang/releases/download/x/{name}",
            "size": 1000, "digest": f"sha256:{sha}"}


RELEASE = {"tag_name": "v0.6.0", "assets": [asset("agenda_0.1.0_amd64.deb", SHA_A),
                                           asset("cassette_0.1.0_amd64.deb", SHA_M),
                                           asset("boomerang_0.6.0-1_amd64.deb", SHA_C)]}


class PackageFilter(unittest.TestCase):
    def test_boomerang_update_never_takes_another_package(self):
        url, _size, sha = updates.deb_asset(RELEASE, "amd64")
        self.assertTrue(url.endswith("boomerang_0.6.0-1_amd64.deb"))
        self.assertEqual(sha, SHA_C)

    def test_optional_app_found_by_name(self):
        url, _size, sha = updates.deb_asset(RELEASE, "amd64", "agenda")
        self.assertTrue(url.endswith("agenda_0.1.0_amd64.deb"))
        self.assertEqual(sha, SHA_A)

    def test_cassette_found_by_name(self):
        url, _size, sha = updates.deb_asset(RELEASE, "amd64", "cassette")
        self.assertTrue(url.endswith("cassette_0.1.0_amd64.deb"))
        self.assertEqual(sha, SHA_M)

    def test_electron_builder_default_name_not_taken(self):
        release = {"tag_name": "v1", "assets": [asset("Cassette-0.1.0-linux-amd64.deb", SHA_M)]}
        self.assertEqual(updates.deb_asset(release, "amd64", "cassette"), ("", 0, ""))

    def test_all_architecture_package(self):
        release = {"tag_name": "v1", "assets": [asset("agenda_0.1.0_all.deb", SHA_A)]}
        self.assertTrue(updates.deb_asset(release, "arm64", "agenda")[0].endswith("_all.deb"))

    def test_release_without_the_package(self):
        release = {"tag_name": "v1", "assets": [asset("boomerang_1.0_amd64.deb", SHA_C)]}
        self.assertEqual(updates.deb_asset(release, "amd64", "agenda"), ("", 0, ""))


class NewestWith(unittest.TestCase):
    def test_newest_release_carrying_the_package(self):
        old = {"tag_name": "v0.5.0", "assets": [asset("agenda_0.0.9_amd64.deb", SHA_A)]}
        newer_without = {"tag_name": "v0.7.0", "assets": [asset("boomerang_0.7.0_amd64.deb", SHA_C)]}
        draft = {"tag_name": "v0.9.0", "draft": True, "assets": [asset("agenda_0.9.0_amd64.deb", SHA_A)]}
        found = apps.newest_with([old, RELEASE, newer_without, draft], "agenda", "amd64")
        self.assertIs(found[0], RELEASE)
        self.assertTrue(found[1].endswith("agenda_0.1.0_amd64.deb"))

    def test_nothing_found(self):
        self.assertIsNone(apps.newest_with([], "agenda", "amd64"))

    def test_version_from_file_name(self):
        self.assertEqual(apps.package_version("https://github.com/x/agenda_0.1.1_amd64.deb"), "0.1.1")
        self.assertEqual(apps.package_version("https://github.com/x/odd.deb"), "")

    def test_unknown_package_refused(self):
        errors = []
        apps.OptionalApps(None).install("nimporte", errors.append)
        self.assertEqual(len(errors), 1)


class Check(unittest.TestCase):
    def run_check(self, pages):
        fetched = []

        def fetch(url):
            fetched.append(url)
            if isinstance(pages.get(url), Exception):
                raise pages[url]
            return pages.get(url, [])

        optional = apps.OptionalApps(None, fetch=fetch)
        with unittest.mock.patch.object(apps.GLib, "idle_add", lambda f: f()), \
                unittest.mock.patch.object(apps.threading, "Thread",
                                           lambda target, **_: unittest.mock.Mock(start=target)):
            optional.check()
        return optional, fetched

    def test_each_app_from_its_own_repository(self):
        own = {apps.SOURCES["agenda"]: [{"tag_name": "v0.1.1", "assets": [asset("agenda_0.1.1_amd64.deb", SHA_A)]}],
               apps.SOURCES["cassette"]: [{"tag_name": "v0.1.1", "assets": [asset("cassette_0.1.1_amd64.deb", SHA_M)]}]}
        optional, fetched = self.run_check(own)
        self.assertNotIn(updates.RELEASES, fetched)
        state = optional.state()
        self.assertEqual(state["agenda"]["version"], "0.1.1")
        self.assertEqual(state["cassette"]["version"], "0.1.1")

    def test_falls_back_on_boomerang_releases(self):
        optional, fetched = self.run_check({apps.SOURCES["agenda"]: OSError("404"),
                                            updates.RELEASES: [RELEASE]})
        self.assertEqual(fetched.count(updates.RELEASES), 1)
        self.assertEqual(optional.state()["agenda"]["version"], "0.1.0")
        self.assertEqual(optional.state()["cassette"]["version"], "0.1.0")


if __name__ == "__main__":
    unittest.main()
