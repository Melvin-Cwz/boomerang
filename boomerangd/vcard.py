# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Full contact cards in vCard 2.1, 3.0 and 4.0: reading, writing, the PBAP details cache.

bmsg.parse_vcards keeps what Messages needs (a name, the addresses, the photo). This
module reads a whole card, the way the iPhone (PBAP), iCloud (CardDAV through EDS) and
exported files write it, into one plain dictionary shared by the D-Bus API:

    {"name", "given", "family", "middle", "prefix", "suffix", "nickname",
     "org", "department", "title", "note", "birthday", "uid",
     "phones": [(label, number)], "emails": [(label, address)],
     "addresses": [(label, street, city, region, postcode, country)],
     "urls": [(label, url)], "dates": [(label, date)],
     "photo": bytes | None, "photo_uri": str, "raw": the card's own text}

Labels are Boomerang's keys (mobile, domicile, travail…), or the user's own words for a
custom Apple label. Dates are "YYYY-MM-DD", or "--MM-DD" when the year is unknown.

properties() turns a card back into vCard properties; serialize() writes them as vCard
3.0 text (export), and contacts.py writes the same properties into an EDS contact, so
that a file and iCloud receive the same thing.

No D-Bus and no GObject here: everything can be checked offline.
"""

import base64
import binascii
import json
import os
import quopri
import re
import time

from .bmsg import normalize_address

# Fields asked of the iPhone's phone book (PBAP « pb »), in BlueZ's names.
PBAP_FIELDS = ["FN", "N", "TEL", "EMAIL", "PHOTO", "ORG", "TITLE", "ADR", "BDAY", "URL",
               "NICKNAME", "NOTE"]

# Labels with the vCard TYPE parameters Apple understands (the first one decides).
PHONE_LABELS = {"mobile": ["CELL", "VOICE"], "iphone": ["IPHONE", "CELL", "VOICE"],
                "domicile": ["HOME", "VOICE"], "travail": ["WORK", "VOICE"],
                "principal": ["MAIN"], "autre": ["OTHER", "VOICE"]}
EMAIL_LABELS = {"domicile": ["INTERNET", "HOME"], "travail": ["INTERNET", "WORK"],
                "autre": ["INTERNET", "OTHER"]}
ADDRESS_LABELS = {"domicile": ["HOME"], "travail": ["WORK"], "autre": ["OTHER"]}
URL_LABELS = {"accueil": [], "domicile": ["HOME"], "travail": ["WORK"], "autre": ["OTHER"]}
DATE_LABELS = {"anniversaire": [], "autre": []}
# Apple's own labels (itemN.X-ABLabel:_$!<Mobile>!$_), read back to ours and written for
# the labels TYPE cannot carry.
APPLE_LABELS = {"mobile": "mobile", "home": "domicile", "work": "travail", "main": "principal",
                "iphone": "iphone", "other": "autre", "homepage": "accueil",
                "anniversary": "anniversaire"}
APPLE_WRITE = {"accueil": "_$!<HomePage>!$_", "anniversaire": "_$!<Anniversary>!$_",
               "autre": "_$!<Other>!$_"}
# Apple writes a birthday without a year as 1604-MM-DD with X-APPLE-OMIT-YEAR=1604.
APPLE_NO_YEAR = "1604"

LIST_FIELDS = ("phones", "emails", "addresses", "urls", "dates")
TEXT_FIELDS = ("name", "given", "family", "middle", "prefix", "suffix", "nickname", "org",
               "department", "title", "note", "birthday", "uid", "photo_uri")


def empty_card():
    card = {key: "" for key in TEXT_FIELDS}
    card.update({key: [] for key in LIST_FIELDS})
    card.update(photo=None, raw="")
    return card


# --- reading ----------------------------------------------------------------------------------

def unfold(text):
    """Logical lines: folded lines joined, quoted-printable soft breaks (vCard 2.1) too."""
    lines, qp_open = [], False
    for raw in (text or "").replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if qp_open and lines:
            lines[-1] = lines[-1][:-1] + raw
        elif raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw.strip():
            lines.append(raw)
        else:
            continue
        head = lines[-1].split(":", 1)[0].upper()
        qp_open = "QUOTED-PRINTABLE" in head and lines[-1].endswith("=")
    return lines


def split_cards(text):
    """Each BEGIN:VCARD … END:VCARD block as its own text (CRLF lines), nested cards kept."""
    cards, current, depth = [], [], 0
    for line in unfold(text):
        upper = line.strip().upper()
        if upper == "BEGIN:VCARD":
            depth += 1
        if depth:
            current.append(line)
        if upper == "END:VCARD" and depth:
            depth -= 1
            if not depth:
                cards.append("\r\n".join(current) + "\r\n")
                current = []
    return cards


def _split_unescaped(value, separator):
    parts, current, escaped = [], [], False
    for c in value:
        if escaped:
            current.append("\\" + c)
            escaped = False
        elif c == "\\":
            escaped = True
        elif c == separator:
            parts.append("".join(current))
            current = []
        else:
            current.append(c)
    if escaped:
        current.append("\\")
    parts.append("".join(current))
    return parts


def unescape(value):
    out, i = [], 0
    while i < len(value):
        c = value[i]
        if c == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out.append("\n" if nxt in "nN" else nxt)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_line(line):
    """'item1.TEL;type=CELL;TYPE=pref:+33…' -> (group, NAME, {PARAM: [values]}, raw value).

    vCard 2.1 bare parameters (TEL;CELL;VOICE) count as TYPE values."""
    head, value = line.split(":", 1)
    # A parameter value may be quoted and hold ':' or ';' (rare): cut on the first ':'
    # outside quotes.
    if head.count('"') % 2:
        quoted, i = False, 0
        for i, c in enumerate(line):
            if c == '"':
                quoted = not quoted
            elif c == ":" and not quoted:
                break
        head, value = line[:i], line[i + 1:]
    pieces = head.split(";")
    name = pieces[0].strip()
    group = ""
    if "." in name:
        group, name = name.split(".", 1)
    params = {}
    for piece in pieces[1:]:
        if not piece:
            continue
        if "=" in piece:
            key, values = piece.split("=", 1)
            key = key.strip().upper()
        else:
            key, values = "TYPE", piece
        for v in values.split(","):
            v = v.strip().strip('"')
            if v:
                params.setdefault(key, []).append(v)
    return group, name.upper(), params, value


def _decode(params, value):
    """Text of a value: quoted-printable and charsets of vCard 2.1 undone."""
    encoding = [e.upper() for e in params.get("ENCODING", [])]
    if "QUOTED-PRINTABLE" in encoding:
        charset = (params.get("CHARSET") or ["utf-8"])[0]
        raw = quopri.decodestring(value.encode("latin-1", "replace"))
        try:
            return raw.decode(charset, "replace")
        except LookupError:
            return raw.decode("utf-8", "replace")
    return value


def types_of(params):
    return [t.upper() for t in params.get("TYPE", [])]


def parse_date(value, params=None):
    """'1990-05-12', '19900512', '1990-05-12T00:00:00Z', '--05-12', '--0512', Apple's
    1604-05-12 (no year) -> 'YYYY-MM-DD' or '--MM-DD'; '' when not a date."""
    value = (value or "").strip().split("T", 1)[0]
    omit = ((params or {}).get("X-APPLE-OMIT-YEAR") or [""])[0]
    m = re.fullmatch(r"--(\d{2})-?(\d{2})", value)
    if m:
        year, month, day = "", m.group(1), m.group(2)
    else:
        m = re.fullmatch(r"(\d{4})-?(\d{2})-?(\d{2})", value)
        if not m:
            return ""
        year, month, day = m.groups()
        if year == omit or (year == APPLE_NO_YEAR and not omit):
            year = ""
    if not (1 <= int(month) <= 12 and 1 <= int(day) <= 31):
        return ""
    return f"{year}-{month}-{day}" if year else f"--{month}-{day}"


def _label(group, params, labels, apple):
    """Our label of a TEL, EMAIL, ADR, URL or X-ABDATE: Apple's label of the group first,
    then the TYPE parameters ('' when nothing says)."""
    if group and group.upper() in apple:
        raw = apple[group.upper()]
        if raw.startswith("_$!<") and raw.endswith(">!$_"):
            raw = raw[4:-4]
            return APPLE_LABELS.get(raw.lower(), raw.lower())
        return raw  # the user's own label, kept as written
    types = types_of(params)
    if "IPHONE" in types and "iphone" in labels:
        return "iphone"
    for name, wanted in labels.items():
        key = next((t for t in wanted if t not in ("INTERNET", "VOICE")), None)
        if key and key in types:
            return name
    if "CELL" in types and "mobile" in labels:
        return "mobile"
    if "FAX" in types and "autre" in labels:
        return "autre"
    return ""


def parse_card(text):
    """One card (as split_cards gives it) -> card dictionary."""
    card = empty_card()
    card["raw"] = text
    lines = []
    depth = 0
    for line in unfold(text):
        upper = line.strip().upper()
        if upper == "BEGIN:VCARD":
            depth += 1
            continue
        if upper == "END:VCARD":
            depth -= 1
            continue
        if depth != 1 or ":" not in line:
            continue  # nested AGENT card, or garbage
        lines.append(parse_line(line))
    apple = {g.upper(): unescape(_decode(p, v)).strip()
             for g, n, p, v in lines if g and n == "X-ABLABEL"}
    fn = ""
    for group, name, params, value in lines:
        text_value = _decode(params, value)
        if name == "FN":
            fn = unescape(text_value).strip()
        elif name == "N":
            parts = [unescape(p).strip() for p in _split_unescaped(text_value, ";")] + [""] * 5
            card.update(family=parts[0], given=parts[1], middle=parts[2], prefix=parts[3],
                        suffix=parts[4])
        elif name == "NICKNAME":
            card["nickname"] = ", ".join(unescape(p).strip()
                                         for p in _split_unescaped(text_value, ",") if p.strip())
        elif name == "ORG":
            parts = [unescape(p).strip() for p in _split_unescaped(text_value, ";")]
            card["org"] = parts[0] if parts else ""
            card["department"] = ", ".join(p for p in parts[1:] if p)
        elif name == "TITLE":
            card["title"] = unescape(text_value).strip()
        elif name == "NOTE":
            note = unescape(text_value).replace("\r\n", "\n").strip()
            card["note"] = (card["note"] + "\n" + note).strip() if card["note"] else note
        elif name == "UID":
            card["uid"] = unescape(text_value).strip()
        elif name == "BDAY":
            card["birthday"] = parse_date(unescape(text_value), params)
        elif name in ("X-ABDATE", "ANNIVERSARY"):
            date = parse_date(unescape(text_value), params)
            if date:
                label = "anniversaire" if name == "ANNIVERSARY" else \
                    _label(group, params, DATE_LABELS, apple) or "autre"
                card["dates"].append((label, date))
        elif name == "TEL":
            number = unescape(text_value).strip()
            if number.lower().startswith("tel:"):
                number = number[4:]
            if number:
                card["phones"].append((_label(group, params, PHONE_LABELS, apple), number))
        elif name == "EMAIL":
            address = unescape(text_value).strip()
            if address.lower().startswith("mailto:"):
                address = address[7:]
            if address:
                card["emails"].append((_label(group, params, EMAIL_LABELS, apple), address))
        elif name == "ADR":
            parts = [unescape(p).strip() for p in _split_unescaped(text_value, ";")] + [""] * 7
            pobox, extended, street, city, region, postcode, country = parts[:7]
            street = "\n".join(p for p in (street, extended, pobox) if p)
            if any((street, city, region, postcode, country)):
                card["addresses"].append((_label(group, params, ADDRESS_LABELS, apple), street,
                                          city, region, postcode, country))
        elif name == "URL":
            url = unescape(text_value).strip()
            if url:
                card["urls"].append((_label(group, params, URL_LABELS, apple), url))
        elif name == "PHOTO":
            _photo(card, params, value)
    card["name"] = display_name(card, fn)
    return card


def _photo(card, params, value):
    encoding = [e.upper() for e in params.get("ENCODING", [])]
    kind = [v.upper() for v in params.get("VALUE", [])]
    value = value.strip()
    if value.lower().startswith("data:"):  # vCard 4.0: data:image/jpeg;base64,…
        head, _, data = value.partition(",")
        if ";base64" in head.lower():
            value, encoding = data, ["B"]
    if "B" in encoding or "BASE64" in encoding:
        try:
            card["photo"] = base64.b64decode("".join(value.split()), validate=False) or None
        except (binascii.Error, ValueError):
            card["photo"] = None
    elif "URI" in kind or "://" in value:
        card["photo_uri"] = value


def display_name(card, fn=""):
    """The name the iPhone shows: FN, else given and family name, else the company, the
    nickname or the first address."""
    joined = " ".join(p for p in (card.get("given", ""), card.get("family", "")) if p)
    for candidate in (fn, joined, card.get("org", ""), card.get("nickname", "")):
        if candidate and candidate.strip():
            return candidate.strip()
    for _label_, value in list(card.get("phones", [])) + list(card.get("emails", [])):
        if value.strip():
            return value.strip()
    return ""


def parse(text):
    """Every card of a vCard text (file, PBAP pull, EDS contact)."""
    return [parse_card(raw) for raw in split_cards(text)]


def addresses_of(card):
    """Normalised phone numbers and e-mail addresses of a card, in order, once each."""
    result = []
    for _label_, value in list(card.get("phones", [])) + list(card.get("emails", [])):
        address = normalize_address(value)
        if address and address not in result:
            result.append(address)
    return result


# --- writing ----------------------------------------------------------------------------------

def escape(value):
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    return (value.replace("\\", "\\\\").replace("\n", "\\n").replace(",", "\\,")
            .replace(";", "\\;"))


def _date_value(date):
    """Our date -> (value, params) as Apple writes it."""
    if date.startswith("--"):
        return f"{APPLE_NO_YEAR}-{date[2:]}", [("X-APPLE-OMIT-YEAR", [APPLE_NO_YEAR])]
    return date, []


def properties(card, fields=None, first_group=1):
    """vCard properties for a card: [(group, NAME, [(PARAM, [values])], [values])].

    fields: only these keys of the card (None: every key the card has). Values are
    plain text; serialize() escapes them, EDS escapes them itself. Labels TYPE cannot
    say go to a group with X-ABLabel, as Apple writes them; groups are numbered from
    first_group."""
    def wanted(key):
        return key in card and (fields is None or key in fields)

    out = []
    group_number = [first_group]

    def labelled(name, labels, label, values, extra=None, pref=False):
        params = list(extra or [])
        types = list(labels.get(label, [])) if label in labels else \
            list(labels.get("autre", []))
        if pref:
            types.append("pref")
        if types:
            params.insert(0, ("TYPE", types))
        if label in labels:  # TYPE says it, else Apple's own label
            apple = None if labels[label] else APPLE_WRITE.get(label)
        else:  # the user's own label (or none)
            apple = label or None
        if apple:
            group = f"item{group_number[0]}"
            group_number[0] += 1
            out.append((group, name, params, values))
            out.append((group, "X-ABLabel", [], [apple]))
        else:
            out.append(("", name, params, values))

    names = ("family", "given", "middle", "prefix", "suffix")
    if any(wanted(k) for k in names):
        out.append(("", "N", [], [card.get(k, "").strip() for k in names]))
        name = " ".join(p for p in (card.get("given", "").strip(), card.get("family", "").strip())
                        if p) or card.get("org", "").strip() or card.get("name", "").strip()
        out.append(("", "FN", [], [name]))
    elif wanted("name"):
        out.append(("", "FN", [], [card["name"].strip()]))
    for key, prop in (("nickname", "NICKNAME"), ("title", "TITLE"), ("note", "NOTE")):
        if wanted(key) and card[key].strip():
            out.append(("", prop, [], [card[key].strip()]))
    if wanted("org") and (card["org"].strip() or card.get("department", "").strip()):
        values = [card["org"].strip()]
        if card.get("department", "").strip():
            values.append(card["department"].strip())
        out.append(("", "ORG", [], values))
    if wanted("birthday") and parse_date(card["birthday"]):
        value, params = _date_value(parse_date(card["birthday"]))
        out.append(("", "BDAY", params, [value]))
    for key, prop, labels in (("phones", "TEL", PHONE_LABELS), ("emails", "EMAIL", EMAIL_LABELS),
                              ("urls", "URL", URL_LABELS)):
        if not wanted(key):
            continue
        first = True
        for label, value in card[key]:
            value = value.strip()
            if value:
                labelled(prop, labels, label, [value], pref=first and key != "urls")
                first = False
    if wanted("addresses"):
        for label, street, city, region, postcode, country in card["addresses"]:
            parts = [p.strip() for p in (street, city, region, postcode, country)]
            if any(parts):
                labelled("ADR", ADDRESS_LABELS, label, ["", ""] + parts)
    if wanted("dates"):
        for label, date in card["dates"]:
            date = parse_date(date)
            if date:
                value, params = _date_value(date)
                labelled("X-ABDATE", DATE_LABELS, label or "autre", [value], extra=params)
    return out


def _fold(line):
    """Lines of at most 75 octets, cut between characters (RFC 2426 § 2.6)."""
    data = line.encode("utf-8")
    if len(data) <= 75:
        return line
    pieces, current, size, limit = [], [], 0, 75
    for c in line:
        n = len(c.encode("utf-8"))
        if size + n > limit:
            pieces.append("".join(current))
            current, size, limit = [], 0, 74  # continuation lines start with a space
        current.append(c)
        size += n
    pieces.append("".join(current))
    return "\r\n ".join(pieces)


def render(group, name, params, values, structured=None):
    head = (group + "." if group else "") + name
    for key, vals in params:
        head += f";{key}={','.join(vals)}"
    if structured is None:
        structured = name in ("N", "ADR", "ORG")
    text = ";".join(escape(v) for v in values) if structured else escape(values[0] if values else "")
    return _fold(f"{head}:{text}")


def serialize(card):
    """One card as vCard 3.0 text (CRLF), with its photo inlined when it has one."""
    lines = ["BEGIN:VCARD", "VERSION:3.0", "PRODID:-//Boomerang//Contacts//FR"]
    props = properties(card)
    if not any(p[1] == "FN" for p in props):
        props.insert(0, ("", "FN", [], [display_name(card)]))
        props.insert(0, ("", "N", [], ["", "", "", "", ""]))
    for prop in props:
        lines.append(render(*prop))
    photo = card.get("photo")
    if photo:
        kind = "PNG" if photo[:8] == b"\x89PNG\r\n\x1a\n" else "JPEG"
        lines.append(_fold(f"PHOTO;ENCODING=b;TYPE={kind}:" + base64.b64encode(photo).decode()))
    if card.get("uid"):
        lines.append(render("", "UID", [], [card["uid"]]))
    lines.append("END:VCARD")
    return "\r\n".join(lines) + "\r\n"


def serialize_all(cards):
    return "".join(serialize(c) for c in cards)


def file_name(name, fallback="Contact"):
    """A file name for an exported card: the person's name without path characters."""
    clean = " ".join(re.sub(r'[\\/:*?"<>|\x00-\x1f]+', " ", name or "").split()).strip(" .")
    return (clean[:80] or fallback) + ".vcf"


# --- PBAP details cache ---------------------------------------------------------------------
# The phone book in messages.db keeps names, addresses and photos for Messages. The rest of
# each card (company, address, birthday…) is kept next to it in contacts-details.json
# (0600), written when the phone book is pulled, read by the Contacts page.

CACHE_NAME = "contacts-details.json"
CACHE_KEYS = ("name", "given", "family", "middle", "prefix", "suffix", "nickname", "org",
              "department", "title", "note", "birthday", "phones", "emails", "addresses",
              "urls", "dates")


def remember_phonebook(directory, device, text):
    """Keep the details of a PBAP pull (worker thread). Never raises: the phone book
    itself must not fail because of this cache."""
    try:
        cards = []
        for card in parse(text):
            entry = {k: card[k] for k in CACHE_KEYS}
            entry["addresses_key"] = addresses_of(card)
            if entry["name"] and entry["addresses_key"]:
                cards.append(entry)
        path = os.path.join(directory, CACHE_NAME)
        tmp = path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"device": device, "time": int(time.time()), "cards": cards}, f,
                      ensure_ascii=False)
        os.replace(tmp, path)
        return len(cards)
    except (OSError, ValueError, TypeError) as error:
        from .util import log
        log(f"contacts : détails du répertoire non gardés ({error})")
        return 0


class PhonebookDetails:
    """The cache above, read again only when the file changes."""

    def __init__(self):
        self.path = None
        self.stamp = None
        self.device = ""
        self.cards = []
        self.index = {}

    def load(self, directory, device=None):
        """Cards of the cache for this device (another iPhone's details are never shown)."""
        path = os.path.join(directory, CACHE_NAME) if directory else None
        try:
            stamp = os.stat(path).st_mtime_ns if path else None
        except OSError:
            stamp = None
        if path != self.path or stamp != self.stamp:
            self.path, self.stamp, self.cards, self.index, self.device = path, stamp, [], {}, ""
            if stamp is not None:
                try:
                    with open(path, encoding="utf-8") as f:
                        data = json.load(f)
                    self.device = data.get("device", "")
                    for card in data.get("cards", []):
                        for key in LIST_FIELDS:
                            card[key] = [tuple(item) for item in card.get(key, [])]
                        self.cards.append(card)
                        for address in card.get("addresses_key", []):
                            self.index.setdefault(address, card)
                except (OSError, ValueError, AttributeError):
                    self.cards, self.index = [], {}
        if device and self.device and device.upper() != self.device.upper():
            return {}
        return self.index

    def find(self, directory, addresses, device=None, name=None):
        """The cached card sharing an address (and the name, when given) with a list card."""
        index = self.load(directory, device)
        fallback = None
        for address in addresses:
            card = index.get(address)
            if card is None:
                continue
            if name is None or card.get("name") == name:
                return card
            fallback = fallback or card
        return fallback
