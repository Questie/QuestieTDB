# `-pi` idea: the self-describing artifact

`-pi` emitted its schema **into the TOC** and re-validated it at load, so the artifact
carried its own contract:

    ## X-ENTITY-TYPE-COUNT: 4
    ## X-ENTITY-TYPE-1: Quest,QuestDB,QUEST-
    ## X-QUEST-FIELD-COUNT: 36
    ## X-QUEST-FIELD-1: name,string
    ## X-LOCALE-COUNT: 9
    ## X-CONTRACT-VERSION: 1

The baked reader parsed the manifests and asserted them against runtime config before
decoding anything (`src/read/baked.lua:71-96` — entity name/global/prefix pattern-matched
and compared field by field), and the generator's stated payoff sits at `generate.lua:126`:
*"The type manifest lets the shared baked reader add a further type without code changes."*
In `-pi`, a schema change meant regenerating **data**; here it means regenerating **code**
(`src/meta/*Meta.lua`).

## Why this repo did not adopt it

- The reader and the artifact ship in **one addon folder, released together** — the skew
  the manifests tolerate mostly cannot occur.
- The one real skew case (CI-built artifacts bootstrapped into an older clone) is already
  covered by `X-Contract-Version` plus the CI schema-drift gate
  (`git diff --exit-code src/meta/`).
- The manifests cost ~90 reserved keys and a load-time parse for a guarantee the
  packaging model makes redundant.

## Adopt when

Any of these becomes true:

1. Baked artifacts are distributed **separately from the reader** (data-only releases, or
   l10n split into its own addon) — then reader/artifact skew is real and in-band schema
   is the correct defense.
2. **Third-party readers** consume the TOC directly without this repo's `src/meta/`
   modules — the artifact becomes the only place the contract can live.
3. Bootstrap-into-older-clone skew starts appearing in the wild despite the contract
   check — the manifests localize the mismatch to a named field instead of a version
   number.

The `-pi` reference implementation (reader and emitter) is small and clean; port the
*pattern*, not the code — key casing and prefixes differ.

Status: **rejected with conditions** — revisit at any packaging change that separates
data from reader.
