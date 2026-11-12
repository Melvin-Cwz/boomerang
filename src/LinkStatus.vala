// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * The iPhone link (Boomerang 2): an arc of three segments that fill as the link builds
 * (absent, classic link, notifications too), on the iPhone's card in Réglages, and a band
 * under the header bar while the link is missing. Everything reads the daemon's LinkState,
 * so the window, the indicator and the tests agree on one word.
 */

/* The arc: three segments of a boomerang's curve. */
public class Boomerang.LinkArc : Gtk.Widget {
    public int filled { get; set; default = 0; }
    public bool problem { get; set; default = false; }
    public bool pending { get; set; default = false; }

    private double phase = 0;
    private uint tick = 0;

    construct {
        width_request = 34;
        height_request = 16;
        valign = Gtk.Align.CENTER;
        accessible_role = Gtk.AccessibleRole.IMG;
        notify["filled"].connect (queue_draw);
        notify["problem"].connect (queue_draw);
        notify["pending"].connect (update_tick);
    }

    private void update_tick () {
        var animate = pending && Gtk.Settings.get_default ().gtk_enable_animations;
        if (animate && tick == 0) {
            tick = add_tick_callback ((widget, clock) => {
                phase = (clock.get_frame_time () % 1600000) / 1600000.0;
                queue_draw ();
                return Source.CONTINUE;
            });
        } else if (!animate && tick != 0) {
            remove_tick_callback (tick);
            tick = 0;
            phase = 0;
            queue_draw ();
        }
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        var w = get_width ();
        var h = get_height ();
        var cr = snapshot.append_cairo ({ { 0, 0 }, { w, h } });
        // Bubblegum 500 when linked; banana 500 when something blocks; the text colour when out of reach.
        Gdk.RGBA pink = { 0.871f, 0.243f, 0.502f, 1 };
        var ink = filled > 0 ? pink : get_color ();
        Gdk.RGBA amber = { 0.976f, 0.769f, 0.251f, 1 };
        // An upward arch over 130° (a boomerang's curve), cut into three.
        double radius = (w - 4) / 1.93, cx = w / 2.0, cy = 2.5 + radius;
        double start = Math.PI * 205 / 180, span = Math.PI * 130 / 180, gap = 0.17;
        cr.set_line_width (3.5);
        cr.set_line_cap (Cairo.LineCap.ROUND);
        for (int i = 0; i < 3; i++) {
            var color = problem ? amber : ink;
            // Partial link: one banana segment only; otherwise the segments that are filled.
            double alpha = problem ? (i == 0 ? 1.0 : 0.0) : i < filled ? 1.0 : 0.28;
            if (pending && i == filled - 1) {
                alpha = 0.55 + 0.45 * Math.cos (2 * Math.PI * phase);  // breathes
            }
            cr.set_source_rgba (color.red, color.green, color.blue, color.alpha * alpha);
            double a0 = start + span * i / 3 + gap, a1 = start + span * (i + 1) / 3 - gap;
            cr.new_path ();
            cr.arc (cx, cy, radius, a0, a1);
            cr.stroke ();
        }
    }
}

/* A thin band under the header bar, only while the iPhone is not fully linked: what is wrong in
   one sentence and the one action that helps. When all is well, nothing is shown. */
public class Boomerang.LinkBanner : Gtk.Box {
    /* "pair" (the window opens the pairing dialog). */
    public signal void action_requested (string action);
    /* For the dot on « iPhone »: the state in words, and whether something is missing. */
    public signal void state_changed (string summary, bool attention);

    private Daemon daemon;
    private Gtk.Label title;
    private Gtk.Label detail;
    private Gtk.Button action;
    private string action_id = "";

    public LinkBanner (Daemon daemon) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        this.daemon = daemon;
        daemon.changed.connect (() => {
            if (daemon.touched ({ "LinkState", "LinkProblem", "DeviceName" })) {
                update ();
            }
        });
    }

    construct {
        add_css_class ("link-banner");
        visible = false;
        title = new Gtk.Label ("") { xalign = 0 };
        title.add_css_class ("heading");
        detail = new Gtk.Label ("") { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
        detail.add_css_class (Granite.CssClass.DIM);
        action = new Gtk.Button () { valign = Gtk.Align.CENTER };
        action.clicked.connect (() => {
            if (action_id == "reconnect") {
                daemon.call.begin ("Reconnect");
            } else if (action_id == "bluetooth") {
                AppInfo.launch_default_for_uri_async.begin ("settings://network/bluetooth", null);
            } else {
                action_requested (action_id);
            }
        });
        append (title);
        append (detail);
        append (action);
    }

    public void update () {
        var state = daemon.get_string ("LinkState");
        var s = LinkText.describe (state, daemon.get_string ("LinkProblem"), daemon.get_string ("DeviceName"));
        var attention = daemon.running && state != "" && state != "complete";
        visible = attention;
        title.label = s.title;
        detail.label = s.detail;
        detail.tooltip_text = s.detail;
        action_id = s.action;
        action.label = s.action_label;
        action.visible = s.action != "";
        state_changed (s.title, attention);
    }
}
