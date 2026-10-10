# vivo Office Kit for Mac — English patch

Turns the China edition of **vivo Office Kit** (`pcsuite`) for Mac into English: the main app, its menus,
and the phone mirroring and PC mode windows.

> [!IMPORTANT]
> - **This project was made entirely by Claude, an AI model made by Anthropic** — the analysis, the
>   translations, the installer and this README. No human has reviewed the code or the translations line by line.
> - **It has only been tested with version 7.0.5 for Apple silicon, China edition**
>   (`pcsuite_setup_v7.0.5-arm64-cn`). **It is not confirmed to work on any other or future release.** On other
>   versions the installer falls back to an untested basic mode (see below), and an app update will put the app
>   back into Chinese until you run the installer again.
> - It is unofficial and not affiliated with or endorsed by vivo. Use it at your own risk.

## Install

You need the China edition of vivo Office Kit already installed from vivo's own installer.

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

## Which versions it works on

The installer looks at each file inside your copy of the app and picks a mode by itself:

| Your copy | Mode | What you get |
| --- | --- | --- |
| 7.0.5 (the files match the ones the patch was built from) | **Full** | Everything listed under "What it does". This is the only tested case. |
| Any other version where the language lock can still be found | **Basic** | vivo's own built-in English is switched on, plus the sign-in and mirroring fixes where their code is found. Chinese text written directly in the code is left alone, so some screens stay Chinese. **Untested.** |
| A version where the lock cannot be found | None | The installer says so and changes nothing. |

The 7.0.5 Intel build has not been tested either; if its files are identical to the Apple silicon ones it gets
full mode, otherwise basic mode. The installer tells you which mode it will use before you confirm.

After vivo Office Kit updates itself, just run the installer again.

## What it does

The patch changes one file, `Contents/Resources/app.asar` (the app's JavaScript and text). It does not touch
vivo's programs, background services or system extensions, and it needs nothing beyond what ships with macOS.

- Unlocks vivo's own built-in English translation, which the China edition forces off even on an English Mac.
- Adds English for about 200 strings vivo never translated.
- Replaces several thousand Chinese strings written directly in the code (recorder, AI features, calendar,
  backup, connection guides, menus). Full mode only.
- Makes the vivo account sign-in window English by asking vivo's sign-in page for English, and shows a
  built-in English slide next to it instead of the Chinese slideshow sent by vivo's servers.
- Makes the phone mirroring and PC mode windows English. Those helper programs only load English when a
  shared setting (`isExport`) is on as they start, so the app turns it on for about 12 seconds each time it
  opens one of them and then turns it off again.

This repository contains **no vivo code**. `patch/edits.dat` is a list of positions and replacement text that
is applied to your own installed copy; in full mode every file is checked against a SHA-256 checksum before and
after. In both modes the rebuilt archive is read back and verified before it replaces the original.

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
- Basic mode has never been run on a real copy of another version. It was only exercised by forcing it on 7.0.5,
  where it produced valid code.
- Works only with a phone the China edition already works with. It does not make the app work with phones it
  did not support before.

## Files

| File | Purpose |
| --- | --- |
| `quick-install.sh` | Downloads this repository and starts the installer. |
| `Install English Patch.command` | Double-clickable launcher for the installer. |
| `install.sh` | The installer dialogs (install, reinstall, restore). |
| `patcher.pl` | Does the work: `perl patcher.pl status`, `install` or `restore`. |
| `patch/edits.dat` | The exact edit list for 7.0.5 (full mode). |
| `patch/main_prefix.js` | Small startup script added to the app for the mirroring and sign-in language fixes. |
| `patch/locale_extra.tsv` | English for the strings vivo never translated (used in basic mode). |

## License

MIT for the scripts and translations in this repository. vivo Office Kit itself belongs to vivo.
