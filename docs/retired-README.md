# .retired

Prototypes QuestieTDB was mined from. **Reference material only — never a build input.**

Everything worth keeping has been ported into QuestieTDB. These folders are kept because
retiring should be reversible and because they are the only other place some of this reasoning
is written down; they are not kept because anything still needs them.

Copy this file to `.retired/README.md` when running the runbook in
`QuestieTDB/docs/retiring-the-prototypes.md`.

## Do not build on `Getters/data/*.lua-table`

That is `GetterDB`'s intermediate output, and **corrections are already applied to it** by the
pipeline QuestieTDB replaces. Consuming it would double-apply corrections from the wrong
system. QuestieTDB goes raw data → corrections → TOC in one pass, reading Questie's tracked
source files directly.

QuestieTDB's test suite fails the build if any of its inputs so much as names a path in here —
see the `no-prototype-inputs` suite in `QuestieTDB/test.lua`.

## `Getters/GetterDB` has no remote

It is a nested git repository that exists only on the machine it was written on, and it holds
the serializer and the corrections registry QuestieTDB was built from. Being in `.retired`
protects it from a cleanup; it does not protect it from machine loss.

**Push it somewhere off-machine.**

## What was taken from each

| | |
| --- | --- |
| `Getters/GetterDB` | the serializer (`Meta/DumpFunctions.lua`), the corrections registry (`Corrections/Corrections.lua`), and the constant tables the correction files reference |
| `toc-database` | the config-driven pipeline shape, chunked TOC emission (`src/lib.lua`), round-trip verification, and the decoder test |

The full accounting, including what was deliberately rejected and why, is in
`QuestieTDB/docs/retiring-the-prototypes.md`.
