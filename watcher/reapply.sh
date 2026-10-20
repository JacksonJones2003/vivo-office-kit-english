#!/bin/bash
# Run by the background watcher whenever vivo Office Kit's files change (and at login).
# If vivo's updater has put the original Chinese archive back, re-applies the English patch.
#   reapply.sh          normal run
#   reapply.sh check    only check that macOS lets the watcher modify the app (triggers the permission prompt)
# Test hooks: VOK_APP=/path/to/pcsuite.app  VOK_AUTO=1 (no dialogs)
set -u
W="$HOME/Library/Application Support/vivo-office-kit-english-watcher"
KIT="$W/kit"
TITLE="vivo Office Kit English Patch"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
ask() {   # ask "message" "default" buttons...  -> clicked button
  [ -n "${VOK_AUTO:-}" ] && { echo "$2"; return; }
  /usr/bin/osascript - "$TITLE" "$@" <<'OSA' 2>/dev/null
on run argv
  try
    return button returned of (display dialog (item 2 of argv) with title (item 1 of argv) buttons (items 4 thru -1 of argv) default button (item 3 of argv) giving up after 600)
  on error
    return ""
  end try
end run
OSA
}
notify() { [ -n "${VOK_AUTO:-}" ] && return; /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$TITLE" "$1" >/dev/null 2>&1; }
need_permission() {
  log "macOS blocked the change (App Management)"
  C="$(ask "macOS blocked the English patch from updating vivo Office Kit.

Open System Settings > Privacy & Security > App Management and switch on \"vivo English Watcher\". The patch will then be reapplied automatically after each vivo update." "Open Settings" "Later" "Open Settings")"
  [ "$C" = "Open Settings" ] && /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
}

APP="${VOK_APP:-}"
if [ -z "$APP" ]; then for a in /Applications/pcsuite.app /Applications/pcsuite.localized/pcsuite.app; do [ -d "$a/Contents/Resources" ] && { APP="$a"; break; }; done; fi
[ -n "$APP" ] && [ -f "$APP/Contents/Resources/app.asar" ] || { log "vivo Office Kit not installed; nothing to do"; exit 0; }
RES="$APP/Contents/Resources"

if [ "${1:-}" = "check" ]; then
  # Write inside the app bundle once, so macOS asks for (or confirms) App Management permission now.
  if /usr/bin/touch "$RES/app.asar.english-patch" 2>/dev/null; then log "permission check ok"; else need_permission; fi
  exit 0
fi

# vivo's updater may still be writing: wait until the archive has stopped changing (up to 2 minutes).
prev=""
for _ in $(seq 1 24); do
  cur="$(/usr/bin/stat -f '%m %z' "$RES/app.asar" 2>/dev/null)"
  [ -n "$cur" ] && [ "$cur" = "$prev" ] && break
  prev="$cur"; sleep 5
done

STATUS="$(/usr/bin/perl "$KIT/patcher.pl" status --app "$APP" 2>&1)"
STATE="$(printf '%s\n' "$STATUS" | sed -n 1p)"; MODE="$(printf '%s\n' "$STATUS" | sed -n 3p)"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
if [ "$STATE" != "original" ]; then log "version ${VER:-?}: state=$STATE, nothing to do"; exit 0; fi
if [ "$MODE" = "none" ]; then
  log "version ${VER:-?}: the patch does not support this version"
  notify "vivo Office Kit $VER can't be patched by this version of the English patch. Run the installer again to check for an update."
  exit 0
fi

OUT="$(/usr/bin/perl "$KIT/patcher.pl" install --app "$APP" 2>&1)"; RC=$?
log "version ${VER:-?}: install rc=$RC: $OUT"
if [ $RC -eq 4 ]; then need_permission; exit 4; fi
if [ $RC -ne 0 ]; then notify "Reapplying the English patch failed: $OUT"; exit $RC; fi

EXTRA=""
[ "$MODE" = "basic" ] && EXTRA="

This version ($VER) is newer than the patch's full translation, so basic mode was used and some screens may be in Chinese. Run the installer again later to check for full support."
if /usr/bin/pgrep -f "$APP/Contents/MacOS/pcsuite" >/dev/null 2>&1; then
  C="$(ask "vivo Office Kit was updated to $VER and the English patch has been reapplied.$EXTRA

Restart vivo Office Kit now to see English?" "Restart Now" "Later" "Restart Now")"
  if [ "$C" = "Restart Now" ]; then
    /usr/bin/osascript -e 'tell application id "com.vivo.pcsuite" to quit' >/dev/null 2>&1
    for _ in $(seq 1 20); do /usr/bin/pgrep -f "$APP/Contents/MacOS/pcsuite" >/dev/null 2>&1 || break; sleep 1; done
    /usr/bin/open "$APP"
  fi
else
  notify "vivo Office Kit was updated to $VER and the English patch has been reapplied."
fi
exit 0
