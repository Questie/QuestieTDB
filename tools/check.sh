#!/usr/bin/env bash
# tools/check.sh
#
# Runs the gates across flavours in parallel, budgeted by memory rather than by core count.
#
# The sweep is embarrassingly parallel within a phase, but it is NOT free to fan out. Measured
# peaks on this tree:
#
#   equivalence Mists   1.66 GB / 57 s        equivalence Vanilla   0.42 GB / 19 s
#   verify      Mists   1.59 GB / 50 s        validators  Mists     0.34 GB /  2 s
#   differential Mists  1.18 GB / 45 s
#
# So a job's footprint varies ~5x by flavour and ~7x by gate. A flat `-j N` either thrashes
# or wastes most of the machine. This admits jobs while their combined estimate fits a runtime
# budget taken from MemAvailable, heaviest first, so the long pole starts immediately.
#
# `all` finishes Generation for every selected flavor before any gate or unit test can read an
# artifact. Explicit `determinism` checks form a second phase when requested.
#
# Usage:
#   tools/check.sh                       verify equivalence reconstruct validators differential
#   tools/check.sh verify equivalence    only these gates
#   tools/check.sh all                   Generation, every gate, and the unit tests
#   tools/check.sh determinism freeze    deterministic regeneration and freeze verification
#   tools/check.sh --flavors=Vanilla,Mists
#   tools/check.sh --budget-mb=4000      override the memory budget
#   tools/check.sh --questie=../Questie  where Questie is checked out
#   tools/check.sh --sequential          run one at a time, for comparison or a small machine
#
# Exits non-zero if any job fails. Per-job logs land in .out/checks/.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

LUA="${LUA:-lua5.1}"
QUESTIE="${QUESTIE_PATH:-../Questie}"
FLAVOURS=(Vanilla TBC Wrath Cata Mists)
GATES=()
BUDGET_MB=0
SEQUENTIAL=0
LOGDIR=".out/checks"

# Byte-reproducible artifacts: Generation stamps X-BUILD-TIME from this rather than the wall
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

# Nested tools and unit-test controls use the same checkout and interpreter selected here.
export QUESTIE_PATH="$QUESTIE"
export LUA

# Gates that read Questie must all use the reviewed input commit. Validators, Golden checks,
# Verification, and Equivalence operate entirely on this repository and generated artifacts.
needs_questie=0
for gate in "${GATES[@]}"; do
    case "$gate" in
        generate|determinism|reconstruct|differential) needs_questie=1 ;;
    esac
done
if [ "$needs_questie" -eq 1 ]; then
    "$LUA" -e 'dofile("generator/lib.lua").assertQuestiePin(os.getenv("QUESTIE_PATH"))' || exit 1
fi

# Peak RSS in MB for the heaviest gate, per flavour. Interpolated from the measurements above;
# deliberately rounded up, because over-estimating costs a little idle CPU while
# under-estimating invites the OOM killer.
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

if [ "$BUDGET_MB" -eq 0 ]; then
    available=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 4096)
    # Leave headroom: these estimates are peaks, and the machine is not ours alone.
    BUDGET_MB=$(( available * 70 / 100 ))
    [ "$BUDGET_MB" -lt 2000 ] && BUDGET_MB=2000
fi

mkdir -p "$LOGDIR"
rm -f "$LOGDIR"/*.log 2>/dev/null

# Build a shell-safe command string for the scheduler's `bash -c` boundary.
command_string() {
    printf '%q ' "$@"
}

# `wait -n -p` already requires Bash 5.1, which provides this clock without GNU `date`.
now_ms() {
    local epoch_realtime="$EPOCHREALTIME"
    local seconds="${epoch_realtime%%.*}"
    local milliseconds="${epoch_realtime#*.}"
    milliseconds="${milliseconds:0:3}"
    printf '%d\n' "$(( seconds * 1000 + 10#$milliseconds ))"
}

elapsed_ms_since() {
    local elapsed_ms=$(( $(now_ms) - $1 ))
    # A wall-clock correction should not turn a duration into a negative number.
    [ "$elapsed_ms" -lt 0 ] && elapsed_ms=0
    printf '%d\n' "$elapsed_ms"
}

format_duration() {
    local rounded_ms=$(( $1 + 50 ))
    printf '%d.%01ds' "$(( rounded_ms / 1000 ))" "$(( rounded_ms % 1000 / 100 ))"
}

labels=()
cmds=()
weights=()

add_job() {
    labels+=("$1")
    weights+=("$2")
    cmds+=("$3")
}

# Run the jobs currently held in labels/cmds/weights. Callers build one dependency phase at a
# time; returning non-zero stops the next phase from seeing absent or half-written artifacts.
run_jobs() {
    local phase="$1"
    local total=${#labels[@]}
    [ "$total" -eq 0 ] && return 0

    local -a order
    local idx label log summary duration
    order=($(for idx in "${!weights[@]}"; do echo "${weights[$idx]} $idx"; done |
        sort -rn | awk '{print $2}'))

    echo "==> $phase: ${total} jobs, budget ${BUDGET_MB} MB$([ "$SEQUENTIAL" = 1 ] && echo ', sequential')"
    local phase_started_ms
    phase_started_ms=$(now_ms)

    local -A PID_LABEL PID_WEIGHT PID_STARTED_MS RESULT DURATION_MS
    local used=0 next=0 inflight=0

    reap_one() {
        local pid rc
        wait -n -p pid
        rc=$?
        [ -z "${pid:-}" ] && return 1
        local finished_label="${PID_LABEL[$pid]}"
        local elapsed_ms
        elapsed_ms=$(elapsed_ms_since "${PID_STARTED_MS[$pid]}")
        duration=$(format_duration "$elapsed_ms")
        RESULT["$finished_label"]=$rc
        DURATION_MS["$finished_label"]=$elapsed_ms
        used=$(( used - PID_WEIGHT[$pid] ))
        inflight=$(( inflight - 1 ))
        unset 'PID_LABEL[$pid]' 'PID_WEIGHT[$pid]' 'PID_STARTED_MS[$pid]'
        if [ "$rc" -eq 0 ]; then
            printf '    ok   %-22s %8s\n' "$finished_label" "$duration"
        else
            printf '    FAIL %-22s %8s (exit %d)\n' "$finished_label" "$duration" "$rc"
        fi
        return 0
    }

    while [ "$next" -lt "$total" ] || [ "$inflight" -gt 0 ]; do
        # Always admit at least one job. Otherwise a job heavier than the whole budget would
        # deadlock the queue instead of running alone.
        while [ "$next" -lt "$total" ]; do
            idx=${order[$next]}
            local weight=${weights[$idx]}
            if [ "$inflight" -gt 0 ] && [ $(( used + weight )) -gt "$BUDGET_MB" ]; then break; fi
            [ "$SEQUENTIAL" = 1 ] && [ "$inflight" -gt 0 ] && break
            label="${labels[$idx]}"
            printf '  start %-22s (%4d MB, %d in flight)\n' "$label" "$weight" "$(( inflight + 1 ))"
            local job_started_ms pid
            job_started_ms=$(now_ms)
            bash -c "${cmds[$idx]}" > "$LOGDIR/${label//[:\/]/_}.log" 2>&1 &
            pid=$!
            PID_LABEL[$pid]="$label"
            PID_WEIGHT[$pid]=$weight
            PID_STARTED_MS[$pid]=$job_started_ms
            used=$(( used + weight ))
            inflight=$(( inflight + 1 ))
            next=$(( next + 1 ))
        done
        [ "$inflight" -gt 0 ] && reap_one
    done

    local phase_elapsed_ms
    phase_elapsed_ms=$(elapsed_ms_since "$phase_started_ms")
    local failed=0 rc
    echo
    echo "==> $phase results ($(format_duration "$phase_elapsed_ms"))"
    for idx in "${!labels[@]}"; do
        label="${labels[$idx]}"
        rc="${RESULT[$label]:-1}"
        duration=$(format_duration "${DURATION_MS[$label]:-0}")
        log="$LOGDIR/${label//[:\/]/_}.log"
        summary=$(grep -E '^\[(PASS|FAIL)\]|^[0-9]+ checks|no regressions|divergences:' "$log" 2>/dev/null | tail -1)
        if [ "$rc" -eq 0 ]; then
            printf '  \033[32mPASS\033[0m %-22s %8s' "$label" "$duration"
        else
            failed=$(( failed + 1 ))
            printf '  \033[31mFAIL\033[0m %-22s %8s' "$label" "$duration"
        fi
        [ -n "$summary" ] && printf '  %s' "$summary"
        printf '\n'
    done
    echo

    if [ "$failed" -gt 0 ]; then
        echo "$failed of $total failed in $phase. Logs in $LOGDIR/"
        return 1
    fi
    echo "all $total $phase jobs passed in $(format_duration "$phase_elapsed_ms")"
}

started_all_ms=$(now_ms)

# ---- phase 1: Generation -----------------------------------------------------------------

run_generation=0
post_generation_gates=()
for gate in "${GATES[@]}"; do
    if [ "$gate" = "generate" ]; then run_generation=1
    else post_generation_gates+=("$gate")
    fi
done

if [ "$run_generation" -eq 1 ]; then
    echo "==> generating base TOC"
    base_started_ms=$(now_ms)
    if "$LUA" generate.lua toc --quiet; then
        base_elapsed_ms=$(elapsed_ms_since "$base_started_ms")
        printf '    ok   %-22s %8s\n' "generate:toc" "$(format_duration "$base_elapsed_ms")"
    else
        base_elapsed_ms=$(elapsed_ms_since "$base_started_ms")
        printf '    FAIL %-22s %8s\n' "generate:toc" "$(format_duration "$base_elapsed_ms")"
        echo "base TOC generation failed" >&2
        exit 1
    fi

    labels=(); cmds=(); weights=()
    for flavor in "${FLAVOURS[@]}"; do
        add_job "generate:$flavor" "$(flavour_weight "$flavor")" \
            "$(command_string "$LUA" generate.lua "$flavor" --no-base-toc --quiet)"
    done
    run_jobs "Generation" || exit 1
fi

# ---- phase 2: deterministic regeneration -------------------------------------------------

run_determinism=0
check_gates=()
for gate in "${post_generation_gates[@]}"; do
    if [ "$gate" = "determinism" ]; then run_determinism=1
    else check_gates+=("$gate")
    fi
done

if [ "$run_determinism" -eq 1 ]; then
    labels=(); cmds=(); weights=()
    for flavor in "${FLAVOURS[@]}"; do
        toc="QuestieTDB_${flavor}.toc"
        hash_file="$LOGDIR/determinism_${flavor}.sha"
        printf -v determinism_cmd \
            'set -euo pipefail; sha256sum %q > %q; %s; sha256sum -c %q' \
            "$toc" "$hash_file" \
            "$(command_string "$LUA" generate.lua "$flavor" --no-base-toc --quiet)" \
            "$hash_file"
        add_job "determinism:$flavor" "$(flavour_weight "$flavor")" "$determinism_cmd"
    done
    run_jobs "determinism" || exit 1
fi

# ---- phase 3: checks ---------------------------------------------------------------------

labels=(); cmds=(); weights=()
for gate in "${check_gates[@]}"; do
    case "$gate" in
        test)
            add_job "test" 300 "$(command_string "$LUA" test.lua)" ;;
        verify|equivalence)
            for flavor in "${FLAVOURS[@]}"; do
                add_job "$gate:$flavor" "$(flavour_weight "$flavor")" \
                    "$(command_string "$LUA" "$gate.lua" "$flavor")"
            done ;;
        freeze)
            for flavor in "${FLAVOURS[@]}"; do
                case "$flavor" in
                    Vanilla|Mists)
                        add_job "verify-freeze:$flavor" "$(flavour_weight "$flavor")" \
                            "$(command_string "$LUA" verify.lua "$flavor" --freeze)" ;;
                esac
            done ;;
        reconstruct)
            for flavor in "${FLAVOURS[@]}"; do
                add_job "reconstruct:$flavor" "$(flavour_weight "$flavor")" \
                    "$(command_string "$LUA" reconstruct.lua "$flavor" --questie="$QUESTIE")"
            done ;;
        validators)
            for flavor in "${FLAVOURS[@]}"; do
                add_job "validators:$flavor" "$(( $(flavour_weight "$flavor") * 25 / 100 ))" \
                    "$(command_string "$LUA" validators/run.lua "$flavor")"
            done ;;
        differential)
            for flavor in "${FLAVOURS[@]}"; do
                add_job "differential:$flavor" "$(( $(flavour_weight "$flavor") * 75 / 100 ))" \
                    "$(command_string python3 tools/differential/compiler_diff.py "$flavor" --questie="$QUESTIE" --lua="$LUA" --self-check)"
            done ;;
        golden)
            for flavor in "${FLAVOURS[@]}"; do
                add_job "golden:$flavor" "$(( $(flavour_weight "$flavor") * 50 / 100 ))" \
                    "$(command_string python3 tools/differential/golden.py check "$flavor" --lua="$LUA" --self-check)"
            done ;;
        *) echo "unknown gate: $gate" >&2; exit 2 ;;
    esac
done

if [ ${#labels[@]} -gt 0 ]; then
    run_jobs "checks" || exit 1
elif [ "$run_generation" -eq 0 ] && [ "$run_determinism" -eq 0 ]; then
    echo "nothing to run"
    exit 0
fi

all_elapsed_ms=$(elapsed_ms_since "$started_all_ms")
echo
echo "all stages passed in $(format_duration "$all_elapsed_ms")"
