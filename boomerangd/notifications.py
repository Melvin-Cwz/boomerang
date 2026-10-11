# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""iPhone notifications as a list (Notifications tab) and per-app choices.

The list lives in memory only (never on disk): it is what the iPhone currently
shows, as reported by ANCS since the link came up. The per-app choice ("show
on this PC or not") and the app names are kept in boomerangd.conf.
"""

import time
from collections import OrderedDict

from gi.repository import GLib

from .appicons import AppIcons

MAX_KEPT = 200


class Notifications:
    def __init__(self, config, on_changed):
        self.config = config
        self.on_changed = on_changed
        self.items = OrderedDict()  # ANCS uid -> dict
        self.icons = AppIcons(config)

    # --- app choices ---------------------------------------------------------------

    def app_enabled(self, app_id):
        return not app_id or self.config.boolean("notification-apps", app_id, True)

    def set_app_enabled(self, app_id, enabled):
        if app_id:
            self.config.keyfile.set_boolean("notification-apps", app_id, enabled)
            self.config.save()
            self.on_changed()

    # Per app, beyond on/off: how it alerts, with which sound, and whether its text shows.
    MODES = ("", "priority", "quiet")  # normal, banner and sound under Do Not Disturb, no sound

    def app_settings(self, app_id):
        """(mode, sound, private) for an iPhone app: mode "" | "priority" | "quiet", sound
        "" (the Notifications sound of Réglages), "none" or a sound value, private: the
        banner says which app, not what the notification says."""
        mode = self.config._string("notification-app-mode", app_id) if app_id else ""
        sound = self.config._string("notification-app-sound", app_id) if app_id else ""
        private = bool(app_id) and self.config.boolean("notification-app-private", app_id, False)
        return (mode if mode in self.MODES else ""), sound, private

    def set_app_settings(self, app_id, mode, sound, private):
        from .sounds import resolve
        if not app_id or mode not in self.MODES:
            raise ValueError(mode)
        sound = "" if sound in ("", "default") else sound
        if sound and sound != "none" and not resolve(sound):
            raise ValueError(sound)
        keyfile = self.config.keyfile
        for group, value in (("notification-app-mode", mode), ("notification-app-sound", sound)):
            if value:
                keyfile.set_string(group, app_id, value)
            else:
                self.config.remove_key(group, app_id)
        if private:
            keyfile.set_boolean("notification-app-private", app_id, True)
        else:
            self.config.remove_key("notification-app-private", app_id)
        self.config.save()
        self.on_changed()

    def app_named(self, app_id, name):
        if app_id and name and self.config._string("notification-app-names", app_id) != name:
            self.config.keyfile.set_string("notification-app-names", app_id, name)
            self.config.save()
            for item in self.items.values():
                if item["app"] == app_id:
                    item["app_name"] = name
            self.on_changed()

    def app_name(self, app_id, fallback=""):
        return self.config._string("notification-app-names", app_id) or fallback or app_id

    def apps(self):
        """Every app seen so far, with its choice and how many notifications are listed."""
        known = {}
        try:
            for key in self.config.keyfile.get_keys("notification-app-names")[0]:
                known[key] = 0
        except GLib.Error:
            pass
        for item in self.items.values():
            known[item["app"]] = known.get(item["app"], 0) + 1
        return sorted(({"id": app, "name": self.app_name(app), "enabled": self.app_enabled(app),
                        "count": count, "mode": self.app_settings(app)[0],
                        **self.icon_fields(app)} for app, count in known.items() if app),
                      key=lambda a: a["name"].casefold())

    # --- list ------------------------------------------------------------------------

    def seen(self, uid, app_id, app_name, title, body, category, actions=None):
        """Record one notification; True when it should pop up on the desktop."""
        if app_id and app_name and app_name != app_id and \
                not self.config._string("notification-app-names", app_id):
            self.app_named(app_id, app_name)
        self.items[uid] = {"uid": uid, "app": app_id or "",
                           "app_name": self.app_name(app_id, app_name),
                           "title": title or "", "body": body or "",
                           "time": int(time.time()), "category": int(category),
                           # iPhone action labels (e.g. « Marquer comme lu »), for the app
                           "positive": (actions or {}).get("positive", ""),
                           "negative": (actions or {}).get("negative", "")}
        self.items.move_to_end(uid)
        while len(self.items) > MAX_KEPT:
            self.items.popitem(last=False)
        self.on_changed()
        return self.app_enabled(app_id)

    def removed(self, uid):
        if self.items.pop(uid, None) is not None:
            self.on_changed()

    def clear(self):
        self.items.clear()
        self.on_changed()

    def listing(self):
        return [dict(item, **self.icon_fields(item["app"])) for item in reversed(self.items.values())]

    def icon_fields(self, app_id):
        """For the app: "icon" (themed name) or "image" (file), both possibly empty."""
        name, path = self.icons.lookup(app_id, lambda *_: self.on_changed())
        return {"icon": name, "image": path}
