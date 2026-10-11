# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Optional apps Boomerang offers to install: Agenda and Cassette.

Each one is published in the releases of its own GitHub repository
(Melvin-Cwz/agenda, Melvin-Cwz/cassette); the releases up to
0.6.0 (under the name Covalence) carried them too and are read as a fallback. Installing one goes the same way as an update of
Boomerang (updates.py): the newest release carrying the package is found, its .deb
is downloaded to ~/.cache/boomerang/apps, checked against the SHA-256 digest GitHub
publishes, then `pkexec boomerang-install-update <deb> <sha256> <package>` installs
it; that helper only accepts the packages it names. Nothing happens without the
user's click, and nothing is fetched until the user opens the page offering them.
"""

import os
import threading

from gi.repository import Gio, GLib

from .i18n import _
from .updates import (RELEASES, _arch, _get_json, deb_asset, download_verified,
                      pkexec_install, version_key)
from .util import log

# package -> desktop id of the app it installs
CATALOG = {"agenda": "io.github.melvincouwez.Agenda",
           "cassette": "io.github.melvincouwez.Cassette"}

# package -> the releases of its own repository
SOURCES = {"agenda": "https://api.github.com/repos/Melvin-Cwz/agenda/releases",
           "cassette": "https://api.github.com/repos/Melvin-Cwz/cassette/releases"}

TYPES = {"state": "s", "version": "s", "size": "x", "progress": "d", "error": "s",
         "installed": "b"}


def newest_with(releases, package, arch):
    """(release, url, size, sha) of the newest non-draft release carrying the package."""
    best = None
    for release in releases or []:
        if not isinstance(release, dict) or release.get("draft"):
            continue
        url, size, sha = deb_asset(release, arch, package)
        if not url:
            continue
        key = version_key(release.get("tag_name") or "")
        if key is not None and (best is None or key > best[0]):
            best = (key, release, url, size, sha)
    return best[1:] if best else None


def package_version(url):
    """Version in a Debian file name: agenda_0.1.1_amd64.deb -> 0.1.1."""
    parts = url.rsplit("/", 1)[-1].split("_")
    return parts[1] if len(parts) == 3 else ""


def _reason(failure):
    """Short, translated reason for a failed download."""
    if isinstance(failure, ValueError):
        return _("le fichier ne correspond pas à son empreinte SHA-256")
    if isinstance(failure, OSError):
        return _("connexion impossible")
    return type(failure).__name__


def _installed(package):
    return Gio.DesktopAppInfo.new(CATALOG[package] + ".desktop") is not None


class OptionalApps:
    def __init__(self, on_changed, fetch=_get_json, cache_dir=None):
        self.on_changed = on_changed
        self.fetch = fetch
        self.dir = cache_dir or os.path.join(GLib.get_user_cache_dir(), "boomerang", "apps")
        self.found = {}                               # package -> (release, url, size, sha)
        self.states = {p: {"state": "idle", "progress": 0.0, "error": ""} for p in CATALOG}
        self.checking = False

    def state(self):
        result = {}
        for package in CATALOG:
            found = self.found.get(package)
            version = package_version(found[1]) if found else ""
            entry = dict(self.states[package], version=version, size=found[2] if found else 0,
                         installed=_installed(package))
            result[package] = {k: v for k, v in entry.items() if k in TYPES}
        return result

    def _changed(self):
        if self.on_changed:
            self.on_changed()

    def check(self):
        """Look for the packages in their repositories (one GET each, in a thread)."""
        if self.checking:
            return
        self.checking = True

        def job():
            found, errors = {}, []
            fallback = None
            for package in CATALOG:
                try:
                    hit = newest_with(self.fetch(SOURCES[package]), package, _arch())
                except Exception as failure:
                    hit = None
                    errors.append(f"{package}: {type(failure).__name__}")
                if hit is None:
                    try:
                        if fallback is None:
                            fallback = self.fetch(RELEASES)
                        hit = newest_with(fallback, package, _arch())
                    except Exception as failure:
                        errors.append(f"boomerang: {type(failure).__name__}")
                if hit:
                    found[package] = hit
            GLib.idle_add(lambda: self._checked(found, errors) and False)

        threading.Thread(target=job, name="boomerang-apps-check", daemon=True).start()

    def _checked(self, found, errors):
        self.checking = False
        if errors:
            log(f"apps : liste des versions incomplète ({', '.join(errors)})")
        self.found.update(found)
        self._changed()

    def install(self, package, on_done):
        """on_done(error or None); progress and outcome also go through state()."""
        if package not in CATALOG:
            return on_done(_("application inconnue"))
        state = self.states[package]
        if state["state"] in ("downloading", "installing"):
            return on_done(None)
        found = self.found.get(package)
        if not found or not found[3]:
            return on_done(_("pas de paquet vérifiable pour cette application"))
        _release, url, size, sha = found
        if not url.startswith(("https://github.com/", "https://objects.githubusercontent.com/")):
            return on_done(_("adresse de téléchargement inattendue"))
        state.update(state="downloading", progress=0.0, error="")
        self._changed()
        target = os.path.join(self.dir, url.rsplit("/", 1)[-1])

        def report(fraction):
            state["progress"] = fraction * 0.9
            self._changed()
            return False

        def job():
            error = None
            try:
                os.makedirs(self.dir, mode=0o700, exist_ok=True)
                download_verified(url, size, sha, target, report)
            except Exception as failure:
                error = _reason(failure)
            GLib.idle_add(lambda: self._downloaded(package, target, sha, error, on_done) and False)

        threading.Thread(target=job, name="boomerang-apps-download", daemon=True).start()

    def _downloaded(self, package, target, sha, error, on_done):
        state = self.states[package]
        if error:
            return self._failed(package, _("Téléchargement impossible ({reason})").format(reason=error), on_done)
        state.update(state="installing", progress=0.9)
        self._changed()

        def installed():
            state.update(state="idle", progress=1.0, error="")
            log(f"apps : {package} installée")
            self._changed()
            on_done(None)

        pkexec_install([target, sha, package], installed,
                       lambda message: self._failed(package, message, on_done))

    def _failed(self, package, message, on_done):
        self.states[package].update(state="error", error=message, progress=0.0)
        log(f"apps : échec de l'installation de {package}")
        self._changed()
        on_done(message)
