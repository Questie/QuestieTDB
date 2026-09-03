# Offline half, part two: compress, base64, split into 1,000-char TOC lines and rewrite
# TDBProbe.toc = original directives + CBOR probe directives + file list.
import base64, sys, zlib
out, orig, toc = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(f"{out}/quests.cbor", "rb").read()
qz = base64.b64encode(zlib.compress(raw, 9)).decode()          # Zlib wrapper = method 1
qr = base64.b64encode(raw).decode()                            # uncompressed
LINE = 1000
def chunks(key, s):
    parts = [s[i:i + LINE] for i in range(0, len(s), LINE)]
    yield f"## {key}: ~{len(parts)}~"
    for i, p in enumerate(parts, 1):
        yield f"## {key}-{i}: {p}"
lines = [l for l in open(orig, encoding="utf-8").read().split("\n") if l and not l.endswith(".lua")]
lines += [
    "## X-P-B64-Sym: " + base64.b64encode(b"\xfb\xff\xbf").decode(),   # -> +/+/
    "## X-P-B64-Pad1: " + base64.b64encode(b"ab").decode(),             # -> YWI=
    "## X-P-B64-Pad2: " + base64.b64encode(b"a").decode(),              # -> YQ==
    f"## X-P-CBOR-Raw-Bytes: {len(raw)}",
]
lines += list(chunks("X-P-QZ", qz)) + list(chunks("X-P-QR", qr))
lines += ["main.lua", "data.lua"]
open(toc, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
print(f"raw={len(raw)} zlib_b64={len(qz)} ({-(-len(qz)//LINE)} lines) b64={len(qr)} ({-(-len(qr)//LINE)} lines) toc_lines={len(lines)}")
