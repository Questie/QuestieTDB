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
# or wastes most of the machine. Runtime priority decides which long jobs should start first;
# memory weight only controls admission within a budget taken from MemAvailable. When the next
# priority job does not fit, smaller jobs may use the remaining budget instead of leaving it idle.
#
# `all` finishes Generation for every selected flavor before any gate or unit test can read an
# artifact. Explicit `determinism` checks form a second phase when requested.
#
# Usage:
#   tools/check.sh                       verify equivalence reconstruct validators differential
#   tools/check.sh verify equivalence    only these gates
#   tools/check.sh all                   Generation, standard gates, Golden, and unit tests
#   tools/check.sh determinism freeze    deterministic regeneration and freeze verification
#   tools/check.sh --flavors=Vanilla,Mists
#   tools/check.sh --budget-mb=4000      override the memory budget, maximum 2147483647 MB
#   tools/check.sh --questie=../Questie  where Questie is checked out
#   tools/check.sh --sequential          run one at a time, for comparison or a small machine
#
# Exits non-zero if any job fails. Per-job logs land in .out/checks/.

if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1) )); then
    printf 'QuestieTDB requires Bash 5.1 or newer; found %s.\n' "$BASH_VERSION" >&2
    exit 2
fi

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

LUA_EXPLICIT=0
[ -n "${LUA:-}" ] && LUA_EXPLICIT=1
LUA="${LUA:-}"
QUESTIE="${QUESTIE_PATH:-../Questie}"
FLAVOURS=(Vanilla TBC Wrath Cata Mists)
GATES=()
BUDGET_MB=0
BUDGET_EXPLICIT=0
MAX_BUDGET_MB=2147483647
FLAVOURS_EXPLICIT=0
SEQUENTIAL=0
LOGDIR=".out/checks"

# Byte-reproducible artifacts: Generation stamps X-BUILD-TIME from this rather than the wall
# clock, so a determinism check means something. Same value CI uses.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

for arg in "$@"; do
    case "$arg" in
        --flavors=*)
            [ "$FLAVOURS_EXPLICIT" -eq 0 ] || { echo "--flavors may be provided only once" >&2; exit 2; }
            flavor_value="${arg#*=}"
            if [ -z "$flavor_value" ] || [[ "$flavor_value" == ,* || "$flavor_value" == *, || "$flavor_value" == *,,* ]]; then
                echo "--flavors requires a comma-separated list without empty values" >&2
                exit 2
            fi
            FLAVOURS_EXPLICIT=1
            IFS=, read -r -a FLAVOURS <<< "$flavor_value"
            ;;
        --budget-mb=*)
            [ "$BUDGET_EXPLICIT" -eq 0 ] || { echo "--budget-mb may be provided only once" >&2; exit 2; }
            BUDGET_MB="${arg#*=}"
            BUDGET_EXPLICIT=1
            ;;
        --questie=*)   QUESTIE="${arg#*=}" ;;
        --lua=*)       LUA="${arg#*=}"; LUA_EXPLICIT=1 ;;
        --sequential)  SEQUENTIAL=1 ;;
        --*)           echo "unknown option: $arg" >&2; exit 2 ;;
        *)             GATES+=("$arg") ;;
    esac
done

# Normalize public selections before interpreter probes or filesystem work. Duplicate labels
# would share one log/result slot in the scheduler, so each gate and flavor runs at most once.
declare -A seen_flavours=() seen_gates=()
normalized_flavours=()
for flavor in "${FLAVOURS[@]}"; do
    case "$flavor" in
        Vanilla|TBC|Wrath|Cata|Mists) ;;
        *)
            echo "unknown flavor: $flavor" >&2
            echo "Flavors: Vanilla TBC Wrath Cata Mists" >&2
            exit 2
            ;;
    esac
    if [ -z "${seen_flavours[$flavor]+x}" ]; then
        normalized_flavours+=("$flavor")
        seen_flavours[$flavor]=1
    fi
done
FLAVOURS=("${normalized_flavours[@]}")

normalized_gates=()
for gate in "${GATES[@]}"; do
    case "$gate" in
        generate|verify|equivalence|reconstruct|validators|differential|golden|test|determinism|freeze|all) ;;
        *) echo "unknown gate: $gate" >&2; exit 2 ;;
    esac
    if [ -z "${seen_gates[$gate]+x}" ]; then
        normalized_gates+=("$gate")
        seen_gates[$gate]=1
    fi
done
GATES=("${normalized_gates[@]}")

if [ -n "${seen_gates[all]+x}" ]; then
    if [ "${#GATES[@]}" -ne 1 ]; then
        echo "all cannot be combined with other gates" >&2
        exit 2
    fi
    GATES=(generate verify equivalence reconstruct validators differential golden test)
elif [ "${#GATES[@]}" -eq 0 ]; then
    GATES=(verify equivalence reconstruct validators differential)
fi

if [ "$FLAVOURS_EXPLICIT" -eq 1 ] && [ -n "${seen_gates[freeze]+x}" ]; then
    for flavor in "${FLAVOURS[@]}"; do
        case "$flavor" in
            Vanilla|Mists) ;;
            *)
                echo "freeze supports only Vanilla and Mists; unsupported flavor: $flavor" >&2
                exit 2
                ;;
        esac
    done
fi

if [ "$BUDGET_EXPLICIT" -eq 1 ]; then
    if [[ ! "$BUDGET_MB" =~ ^[0-9]+$ ]]; then
        echo "--budget-mb requires a positive decimal integer" >&2
        exit 2
    fi
    while [[ "$BUDGET_MB" == 0* && ${#BUDGET_MB} -gt 1 ]]; do
        BUDGET_MB="${BUDGET_MB#0}"
    done
    if [ "$BUDGET_MB" = "0" ]; then
        echo "--budget-mb requires a positive decimal integer" >&2
        exit 2
    fi
    if [ "${#BUDGET_MB}" -gt "${#MAX_BUDGET_MB}" ] ||
       { [ "${#BUDGET_MB}" -eq "${#MAX_BUDGET_MB}" ] && [[ "$BUDGET_MB" > "$MAX_BUDGET_MB" ]]; }; then
        echo "--budget-mb must not exceed $MAX_BUDGET_MB MB" >&2
        exit 2
    fi
fi

# Resolve the interpreter before pin checks, log cleanup, or artifact writes. A generic `lua`
# is accepted only when it has the Lua 5.1 behavior this generator and its tests target.
if [ "$LUA_EXPLICIT" -eq 1 ]; then
    lua_candidates=("$LUA")
else
    lua_candidates=(lua5.1 lua)
fi

selected_lua=""
found_lua_versions=()
for candidate in "${lua_candidates[@]}"; do
    if [ -z "$candidate" ] || ! command -v "$candidate" >/dev/null 2>&1; then
        continue
    fi
    version=$("$candidate" -e 'io.write(_VERSION)' 2>/dev/null) || version="unusable"
    if [ "$version" = "Lua 5.1" ]; then
        selected_lua="$candidate"
        break
    fi
    found_lua_versions+=("$candidate: $version")
done

if [ -z "$selected_lua" ]; then
    if [ "$LUA_EXPLICIT" -eq 1 ]; then
        if [ -z "$LUA" ] || ! command -v "$LUA" >/dev/null 2>&1; then
            echo "Lua interpreter not found: ${LUA:-<empty>}" >&2
        else
            echo "QuestieTDB requires Lua 5.1; $LUA reports ${found_lua_versions[0]#*: }." >&2
        fi
    else
        echo "QuestieTDB requires Lua 5.1, but neither lua5.1 nor a Lua 5.1 'lua' was found." >&2
        if [ "${#found_lua_versions[@]}" -gt 0 ]; then
            printf 'Found %s\n' "${found_lua_versions[@]}" >&2
        fi
    fi
    echo "Install Lua 5.1, set LUA=/path/to/lua5.1, or pass --lua=/path/to/lua5.1." >&2
    exit 127
fi
LUA="$selected_lua"

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
priorities=()

add_job() {
    labels+=("$1")
    weights+=("$2")
    cmds+=("$3")
    priorities+=("${4:-0}")
}

# Run the jobs currently held in labels/cmds/weights/priorities. Callers build one dependency
# phase at a time; returning non-zero stops the next phase from seeing absent or half-written
# artifacts.
run_jobs() {
    local phase="$1"
    local total=${#labels[@]}
    [ "$total" -eq 0 ] && return 0

    local -a order pending
    local idx label log summary duration
    mapfile -t order < <(
        for idx in "${!weights[@]}"; do
            printf '%d %d %d\n' "${priorities[$idx]}" "${weights[$idx]}" "$idx"
        done | sort -k1,1nr -k2,2nr -k3,3n | awk '{print $3}'
    )
    pending=("${order[@]}")

    echo "==> $phase: ${total} jobs, budget ${BUDGET_MB} MB$([ "$SEQUENTIAL" = 1 ] && echo ', sequential')"
    local phase_started_ms
    phase_started_ms=$(now_ms)

    local -A PID_LABEL PID_WEIGHT PID_STARTED_MS RESULT DURATION_MS
    local used=0 inflight=0

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

    while [ "${#pending[@]}" -gt 0 ] || [ "$inflight" -gt 0 ]; do
        while [ "${#pending[@]}" -gt 0 ]; do
            [ "$SEQUENTIAL" = 1 ] && [ "$inflight" -gt 0 ] && break

            # Pick the highest-priority pending job that fits. With nothing running, admit the
            # first job even when its estimate exceeds the budget so the queue cannot deadlock.
            local pending_pos=-1 weight pos
            for pos in "${!pending[@]}"; do
                idx=${pending[$pos]}
                weight=${weights[$idx]}
                if [ "$inflight" -eq 0 ] || [ $(( used + weight )) -le "$BUDGET_MB" ]; then
                    pending_pos=$pos
                    break
                fi
            done
            [ "$pending_pos" -lt 0 ] && break

            idx=${pending[$pending_pos]}
            weight=${weights[$idx]}
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

            unset "pending[$pending_pos]"
            pending=("${pending[@]}")
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

    labels=(); cmds=(); weights=(); priorities=()
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
    labels=(); cmds=(); weights=(); priorities=()
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

labels=(); cmds=(); weights=(); priorities=()
for gate in "${check_gates[@]}"; do
    case "$gate" in
        test)
            # This is the checks phase's long pole, so start it before memory-heavy flavor jobs.
            add_job "test" 650 "$(command_string "$LUA" test.lua)" 100 ;;
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
