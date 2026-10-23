#!/bin/bash
# Phone audio on this Mac over Wi-Fi: plays the phone's sound through the Mac without mirroring the screen.
# Uses scrcpy by Genymobile (https://github.com/Genymobile/scrcpy, Apache License 2.0) in audio-only mode with
# lossless FLAC. scrcpy is not bundled: the official release is downloaded once and checked before use.
# Started by the patched vivo Office Kit; reports one JSON object per line on stdout and reads "quit" on stdin.
#   VOK_PHONE_IP=<ip>      the phone's address (else found in vivo Office Kit's relay log, VOK_RELAY_LOG)
#   VOK_AUDIO_DUP=1        keep playing on the phone too        VOK_BT_PARENT=<pid>  stop when that process is gone
# States: downloading, connecting, connected, closed, error.
set -u
VER=v5.0.1
case "$(uname -m)" in
  arm64)  ARCH=aarch64; SHA=33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b ;;
  x86_64) ARCH=x86_64;  SHA=31a5467a9e907f162b093267cbbab1276b15c6e709c2ea8159566a8d165beb50 ;;
  *) printf '{"state":"error","error":"This Mac is not supported for Wi-Fi audio."}\n'; exit 1 ;;
esac
export ANDROID_ADB_SERVER_PORT=5137   # our own adb server, so vivo Office Kit's adb is never disturbed
W="$HOME/Library/Application Support/vivo-office-kit-english-watcher/scrcpy"
D="$W/scrcpy-macos-$ARCH-$VER"
ADB="$D/adb"; SCRCPY="$D/scrcpy"; export ADB
say() { printf '%s\n' "$1"; }
fail() { local m="${1//\\/\\\\}"; m="${m//\"/\\\"}"; say "{\"state\":\"error\",\"error\":\"$m\"}"; exit 1; }
# run with a time limit (macOS has no `timeout`)
run() { local t="$1"; shift; "$@" > "$TMPO" 2>&1 & local p=$!; local i=0
  while kill -0 "$p" 2>/dev/null; do sleep 0.25; i=$((i+1)); [ $i -ge $((t*4)) ] && { kill "$p" 2>/dev/null; break; }; done; wait "$p" 2>/dev/null; cat "$TMPO"; }
TMPO="$(mktemp)"; SC_LOG="$(mktemp)"; PID_SC=""
cleanup() { [ -n "$PID_SC" ] && kill "$PID_SC" 2>/dev/null; rm -f "$TMPO" "$SC_LOG"; }
trap cleanup EXIT

if [ ! -x "$SCRCPY" ] || [ ! -x "$ADB" ]; then
  say '{"state":"downloading"}'
  T="$(mktemp -d)"
  curl -fsSL --max-time 300 -o "$T/s.tgz" "https://github.com/Genymobile/scrcpy/releases/download/$VER/scrcpy-macos-$ARCH-$VER.tar.gz" \
    || { rm -rf "$T"; fail "Could not download the Wi-Fi audio component (scrcpy). Check the internet connection and try again."; }
  [ "$(/usr/bin/shasum -a 256 "$T/s.tgz" | cut -d' ' -f1)" = "$SHA" ] || { rm -rf "$T"; fail "The downloaded Wi-Fi audio component did not pass its check and was not used."; }
  mkdir -p "$W" && tar -xzf "$T/s.tgz" -C "$W"; rm -rf "$T"
  /usr/bin/xattr -dr com.apple.quarantine "$D" 2>/dev/null
  [ -x "$SCRCPY" ] || fail "The Wi-Fi audio component could not be installed."
fi
say '{"state":"connecting"}'

IP="${VOK_PHONE_IP:-}"
if [ -z "$IP" ] && [ -n "${VOK_RELAY_LOG:-}" ]; then
  for f in "$VOK_RELAY_LOG" "$VOK_RELAY_LOG.1"; do
    [ -z "$IP" ] && [ -f "$f" ] && IP="$(tail -c 400000 "$f" | grep -Eo 'mobileDeviceIp[^0-9]{1,6}[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}' | tail -1 | grep -Eo '[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}$')"
  done
fi
[ -n "$IP" ] || fail "Couldn't find your phone on the network. Connect it in vivo Office Kit first, then try again."
SERIAL="$IP:5555"
OUT="$(run 15 "$ADB" connect "$SERIAL")"; DEV="$(run 8 "$ADB" devices)"
if printf '%s\n' "$DEV" | grep -Eq "^$SERIAL[[:space:]]+offline"; then
  # A stale link (the phone dropped it): reconnect.
  run 8 "$ADB" disconnect "$SERIAL" >/dev/null; sleep 1; OUT="$(run 15 "$ADB" connect "$SERIAL")"; DEV="$(run 8 "$ADB" devices)"
fi
if ! printf '%s\n' "$DEV" | grep -Eq "^$SERIAL[[:space:]]+device"; then
  # Not listening on Wi-Fi (for example after the phone restarted). If it is plugged in by USB, switch its debugging
  # to Wi-Fi (port 5555) and try again.
  USB="$(printf '%s\n' "$DEV" | awk '$2=="device" && $1 !~ /:[0-9]+$/ {print $1; exit}')"
  if [ -n "$USB" ]; then run 10 "$ADB" -s "$USB" tcpip 5555 >/dev/null; sleep 3; OUT="$(run 15 "$ADB" connect "$SERIAL")"; DEV="$(run 8 "$ADB" devices)"; fi
fi
if printf '%s\n' "$DEV" | grep -Eq "^$SERIAL[[:space:]]+unauthorized" || printf '%s' "$OUT" | grep -q 'failed to authenticate'; then
  fail "Your phone is asking to allow debugging from this computer. Tap Allow (and Always allow), then try again."
fi
printf '%s\n' "$DEV" | grep -Eq "^$SERIAL[[:space:]]+device" \
  || fail "Your phone isn't accepting Wi-Fi audio from this Mac right now. Connect it to this Mac with a USB cable once, then try again."

ARGS=(-s "$SERIAL" --no-window --audio-codec=flac --audio-buffer=200 --no-clipboard-autosync)
[ "${VOK_AUDIO_DUP:-}" = "1" ] && ARGS+=(--audio-dup)
"$SCRCPY" "${ARGS[@]}" > "$SC_LOG" 2>&1 &
PID_SC=$!
for _ in $(seq 1 24); do kill -0 "$PID_SC" 2>/dev/null || break; sleep 0.25; done
if ! kill -0 "$PID_SC" 2>/dev/null; then
  PID_SC=""; fail "Wi-Fi audio stopped right away. $(grep ERROR "$SC_LOG" | tail -1)"
fi
say '{"state":"connected"}'

while true; do
  read -r -t 1 line; rc=$?
  if [ $rc -eq 0 ]; then [ "$line" = "quit" ] && break
  elif [ $rc -le 128 ]; then sleep 1; fi   # input closed: just wait (a timeout returns > 128)
  [ -n "${VOK_BT_PARENT:-}" ] && ! kill -0 "$VOK_BT_PARENT" 2>/dev/null && break
  if ! kill -0 "$PID_SC" 2>/dev/null; then PID_SC=""; say '{"state":"closed"}'; break; fi
done
exit 0
