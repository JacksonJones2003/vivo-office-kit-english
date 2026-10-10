#!/bin/bash
# Point-and-click installer for the vivo Office Kit English patch (macOS).
# Shows dialogs, asks for an administrator password only if needed, and can undo the patch.
# Usage: ./install.sh [/path/to/pcsuite.app]
#   VOK_AUTO=install|restore  run without dialogs (used for testing)
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHER="$DIR/patcher.pl"
TITLE="vivo Office Kit English Patch"
APP_ARG=()
[ -n "${1:-}" ] && APP_ARG=(--app "$1")
AUTO="${VOK_AUTO:-}"

# ask "message" "default button" "button" ["button" ...]  -> prints the clicked button, or nothing if cancelled
ask() {
  /usr/bin/osascript - "$TITLE" "$@" <<'OSA' 2>/dev/null
on run argv
  set theTitle to item 1 of argv
  set theMsg to item 2 of argv
  set theDefault to item 3 of argv
  set theButtons to items 4 thru -1 of argv
  try
    set r to display dialog theMsg with title theTitle buttons theButtons default button theDefault
    return button returned of r
  on error
    return ""
  end try
end run
OSA
}
say_msg() { if [ -n "$AUTO" ]; then echo "$1"; else ask "$1" "OK" "OK" >/dev/null; fi; }

STATUS="$(/usr/bin/perl "$PATCHER" status ${APP_ARG[@]+"${APP_ARG[@]}"} 2>&1)"; RC=$?
if [ $RC -ne 0 ]; then say_msg "$STATUS"; exit $RC; fi
STATE="$(printf '%s\n' "$STATUS" | sed -n 1p)"
APP="$(printf '%s\n' "$STATUS" | sed -n 2p)"
MODE="$(printf '%s\n' "$STATUS" | sed -n 3p)"
VER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
NOTE=""
[ "$MODE" = "basic" ] && NOTE="

Note: this is version $VER, not the 7.0.5 build the patch was made for. It will be installed in basic mode, which switches the app to vivo's own built-in English. It has not been tested on this version and some screens may stay in Chinese."

if [ -n "$AUTO" ]; then
  ACTION="$AUTO"
else
  case "$STATE" in
    original) CHOICE="$(ask "vivo Office Kit $VER was found and is currently in Chinese.

Install the English patch? The original is kept as a backup and can be restored at any time by running this again.$NOTE" "Install English" "Cancel" "Install English")" ;;
    patched)  CHOICE="$(ask "The English patch is already installed.

You can reinstall it (for example after updating this patch) or restore the original Chinese version.$NOTE" "Reinstall English" "Cancel" "Restore Chinese" "Reinstall English")" ;;
    *)        CHOICE="$(ask "This copy of vivo Office Kit (version $VER) is too different from the one this patch was made for: $(printf '%s\n' "$STATUS" | sed -n 4p).

Nothing will be changed." "OK" "OK")"; exit 3 ;;
  esac
  case "$CHOICE" in
    "Install English"|"Reinstall English") ACTION=install ;;
    "Restore Chinese") ACTION=restore ;;
    *) exit 0 ;;
  esac
fi

running() { /usr/bin/pgrep -f "$APP/Contents/MacOS/pcsuite" >/dev/null 2>&1; }
if running && [ -z "$AUTO" ]; then
  CHOICE="$(ask "vivo Office Kit is running and needs to quit first." "Quit and Continue" "Cancel" "Quit and Continue")"
  [ "$CHOICE" = "Quit and Continue" ] || exit 0
  /usr/bin/osascript -e 'tell application id "com.vivo.pcsuite" to quit' >/dev/null 2>&1
  for _ in $(seq 1 20); do running || break; sleep 1; done
  if running; then say_msg "vivo Office Kit is still running. Quit it from its menu bar icon, then run this installer again."; exit 1; fi
fi

OUT="$(/usr/bin/perl "$PATCHER" "$ACTION" --app "$APP" 2>&1)"; RC=$?
if [ $RC -eq 4 ] && [ -z "$AUTO" ]; then
  # Not writable as this user: retry with an administrator password (standard macOS prompt).
  OUT="$(/usr/bin/osascript - "$PATCHER" "$ACTION" "$APP" <<'OSA' 2>&1
on run argv
  set cmd to "/usr/bin/perl " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv) & " --app " & quoted form of (item 3 of argv) & " 2>&1"
  return do shell script cmd with administrator privileges
end run
OSA
)"; RC=$?
  if [ $RC -ne 0 ]; then
    case "$OUT" in
      *"User canceled"*|*"-128"*) exit 0 ;;
      *"not permitted"*|*"Permission denied"*|*"Cannot write"*|*"Could not"*)
        CHOICE="$(ask "macOS blocked the change because it protects installed apps.

Open System Settings > Privacy & Security > App Management, switch on the app you launched this installer from (usually Terminal), then run the installer again." "Open Settings" "Cancel" "Open Settings")"
        [ "$CHOICE" = "Open Settings" ] && /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
        exit 4 ;;
    esac
  fi
fi

if [ $RC -ne 0 ]; then say_msg "The patch could not be applied:

$OUT"; exit $RC; fi

if [ -n "$AUTO" ]; then echo "$OUT"; exit 0; fi
CHOICE="$(ask "$OUT

Open vivo Office Kit now?" "Open vivo Office Kit" "Done" "Open vivo Office Kit")"
[ "$CHOICE" = "Open vivo Office Kit" ] && /usr/bin/open "$APP"
exit 0
