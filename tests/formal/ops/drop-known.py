# spec.lua の M.known から、指定した issue の項目を外す: drop-known.py <spec.lua> 27 32 ...
import re, sys
p = sys.argv[1]; fixed = {"#" + n for n in sys.argv[2:]}
lines = open(p, encoding="utf-8").read().split("\n"); out, i = [], 0
while i < len(lines):
    L = lines[i]
    if L.startswith("M.known[#M.known + 1] = {") or L.startswith("for _, property in ipairs({"):
        endtok = "}" if L.startswith("M.known") else "end"; j = i
        while lines[j] != endtok: j += 1
        m = re.search(r'reason = "(#\d+):', "\n".join(lines[i:j + 1]))
        if m and m.group(1) in fixed:
            while out and out[-1].startswith("--"): out.pop()
            i = j + 1
            if i < len(lines) and lines[i] == "" and out and out[-1] == "": i += 1
            continue
    out.append(L); i += 1
open(p, "w", encoding="utf-8").write("\n".join(out))
