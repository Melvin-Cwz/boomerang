// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Which bubbles of the open conversation must be redrawn: the messages shown and the
 * messages now, one signature each, compared from the start. A new message only adds
 * itself at the end; a change further up (a deletion, a reaction, a sender name that
 * arrives) redraws from there on.
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
}
