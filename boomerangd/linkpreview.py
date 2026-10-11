# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Link previews in conversations: title, description and image of a web page.

Off by default ([messages] link_previews): fetching a preview tells the site that
someone opened the conversation. Only public http(s) addresses are fetched (never
the loopback, the local network or link-local ones, redirects included), with a
short timeout and size limits. Results are kept for a week in
~/.cache/boomerang/link-previews (index.json plus the images), and the journal
never gets the address.
"""

import hashlib
import html.parser
import ipaddress
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from gi.repository import GLib

from . import cachedir
from .util import log

TIMEOUT = 6  # seconds, per request
MAX_HTML = 512 * 1024
MAX_IMAGE = 2 * 1024 * 1024
KEEP_DAYS = 7
KEEP_FAILED = 3600  # seconds: a page that failed is not asked again before this
MAX_FILES = 300
MAX_TITLE = 300
MAX_DESCRIPTION = 500
WORKERS = 3  # fetches at the same time
IMAGE_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/gif": ".gif",
               "image/webp": ".webp"}
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) Boomerang link preview"
INDEX = "index.json"
KEYS = ("title", "description", "site", "image")


class Refused(Exception):
    """An address Boomerang does not fetch (not http(s), or not a public host)."""


def _public_host(host, resolver=socket.getaddrinfo):
    """True when every address of host is a public one."""
    if not host:
        return False
    try:
        infos = resolver(host, None, 0, socket.SOCK_STREAM)
    except (OSError, UnicodeError):
        return False
    if not infos:
        return False
    for info in infos:
        try:
            ip = ipaddress.ip_address(info[4][0].split("%", 1)[0])
        except ValueError:
            return False
        if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        if not ip.is_global or ip.is_multicast:
            return False
    return True


def check_url(url, resolver=socket.getaddrinfo):
    """Raise Refused unless url is http(s) on a public host."""
    try:
        parts = urllib.parse.urlsplit(url)
    except ValueError as error:
        raise Refused("adresse illisible") from error
    if parts.scheme not in ("http", "https"):
        raise Refused("ni http ni https")
    if parts.username or parts.password:
        raise Refused("identifiants dans l'adresse")
    if not _public_host(parts.hostname, resolver):
        raise Refused("adresse privée ou introuvable")


class _Redirects(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to another public http(s) address."""

    def __init__(self, resolver):
        super().__init__()
        self.resolver = resolver

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_url(newurl, self.resolver)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _opener(resolver):
    # No file:, ftp: or data: handlers: only what check_url lets through.
    opener = urllib.request.OpenerDirector()
    for handler in (urllib.request.ProxyHandler(), urllib.request.HTTPHandler(),
                    urllib.request.HTTPSHandler(), urllib.request.HTTPDefaultErrorHandler(),
                    urllib.request.HTTPErrorProcessor(), _Redirects(resolver)):
        opener.add_handler(handler)
    return opener


def urlopen(url, resolver=socket.getaddrinfo, accept="text/html"):
    """Open a public http(s) address; the caller reads and closes the response."""
    check_url(url, resolver)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    return _opener(resolver).open(request, timeout=TIMEOUT)


class _MetaParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.meta = {}
        self.title = ""
        self.in_title = False
        self.done = False

    def handle_starttag(self, tag, attrs):
        if self.done:
            return
        if tag == "title":
            self.in_title = not self.title
        elif tag == "meta":
            attrs = {k.lower(): (v or "") for k, v in attrs if k}
            name = (attrs.get("property") or attrs.get("name") or "").strip().lower()
            if name and "content" in attrs:
                self.meta.setdefault(name, attrs["content"].strip())

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        elif tag in ("head", "body"):
            self.done = True  # everything needed is in <head>

    def handle_data(self, data):
        if self.in_title and not self.done:
            self.title += data


def _clean(text, size):
    text = " ".join((text or "").split())
    return text if len(text) <= size else text[:size - 1] + "…"


def parse(text, base_url):
    """{title, description, image (absolute URL, may be "")} from a page's HTML."""
    parser = _MetaParser()
    try:
        parser.feed(text)
        parser.close()
    except Exception:  # noqa: BLE001 - a broken page gives what was read so far
        pass
    meta = parser.meta
    title = meta.get("og:title") or meta.get("twitter:title") or parser.title
    description = meta.get("og:description") or meta.get("twitter:description") \
        or meta.get("description")
    image = meta.get("og:image") or meta.get("og:image:url") or meta.get("twitter:image") \
        or meta.get("twitter:image:src") or ""
    if image:
        image = urllib.parse.urljoin(base_url, image)
        if urllib.parse.urlsplit(image).scheme not in ("http", "https"):
            image = ""
    return {"title": _clean(title, MAX_TITLE), "description": _clean(description, MAX_DESCRIPTION),
            "image": image}


def _charset(response, head):
    charset = response.headers.get_content_charset()
    if not charset:
        lower = head[:2048].lower()
        index = lower.find(b"charset=")
        if index >= 0:
            value = lower[index + 8:index + 48].strip(b"\"' ")
            charset = value.split(b"\"")[0].split(b"'")[0].split(b";")[0].split(b">")[0] \
                .split(b"/")[0].strip().decode("ascii", "ignore")
    try:
        "".encode(charset or "utf-8")
    except LookupError:
        charset = "utf-8"
    return charset or "utf-8"


def _read(response, limit):
    data = response.read(limit + 1)
    return data[:limit], len(data) > limit


def fetch(url, directory, resolver=socket.getaddrinfo, open_url=None):
    """The preview of url, its image saved in directory. Runs in a worker thread.
    Raises Refused, OSError (network, timeout) or ValueError (not a page)."""
    open_url = open_url or urlopen
    with open_url(url, resolver) as response:
        kind = response.headers.get_content_type()
        if kind != "text/html":
            raise ValueError("pas une page web")
        data, _cut = _read(response, MAX_HTML)
        final = response.geturl() or url
        text = data.decode(_charset(response, data), "replace")
    found = parse(text, final)
    site = (urllib.parse.urlsplit(final).hostname or "").removeprefix("www.")
    result = {"title": found["title"], "description": found["description"], "site": site,
              "image": ""}
    if not result["title"] and not result["description"]:
        raise ValueError("page sans titre")
    if found["image"]:
        try:
            result["image"] = _fetch_image(found["image"], url, directory, resolver, open_url)
        except (Refused, OSError, ValueError):
            pass  # a preview without its image
    return result


def _fetch_image(image_url, page_url, directory, resolver, open_url):
    with open_url(image_url, resolver, accept="image/*") as response:
        ext = IMAGE_TYPES.get(response.headers.get_content_type())
        if not ext:
            raise ValueError("pas une image")
        data, cut = _read(response, MAX_IMAGE)
    if cut or not data:
        raise ValueError("image trop lourde")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    path = os.path.join(directory, _digest(page_url) + ext)
    partial = path + ".part"
    with open(partial, "wb") as f:
        f.write(data)
    os.replace(partial, path)
    return path


def _digest(url):
    return hashlib.sha1(url.encode()).hexdigest()


class LinkPreviews:
    def __init__(self, config, directory=None, resolver=socket.getaddrinfo, open_url=None,
                 clock=time.time):
        self.config = config
        self.dir = directory or os.path.join(GLib.get_user_cache_dir(), "boomerang",
                                             "link-previews")
        self.resolver = resolver
        self.open_url = open_url
        self.clock = clock
        self.index = None  # sha1(url) -> {time, title, description, site, image}; lazy
        self.failed = {}  # sha1(url) -> time of the failure, in memory only
        self.pending = {}  # sha1(url) -> callbacks waiting for the same fetch
        self.slots = threading.BoundedSemaphore(WORKERS)

    def enabled(self):
        return bool(self.config and self.config.boolean("messages", "link_previews", False))

    def set_enabled(self, enabled):
        self.config.set_boolean("messages", "link_previews", bool(enabled))
        log(f"messages : aperçus de liens {'activés' if enabled else 'désactivés'}")

    # --- cache -------------------------------------------------------------------------------

    def _load(self):
        if self.index is not None:
            return
        self.index = {}
        try:
            with open(os.path.join(self.dir, INDEX), encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                self.index = {k: v for k, v in data.items() if isinstance(v, dict)}
        except (OSError, ValueError):
            pass
        self._prune()

    def _prune(self):
        limit = self.clock() - KEEP_DAYS * 86400
        for digest, entry in list(self.index.items()):
            image = entry.get("image") or ""
            if entry.get("time", 0) < limit or (image and not os.path.isfile(image)):
                self.index.pop(digest)
        if len(self.index) > MAX_FILES:
            for digest, _entry in sorted(self.index.items(),
                                         key=lambda item: item[1].get("time", 0))[:len(self.index) - MAX_FILES]:
                self.index.pop(digest)
        # Images no entry points to any more (and leftovers of an interrupted download).
        keep = {os.path.basename(e.get("image") or "") for e in self.index.values()} | {INDEX}
        try:
            names = os.listdir(self.dir)
        except OSError:
            names = []
        for name in names:
            if name not in keep:
                try:
                    os.unlink(os.path.join(self.dir, name))
                except OSError:
                    pass
        cachedir.prune(self.dir, MAX_FILES + 1, KEEP_DAYS)

    def _save(self):
        try:
            os.makedirs(self.dir, mode=0o700, exist_ok=True)
            partial = os.path.join(self.dir, INDEX + ".part")
            with open(partial, "w", encoding="utf-8") as f:
                json.dump(self.index, f, ensure_ascii=False)
            os.replace(partial, os.path.join(self.dir, INDEX))
        except OSError as error:
            log(f"messages : cache des aperçus non enregistré ({error.strerror})")

    def cached(self, url):
        """The preview kept for url, or None."""
        self._load()
        entry = self.index.get(_digest(url))
        if not entry or entry.get("time", 0) < self.clock() - KEEP_DAYS * 86400:
            return None
        if entry.get("image") and not os.path.isfile(entry["image"]):
            return None
        return {k: str(entry.get(k) or "") for k in KEYS}

    # --- API -------------------------------------------------------------------------------

    def get(self, url, on_done):
        """on_done(preview dict, {} when there is none), on the main loop. Never blocks:
        the page is fetched in a worker thread."""
        url = (url or "").strip()
        if not self.enabled() or len(url) > 4096 or \
                urllib.parse.urlsplit(url).scheme not in ("http", "https"):
            on_done({})
            return
        found = self.cached(url)
        if found is not None:
            on_done(found)
            return
        digest = _digest(url)
        if self.clock() - self.failed.get(digest, -KEEP_FAILED) < KEEP_FAILED:
            on_done({})
            return
        if digest in self.pending:
            self.pending[digest].append(on_done)
            return
        self.pending[digest] = [on_done]
        threading.Thread(target=self._work, args=(url, digest), daemon=True,
                         name="link-preview").start()

    def _work(self, url, digest):
        result, reason = None, ""
        with self.slots:
            try:
                result = fetch(url, self.dir, self.resolver, self.open_url)
            except Refused as error:
                reason = str(error)
            except (OSError, ValueError, urllib.error.URLError) as error:
                reason = error.__class__.__name__
            except Exception as error:  # noqa: BLE001 - a worker must always answer
                reason = error.__class__.__name__
        GLib.idle_add(self._finish, digest, result, reason)

    def _finish(self, digest, result, reason):
        self._load()
        if result is None:
            now = self.clock()  # failures older than KEEP_FAILED count for nothing: drop them
            self.failed = {d: t for d, t in self.failed.items() if now - t < KEEP_FAILED}
            self.failed[digest] = now
            log(f"messages : aperçu de lien impossible ({reason})")  # never the address
        else:
            self.index[digest] = dict(result, time=self.clock())
            self._prune()
            self._save()
            log("messages : aperçu de lien récupéré")
        for callback in self.pending.pop(digest, []):
            callback(dict(result) if result else {})
        return GLib.SOURCE_REMOVE
