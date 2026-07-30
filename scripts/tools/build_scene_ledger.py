"""libgame.so 심볼 → 씬 이식 원장(docs/ref/design/scene_port_ledger.md).

스켈레톤-우선 파이프라인 Phase 0. `_symbol_map.md`와 달리 **연출(render) 클래스만**
필터링해 "무엇을 이식해야 하는가"의 전수 목록을 만든다. 각 클래스에:
  - tier: 1(코어 오프라인 루프) / 2(보조 화면) / 3(폴리시·기타)
  - cut : 온라인/PvP/이벤트 = 오프라인 재구현서 제외
  - status: done(이식완료) / partial / todo
를 부여. Phase 1 일괄 디컴파일의 우선순위·범위 결정에 쓴다.

사용:  python scripts/tools/build_scene_ledger.py [so경로] > docs/ref/design/scene_port_ledger.md
"""
from __future__ import annotations
import sys
from collections import defaultdict
from so_reader import ELF, demangle, DEFAULT_SO

# 연출 클래스 판별: 리프(마지막 네임스페이스 컴포넌트)에 이 토큰이 있으면 render 클래스.
PRESENTATION_SUFFIX = (
    "Scene", "Layer", "Popup", "Dialog", "Cell", "Widget", "View", "HUD",
    "Menu", "Toast", "Alert", "Card", "Slot", "Panel", "Tab", "Btn", "Button",
    "Bar", "Icon", "Node",  # Node는 아래서 다른 힌트와 함께만 채택
)
STRONG_SCENE = ("Scene", "Layer", "Popup", "Dialog", "View", "HUD")  # 풀스크린/주요 컨테이너

# 엔진/표준 라이브러리 제외
ENGINE_PREFIXES = ("std", "__ndk1", "__cxx", "rapidjson", "google", "spine", "boost")
ENGINE_CLASS_HINTS = ("CC", "extension", "network::", "ui::", "__")

# CUT: 온라인/PvP/이벤트 (오프라인 재구현서 제외)
CUT_KEYS = (
    "Auction", "Colosseum", "Coliseum", "Arena", "Pvp", "PvP", "Friend", "Rank",
    "Guild", "Chat", "Login", "SignIn", "Mail", "Post", "Charge", "Cash", "Coupon",
    "Attend", "Invite", "Mercenary", "Merc", "Trade", "Market", "Ranking", "Event",
    "Anniversary", "Push", "Notice", "Facebook", "Kakao", "Google", "Server",
    "Network", "Http", "Coloseum",
    # 온라인 이벤트/가챠성(연도표기·룰렛·복주머니·기념) → 오프라인 재구현 제외
    "2019", "2020", "2021", "2022", "WorldRaid", "FourthRaid", "Roulette",
    "LuckyBag", "Nuri", "DragonBall", "Berna",  # Berna=에셋부재(컷 확정)
)
# Tier1: 코어 오프라인 루프
TIER1_KEYS = (
    "World", "Map", "Cave", "Nest", "Town", "Village", "Battle", "Fight",
    "Adventure", "Field", "Stage", "Dungeon", "Dragon", "Book", "Egg", "Breed",
    "Hatch", "Combine", "Evolv", "Awak", "Enchant", "Seal", "Item", "Inven",
    "Bag", "Gem", "Equip", "Skill", "Result", "Reward", "Monster", "Raid",
)
# Tier2: 보조 화면
TIER2_KEYS = (
    "Menu", "Option", "Setting", "Shop", "Store", "Gacha", "Box", "Tutorial",
    "Guide", "Level", "Title", "Load", "Intro", "Lobby", "Quest", "Mission",
    "Status", "Info", "Detail", "Select", "Confirm", "Popup", "Dialog",
)
# 이미 이식된(또는 부분 이식) 클래스 힌트 → status
DONE_HINTS = ("WorldMap", "Cave", "Town", "Battle")


def is_engine(sym) -> bool:
    if not sym.namespaces:
        return True
    if sym.namespaces[0] in ENGINE_PREFIXES:
        return True
    for h in ENGINE_CLASS_HINTS:
        if h in sym.full:
            return True
    return False


def leaf_of(sym) -> tuple[str, str]:
    ns = sym.namespaces
    if ns and ns[0] == "cocos2d":
        ns = ns[1:]
    cls = "::".join(ns) if ns else sym.member
    leaf = ns[-1] if ns else sym.member
    return cls, leaf


def is_presentation(leaf: str) -> bool:
    for suf in PRESENTATION_SUFFIX:
        if suf in leaf:
            if suf == "Node":
                # Node 단독은 너무 광범위 → 다른 render 힌트가 함께 있을 때만
                return any(s in leaf for s in STRONG_SCENE) or leaf.endswith("Node") and any(
                    k in leaf for k in TIER1_KEYS + TIER2_KEYS)
            return True
    return False


def has(name: str, keys) -> bool:
    return any(k in name for k in keys)


def classify(cls: str) -> tuple[str, int]:
    """returns (status_group, tier). status_group in {cut, keep}."""
    if has(cls, CUT_KEYS):
        return "cut", 0
    if has(cls, TIER1_KEYS):
        return "keep", 1
    if has(cls, TIER2_KEYS):
        return "keep", 2
    return "keep", 3


def status_of(cls: str) -> str:
    if any(h in cls for h in DONE_HINTS):
        return "partial"  # 주요 레이어 이식됨, 부속 셀/팝업은 미완
    return "todo"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    so = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SO
    elf = ELF(so)
    names = elf.dynsym_names()

    classes: dict[str, set[str]] = defaultdict(set)
    for raw in names:
        sym = demangle(raw)
        if sym is None or is_engine(sym):
            continue
        cls, leaf = leaf_of(sym)
        if not is_presentation(leaf):
            continue
        m = sym.member
        if not m.startswith("~") and m != leaf:
            classes[cls].add(m)
        else:
            classes[cls]  # ensure present

    # 분류
    rows = []  # (cls, nmethods, group, tier, status)
    for cls in classes:
        group, tier = classify(cls)
        rows.append((cls, len(classes[cls]), group, tier, status_of(cls)))

    keep = [r for r in rows if r[2] == "keep"]
    cut = [r for r in rows if r[2] == "cut"]
    keep.sort(key=lambda r: (r[3], -r[1], r[0]))
    cut.sort(key=lambda r: (-r[1], r[0]))

    out = []
    out.append("<!-- 자동생성: scripts/tools/build_scene_ledger.py — libgame.so 심볼 기반. Phase 0. -->")
    out.append("# 씬 이식 원장 (Scene Port Ledger)\n")
    out.append(f"- 원본: `{so}`")
    out.append(f"- 연출(render) 클래스 {len(rows)}개 추출 · 유지 {len(keep)} / CUT {len(cut)}")
    out.append("- tier1=코어 오프라인 루프, tier2=보조 화면, tier3=폴리시/기타")
    out.append("- status: done(완료) / partial(주요 레이어만) / todo\n")
    out.append("> Phase 1 일괄 디컴파일은 이 원장의 tier 순서로 진행. CUT은 제외(디컴파일 예산 절약).\n")

    for tier, title in [(1, "Tier 1 — 코어 오프라인 루프"), (2, "Tier 2 — 보조 화면"), (3, "Tier 3 — 폴리시/기타")]:
        trows = [r for r in keep if r[3] == tier]
        out.append(f"\n## {title} ({len(trows)}개)\n")
        out.append("| 클래스 | #메서드 | status |")
        out.append("|---|---|---|")
        for cls, n, _, _, st in trows:
            out.append(f"| `{cls}` | {n} | {st} |")

    out.append(f"\n## CUT — 온라인/PvP/이벤트 (제외, {len(cut)}개)\n")
    out.append("<details><summary>펼치기</summary>\n")
    out.append("| 클래스 | #메서드 |")
    out.append("|---|---|")
    for cls, n, _, _, _ in cut:
        out.append(f"| `{cls}` | {n} |")
    out.append("\n</details>")

    sys.stdout.write("\n".join(out))
    sys.stderr.write(f"\n[ledger] render 클래스 {len(rows)} (keep {len(keep)}, cut {len(cut)})\n")


if __name__ == "__main__":
    main()
