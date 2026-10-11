# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""The screen mirroring window.

UxPlay receives and decodes the iPhone's screen; its own video window has no
frame, no title and no app identity under Wayland. So UxPlay hands the decoded
frames to this window through shared memory (gdppay ! shmsink, which carries
the caps along), and this window shows them like any app: header bar in
Boomerang's colour, sized to the screen, its own entry in the dock (app id of
the Mirroring launcher), full screen with F11.

Started and stopped by boomerangd (mirror.py) with:
    python3 -m boomerangd.mirror_viewer --socket PATH --name NAME [--fullscreen]
Closing the window stops the mirroring.
"""

import argparse
import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gst", "1.0")
from gi.repository import Gdk, Gio, GLib, Gst, Gtk  # noqa: E402

from .i18n import _  # noqa: E402
from .util import APP_ID  # noqa: E402

DAEMON = os.environ.get("BOOMERANG_DAEMON_NAME", "io.github.melvincouwez.Boomerang1")
PATH = "/io/github/melvincouwez/Boomerang1"
IFACE = "io.github.melvincouwez.Boomerang1"
RETRY_MS = 500

CSS = """
headerbar.mirror-bar {
    background: linear-gradient(#b4519f, #96368a);
    box-shadow: inset 0 1px alpha(white, 0.22), inset 0 -1px #6f2266;
    color: white;
    border: none;
}
headerbar.mirror-bar button { color: white; background: none; border: none; box-shadow: none; }
headerbar.mirror-bar button:hover { background-color: alpha(white, 0.16); }
headerbar.mirror-bar .subtitle { opacity: 0.85; }
.mirror-screen { background: black; }
.mirror-wait { color: alpha(white, 0.8); }
"""


def available():
    """Whether this window can run: GTK 4's GStreamer sink is installed."""
    try:
        Gst.init(None)
        return Gst.ElementFactory.find("gtk4paintablesink") is not None
    except Exception:
        return False


class Viewer(Gtk.Application):
    def __init__(self, socket_path, name, fullscreen):
        # NON_UNIQUE: the Mirroring tab of Boomerang uses the same id for the dock icon.
        super().__init__(application_id=APP_ID + ".Mirror", flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.socket_path = socket_path
        self.name = name
        self.start_fullscreen = fullscreen
        self.pipeline = None
        self.sink = None
        self.sized = False
        self.closing = False

    def do_activate(self):
        Gtk.Application.do_activate(self)
        css = Gtk.CssProvider()
        css.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        win = self.window = Gtk.ApplicationWindow(application=self, title=_("Recopie d'écran"))
        header = Gtk.HeaderBar()
        header.add_css_class("mirror-bar")
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        title = Gtk.Label(label=_("Recopie d'écran"))
        title.add_css_class("title")
        subtitle = Gtk.Label(label=self.name)
        subtitle.add_css_class("subtitle")
        titles.append(title)
        titles.append(subtitle)
        header.set_title_widget(titles)
        self.full_button = Gtk.Button(icon_name="view-fullscreen-symbolic", tooltip_text=_("Plein écran (F11)"))
        self.full_button.connect("clicked", lambda b: self.toggle_fullscreen())
        header.pack_end(self.full_button)
        win.set_titlebar(header)

        self.picture = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN, hexpand=True, vexpand=True)
        self.picture.add_css_class("mirror-screen")
        self.waiting = Gtk.Label(
            label=_("En attente de l'iPhone…\nSur l'iPhone : Centre de contrôle › Recopie de l'écran › {name}")
            .format(name=self.name), justify=Gtk.Justification.CENTER, wrap=True)
        self.waiting.add_css_class("mirror-wait")
        overlay = Gtk.Overlay(child=self.picture)
        overlay.add_css_class("mirror-screen")
        overlay.add_overlay(self.waiting)
        win.set_child(overlay)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        win.add_controller(keys)
        win.connect("close-request", self.on_close)
        win.connect("notify::fullscreened", lambda *a: self.full_button.set_icon_name(
            "view-restore-symbolic" if win.is_fullscreen() else "view-fullscreen-symbolic"))
        if self.start_fullscreen:
            win.fullscreen()
        # Shown with the first picture, at its shape: until then there is nothing to see
        # (Boomerang's Recopie page says what to do on the iPhone).
        self.hold()
        self.connect_stream()

    # --- stream ---

    def connect_stream(self):
        """shmsrc fails until UxPlay has a picture to give: try again until it has."""
        if self.closing:
            return False
        if not os.path.exists(self.socket_path):
            GLib.timeout_add(RETRY_MS, self.connect_stream)
            return False
        self.pipeline = Gst.parse_launch(
            f'shmsrc socket-path="{self.socket_path}" is-live=true do-timestamp=true '
            "! gdpdepay ! videoconvert ! gtk4paintablesink name=sink sync=false")
        self.sink = self.pipeline.get_by_name("sink")
        self.picture.set_paintable(self.sink.get_property("paintable"))
        self.sink.get_static_pad("sink").connect("notify::caps", self.on_caps)
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message::error", self.on_error)
        bus.connect("message::eos", self.on_error)
        self.pipeline.set_state(Gst.State.PLAYING)
        return False

    def on_error(self, bus, message):
        # UxPlay stopped sending (iPhone stopped mirroring, rotation): wait for the next stream.
        self.drop_pipeline()
        self.waiting.set_visible(True)
        GLib.timeout_add(RETRY_MS, self.connect_stream)

    def drop_pipeline(self):
        if self.pipeline is not None:
            self.pipeline.get_bus().remove_signal_watch()
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None

    def on_caps(self, pad, pspec):
        caps = pad.get_current_caps()
        if caps is None:
            return
        s = caps.get_structure(0)
        ok_w, width = s.get_int("width")
        ok_h, height = s.get_int("height")
        GLib.idle_add(self.on_first_frame, width if ok_w else 0, height if ok_h else 0)

    def on_first_frame(self, width, height):
        self.waiting.set_visible(False)
        win = self.window
        if not win.get_visible():
            if width and height:
                # The picture's shape, 85 % of the screen high at most (or wide, for landscape).
                monitors = win.get_display().get_monitors()
                geo = monitors.get_item(0).get_geometry() if monitors.get_n_items() else None
                max_w = int((geo.width if geo else 1920) * 0.85)
                max_h = int((geo.height if geo else 1080) * 0.85) - 48
                scale = min(max_w / width, max_h / height, 1.0)
                size = (max(240, int(width * scale)), max(240, int(height * scale)) + 48)
                win.set_default_size(*size)
                # The compositor may hand back the size of the last window of this app: insist once.
                GLib.timeout_add(300, lambda: win.set_default_size(*size) or False)
            win.present()
            self.release()
        snapshot = os.environ.get("BOOMERANG_SNAPSHOT")
        if snapshot and not getattr(self, "_snapped", False):
            # Development: the window as a PNG, then quit (checked without showing anything).
            self._snapped = True
            GLib.timeout_add(1500, self.save_snapshot, snapshot)
        return False

    def save_snapshot(self, path):
        paintable = Gtk.WidgetPaintable.new(self.window)
        snap = Gtk.Snapshot()
        paintable.snapshot(snap, self.window.get_width(), self.window.get_height())
        node = snap.to_node()
        if node is not None:
            self.window.get_native().get_renderer().render_texture(node, None).save_to_png(path)
        self.quit()
        return False

    # --- window ---

    def toggle_fullscreen(self):
        if self.window.is_fullscreen():
            self.window.unfullscreen()
        else:
            self.window.fullscreen()

    def on_key(self, controller, keyval, code, state):
        if keyval == 0xffc8:  # F11
            self.toggle_fullscreen()
            return True
        if keyval == 0xff1b and self.window.is_fullscreen():  # Escape
            self.window.unfullscreen()
            return True
        return False

    def on_close(self, window):
        self.closing = True
        self.drop_pipeline()
        # Closing the window ends the mirroring, as UxPlay's own window did.
        try:
            Gio.bus_get_sync(Gio.BusType.SESSION).call_sync(
                DAEMON, PATH, IFACE, "StopMirror", None, None, Gio.DBusCallFlags.NO_AUTO_START, 3000)
        except GLib.Error:
            pass
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(prog="boomerang-mirror-viewer")
    parser.add_argument("--socket", required=True)
    parser.add_argument("--name", default="Boomerang")
    parser.add_argument("--fullscreen", action="store_true")
    args = parser.parse_args(argv)
    Gst.init(None)
    GLib.set_prgname(APP_ID + ".Mirror")
    GLib.set_application_name(_("Recopie d'écran"))
    return Viewer(args.socket, args.name, args.fullscreen).run([sys.argv[0]])


if __name__ == "__main__":
    sys.exit(main())
