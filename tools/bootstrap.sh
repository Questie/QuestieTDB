#!/usr/bin/env bash
# tools/bootstrap.sh
#
# Installs generated QuestieTDB artifacts into a developer's AddOns folder, so refreshing a
# local copy is one command instead of a 50-second regeneration.
#
# It is a **downloader**, not a build tool: no Lua, no toolchain. curl, unzip and sha256sum.
#
# Two deviations from the usual pattern, both deliberate:
#   * the install target is `Interface/AddOns/QuestieTDB/`, not a project cache directory
#   * **all flavors are downloaded**, so switching test clients needs no re-bootstrap
#
# Usage:
#   tools/bootstrap.sh <AddOns-path> [tag]
#   tools/bootstrap.sh "/c/Program Files/World of Warcraft/_classic_era_/Interface/AddOns"
#   tools/bootstrap.sh ~/wow/Interface/AddOns build-a1b2c3d      # pin an exact release

set -euo pipefail

REPO="${QUESTIETDB_REPO:-Questie/QuestieTDB}"
ADDONS="${1:-}"
TAG="${2:-latest}"

if [ -z "$ADDONS" ]; then
    echo "usage: $0 <AddOns-path> [tag]" >&2
    exit 2
fi
if [ ! -d "$ADDONS" ]; then
    echo "bootstrap: '$ADDONS' is not a directory. Point this at Interface/AddOns." >&2
    exit 2
fi

for tool in curl unzip sha256sum; do
    command -v "$tool" >/dev/null || { echo "bootstrap: $tool is required" >&2; exit 2; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$TAG" = "latest" ]; then
    BASE="https://github.com/${REPO}/releases/latest/download"
else
    BASE="https://github.com/${REPO}/releases/download/${TAG}"
fi

echo "bootstrap: fetching manifest from ${BASE}"
curl -fsSL "${BASE}/release.json" -o "$WORK/release.json"

COMMIT=$(grep -oE '"producerCommit"[^"]*"[^"]*"' "$WORK/release.json" | grep -oE '[0-9a-f]{40}' || echo unknown)
CONTRACT=$(grep -oE '"contractVersion"[^,]*' "$WORK/release.json" | grep -oE '[0-9]+$' || echo unknown)
echo "bootstrap: release built from ${COMMIT}, contract version ${CONTRACT}"

# One entry per line: <file> <sha256>
grep -oE '"file": "[^"]+", "sha256": "[0-9a-f]{64}"' "$WORK/release.json" \
  | sed -E 's/"file": "([^"]+)", "sha256": "([0-9a-f]{64})"/\1 \2/' > "$WORK/files.txt"

if [ ! -s "$WORK/files.txt" ]; then
    echo "bootstrap: manifest listed no artifacts" >&2
    exit 1
fi

TARGET="$ADDONS/QuestieTDB"
mkdir -p "$TARGET"

while read -r FILE SHA; do
    echo "bootstrap: downloading $FILE"
    curl -fsSL "${BASE}/${FILE}" -o "$WORK/$FILE"

    # Checksums are verified **before** installing, not after. A truncated download that
    # overwrites a working install is worse than no install.
    echo "$SHA  $WORK/$FILE" | sha256sum -c --quiet - || {
        echo "bootstrap: checksum mismatch for $FILE — refusing to install" >&2
        exit 1
    }
done < "$WORK/files.txt"

echo "bootstrap: all checksums verified, installing into $TARGET"

# Remove only the generated TOCs. Everything else in the folder may be a working clone, and
# clobbering that would be an unpleasant surprise.
rm -f "$TARGET"/QuestieTDB_*.toc

while read -r FILE SHA; do
    unzip -qo "$WORK/$FILE" -d "$WORK/extract"
done < "$WORK/files.txt"

cp -r "$WORK/extract/QuestieTDB/." "$TARGET/"

echo "bootstrap: installed. Suffixed TOCs present:"
ls -1 "$TARGET"/QuestieTDB_*.toc 2>/dev/null | sed 's|.*/|  |'
echo "bootstrap: the client will now use Baked mode. Delete those TOCs to return to Source mode."
