# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Offline checks of the Contacts book: EDS mapping, import, export, PBAP details.

EDS contacts are the real in-memory EBookContacts objects (no server, no account); the
address book client is a stand-in. Nothing reaches iCloud."""

import os
import tempfile
import unittest

from gi.repository import GLib

from boomerangd import contacts, service, vcard
from tests.test_vcard import APPLE, PBAP_IOS


class FakeConfig:
    def __init__(self, source="icloud"):
        self.keyfile = GLib.KeyFile()
        self.keyfile.set_string("contacts", "source", source)

    def save(self):
        pass


class FakeClient:
    """BookClient stand-in: contacts in a dictionary, by uid."""

    def __init__(self):
        self.contacts = {}
        self.added = []

    def get_contact_sync(self, uid, _cancellable):
        return True, self.contacts[uid]

    def modify_contact_sync(self, contact, _flags, _cancellable):
        self.contacts[contact.get_property("id")] = contact

    def add_contact_sync(self, contact, _flags, _cancellable):
        uid = f"new-{len(self.added) + 1}"
        contact.set_property("id", uid)
        self.contacts[uid] = contact
        self.added.append(contact)
        return True, uid


class FakeStore:
    def __init__(self, directory, device="AA:BB"):
        self.dir = directory
        self.device = device

    def meta(self, key, default=""):
        return self.device if key == "device" else default


def book_with(client=None, source="icloud"):
    book = contacts.ContactBook.__new__(contacts.ContactBook)
    book.config = FakeConfig(source)
    book.on_change = lambda: None
    book.worker = None
    book.client = client
    book.state = "ready" if client else "off"
    book.cards = []
    book.phonebook = vcard.PhonebookDetails()
    book.reload = lambda: None
    book._submit = lambda job, done: done(job(), None)  # synchronous: no worker thread
    return book


def results():
    got = {}
    return got, lambda value, error: got.update(value=value, error=error)


@unittest.skipIf(contacts.EBookContacts is None, "gir1.2-ebook-1.2 missing")
class EdsMappingTest(unittest.TestCase):
    def contact(self, text=APPLE, uid="u1"):
        contact = contacts.EBookContacts.Contact.new_from_vcard(text)
        contact.set_property("id", uid)
        return contact

    def text(self, contact):
        return contact.to_string(contacts.vcard_format_30())

    def test_old_client_save_keeps_fields_it_does_not_know(self):
        # The editor of Boomerang 1.x sends only names, company, note, numbers, e-mails.
        contact = self.contact()
        contacts.fill(contact, {"given": "Chloé", "family": "Bernard", "org": "", "note": "",
                                "phones": [("travail", "01 02 03 04 05")], "emails": []})
        [card] = vcard.parse(self.text(contact))
        self.assertEqual(card["phones"], [("travail", "01 02 03 04 05")])
        self.assertEqual(card["emails"], [])
        self.assertEqual(card["urls"], [("accueil", "https://chloe.example")])
        self.assertEqual(card["birthday"], "--11-03")
        self.assertEqual(card["addresses"][0][2], "Marseille")
        self.assertEqual(card["dates"], [("anniversaire", "2015-06-20")])
        # The old numbers' Apple labels went with them, no orphan label is left.
        text = self.text(contact)
        self.assertNotIn("_$!<Mobile>!$_", text)
        self.assertNotIn("Club de voile", text)

    def test_full_card_written_and_read_back(self):
        contact = self.contact()
        photo = b"\xff\xd8\xff\xe0" + b"\x00" * 20
        edited = {"given": "Chloé", "family": "Bernard-Roy", "nickname": "Clo", "org": "Voiles",
                  "title": "Monitrice", "note": "Ligne 1\nLigne 2", "birthday": "1988-11-03",
                  "phones": [("mobile", "0600000004"), ("Bateau", "0600000099")],
                  "emails": [("travail", "chloe@voiles.example")],
                  "addresses": [("domicile", "1 rue Haute", "Marseille", "", "13001", "France")],
                  "urls": [("travail", "https://voiles.example")],
                  "dates": [("autre", "--06-21")],
                  "photo_data": photo}
        contacts.fill(contact, dict(edited))
        [card] = vcard.parse(self.text(contact))
        for key in ("given", "family", "nickname", "org", "title", "note", "birthday", "phones",
                    "emails", "addresses", "urls", "dates"):
            self.assertEqual(card[key], edited[key], key)
        self.assertEqual(card["photo"], photo)
        self.assertEqual(card["name"], "Chloé Bernard-Roy")
        # Each group holds one property and its label: no number used twice.
        groups = {}
        for line in self.text(contact).split("\r\n"):
            if line.lower().startswith("item"):
                group, rest = line.split(".", 1)
                groups.setdefault(group.lower(), []).append(rest.split(":")[0].split(";")[0])
        self.assertTrue(groups)
        for names in groups.values():
            self.assertEqual(len([n for n in names if n.upper() != "X-ABLABEL"]), 1, groups)

    def test_photo_removed(self):
        contact = self.contact(PBAP_IOS)
        contacts.fill(contact, {"photo_remove": True})
        self.assertIsNone(vcard.parse(self.text(contact))[0]["photo"])
        self.assertIn("ORG:Atelier Nord;Design", self.text(contact))

    def test_department_kept_when_company_edited(self):
        contact = self.contact(PBAP_IOS)
        contacts.fill(contact, {"org": "Atelier Sud"})
        self.assertEqual(vcard.parse(self.text(contact))[0]["department"], "Design")

    def test_details_through_the_client(self):
        client = FakeClient()
        client.contacts["u1"] = self.contact()
        book = book_with(client)
        got, done = results()
        book.details("u1", done)
        card = got["value"]
        self.assertEqual(card["uid"], "u1")
        self.assertEqual(card["name"], "Chloé Bernard")
        self.assertEqual(card["urls"], [("accueil", "https://chloe.example")])
        self.assertEqual(card["photo"], "")
        self.assertNotIn("raw", card)
        service._dicts([card], service.DETAIL_TYPES)  # every value fits the D-Bus type
        service._dicts([card], service.CARD_TYPES)

    def test_save_new_card(self):
        client = FakeClient()
        book = book_with(client)
        got, done = results()
        book.save({"uid": "", "given": "Hugo", "family": "Richard", "org": "", "note": "",
                   "phones": [("mobile", "0600000007")], "emails": [],
                   "birthday": "--03-14"}, done)
        self.assertEqual(got["value"], "new-1")
        [card] = vcard.parse(self.text(client.contacts["new-1"]))
        self.assertEqual((card["name"], card["birthday"]), ("Hugo Richard", "--03-14"))

    def test_import_skips_duplicates_and_drops_uids(self):
        client = FakeClient()
        book = book_with(client)
        book.cards = [{"name": "Alice Martin", "addresses": ["+33600000001"]}]
        text = PBAP_IOS + APPLE.replace("END:VCARD", "UID:abc-123\r\nEND:VCARD") + APPLE
        got, done = results()
        book.import_cards(text, done)
        self.assertIsNone(got["error"])
        self.assertEqual(got["value"], {"added": 1, "duplicates": 2, "failed": 0,
                                        "names": ["Chloé Bernard"]})
        self.assertNotIn("abc-123", self.text(client.added[0]))

    def test_export_icloud_cards(self):
        client = FakeClient()
        client.contacts["u1"] = self.contact()
        book = book_with(client)
        listed = book.enrich([{"uid": "u1", "name": "Chloé Bernard",
                               "addresses": ["+33600000004"], "photo": ""}], None)
        got, done = results()
        book.export([], listed, None, done)
        [card] = vcard.parse(got["value"])
        self.assertEqual(card["dates"], [("anniversaire", "2015-06-20")])
        self.assertIn("VERSION:3.0", got["value"])


class PreviewTest(unittest.TestCase):
    def test_preview_marks_duplicates(self):
        cards = [{"name": "alice martin", "addresses": ["alice@example.org"]}]
        found = contacts.preview(PBAP_IOS + APPLE, cards)
        self.assertEqual([(c["name"], c["duplicate"]) for c in found],
                         [("Alice Martin", True), ("Chloé Bernard", False)])
        self.assertEqual(found[0]["count"], 3)
        service._dicts(found, service.IMPORT_PREVIEW_TYPES)

    def test_preview_refuses_huge_files(self):
        with self.assertRaises(ValueError):
            contacts.preview("x" * (contacts.IMPORT_MAX_BYTES + 1), [])

    def test_same_name_other_number_is_not_a_duplicate(self):
        [card] = vcard.parse(PBAP_IOS)
        self.assertFalse(contacts.is_duplicate(card, [{"name": "Alice Martin",
                                                       "addresses": ["+33699999999"]}]))


class PhonebookDetailsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        vcard.remember_phonebook(self.tmp.name, "AA:BB", PBAP_IOS)
        self.store = FakeStore(self.tmp.name)
        self.book = book_with(None, source="bluetooth")
        # As the store lists the iPhone's phone book (messages.db).
        self.listed = self.book.enrich([{"name": "Alice Martin", "photo": "",
                                         "addresses": ["+33600000001", "alice@example.org"]},
                                        {"name": "Maman", "photo": "",
                                         "addresses": ["+33600000003"]}], self.store)

    def tearDown(self):
        self.tmp.cleanup()

    def test_list_gets_key_and_names(self):
        alice, mum = self.listed
        self.assertEqual(alice["key"], "pbap:+33600000001")
        self.assertEqual((alice["given"], alice["family"], alice["org"]),
                         ("Alice", "Martin", "Atelier Nord"))
        self.assertNotIn("given", mum)  # not in the cache: the list sorts on the name

    def test_details_from_the_cache_or_the_list(self):
        got, done = results()
        self.book.card_details("pbap:+33600000001", self.listed, self.store, done)
        self.assertEqual(got["value"]["title"], "Architecte")
        self.assertEqual(got["value"]["birthday"], "1990-05-12")
        service._dicts([got["value"]], service.DETAIL_TYPES)
        service._dicts(self.listed, service.CONTACT_TYPES)
        self.book.card_details("pbap:+33600000003", self.listed, self.store, done)
        self.assertEqual(got["value"]["phones"], [("", "+33600000003")])
        self.book.card_details("pbap:+33611111111", self.listed, self.store, done)
        self.assertIsNotNone(got["error"])

    def test_export_with_photo(self):
        photo = os.path.join(self.tmp.name, "photo")
        with open(photo, "wb") as f:
            f.write(b"\xff\xd8\xff\xe0JFIF")
        listed = [dict(self.listed[0], photo=photo)]
        got, done = results()
        self.book.export(["pbap:+33600000001"], listed, self.store, done)
        [card] = vcard.parse(got["value"])
        self.assertEqual(card["photo"], b"\xff\xd8\xff\xe0JFIF")
        self.assertEqual(card["addresses"][0][2], "Lyon")


if __name__ == "__main__":
    unittest.main()
