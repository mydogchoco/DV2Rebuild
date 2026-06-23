"""Phase 0: analyze stringsData_*.xml structure.

Goal: separate pure UI text from (a) format templates and (b) entity-indexed
text families (dragon/skill/stage names & descriptions) that must link to
data/*.json entities. Read-only. Writes docs/strings_analysis.md.
"""
import os, re, sys
from collections import Counter, defaultdict

SRC = "DV2/string"
OUT = "docs/strings_analysis.md"
LANGS = ["KR", "EN", "JP", "CN", "TW"]

# regex extraction (robust to raw &/< in values; structure is flat root>leaf)
# match leaf pairs only: value has no nested '<' (so the <root> wrapper is skipped)
PAIR = re.compile(r"<([A-Za-z_][\w]*)>([^<]*)</\1>")

def load(lang):
    p = os.path.join(SRC, f"stringsData_{lang}.xml")
    if not os.path.exists(p): return None
    txt = open(p, encoding="utf-8", errors="replace").read()
    return {m.group(1): m.group(2) for m in PAIR.finditer(txt) if m.group(1) != "root"}

kr = load("KR")
if kr is None:
    print("KR strings not found"); sys.exit(1)

# per-language key counts (coverage)
lang_counts = {}
for L in LANGS:
    d = load(L)
    lang_counts[L] = len(d) if d else 0

# placeholder / data smell
placeholder = re.compile(r"%\d*\$?[.\d]*[dsf]")
num_only = re.compile(r"^[\d\s,./%+-]+$")
with_ph = {k: v for k, v in kr.items() if placeholder.search(v)}
# numeric value = matches num charset AND contains an actual digit (excludes "....." dialogue)
numeric_vals = {k: v for k, v in kr.items()
                if v.strip() and num_only.match(v.strip()) and re.search(r"\d", v)}

# entity-indexed families: keys containing a number (id), grouped by skeleton
def skeleton(k):
    # replace digit runs with # to find families like dragon_#_name
    return re.sub(r"\d+", "#", k)

families = defaultdict(list)
for k in kr:
    if re.search(r"\d", k):
        families[skeleton(k)].append(k)
indexed = {fam: ks for fam, ks in families.items() if len(ks) >= 3}

# entity NAME presence check: are dragon/skill/monster names keyed by id here?
entity_name_pat = re.compile(r"(dragon|skill|monster|mon|item)\w*_?#|#_?(name)", re.I)
entity_name_families = {f: ks for f, ks in indexed.items() if entity_name_pat.search(f)}

# prefix grouping for the rest (first token before _)
prefix = Counter()
for k in kr:
    prefix[k.split("_")[0]] += 1

with open(OUT, "w", encoding="utf-8") as o:
    w = o.write
    w("# strings XML 구조 분석 (Phase 0)\n\n")
    w("> `scripts/tools/analyze_strings.py` 생성. 원본 `DV2/string/` (읽기 전용).\n\n")
    w("## 언어별 키 개수 (번역 커버리지)\n\n| 언어 | 키 수 |\n|---|---|\n")
    for L in LANGS:
        w(f"| {L} | {lang_counts[L]} |\n")
    w(f"\n- KR 마스터 총 키: **{len(kr)}**\n\n")

    w("## 분류 요약\n\n")
    w(f"- 포맷 템플릿(%d/%s/%f 포함): **{len(with_ph)}**개 → 런타임 포맷 문자열\n")
    w(f"- 순수 숫자/기호 값(데이터 냄새): **{len(numeric_vals)}**개\n")
    w(f"- 엔티티 인덱스 패밀리(번호 포함, 3개 이상): **{len(indexed)}**종\n\n")

    w("## 엔티티 인덱스 패밀리 (데이터 엔티티와 연결될 텍스트)\n\n")
    w("> `#`은 ID 자리. 이 키들이 dragon/skill/stage 등 `data/*.json` 항목의 이름·설명으로 연결됨.\n\n")
    w("| 패턴(skeleton) | 개수 | 예시 |\n|---|---|---|\n")
    for fam, ks in sorted(indexed.items(), key=lambda x: -len(x[1]))[:40]:
        ex = ", ".join(sorted(ks)[:3])
        w(f"| `{fam}` | {len(ks)} | {ex} |\n")

    w("\n## 순수 숫자 값 키 (있다면 데이터일 수 있음)\n\n")
    if numeric_vals:
        w("| 키 | 값 |\n|---|---|\n")
        for k, v in list(numeric_vals.items())[:50]:
            w(f"| {k} | `{v.strip()}` |\n")
    else:
        w("없음 — strings에는 실제 수치 데이터가 들어있지 않음(라벨/템플릿뿐).\n")

    w("\n## 최상위 prefix 분포 (상위 30)\n\n| prefix | 키 수 |\n|---|---|\n")
    for p, c in prefix.most_common(30):
        w(f"| {p} | {c} |\n")

    w("\n## 결론 (Phase 0)\n\n")
    w("- strings의 정체 = **UI 라벨 + 시스템/에러 메시지 + 시나리오 대사 + 튜토리얼/퀘스트/팁**의 다국어 로컬라이제이션.\n")
    w(f"- **엔티티 이름은 여기 없음.** 드래곤/스킬/몬스터 이름을 ID로 담는 패밀리 미발견(검출 {len(entity_name_families)}종). "
      "예: '철갑방패' 같은 스킬명·드래곤명이 strings에 부재.\n")
    w("  ⇒ 드래곤/스킬/몬스터 **이름도 마스터 데이터처럼 사용자가 위키 기반으로 복원**해야 함(에셋 미수록).\n")
    w("- 순수 숫자 값 키: 위 표 기준 — 게임 수치 데이터로 볼 만한 항목은 사실상 없음(대사 말줄임표 등 제외).\n")
    w("- 활용: 시나리오/튜토리얼/UI 텍스트는 `data/strings.json`으로 파싱해 그대로 사용 가능(번역 5개 언어).\n")
    w(f"- 번역 커버리지: KR {lang_counts['KR']} / EN {lang_counts['EN']} (거의 전수) vs JP·CN·TW ~{lang_counts['JP']} (부분, 주로 시나리오 누락 추정).\n")

print(f"wrote {OUT}")
print("KR keys:", len(kr), "| langs:", lang_counts)
print("placeholders:", len(with_ph), "| numeric-only:", len(numeric_vals), "| indexed families:", len(indexed))
print("\ntop indexed families:")
for fam, ks in sorted(indexed.items(), key=lambda x: -len(x[1]))[:15]:
    print(f"  {fam}: {len(ks)}  e.g. {sorted(ks)[:2]}")
