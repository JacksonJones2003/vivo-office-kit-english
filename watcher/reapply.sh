#!/bin/bash
# Run by the background watcher whenever vivo Office Kit's files change (and at login).
# If vivo's updater has put the original Chinese archive back, re-applies the English patch.
#   reapply.sh          normal run
#   reapply.sh check    only check that macOS lets the watcher modify the app (triggers the permission prompt)
#   reapply.sh monitor  stay running; whenever vivo Office Kit is opened, do a normal run (reminder popups)
#   reapply.sh ensure-monitor   install/refresh the launch agent that runs "monitor"
# Test hooks: VOK_APP=/path/to/pcsuite.app  VOK_AUTO=1 (no dialogs)  VOK_MANIFEST_URL=... (update source)
#             VOK_CHOICE="<button>\t<0|1>" (answer for the reminder alert in test mode)  VOK_TRIGGER=launch
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
# ask_check "message" "main button" "other button" -> prints "<button>\t<1 if 'Don't remind me again' ticked>"
ask_check() {
  if [ -n "${VOK_AUTO:-}" ]; then printf '%s\n' "${VOK_CHOICE:-$2	0}"; return; fi
  local r; r="$(/usr/bin/osascript -l JavaScript - "$TITLE" "$1" "$2" "$3" "Don't remind me again" <<'JXA' 2>/dev/null
function run(argv) {
  ObjC.import('AppKit');
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(1);
  var a = $.NSAlert.alloc.init;
  a.messageText = argv[0]; a.informativeText = argv[1];
  a.addButtonWithTitle(argv[2]); a.addButtonWithTitle(argv[3]);
  a.showsSuppressionButton = true; a.suppressionButton.title = argv[4];
  a.layout; a.window.level = 3;                   // stay above the vivo windows and permission prompts
  app.activateIgnoringOtherApps(true);
  var r = a.runModal;
  return ((r == 1000) ? argv[2] : argv[3]) + '\t' + (a.suppressionButton.state == 1 ? '1' : '0');
}
JXA
)"
  case "$r" in *"	"*) printf '%s\n' "$r"; return ;; esac
  # Fallback: a plain dialog, with the checkbox turned into a third button.
  local c; c="$(ask "$1" "$2" "Don't Remind Me" "$3" "$2")"
  case "$c" in "Don't Remind Me") printf '%s\t1\n' "$3" ;; "") printf '%s\t0\n' "$3" ;; *) printf '%s\t0\n' "$c" ;; esac
}
notify() { [ -n "${VOK_AUTO:-}" ] && return; /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$TITLE" "$1" >/dev/null 2>&1; }
need_permission() {
  log "macOS blocked the change (App Management)"
  C="$(ask "macOS blocked the English patch from updating vivo Office Kit.

Open System Settings > Privacy & Security > App Management and switch on \"vivo English Watcher\". The patch will then be reapplied automatically after each vivo update." "Open Settings" "Later" "Open Settings")"
  [ "$C" = "Open Settings" ] && /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
}

# Runs the patcher; if vivo's installer left the app owned by the system (a fresh install or reinstall),
# asks once for your password instead of failing. Sets OUT and RC.
# Reminders: the popup appears every time vivo Office Kit is opened while it is not in English. "Not Now" (or a
# popup that was missed) only skips this time; background checks then stay quiet for that copy. Ticking
# "Don't remind me again" stops the popups until the installer is run again.
NOREMIND="$W/no-reminders"; SNOOZE="$W/snoozed-copy"
do_install() {
  OUT="$(/usr/bin/perl "$KIT/patcher.pl" install --app "$APP" 2>&1)"; RC=$?
  [ $RC -eq 4 ] && [ ! -w "$RES" ] || return 0
  local stamp; stamp="$(/usr/bin/stat -f '%m %z' "$RES/app.asar" 2>/dev/null)"
  if [ -f "$NOREMIND" ]; then RC=0; OUT="skipped (reminders turned off with \"Don't remind me again\")"; SKIPPED=1; return 0; fi
  if [ "${VOK_TRIGGER:-}" != "launch" ] && [ -f "$SNOOZE" ] && [ "$(cat "$SNOOZE")" = "$stamp" ]; then RC=0; OUT="skipped (Not Now; will ask again when vivo Office Kit is opened)"; SKIPPED=1; return 0; fi
  log "showing the reminder popup (vivo Office Kit is read-only and not in English)"
  local r btn sup; r="$(ask_check "vivo Office Kit is not in English. It was installed, reinstalled or updated with vivo's installer, which made it read-only for your account, so the English patch could not be applied automatically.

Apply the English patch now? macOS will ask for your Mac password." "Apply English" "Not Now")"
  btn="${r%%	*}"; sup="${r##*	}"
  if [ "$sup" = "1" ]; then : > "$NOREMIND"; log "reminders turned off (Don't remind me again)"; fi
  if [ "$btn" != "Apply English" ]; then echo "$stamp" > "$SNOOZE"; RC=0; OUT="skipped (Not Now)"; SKIPPED=1; return 0; fi
  log "app is read-only for this user; asking for an administrator password"
  if [ -n "${VOK_FAKE_ADMIN:-}" ]; then   # test hook: stands in for the password prompt
    /bin/chmod u+w "$RES"; OUT="$(/usr/bin/perl "$KIT/patcher.pl" install --app "$APP" 2>&1)"; RC=$?; rm -f "$SNOOZE"; return 0
  fi
  [ -n "${VOK_AUTO:-}" ] && return 0
  OUT="$(/usr/bin/osascript - "$KIT/patcher.pl" "$APP" <<'OSA' 2>&1
on run argv
  return do shell script "/usr/bin/perl " & quoted form of (item 1 of argv) & " install --app " & quoted form of (item 2 of argv) & " 2>&1" with administrator privileges
end run
OSA
)"; RC=$?
  case "$OUT" in *"User canceled"*|*"-128"*) RC=0; OUT="skipped (password prompt cancelled)"; SKIPPED=1 ;; esac
  [ $RC -ne 0 ] && case "$OUT" in *"not permitted"*|*"Cannot write"*|*"Could not"*) RC=4 ;; esac
  [ $RC -eq 0 ] && rm -f "$SNOOZE"
}
SKIPPED=""

# Existing helpers were set up before the watch on /Applications was added: add it (takes effect at next login).
PL="$HOME/Library/LaunchAgents/io.github.jacksonjones2003.vivo-english-watcher.plist"
if [ -f "$PL" ] && ! /usr/bin/grep -q '<string>/Applications</string>' "$PL"; then
  /usr/libexec/PlistBuddy -c "Add :WatchPaths: string /Applications" "$PL" >/dev/null 2>&1 && log "watching /Applications from next login (catches full reinstalls)"
fi

MLABEL="io.github.jacksonjones2003.vivo-english-monitor"
MPL="$HOME/Library/LaunchAgents/$MLABEL.plist"
ensure_monitor() {   # the agent that keeps "monitor" running (added in 1.6.0; older helpers add it themselves)
  [ -n "${VOK_APP:-}${VOK_AUTO:-}" ] && return 0          # never during tests
  [ -f "$PL" ] || return 0                                 # automatic re-patching is off
  local applet="$W/vivo English Watcher.app/Contents/MacOS/applet"
  [ -x "$applet" ] || return 0
  [ -f "$MPL" ] && [ "${1:-}" != "force" ] && return 0
  cat > "$MPL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$MLABEL</string>
  <key>ProgramArguments</key><array><string>$applet</string></array>
  <key>EnvironmentVariables</key><dict><key>VOK_MODE</key><string>monitor</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
</dict>
</plist>
PLIST
  /bin/launchctl bootout "gui/$(id -u)/$MLABEL" >/dev/null 2>&1
  /bin/launchctl bootstrap "gui/$(id -u)" "$MPL" >/dev/null 2>&1 && log "started the launch monitor (reminders when vivo Office Kit is opened)"
}
if [ "${1:-}" = "ensure-monitor" ]; then ensure_monitor force; exit 0; fi
if [ "${1:-}" = "monitor" ]; then
  # Cheap loop: every 10 seconds, is vivo Office Kit running? Each new launch triggers one normal run.
  log "launch monitor running"
  last=""
  while :; do
    pid=""
    for a in /Applications/pcsuite.app /Applications/pcsuite.localized/pcsuite.app; do
      p="$(/usr/bin/pgrep -f "^$a/Contents/MacOS/pcsuite( |\$)" 2>/dev/null | head -1)"; [ -n "$p" ] && { pid="$p"; break; }
    done
    if [ -n "$pid" ] && [ "$pid" != "$last" ]; then last="$pid"; VOK_TRIGGER=launch /bin/bash "$W/reapply.sh"; fi
    [ -z "$pid" ] && last=""
    sleep 10
  done
fi

# One run at a time, so two triggers can never show two popups.
LOCK="$W/.run-lock"
if ! /bin/mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(/usr/bin/find "$LOCK" -maxdepth 0 -mmin +15 2>/dev/null)" ]; then rm -rf "$LOCK"; /bin/mkdir "$LOCK" 2>/dev/null || exit 0; else exit 0; fi
fi
trap 'rm -rf "$LOCK"' EXIT
ensure_monitor

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

VER=""; [ -f "$APP/Contents/Info.plist" ] && VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"

# ---------------------------------------------------------------- new translations from GitHub
# Looks for a newer release of this patch and, only if you click Install, downloads and switches to it.
REPO_URL="https://github.com/JacksonJones2003/vivo-office-kit-english-mac"
MANIFEST_URL="${VOK_MANIFEST_URL:-https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english-mac/main/latest.json}"
STAMP="$W/last-update-check"; DECLINED="$W/declined-version"
REQ="$W/launch-request"   # written by the patched app when it starts
maybe_update() {
  local force="$1" now; now=$(date +%s)
  # Check at most every 12 hours, or every hour when you open vivo Office Kit, unless vivo just changed
  # or this version is not fully supported.
  local limit=43200; [ -f "$REQ" ] && { limit=3600; rm -f "$REQ"; }; [ "${VOK_TRIGGER:-}" = "launch" ] && limit=3600
  if [ "$force" != 1 ] && [ -f "$STAMP" ] && [ $((now - $(cat "$STAMP" 2>/dev/null || echo 0))) -lt "$limit" ]; then return; fi
  echo "$now" > "$STAMP"
  local mf; mf="$(/usr/bin/curl -fsSL --max-time 20 "$MANIFEST_URL" 2>/dev/null)" || { log "update check: could not reach GitHub"; return; }
  local info; info="$(printf '%s' "$mf" | /usr/bin/perl -MJSON::PP -e '
    my $m = eval { decode_json(join("", <STDIN>)) } or exit 1;
    print join("\t", map { $_ // "" } $m->{version}, $m->{zip_url}, $m->{zip_sha256}, join(", ", @{ $m->{full_versions} || [] })), "\n";')" || { log "update check: unreadable manifest"; return; }
  local nv url sha sup; IFS=$'\t' read -r nv url sha sup <<< "$info"
  local cv; cv="$(/usr/bin/perl "$KIT/patcher.pl" version 2>/dev/null)"
  local newer; newer="$(/usr/bin/perl -e 'my @a=split /\./,$ARGV[0]; my @b=split /\./,$ARGV[1]; for (0..2) { my $d=($a[$_]//0)<=>($b[$_]//0); if ($d) { print $d>0 ? 1 : 0; exit } } print 0' "$nv" "$cv")"
  [ "$newer" = 1 ] || { log "update check: patch $cv is current"; return; }
  case "$url" in "$REPO_URL"/releases/download/*) ;; *) log "update check: refusing unexpected download address"; return ;; esac
  [ ${#sha} -eq 64 ] || { log "update check: manifest has no checksum"; return; }
  # Do not nag: after "Not Now", ask again only after 3 days or when vivo's version changes.
  if [ "$force" != 1 ] && [ -f "$DECLINED" ] && [ "$(sed -n 1p "$DECLINED")" = "$nv" ] && [ $((now - $(sed -n 2p "$DECLINED"))) -lt 259200 ]; then return; fi
  local extra=""; [ -n "$sup" ] && extra="

It has the full translation for vivo Office Kit $sup."
  [ -n "$VER" ] && case ", $sup, " in *", $VER, "*) extra="$extra Your version, $VER, is included." ;; esac
  local c; c="$(ask "A new English translation for vivo Office Kit is available (patch $nv; you have $cv).$extra

Download and install it now? It is downloaded from the project's GitHub page and checked before use." "Install" "Not Now" "Install")"
  if [ "$c" != "Install" ]; then printf '%s\n%s\n' "$nv" "$now" > "$DECLINED"; log "update $nv declined"; return; fi
  local tmp; tmp="$(mktemp -d)"
  if ! /usr/bin/curl -fsSL --max-time 300 -o "$tmp/p.zip" "$url"; then log "update: download failed"; notify "Downloading the new English translation failed. It will be offered again later."; rm -rf "$tmp"; return; fi
  if [ "$(/usr/bin/shasum -a 256 "$tmp/p.zip" | cut -d' ' -f1)" != "$sha" ]; then log "update: checksum mismatch"; notify "The downloaded translation did not pass its check and was not used."; rm -rf "$tmp"; return; fi
  /usr/bin/ditto -x -k "$tmp/p.zip" "$tmp/x" 2>/dev/null
  local d; d="$(ls -d "$tmp"/x/*/ 2>/dev/null | head -1)"
  if [ -z "$d" ] || [ ! -f "$d/patcher.pl" ] || [ ! -f "$d/patch/edits.dat" ] || ! /usr/bin/perl -c "$d/patcher.pl" >/dev/null 2>&1; then log "update: package incomplete"; rm -rf "$tmp"; return; fi
  rm -rf "$W/kit.new"; mkdir -p "$W/kit.new"; cp -R "$d/patcher.pl" "$d/patch" "$W/kit.new/" && rm -rf "$W/kit" && mv "$W/kit.new" "$W/kit"
  [ -f "$d/watcher/reapply.sh" ] && cp "$d/watcher/reapply.sh" "$W/reapply.sh.new" && chmod +x "$W/reapply.sh.new" && mv "$W/reapply.sh.new" "$W/reapply.sh"
  rm -rf "$tmp" "$DECLINED"
  log "updated the patch to $nv"
  UPDATED="$nv"
}

UPDATED=""
STATUS="$(/usr/bin/perl "$KIT/patcher.pl" status --app "$APP" 2>&1)"
STATE="$(printf '%s\n' "$STATUS" | sed -n 1p)"; MODE="$(printf '%s\n' "$STATUS" | sed -n 3p)"
INST_MODE="$(sed -n 's/^mode=//p' "$RES/app.asar.english-patch" 2>/dev/null)"   # mode the app is actually patched in
FORCE=0; [ "$STATE" = "original" ] && FORCE=1; [ "$MODE" != "full" ] && FORCE=1; [ "$INST_MODE" = "basic" ] && FORCE=1
maybe_update "$FORCE"
# Patched in basic mode earlier, but full English is now possible (new translation just downloaded, or already here): upgrade.
if [ -z "$UPDATED" ] && [ "$STATE" = "patched" ] && [ "$INST_MODE" = "basic" ] && [ "$MODE" = "full" ]; then
  UPDATED="$(/usr/bin/perl "$KIT/patcher.pl" version 2>/dev/null)"; log "app was in basic mode; full translation available, upgrading"
fi
if [ -n "$UPDATED" ]; then
  if [ "$STATE" = "patched" ]; then
    # Already English: rebuild it with the new translation (the patcher rebuilds from its backup of the original).
    do_install; log "reinstall with $UPDATED rc=$RC: $OUT"
    [ $RC -eq 4 ] && { need_permission; exit 4; }
    [ -n "$SKIPPED" ] && exit 0
    STATE="reinstalled"
  fi
  STATUS="$(/usr/bin/perl "$KIT/patcher.pl" status --app "$APP" 2>&1)"
  [ "$STATE" = "reinstalled" ] || STATE="$(printf '%s\n' "$STATUS" | sed -n 1p)"
  MODE="$(printf '%s\n' "$STATUS" | sed -n 3p)"
fi
if [ "$STATE" = "reinstalled" ]; then
  if /usr/bin/pgrep -f "$APP/Contents/MacOS/pcsuite" >/dev/null 2>&1; then
    C="$(ask "The new English translation ($UPDATED) has been installed.

Restart vivo Office Kit now to use it?" "Restart Now" "Later" "Restart Now")"
    if [ "$C" = "Restart Now" ]; then
      /usr/bin/osascript -e 'tell application id "com.vivo.pcsuite" to quit' >/dev/null 2>&1
      for _ in $(seq 1 20); do /usr/bin/pgrep -f "$APP/Contents/MacOS/pcsuite" >/dev/null 2>&1 || break; sleep 1; done
      /usr/bin/open "$APP"
    fi
  else
    notify "The new English translation ($UPDATED) has been installed."
  fi
  exit 0
fi
if [ "$STATE" != "original" ]; then log "version ${VER:-?}: state=$STATE, nothing to do"; exit 0; fi
if [ "$MODE" = "none" ]; then
  log "version ${VER:-?}: the patch does not support this version"
  notify "vivo Office Kit $VER can't be patched by this version of the English patch. Run the installer again to check for an update."
  exit 0
fi

do_install
log "version ${VER:-?}: install rc=$RC: $OUT"
if [ $RC -eq 4 ]; then need_permission; exit 4; fi
[ -n "$SKIPPED" ] && exit 0
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
  notify "vivo Office Kit $VER: the English patch has been (re)applied."
fi
exit 0
