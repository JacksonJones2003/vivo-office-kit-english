# vivo Office Kit for Mac — English patch

Turns the China edition of **vivo Office Kit** (`pcsuite`) for Mac into English: the main app, its menus,
and the phone mirroring and PC mode windows.

> [!IMPORTANT]
> - **This project was made entirely by Claude, an AI model made by Anthropic** — the analysis, the
>   translations, the installer and this README. No human has reviewed the code or the translations line by line.
> - **It is only known to work with version 7.0.5 for Apple silicon, China edition**
>   (`pcsuite_setup_v7.0.5-arm64-cn`). **It is not confirmed to work on any future release.** The installer
>   checks the exact build and refuses to touch anything else, and an app update will put the app back into Chinese.
> - It is unofficial and not affiliated with or endorsed by vivo. Use it at your own risk.

## Install

You need vivo Office Kit 7.0.5 already installed from vivo's own installer.

**Easiest:** open the Terminal app, paste this line and press Return:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english-mac/main/quick-install.sh)"
```

A window appears. Click **Install English**, let it quit vivo Office Kit, enter your Mac password if asked,
then click **Open vivo Office Kit**.

**Or download the zip:** get the zip from the [latest release](https://github.com/JacksonJones2003/vivo-office-kit-english-mac/releases/latest),
unzip it, then right-click **Install English Patch.command** and choose **Open**. (macOS blocks a plain
double-click on files downloaded from the internet; if it still refuses, allow it under
System Settings > Privacy & Security > Open Anyway.)

### If macOS says the change was blocked

macOS protects installed apps from being modified. Open **System Settings > Privacy & Security > App Management**,
switch on **Terminal**, and run the installer again. The installer offers to open that page for you.

## Undo

Run the installer again and click **Restore Chinese**. This puts back vivo's original file, which the
patch keeps inside the app as `app.asar.zh-backup`. Reinstalling vivo's own package also undoes everything.

## What it does

The patch changes one file, `Contents/Resources/app.asar` (the app's JavaScript and text). It does not touch
vivo's programs, background services or system extensions, and it needs nothing beyond what ships with macOS.

- Unlocks vivo's own built-in English translation, which the China edition forces off even on an English Mac.
- Adds English for about 200 strings vivo never translated.
- Replaces several thousand Chinese strings written directly in the code (recorder, AI features, calendar,
  backup, connection guides, menus).
- Makes the phone mirroring and PC mode windows English. Those helper programs only load English when a
  shared setting (`isExport`) is on as they start, so the app turns it on for about 12 seconds each time it
  opens one of them and then turns it off again.

This repository contains **no vivo code**. `patch/edits.dat` is a list of positions and replacement text that
is applied to your own installed copy; every file is checked against a SHA-256 checksum before and after.

## Known limits

- Tested lightly, on one Mac, by one person. The main window and the mirroring window were seen in English;
  most screens have not been clicked through. If something breaks, restore and open an issue.
- Left in Chinese on purpose: lunar-calendar terms, names of Chinese third-party apps, AI prompt templates sent
  to vivo's servers, some one-character sentence fragments, words the app compares against data from the phone
  (for example the album names 相机 and 视频), and anything the phone or vivo's servers send in Chinese.
- Some sentences assembled from fragments read stiffly.
- For about 12 seconds after a mirroring or PC mode window opens, the app reports itself as the international
  edition. Pairing a new device in that moment might fail once; retry.
- Changing `app.asar` breaks the app bundle's code-signature seal (vivo's programs keep their own valid
  signatures). macOS may ask about this.
- Works only with a phone the China edition already works with. It does not make the app work with phones it
  did not support before.

## Files

| File | Purpose |
| --- | --- |
| `quick-install.sh` | Downloads this repository and starts the installer. |
| `Install English Patch.command` | Double-clickable launcher for the installer. |
| `install.sh` | The installer dialogs (install, reinstall, restore). |
| `patcher.pl` | Does the work: `perl patcher.pl status`, `install` or `restore`. |
| `patch/edits.dat` | The edit list for build 7.0.5 arm64 China edition. |

## License

MIT for the scripts and translations in this repository. vivo Office Kit itself belongs to vivo.
