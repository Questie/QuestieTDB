#!/usr/bin/env python3
"""QuestieTDB vs Questie's compiler — the reference-implementation differential.

DESIGN.md phase 6 called for a compiled/TOC differential and gave it a deadline: the
compiler is the reference implementation, so its behaviour must be captured before it is
deleted. `golden.py` snapshots QuestieTDB's *own* composed reads, so it can only catch
drift from itself; this gate compares against the thing QuestieTDB replaces.

Both sides are read through their public per-field surface — `Entity.Get(id, field)` here,
`QuestieDB.Query<Type>Single(id, field)` there — so what is compared is what the ~290
consumer call sites actually observe, overrides and all.

Usage (cwd = the QuestieTDB repo root):

    python3 tools/differential/compiler_diff.py Vanilla
    python3 tools/differential/compiler_diff.py all --questie=../Questie
    python3 tools/differential/compiler_diff.py Vanilla --season=SoD
    python3 tools/differential/compiler_diff.py all --update-baseline
    python3 tools/differential/compiler_diff.py Vanilla --self-check

Divergence classes:
    ID_ONLY_IN_TDB / ID_ONLY_IN_COMPILER  whole entities present on one side only
    EMPTY_VS_ABSENT                       one side reads a value, the other reads nothing
    VALUE                                 both present, different canonical value

Known, accepted divergences are recorded per flavor under compiler-baseline/ as
(entityType, field, class, count). A run fails on a class that is new or has grown, so
this is a regression gate rather than a wall of known noise — the same discipline
validators/baseline uses. Reducing a count is also a failure, because it means the
baseline is stale and should be re-recorded deliberately.

`--self-check` perturbs one value in the QuestieTDB dump in memory and requires exactly one
extra divergence to appear — a gate that cannot fail is not a gate.

Requires `bit32` on the Lua path for Questie's compiler; the script picks it up from
luarocks automatically when it is not already visible.
"""
import os
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASELINE_DIR = os.path.join(ROOT, "tools", "differential", "compiler-baseline")
DUMP_DIR = os.path.join(ROOT, ".out", "differential")
FLAVORS = ["Vanilla", "TBC", "Wrath", "Cata", "Mists"]
SAMPLES = 3


def lua_env():
    """Questie's apiMocks require `bit32`, which luarocks installs outside the default path."""
    env = os.environ.copy()
    probe = subprocess.run(["lua5.1", "-e", "require('bit32')"], capture_output=True)
    if probe.returncode == 0:
        return env
    paths = subprocess.run(["luarocks", "path", "--lua-version=5.1"],
                           capture_output=True, text=True)
    if paths.returncode != 0:
        return env
    for line in paths.stdout.splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[len("export "):]
        if "=" in line:
            key, value = line.split("=", 1)
            env[key] = value.strip().strip("'").strip('"')
    return env


def run(cmd, cwd, env, label):
    result = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    if result.returncode != 0:
        sys.stderr.write(result.stdout.decode("utf-8", "replace"))
        sys.exit("%s failed (exit %d)" % (label, result.returncode))
    return result.stdout.decode("utf-8", "replace")


def dump_both(flavor, questie, lua, season):
    os.makedirs(DUMP_DIR, exist_ok=True)
    tdb = os.path.join(DUMP_DIR, "tdb-%s.tsv" % flavor)
    comp = os.path.join(DUMP_DIR, "compiler-%s.tsv" % flavor)
    env = lua_env()

    run([lua, "tools/differential/dump_a.lua", flavor, tdb], ROOT, env, "QuestieTDB dump")

    questie_root = questie if os.path.isabs(questie) else os.path.join(ROOT, questie)
    if not os.path.isdir(questie_root):
        sys.exit("Questie checkout not found: %s (pass --questie=<path>)" % questie_root)
    script = os.path.join(ROOT, "tools", "differential", "dump_compiler.lua")
    cmd = [lua, script, flavor, comp]
    if season:
        cmd.append("--season=%s" % season)
    run(cmd, questie_root, env, "compiler dump")
    return tdb, comp


def load(path):
    values, ids = {}, defaultdict(set)
    with open(path, "rb") as handle:
        for line in handle:
            parts = line.rstrip(b"\r\n").split(b"\t", 3)
            if len(parts) != 4:
                continue
            etype, eid, field, value = parts
            values[(etype, eid, field)] = value
            ids[etype].add(eid)
    return values, ids


def classify(tdb_path, comp_path):
    a, a_ids = load(tdb_path)
    b, b_ids = load(comp_path)
    rows = []

    only_a = {t: a_ids[t] - b_ids.get(t, set()) for t in a_ids}
    only_b = {t: b_ids[t] - a_ids.get(t, set()) for t in b_ids}
    for t, s in only_a.items():
        for eid in s:
            rows.append(("ID_ONLY_IN_TDB", t, eid, b"-", b"<entity>", b"<absent>"))
    for t, s in only_b.items():
        for eid in s:
            rows.append(("ID_ONLY_IN_COMPILER", t, eid, b"-", b"<absent>", b"<entity>"))
    skip_a = {(t, i) for t, s in only_a.items() for i in s}
    skip_b = {(t, i) for t, s in only_b.items() for i in s}

    compared = 0
    for key, av in a.items():
        t, eid, field = key
        if (t, eid) in skip_a:
            continue
        bv = b.get(key)
        if bv is None:
            rows.append(("EMPTY_VS_ABSENT", t, eid, field, av, b"<absent>"))
        else:
            compared += 1
            if av != bv:
                rows.append(("VALUE", t, eid, field, av, bv))
    for key, bv in b.items():
        t, eid, field = key
        if (t, eid) in skip_b or key in a:
            continue
        rows.append(("EMPTY_VS_ABSENT", t, eid, field, b"<absent>", bv))

    return rows, compared, a_ids, b_ids


def summarize(rows):
    """(entityType, field, class) -> count. The unit the baseline records."""
    counts = defaultdict(int)
    for cls, t, _eid, field, _av, _bv in rows:
        counts[(t.decode(), field.decode(), cls)] += 1
    return counts


def baseline_path(flavor):
    return os.path.join(BASELINE_DIR, "%s.tsv" % flavor)


#: Every baseline row carries why it is there, so a green run can never be mistaken for
#: "no known problems". Only POLICY rows are permanent.
REASON_POLICY = "POLICY"        # correct and permanent; the consumer closes it
REASON_FIX = "FIX"              # decided: we will match Questie; not implemented yet
REASON_OPEN = "OPEN"            # known divergence, disposition undecided
REASON_UNTRIAGED = "UNTRIAGED"  # nobody has looked at this yet
TEMPORARY_REASONS = (REASON_FIX, REASON_OPEN, REASON_UNTRIAGED)


def read_baseline(flavor):
    """-> {(etype, field, cls): (count, reason)} or None."""
    path = baseline_path(flavor)
    if not os.path.exists(path):
        return None
    rows = {}
    with open(path) as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) == 4:  # pre-reason format
                etype, field, cls, count = parts
                reason = REASON_UNTRIAGED
            else:
                etype, field, cls, count, reason = parts[:5]
            rows[(etype, field, cls)] = (int(count), reason)
    return rows


def write_baseline(flavor, counts, existing):
    """Refresh counts while PRESERVING the reason already recorded for a row.

    A refresh must never silently downgrade a curated judgement to a guess, so an existing
    reason wins and only genuinely new rows land as UNTRIAGED - which is loud on purpose.
    """
    os.makedirs(BASELINE_DIR, exist_ok=True)
    existing = existing or {}
    with open(baseline_path(flavor), "w") as handle:
        handle.write("# Known QuestieTDB-vs-compiler divergences for %s.\n" % flavor)
        handle.write("#\n")
        handle.write("# This is a to-do list, not an approval. Only %s rows are permanent;\n"
                     % REASON_POLICY)
        handle.write("# every other row is work we still owe. Dispositions and rationale live in\n")
        handle.write("# docs/questie-handover.md.\n")
        handle.write("#\n")
        handle.write("# Refresh with: compiler_diff.py %s --update-baseline\n" % flavor)
        handle.write("# entityType\tfield\tclass\tcount\treason\n")
        for key, n in sorted(counts.items()):
            reason = existing.get(key, (None, REASON_UNTRIAGED))[1]
            handle.write("%s\t%s\t%s\t%d\t%s\n" % (key[0], key[1], key[2], n, reason))


def report(flavor, rows, compared, a_ids, b_ids, counts, baseline):
    print("=" * 78)
    print("%s — QuestieTDB vs Questie compiler" % flavor)
    print("=" * 78)
    for t in sorted(a_ids):
        name = t.decode()
        print("  %-7s TDB ids %7s   compiler ids %7s"
              % (name, format(len(a_ids[t]), ","), format(len(b_ids.get(t, set())), ",")))
    print("  compared (present on both sides): %s" % format(compared, ","))
    print("  divergences: %s" % format(len(rows), ","))

    by_class = defaultdict(list)
    for row in rows:
        by_class[row[0]].append(row)

    for cls in sorted(by_class):
        print("\n[%s] %s" % (cls, format(len(by_class[cls]), ",")))
        per_field = defaultdict(list)
        for _c, t, eid, field, av, bv in by_class[cls]:
            per_field[(t.decode(), field.decode())].append((eid, av, bv))
        for (etype, field), hits in sorted(per_field.items(), key=lambda kv: -len(kv[1])):
            print("    %s.%s: %s" % (etype, field, format(len(hits), ",")))
            for eid, av, bv in sorted(hits)[:SAMPLES]:
                print("      id %s" % eid.decode())
                print("        tdb      : %s" % av[:150].decode("utf-8", "replace"))
                print("        compiler : %s" % bv[:150].decode("utf-8", "replace"))

    if baseline is None:
        print("\nNo baseline recorded for %s — run with --update-baseline to accept these."
              % flavor)
        return 1 if rows else 0

    new, grown, shrunk = [], [], []
    for key, n in sorted(counts.items()):
        row = baseline.get(key)
        if row is None:
            new.append((key, n))
        elif n > row[0]:
            grown.append((key, row[0], n))
        elif n < row[0]:
            shrunk.append((key, row[0], n))
    gone = [(k, v[0]) for k, v in sorted(baseline.items()) if k not in counts]

    print("\n--- against baseline ---")
    for key, n in new:
        print("  NEW      %s.%s [%s] %d" % (key[0], key[1], key[2], n))
    for key, was, n in grown:
        print("  GREW     %s.%s [%s] %d -> %d" % (key[0], key[1], key[2], was, n))
    for key, was, n in shrunk:
        print("  SHRANK   %s.%s [%s] %d -> %d" % (key[0], key[1], key[2], was, n))
    for key, was in gone:
        print("  RESOLVED %s.%s [%s] %d -> 0" % (key[0], key[1], key[2], was))

    # Outstanding work, always printed. A gate that only says pass/fail lets a known defect
    # sit in a baseline for a year; this makes the debt visible on every single run.
    by_reason = defaultdict(lambda: [0, 0])
    for key, n in counts.items():
        reason = baseline.get(key, (0, REASON_UNTRIAGED))[1]
        by_reason[reason][0] += 1
        by_reason[reason][1] += n
    print("\n--- outstanding ---")
    for reason in sorted(by_reason):
        rows, total = by_reason[reason]
        label = "permanent" if reason == REASON_POLICY else "TO FIX"
        print("  %-10s %2d classes  %9s divergences   (%s)"
              % (reason, rows, format(total, ","), label))
    owed = sum(by_reason[r][1] for r in TEMPORARY_REASONS if r in by_reason)
    if owed:
        print("  => %s divergences still owed before this gate can reach zero."
              % format(owed, ","))

    if not (new or grown or shrunk or gone):
        print("  no regressions - every divergence is accounted for in the baseline")
        return 0
    print("\nBaseline mismatch. Fix the regression, or re-record with --update-baseline"
          " and commit the diff for review.")
    return 1


def run_self_check(flavor, tdb_path, comp_path, baseline_divergences):
    """Corrupt one agreeing value and require exactly one new divergence.

    The perturbation targets a field the two sides already agree on, so the detection can
    only come from the comparison itself. Done on a copy in a temp file rather than in the
    dump, so a failed self-check cannot leave a poisoned artifact behind.
    """
    import tempfile

    b, _ = load(comp_path)
    target = None
    with open(tdb_path, "rb") as handle:
        for offset, line in enumerate(handle):
            parts = line.rstrip(b"\r\n").split(b"\t", 3)
            if len(parts) == 4 and b.get((parts[0], parts[1], parts[2])) == parts[3]:
                target = offset
                break
    if target is None:
        print("  self-check: no agreeing value to perturb — cannot self-prove")
        return 1

    handle = tempfile.NamedTemporaryFile(mode="wb", suffix=".tsv", delete=False)
    try:
        with open(tdb_path, "rb") as source:
            for offset, line in enumerate(source):
                if offset == target:
                    parts = line.rstrip(b"\r\n").split(b"\t", 3)
                    parts[3] = b'"__self_check_perturbation__"'
                    handle.write(b"\t".join(parts) + b"\n")
                else:
                    handle.write(line)
        handle.close()
        rows, _compared, _a, _b = classify(handle.name, comp_path)
        delta = len(rows) - baseline_divergences
        if delta == 1:
            print("  self-check: perturbation detected exactly once — gate is live")
            return 0
        print("  self-check: expected exactly 1 new divergence, saw %d — GATE IS NOT LIVE"
              % delta)
        return 1
    finally:
        os.unlink(handle.name)


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)

    targets, questie, lua, season = [], "../Questie", "lua5.1", None
    update = False
    self_check = False
    for value in args:
        if value.startswith("--questie="):
            questie = value.split("=", 1)[1]
        elif value.startswith("--lua="):
            lua = value.split("=", 1)[1]
        elif value.startswith("--season="):
            season = value.split("=", 1)[1]
        elif value == "--update-baseline":
            update = True
        elif value == "--self-check":
            self_check = True
        elif value.startswith("--"):
            sys.exit("Unknown option: %s" % value)
        elif value == "all":
            targets.extend(FLAVORS)
        elif value in FLAVORS:
            targets.append(value)
        else:
            sys.exit("Unknown flavor: %s" % value)

    if not targets:
        targets = ["Vanilla"]

    status = 0
    for flavor in targets:
        tdb_path, comp_path = dump_both(flavor, questie, lua, season)
        rows, compared, a_ids, b_ids = classify(tdb_path, comp_path)
        counts = summarize(rows)
        if update:
            write_baseline(flavor, counts, read_baseline(flavor))
            print("%s: recorded %d baseline entries (%s divergences)"
                  % (flavor, len(counts), format(len(rows), ",")))
            continue
        status |= report(flavor, rows, compared, a_ids, b_ids, counts, read_baseline(flavor))
        if self_check:
            status |= run_self_check(flavor, tdb_path, comp_path, len(rows))
        print()
    sys.exit(status)


if __name__ == "__main__":
    main()
