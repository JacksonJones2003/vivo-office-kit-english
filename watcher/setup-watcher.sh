#!/bin/bash
# Turns the automatic re-patching on or off.
#   setup-watcher.sh install   copy the patch to a fixed place, create the watcher and start it
#   setup-watcher.sh remove    stop and delete the watcher
#   setup-watcher.sh status    print "on" or "off"
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
W="$HOME/Library/Application Support/vivo-office-kit-english-watcher"
APPLET="$W/vivo English Watcher.app"
LABEL="io.github.jacksonjones2003.vivo-english-watcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
status)
  if /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then echo on; else echo off; fi ;;
remove)
  /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
  rm -f "$PLIST"
  rm -rf "$W"
  echo "Automatic re-patching is off." ;;
install)
  mkdir -p "$W/kit" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  # Fresh copy of the patch itself (kept separate from the helper app so updating it does not reset macOS permissions).
  rm -rf "$W/kit.new"; mkdir -p "$W/kit.new"
  cp -R "$SRC/patcher.pl" "$SRC/patch" "$W/kit.new/" || { echo "Could not copy the patch files." >&2; exit 1; }
  rm -rf "$W/kit"; mv "$W/kit.new" "$W/kit"
  cp "$SRC/watcher/reapply.sh" "$W/reapply.sh"; chmod +x "$W/reapply.sh"
  # The helper app is created once and then left alone, so the App Management permission you give it sticks.
  if [ ! -d "$APPLET" ]; then
    /usr/bin/osacompile -o "$APPLET" \
      -e 'on run' \
      -e '  set w to POSIX path of (path to home folder) & "Library/Application Support/vivo-office-kit-english-watcher/"' \
      -e '  set m to system attribute "VOK_MODE"' \
      -e '  do shell script "/bin/bash " & quoted form of (w & "reapply.sh") & " " & quoted form of m & " >> \"$HOME/Library/Logs/vivo-office-kit-english.log\" 2>&1"' \
      -e 'end run' || { echo "Could not create the watcher app." >&2; exit 1; }
    /usr/bin/plutil -replace LSUIElement -bool true "$APPLET/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleIdentifier -string "$LABEL" "$APPLET/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleName -string "vivo English Watcher" "$APPLET/Contents/Info.plist"
    /usr/bin/codesign --force --sign - "$APPLET" >/dev/null 2>&1
  fi
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APPLET/Contents/MacOS/applet</string></array>
  <key>WatchPaths</key>
  <array>
    <string>/Applications/pcsuite.app/Contents</string>
    <string>/Applications/pcsuite.app/Contents/Resources</string>
    <string>/Applications/pcsuite.localized/pcsuite.app/Contents/Resources</string>
    <string>/Applications</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>21600</integer>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PL
  /usr/bin/plutil -lint "$PLIST" >/dev/null || { echo "Invalid watcher settings file." >&2; exit 1; }
  [ -n "${VOK_NO_LAUNCHD:-}" ] && { echo "(test) watcher files created, not started"; exit 0; }
  /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
  /bin/launchctl bootstrap "$DOMAIN" "$PLIST" || { echo "Could not start the watcher." >&2; exit 1; }
  # Ask macOS for the App Management permission now, while you are here, rather than during a future update.
  VOK_MODE=check "$APPLET/Contents/MacOS/applet" >/dev/null 2>&1
  echo "Automatic re-patching is on." ;;
*)
  echo "usage: $0 install|remove|status" >&2; exit 1 ;;
esac
