# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Offline checks of the full vCard reader and writer (Contacts): PBAP, import, export."""

import json
import os
import tempfile
import unittest

from boomerangd import vcard

# What iOS sends over PBAP for one card with every field asked (vCard 3.0, made-up person).
PBAP_IOS = (
    "BEGIN:VCARD\r\n"
    "VERSION:3.0\r\n"
    "FN:Alice Martin\r\n"
    "N:Martin;Alice;;;\r\n"
    "NICKNAME:Lili\r\n"
    "ORG:Atelier Nord;Design\r\n"
    "TITLE:Architecte\r\n"
    "TEL;TYPE=CELL:06 00 00 00 01\r\n"
    "TEL;TYPE=WORK;TYPE=VOICE:01 23 45 67 89\r\n"
    "EMAIL;TYPE=INTERNET;TYPE=HOME:alice@example.org\r\n"
    "ADR;TYPE=HOME:;;12 rue des Lilas\\nBât. B;Lyon;;69003;France\r\n"
    "URL;TYPE=pref:https://example.org/alice\r\n"
    "BDAY:1990-05-12\r\n"
    "NOTE:Allergique aux noix\\, préfère le thé.\\nAppeler après 18 h.\r\n"
    "PHOTO;ENCODING=b;TYPE=JPEG:/9j/4AAQ\r\n"
    " SkZJRg==\r\n"
    "END:VCARD\r\n"
)

# As iCloud (CardDAV) and macOS Contacts write it: groups with Apple's labels.
APPLE = (
    "BEGIN:VCARD\r\n"
    "VERSION:3.0\r\n"
    "PRODID:-//Apple Inc.//iPhone OS 18.0//EN\r\n"
    "N:Bernard;Chloé;;;\r\n"
    "FN:Chloé Bernard\r\n"
    "item1.TEL;type=pref:+33 6 00 00 00 04\r\n"
    "item1.X-ABLabel:_$!<Mobile>!$_\r\n"
    "item2.EMAIL;type=INTERNET:chloe@club.example\r\n"
    "item2.X-ABLabel:Club de voile\r\n"
    "item3.URL;type=pref:https://chloe.example\r\n"
    "item3.X-ABLabel:_$!<HomePage>!$_\r\n"
    "BDAY;X-APPLE-OMIT-YEAR=1604:1604-11-03\r\n"
    "item4.X-ABDATE;type=pref:2015-06-20\r\n"
    "item4.X-ABLabel:_$!<Anniversary>!$_\r\n"
    "item5.ADR;type=WORK;type=pref:;;3 quai du Port;Marseille;;13002;France\r\n"
    "item5.X-ABADR:fr\r\n"
    "TEL;type=IPHONE;type=CELL;type=VOICE:0600000044\r\n"
    "END:VCARD\r\n"
)

# vCard 2.1 as older phones and some exports write it: bare types, quoted-printable.
OLD = (
    "BEGIN:VCARD\r\n"
    "VERSION:2.1\r\n"
    "N;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Dupr=C3=A9;=C3=89lodie\r\n"
    "TEL;CELL;VOICE:0611223344\r\n"
    "NOTE;ENCODING=QUOTED-PRINTABLE:Premi=C3=A8re ligne=0D=0A=\r\n"
    "seconde\r\n"
    "BDAY:19800102\r\n"
    "END:VCARD\r\n"
)


class ReadTest(unittest.TestCase):
    def test_pbap_card_from_ios(self):
        [card] = vcard.parse(PBAP_IOS)
        self.assertEqual(card["name"], "Alice Martin")
        self.assertEqual((card["given"], card["family"]), ("Alice", "Martin"))
        self.assertEqual(card["nickname"], "Lili")
        self.assertEqual((card["org"], card["department"], card["title"]),
                         ("Atelier Nord", "Design", "Architecte"))
        self.assertEqual(card["phones"], [("mobile", "06 00 00 00 01"),
                                          ("travail", "01 23 45 67 89")])
        self.assertEqual(card["emails"], [("domicile", "alice@example.org")])
        self.assertEqual(card["addresses"],
                         [("domicile", "12 rue des Lilas\nBât. B", "Lyon", "", "69003", "France")])
        self.assertEqual(card["urls"], [("", "https://example.org/alice")])
        self.assertEqual(card["birthday"], "1990-05-12")
        self.assertEqual(card["note"], "Allergique aux noix, préfère le thé.\nAppeler après 18 h.")
        self.assertEqual(card["photo"][:4], b"\xff\xd8\xff\xe0")
        self.assertEqual(vcard.addresses_of(card), ["+33600000001", "+33123456789",
                                                    "alice@example.org"])

    def test_apple_groups_and_labels(self):
        [card] = vcard.parse(APPLE)
        self.assertEqual(card["phones"], [("mobile", "+33 6 00 00 00 04"), ("iphone", "0600000044")])
        self.assertEqual(card["emails"], [("Club de voile", "chloe@club.example")])
        self.assertEqual(card["urls"], [("accueil", "https://chloe.example")])
        self.assertEqual(card["birthday"], "--11-03")  # no year
        self.assertEqual(card["dates"], [("anniversaire", "2015-06-20")])
        self.assertEqual(card["addresses"][0][0], "travail")

    def test_vcard_21_quoted_printable(self):
        [card] = vcard.parse(OLD)
        self.assertEqual(card["name"], "Élodie Dupré")
        self.assertEqual(card["phones"], [("mobile", "0611223344")])
        self.assertEqual(card["note"], "Première ligne\nseconde")
        self.assertEqual(card["birthday"], "1980-01-02")

    def test_several_cards_and_garbage(self):
        text = "junk\r\n" + PBAP_IOS + "\r\n\r\n" + OLD + "BEGIN:VCARD\r\nFN:Cut"
        cards = vcard.parse(text)
        self.assertEqual([c["name"] for c in cards], ["Alice Martin", "Élodie Dupré"])
        self.assertTrue(cards[0]["raw"].startswith("BEGIN:VCARD\r\n"))
        self.assertTrue(cards[0]["raw"].endswith("END:VCARD\r\n"))

    def test_name_falls_back_like_the_iphone(self):
        only_org = "BEGIN:VCARD\r\nVERSION:3.0\r\nN:;;;;\r\nORG:Boulangerie\r\nEND:VCARD\r\n"
        self.assertEqual(vcard.parse(only_org)[0]["name"], "Boulangerie")
        only_tel = "BEGIN:VCARD\r\nVERSION:3.0\r\nTEL:0611\r\nEND:VCARD\r\n"
        self.assertEqual(vcard.parse(only_tel)[0]["name"], "0611")

    def test_vcard4_photo_and_dates(self):
        text = ("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Zoé\r\n"
                "PHOTO:data:image/png;base64,iVBORw0KGgo=\r\n"
                "BDAY:--0704\r\nANNIVERSARY:20100918T000000Z\r\nEND:VCARD\r\n")
        [card] = vcard.parse(text)
        self.assertEqual(card["photo"][:4], b"\x89PNG")
        self.assertEqual(card["birthday"], "--07-04")
        self.assertEqual(card["dates"], [("anniversaire", "2010-09-18")])

    def test_dates(self):
        self.assertEqual(vcard.parse_date("1604-02-29"), "--02-29")
        self.assertEqual(vcard.parse_date("2000-13-01"), "")
        self.assertEqual(vcard.parse_date("hier"), "")


class WriteTest(unittest.TestCase):
    def test_round_trip_keeps_every_field(self):
        for text in (PBAP_IOS, APPLE, OLD):
            [card] = vcard.parse(text)
            [back] = vcard.parse(vcard.serialize(card))
            for key in vcard.TEXT_FIELDS + vcard.LIST_FIELDS + ("photo",):
                if key in ("uid",):
                    continue
                expected = card[key]
                if key == "phones":  # labels without a TYPE of their own come back as « autre »
                    expected = [(label or "autre", value) for label, value in expected]
                if key == "urls":
                    expected = [(label or "autre", value) for label, value in expected]
                self.assertEqual(back[key], expected, f"{key} of {card['name']}")

    def test_apple_labels_written_as_apple_does(self):
        card = vcard.empty_card()
        card.update(given="Hugo", family="Richard", birthday="--03-14",
                    urls=[("accueil", "https://hugo.example")],
                    dates=[("anniversaire", "2019-09-01")],
                    emails=[("Association", "hugo@asso.example")])
        text = vcard.serialize(card)
        self.assertIn("BDAY;X-APPLE-OMIT-YEAR=1604:1604-03-14\r\n", text)
        self.assertIn("item2.URL:https://hugo.example\r\nitem2.X-ABLabel:_$!<HomePage>!$_", text)
        self.assertIn("X-ABLabel:_$!<Anniversary>!$_", text)
        self.assertIn("X-ABLabel:Association", text)
        self.assertIn("N:Richard;Hugo;;;\r\nFN:Hugo Richard\r\n", text)

    def test_escaping_and_folding(self):
        card = vcard.empty_card()
        card.update(given="Léa", family="Dubois", note="Code ; porte, 2e étage\n" + "é" * 80,
                    org="A;B")
        text = vcard.serialize(card)
        for line in text.split("\r\n"):
            self.assertLessEqual(len(line.encode()), 75)
        [back] = vcard.parse(text)
        self.assertEqual(back["note"], card["note"])

    def test_file_name(self):
        self.assertEqual(vcard.file_name("Alice / Martin"), "Alice Martin.vcf")
        self.assertEqual(vcard.file_name(""), "Contact.vcf")


class PhonebookCacheTest(unittest.TestCase):
    def test_remember_and_find(self):
        with tempfile.TemporaryDirectory() as directory:
            count = vcard.remember_phonebook(directory, "AA:BB", PBAP_IOS + APPLE)
            self.assertEqual(count, 2)
            path = os.path.join(directory, vcard.CACHE_NAME)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            with open(path, encoding="utf-8") as f:
                self.assertNotIn("photo", json.load(f)["cards"][0])  # photos live in messages.db
            details = vcard.PhonebookDetails()
            card = details.find(directory, ["+33600000001"], device="aa:bb")
            self.assertEqual(card["title"], "Architecte")
            self.assertEqual(card["addresses"][0][2], "Lyon")
            # Another iPhone's cache is never shown.
            self.assertIsNone(details.find(directory, ["+33600000001"], device="CC:DD"))
            self.assertIsNone(details.find(directory, ["+33699999999"]))

    def test_broken_cache_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, vcard.CACHE_NAME), "w") as f:
                f.write("{not json")
            self.assertIsNone(vcard.PhonebookDetails().find(directory, ["+33600000001"]))


if __name__ == "__main__":
    unittest.main()
