# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""One-time move from the app's former names to Boomerang.

The app was called Tandem until 2026-09-27, then Covalence until 2026-10-04. Each
former name gets the same treatment (Rename(old) below); it runs at every start of
boomerangd and does nothing once done: each step first checks that there is
something to move and that the new place is free. It never logs content (paths
only). Only files an older version created are touched, by their exact names.

- ~/.config/<old> -> ~/.config/boomerang (<old>d.conf -> boomerangd.conf, sound ids,
  apps.conf keys and ids, <OLD>_* names in drive.env and photos.env)
- ~/.local/share/<old>/{messages,contacts} -> ~/.local/share/boomerang/
  (the code of an old ~/.local install in ~/.local/share/<old>/{<old>d,docs} is removed)
- ~/.local/state/<old>, ~/.cache/<old> and ~/.local/libexec/<old> (obexd, rclone)
  -> .../boomerang
- keyring: the rclone config key is copied under the new attributes, and the
  old item is cleared only once the new one reads back identical
- systemd user units: old units stopped and disabled (unit files of an old
  ~/.local install and the enablement links left by a removed package), the new
  ones enabled and started in their place
- launchers, icons, D-Bus activation and metainfo of an old ~/.local install
- GTK bookmarks pointing into the old folders (mount points do not move)
- desktop ids in mimeapps.list, in the dock and in the notification settings
- the browser native messaging manifests (com.<old>.otp) are replaced

iCloud sources in Evolution Data Server keep their <old>-icloud-* uids (see
util.ICLOUD_UID_PREFIXES).
"""

import json
import os
import re
import shutil
import subprocess

NEW = "boomerang"
NEW_ID = "io.github.melvincouwez.Boomerang"
NEW_KEY = ["application", NEW_ID, "kind", "rclone-config"]
KEY_LABEL = "Boomerang : clé de la configuration iCloud Drive"
FORMER = ("tandem", "covalence")
SUFFIXES = ("", ".Messages", ".Contacts", ".Phone", ".Headphones", ".Mirror", ".NowPlaying",
            ".Calendar")
NOTIFICATIONS = "io.elementary.notifications.applications"
BROWSER_DIRS = (".config/google-chrome", ".config/chromium", ".config/microsoft-edge",
                ".mozilla")


def _run(args, stdin=None):
    try:
        return subprocess.run(args, input=stdin, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None


def _units(old):
    """old unit -> new unit"""
    return {f"{old}d.service": f"{NEW}d.service",
            f"{old}-icloud-drive.service": f"{NEW}-icloud-drive.service",
            f"{old}-icloud-photos.service": f"{NEW}-icloud-photos.service"}


class Rename:
    def __init__(self, old, home=None, run=_run, log=print):
        self.old = old
        self.old_id = "io.github.melvincouwez." + old.capitalize()
        self.home = home or os.path.expanduser("~")
        self.run = run
        self.log = log
        env = (lambda name: os.environ.get(name)) if home is None else (lambda name: None)
        self.config = env("XDG_CONFIG_HOME") or os.path.join(self.home, ".config")
        self.data = env("XDG_DATA_HOME") or os.path.join(self.home, ".local", "share")
        self.state = env("XDG_STATE_HOME") or os.path.join(self.home, ".local", "state")
        self.cache = env("XDG_CACHE_HOME") or os.path.join(self.home, ".cache")
        self.local = os.path.join(self.home, ".local")
        # Programs of the former name still installed (a system install only for the real home).
        self.programs = [os.path.join(self.local, "bin", f"{old}d")] + (
            [f"/usr/bin/{old}d", f"/usr/lib/systemd/user/{old}d.service"] if home is None else [])
        self.done = []
        self.settled = self.failed = False  # see run_all
        self.marker = os.path.join(self.state, NEW, f"migrated-{old}")

    def _p(self, *parts):
        return os.path.join(*parts)

    # --- folders ----------------------------------------------------------------------

    def _move(self, old, new):
        if os.path.exists(old) and not os.path.exists(new):
            os.makedirs(os.path.dirname(new), exist_ok=True)
            shutil.move(old, new)
            self.done.append(f"{old} -> {new}")
            return True
        return False

    def _rewrite(self, path, fixes):
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except (FileNotFoundError, UnicodeDecodeError):
            return
        new = text
        for old, repl in fixes:
            new = re.sub(old, repl, new)
        if new != text:
            mode = os.stat(path).st_mode & 0o777
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)
            os.chmod(path, mode)
            self.done.append(f"réécrit {path}")

    def folders(self):
        old, upper, title = self.old, self.old.upper(), self.old.capitalize()
        old_conf, new_conf = self._p(self.config, old), self._p(self.config, NEW)
        self._move(old_conf, new_conf)
        self._move(self._p(new_conf, f"{old}d.conf"), self._p(new_conf, f"{NEW}d.conf"))
        # sounds chosen among the bundled ones are stored as "<name>:<id>"
        self._rewrite(self._p(new_conf, f"{NEW}d.conf"), [(rf"(?m)(=\s*){old}:", rf"\1{NEW}:")])
        self._rewrite(self._p(new_conf, "apps.conf"),
                      [(rf"\b{upper}_MODE_", f"{NEW.upper()}_MODE_"), (re.escape(self.old_id), NEW_ID)])
        for env in ("drive.env", "photos.env"):
            self._rewrite(self._p(new_conf, env),
                          [(rf"(?m)^{upper}_", f"{NEW.upper()}_"),
                           (rf"Written by {title}", "Written by Boomerang")])

        old_data, new_data = self._p(self.data, old), self._p(self.data, NEW)
        for sub in ("messages", "contacts"):
            self._move(self._p(old_data, sub), self._p(new_data, sub))
        # Code and docs of an old ~/.local install (a system install lives in /usr).
        for sub in (f"{old}d", "docs", "extension"):
            path = self._p(old_data, sub)
            if old_data.startswith(self.local) and os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
                self.done.append(f"supprimé {path}")
        try:
            os.rmdir(old_data)
        except OSError:
            pass

        self._move(self._p(self.state, old), self._p(self.state, NEW))
        self._move(self._p(self.cache, old), self._p(self.cache, NEW))
        self._move(self._p(self.local, "libexec", old), self._p(self.local, "libexec", NEW))

    # --- keyring ----------------------------------------------------------------------

    def keyring(self):
        if self.settled:
            return
        old_key = ["application", self.old_id, "kind", "rclone-config"]
        old = self.run(["secret-tool", "lookup", *old_key])
        if old is None or old.returncode != 0 or not old.stdout:
            return
        new = self.run(["secret-tool", "lookup", *NEW_KEY])
        if new is None or new.returncode != 0 or not new.stdout:
            self.run(["secret-tool", "store", "--label", KEY_LABEL, *NEW_KEY], stdin=old.stdout)
            new = self.run(["secret-tool", "lookup", *NEW_KEY])
        if new is not None and new.returncode == 0 and new.stdout == old.stdout:
            self.run(["secret-tool", "clear", *old_key])
            self.done.append("clé rclone du trousseau reprise")
        else:
            self.log("migration : clé rclone non recopiée, l'ancienne est gardée")

    # --- systemd user units --------------------------------------------------------------

    def units(self):
        units = _units(self.old)
        # A package update swaps the programs under a running daemon: the old one (enabled
        # for every user by its package, not per user) still holds the Bluetooth link.
        daemon = f"{self.old}d.service"
        state = None if self.settled else self.run(["systemctl", "--user", "is-active", daemon])
        if state is not None and state.stdout.strip() in ("active", "activating", "reloading"):
            self.run(["systemctl", "--user", "stop", daemon])
            self.done.append(f"{daemon} arrêté")
        dirs = [self._p(self.data, "systemd", "user"), self._p(self.config, "systemd", "user")]
        # Unit files of an old ~/.local install, and enablement links (<target>.wants/<unit>)
        # that may point to a unit file a removed package took away.
        found = {}
        for d in dirs:
            if not os.path.isdir(d):
                continue
            for root, _subdirs, files in os.walk(d):
                for name in files + _subdirs:
                    if name in units:
                        found.setdefault(name, []).append(self._p(root, name))
        if not found:
            return
        states = {}
        for unit, paths in found.items():
            linked = any(os.path.basename(os.path.dirname(p)).endswith(".wants") for p in paths)
            enabled = self.run(["systemctl", "--user", "is-enabled", unit])
            active = self.run(["systemctl", "--user", "is-active", unit])
            states[unit] = (linked or (enabled is not None and enabled.stdout.strip() == "enabled"),
                            active is not None and active.stdout.strip() == "active")
        # Stop the old ones first: the mounts use the same folders.
        for unit in found:
            self.run(["systemctl", "--user", "stop", unit])
            self.run(["systemctl", "--user", "disable", unit])
        for unit, paths in found.items():
            for path in paths:
                if os.path.isfile(path) or os.path.islink(path):
                    os.unlink(path)
                    self.done.append(f"supprimé {path}")
        self.run(["systemctl", "--user", "daemon-reload"])
        for unit in found:
            enabled, active = states[unit]
            new = units[unit]
            if unit == f"{self.old}d.service":
                # This process is boomerangd itself: only make it start at login.
                if enabled:
                    self.run(["systemctl", "--user", "enable", new])
                continue
            if enabled:
                self.run(["systemctl", "--user", "enable", new])
            if active:
                self.run(["systemctl", "--user", "start", new])
            self.done.append(f"{unit} -> {new}")

    # --- old ~/.local install --------------------------------------------------------------

    def launchers(self):
        share = self._p(self.local, "share")
        old = self.old
        binaries = [f"{old}d", f"{old}-icloud-signin", f"{old}-icloud-drive", f"{old}-rclone",
                    f"{old}-otp-host"] + [self.old_id + s for s in SUFFIXES]
        paths = [self._p(self.local, "bin", b) for b in binaries]
        paths += [self._p(share, "applications", self.old_id + s + ".desktop") for s in SUFFIXES]
        icons = self._p(share, "icons", "hicolor")
        if os.path.isdir(icons):
            for size in os.listdir(icons):
                paths += [self._p(icons, size, "apps", self.old_id + s + ".svg") for s in SUFFIXES]
                paths += [self._p(icons, size, "apps", self.old_id + s + ".png") for s in SUFFIXES]
        paths += [self._p(share, "metainfo", self.old_id + ".metainfo.xml"),
                  self._p(share, "dbus-1", "services", self.old_id + ".Daemon.service")]
        removed = set()
        for path in paths:
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)
                self.done.append(f"supprimé {path}")
                removed.add("icons" if path.startswith(icons) else "applications")
        if "applications" in removed:
            self.run(["update-desktop-database", self._p(share, "applications")])
        if "icons" in removed:
            self.run(["gtk-update-icon-cache", "-q", "-t", "-f", icons])

    def bookmarks(self):
        path = self._p(self.config, "gtk-3.0", "bookmarks")
        self._rewrite(path, [(re.escape("file://" + self._p(self.data, self.old)) + r"(?=[/\s])",
                              "file://" + self._p(self.data, NEW)),
                             (re.escape("file://" + self._p(self.config, self.old)) + r"(?=[/\s])",
                              "file://" + self._p(self.config, NEW))])

    # --- desktop ids remembered by the desktop ----------------------------------------------

    def desktop_ids(self):
        old_id = re.escape(self.old_id)
        self._rewrite(self._p(self.config, "mimeapps.list"), [(old_id + r"(?=[.;\s])", NEW_ID)])
        if self.settled:
            return
        # the dock's pinned launchers
        out = self.run(["gsettings", "get", "io.elementary.dock", "launchers"])
        if out is not None and out.returncode == 0 and self.old_id in out.stdout:
            value = re.sub(old_id + r"(?=[.'])", NEW_ID, out.stdout.strip())
            self.run(["gsettings", "set", "io.elementary.dock", "launchers", value])
            self.done.append("dock : lanceurs renommés")
        # per-app notification settings (bubbles, sounds, remember)
        for suffix in SUFFIXES:
            old_path = f"/io/elementary/notifications/applications/{self.old_id}{suffix}/"
            new_path = f"/io/elementary/notifications/applications/{NEW_ID}{suffix}/"
            listing = self.run(["gsettings", "list-recursively", f"{NOTIFICATIONS}:{old_path}"])
            if listing is None or listing.returncode != 0:
                continue
            dump = self.run(["dconf", "dump", old_path])
            if dump is None or dump.returncode != 0 or not dump.stdout.strip():
                continue  # nothing was changed from the defaults
            for line in listing.stdout.splitlines():
                parts = line.split(None, 2)
                if len(parts) == 3:
                    self.run(["gsettings", "set", f"{NOTIFICATIONS}:{new_path}", parts[1], parts[2]])
            self.run(["dconf", "reset", "-f", old_path])
            self.done.append(f"notifications : réglages de {self.old_id}{suffix} repris")

    def browser_hosts(self):
        name = f"com.{self.old}.otp.json"
        removed = False
        for base in BROWSER_DIRS:
            sub = "native-messaging-hosts" if base == ".mozilla" else "NativeMessagingHosts"
            path = self._p(self.home, base, sub, name)
            if os.path.isfile(path):
                os.unlink(path)
                self.done.append(f"supprimé {path}")
                removed = True
        if removed:
            from . import browser_host
            try:
                browser_host.install()
                self.done.append("hôte des codes pour le navigateur réinstallé")
            except (OSError, ValueError, json.JSONDecodeError):
                self.log("migration : hôte des codes pour le navigateur à réinstaller")

    def run_all(self):
        # A start that found nothing to move leaves a mark: later starts skip the steps that
        # need commands (keyring, systemctl, gsettings, about 19 per former name) as long as
        # no program of the former name is installed. Files are still looked at each time.
        self.settled = os.path.exists(self.marker) and not any(map(os.path.exists, self.programs))
        self.failed = False
        for step in (self.folders, self.keyring, self.units, self.launchers, self.bookmarks,
                     self.desktop_ids, self.browser_hosts):
            try:
                step()
            except OSError as e:
                self.failed = True
                self.log(f"migration : étape {step.__name__} incomplète ({e.strerror})")
        if self.done:
            self.log(f"migration depuis {self.old.capitalize()} : {len(self.done)} élément(s) repris")
        return self.done


def migrate(log=print, home=None, run=_run):
    done, marks = [], []
    for old in FORMER:
        rename = Rename(old, home=home, run=run, log=log)
        moved = rename.run_all()
        done += moved
        if not moved and not rename.failed and not rename.settled:
            marks.append(rename.marker)
    # Marked once every former name ran: a marker folder must not stand in the way of a move.
    for marker in marks:
        try:
            os.makedirs(os.path.dirname(marker), exist_ok=True)
            open(marker, "w").close()
        except OSError:
            pass
    return done
