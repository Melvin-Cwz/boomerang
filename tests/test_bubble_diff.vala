// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/* Boomerang.first_change and redraw_range: what the Messages view redraws when a conversation
   changes or older messages are loaded above. */

void range (string[] shown, string[] now, bool changed, int start, int shown_end, int now_end) {
    int s, a, b;
    assert (Boomerang.redraw_range (shown, now, out s, out a, out b) == changed);
    assert (s == start && a == shown_end && b == now_end);
}

int main () {
    string[] shown = { "a", "b", "c" };
    assert (Boomerang.first_change (shown, { "a", "b", "c" }) == 3);       // nothing to redraw
    assert (Boomerang.first_change (shown, { "a", "b", "c", "d" }) == 3);  // new message: append d
    assert (Boomerang.first_change (shown, { "a", "b", "c2" }) == 2);      // last one changed (sent)
    assert (Boomerang.first_change (shown, { "a", "c" }) == 1);            // b deleted: from there
    assert (Boomerang.first_change (shown, { "b", "c", "d" }) == 0);       // window slid: all
    assert (Boomerang.first_change (shown, { "a", "b" }) == 2);            // last one gone
    assert (Boomerang.first_change ({}, { "a" }) == 0);                    // first load

    assert (Boomerang.common_tail (shown, { "x", "y", "a", "b", "c" }, 0) == 3);
    assert (Boomerang.common_tail (shown, { "a", "b", "c" }, 3) == 0);     // never overlaps
    assert (Boomerang.common_tail ({ "a", "a" }, { "a", "a", "a" }, 2) == 0);

    range (shown, { "a", "b", "c" }, false, 3, 3, 3);
    range (shown, { "a", "b", "c", "d" }, true, 3, 3, 4);        // append d only
    range (shown, { "x", "y", "a", "b", "c" }, true, 0, 1, 3);   // older x, y above; a redrawn
    range (shown, { "a", "c" }, true, 1, 3, 2);                   // b deleted: c follows a now
    range (shown, { "a", "b2", "c" }, true, 1, 3, 3);             // reaction on b: b and c
    range (shown, { "a", "b" }, true, 2, 3, 2);                   // last one gone
    range ({}, { "a" }, true, 0, 0, 1);                           // first load
    range (shown, { "b", "c", "d" }, true, 0, 3, 3);              // window slid: all
    return 0;
}
