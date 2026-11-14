title: Mirroring and iPhone control
icon: @APP_ID@.Mirror
summary: The iPhone's screen on the PC, and the PC's mouse and keyboard on the iPhone.
---
## Show the iPhone's screen
1. Open the [Screen mirroring](app:mirror) page of the iPhone tab, or the separate Mirroring app, and click **Receive the iPhone's screen**.
2. On the iPhone, open **Control Centre** (swipe down from the top right corner).
3. Tap **Screen Mirroring**, then choose **Boomerang (name of the PC)**.
4. Type on the iPhone the four-digit code shown on the Screen mirroring page. It changes at each start: another device on the network cannot show its screen on the PC.
5. A window opens on the PC with the iPhone's screen. To finish, click **Stop** on the Screen mirroring page or stop mirroring on the iPhone.

The PC and the iPhone must be on the same Wi-Fi network.

!tip Screen mirroring is a module. If the page does not show in the left column of the iPhone tab, click **Add Modules…**, then **Add** next to Screen mirroring.

!tip In the **Profile** setting, **Smooth** keeps the delay as short as possible, best to control the iPhone. **Quality** keeps the sound in sync with the picture, better to watch a video.

## Control the iPhone with the PC's mouse and keyboard
Boomerang can present itself to the iPhone as a Bluetooth mouse and keyboard. This is experimental and off by default.

### 1. Turn on the mouse and keyboard
1. On the [Screen mirroring](app:mirror) page, turn on **Bluetooth mouse and keyboard**.
2. On the iPhone, open **Settings › Bluetooth**.
3. Tap **Boomerang** in the list of devices, then accept the pairing request.

!warn If the iPhone already knows Boomerang (for notifications) but offers no mouse, tap the **ⓘ** next to Boomerang, then **Forget This Device**, and pair it again. You will then need to allow notifications again.

### 2. Show the pointer with AssistiveTouch
The iPhone only shows a mouse pointer with AssistiveTouch.
1. Open **Settings › Accessibility › Touch › AssistiveTouch**.
2. Turn on **AssistiveTouch**. A grey button and a pointer appear.
3. On the same screen, set the **Tracking Speed**: slower makes the pointer more precise.

!tip To turn AssistiveTouch on without going to Settings: **Settings › Accessibility › Accessibility Shortcut**, tick **AssistiveTouch**. A triple click on the side button turns it on or off.

### 3. Use the control pad
- Click in the control pad of the Screen mirroring page: it turns blue, the mouse and keyboard go to the iPhone.
- Move the mouse over the pad: the iPhone's pointer follows. Left click taps, right click opens the AssistiveTouch menu, the wheel scrolls.
- Type on the keyboard: the keys reach the iPhone. For longer text, use the **Text to type on the iPhone** field.
- The **Control Centre** and **App Switcher** buttons do the matching gestures.
- **Re-centre the pointer** brings it to the middle. If it misses, adjust the width and height in **Pointer setting**.

!tip Choose the same keyboard layout on the iPhone as on the PC: **Settings › General › Keyboard › Hardware Keyboard**.

## Useful keyboard shortcuts
Apple's ⌘ (Command) key is the PC's Super key. The desktop often keeps it for itself: use the buttons of the Screen mirroring page instead, or the **⌘** button, which holds it for the next key.
- **⌘H**: back to the Home Screen (**Home** button).
- **⌘Space**: search (**Search** button).
- **⌘Tab**: switch to the previous app (**Switch app** button).
- **Arrows** and **Return**: move and confirm in many apps.

Depending on the model and the iOS version, some shortcuts only work on iPad.

## Bonus: Apple's Shortcuts
- **AssistiveTouch in one gesture**: the Accessibility Shortcut above (triple click on the side button) is the simplest.
- **A "Control from the PC" shortcut**: in the **Shortcuts** app, make a shortcut with the **Set AssistiveTouch** action (On), if your iOS version offers it. Add it to the Home Screen.
- **Automation (optional)**: in Shortcuts › Automation, run this shortcut when the iPhone joins your home Wi-Fi, for example.

!warn As far as we know, Shortcuts has no action to start screen mirroring. The **Set Playback Destination** action only sends the sound and videos being played to an AirPlay device, not the screen. For mirroring, use Control Centre.
