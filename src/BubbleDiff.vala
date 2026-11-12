// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Which bubbles of the open conversation must be redrawn: the messages shown and the
 * messages now, one signature each, compared from both ends. A new message only adds
 * itself at the end, older messages loaded on scrolling up only add themselves at the
 * start; a change in the middle (a deletion, a reaction, a sender name that arrives)
 * redraws that part only.
 */

namespace Boomerang {
    /* Index of the first message whose signature differs, or the shorter length when one
       list starts with the other. Equal to both lengths when nothing changed. */
    public int first_change (string[] shown, string[] now) {
        int i = 0;
        while (i < shown.length && i < now.length && shown[i] == now[i]) {
            i++;
        }
        return i;
    }

    /* How many messages at the end are the same in both lists, not counting the first
       `prefix` ones (already found equal by first_change): the two never overlap. */
    public int common_tail (string[] shown, string[] now, int prefix) {
        int i = 0;
        while (i < shown.length - prefix && i < now.length - prefix
               && shown[shown.length - 1 - i] == now[now.length - 1 - i]) {
            i++;
        }
        return i;
    }

    /* The part to redraw: messages [start, shown_end) of the old list are replaced by
       [start, now_end) of the new one. A bubble depends on the message before it (time
       line, sender's name, spacing; what follows it is in its signature), so the first
       message after a change is redrawn too. False when nothing changed. */
    public bool redraw_range (string[] shown, string[] now, out int start, out int shown_end,
                              out int now_end) {
        start = first_change (shown, now);
        var tail = common_tail (shown, now, start);
        if (start == shown.length && start == now.length) {
            shown_end = now_end = start;
            return false;
        }
        if (tail > 0) {
            tail--;
        }
        shown_end = shown.length - tail;
        now_end = now.length - tail;
        return true;
    }
}
