# TDBProbe — synthetic metadata probe addon

Answers the client-behavior questions that cannot be probed against a generated artifact
(deferred items in `docs/client-metadata-probes.md` §7). One TOC per addon means one
restart per battery; everything here fits in a single load.

**The TOC is byte-exact — never hand-edit it.** Regenerate with the Python block in the
repo history (commit that added this folder) if directives need to change.

## Install

Copy or junction this folder into the client as `Interface/AddOns/TDBProbe/`, then fully
restart the client (TOC metadata is read at client start; `/reload` is not sufficient).

## Run (via WoWDevBridge)

```
./wow-lua-bridge run 'local g=C_AddOns.GetAddOnMetadata local out={}
local function p(k) local v=g("TDBProbe",k) if v==nil then return "NIL" end return #v.."B:"..string.byte(v,1)..":"..string.byte(v,#v)..":"..v:sub(-8) end
for _, k in ipairs({"X-P-L1023","X-P-L1024","X-P-L1027","X-P-Empty","X-P-Colon-NoSpace","X-P-Marker","X-P-QMarker","X-P-InnerWs","X-P-LeadWs","X-P-TrailWs","X-P-OnlyWs","X-P-Tab"}) do out[k]=p(k) end
out.loaded = TDBProbe_Loaded
return out'
```

## What each directive answers

| Key | Line bytes | Question |
| --- | ---: | --- |
| `X-P-L1023` | 1023 | Safe side: full value returns, tail `01234567` intact? |
| `X-P-L1024` | 1024 | Boundary: which tail bytes drop first? |
| `X-P-L1027` | 1027 | Over: truncation length exactly 1023-line-bytes' worth? |
| `X-P-Empty` (trailing space) / `X-P-Colon-NoSpace` | | Empty value: `""` or `nil`? Does the colon-only form differ? |
| `X-P-Marker` `~3~` | | Marker-lookalike returned verbatim? |
| `X-P-QMarker` `~Q~test` | | `~Q~` escape sequence survives raw? |
| `X-P-InnerWs` | | Interior double-space and tab preserved? |
| `X-P-LeadWs` / `X-P-TrailWs` / `X-P-OnlyWs` / `X-P-Tab` | | Confirm trim behavior for space and tab, both edges, and whole-value whitespace |

Record results in `docs/client-metadata-probes.md` with the client build.

## CBOR transport battery (build 69547)

Answers whether a base64 blob survives a TOC line and whether the offline
`BlizzardCBOR.lua` encoder and the client's `C_EncodingUtil.DeserializeCBOR` agree on real
data. Generated on demand, never committed: the output is 2.3 MB.

Run from the QuestieTDB root:

```sh
lua5.1 tools/probe-addon/gen-cbor-probe.lua <outdir>  # quests.cbor + data.lua
uv run python tools/probe-addon/gen-cbor-probe.py \
  <outdir> tools/probe-addon/TDBProbe.toc.orig tools/probe-addon/TDBProbe.toc
cp <outdir>/data.lua tools/probe-addon/
```

`gen-cbor-probe.py` appends the CBOR directives to a copy of the byte-exact TOC, so keep
the original aside and restore it afterwards. The client-side check is in
`docs/client-metadata-probes.md` §10. On build 69547 a `/reload` re-reads TOC metadata, so
the restart note above no longer applies; it was true on 69109.
