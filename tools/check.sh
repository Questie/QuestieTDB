#!/usr/bin/env bash
# tools/check.sh
#
# Runs the gates across flavours in parallel, budgeted by memory rather than by core count.
#
# The sweep is embarrassingly parallel -- every gate reads one flavour's artifact and writes
# only per-flavour output -- but it is NOT free to fan out. Measured peaks on this tree:
#
#   equivalence Mists   1.66 GB / 57 s        equivalence Vanilla   0.42 GB / 19 s
#   verify      Mists   1.59 GB / 50 s        validators  Mists     0.34 GB /  2 s
#   differential Mists  1.18 GB / 45 s
#
# So a job's footprint varies ~5x by flavour and ~7x by gate. A flat `-j N` either thrashes
# (five Mists-sized jobs is ~8 GB) or wastes most of the machine (five Vanilla-sized jobs is
# ~2 GB). This admits jobs while their combined estimate fits a runtime budget taken from
# MemAvailable, heaviest first, so the long pole starts immediately.
#
# Usage:
#   tools/check.sh                       verify equivalence reconstruct validators differential
#   tools/check.sh verify equivalence    only these gates
#   tools/check.sh all                   everything, including generate and the unit tests
#   tools/check.sh --flavors=Vanilla,Mists
#   tools/check.sh --budget-mb=4000      override the memory budget
#   tools/check.sh --questie=../Questie  where Questie is checked out
#   tools/check.sh --sequential          run one at a time, for comparison or a small machine
#
# Exits non-zero if any job fails. Per-job logs land in .out/checks/.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

LUA="${LUA:-lua5.1}"
QUESTIE="../Questie"
FLAVOURS=(Vanilla TBC Wrath Cata Mists)
GATES=()
BUDGET_MB=0
SEQUENTIAL=0
LOGDIR=".out/checks"

# Byte-reproducible artifacts: generation stamps X-BUILD-TIME from this rather than the wall
# clock, so a determinism check means something. Same value CI uses.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

for arg in "$@"; do
    case "$arg" in
        --flavors=*)   IFS=, read -r -a FLAVOURS <<< "${arg#*=}" ;;
        --budget-mb=*) BUDGET_MB="${arg#*=}" ;;
        --questie=*)   QUESTIE="${arg#*=}" ;;
        --lua=*)       LUA="${arg#*=}" ;;
        --sequential)  SEQUENTIAL=1 ;;
        --*)           echo "unknown option: $arg" >&2; exit 2 ;;
        all)           GATES=(generate verify equivalence reconstruct validators differential golden test) ;;
        *)             GATES+=("$arg") ;;
    esac
done
[ ${#GATES[@]} -eq 0 ] && GATES=(verify equivalence reconstruct validators differential)

# Peak RSS in MB for the heaviest gate, per flavour. Interpolated from the measurements above;
# deliberately rounded up, because the cost of over-estimating is a little idle CPU and the
# cost of under-estimating is the OOM killer.
flavour_weight() {
    case "$1" in
        Vanilla) echo 450 ;;
        TBC)     echo 700 ;;
        Wrath)   echo 1000 ;;
        Cata)    echo 1400 ;;
        Mists)   echo 1750 ;;
        *)       echo 1750 ;;
    esac
}

# Gate cost relative to that peak. Anything unmeasured stays at 1.0.
gate_factor() {
    case "$1" in
        validators) echo 25 ;;
        golden)     echo 50 ;;
        differential) echo 75 ;;
        *)          echo 100 ;;
    esac
}

if [ "$BUDGET_MB" -eq 0 ]; then
    available=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 4096)
    # Leave headroom: these estimates are peaks, and the machine is not ours alone.
    BUDGET_MB=$(( available * 70 / 100 ))
    [ "$BUDGET_MB" -lt 2000 ] && BUDGET_MB=2000
fi

mkdir -p "$LOGDIR"
rm -f "$LOGDIR"/*.log 2>/dev/null

# ---- build the job list -------------------------------------------------------------------
labels=(); cmds=(); weights=()

add_job() { labels+=("$1"); weights+=("$2"); cmds+=("$3"); }

for gate in "${GATES[@]}"; do
    case "$gate" in
        test)
            add_job "test" 300 "$LUA test.lua" ;;
        generate)
            # The base TOC is shared, so it is written once here rather than raced over.
            echo "==> generating base TOC"
            "$LUA" generate.lua toc --quiet || { echo "base TOC generation failed" >&2; exit 1; }
            for f in "${FLAVOURS[@]}"; do
                add_job "generate:$f" "$(flavour_weight "$f")" \
                    "$LUA generate.lua $f --questie=$QUESTIE --no-base-toc --quiet"
            done ;;
        verify|equivalence)
            for f in "${FLAVOURS[@]}"; do
                add_job "$gate:$f" "$(flavour_weight "$f")" "$LUA $gate.lua $f"
            done ;;
        reconstruct)
            for f in "${FLAVOURS[@]}"; do
                add_job "reconstruct:$f" "$(flavour_weight "$f")" \
                    "$LUA reconstruct.lua $f --questie=$QUESTIE"
            done ;;
        validators)
            for f in "${FLAVOURS[@]}"; do
                add_job "validators:$f" "$(( $(flavour_weight "$f") * 25 / 100 ))" \
                    "$LUA validators/run.lua $f"
            done ;;
        differential)
            for f in "${FLAVOURS[@]}"; do
                add_job "differential:$f" "$(( $(flavour_weight "$f") * 75 / 100 ))" \
                    "python3 tools/differential/compiler_diff.py $f --questie=$QUESTIE --lua=$LUA --self-check"
            done ;;
        golden)
            for f in "${FLAVOURS[@]}"; do
                add_job "golden:$f" "$(( $(flavour_weight "$f") * 50 / 100 ))" \
                    "python3 tools/differential/golden.py check $f --lua=$LUA --self-check"
            done ;;
        *) echo "unknown gate: $gate" >&2; exit 2 ;;
    esac
done

total=${#labels[@]}
[ "$total" -eq 0 ] && { echo "nothing to run"; exit 0; }

# Heaviest first. Longest-processing-time ordering: the long pole has to start immediately or
# it lands at the end and the whole sweep waits on it.
order=($(for i in "${!weights[@]}"; do echo "${weights[$i]} $i"; done | sort -rn | awk '{print $2}'))

echo "==> ${total} jobs, budget ${BUDGET_MB} MB$([ "$SEQUENTIAL" = 1 ] && echo ', sequential')"
started=$(date +%s)

declare -A PID_LABEL PID_WEIGHT RESULT
used=0
next=0
# An explicit counter rather than ${#PID_LABEL[@]}: under `set -u`, bash treats the length of a
# declared-but-never-assigned associative array as an unbound variable.
inflight=0

reap_one() {
    local pid rc
    wait -n -p pid
    rc=$?
    [ -z "${pid:-}" ] && return 1
    local label="${PID_LABEL[$pid]}"
    RESULT["$label"]=$rc
    used=$(( used - PID_WEIGHT[$pid] ))
    inflight=$(( inflight - 1 ))
    unset 'PID_LABEL[$pid]' 'PID_WEIGHT[$pid]'
    if [ "$rc" -eq 0 ]; then printf '    ok   %s\n' "$label"
    else printf '    FAIL %s (exit %d)\n' "$label" "$rc"; fi
    return 0
}

while [ "$next" -lt "$total" ] || [ "$inflight" -gt 0 ]; do
    # Admit while the budget allows. Always admit at least one, or a job heavier than the
    # whole budget would deadlock the loop.
    while [ "$next" -lt "$total" ]; do
        idx=${order[$next]}
        w=${weights[$idx]}
        if [ "$inflight" -gt 0 ] && [ $(( used + w )) -gt "$BUDGET_MB" ]; then break; fi
        [ "$SEQUENTIAL" = 1 ] && [ "$inflight" -gt 0 ] && break
        label="${labels[$idx]}"
        printf '  start %-22s (%4d MB, %d in flight)\n' "$label" "$w" "$(( inflight + 1 ))"
        bash -c "${cmds[$idx]}" > "$LOGDIR/${label//[:\/]/_}.log" 2>&1 &
        PID_LABEL[$!]="$label"
        PID_WEIGHT[$!]=$w
        used=$(( used + w ))
        inflight=$(( inflight + 1 ))
        next=$(( next + 1 ))
    done
    [ "$inflight" -gt 0 ] && reap_one
done

elapsed=$(( $(date +%s) - started ))

# ---- summary ------------------------------------------------------------------------------
echo
echo "==> results (${elapsed}s)"
failed=0
for idx in "${!labels[@]}"; do
    label="${labels[$idx]}"
    rc="${RESULT[$label]:-1}"
    log="$LOGDIR/${label//[:\/]/_}.log"
    summary=$(grep -E '^\[(PASS|FAIL)\]|^[0-9]+ checks|no regressions|divergences:' "$log" 2>/dev/null | tail -1)
    if [ "$rc" -eq 0 ]; then
        printf '  \033[32mPASS\033[0m %-22s %s\n' "$label" "${summary:0:96}"
    else
        failed=$(( failed + 1 ))
        printf '  \033[31mFAIL\033[0m %-22s %s\n' "$label" "${summary:0:96}"
    fi
done

if [ "$failed" -gt 0 ]; then
    echo
    echo "$failed of $total failed. Logs in $LOGDIR/"
    exit 1
fi
echo
echo "all $total passed in ${elapsed}s"
