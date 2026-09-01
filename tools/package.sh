#!/usr/bin/env bash
# tools/package.sh
#
# Packages generated artifacts and writes the release manifest.
#
# Bash rather than Lua on purpose: this needs zip, unzip and sha256sum, and the generator's
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
LUA="${LUA:-lua5.1}"

# The addon folder must be named QuestieTDB in the zip, because that is what
# `## Dependencies: QuestieTDB` resolves against.
mkdir -p "$STAGE/QuestieTDB"

# Stage exactly the runtime files a TOC lists, plus the TOC itself. Static-only correction files
# are build-time input and are already absent from that list. Analysis-only files are staged
# separately below. Staging into an existing folder is safe because every copy comes from the
# same working tree: a path two flavors share is the same file, which is what lets the combined
# artifact union five TOCs below.
stage_toc() {
    local toc="$1" dest="$2" line rel
    cp "$toc" "$dest/"
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        rel="${line//\\//}"
        if [ -f "$rel" ]; then
            mkdir -p "$dest/$(dirname "$rel")"
            cp "$rel" "$dest/$rel"
        fi
    done < "$toc"
}

# LuaLS declarations ship beside the addon, but the client must never load them through a TOC.
stage_types() {
    local dest="$1"
    mkdir -p "$dest/Types"
    cp src/types/*.t.lua "$dest/Types/"
}

assert_type_artifacts() {
    local zip="$1" type_file basename listing
    listing="$(unzip -Z1 "$zip")"
    for type_file in src/types/*.t.lua; do
        basename="${type_file##*/}"
        if ! grep -Fxq "QuestieTDB/Types/$basename" <<< "$listing"; then
            echo "package: $zip is missing QuestieTDB/Types/$basename" >&2
            exit 1
        fi
    done
}

entries=()

for FLAVOR in "${FLAVORS[@]}"; do
    TOC="QuestieTDB_${FLAVOR}.toc"
    if [ ! -f "$TOC" ]; then
        echo "package: $TOC not generated, skipping" >&2
        continue
    fi

    rm -rf "${STAGE:?}/QuestieTDB"
    mkdir -p "$STAGE/QuestieTDB"

    stage_toc "$TOC" "$STAGE/QuestieTDB"
    stage_types "$STAGE/QuestieTDB"

    # Mixed correction files ship for their Dynamic functions, but their Static bodies are
    # already folded into the metadata store — 94-96% of the bytes (issue #5). Strip the
    # staged copies; src/corrections/ keeps every upstream byte outside the declared ownership
    # exclusions, which is what the drift gate and port-corrections compare.
    "$LUA" tools/strip-static.lua "$STAGE/QuestieTDB"

    ZIP="$DIST/QuestieTDB-${FLAVOR}.zip"
    (cd "$STAGE" && zip -qr9X "../../$ZIP" QuestieTDB)
    assert_type_artifacts "$ZIP"

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

# The combined artifact: every flavor's TOC plus the union of the files they list. Dropped
# into any Classic client's AddOns folder, the client picks its own suffixed TOC — the same
# precedence rule that makes a dev clone work everywhere. The per-flavor zips above stay as
# the smaller downloads; this is the "works anywhere" install and what bootstrap fetches.
#
# The base QuestieTDB.toc deliberately does not ship: the package carries no data/, so source
# mode cannot run from it, and every Classic client matches one of the five suffixed TOCs.
# Built only when every flavor was packaged in this run — CI's per-flavor matrix jobs skip it.
if [ ${#entries[@]} -eq 5 ]; then
    rm -rf "${STAGE:?}/QuestieTDB"
    mkdir -p "$STAGE/QuestieTDB"

    RAW_ALL=0
    for FLAVOR in "${FLAVORS[@]}"; do
        TOC="QuestieTDB_${FLAVOR}.toc"
        stage_toc "$TOC" "$STAGE/QuestieTDB"
        RAW_ALL=$(( RAW_ALL + $(stat -c %s "$TOC") ))
    done
    stage_types "$STAGE/QuestieTDB"

    "$LUA" tools/strip-static.lua "$STAGE/QuestieTDB"

    ZIP="$DIST/QuestieTDB-all.zip"
    (cd "$STAGE" && zip -qr9X "../../$ZIP" QuestieTDB)
    assert_type_artifacts "$ZIP"

    SIZE=$(stat -c %s "$ZIP")
    SHA=$(sha256sum "$ZIP" | cut -d' ' -f1)
    echo "packaged $ZIP  ($(( SIZE / 1048576 )) MB zipped, $(( RAW_ALL / 1048576 )) MB raw, every flavor)"
    entries+=("    {\"flavor\": \"All\", \"file\": \"QuestieTDB-all.zip\", \"sha256\": \"${SHA}\", \"bytes\": ${SIZE}, \"rawBytes\": ${RAW_ALL}}")
else
    echo "package: QuestieTDB-all.zip needs all five flavors in one run — skipped" >&2
fi

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
    joined="$(printf '%s,\n' "${entries[@]}")"
    printf '%s\n' "${joined%,}"
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
    echo "Not sure which zip matches your client? \`QuestieTDB-all.zip\` contains every flavor"
    echo "and the client loads the one that matches. The per-flavor zips are the same content,"
    echo "one flavor at a time, as smaller downloads."
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
