# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Modules offered on demand (Boomerang 2).

The core (notifications, battery, messages, phone and contacts, Now Playing) is always
there. Everything else is a module the user adds from the catalogue: its page joins the
sidebar (or its settings the iPhone page), and the daemon part only runs once added.
Removing a module turns its feature off; its settings are kept for a later return.

Choices live in boomerangd.conf, group [catalog], one boolean per module. The first
time Boomerang 2 runs, each module counts as added when its feature was already in use,
so an update never takes away something the user relied on.
"""

from .i18n import N_, _

# id, title, summary, icon, page in the app ("" = settings on the iPhone page),
# Debian packages it needs (installed on demand).
MODULES = (
    ("airpods", N_("AirPods"), N_("Batterie, contrôle du bruit et réglages des AirPods"),
     "io.github.melvincouwez.Boomerang.AirPods", "headphones", ()),
    ("audio", N_("Son de l'iPhone"), N_("Recevoir sur ce PC le son envoyé depuis le bouton AirPlay"),
     "audio-speakers", "", ()),
    ("icloud", N_("Services iCloud"),
     N_("Courriel, agendas, rappels et contacts iCloud ; iCloud Drive et Photos dans Fichiers"),
     "preferences-desktop-online-accounts", "services",
     ("evolution-data-server", "gir1.2-edataserver-1.2", "gir1.2-ebook-1.2",
      "gir1.2-ebookcontacts-1.2", "gir1.2-secret-1", "libsecret-tools", "fuse3")),
    ("files", N_("Envoi de fichiers"), N_("Échanger des fichiers avec l'iPhone par LocalSend"),
     "document-send", "files", ()),
    ("photos", N_("Import de photos"), N_("Copier les photos de l'iPhone branché en USB"),
     "multimedia-photo-viewer", "photos", ()),
    ("mirror", N_("Recopie d'écran"), N_("Afficher l'écran de l'iPhone sur le PC"),
     "video-display", "mirror", ()),
    ("hotspot", N_("Internet via l'iPhone"), N_("Partage de connexion de l'iPhone en Bluetooth"),
     "network-wireless", "", ()),
    ("proximity", N_("Verrouillage de proximité"), N_("Verrouiller le PC quand l'iPhone s'éloigne"),
     "system-lock-screen", "", ()),
    ("codes", N_("Codes dans le navigateur"),
     N_("Proposer les codes à usage unique dans le navigateur, y compris ceux reçus par courriel"),
     "dialog-password", "", ()),
)
IDS = tuple(m[0] for m in MODULES)
GROUP = "catalog"


def added(config, module):
    return config.boolean(GROUP, module, False)


def migrate(config, in_use):
    """First run of Boomerang 2: keep every module whose feature was in use.
    in_use: {module id: bool}. Returns the ids marked as added."""
    if config.boolean(GROUP, "migrated", False):
        return []
    kept = [m for m in IDS if in_use.get(m)]
    for module in IDS:
        config.keyfile.set_boolean(GROUP, module, module in kept)
    config.keyfile.set_boolean(GROUP, "migrated", True)
    config.save()
    return kept


def entries(config, missing_packages=()):
    """The catalogue as published on D-Bus: one dict per module."""
    missing = set(missing_packages)
    return [{"id": mid, "title": _(title), "summary": _(summary), "icon": icon, "page": page,
             "added": added(config, mid), "missing": [p for p in packages if p in missing]}
            for mid, title, summary, icon, page, packages in MODULES]
