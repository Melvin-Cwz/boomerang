# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""GATT over classic Bluetooth (BR/EDR): ANCS and AMS without the LE link.

The iPhone serves its GATT database (ANCS, AMS, battery…) on the ATT channel of the
classic link too (L2CAP PSM 31). That link always comes back on its own after a
reboot, a suspend or a daemon restart, while the LE link only returns when the
iPhone decides to open it. AttLink opens that channel itself, finds the services
and gives GattClient a transport with the same calls as BlueZ (notify, write, read).

The iPhone is also a client on the same channel: it asks for our services and
subscribes to Service Changed. We have no database here; requests get the answer
« attribute not found » (writes are acknowledged), as an empty server would.

One request at a time from our side, as ATT requires; notifications and indications
are handed to the listener of their handle.
"""

import errno
import socket
import struct
import uuid as uuidlib

from gi.repository import GLib

from .util import log

PSM_ATT = 31
SOL_BLUETOOTH, BT_SECURITY, BT_SECURITY_MEDIUM = 274, 4, 2
CCC = 0x2902
REQUEST_SECONDS = 10

ERROR, MTU_REQ, MTU_RSP = 0x01, 0x02, 0x03
FIND_INFO_REQ, FIND_INFO_RSP = 0x04, 0x05
READ_BY_TYPE_REQ, READ_BY_TYPE_RSP = 0x08, 0x09
READ_REQ, READ_RSP, READ_BLOB_REQ, READ_BLOB_RSP = 0x0A, 0x0B, 0x0C, 0x0D
READ_BY_GROUP_REQ, READ_BY_GROUP_RSP = 0x10, 0x11
WRITE_REQ, WRITE_RSP = 0x12, 0x13
NOTIFY, INDICATE, CONFIRM = 0x1B, 0x1D, 0x1E
# Requests the iPhone may send us, by opcode (others are commands: no answer).
SERVER_REQUESTS = {0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0x16, 0x18, 0x20}
ERR_INVALID_HANDLE, ERR_NOT_FOUND = 0x01, 0x0A


class AttError(Exception):
    """Same wording as BlueZ's D-Bus errors, which GattClient reads."""

    def __init__(self, message):
        super().__init__(message)
        self.message = message


def uuid_text(raw):
    if len(raw) == 2:
        return f"0000{struct.unpack('<H', raw)[0]:04x}-0000-1000-8000-00805f9b34fb"
    return str(uuidlib.UUID(bytes=raw[::-1]))


def server_answer(pdu):
    """Our answer to a request of the iPhone, as an empty GATT server; None for commands."""
    op = pdu[0]
    if op not in SERVER_REQUESTS:
        return None
    if op == MTU_REQ:
        return struct.pack("<BH", MTU_RSP, 672)
    if op == WRITE_REQ:
        return bytes([WRITE_RSP])
    handle = struct.unpack("<H", pdu[1:3])[0] if len(pdu) >= 3 else 0
    code = ERR_INVALID_HANDLE if op in (READ_REQ, READ_BLOB_REQ, 0x16) else ERR_NOT_FOUND
    return struct.pack("<BBHB", ERROR, op, handle, code)


class AttLink:
    """The ATT channel over the classic link and the services found on it."""

    def __init__(self, address, wanted, on_ready, on_lost):
        self.address = address
        self.wanted = set(wanted)  # service uuids (lower case) to discover
        self.on_ready = on_ready  # callable({service uuid: {char uuid: value handle}})
        self.on_lost = on_lost
        self.sock = None
        self.watch = 0
        self.queue = []  # (pdu, callback(response or None, error))
        self.current = None
        self.timer = 0
        self.listeners = {}  # value handle -> callable(bytes)
        self.ccc = {}  # value handle -> its Client Characteristic Configuration handle
        self.mtu = 672
        self.closed = False

    # --- channel -------------------------------------------------------------------------

    def open(self):
        try:
            self.sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET,
                                      socket.BTPROTO_L2CAP)
            self.sock.setsockopt(SOL_BLUETOOTH, BT_SECURITY,
                                 struct.pack("BB", BT_SECURITY_MEDIUM, 0))
            self.sock.setblocking(False)
            err = self.sock.connect_ex((self.address, PSM_ATT))
        except OSError as error:
            self._lost(f"ouverture impossible ({error.strerror})")
            return
        if err not in (0, errno.EINPROGRESS):
            self._lost(f"ouverture impossible ({errno.errorcode.get(err, err)})")
            return
        self.watch = GLib.io_add_watch(self.sock.fileno(), GLib.PRIORITY_DEFAULT,
                                       GLib.IO_OUT | GLib.IO_ERR | GLib.IO_HUP, self._on_open)

    def _on_open(self, _fd, _cond):
        self.watch = 0
        err = self.sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
        if err:
            self._lost(f"ouverture impossible ({errno.errorcode.get(err, err)})")
            return False
        self.watch = GLib.io_add_watch(self.sock.fileno(), GLib.PRIORITY_DEFAULT,
                                       GLib.IO_IN | GLib.IO_ERR | GLib.IO_HUP, self._on_input)
        self._discover()
        return False

    def close(self):
        self.closed = True
        self._teardown()

    def _teardown(self):
        if self.watch:
            GLib.source_remove(self.watch)
            self.watch = 0
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = 0
        if self.sock:
            self.sock.close()
            self.sock = None
        pending, self.queue = ([self.current] if self.current else []) + self.queue, []
        self.current = None
        for _pdu, callback in pending:
            callback(None, AttError("Not connected"))

    def _lost(self, why):
        if self.closed:
            return
        self.closed = True
        log(f"GATT classique : {why}")
        self._teardown()
        self.on_lost()

    def _on_input(self, _fd, cond):
        try:
            pdu = self.sock.recv(4096)
        except BlockingIOError:
            return True
        except OSError as error:
            self._lost(f"canal fermé ({error.strerror})")
            return False
        if not pdu:
            self._lost("canal fermé par l'iPhone")
            return False
        self._dispatch(pdu)
        return True

    def _send(self, pdu):
        try:
            self.sock.send(pdu)
        except OSError as error:
            GLib.idle_add(lambda: self._lost(f"envoi impossible ({error.strerror})") and False)

    def _dispatch(self, pdu):
        op = pdu[0]
        if op in (NOTIFY, INDICATE):
            if op == INDICATE:
                self._send(bytes([CONFIRM]))
            if len(pdu) >= 3:
                listener = self.listeners.get(struct.unpack("<H", pdu[1:3])[0])
                if listener:
                    listener(bytes(pdu[3:]))
            return
        answer = server_answer(pdu)
        if answer is not None:
            self._send(answer)
            return
        if self.current and op & 1:  # a response (odd opcode) to our request
            _req, callback = self.current
            self.current = None
            if self.timer:
                GLib.source_remove(self.timer)
                self.timer = 0
            if op == ERROR:
                callback(None, AttError(f"Operation failed with ATT error: 0x{pdu[4]:02x}")
                         if len(pdu) >= 5 else AttError("ATT error"))
            else:
                callback(bytes(pdu), None)
            self._pump()

    # --- requests ------------------------------------------------------------------------

    def request(self, pdu, callback):
        if self.sock is None:
            callback(None, AttError("Not connected"))
            return
        self.queue.append((pdu, callback))
        self._pump()

    def _pump(self):
        if self.current or not self.queue or self.sock is None:
            return
        self.current = self.queue.pop(0)
        self._send(self.current[0])
        self.timer = GLib.timeout_add_seconds(REQUEST_SECONDS, self._expired)

    def _expired(self):
        self.timer = 0
        self._lost("pas de réponse de l'iPhone")
        return False

    # --- discovery -----------------------------------------------------------------------

    def _discover(self):
        self.services = {}  # uuid -> (start, end)
        self._groups(1)

    def _groups(self, start):
        def done(rsp, error):
            if error or rsp[0] != READ_BY_GROUP_RSP or start > 0xFFFF:
                self._characteristics(sorted(self.services.items(), key=lambda s: s[1][0]), {})
                return
            size, last = rsp[1], start
            for i in range(2, len(rsp) - size + 1, size):
                first, end = struct.unpack("<HH", rsp[i:i + 4])
                found = uuid_text(rsp[i + 4:i + size])
                if found in self.wanted:
                    self.services[found] = (first, end)
                last = end
            if last >= 0xFFFF:
                done(None, AttError("end"))
            else:
                self._groups(last + 1)
        self.request(struct.pack("<BHHH", READ_BY_GROUP_REQ, start, 0xFFFF, 0x2800), done)

    def _characteristics(self, services, result):
        if not services:
            self._descriptors(result)
            return
        (service, (start, end)), rest = services[0], services[1:]
        chars = []  # (decl handle, value handle, uuid, properties)

        def step(first):
            self.request(struct.pack("<BHHH", READ_BY_TYPE_REQ, first, end, 0x2803), done)

        def done(rsp, error):
            if not error and rsp[0] == READ_BY_TYPE_RSP:
                size = rsp[1]
                for i in range(2, len(rsp) - size + 1, size):
                    decl, props, value = struct.unpack("<HBH", rsp[i:i + 5])
                    chars.append((decl, value, uuid_text(rsp[i + 5:i + size]), props))
                if chars and chars[-1][1] < end:
                    step(chars[-1][1] + 1)
                    return
            result[service] = (chars, end)
            self._characteristics(rest, result)
        step(start)

    def _descriptors(self, result):
        """Find the CCC of each notifying characteristic, then hand the services over."""
        todo = []
        for chars, end in result.values():
            for n, (_decl, value, _uuid, props) in enumerate(chars):
                if props & 0x30:  # notify or indicate
                    last = chars[n + 1][0] - 1 if n + 1 < len(chars) else end
                    if last > value:
                        todo.append((value, value + 1, last))

        def next_one():
            if not todo:
                services = {s: {u: v for _d, v, u, _p in chars}
                            for s, (chars, _end) in result.items()}
                log("GATT classique : services " + ", ".join(s[:8] for s in services)
                    if services else "GATT classique : aucun service attendu")
                self.on_ready(services)
                return
            value, first, last = todo.pop(0)

            def done(rsp, error):
                if not error and rsp[0] == FIND_INFO_RSP and rsp[1] == 1:
                    for i in range(2, len(rsp) - 3, 4):
                        handle, kind = struct.unpack("<HH", rsp[i:i + 4])
                        if kind == CCC:
                            self.ccc[value] = handle
                next_one()
            self.request(struct.pack("<BHH", FIND_INFO_REQ, first, last), done)
        next_one()

    # --- transport for GattClient --------------------------------------------------------

    def start_notify(self, handle, listener, then):
        self.listeners[handle] = listener
        ccc = self.ccc.get(handle)
        if ccc is None:
            then(AttError("Operation failed: no CCC"))
            return
        self.request(struct.pack("<BHH", WRITE_REQ, ccc, 1), lambda _r, error: then(error))

    def stop_notify(self, handle):
        self.listeners.pop(handle, None)
        ccc = self.ccc.get(handle)
        if ccc is not None and self.sock is not None:
            self.request(struct.pack("<BHH", WRITE_REQ, ccc, 0), lambda *_: None)

    def write(self, handle, data, then):
        self.request(struct.pack("<BH", WRITE_REQ, handle) + data, lambda _r, error: then(None, error))

    def read(self, handle, then):
        value = bytearray()

        def done(rsp, error):
            if error:
                then(None, error)
                return
            value.extend(rsp[1:])
            if len(rsp) - 1 == self.mtu - 1:  # full: maybe more to read
                self.request(struct.pack("<BHH", READ_BLOB_REQ, handle, len(value)), blob)
            else:
                then(bytes(value), None)

        def blob(rsp, error):
            if error:  # « invalid offset »: the value ended exactly on a boundary
                then(bytes(value), None)
                return
            done(rsp, None)
        self.request(struct.pack("<BH", READ_REQ, handle), done)
