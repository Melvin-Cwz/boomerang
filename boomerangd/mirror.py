# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Recopie d'écran: the iPhone's screen on the PC through UxPlay (experimental).

UxPlay (https://github.com/FDH2/UxPlay, GPL-3.0) is a free AirPlay mirroring
receiver, packaged by Ubuntu as "uxplay". Boomerang only starts and stops it,
on the user's request, under the name "Boomerang (<computer>)"; the iPhone then
lists it in Control Centre › Screen Mirroring. It needs Avahi (mDNS) to be seen.
Nothing listens on the network while it is stopped. While it runs, AirPlay asks
for a 4-digit code (UxPlay -pin), drawn anew at each start and shown in the Recopie
app: another device on the network cannot put its own picture on the PC's screen.

The video stays in UxPlay's own window: UxPlay is a separate program, so its
GStreamer video sink cannot draw inside Boomerang's GTK window (that would need
the frames sent between processes, e.g. shmsink/shmsrc, left for later). The
Recopie app is the control panel: start, stop, profile, rotation, full screen,
and the iPhone control pad.

Options ([mirror] in boomerangd.conf):
- profile: "fluid" (default: no audio/video sync, lowest latency) or "quality"
  (audio kept in sync with the picture, a little more delay);
- rotation: "", "R" or "L"; fullscreen: true or false;
- screen: "WxH" of the PC's screen, sent by the app, asked of the iPhone (-s);
- record: true to save the mirrored screen and sound as an MP4 file in the Videos
  folder (UxPlay -mp4, one dated file per session).
The screensaver is held off while the iPhone mirrors (UxPlay -scrsv 1, through D-Bus).
Experimental (AlphaFeatures "mirror_ble"): a Bluetooth LE beacon (UxPlay -ble and its
uxplay-beacon script) so that the iPhone lists the PC even when mDNS does not get
through the network. It is a second BlueZ advertisement beside Boomerang's own
(adapters offer several instances, see LEAdvertisingManager1.SupportedInstances), and
it only runs while UxPlay does.
The H.264 decoder is chosen once: NVIDIA (nvh264dec, needs libcuda), then VA-API
(vah264dec, needs a render node), then software (libav). If UxPlay stops with an
error on a hardware decoder, it is restarted once in software.
"""

import glob
import os
import secrets
import shutil
import socket
import sys

from gi.repository import Gio, GLib

from .util import cached_for, log

# GStreamer plugins UxPlay needs at start ("Required gstreamer plugin … not found"),
# by file name, with the package that provides them.
PLUGINS = {"libgstvideoparsersbad.so": "gstreamer1.0-plugins-bad",
           "libgstlibav.so": "gstreamer1.0-libav"}
LOG = os.path.join(GLib.get_user_cache_dir(), "boomerang", "uxplay.log")
PROFILES = ("fluid", "quality")
ROTATIONS = ("", "R", "L")

TYPES = {"available": "b", "running": "b", "name": "s", "error": "s", "missing": "as",
         "profile": "s", "rotation": "s", "fullscreen": "b", "decoder": "s", "pin": "s",
         "record": "b", "recording": "s", "beacon": "b"}
BLE_FILE = os.path.join(GLib.get_user_cache_dir(), "boomerang", "uxplay.ble")
# Decoded frames from UxPlay to Boomerang's mirroring window.
VIEWER_SOCKET = os.path.join(GLib.get_user_runtime_dir(), "boomerang-mirror.shm")


def _plugin_dirs():
    return glob.glob("/usr/lib/*/gstreamer-1.0") + glob.glob("/usr/lib/gstreamer-1.0")


def _has_plugin(name, dirs=None):
    return any(os.path.exists(os.path.join(d, name)) for d in (dirs or _plugin_dirs()))


def pick_decoder(dirs=None, cuda=None, render=None):
    """"nvidia", "vaapi" or "software", from what the system offers."""
    dirs = dirs if dirs is not None else _plugin_dirs()
    if cuda is None:
        cuda = bool(glob.glob("/usr/lib/*/libcuda.so.1") or glob.glob("/usr/lib/libcuda.so.1"))
    if render is None:
        render = bool(glob.glob("/dev/dri/renderD*"))
    if cuda and _has_plugin("libgstnvcodec.so", dirs):
        return "nvidia"
    if render and _has_plugin("libgstva.so", dirs):
        return "vaapi"
    return "software"


@cached_for(60)
def _probe():
    """(missing packages, decoder) for the state, which runs at every property refresh:
    an install is seen within 60 s, at once after StopMirror; start() always looks again."""
    return Mirror.missing(), pick_decoder()


def new_pin():
    """A 4-digit AirPlay code, never 0000 (UxPlay reads a missing code as « draw one »)."""
    return "%04d" % (1 + secrets.randbelow(9999))


def viewer_sink(socket_path):
    """UxPlay's video sink when Boomerang's own window shows the picture: the decoded
    frames go to shared memory in I420, gdppay carrying their size and format along.
    UxPlay waits for the window to be connected: gdppay sends the format only once,
    with the first frame, and a window joining later could not read the rest."""
    return (f"videoconvert ! video/x-raw,format=I420 ! gdppay ! shmsink socket-path={socket_path} "
            "shm-size=134217728 wait-for-connection=true sync=false")


def build_args(name, profile="fluid", rotation="", fullscreen=False, screen="", decoder="software",
               pin="", record="", ble="", viewer=""):
    """UxPlay's command line for these options. viewer: shared memory socket of
    Boomerang's mirroring window, which then shows the picture instead of UxPlay."""
    args = ["uxplay", "-n", name, "-nh", "-fps", "60", "-scrsv", "1"]
    if pin:
        args += ["-pin", pin]
    if record:
        args += ["-mp4", record]  # UxPlay adds .<n>.<format>.mp4
    if ble:
        args += ["-ble", ble]
    if profile != "quality":
        args += ["-vsync", "no"]  # no audio/video timestamp sync: lowest latency
    size = _screen(screen)
    if size:
        args += ["-s", "%dx%d@60" % size]
    if decoder == "nvidia":
        args += ["-vd", "nvh264dec"] + ([] if viewer else ["-vs", "glimagesink"])
    elif decoder == "vaapi":
        args += ["-vd", "vah264dec"]
    else:
        args += ["-avdec"]
    if viewer:
        args += ["-vs", viewer_sink(viewer)]
    if rotation in ("R", "L"):
        args += ["-r", rotation]
    if fullscreen and not viewer:
        args += ["-fs"]  # the window does it otherwise
    return args


def recording_base(now=None, videos=None):
    """Videos/Recopie iPhone 2026-10-04 21-30-05 (UxPlay appends the extension)."""
    now = now or GLib.DateTime.new_now_local()
    videos = videos or GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_VIDEOS) \
        or os.path.join(GLib.get_home_dir(), "Videos")
    return os.path.join(videos, now.format("Recopie iPhone %Y-%m-%d %H-%M-%S"))


def _screen(text):
    """"2560x1600" -> (2560, 1600), capped to what AirPlay mirroring asks for."""
    try:
        width, height = (int(v) for v in (text or "").lower().split("x", 1))
    except ValueError:
        return None
    if width < 320 or height < 240:
        return None
    # The iPhone sends at most 1920 wide in mirroring; a larger request only costs bandwidth.
    if width > 1920:
        height = height * 1920 // width
        width = 1920
    return width, height


class Mirror:
    def __init__(self, changed, config=None):
        self.changed = changed
        self.config = config
        self.process = None
        self.error = ""
        self.decoder = ""
        self.fallback = False
        self.pin = ""
        self.recording = ""   # base path of the MP4 being written, while UxPlay runs
        self.beacon = None    # uxplay-beacon process, while UxPlay runs with mirror_ble
        self.viewer = None    # Boomerang's mirroring window (mirror_viewer.py), while UxPlay runs
        self._viewer_ok = None
        self.name = "Boomerang (%s)" % (socket.gethostname().split(".")[0] or "PC")

    @staticmethod
    def missing():
        found = []
        if shutil.which("uxplay") is None:
            found.append("uxplay")
        if shutil.which("avahi-daemon") is None and not GLib.file_test(
                "/usr/sbin/avahi-daemon", GLib.FileTest.EXISTS):
            found.append("avahi-daemon")
        dirs = _plugin_dirs()
        for plugin, package in PLUGINS.items():
            if not _has_plugin(plugin, dirs):
                found.append(package)
        return found

    # --- options ----------------------------------------------------------------------------

    def _get(self, key, default=""):
        if self.config is None:
            return default
        try:
            return self.config.keyfile.get_string("mirror", key)
        except GLib.Error:
            return default

    def option(self, key):
        if key in ("fullscreen", "record"):
            return self._get(key, "false") == "true"
        if key == "profile":
            value = self._get("profile", "fluid")
            return value if value in PROFILES else "fluid"
        if key == "rotation":
            value = self._get("rotation", "")
            return value if value in ROTATIONS else ""
        return self._get(key, "")

    def set_option(self, key, value):
        """profile, rotation, fullscreen or screen; applied at the next start."""
        if key == "profile" and value not in PROFILES or key == "rotation" and value not in ROTATIONS:
            return False
        if key in ("fullscreen", "record"):
            value = "true" if value in ("true", "1", "yes") else "false"
        if key not in ("profile", "rotation", "fullscreen", "screen", "record"):
            return False
        if self.config is not None and self._get(key, None) != value:
            self.config.keyfile.set_string("mirror", key, value)
            self.config.save()
        self.changed()
        return True

    def state(self):
        missing, decoder = _probe()
        return {"available": not missing, "running": self.process is not None,
                "name": self.name, "error": self.error, "missing": missing,
                "profile": self.option("profile"), "rotation": self.option("rotation"),
                "fullscreen": self.option("fullscreen"),
                "decoder": self.decoder or decoder,
                "pin": self.pin if self.process is not None else "",
                "record": self.option("record"), "recording": self.recording,
                "beacon": self.beacon is not None}

    # --- process ------------------------------------------------------------------------------

    def start(self, decoder=None):
        if self.process is not None:
            return True
        if self.missing():
            self.error = "missing"
            self.changed()
            return False
        self.error = ""
        self.decoder = decoder or pick_decoder()
        self.fallback = decoder is not None
        if not self.fallback or not self.pin:
            self.pin = new_pin()
        self.recording = recording_base() if self.option("record") else ""
        if self.recording:
            os.makedirs(os.path.dirname(self.recording), exist_ok=True)
        ble = BLE_FILE if self._beacon_wanted() else ""
        socket_path = VIEWER_SOCKET if self._viewer_usable() else ""
        if socket_path:
            try:
                os.remove(socket_path)  # a socket left by a crash would be taken for a live one
            except OSError:
                pass
        args = build_args(self.name, self.option("profile"), self.option("rotation"),
                          self.option("fullscreen"), self.option("screen"), self.decoder, self.pin,
                          self.recording, ble, socket_path)
        try:
            # Its output goes to a file (a pipe left unread would block it); read on exit.
            os.makedirs(os.path.dirname(LOG), exist_ok=True)
            launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.NONE)
            launcher.set_stdout_file_path(LOG)
            launcher.set_stderr_file_path(LOG)
            self.process = launcher.spawnv(args)
        except GLib.Error as error:
            self.error = error.message
            log("recopie : lancement impossible")
            self.changed()
            return False
        self.process.wait_async(None, self._ended)
        if socket_path:
            self._start_viewer(socket_path)
        if ble:
            self._start_beacon()
        log(f"recopie : récepteur AirPlay démarré (décodage {self.decoder}, "
            f"profil {self.option('profile')})")
        self.changed()
        return True

    def _ended(self, process, result):
        try:
            process.wait_finish(result)
        except GLib.Error:
            pass
        if process is not self.process:
            return
        status = process.get_exit_status() if process.get_if_exited() else 0
        self.process = None
        self._stop_beacon()
        self._stop_viewer()
        if self.recording:
            log("recopie : enregistrement terminé (dossier Vidéos)")
            self.recording = ""
        failed = status not in (0,) and not process.get_if_signaled()
        if failed and self.decoder != "software" and not self.fallback:
            log(f"recopie : échec avec le décodage {self.decoder}, nouvel essai en logiciel")
            self.start(decoder="software")
            return
        if failed:
            self.error = self._reason() or "exited"
        log("recopie : récepteur AirPlay arrêté")
        self.changed()

    @staticmethod
    def _reason():
        """The first error UxPlay printed, e.g. "Required gstreamer plugin 'x' not found"."""
        try:
            with open(LOG, encoding="utf-8", errors="replace") as f:
                lines = [line.strip() for line in f.readlines()[-40:]]
        except OSError:
            return ""
        for line in lines:
            if "not found" in line or "ERROR" in line or "rror" in line:
                return line.strip("* ")[:200]
        return ""

    # --- Boomerang's mirroring window ----------------------------------------------------------

    def _viewer_usable(self):
        """GTK 4's GStreamer sink (package gstreamer1.0-gtk4) is needed; without it
        UxPlay keeps its own window."""
        if self._viewer_ok is None:
            try:
                import gi
                gi.require_version("Gst", "1.0")
                from gi.repository import Gst
                Gst.init(None)
                self._viewer_ok = Gst.ElementFactory.find("gtk4paintablesink") is not None
            except (ImportError, ValueError):
                self._viewer_ok = False
            if not self._viewer_ok:
                log("recopie : gstreamer1.0-gtk4 absent, fenêtre d'UxPlay")
        return self._viewer_ok

    def _start_viewer(self, socket_path):
        package_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        args = [sys.executable, "-m", "boomerangd.mirror_viewer", "--socket", socket_path,
                "--name", self.name]
        if self.option("fullscreen"):
            args.append("--fullscreen")
        try:
            launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.NONE)
            launcher.setenv("PYTHONPATH", package_root, True)
            launcher.set_stdout_file_path(LOG + ".viewer")
            launcher.set_stderr_file_path(LOG + ".viewer")
            self.viewer = launcher.spawnv(args)
        except GLib.Error:
            log("recopie : fenêtre de recopie non lancée")
            self.viewer = None
            return
        self.viewer.wait_async(None, self._viewer_ended)

    def _viewer_ended(self, process, result):
        try:
            process.wait_finish(result)
        except GLib.Error:
            pass
        if process is not self.viewer:
            return
        # The window is gone (closed, or crashed): UxPlay would wait for it forever.
        self.viewer = None
        if self.process is not None:
            log("recopie : fenêtre fermée, recopie arrêtée")
            self.stop()

    def _stop_viewer(self):
        if self.viewer is not None:
            self.viewer.send_signal(15)
            self.viewer = None
        try:
            os.remove(VIEWER_SOCKET)
        except OSError:
            pass

    # --- Bluetooth LE beacon (experimental) ---------------------------------------------------

    def _beacon_wanted(self):
        return (self.config is not None and self.config.alpha("mirror_ble")
                and shutil.which("uxplay-beacon") is not None)

    def _start_beacon(self):
        """uxplay-beacon reads what UxPlay writes in BLE_FILE (address, port) and
        advertises it through BlueZ; it stops advertising when that file goes away."""
        if self.beacon is not None:
            return
        try:
            launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.NONE)
            launcher.set_stdout_file_path(LOG + ".ble")
            launcher.set_stderr_file_path(LOG + ".ble")
            self.beacon = launcher.spawnv(["uxplay-beacon", "--path", BLE_FILE])
        except GLib.Error:
            log("recopie : balise Bluetooth non lancée")
            self.beacon = None
            return
        log("recopie : balise Bluetooth LE active")

    def _stop_beacon(self):
        if self.beacon is not None:
            self.beacon.send_signal(15)
            self.beacon = None
            log("recopie : balise Bluetooth LE arrêtée")
        try:
            os.remove(BLE_FILE)
        except OSError:
            pass

    def stop(self):
        if self.process is not None:
            self.process.send_signal(15)
        else:
            _probe.forget()
            self.changed()  # also a refresh after installing UxPlay
