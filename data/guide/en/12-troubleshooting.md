title: Troubleshooting
icon: dialog-question
summary: Common problems and what to try.
---
### "The Boomerang service is not responding"
The background service is stopped. Open a Terminal and type `systemctl --user restart boomerangd`. Its log: `journalctl --user -u boomerangd`.

### The iPhone does not reconnect
1. Check that Bluetooth is on, on both sides.
2. Click **Reconnect** in the [Overview](app:device).
3. Otherwise, on the iPhone: Settings › Bluetooth, tap the computer's name.
4. If the Overview says the iPhone no longer knows this PC, click **Pair again…**
5. As a last resort, click **Forget** in the Overview, forget the computer on the iPhone too, then [pair](guide:link) again.

### No notifications
Boomerang receives notifications over the low energy link or, failing that, over the classic link. If it says **Notifications interrupted**:

1. Check **Share System Notifications** (Settings › Bluetooth › ⓘ next to the computer).
2. Turn the iPhone's Bluetooth off and on again in Settings.
3. If nothing changes, click **Pair again** in the Overview. Boomerang drops its old keys and guides you: forget the computer on the iPhone (ⓘ › **Forget This Device**), then pair it again.

### A notification stays or comes back
A notification cleared on the iPhone leaves the desktop, even when it was cleared during a cut: Boomerang sorts them out about twenty seconds after reconnecting. A notification closed on the computer does not come back, even if the iPhone updates it. If one stays anyway, report it on the project page.

### The iPhone refuses messages
Turn on **Show Notifications** (Settings › Bluetooth › ⓘ), then click **Check** in the setup.

### A message shows twice
Delete the extra copy (right-click, **Delete from Boomerang**). If it happens again, report it on the project page.

### A message only shows its beginning
That is intended until it is read on the iPhone. See [Messages](guide:messages).

### A call has no sound
During the call, turn on **PC audio**. Check the output and microphone in System Settings › Sound.

### No calls at all
If your PipeWire is older than 1.4, calls are not available. See [Phone](guide:phone).

### iCloud Drive or Photos is empty
Apple probably wants the sign-in confirmed again: **Reconnect…** in [Apple Services](app:services). Log: `journalctl --user -u boomerang-icloud-drive`.

### "rclone not found" or too old
rclone 1.69 or newer is needed. Follow the **Missing components** card in [Settings](app:settings).

### The earbuds stay on "reading state"
Put the earbuds back in the case, close it, then open it again near the computer.

### Report a problem
Open an issue on the project page (Issues tab). Describe what you were doing, without pasting your messages or numbers.
