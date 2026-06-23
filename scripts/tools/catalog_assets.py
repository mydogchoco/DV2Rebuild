"""Phase 0: catalog the DV2 raw asset repo -> docs/asset_inventory.md.

Read-only over DV2/. Produces a category/count/coverage overview so we know
what graphics back which game entities (dragons, monsters, skills, ...).
"""
import os, glob, re, json, sys
from collections import Counter, defaultdict

ROOT = "DV2"
OUT = "docs/asset_inventory.md"

def rel(p): return p.replace("\\", "/")

# 1) extension census (exclude .git)
ext = Counter()
total_bytes = 0
for dp, dn, fn in os.walk(ROOT):
    if ".git" in dp.split(os.sep):
        continue
    for f in fn:
        e = f.rsplit(".", 1)[-1].lower() if "." in f else "(none)"
        ext[e] += 1
        try: total_bytes += os.path.getsize(os.path.join(dp, f))
        except OSError: pass

# 2) ID coverage for dragons / monsters / skills
def ids_from_dirs(base, pat):
    out = set()
    if not os.path.isdir(base): return out
    for name in os.listdir(base):
        m = re.match(pat, name)
        if m: out.add(int(m.group(1)))
    return out

dragon_ids = ids_from_dirs(f"{ROOT}/480/dragon", r"dragon_(\d+)(?:[._]|$)")
monster_ids = ids_from_dirs(f"{ROOT}/480/monster", r"^(\d+)$")

# dragon variant coverage (baby/child/adult/critical/e)
variants = Counter()
for f in glob.glob(f"{ROOT}/480/dragon/dragon_*_spine.spine_json"):
    name = os.path.basename(f)
    for v in ("baby", "child", "adult", "e_critical", "critical", "e"):
        if f"_{v}_spine" in name:
            variants[v] += 1; break
    else:
        variants["(base)"] += 1

# skill icons
skill_ids = set()
sp = f"{ROOT}/480/skill.img_plist"
if os.path.exists(sp):
    for m in re.finditer(r"skill/(\d+)\.png", open(sp, encoding="utf-8", errors="ignore").read()):
        skill_ids.add(int(m.group(1)))

# 3) top-level 480 categories
cats = []
base480 = f"{ROOT}/480"
if os.path.isdir(base480):
    for name in sorted(os.listdir(base480)):
        p = os.path.join(base480, name)
        if os.path.isdir(p):
            n = sum(len(fs) for _, _, fs in os.walk(p))
            cats.append((name, n))

def span(s):
    return f"{min(s)}~{max(s)} ({len(s)}개)" if s else "—"

with open(OUT, "w", encoding="utf-8") as o:
    w = o.write
    w("# 에셋 인벤토리 (Phase 0 자동 카탈로깅)\n\n")
    w("> `scripts/tools/catalog_assets.py`로 생성. 원본: `DV2/` (읽기 전용).\n\n")
    w(f"- 총 용량(.git 제외): **{total_bytes/1024/1024:.0f} MB**\n\n")
    w("## 파일 포맷 분포\n\n| 확장자 | 개수 |\n|---|---|\n")
    for e, c in ext.most_common():
        w(f"| {e} | {c} |\n")
    w("\n## 엔티티 ID 커버리지\n\n")
    w(f"- 드래곤 ID: {span(dragon_ids)}\n")
    w(f"- 몬스터 ID: {span(monster_ids)}\n")
    w(f"- 스킬 아이콘 ID: {span(skill_ids)}\n\n")
    w("### 드래곤 spine 변형별 개수\n\n| 변형 | 개수 |\n|---|---|\n")
    for v, c in variants.most_common():
        w(f"| {v} | {c} |\n")
    w("\n## 480/ 카테고리별 파일 수\n\n| 카테고리 | 파일 수 |\n|---|---|\n")
    for name, n in cats:
        w(f"| {name} | {n} |\n")
    w("\n## 메모\n\n")
    w("- Spine 포맷: 구버전(2.0/2.1/3.0/3.5 혼재) — `analyze_spine.py` 참고.\n")
    w("- 게임플레이 수치 데이터는 에셋에 없음(역설계 대상).\n")

print(f"wrote {OUT}")
print("dragon ids:", span(dragon_ids))
print("monster ids:", span(monster_ids))
print("skill ids:", span(skill_ids))
print("variants:", dict(variants))
