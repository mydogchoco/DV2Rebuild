from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
DATA = REPO / "data"

KEEP = {"_cut", "_variant_rules", "_element_crystal", "_wallet",
        "_effect_progress", "_recovered", "_npc", "_slots",
        "_impl", "_total", "_partial"}
KEEP_PREFIX = ("_default_",)

MEMO_KEYS = {"note", "unused", "highlight_basis", "basis",
             "evidence", "todo", "authored"}

FILE_MEMO_KEYS = {"items.json": {"use"}}

def gd_corpus() -> str:
    out = subprocess.run(["git", "ls-files", "scripts/**/*.gd", "scripts/*.gd"],
                         cwd=REPO, capture_output=True, text=True).stdout
    parts = []
    for rel in out.split():
        p = REPO / rel
        if p.exists():
            parts.append(p.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(parts)

def strip(node, removed: list, kept_by_code: set, corpus: str, path="", extra=frozenset()):
    if isinstance(node, dict):
        for k in list(node.keys()):
            if isinstance(k, str) and k.startswith("_"):
                if k in KEEP or k.startswith(KEEP_PREFIX) or ('"%s"' % k) in corpus:
                    if ('"%s"' % k) in corpus and k not in KEEP:
                        kept_by_code.add(k)
                    strip(node[k], removed, kept_by_code, corpus, f"{path}{k}.", extra)
                    continue
                removed.append(f"{path}{k}")
                del node[k]
                continue
            if k in extra or (k in MEMO_KEYS and ('"%s"' % k) not in corpus):
                removed.append(f"{path}{k}")
                del node[k]
                continue
            strip(node[k], removed, kept_by_code, corpus, f"{path}{k}.", extra)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            strip(v, removed, kept_by_code, corpus, f"{path}[{i}].", extra)

def detect_indent(text: str):
    m = re.search(r'\n(\s+)"', text)
    return len(m.group(1)) if m else 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    corpus = gd_corpus()
    total, files = 0, 0
    kept_by_code: set[str] = set()
    for p in sorted(DATA.glob("*.json")):
        text = p.read_text(encoding="utf-8")
        try:
            doc = json.loads(text)
        except Exception as e:
            print(f"[skip] {p.name}: {e}")
            continue
        removed: list[str] = []
        strip(doc, removed, kept_by_code, corpus, "", FILE_MEMO_KEYS.get(p.name, frozenset()))
        if not removed:
            continue
        files += 1
        total += len(removed)
        if args.dry_run:
            print(f"{p.name}: {len(removed)}건  예) {removed[:3]}")
            continue
        out = json.dumps(doc, ensure_ascii=False, indent=detect_indent(text))
        p.write_text(out + "\n", encoding="utf-8", newline="\n")
        print(f"{p.name}: {len(removed)}건 정리")
    if kept_by_code:
        print(f"\n경고 — 코드가 참조해 지우지 않은 키(화이트리스트 확인 필요): {sorted(kept_by_code)}")
    print(f"\n합계 {files}파일 {total}키" + (" (dry-run)" if args.dry_run else ""))
    return 0

if __name__ == "__main__":
    sys.exit(main())
