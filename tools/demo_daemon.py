#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Stand-in for boomerangd with made-up data, for screenshots and demos.

It serves the real D-Bus interface (boomerangd.service.XML) under another bus
name, so it never touches Bluetooth, iCloud or the user's messages:

    python3 tools/demo_daemon.py &
    BOOMERANG_DAEMON_NAME=io.github.melvincouwez.Boomerang.Demo \\
        BOOMERANG_SNAPSHOT=/tmp/shot.png build/src/io.github.melvincouwez.Boomerang --page messages

Everything shown (people, numbers, messages, notifications) is fictitious.
"""

import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from gi.repository import Gio, GLib  # noqa: E402

from boomerangd import __version__, service  # noqa: E402
from boomerangd.headphones import features_for  # noqa: E402
from boomerangd.util import APP_ID  # noqa: E402

# BOOMERANG_DEMO_BUS picks another name, so that two demo runs never collide.
DEMO_NAME = os.environ.get("BOOMERANG_DEMO_BUS", "io.github.melvincouwez.Boomerang.Demo")
ARTWORK = ""
NOW = int(time.time())
MIN, HOUR, DAY = 60, 3600, 86400

PROPS = {
    "LinkState": os.environ.get("BOOMERANG_DEMO_LINK", "complete"),
    "Version": __version__, "BluetoothAvailable": True, "Advertising": True, "Pairing": False, "LinkProblem": "", "AdapterName": "Boomerang-PC",
    "DeviceName": "iPhone de Camille", "DeviceAddress": "00:11:22:33:44:55", "Paired": True,
    "Connected": True, "NotificationsLinked": True, "MediaLinked": True, "CallsLinked": True,
    "CallsSupported": True, "Battery": 78, "ICloudState": "connected", "MessagesState": "ready",
    "MessagesSend": "yes", "ReactionsSend": True, "ContactsState": "ready", "AudioOnPC": True, "MicMuted": False,
    "PhoneAudio": "idle", "PhoneAudioOutput": "", "ContactsSource": "bluetooth",
    "ContactsBook": "", "UnreadMessages": 2, "MissedCalls": 1, "LinkPreviews": True,
    "Modules": {m: True for m in ("notifications", "media", "calls", "battery", "messages",
                                  "icloud")},
}
# BOOMERANG_DEMO_LINK=absent and the like: the rest of the demo agrees with it.
if PROPS["LinkState"] not in ("complete", "classic"):
    PROPS.update({"Connected": False, "NotificationsLinked": False, "MediaLinked": False,
                  "CallsLinked": False, "MessagesState": "absent", "Battery": -1})

# Demo data in the language of the screenshot (BOOMERANG_DEMO_LANG, else LANGUAGE).
LANG = (os.environ.get("BOOMERANG_DEMO_LANG") or os.environ.get("LANGUAGE") or "fr")[:2]
EN = LANG == "en"

PEOPLE = [
    ("Alice Martin", "+33600000001"), ("Bob Leroy", "+33600000002"),
    ("Mum" if EN else "Maman", "+33600000003"), ("Chloé Bernard", "+33600000004"),
    ("David Petit", "+33600000005"), ("Emma Robert", "+33600000006"),
    ("Hugo Richard", "+33600000007"), ("Léa Dubois", "+33600000008"),
]

# Per-conversation alerts: thread -> (mode, sound).
APP_NOTIFY = {"com.apple.mobilemail": ("priority", "", True), "com.apple.reminders": ("quiet", "", False)}
THREAD_NOTIFY = {"t1": ("priority", "boomerang:carillon"), "t3": ("mute", "")}

if EN:
    PROPS["DeviceName"] = "Camille's iPhone"
    PROPS["QuickReplies"] = ["On my way", "I'll call you back", "OK 👍", "Thanks!",
                             "Busy, I'll answer soon"]
    LINK_PREVIEW = {"title": "Autumn hikes: ten trails near the city",
                    "description": "Forests, ridges and lakes within an hour by train.",
                    "site": "example.org", "image": ""}
    THREADS = {
        "t1": ("Mum", "+33600000003", [
            (False, "Hi! Are you coming for lunch on Sunday?", 3 * HOUR),
            (True, "Yes, I'll be there around half past twelve 🙂", 3 * HOUR - 5 * MIN),
            (False, "Perfect, I'm making lasagne.", 2 * HOUR),
            (False, "Don't forget the bread!", 20 * MIN),
        ], 1),
        "t2": ("Alice Martin", "+33600000001", [
            (False, "The meeting has moved to 3 pm.", DAY + 2 * HOUR),
            (True, "Thanks, noted.", DAY + HOUR),
            (False, "I'll send you the minutes tonight.", 45 * MIN),
        ], 1),
        "t3": ("Bob Leroy", "+33600000002", [
            (True, "Cinema at 8 pm?", 2 * DAY),
            (False, "Sure, I'll book the seats.", 2 * DAY - 10 * MIN),
        ], 0),
        "t4": ("Chloé Bernard", "+33600000004", [
            (False, "Your parcel arrived at my place 📦", 4 * DAY),
        ], 0),
    }
    NOTIFICATIONS = [
        (1, "com.example.chatter", "Chatter", "Bob Leroy", "Weekend photo 📷", 4 * MIN,
         "internet-chat"),
        (2, "com.apple.mobilemail", "Mail", "Club newsletter", "This season's programme", 18 * MIN,
         "io.elementary.mail"),
        (3, "com.apple.mobilecal", "Calendar", "Dentist", "Tomorrow at 9:30", HOUR,
         "io.github.melvincouwez.Boomerang.Calendar"),
        (4, "com.apple.reminders", "Reminders", "Water the plants", "", 2 * HOUR,
         "io.elementary.tasks"),
    ]
else:
    PROPS["QuickReplies"] = ["J'arrive", "Je te rappelle", "OK 👍", "Merci !",
                             "Je suis occupé, je te réponds vite"]
    LINK_PREVIEW = {"title": "Randonnées d'automne : dix sentiers près de la ville",
                    "description": "Forêts, crêtes et lacs à moins d'une heure de train.",
                    "site": "example.org", "image": ""}
    THREADS = {
        "t1": ("Maman", "+33600000003", [
            (False, "Coucou ! Tu passes dimanche midi ?", 3 * HOUR),
            (True, "Oui, j'arrive vers midi et demi 🙂", 3 * HOUR - 5 * MIN),
            (False, "Parfait, je fais des lasagnes.", 2 * HOUR),
            (False, "N'oublie pas le pain !", 20 * MIN),
        ], 1),
        "t2": ("Alice Martin", "+33600000001", [
            (False, "La réunion est déplacée à 15 h.", DAY + 2 * HOUR),
            (True, "Merci, c'est noté.", DAY + HOUR),
            (False, "Je t'envoie le compte rendu ce soir.", 45 * MIN),
        ], 1),
        "t3": ("Bob Leroy", "+33600000002", [
            (True, "On se retrouve au cinéma à 20 h ?", 2 * DAY),
            (False, "Carrément, je prends les places.", 2 * DAY - 10 * MIN),
        ], 0),
        "t4": ("Chloé Bernard", "+33600000004", [
            (False, "Ton colis est arrivé chez moi 📦", 4 * DAY),
        ], 0),
    }
    NOTIFICATIONS = [
        (1, "com.example.chatter", "Bavard", "Bob Leroy", "Photo du week-end 📷", 4 * MIN,
         "internet-chat"),
        (2, "com.apple.mobilemail", "Mail", "Newsletter du club", "Programme de la saison", 18 * MIN,
         "io.elementary.mail"),
        (3, "com.apple.mobilecal", "Calendrier", "Dentiste", "Demain à 9:30", HOUR,
         "io.github.melvincouwez.Boomerang.Calendar"),
        (4, "com.apple.reminders", "Rappels", "Arroser les plantes", "", 2 * HOUR,
         "io.elementary.tasks"),
    ]


# Richer conversations for the Messages screens: a link and a photo (attachment) with
# Alice, a sender who is not in the contacts, a long history to page through.
ATTACHMENT = {"attachment": True}
THREADS["t2"][2][1:1] = [
    (False, ("Here are the trails: https://example.org/hikes" if EN else
             "Voici les sentiers : https://example.org/randonnees"), DAY + 110 * MIN),
    (False, "", DAY + 100 * MIN, ATTACHMENT),
]
THREADS["t5"] = ("06 12 34 56 78", "+33612345678", [
    (False, ("Your appointment on Thursday at 10 am is confirmed." if EN else
             "Votre rendez-vous de jeudi à 10 h est confirmé."), 5 * DAY),
], 0)
THREADS["t6"] = ("Hugo Richard", "+33600000007", [
    (i % 3 == 0, (f"Message {i + 1} of the hike club chat" if EN else
                  f"Message {i + 1} de la discussion du club de randonnée"),
     6 * DAY + (320 - i) * 20 * MIN) for i in range(320)
], 0)
KNOWN = {number for _, number in PEOPLE}


def demo_artwork():
    """A made-up cover (soft gradient with a sun), drawn here: no real album art."""
    import math
    import tempfile
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
    size = 300
    pixels = bytearray(size * size * 3)
    for y in range(size):
        for x in range(size):
            t = y / size
            r, g, b = 255 - 90 * t, 140 + 40 * t, 90 + 140 * t
            d = math.hypot(x - 190, y - 120)
            if d < 55:
                r, g, b = 255, 225, 140
            elif y > 210 + 12 * math.sin(x / 25):
                r, g, b = 60 + 20 * t, 50, 110
            i = (y * size + x) * 3
            pixels[i:i + 3] = bytes((int(r), int(g), int(b)))
    pixbuf = GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(pixels)),
                                             GdkPixbuf.Colorspace.RGB, False, 8, size, size,
                                             size * 3)
    path = os.path.join(tempfile.mkdtemp(prefix="boomerang-demo-"), "cover.png")
    pixbuf.savev(path, "png", [], [])
    return path


def now_playing():
    if os.environ.get("BOOMERANG_DEMO_NOWPLAYING") == "0":
        return {"source": "avrcp-control", "status": "stopped", "volume": -1.0,
                "can_play": True}
    return {"source": "ams", "app": "Music" if EN else "Musique", "app_icon": "io.github.melvincouwez.Boomerang.NowPlaying", "app_image": "",
            "title": "October Light" if EN else "Lumière d'octobre",
            "artist": "The Evening Travellers" if EN else "Les Voyageurs du Soir",
            "album": "Horizons", "duration": 214.0, "position": 83.0,
            "position_time": time.time(), "rate": 1.0, "status": "playing", "volume": 0.6,
            "can_volume": True, "artwork": ARTWORK, "can_play": True,
            "commands": ["play", "pause", "toggle", "next", "previous", "volume-up",
                         "volume-down"]}


def v(sig, value):
    return GLib.Variant(sig, value)


def dicts(items, types):
    return service._dicts(items, types)


def threads():
    out = []
    for tid, (name, number, msgs, unread) in THREADS.items():
        last = msgs[-1]
        out.append({"id": tid, "name": name, "snippet": last[1], "time": NOW - last[2],
                    "unread": unread, "group": False, "outgoing": last[0], "can_send": True,
                    "participants": [number], "avatar": "", "draft": "",
                    "known": number in KNOWN})
    return sorted(out, key=lambda t: -t["time"])


# Made-up reactions: (thread, message index) -> [(emoji, author, mine, pending)]
REACTIONS = {
    ("t1", 1): [("❤️", "Maman", False, False)],
    ("t1", 2): [("😂", "Moi", True, False)],
    ("t3", 0): [("👍", "Bob Leroy", False, False)],
    ("t2", 0): [("‼️", "Moi", True, True)],
}


def messages(tid):
    name, number, msgs, _ = THREADS.get(tid, ("", "", [], 0))
    return [{"id": f"{tid}-{i}", "outgoing": m[0], "sender": "" if m[0] else name,
             "address": "" if m[0] else number, "time": NOW - m[2], "body": m[1],
             "complete": True, "source": "map", "status": "sent" if m[0] else "", "avatar": "",
             "reactions": REACTIONS.get((tid, i), []),
             "attachment": len(m) > 3 and m[3].get("attachment", False)}
            for i, m in enumerate(msgs)]


def links(tid):
    from boomerangd.messages import links_in
    found = []
    for m in reversed(messages(tid)):
        for url in links_in(m["body"]):
            if url not in [f["url"] for f in found]:
                found.append({"url": url, "time": m["time"], "outgoing": m["outgoing"],
                              "message": m["id"]})
    return found


def messages_page(tid, before_time, before_id, count):
    """GetMessagesPage over the made-up thread: `count` messages older than the cursor."""
    msgs = messages(tid)
    end = len(msgs)
    if before_time:
        ids = [m["id"] for m in msgs]
        end = ids.index(before_id) if before_id in ids else \
            sum(1 for m in msgs if m["time"] < before_time)
    start = max(0, end - max(1, count))
    return msgs[start:end], start > 0


FAVORITES = {"+33600000003", "+33600000001", "+33600000008"}


# Whole cards for the Contacts page (made up). BOOMERANG_DEMO_CONTACTS=icloud: the
# editable iCloud source, so the editor and the import can be shown.
if os.environ.get("BOOMERANG_DEMO_CONTACTS") == "icloud":
    PROPS.update({"ContactsSource": "icloud", "ContactsBook": "ready"})
CARD_EXTRAS = {
    "Alice Martin": {"nickname": "Lili", "org": "Atelier Nord", "title": "Architecte",
                     "phones": [("mobile", "+33600000001"), ("travail", "+33123456789")],
                     "emails": [("travail", "alice@atelier-nord.example")],
                     "addresses": [("travail", "12 rue des Lilas", "Lyon", "", "69003", "France")],
                     "urls": [("accueil", "https://atelier-nord.example")],
                     "birthday": "1990-05-12", "dates": [("anniversaire", "2016-06-18")],
                     "note": "Préfère être appelée après 18 h." if not EN else
                     "Rather be called after 6 pm."},
    "Chloé Bernard": {"org": "Voiles du Port", "birthday": "--11-03",
                      "emails": [("domicile", "chloe@example.org")]},
}


def _demo_card(i, name, number):
    given, _, family = name.partition(" ")
    card = {"key": f"c{i}", "uid": f"c{i}", "name": name, "given": given, "family": family,
            "photo": "", "phones": [("mobile", number)]}
    card.update(CARD_EXTRAS.get(name, {}))
    return card


CARDS = {f"c{i}": _demo_card(i, n, a) for i, (n, a) in enumerate(PEOPLE)}


def _addresses(card):
    from boomerangd.bmsg import normalize_address
    return [normalize_address(v) for _, v in card.get("phones", []) + card.get("emails", [])]


def contacts():
    return sorted(({"name": c["name"], "addresses": _addresses(c), "photo": c.get("photo", ""),
                    "uid": c["uid"], "key": c["key"], "given": c.get("given", ""),
                    "family": c.get("family", ""), "org": c.get("org", ""),
                    "favorite": any(a in FAVORITES for _, a in c.get("phones", []))}
                   for c in CARDS.values()), key=lambda c: c["name"].casefold())


def contact_details(key):
    from boomerangd import vcard
    card = vcard.empty_card()
    card.update({k: v for k, v in CARDS.get(key, {}).items() if k in card or k == "photo"})
    card["photo"] = CARDS.get(key, {}).get("photo", "")
    return {k: v for k, v in card.items() if k in service.DETAIL_TYPES}


def save_contact(conn, card):
    import tempfile
    key = card.get("uid") or f"c{len(CARDS) + 100}"
    entry = CARDS.setdefault(key, {"key": key, "uid": key, "photo": ""})
    for field, value in card.items():
        if field in ("phones", "emails", "addresses", "urls", "dates"):
            entry[field] = [tuple(item) for item in value]
        elif field == "photo_data" and value:
            path = os.path.join(tempfile.mkdtemp(prefix="boomerang-demo-"), "photo")
            with open(path, "wb") as f:
                f.write(bytes(value))
            entry["photo"] = path
        elif field == "photo_remove" and value:
            entry["photo"] = ""
        elif field in service.CARD_TYPES and field not in ("photo", "photo_data", "uid"):
            entry[field] = value
    entry["name"] = " ".join(p for p in (entry.get("given", ""), entry.get("family", "")) if p) \
        or entry.get("org", "") or entry.get("name", "")
    conn.emit_signal(None, service.PATH, service.INTERFACE, "ContactsChanged", None)
    return key


def export_contacts(keys):
    from boomerangd import vcard
    cards = []
    for key in keys or list(CARDS):
        card = vcard.empty_card()
        card.update({k: v for k, v in CARDS.get(key, {}).items() if k in card and k != "photo"})
        cards.append(card)
    return vcard.serialize_all(cards)


def preview_import(text):
    from boomerangd import contacts as book
    return book.preview(text, contacts())


def import_contacts(conn, text):
    from boomerangd import contacts as book, vcard
    report = {"added": 0, "duplicates": 0, "failed": 0, "names": []}
    for card in vcard.parse(text):
        if book.is_duplicate(card, contacts()):
            report["duplicates"] += 1
            continue
        key = f"c{len(CARDS) + 100}"
        CARDS[key] = dict({k: card[k] for k in ("name", "given", "family", "org", "title",
                                                "nickname", "note", "birthday", "phones",
                                                "emails", "addresses", "urls", "dates")},
                          key=key, uid=key, photo="")
        report["added"] += 1
        report["names"].append(card["name"])
    conn.emit_signal(None, service.PATH, service.INTERFACE, "ContactsChanged", None)
    return report


def calls():
    kinds = ["received", "missed", "dialed", "received", "dialed", "received"]
    # Lengths measured on the PC for some calls; -1: not followed by the PC.
    durations = [754, -1, 192, -1, 3725, 48]
    return [{"address": PEOPLE[i][1], "name": PEOPLE[i][0], "time": NOW - (i + 1) * 5 * HOUR,
             "kind": kinds[i], "avatar": "", "duration": durations[i]} for i in range(len(kinds))]


# Calls going on, picked with BOOMERANG_DEMO_CALL: incoming, outgoing, active, waiting
# (a second call during a call), held (two calls, one on hold), conference, resume (a
# lone held call). Actions from the app change them like the iPhone would.
CALL_PATH = "/io/github/melvincouwez/Boomerang/demo/call"
DEMO_CALLS = {}  # path -> {"state", "name", "number", "multiparty", "started"}


def _demo_call(n, state, person, ago=0, multiparty=False):
    name, number = PEOPLE[person]
    DEMO_CALLS[f"{CALL_PATH}{n}"] = {"state": state, "name": name, "number": number,
                                     "multiparty": multiparty,
                                     "started": time.monotonic() - ago if ago >= 0 else None}


def setup_calls(kind):
    first = {"incoming": "incoming", "outgoing": "alerting", "resume": "held"}.get(kind, "active")
    if kind in ("incoming", "outgoing"):
        _demo_call(1, first, 0, -1)
    elif kind:
        _demo_call(1, first, 0, 272, multiparty=kind == "conference")
    if kind == "waiting":
        _demo_call(2, "waiting", 1, -1)
    elif kind == "held":
        _demo_call(2, "held", 1, 64)
    elif kind == "conference":
        _demo_call(2, "active", 1, 64, multiparty=True)


def active_calls():
    from boomerangd.calls import available_actions
    states = {p: c["state"] for p, c in DEMO_CALLS.items()}
    now = time.monotonic()
    return [{"path": p, "state": c["state"], "number": c["number"], "name": c["name"],
             "duration": int(now - c["started"]) if c["started"] is not None else -1,
             "avatar": "", "multiparty": c["multiparty"], "actions": available_actions(states, p)}
            for p, c in DEMO_CALLS.items()]


def call_action(conn, path, action):
    from boomerangd.calls import available_actions, demo_transition
    states = {p: c["state"] for p, c in DEMO_CALLS.items()}
    if action not in available_actions(states, path):
        return False
    conference = {p for p, c in DEMO_CALLS.items() if c["multiparty"]}
    after, conference = demo_transition(states, action, path, conference)
    for p in list(DEMO_CALLS):
        if p not in after:
            del DEMO_CALLS[p]
            continue
        call = DEMO_CALLS[p]
        if after[p] == "active" and call["started"] is None:
            call["started"] = time.monotonic()
        call["state"], call["multiparty"] = after[p], p in conference
    conn.emit_signal(None, service.PATH, service.INTERFACE, "ActiveCallsChanged", None)
    return True


CALL_OUTPUTS = [("alsa_output.pci-analog-stereo", "Built-in speakers" if EN else "Haut-parleurs intégrés"),
                ("alsa_output.usb-headset", "USB headset" if EN else "Casque USB")]
CALL_OUTPUT = {"name": ""}


def call_outputs():
    return [{"name": name, "description": desc, "default": i == 0,
             "current": name == CALL_OUTPUT["name"]} for i, (name, desc) in enumerate(CALL_OUTPUTS)]


def set_prop(conn, name, value):
    PROPS[name] = value
    conn.emit_signal(None, service.PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                     GLib.Variant("(sa{sv}as)", (service.INTERFACE, {
                         name: service._variant(name, value)}, [])))


def notifications():
    return [{"uid": uid, "app": app, "app_name": name, "title": title, "body": body,
             "time": NOW - ago, "category": 0, "icon": icon, "image": ""}
            for uid, app, name, title, body, ago, icon in NOTIFICATIONS]


def notification_apps():
    return [{"id": app, "name": name, "enabled": True, "count": 1, "icon": icon, "image": "",
             "mode": APP_NOTIFY.get(app, ("", "", False))[0]}
            for _, app, name, _, _, _, icon in NOTIFICATIONS]


def headphones():
    return [{"address": "00:11:22:33:44:66", "name": "Camille's AirPods Pro" if EN else "AirPods Pro de Camille",
             "model": "AirPods Pro 2", "firmware": "7A305", "connected": True, "linked": True,
             "left": 85, "right": 80, "case": 60, "left_charging": False,
             "right_charging": False, "case_charging": True, "ear_left": "in", "ear_right": "in",
             "mode": 4, "cycle": 6, "conversation": 1, "adaptive": 50, "one_bud": 1,
             "features": sorted(features_for("AirPods Pro 2")), "auto_pause": True,
             "battery_alerts": True, "ear_detection": 1, "hold_left": 1, "hold_right": 5,
             "hold_interval": 0, "swipe": 1, "swipe_interval": 0}]


REPLIES = {
    "ListThreads": lambda _: v("(aa{sv})", (dicts(threads(), service.THREAD_TYPES),)),
    "GetMessages": lambda p: v("(aa{sv})", (dicts(messages(p.unpack()[0]),
                                                   service.MESSAGE_TYPES),)),
    "GetMessagesPage": lambda p: (lambda page, more: v("(aa{sv}b)", (
        dicts(page, service.MESSAGE_TYPES), more)))(*messages_page(*p.unpack())),
    "ListLinks": lambda p: v("(aa{sv})", (dicts(links(p.unpack()[0]), service.LINK_TYPES),)),
    "SearchThreads": lambda _: v("(as)", ([],)),
    "ListContacts": lambda _: v("(aa{sv})", (dicts(contacts(), service.CONTACT_TYPES),)),
    "ListCalls": lambda _: v("(aa{sv})", (dicts(calls(), service.CALL_TYPES),)),
    "ListActiveCalls": lambda _: v("(aa{sv})", (dicts(active_calls(), service.ACTIVE_TYPES),)),
    "ListCallAudioOutputs": lambda _: v("(aa{sv})", (dicts(call_outputs(),
                                                          service.CALL_OUTPUT_TYPES),)),
    "ListNotifications": lambda _: v("(aa{sv})", (dicts(notifications(),
                                                         service.NOTIFICATION_TYPES),)),
    "ListNotificationApps": lambda _: v("(aa{sv})", (dicts(notification_apps(),
                                                            service.APP_TYPES),)),
    "ListHeadphones": lambda _: v("(aa{sv})", (dicts(headphones(),
                                                      service.HEADPHONES_TYPES),)),
    "ListAudioOutputs": lambda _: v("(aa{sv})", (dicts(
        [{"name": "speakers", "description": "Speakers" if EN else "Haut-parleurs",
          "default": True}],
        service.OUTPUT_TYPES),)),
    "ListFilePeers": lambda _: v("(aa{sv})", (dicts(
        [{"id": "demo-iphone", "alias": PROPS["DeviceName"], "model": "iPhone", "type": "mobile"}],
        service.PEER_TYPES),)),
    "OpenConversation": lambda _: v("(a{sv})", ({},)),
    "GetContact": lambda p: v("(a{sv})", (dicts([contact_details(p.unpack()[0])],
                                                service.CARD_TYPES)[0],)),
    "GetContactDetails": lambda p: v("(a{sv})", (dicts([contact_details(p.unpack()[0])],
                                                       service.DETAIL_TYPES)[0],)),
    "ExportContacts": lambda p: v("(s)", (export_contacts(p.unpack()[0]),)),
    "PreviewContactsImport": lambda p: v("(aa{sv})", (dicts(preview_import(p.unpack()[0]),
                                                            service.IMPORT_PREVIEW_TYPES),)),
    "MediaCommand": lambda _: v("(b)", (True,)),
    "GetNotificationAppSettings": lambda p: v("(ssb)", APP_NOTIFY.get(p.unpack()[0], ("", "", False))),
    "GetThreadNotify": lambda p: v("(ss)", THREAD_NOTIFY.get(p.unpack()[0], ("", ""))),
    "GetLinkPreview": lambda p: v("(a{sv})", ({k: v("s", x) for k, x in LINK_PREVIEW.items()}
                                              if PROPS["LinkPreviews"] and
                                              p.unpack()[0].startswith(("http://", "https://"))
                                              else {},)),
}


# Modules (catalog.py): the demo has AirPods and iCloud added, and those listed in
# BOOMERANG_DEMO_MODULES (e.g. "mirror files" for the Recopie page with its drop area).
DEMO_ADDED = {"airpods", "icloud"} | set(os.environ.get("BOOMERANG_DEMO_MODULES", "").split())

# Recopie: mirroring under way with a picture shown, iPhone control on and connected.
MIRROR = {"available": True, "running": True, "name": "Boomerang (bureau)", "error": "",
          "missing": [], "profile": "fluid", "rotation": "", "fullscreen": False,
          "decoder": "vaapi", "pin": "4821", "record": False, "recording": "", "beacon": False,
          "can_capture": True,
          "screenshot": os.path.join(GLib.get_home_dir(), "Pictures" if EN else "Images",
                                     "Recopie iPhone 2026-11-02 18-42-10.png")}
CONTROL = {"enabled": True, "registered": True, "connected": True, "error": "",
           "width": 400, "height": 866, "auto_size": True, "video_width": 1170,
           "video_height": 2532}
FILES = {"enabled": "files" in DEMO_ADDED, "state": "listening", "error": "",
         "alias": "Boomerang", "folder": "", "activity": "", "progress": 0.0, "peers": 1,
         "sending": False}
DEMO_DICTS = {"Mirror": MIRROR, "Control": CONTROL, "Files": FILES}


def catalog_entries():
    from boomerangd import catalog
    return [{"id": mid, "title": title, "summary": summary, "icon": icon, "page": page,
             "added": mid in DEMO_ADDED, "missing": list(packages[:1]) if mid == "icloud" else []}
            for mid, title, summary, icon, page, packages in catalog.MODULES]


def on_method(conn, _sender, _path, _iface, method, params, invocation):
    # Settings the demo keeps in memory, so the app sees its own changes.
    if method == "SetThreadNotify":
        thread, mode, sound = params.unpack()
        THREAD_NOTIFY[thread] = (mode, sound)
    elif method == "SetNotificationAppSettings":
        app, mode, sound, private = params.unpack()
        APP_NOTIFY[app] = (mode, sound, private)
    elif method == "SetModuleAdded":
        module, added = params.unpack()
        (DEMO_ADDED.add if added else DEMO_ADDED.discard)(module)
        conn.emit_signal(None, service.PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         GLib.Variant("(sa{sv}as)", (service.INTERFACE, {
                             "Catalog": service._variant("Catalog", catalog_entries())}, [])))
    elif method == "SetLinkPreviews":
        PROPS["LinkPreviews"] = params.unpack()[0]
    elif method == "SetQuickReplies":
        PROPS["QuickReplies"] = [t.strip() for t in params.unpack()[0] if t.strip()][:8]
    elif method == "SaveContact":
        invocation.return_value(v("(s)", (save_contact(conn, params.unpack()[0]),)))
        return
    elif method == "DeleteContact":
        CARDS.pop(params.unpack()[0], None)
        conn.emit_signal(None, service.PATH, service.INTERFACE, "ContactsChanged", None)
    elif method == "ImportContacts":
        report = import_contacts(conn, params.unpack()[0])
        invocation.return_value(v("(a{sv})", (dicts([report], service.IMPORT_REPORT_TYPES)[0],)))
        return
    elif method == "SetContactsSource":
        source = params.unpack()[0]
        PROPS.update({"ContactsSource": source, "ContactsBook": "ready" if source == "icloud" else ""})
        conn.emit_signal(None, service.PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         GLib.Variant("(sa{sv}as)", (service.INTERFACE, {
                             "ContactsSource": v("s", PROPS["ContactsSource"]),
                             "ContactsBook": v("s", PROPS["ContactsBook"])}, [])))
        conn.emit_signal(None, service.PATH, service.INTERFACE, "ContactsChanged", None)
    elif method == "CallAction":
        if not call_action(conn, *params.unpack()):
            invocation.return_dbus_error(f"{service.INTERFACE}.Error.CallFailed",
                                         "not possible with the calls going on now")
            return
    elif method == "SetCallAudio":
        set_prop(conn, "AudioOnPC", params.unpack()[0])
    elif method == "SetMuted":
        set_prop(conn, "MicMuted", params.unpack()[0])
    elif method == "SetCallAudioOutput":
        CALL_OUTPUT["name"] = params.unpack()[0]
    reply = REPLIES.get(method)
    invocation.return_value(reply(params) if reply else None)


def on_get(_conn, _sender, _path, _iface, name):
    if name == "NowPlaying":
        return service._variant(name, now_playing())
    if name == "Catalog":
        return service._variant(name, catalog_entries())
    if name in DEMO_DICTS:
        return service._variant(name, DEMO_DICTS[name])
    signature = service.SIGNATURES[name]
    if name not in PROPS:  # a property newer than the demo: an empty value of its type
        empty = {"b": False, "s": "", "i": -1, "u": 0, "x": 0, "d": 0.0}
        return GLib.Variant(signature, empty.get(signature, [] if signature.startswith("aa")
                                                  or signature == "as" else {}))
    return v(signature, PROPS[name])


def main():
    global ARTWORK
    ARTWORK = demo_artwork()
    setup_calls(os.environ.get("BOOMERANG_DEMO_CALL", ""))
    LINK_PREVIEW["image"] = ARTWORK  # a picture on the link card (decoded off the main thread)
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    info = Gio.DBusNodeInfo.new_for_xml(service.XML).interfaces[0]
    bus.register_object(service.PATH, info, on_method, on_get, None)
    loop = GLib.MainLoop()
    Gio.bus_own_name_on_connection(bus, DEMO_NAME, Gio.BusNameOwnerFlags.NONE, None,
                                   lambda *_: (print(f"lost {DEMO_NAME}", flush=True),
                                               loop.quit()))
    print(f"demo daemon on {DEMO_NAME} (app id {APP_ID})", flush=True)
    loop.run()


if __name__ == "__main__":
    main()
