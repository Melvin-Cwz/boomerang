// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Écouteurs and Recopie as apps of their own: same program, launched as
 * io.github.melvincouwez.Boomerang.Headphones or .Mirror (symlinks), so each has its own
 * dock icon, launcher entry and window. Messages, calls and contacts live in Boomerang's
 * main window (Personnes, Pavé).
 */

namespace Boomerang {
    public enum Mode {
        HUB, HEADPHONES, MIRROR;

        public string suffix () {
            switch (this) {
                case HEADPHONES: return ".Headphones";
                case MIRROR: return ".Mirror";
                default: return "";
            }
        }

        /* Écouteurs uses elementary's own icon (d9ecca9): its Boomerang SVG
           is gone, so the app id is no icon name for it. */
        public string icon_name () {
            switch (this) {
                case HEADPHONES: return "audio-headphones";
                default: return Config.APP_ID + suffix ();
            }
        }

        public string title () {
            switch (this) {
                case HEADPHONES: return _("Écouteurs");
                case MIRROR: return _("Recopie");
                default: return "Boomerang";
            }
        }

        public string guide_topic () {
            switch (this) {
                case HEADPHONES: return "headphones";
                case MIRROR: return "mirror";
                default: return "welcome";
            }
        }

        public static Mode from_program (string program) {
            var name = Path.get_basename (program);
            if (name.has_suffix (".Headphones")) {
                return HEADPHONES;
            }
            if (name.has_suffix (".Mirror")) {
                return MIRROR;
            }
            return HUB;
        }
    }

    /* Start (or reach) Boomerang or one of its apps with the given arguments. */
    public void launch (Mode mode, string[] args = {}) {
        string[] argv = { Path.build_filename (Config.BINDIR, Config.APP_ID + mode.suffix ()) };
        foreach (var a in args) {
            argv += a;
        }
        try {
            new Subprocess.newv (argv, SubprocessFlags.NONE);
        } catch (Error e) {
            warning ("cannot start %s: %s", argv[0], e.message);
        }
    }

    public class AppWindow : Gtk.ApplicationWindow {
        public Mode mode { get; construct; }

        private Daemon daemon;

        public AppWindow (Gtk.Application app, Mode mode) {
            Object (application: app, mode: mode,
                    title: mode.title (),
                    default_width: mode == Mode.HEADPHONES ? 620 : 640,
                    default_height: 640);
        }

        construct {
            daemon = new Daemon ();
            titlebar = plain_header ();
            Gtk.Widget content = mode == Mode.MIRROR ? (Gtk.Widget) new MirrorView (daemon) : new HeadphonesView (daemon);
            // The ongoing call is shown at the top of every Boomerang window.
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (new CallBar (daemon));
            content.vexpand = true;
            box.append (content);
            child = box;
            daemon.connect_bus.begin ();
        }

        private Gtk.HeaderBar plain_header () {
            var header = new Gtk.HeaderBar ();
            header.add_css_class ("flat");
            header.title_widget = new Gtk.Label (title);
            ((Gtk.Label) header.title_widget).add_css_class ("title");
            header.pack_end (Guide.help_button (mode.guide_topic (), _("Guide (F1)")));
            return header;
        }
    }
}
