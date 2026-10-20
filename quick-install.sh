#!/bin/bash
# Downloads the latest version of this patch and starts the point-and-click installer.
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english/main/quick-install.sh)"
set -euo pipefail
REPO="JacksonJones2003/vivo-office-kit-english"
DEST="$HOME/Library/Application Support/vivo-office-kit-english-mac"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading the English patch..."
curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP"
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
SRC="$(ls -d "$TMP"/*/ | head -1)"   # top folder is named after the repository, which was renamed
mv "${SRC%/}" "$DEST"
chmod +x "$DEST/install.sh" "$DEST/Install English Patch.command" "$DEST/patcher.pl" "$DEST/watcher/"*.sh
echo "Starting the installer (look for a dialog window)..."
exec "$DEST/install.sh"
