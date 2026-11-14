title: Getting started
icon: system-software-install
summary: Install, add missing components, run the setup.
---
## Install Boomerang
1. Download the `.deb` package from the project's releases page.
2. In a terminal, in the download folder, run `sudo apt install ./boomerang_*.deb` and enter your password. The required packages are installed at the same time. On Ubuntu, the App Center can also open the file with a double-click.
3. Log out and back in to start the service.
4. Open Boomerang from the applications menu.

## Missing components
If something is missing on your system, Boomerang says so in a **Missing components** card. The card shows at the start of the setup and in [Settings › Advanced › Updates](app:advanced/updates).
1. Read the list: each line says what the component is for.
2. Click **Install**. You are asked for your password once.
3. Wait for the progress bar to finish. The card disappears when everything is in place.

!warn Some components cannot be installed from Boomerang, for example a newer PipeWire for calls on elementary OS 8. The card then says "System update needed". The rest of Boomerang still works.

## The setup assistant
On first launch, a full-window assistant welcomes you:
1. Choose what to connect: **Your iPhone**, **Apple Services**, or both.
2. Follow the steps. Each one ticks itself when it is done.
3. At the **Separate Apps** step, choose whether Headphones also shows as a separate app in the Applications menu.
4. Click **Open Boomerang**. You can also click **Skip Setup** and come back later.

To run it again, open the menu at the top right of the window and choose [Setup Assistant](app:setup). It is also in Settings › Advanced › Help, on the **Initial Setup** row.
