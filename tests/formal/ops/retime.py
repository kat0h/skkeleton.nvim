# .cast のコマの時刻を付け直す: 普通 1.5 秒、違反のコマ 3 秒
import json, sys
for path in sys.argv[1:]:
    lines = open(path, encoding="utf-8").read().splitlines(); t = 0.0
    ev = [json.loads(l) for l in lines[1:] if l.strip()]
    for e in ev: e[0] = round(t, 3); t += 3.0 if "41m ✗" in e[2] else 1.5
    with open(path, "w", encoding="utf-8") as f:
        f.write(lines[0] + "\n"); [f.write(json.dumps(e, ensure_ascii=False) + "\n") for e in ev]
