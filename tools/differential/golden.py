#!/usr/bin/env python3
"""A-vs-golden regression gate over composed public reads.

History: tools/differential/ was built to compare this tree against the independent
sibling implementation (`Questie-toc-pi`), and that comparison caught the Era-gating,
era-frozen-constants, and Titan Reforged defect chain that this tree's own verify and
equivalence gates are structurally blind to (generator and source mode share the same
manifest, so they agree with each other even when both are wrong). With the sibling
retired, the same dump feeds this gate instead: composed reads are hashed per entity and
compared against a committed snapshot, so "consistently wrong on both sides of the seam"
still has an independent witness.

Usage (cwd anywhere; paths resolve from the repo root):

    python3 tools/differential/golden.py check <Flavor> [--lua=lua5.1] [--self-check]
    python3 tools/differential/golden.py refresh <Flavor>|all [--lua=lua5.1]

`check` dumps the flavor's composed reads (tools/differential/dump_a.lua, source mode,
default persona) and compares per-entity hashes against tools/differential/golden/. Any
difference exits nonzero. Two legitimate responses to a failure:

  - an unintended regression: fix the change;
  - an INTENTIONAL data change (upstream re-sync, new correction): refresh the snapshot,
    review the diff, and commit it alongside the change.

`--self-check` then perturbs one entity's hash in memory and requires exactly one
detection - a gate that cannot fail is not a gate.

Hash: sha256 over the entity's canonical field lines (sorted, newline-joined), truncated
to 16 hex characters. One golden line per (entityType, id).
"""
import hashlib
import os
import subprocess
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GOLDEN_DIR = os.path.join(ROOT, "tools", "differential", "golden")
DUMP_DIR = os.path.join(ROOT, ".out", "differential")
FLAVORS = ["Vanilla", "TBC", "Wrath", "Cata", "Mists"]
SAMPLES = 5


def run_dump(flavor, lua):
    os.makedirs(DUMP_DIR, exist_ok=True)
    out = os.path.join(DUMP_DIR, "golden-dump-%s.tsv" % flavor)
    result = subprocess.run(
        [lua, "tools/differential/dump_a.lua", flavor, out],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        sys.stdout.buffer.write(result.stdout)
        sys.exit("golden: dump_a.lua failed for %s" % flavor)
    return out


def derive(dump_path):
    """(entityType, id) -> 16-hex sha256 over the entity's sorted canonical field lines."""
    per_entity = OrderedDict()
    with open(dump_path, "rb") as f:
        for line in f:
            line = line.rstrip(b"\r\n")
            parts = line.split(b"\t", 3)
            if len(parts) != 4:
                continue
            per_entity.setdefault((parts[0], parts[1]), []).append(line)
    hashes = OrderedDict()
    for key, lines in per_entity.items():
        lines.sort()
        digest = hashlib.sha256(b"\n".join(lines) + b"\n").hexdigest()[:16]
        hashes[key] = digest
    return hashes


def golden_path(flavor):
    return os.path.join(GOLDEN_DIR, "%s.tsv" % flavor)


def worktree_stamp():
    try:
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                             stdout=subprocess.PIPE).stdout.decode().strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                               stdout=subprocess.PIPE).stdout.strip()
        return sha + ("+dirty" if dirty else "")
    except OSError:
        return "unknown"


def refresh(flavor, lua):
    hashes = derive(run_dump(flavor, lua))
    os.makedirs(GOLDEN_DIR, exist_ok=True)
    with open(golden_path(flavor), "wb") as f:
        f.write(b"# QuestieTDB golden composed-read hashes - %s\n" % flavor.encode())
        f.write(b"# One line per entity: type, id, sha256/16 over its sorted canonical field lines.\n")
        f.write(b"# Produced from worktree at %s\n" % worktree_stamp().encode())
        f.write(b"# Refresh (after an INTENTIONAL data change, with review):\n")
        f.write(b"#   python3 tools/differential/golden.py refresh %s\n" % flavor.encode())
        for (etype, eid), digest in hashes.items():
            f.write(etype + b"\t" + eid + b"\t" + digest.encode() + b"\n")
    print("golden: wrote %s (%d entities)" % (os.path.relpath(golden_path(flavor), ROOT),
                                              len(hashes)))


def load_golden(flavor):
    path = golden_path(flavor)
    if not os.path.exists(path):
        sys.exit("golden: no snapshot for %s - create one with:\n"
                 "  python3 tools/differential/golden.py refresh %s" % (flavor, flavor))
    hashes = OrderedDict()
    with open(path, "rb") as f:
        for line in f:
            if line.startswith(b"#"):
                continue
            parts = line.rstrip(b"\r\n").split(b"\t")
            if len(parts) == 3:
                hashes[(parts[0], parts[1])] = parts[2].decode()
    return hashes


def diff(golden, current):
    missing = [k for k in golden if k not in current]
    extra = [k for k in current if k not in golden]
    changed = [k for k in golden if k in current and golden[k] != current[k]]
    return missing, extra, changed


def report(kind, keys):
    print("  %s: %d" % (kind, len(keys)))
    for etype, eid in keys[:SAMPLES]:
        print("    %s %s" % (etype.decode(), eid.decode()))


def check(flavor, lua, self_check):
    current = derive(run_dump(flavor, lua))
    golden = load_golden(flavor)
    missing, extra, changed = diff(golden, current)
    total = len(missing) + len(extra) + len(changed)
    print("golden %s: %d entities against %d golden, %d differences"
          % (flavor, len(current), len(golden), total))
    if total:
        report("missing (in golden, not read back)", missing)
        report("extra (read back, not in golden)", extra)
        report("changed (hash differs)", changed)
        print("\nComposed reads differ from the committed golden snapshot. Two legitimate")
        print("outcomes: an unintended regression - fix the change; or an INTENTIONAL data")
        print("change (upstream re-sync, new correction) - refresh the snapshot, review the")
        print("diff, and commit it alongside the change:")
        print("  python3 tools/differential/golden.py refresh %s" % flavor)
        sys.exit(1)
    if self_check:
        victim = next(iter(current))
        perturbed = dict(current)
        perturbed[victim] = ("0" * 16 if current[victim] != "0" * 16 else "f" * 16)
        m2, e2, c2 = diff(golden, perturbed)
        if len(m2) == 0 and len(e2) == 0 and len(c2) == 1:
            print("golden %s: self-check ok (one perturbed hash -> exactly one detection)"
                  % flavor)
        else:
            sys.exit("golden %s: SELF-CHECK FAILED - perturbation detected as %d/%d/%d "
                     "missing/extra/changed instead of 0/0/1" % (flavor, len(m2), len(e2),
                                                                 len(c2)))
    print("golden %s: PASS" % flavor)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = [a for a in sys.argv[1:] if a.startswith("--")]
    lua = os.environ.get("LUA", "lua")
    self_check = False
    for opt in opts:
        if opt.startswith("--lua="):
            lua = opt[len("--lua="):]
        elif opt == "--self-check":
            self_check = True
        else:
            sys.exit("golden: unknown option %s" % opt)
    if len(args) != 2 or args[0] not in ("check", "refresh"):
        sys.exit(__doc__)
    command, flavor = args
    if flavor != "all" and flavor not in FLAVORS:
        sys.exit("golden: unknown flavor %s (expected %s or all)"
                 % (flavor, ", ".join(FLAVORS)))
    flavors = FLAVORS if flavor == "all" else [flavor]
    if command == "refresh":
        for f in flavors:
            refresh(f, lua)
    else:
        if flavor == "all":
            sys.exit("golden: check takes one flavor (CI runs one per matrix leg)")
        check(flavor, lua, self_check)


if __name__ == "__main__":
    main()
