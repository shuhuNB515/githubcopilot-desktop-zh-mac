
import json, glob, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
out = {}
for f in sorted(glob.glob("src/dict-*.tsv")):
    for line in open(f, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            print("BAD:", f, repr(line[:60])); continue
        en, zh = parts[0], parts[1]
        if not en or not zh:
            print("EMPTY:", f, repr(line[:60])); continue
        if en in out and out[en] != zh:
            print("DUP:", en)
        out[en] = zh
# 允许用户自定义词典覆盖
if os.path.exists("src/dict-user.tsv"):
    for line in open("src/dict-user.tsv", encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"): continue
        p = line.split("\t")
        if len(p) == 2: out[p[0]] = p[1]
json.dump(out, open("runtime/dict.json","w"), ensure_ascii=False, indent=0)
print("entries:", len(out), "bytes:", os.path.getsize("runtime/dict.json"))
