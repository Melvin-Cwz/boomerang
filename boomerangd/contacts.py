# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Contact cards managed through iCloud (CardDAV in Evolution Data Server).

Bluetooth cannot change the iPhone's contacts: PBAP only reads them and iOS
accepts no vCard push. The contacts the iPhone shows are those of the iCloud
account, so Boomerang edits them there and iCloud brings the change back to the
iPhone within seconds.

The user picks the source in the Contacts page:
- "bluetooth": the phone book read over PBAP, cached, read only (default);
- "icloud": the iCloud address book, editable; needs the iCloud account.

Whole cards (company, postal address, birthday…) are read the same way from both
sources: vcard.py parses the vCard of the EDS contact, or the PBAP details cache.
Writing goes through vcard.properties (), the same mapping as the export file.

All EBook calls are blocking: they run on a worker thread, and the results
come back on the main loop.
"""

import base64
import hashlib
import os
import re

import gi

from . import vcard
from .bmsg import normalize_address
from .messages import Worker
from .util import icloud_uid_prefix, log

try:
    gi.require_version("EDataServer", "1.2")
    gi.require_version("EBook", "1.2")
    gi.require_version("EBookContacts", "1.2")
    from gi.repository import EBook, EBookContacts, EDataServer
except (ImportError, ValueError):  # gir1.2-ebook-1.2 missing: iCloud mode unavailable
    EBook = EBookContacts = EDataServer = None

from gi.repository import GLib

SOURCES = ("bluetooth", "icloud")
PHOTO_DIR = os.path.join(GLib.get_user_data_dir(), "boomerang", "contacts", "photos")

# Labels offered in the editor (kept here for older imports).
PHONE_LABELS = vcard.PHONE_LABELS
EMAIL_LABELS = vcard.EMAIL_LABELS

# Card fields written to iCloud, by the vCard properties that hold them. A field missing
# from a saved card is left as it is (older clients send only the first six).
FIELD_PROPERTIES = {
    "names": ("N", "FN"), "nickname": ("NICKNAME",), "org": ("ORG",), "title": ("TITLE",),
    "note": ("NOTE",), "birthday": ("BDAY",), "phones": ("TEL",), "emails": ("EMAIL",),
    "addresses": ("ADR",), "urls": ("URL",), "dates": ("X-ABDATE", "ANNIVERSARY"),
}
EDITABLE = ("given", "family", "nickname", "org", "title", "note", "birthday", "phones", "emails",
            "addresses", "urls", "dates")
# Properties Apple ties to a labelled one through its group: they go with it.
GROUP_COMPANIONS = ("X-ABLABEL", "X-ABADR")
IMPORT_MAX_BYTES = 20 * 1024 * 1024
IMPORT_MAX_CARDS = 5000
PHOTO_MAX_BYTES = 2 * 1024 * 1024


def vcard_format_30():
    return getattr(EBookContacts.VCardFormat, "30", None) or EBookContacts.VCardFormat.VCARD_30


def is_duplicate(card, cards):
    """Whether an imported card is already in the book: same name, and a shared address
    (or neither has one)."""
    name = (card.get("name") or "").casefold()
    addresses = set(vcard.addresses_of(card))
    for other in cards:
        if (other.get("name") or "").casefold() != name:
            continue
        theirs = set(other.get("addresses", []))
        if addresses & theirs or (not addresses and not theirs):
            return True
    return False


def preview(text, cards):
    """What an import would do, before it is confirmed: [{name, org, count, duplicate}]."""
    if len(text.encode("utf-8", "replace")) > IMPORT_MAX_BYTES:
        raise ValueError("fichier trop volumineux (20 Mo au plus)")
    found = vcard.parse(text)
    if len(found) > IMPORT_MAX_CARDS:
        raise ValueError(f"trop de fiches ({IMPORT_MAX_CARDS} au plus)")
    return [{"name": c["name"], "org": c["org"],
             "count": len(c["phones"]) + len(c["emails"]),
             "duplicate": is_duplicate(c, cards)} for c in found if c["name"]]


def details_for_dbus(card, photo=""):
    """A parsed card as GetContactDetails and GetContact give it."""
    out = {k: card.get(k, "") for k in vcard.TEXT_FIELDS if k not in ("photo_uri",)}
    for key in vcard.LIST_FIELDS:
        out[key] = [tuple(item) for item in card.get(key, [])]
    out["photo"] = photo
    return out


def _attributes(contact):
    return list(EBookContacts.VCard.get_attributes(contact))


def _attribute(group, name, params, values):
    attr = EBookContacts.VCardAttribute.new(group or None, name)
    for key, vals in params:
        for value in vals:  # one parameter per value, as EDS and Apple write TYPE
            param = EBookContacts.VCardAttributeParam.new(key)
            param.add_value(value)
            attr.add_param(param)
    for value in values:
        attr.add_value(value)
    return attr


def _values(attr):
    try:
        return [v or "" for v in (attr.get_values() or [])]
    except (AttributeError, TypeError):
        return [attr.get_value() or ""]


def fill(contact, card):
    """Write a card's fields into an EDS contact; fields the card does not carry stay.

    Labelled lists (numbers, e-mails, addresses, sites, dates) are written again as a
    whole, with Apple's label groups of the old ones; everything Boomerang does not edit
    (social profiles, related names, Apple's own fields) is kept."""
    present = {k for k in card if k in EDITABLE}
    if present & {"given", "family"}:
        present.add("names")
        # Middle name, prefix and suffix are not edited: keep the ones the card has.
        for attr in _attributes(contact):
            if attr.get_name().upper() == "N":
                old = _values(attr) + [""] * 5
                for key, value in zip(("middle", "prefix", "suffix"), old[2:5]):
                    card.setdefault(key, value)
    if "org" in present and "department" not in card:
        for attr in _attributes(contact):
            if attr.get_name().upper() == "ORG":
                card["department"] = ", ".join(v for v in _values(attr)[1:] if v)
    names = set()
    for field, props in FIELD_PROPERTIES.items():
        if field in present:
            names.update(props)
    if card.get("photo_data") or card.get("photo_remove"):
        names.add("PHOTO")

    groups = set()
    for attr in _attributes(contact):
        if attr.get_name().upper() in names:
            if attr.get_group():
                groups.add(attr.get_group().lower())
            EBookContacts.VCard.remove_attribute(contact, attr)
    used = 0
    for attr in _attributes(contact):
        group = (attr.get_group() or "").lower()
        if group in groups and attr.get_name().upper() in GROUP_COMPANIONS:
            EBookContacts.VCard.remove_attribute(contact, attr)
        elif group:
            m = re.fullmatch(r"item(\d+)", group)
            if m:
                used = max(used, int(m.group(1)))

    fields = set(present)
    if "names" in present:
        fields |= {"given", "family", "middle", "prefix", "suffix"}
    if "org" in present:
        fields.add("department")
    for group, name, params, values in vcard.properties(card, fields, first_group=used + 1):
        EBookContacts.VCard.append_attribute(contact, _attribute(group, name, params, values))
    if card.get("photo_data"):
        data = bytes(card["photo_data"])
        kind = "PNG" if data[:8] == b"\x89PNG\r\n\x1a\n" else "JPEG"
        EBookContacts.VCard.append_attribute(contact, _attribute(
            "", "PHOTO", [("ENCODING", ["b"]), ("TYPE", [kind])],
            [base64.b64encode(data).decode("ascii")]))


class ContactBook:
    def __init__(self, config, on_change):
        self.config = config
        self.on_change = on_change
        self.worker = None
        self.client = None
        self.state = "off"   # off, connecting, ready, no-account, missing, error
        self.cards = []      # [{'uid', 'name', 'addresses', 'photo', 'given', 'family', 'org'}]
        self.phonebook = vcard.PhonebookDetails()
        if self.source == "icloud":
            self._open()

    # --- settings ---------------------------------------------------------------------

    @property
    def source(self):
        try:
            value = self.config.keyfile.get_string("contacts", "source")
        except GLib.Error:
            return "bluetooth"
        return value if value in SOURCES else "bluetooth"

    def set_source(self, source):
        if source not in SOURCES:
            raise ValueError(source)
        self.config.keyfile.set_string("contacts", "source", source)
        self.config.save()
        log(f"contacts : gestion {'via iCloud' if source == 'icloud' else 'par Bluetooth'}")
        if source == "icloud":
            self._open()
        else:
            self.client = None
            self.cards = []
            self.state = "off"
        self.on_change()

    @property
    def editable(self):
        return self.source == "icloud" and self.state == "ready"

    # --- opening ----------------------------------------------------------------------

    def _submit(self, job, done):
        if self.worker is None:
            self.worker = Worker()
        self.worker.submit(job, done)

    def _open(self):
        if EBook is None:
            self.state = "missing"
            self.on_change()
            return
        self.state = "connecting"

        def job():
            registry = EDataServer.SourceRegistry.new_sync(None)
            for source in registry.list_sources(EDataServer.SOURCE_EXTENSION_ADDRESS_BOOK):
                if source.get_parent() == f"{icloud_uid_prefix()}-collection" and source.get_enabled():
                    client = EBook.BookClient.connect_sync(source, 30, None)
                    return client, self._read(client)
            return None, []

        self._submit(job, self._opened)

    def _opened(self, result, error):
        if self.source != "icloud":
            return
        if error:
            log(f"contacts : carnet iCloud illisible ({error})")
            self.state = "error"
        elif result[0] is None:
            self.state = "no-account"
        else:
            self.client, self.cards = result
            self.state = "ready"
            log(f"contacts : {len(self.cards)} fiches iCloud")
        self.on_change()

    def reload(self):
        if self.client is None:
            if self.source == "icloud":
                self._open()
            return
        client = self.client
        self._submit(lambda: self._read(client), self._reloaded)

    def _reloaded(self, cards, error):
        if not error and cards is not None:
            self.cards = cards
        self.on_change()

    # --- reading ----------------------------------------------------------------------

    @staticmethod
    def _contacts(client):
        _ok, contacts = client.get_contacts_sync('(exists "full_name")', None)
        return contacts

    def _read(self, client):
        cards = []
        for contact in self._contacts(client):
            uid = contact.get_property("id")
            addresses = []
            for attr in EBookContacts.VCard.get_attributes(contact):
                if attr.get_name().upper() in ("TEL", "EMAIL"):
                    address = normalize_address(attr.get_value() or "")
                    if address and address not in addresses:
                        addresses.append(address)
            given = (contact.get_property("given-name") or "").strip()
            family = (contact.get_property("family-name") or "").strip()
            org = (contact.get_property("org") or "").strip()
            # iOS often leaves FN empty and only fills N: build the name like the iPhone does.
            name = (contact.get_property("full-name") or "").strip() or " ".join(
                p for p in (given, family) if p) or org \
                or (contact.get_property("nickname") or "").strip()
            cards.append({"uid": uid, "name": name, "addresses": addresses,
                          "photo": self._photo(uid, contact), "given": given,
                          "family": family, "org": org})
        cards.sort(key=lambda c: c["name"].casefold())
        return cards

    @staticmethod
    def _photo(uid, contact):
        photo = contact.get_property("photo")
        if photo is None:
            return ""
        if photo.type == EBookContacts.ContactPhotoType.URI:
            # EDS keeps downloaded photos in its cache and points to them.
            uri = photo.get_uri() or ""
            path = GLib.filename_from_uri(uri)[0] if uri.startswith("file://") else ""
            return path if path and os.path.exists(path) else ""
        data = photo.get_inlined()
        data = bytes(data[0] if isinstance(data, tuple) else data or b"")
        if not data:
            return ""
        os.makedirs(PHOTO_DIR, mode=0o700, exist_ok=True)
        name = hashlib.sha1(uid.encode()).hexdigest()[:16]
        path = os.path.join(PHOTO_DIR, name + "-" + hashlib.sha1(data).hexdigest()[:8])
        if not os.path.exists(path):
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(data)
        return path

    @classmethod
    def _parsed(cls, uid, contact):
        """A whole EDS contact as a vcard.py card, its photo as a file path."""
        cards = vcard.parse(contact.to_string(vcard_format_30()))
        card = cards[0] if cards else vcard.empty_card()
        card["uid"] = uid
        return details_for_dbus(card, cls._photo(uid, contact))

    def details(self, uid, on_done):
        """Every field of one iCloud card: on_done(dict | None, error)."""
        client = self.client

        def job():
            _ok, contact = client.get_contact_sync(uid, None)
            return self._parsed(uid, contact)

        if client is None:
            on_done(None, "carnet iCloud non ouvert")
            return
        self._submit(job, on_done)

    # --- list and details for both sources -----------------------------------------------

    def enrich(self, cards, store):
        """List cards with what sorting and the detail pane need: key (the iCloud uid, or
        « pbap: » and the first address), given and family names, company."""
        directory = store.dir if store else None
        device = store.meta("device", "") if store else ""
        out = []
        for card in cards:
            card = dict(card)
            if card.get("uid") and self.source == "icloud":
                card["key"] = card["uid"]
            else:
                card["key"] = "pbap:" + (card["addresses"][0] if card.get("addresses") else "")
                cached = self.phonebook.find(directory, card.get("addresses", []), device,
                                             card.get("name")) if directory else None
                if cached:
                    for key in ("given", "family", "org"):
                        card.setdefault(key, cached.get(key, ""))
            out.append(card)
        return out

    def _pbap_card(self, listed, store):
        """Whole card of a PBAP list entry: the details cache, else what the list knows."""
        directory = store.dir if store else None
        device = store.meta("device", "") if store else ""
        cached = self.phonebook.find(directory, listed.get("addresses", []), device,
                                     listed.get("name")) if directory else None
        if cached:
            card = vcard.empty_card()
            card.update({k: v for k, v in cached.items() if k in card})
            card["name"] = listed.get("name") or card["name"]
        else:
            card = vcard.empty_card()
            card["name"] = listed.get("name", "")
            for address in listed.get("addresses", []):
                (card["emails"] if "@" in address else card["phones"]).append(("", address))
        return card

    def card_details(self, key, listed, store, on_done):
        """GetContactDetails: on_done(dict | None, error). listed: the list cards (enriched)."""
        entry = next((c for c in listed if c.get("key") == key), None)
        if key and not key.startswith("pbap:") and self.client is not None:
            photo = entry.get("photo", "") if entry else ""

            def done(card, error):
                if card is not None and not card.get("photo"):
                    card["photo"] = photo  # the iPhone's photo while iCloud's is not there
                on_done(card, error)

            self.details(key, done)
            return
        if entry is None:
            address = key[5:] if key.startswith("pbap:") else ""
            entry = next((c for c in listed if address and address in c.get("addresses", [])),
                         None)
        if entry is None:
            on_done(None, "fiche inconnue")
            return
        card = self._pbap_card(entry, store)
        on_done(details_for_dbus(card, entry.get("photo", "")), None)

    def export(self, keys, listed, store, on_done):
        """vCard 3.0 text of these cards (all listed ones when keys is empty), photos inlined:
        on_done(text | None, error)."""
        wanted = [c for c in listed if not keys or c.get("key") in keys]
        client = self.client

        def photo_bytes(path):
            try:
                if path and os.path.getsize(path) <= PHOTO_MAX_BYTES:
                    with open(path, "rb") as f:
                        return f.read()
            except OSError:
                pass
            return None

        def job():
            texts = []
            for entry in wanted:
                if entry.get("uid") and not entry["key"].startswith("pbap:") and client:
                    _ok, contact = client.get_contact_sync(entry["uid"], None)
                    parsed = vcard.parse(contact.to_string(vcard_format_30()))
                    card = parsed[0] if parsed else vcard.empty_card()
                    if not card.get("photo"):
                        card["photo"] = photo_bytes(self._photo(entry["uid"], contact)
                                                    or entry.get("photo", ""))
                else:
                    card = self._pbap_card(entry, store)
                    card["photo"] = photo_bytes(entry.get("photo", ""))
                texts.append(vcard.serialize(card))
            return "".join(texts)

        if not wanted:
            on_done(None, "aucune fiche à exporter")
            return
        self._submit(job, on_done)

    # --- writing ----------------------------------------------------------------------

    def save(self, card, on_done):
        """Create (no uid) or update a card; on_done(uid | None, error)."""
        client = self.client
        if client is None:
            on_done(None, "carnet iCloud non ouvert")
            return

        def job():
            uid = card.get("uid") or ""
            if uid:
                _ok, contact = client.get_contact_sync(uid, None)
            else:
                contact = EBookContacts.Contact.new()
            self._fill(contact, card)
            if uid:
                client.modify_contact_sync(contact, EBookContacts.BookOperationFlags.NONE, None)
            else:
                _ok, uid = client.add_contact_sync(contact, EBookContacts.BookOperationFlags.NONE, None)
            return uid

        def done(uid, error):
            if error:
                log(f"contacts : fiche non enregistrée ({error})")
            else:
                log("contacts : fiche enregistrée dans iCloud")
                self.reload()
            on_done(uid, error)

        self._submit(job, done)

    def delete(self, uid, on_done):
        client = self.client
        if client is None:
            on_done(None, "carnet iCloud non ouvert")
            return

        def done(result, error):
            if error:
                log(f"contacts : fiche non supprimée ({error})")
            else:
                log("contacts : fiche supprimée dans iCloud")
                self.reload()
            on_done(result, error)

        self._submit(lambda: client.remove_contact_by_uid_sync(
            uid, EBookContacts.BookOperationFlags.NONE, None), done)

    def import_cards(self, text, on_done):
        """Add the cards of a vCard text to iCloud, skipping those already there:
        on_done({'added', 'duplicates', 'failed', 'names'} | None, error)."""
        client = self.client
        if client is None:
            on_done(None, "carnet iCloud non ouvert")
            return
        try:
            preview(text, [])  # size limits
        except ValueError as error:
            on_done(None, str(error))
            return
        known = [dict(c) for c in self.cards]

        def job():
            report = {"added": 0, "duplicates": 0, "failed": 0, "names": []}
            for card in vcard.parse(text):
                if not card["name"]:
                    report["failed"] += 1
                    continue
                if is_duplicate(card, known):
                    report["duplicates"] += 1
                    continue
                try:
                    contact = EBookContacts.Contact.new_from_vcard(card["raw"])
                    # A fresh card in iCloud: an exported UID would collide with its source.
                    for attr in _attributes(contact):
                        if attr.get_name().upper() in ("UID", "REV", "PRODID"):
                            EBookContacts.VCard.remove_attribute(contact, attr)
                    client.add_contact_sync(contact, EBookContacts.BookOperationFlags.NONE, None)
                except GLib.Error as error:
                    log(f"contacts : fiche non importée ({error.message})")
                    report["failed"] += 1
                    continue
                report["added"] += 1
                report["names"].append(card["name"])
                known.append({"name": card["name"], "addresses": vcard.addresses_of(card)})
            return report

        def done(report, error):
            if error:
                log(f"contacts : import interrompu ({error})")
            else:
                log(f"contacts : import vCard, {report['added']} fiche(s) ajoutée(s), "
                    f"{report['duplicates']} déjà présente(s), {report['failed']} refusée(s)")
                if report["added"]:
                    self.reload()
            on_done(report, error)

        self._submit(job, done)

    @staticmethod
    def _fill(contact, card):
        fill(contact, card)
