# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""One-time codes received by mail, as macOS offers the codes from Mail.

Two sources: the desktop notifications of mail apps (Lucarne, Thunderbird, Geary,
Evolution, a webmail in the browser…), read by watching org.freedesktop.Notifications
Notify calls on the session bus, and the iPhone's mail notifications (ANCS, see
ancs.py). Either way the text goes to Messages.code_from_mail(), which keeps the code
for the browser extension and copies it like an SMS code.

The monitor is a second session-bus connection turned into a monitor: it only reads,
the notifications are shown as usual. Only mail senders are looked at, so a chat
message with digits in it never ends up on the clipboard.
"""

from gi.repository import Gio, GLib

from .util import log

# Desktop notifications: app name or desktop entry, case-folded, containing one of these.
DESKTOP_MAIL = ("mail", "courrier", "outlook", "lucarne", "thunderbird", "geary", "evolution",
                "betterbird", "proton", "tuta", "kmail", "mutt", "gmail")
# Browser notifications: a webmail says so in its title or body.
BROWSER = ("chrome", "chromium", "firefox", "vivaldi", "brave", "edge", "epiphany", "web")
WEBMAIL = ("gmail", "outlook", "icloud", "proton", "yahoo", "laposte", "orange", "free.fr",
           "sfr", "mail")
# iPhone apps (ANCS bundle identifiers).
IPHONE_MAIL = {"com.apple.mobilemail", "com.google.Gmail", "com.microsoft.Office.Outlook",
               "ch.protonmail.protonmail", "com.yahoo.Aerogram", "com.readdle.smartemail",
               "it.mail.mail", "com.tutanota.tutanota", "com.orange.mail.fr"}

MATCH = "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"


def is_mail(app_name, desktop_entry, text):
    who = f"{app_name} {desktop_entry}".casefold()
    if any(word in who for word in DESKTOP_MAIL):
        return True
    return any(word in who for word in BROWSER) and any(w in text.casefold() for w in WEBMAIL)


class MailCodes:
    def __init__(self, on_text):
        self.on_text = on_text  # called in the main loop with the text and the summary
        self.connection = None
        Gio.DBusConnection.new_for_address(
            Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None),
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None, self._connected)

    def _connected(self, _source, result):
        try:
            self.connection = Gio.DBusConnection.new_for_address_finish(result)
            self.connection.add_filter(self._filter)
            self.connection.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
                GLib.Variant("(asu)", ([MATCH], 0)), None, Gio.DBusCallFlags.NONE, 5000, None)
            log("codes : notifications de mail suivies")
        except GLib.Error as error:
            log(f"codes : notifications de mail non suivies ({error.message})")

    def stop(self):
        """Stop watching: closing the private connection ends the monitoring."""
        connection, self.connection = self.connection, None
        if connection is not None:
            connection.close(None, None, None)
        log("codes : notifications de mail plus suivies")

    def _filter(self, _connection, message, incoming):
        # Runs in GDBus's worker thread: hand the text over to the main loop.
        if incoming and message.get_member() == "Notify":
            body = message.get_body()
            if body is not None and body.n_children() >= 8:
                app_name, summary, text = body[0], body[3], body[4]
                entry = body[6].get("desktop-entry", "") if hasattr(body[6], "get") else ""
                full = f"{summary}\n{text}"
                if is_mail(app_name, entry, full):
                    GLib.idle_add(self._deliver, full, summary)
        return message

    def _deliver(self, text, sender):
        self.on_text(text, sender)
        return False
