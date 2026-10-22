# vivo Office Kit for Windows — English patch (test build)

Turns the China edition of vivo Office Kit (pcsuite) for Windows into English: the main app, its menus, and the phone mirroring and PC mode windows.

This is the Windows version of the patch in [vivo-office-kit-english](https://github.com/JacksonJones2003/vivo-office-kit-english). It uses the same translations as the Mac version, carried over to the Windows build of the app.

> [!IMPORTANT]
> - **This is a test build.** It has been checked against copies of vivo Office Kit 7.0.5 and 7.0.6 for Windows (China edition): the patched app archive is read by vivo's own Electron, and every script in it compiles. 7.0.6 has been used as the installed app.
> - This project was made entirely by **Claude**, an AI model made by Anthropic: the analysis, the translations, the installer and this README. No human has reviewed the code or the translations line by line.
> - It is unofficial and not affiliated with or endorsed by vivo. Use it at your own risk.

## Install

You need the China edition of vivo Office Kit already installed from vivo's own installer.

1. Download the zip from the [latest Windows release](https://github.com/JacksonJones2003/vivo-office-kit-english/releases?q=windows&expanded=true) and unzip it.
2. Double-click **Install English Patch.cmd**. If Windows shows "Windows protected your PC", click **More info** › **Run anyway**.
3. Click **Yes** when Windows asks for administrator permission. vivo Office Kit is installed in Program Files, which only administrators may change.
4. Click **Install English**, and let it quit vivo Office Kit if it is running.
5. It then offers to keep English after vivo updates (see below). Finally, click **Open vivo Office Kit**.

**One-line install:** open PowerShell, paste this line, and press Enter:

```powershell
irm https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english/main/windows/quick-install.ps1 | iex
```

## Staying English after vivo updates

vivo Office Kit updates itself, and each update puts the app back into Chinese. If you answer **Yes, Keep English** when the installer asks, it sets up a small background helper:

- A scheduled task, **vivo English Watcher**, starts the helper when you sign in to Windows. It runs with your account's highest privileges, so it can update vivo Office Kit in Program Files without asking each time. Windows asks for this permission once, during installation.
- Every 10 seconds the helper checks a few things. Each check is one file or process lookup.
  - **vivo replaced the app's files:** it waits for the update to finish and reapplies the patch.
  - **vivo Office Kit was just opened:** if the app isn't in English and the helper can't fix it on its own, it shows a popup. Tick **Don't remind me again** to stop these popups. Running the installer again turns them back on.
  - **The patched app sent a request**, for example from the **Check for updates** button.
- **vivo's updater restarts the app while it is updating.** Windows doesn't allow changing an app's files while it is running, so the helper asks to restart vivo Office Kit in English. If you choose **Later**, it reapplies the patch the next time vivo Office Kit is closed.
- **New translations arrive as a popup.** The helper checks `windows/latest.json` in this repository for a newer release of the patch at these times:
  - when you open vivo Office Kit (at most once an hour);
  - about twice a day;
  - right after vivo updates the app.

  If there is a newer release, it asks whether to install it. Only if you click **Install** does it download the release zip from this repository's Releases page, check it against the SHA-256 checksum in `latest.json`, switch to it, and re-patch the app. **Not Now** silences that version for three days.
- **Reinstalling vivo Office Kit from scratch is covered too.** The helper lives outside the app, in `%LOCALAPPDATA%\vivo-office-kit-english-watcher`, so it survives a reinstall.
- A log is kept in `%LOCALAPPDATA%\vivo-office-kit-english-watcher\vivo-office-kit-english.log`.

To turn it off, run the installer and choose **Restore Chinese**, or run `watcher\setup-watcher.ps1 remove`.

## Phone audio on PC (no mirroring)

The patch adds a small **speaker button** to your phone's card in vivo Office Kit, next to **Transfer history** and **Handoff connectivity**. It lets your phone play its sound through this PC over Bluetooth, like a speaker, without mirroring the screen.

- **Turn it on:** click the speaker button. It connects in a few seconds and turns green. Your phone's music, videos and games now play on the PC.
- **Volume:** click the green button again to open a panel with a **volume slider**. It controls only your phone's sound on the PC, not other apps, and the level is remembered for next time.
- **Turn it off:** choose **Turn off phone audio** in that panel. Quitting vivo Office Kit also turns it off. Your phone goes back to its own speaker.

Requirements and notes:
- Your phone must be paired with this PC in Windows Bluetooth settings (Windows 10 2004 or newer).
- Sound goes to Windows' current output device. If you hear nothing, pick your speakers or headset in the taskbar's sound menu.
- If your earbuds are connected to the phone, they take priority, so disconnect them first.
- The phone's own volume buttons don't change the PC volume, because Windows ignores the volume commands phones send. Use the slider. (Android's developer option **Disable absolute volume** makes the phone buttons work, but it changes how volume works for every Bluetooth device, including cars and earbuds.)
- Phone calls stay on the phone. This is media audio only.
- Don't use it at the same time as vivo's phone mirroring, which also sends phone sound to the PC.

How it works: Windows has a built-in Bluetooth audio receiver (`AudioPlaybackConnection`). The patch installs a small PowerShell helper next to vivo's files (`resources\english-patch-bt-audio.ps1`) that vivo Office Kit starts when you click the button. The helper sets the volume of the phone's audio stream through Windows' per-app volume controls.

## Checking for patch updates from inside the app

The patched app's main window has a small **English patch vX · Check for updates** button in the bottom-right corner. Click **–** to shrink it to a small **EN** badge. **Settings › Version info** has an **English patch** section. These work as in the Mac version.

When vivo Office Kit shows its own update window, the patch adds a line saying whether a full English translation exists for that version. To know this, the patched app downloads the small `windows/latest.json` file from GitHub when it starts and every 6 hours. Nothing about you or your devices is sent.

## Undo

Run the installer again and click **Restore Chinese**. This also turns off automatic re-patching and puts back vivo's original file, which the patch keeps as `app.asar.zh-backup` in `resources`. Reinstalling vivo's own package also undoes everything.

**If another English patch was installed before:** the installer notices that `app.asar` was already changed by another tool, and uses vivo's untouched copy (`app.asar.original`) instead. The other tool's version is kept as `app.asar.pre-english-patch`.

## Which versions it works on

| Your copy | Mode | What you get |
|---|---|---|
| 7.0.5 or 7.0.6 for Windows, China edition | Full | All of the above. Most of the app's 66 translated files are identical to the Mac build. For the 17 or 18 that differ, every Mac translation was carried over. |
| Any other version where the language lock can still be found | Basic | vivo's own built-in English is switched on. Chinese text written directly in the code is left alone, so some screens stay Chinese. Untested. |
| A version where the lock cannot be found | None | The installer says so and changes nothing. |

## For maintainers: how the Windows translation was made

- `patch\edits.dat` holds the Mac edit lists, plus Windows lists for the 18 files whose Windows build differs. Each list is keyed by the original file's SHA-256, so the right one is chosen automatically.
- **How the Windows lists were built:** each Mac edit was located in the Windows file by its surrounding text, using vivo's Mac build of the same version as the reference. Windows writes `\r\n` where the Mac build writes `\n` in a few template strings.
- **Checks:** all 3,567 edits were placed. No Chinese text remains on Windows that the patched Mac build does not also keep.
- **To publish:**
  1. Bump `PATCH_VERSION` in `patcher.ps1`.
  2. Zip the `windows` folder and attach it to a GitHub release tagged `windows-vX.Y.Z`. Untick **Set as the latest release**, because installed Mac apps link to the latest release.
  3. Put the asset's URL and SHA-256 into `windows/latest.json`, then push.
- **Experimental, off by default:** `patcher.ps1 install -Bridge` removes vivo's PC-side check that stops Infinite collaboration from running alongside desktop mode. `-NoBridge` turns it off again. It doesn't make typing work in desktop mode, because the phone sends Infinite collaboration keystrokes to its own screen.
- **Mac and Windows never take each other's updates.** Mac helpers read the root `latest.json` and only accept downloads from `…/vivo-office-kit-english-mac/releases/download/`. Windows helpers read `windows/latest.json` and only accept `…/releases/download/windows-v…`.
