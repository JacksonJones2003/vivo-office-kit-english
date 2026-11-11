#!/bin/bash
# Install the in-app iCloud Photos service (pyicloud + local UI).
#   ./setup.sh
# Requires Python 3 (macOS 12+ ships python3 with the Command Line Tools).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/vivo-office-kit-icloud-photos"
PY="${VOK_PYTHON:-python3}"

if ! command -v "$PY" >/dev/null 2>&1; then
  echo "Python 3 was not found. Install the Xcode Command Line Tools (xcode-select --install) and try again." >&2
  exit 1
fi

mkdir -p "$DEST"
cp "$HERE/service.py" "$HERE/ui.html" "$DEST/"
chmod +x "$DEST/service.py"
# The previous design used a separate WindowKit helper app; the photo panel is in-app now.
rm -rf "$DEST/iCloud Photos.app"

if [ ! -x "$DEST/venv/bin/python" ] || ! "$DEST/venv/bin/python" -c 'import pyicloud' >/dev/null 2>&1; then
  echo "Setting up the iCloud Photos service (this downloads pyicloud once)…"
  rm -rf "$DEST/venv"
  "$PY" -m venv "$DEST/venv"
  "$DEST/venv/bin/pip" install --quiet --disable-pip-version-check --upgrade pip >/dev/null 2>&1 || true
  "$DEST/venv/bin/pip" install --quiet --disable-pip-version-check 'pyicloud==2026.10.1'
fi

echo "iCloud Photos service ready: $DEST"
