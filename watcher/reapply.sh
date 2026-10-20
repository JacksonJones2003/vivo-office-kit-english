#!/bin/bash
# Run by the background watcher whenever vivo Office Kit's files change (and at login).
# If vivo's updater has put the original Chinese archive back, re-applies the English patch.
#   reapply.sh          normal run
#   reapply.sh check    only check that macOS lets the watcher modify the app (triggers the permission prompt)
# Test hooks: VOK_APP=/path/to/pcsuite.app  VOK_AUTO=1 (no dialogs)  VOK_MANIFEST_URL=... (update source)
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
  local limit=43200; [ -f "$REQ" ] && { limit=3600; rm -f "$REQ"; }
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
    OUT="$(/usr/bin/perl "$KIT/patcher.pl" install --app "$APP" 2>&1)"; RC=$?; log "reinstall with $UPDATED rc=$RC: $OUT"
    [ $RC -eq 4 ] && { need_permission; exit 4; }
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
