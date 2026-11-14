title: Troubleshooting
icon: dialog-question
summary: Common problems and what to try.
---
### "The Boomerang service is not responding"
The background service is stopped. Open a Terminal and type `systemctl --user restart boomerangd`, then click **Retry**. Its log: `journalctl --user -u boomerangd`.

### The iPhone does not reconnect
1. Check that Bluetooth is on, on both sides.
2. Click **Reconnect Now** in the band at the top of the window, or **Reconnect** on the iPhone card in [Settings](app:device).
3. Otherwise, on the iPhone: Settings › Bluetooth, tap the computer's name.
4. If Boomerang says "The iPhone no longer recognises this PC", click **Pair again…**
5. As a last resort, click **Forget This iPhone…** in [Settings › Advanced › Connection](app:advanced/connection). Forget the computer on the iPhone too, then [pair](guide:link) again.

### No notifications
Boomerang receives notifications over the low energy link or, failing that, over the classic link. If it says **Notifications interrupted**:

1. Check **Share System Notifications** (Settings › Bluetooth › ⓘ next to the computer).
2. Turn the iPhone's Bluetooth off and on again in Settings.
3. If nothing changes, click **Pair again…** in the band. Boomerang drops its old keys and guides you: forget the computer on the iPhone (ⓘ › **Forget This Device**), then pair it again.

### A notification stays or comes back
A notification cleared on the iPhone leaves the desktop, even when it was cleared during a cut: Boomerang sorts them out about twenty seconds after reconnecting. A notification closed on the computer does not come back, even if the iPhone updates it. If one stays anyway, report it on the project page.

### The iPhone refuses messages
Turn on **Show Notifications** (Settings › Bluetooth › ⓘ). Then open the **Connection guide** in [Settings › Advanced › Connection](app:advanced/connection) and click **Check**.

### A message shows twice
Delete the extra copy (right-click, **Delete from Boomerang…**). If it happens again, report it on the project page.

### A message only shows its beginning
That is intended until it is read on the iPhone. See [Messages](guide:messages).

### A call has no sound
In the call window, open **Audio output** and choose an output of the computer. In the green bar, the **Sound on this PC** button must be on. Then check the output and microphone in System Settings › Sound.

### No calls at all
If your PipeWire is older than 1.4, calls are not available. The **Calls on this PC** row in [Settings](app:settings) says so. See [Calls](guide:phone).

### iCloud Drive or Photos is empty
Apple probably wants the sign-in confirmed again: click **Reconnect…** on the [iCloud Services](app:services) page. Log: `journalctl --user -u boomerang-icloud-drive`.

### rclone missing or too old
rclone 1.69 or newer is needed. Follow the **Missing components** card in [Settings › Advanced › Updates](app:advanced/updates).

### The earbuds stay on "Reading the headphones' state…"
Put the earbuds back in the case, close it, then open it again near the computer.

### Report a problem
Open an issue on the project page (Issues tab). Describe what you were doing, without pasting your messages or numbers.
