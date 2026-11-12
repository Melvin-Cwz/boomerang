// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * The column of a page (Réglages, Le Fil, the iPhone's pages): centred, 600 px wide however long
 * its texts, so that page titles and contents line up, on the 6/12/24 grid. A Gtk.Box alone
 * would grow to the natural width of its wrapping labels.
 */

public class Boomerang.PageColumn : Gtk.Widget {
    private const int MIN_WIDTH = 600;
    private const int MAX_WIDTH = 600;
    private Gtk.Box box;

    public PageColumn () {
        Object (halign: Gtk.Align.CENTER);
    }

    construct {
        box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.set_parent (this);
        margin_top = 24;
        margin_bottom = 24;
        margin_start = 24;
        margin_end = 24;
    }

    public void append (Gtk.Widget child) {
        box.append (child);
    }

    protected override void dispose () {
        box.unparent ();
        base.dispose ();
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            box.measure (orientation, for_size, out minimum, out natural, null, null);
            minimum = int.max (minimum, MIN_WIDTH);
            natural = natural.clamp (minimum, int.max (minimum, MAX_WIDTH));
        } else {
            // Centred, it gets at most its bounded natural width: its height is the one at that width.
            int min_width, nat_width;
            box.measure (Gtk.Orientation.HORIZONTAL, -1, out min_width, out nat_width, null, null);
            min_width = int.max (min_width, MIN_WIDTH);
            nat_width = nat_width.clamp (min_width, int.max (min_width, MAX_WIDTH));
            for_size = for_size < 0 ? nat_width : for_size.clamp (min_width, nat_width);
            box.measure (orientation, for_size, out minimum, out natural, null, null);
        }
        minimum_baseline = natural_baseline = -1;
    }

    public override void size_allocate (int width, int height, int baseline) {
        box.allocate (width, height, baseline, null);
    }
}
