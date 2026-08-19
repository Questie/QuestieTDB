#!/usr/bin/env bash
# tools/package.sh
#
# Packages generated artifacts and writes the release manifest.
#
# Bash rather than Lua on purpose: this needs zip and sha256sum, and the generator's
# no-C-dependency rule exists so contributors can regenerate with a bare interpreter — it does
# not extend to packaging, which only ever runs in CI or on a maintainer's machine.
#
# Usage: tools/package.sh <Vanilla|TBC|Wrath|Cata|Mists|all>

set -euo pipefail

FLAVORS=("$@")
if [ "${1:-}" = "all" ] || [ $# -eq 0 ]; then
    FLAVORS=(Vanilla TBC Wrath Cata Mists)
fi

DIST=".out/dist"
STAGE=".out/stage"
rm -rf "$DIST" "$STAGE"
mkdir -p "$DIST"

COMMIT="$(git rev-parse HEAD 2>/dev/null || printf '%040d' 0)"
CONTRACT="$(grep -oE 'config\.contractVersion = [0-9]+' src/config.lua | grep -oE '[0-9]+$')"
BUILT="$(date -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y-%m-%dT%H:%M:%SZ)"

# The addon folder must be named QuestieTDB in the zip, because that is what
# `## Dependencies: QuestieTDB` resolves against.
mkdir -p "$STAGE/QuestieTDB"

entries=()

for FLAVOR in "${FLAVORS[@]}"; do
    TOC="QuestieTDB_${FLAVOR}.toc"
    if [ ! -f "$TOC" ]; then
        echo "package: $TOC not generated, skipping" >&2
        continue
    fi

    rm -rf "${STAGE:?}/QuestieTDB"
    mkdir -p "$STAGE/QuestieTDB"

    # Ship exactly the files the artifact's own TOC lists, plus the TOC. Static-only correction
    # files are build-time input and are already absent from that list.
    cp "$TOC" "$STAGE/QuestieTDB/"
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        rel="${line//\\//}"
        if [ -f "$rel" ]; then
            mkdir -p "$STAGE/QuestieTDB/$(dirname "$rel")"
            cp "$rel" "$STAGE/QuestieTDB/$rel"
        fi
    done < "$TOC"

    ZIP="$DIST/QuestieTDB-${FLAVOR}.zip"
    (cd "$STAGE" && zip -qr9X "../../$ZIP" QuestieTDB)

    SIZE=$(stat -c %s "$ZIP")
    SHA=$(sha256sum "$ZIP" | cut -d' ' -f1)
    RAW=$(stat -c %s "$TOC")

    # The artifact records the Questie checkout its l10n was generated from. One release is
    # one Questie state: artifacts that disagree must never share a manifest.
    QC=$(sed -n 's/^## X-QUESTIE-COMMIT: //p' "$TOC" | head -1 | tr -d '\r')
    [ -n "$QC" ] || QC="$(printf '%040d' 0)"
    if [ -z "${QUESTIE_COMMIT:-}" ]; then
        QUESTIE_COMMIT="$QC"
    elif [ "$QUESTIE_COMMIT" != "$QC" ]; then
        echo "package: $TOC was generated against Questie $QC but an earlier artifact against $QUESTIE_COMMIT — regenerate all flavors from one checkout" >&2
        exit 1
    fi

    echo "packaged $ZIP  ($(( SIZE / 1048576 )) MB zipped, $(( RAW / 1048576 )) MB raw)"
    entries+=("    {\"flavor\": \"${FLAVOR}\", \"file\": \"QuestieTDB-${FLAVOR}.zip\", \"sha256\": \"${SHA}\", \"bytes\": ${SIZE}, \"rawBytes\": ${RAW}}")
done

rm -rf "$STAGE"

# release.json mirrors the discipline of Questie's own multi-flavor manifest, including
# "nolib" — CurseForge's mechanism for letting a standalone installer avoid a folder collision
# when QuestieTDB also ships bundled inside Questie's zip.
{
    printf '{\n'
    printf '  "producerCommit": "%s",\n' "$COMMIT"
    printf '  "questieCommit": "%s",\n' "${QUESTIE_COMMIT:-$(printf '%040d' 0)}"
    printf '  "contractVersion": %s,\n' "$CONTRACT"
    printf '  "builtAt": "%s",\n' "$BUILT"
    printf '  "nolib": false,\n'
    printf '  "artifacts": [\n'
    printf '%s\n' "$(IFS=$',\n'; echo "${entries[*]}")"
    printf '  ]\n'
    printf '}\n'
} > "$DIST/release.json"

{
    echo "# QuestieTDB"
    echo
    echo "Producing commit: \`$COMMIT\`"
    echo "Questie input commit: \`${QUESTIE_COMMIT:-unknown}\`"
    echo "Contract version: \`$CONTRACT\`"
    echo
    echo "Verify a download before installing:"
    echo
    echo '```'
    echo "sha256sum -c <(jq -r '.artifacts[] | \"\\(.sha256)  \\(.file)\"' release.json)"
    echo '```'
    echo
    echo "Or let \`tools/bootstrap.sh\` do it."
} > "$DIST/RELEASE_NOTES.md"

echo "wrote $DIST/release.json"
