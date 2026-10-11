// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/* Boomerang.first_change: what the Messages view redraws when a conversation changes. */

int main () {
    string[] shown = { "a", "b", "c" };
    assert (Boomerang.first_change (shown, { "a", "b", "c" }) == 3);       // nothing to redraw
    assert (Boomerang.first_change (shown, { "a", "b", "c", "d" }) == 3);  // new message: append d
    assert (Boomerang.first_change (shown, { "a", "b", "c2" }) == 2);      // last one changed (sent)
    assert (Boomerang.first_change (shown, { "a", "c" }) == 1);            // b deleted: from there
    assert (Boomerang.first_change (shown, { "b", "c", "d" }) == 0);       // window slid: all
    assert (Boomerang.first_change (shown, { "a", "b" }) == 2);            // last one gone
    assert (Boomerang.first_change ({}, { "a" }) == 0);                    // first load
    return 0;
}
