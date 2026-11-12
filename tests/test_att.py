# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
from boomerangd.att import server_answer, uuid_text


def test_empty_server_answers():
    assert server_answer(bytes([0x12, 0x09, 0x00, 0x02, 0x00])) == b"\x13"
    assert server_answer(bytes([0x10, 0x01, 0x00, 0xff, 0xff, 0x00, 0x28])) == b"\x01\x10\x01\x00\x0a"
    assert server_answer(bytes([0x0a, 0x05, 0x00])) == b"\x01\x0a\x05\x00\x01"
    assert server_answer(bytes([0x52, 0x05, 0x00, 0x01])) is None  # write command
    assert server_answer(bytes([0x13])) is None  # a response is not a request


def test_uuid_text():
    assert uuid_text(b"\x02\x29") == "00002902-0000-1000-8000-00805f9b34fb"
