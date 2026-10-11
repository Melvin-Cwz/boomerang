# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Link previews: page parsing, refused addresses, setting off (no network)."""

import email.message
import io
import os
import socket
import tempfile
import unittest
from unittest import mock

from gi.repository import GLib

from boomerangd import linkpreview
from tests.test_sounds import private_config

PAGE = """<!doctype html><html><head>
<meta charset="utf-8">
<title>Titre de secours</title>
<meta property="og:title" content="Randonnées d&#39;automne">
<meta name="description" content="Description simple">
<meta property="og:description" content="  Dix   sentiers près de la ville. ">
<meta name="twitter:image" content="/img/twitter.png">
<meta property="og:image" content="/img/cover.jpg">
</head><body><meta property="og:title" content="Ignoré"></body></html>"""


def resolver_for(address):
    def resolve(host, *_args):
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (address, 0))]
    return resolve


class FakeResponse(io.BytesIO):
    def __init__(self, data, content_type, url):
        super().__init__(data)
        self.headers = email.message.Message()
        self.headers["Content-Type"] = content_type
        self.url = url

    def geturl(self):
        return self.url


class ParseTest(unittest.TestCase):
    def test_open_graph(self):
        found = linkpreview.parse(PAGE, "https://example.org/blog/page")
        self.assertEqual(found["title"], "Randonnées d'automne")
        self.assertEqual(found["description"], "Dix sentiers près de la ville.")
        self.assertEqual(found["image"], "https://example.org/img/cover.jpg")

    def test_fallbacks(self):
        found = linkpreview.parse("<html><head><title> Seul titre </title>"
                                  "<meta name=description content=Résumé>"
                                  "<meta name='twitter:image' content='https://cdn.example.org/a.png'>"
                                  "</head></html>", "https://example.org/")
        self.assertEqual(found, {"title": "Seul titre", "description": "Résumé",
                                 "image": "https://cdn.example.org/a.png"})
        found = linkpreview.parse("<meta property='og:image' content='javascript:alert(1)'>"
                                  "<title>x</title>", "https://example.org/")
        self.assertEqual(found["image"], "")


class RefusedTest(unittest.TestCase):
    def test_private_addresses(self):
        for address in ("127.0.0.1", "10.0.0.2", "192.168.1.1", "172.16.0.1", "169.254.1.1",
                        "::1", "fe80::1", "fd00::1", "0.0.0.0", "::ffff:127.0.0.1", "100.64.0.1"):
            with self.assertRaises(linkpreview.Refused, msg=address):
                linkpreview.check_url("http://site.example/", resolver_for(address))
        linkpreview.check_url("https://site.example/", resolver_for("93.184.216.34"))

    def test_schemes(self):
        public = resolver_for("93.184.216.34")
        for url in ("file:///etc/passwd", "ftp://site.example/", "data:text/html,x",
                    "https://user:pw@site.example/"):
            with self.assertRaises(linkpreview.Refused, msg=url):
                linkpreview.check_url(url, public)

    def test_private_host_never_opened(self):
        opened = []

        def opener(request, timeout=None):
            opened.append(request)

        with mock.patch.object(linkpreview, "_opener",
                                        return_value=mock.Mock(open=opener)):
            with self.assertRaises(linkpreview.Refused):
                linkpreview.urlopen("http://router.example/", resolver_for("192.168.0.254"))
        self.assertEqual(opened, [])

    def test_redirect_to_private_refused(self):
        handler = linkpreview._Redirects(resolver_for("127.0.0.1"))
        with self.assertRaises(linkpreview.Refused):
            handler.redirect_request(None, None, 302, "Found", {}, "http://localhost/admin")


class PreviewsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.config = private_config(self.tmp.name)
        self.opened = []
        self.dir = os.path.join(self.tmp.name, "link-previews")

    def tearDown(self):
        self.tmp.cleanup()

    def open_url(self, url, resolver, accept="text/html"):
        linkpreview.check_url(url, resolver)  # what the real urlopen does first
        self.opened.append(url)
        if url.endswith(".jpg"):
            return FakeResponse(b"\xff\xd8\xff fake jpeg", "image/jpeg", url)
        return FakeResponse(PAGE.encode(), "text/html; charset=utf-8", url)

    def previews(self, address="93.184.216.34"):
        return linkpreview.LinkPreviews(self.config, self.dir, resolver_for(address),
                                        self.open_url)

    def wait(self, previews, url):
        results = []
        previews.get(url, results.append)
        context = GLib.MainContext.default()
        for _ in range(500):
            if results:
                break
            context.iteration(False)
            GLib.usleep(10000)
        return results[0] if results else None

    def test_off_by_default(self):
        previews = self.previews()
        self.assertFalse(previews.enabled())
        self.assertEqual(self.wait(previews, "https://example.org/page"), {})
        self.assertEqual(self.opened, [])

    def test_fetch_cache_and_image(self):
        previews = self.previews()
        previews.set_enabled(True)
        result = self.wait(previews, "https://www.example.org/page")
        self.assertEqual(result["title"], "Randonnées d'automne")
        self.assertEqual(result["site"], "example.org")
        self.assertTrue(result["image"].startswith(self.dir))
        self.assertTrue(result["image"].endswith(".jpg"))
        self.assertTrue(os.path.isfile(result["image"]))
        self.assertEqual(len(self.opened), 2)  # the page, then its image
        # Cached, in memory and on disk: not fetched again.
        self.assertEqual(self.wait(previews, "https://www.example.org/page"), result)
        again = self.previews()
        self.assertEqual(self.wait(again, "https://www.example.org/page"), result)
        self.assertEqual(len(self.opened), 2)

    def test_private_address_gives_nothing(self):
        previews = self.previews("192.168.1.20")
        previews.set_enabled(True)
        self.assertEqual(self.wait(previews, "http://nas.example/"), {})
        self.assertEqual(self.opened, [])
        self.assertEqual(self.wait(previews, "ftp://example.org/"), {})

    def test_not_html(self):
        previews = self.previews()
        previews.set_enabled(True)
        self.assertEqual(self.wait(previews, "https://example.org/photo.jpg"), {})


if __name__ == "__main__":
    unittest.main()
