#!/usr/bin/env python3
"""Compare two canonical composed-read dumps (A = this tree, B = the -pi sibling).

Historical: this comparator ran against the retired independent `-pi` implementation and
caught the Era-gating / era-frozen-constants / Titan Reforged defect chain. The ongoing
regression gate is golden.py (A vs committed per-entity hashes); this file and dump_b.lua
stay as the record of how the two-implementation comparison was driven.

Usage: python3 tools/differential/compare.py <a.tsv> <b.tsv>

Classifies divergences:
  ID_ONLY_IN_A / ID_ONLY_IN_B  - whole entities present on one side only
  EMPTY_STRING                 - one side reads "" where the other reads nothing
  NIL_VS_ABSENT                - non-empty value on one side, absent on the other
  VALUE                        - both sides present, different canonical value

Everything except EMPTY_STRING is unexpected after ADR 0003; coordinates and
zero-valued numerics are supposed to match exactly.
"""
import sys
from collections import defaultdict


def load(path):
    values = {}
    ids = defaultdict(set)
    with open(path, "rb") as f:
        for line in f:
            parts = line.rstrip(b"\r\n").split(b"\t", 3)
            if len(parts) != 4:
                continue
            etype, eid, field, value = parts
            values[(etype, eid, field)] = value
            ids[etype].add(eid)
    return values, ids


def main():
    a_path, b_path = sys.argv[1], sys.argv[2]
    a, a_ids = load(a_path)
    b, b_ids = load(b_path)

    classes = defaultdict(list)

    only_a_ids = {t: a_ids[t] - b_ids.get(t, set()) for t in a_ids}
    only_b_ids = {t: b_ids[t] - a_ids.get(t, set()) for t in b_ids}
    for t, s in only_a_ids.items():
        for eid in sorted(s, key=lambda x: int(x)):
            classes["ID_ONLY_IN_A"].append((t, eid, b"-", b"<entity>", b""))
    for t, s in only_b_ids.items():
        for eid in sorted(s, key=lambda x: int(x)):
            classes["ID_ONLY_IN_B"].append((t, eid, b"-", b"", b"<entity>"))
    skip_a = {(t, i) for t, s in only_a_ids.items() for i in s}
    skip_b = {(t, i) for t, s in only_b_ids.items() for i in s}

    both = 0
    for key, av in a.items():
        t, eid, field = key
        if (t, eid) in skip_a:
            continue
        bv = b.get(key)
        if bv is None:
            cls = "EMPTY_STRING" if av == b'""' else "NIL_VS_ABSENT"
            classes[cls].append((t, eid, field, av, b"<absent>"))
        elif av != bv:
            classes["VALUE"].append((t, eid, field, av, bv))
            both += 1
        else:
            both += 1
    for key, bv in b.items():
        t, eid, field = key
        if (t, eid) in skip_b:
            continue
        if key not in a:
            cls = "EMPTY_STRING" if bv == b'""' else "NIL_VS_ABSENT"
            classes[cls].append((t, eid, field, b"<absent>", bv))

    print(f"A lines: {len(a):,}   B lines: {len(b):,}   compared both-present: {both:,}")
    for t in sorted(a_ids):
        print(f"  {t.decode()}: A ids {len(a_ids[t]):,}  B ids {len(b_ids.get(t, set())):,}")

    total_div = sum(len(v) for v in classes.values())
    print(f"\nDivergences: {total_div:,}")
    for cls in sorted(classes):
        rows = classes[cls]
        by_field = defaultdict(int)
        for t, eid, field, _, _ in rows:
            by_field[(t, field)] += 1
        print(f"\n[{cls}] {len(rows):,}")
        for (t, field), n in sorted(by_field.items(), key=lambda kv: -kv[1])[:8]:
            print(f"    {t.decode()}.{field.decode()}: {n:,}")
        for t, eid, field, av, bv in rows[:3]:
            print(f"    sample {t.decode()} {eid.decode()} {field.decode()}")
            print(f"      A: {av[:140].decode('utf-8', 'replace')}")
            print(f"      B: {bv[:140].decode('utf-8', 'replace')}")

    sys.exit(0 if total_div == 0 else 1)


if __name__ == "__main__":
    main()
