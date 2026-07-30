"""엔티티 마스터 대장 생성기 — goal(디컴파일 근거 1:1 재현) 완전성 추적의 백본.

libgame.so의 전 게임 클래스(~357, `_symbol_map.md`)를 대상으로 각 엔티티에
상태(미분석/분석중/구현/검증완료/CUT)와 **근거 링크**를 붙여 `docs/entity_master_ledger.md`를
생성한다. `.so` 재파싱 없이 **이미 커밋된 권위 산출물**을 파싱하므로 로컬에 .so가 없어도 동작.

입력(모두 레포 내):
  - docs/ref/orig_code/symbol_map.md        : 게임 클래스 + 메서드수 + 시스템 카테고리 (extract_symbols.py 산출)
  - docs/ref/design/scene_port_ledger.md  : render 클래스의 tier / CUT 분류 (build_scene_ledger.py 산출)
  - docs/ref/design/ledger_overlay.json  : 수기 오버레이(구현/검증완료 상태 + godot 파일 + note)
  - 파일시스템 근거: docs/ref/orig_code/decomp/<Class>.c, data/recipes/<Class>.json, 분석문서 언급

상태 도출:
  - overlay.impl 에 있으면 그 status/근거 사용(수기 확정).
  - 없으면 자동: CUT키워드 → CUT / 디컴파일·레시피·분석언급 있으면 → 분석중 / 아무것도 없으면 → 미분석.

사용:  python scripts/tools/build_master_ledger.py > docs/entity_master_ledger.md
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
DECOMP = DOCS / "ref" / "orig_code" / "decomp"
RECIPES = ROOT / "data" / "recipes"

# 분석문서: 클래스명이 언급되면 "분석 근거 있음"으로 간주.
# *_analysis.md + render_recipe_*.md + gap 트래커 자동 수집(향후 문서 추가 시 자동 반영).
ANALYSIS_DOCS = sorted(
    set(DOCS.glob("*_analysis.md"))
    | set(DOCS.glob("render_recipe_*.md"))
    | {DOCS / "reimplementation_gaps.md"}
)

STATUS_ORDER = ["검증완료", "구현", "분석중", "미분석", "CUT"]
STATUS_EMOJI = {"검증완료": "✅", "구현": "🟢", "분석중": "🔬", "미분석": "⬜", "CUT": "✂️"}


def parse_symbol_map(path: Path):
    """반환: {class: {'methods': int, 'category': str}}, 카테고리 순서 리스트."""
    text = path.read_text(encoding="utf-8")
    classes: dict[str, dict] = {}
    cat_order: list[str] = []
    cur_cat = None
    for line in text.splitlines():
        m = re.match(r"^## (.+)$", line)
        if m:  # any ## header = 시스템 카테고리
            cur_cat = m.group(1).strip()
            if cur_cat not in cat_order:
                cat_order.append(cur_cat)
            continue
        m = re.match(r"^### `([^`]+)` \((\d+) methods\)", line)
        if m:
            classes[m.group(1)] = {"methods": int(m.group(2)), "category": cur_cat or "기타"}
    return classes, cat_order


def parse_ledger(path: Path):
    """반환: {class: {'tier': int|0, 'cut': bool}}. tier0 = CUT."""
    text = path.read_text(encoding="utf-8")
    info: dict[str, dict] = {}
    cur_tier = None
    in_cut = False
    for line in text.splitlines():
        if line.startswith("## Tier 1"):
            cur_tier, in_cut = 1, False
        elif line.startswith("## Tier 2"):
            cur_tier, in_cut = 2, False
        elif line.startswith("## Tier 3"):
            cur_tier, in_cut = 3, False
        elif line.startswith("## CUT"):
            cur_tier, in_cut = 0, True
        m = re.match(r"^\| `([^`]+)` \| (\d+) \|", line)
        if m:
            cls = m.group(1)
            info[cls] = {"tier": 0 if in_cut else (cur_tier or 3), "cut": in_cut}
    return info


# scene_port_ledger 의 CUT 키워드 재사용(로직/데이터 클래스는 ledger에 없어 자체 판정 필요)
CUT_KEYS = (
    "Auction", "Colosseum", "Coliseum", "Arena", "Pvp", "PvP", "Friend", "Rank",
    "Guild", "Chat", "Login", "Mail", "Charge", "Cash", "Coupon", "Attend",
    "Invite", "Mercenary", "Trade", "Market", "Ranking", "Event", "Anniversary",
    "Notice", "Facebook", "Kakao", "Server", "Network", "Http", "2019", "2020",
    "2021", "2022", "WorldRaid", "FourthRaid", "Roulette", "LuckyBag", "Nuri",
    "DragonBall", "Berna", "Social", "Billing", "Sms", "Register", "Reset",
    "Dispatch", "Scramble", "Colosseum", "WorldCup", "Worldcup", "Season",
    "Custom", "Duel", "3vs3", "1vs1", "Vote", "Bingo", "Christmas", "Halloween",
    "NewYear", "Valentine", "YongSoon", "GoldenDog", "Golden", "Comeback",
    "Recruit", "Package", "Slot", "Lottery", "Lucky", "Wonder", "Genuine",
    "Promote", "Promotion", "Code", "Ads", "Ad_", "Replay",
)


def is_cut_kw(cls: str) -> bool:
    return any(k in cls for k in CUT_KEYS)


# 명백한 이벤트/시즌/온라인 토큰: scene_port_ledger가 tier-3 keep으로 놓쳤어도 §1대로 CUT 오버라이드.
# 구조적/모호 토큰(Slot 단독, Custom 등)은 제외해 오컷 방지.
EVENT_CUT_KEYS = (
    "Christmas", "Halloween", "NewYear", "Valentine", "Bingo", "YongSoon",
    "GoldenDog", "GoldImp", "Anniversary", "SixAnniversary", "SixthBingo",
    "SixthBadge", "SixthSpectial", "SixthThanks", "Children2020", "Children2018",
    "ChildrenBingo", "ChildrenEvent", "Event2020", "WorldRaid", "FourthRaid",
    "GuildRaid", "LuckyBag", "LuckyPocket", "Lottery", "Roulette", "DragonBall",
    "Nuri", "Berna", "Scramble", "CustomTournament", "CustomTourament", "DailyMatch",
    "Dual", "Select3vs3", "Select1vs1", "PopVote", "Recruit", "Comeback",
    "FreeCharge", "FreeCash", "Marketpass", "BillingPack", "BillingSkin",
    "BillingGold", "BillingCash", "PremiumFriend", "SocialRecommend", "SocialRequest",
    "SocialFriend", "Sms", "GoldenNecklace", "HalloweenBingo", "NewYearBingo",
    "ConsumWorldcup", "CollectWorldcup", "WorldCup", "Worldcup", "StarEvent",
    "SeasonRanking", "SeasonInfo", "SeasonScene", "SeasonShop", "PromotionPop",
    "PickGoldenDog", "PickLuckyPocket", "PickPalagon", "FindGoldenDog",
    "FindNewYearCard", "BuyNewYearCard", "AccessTerms", "AccessTermsLayer",
    # 온라인 인프라(SDK/웹뷰/광고/계정) — 오프라인 재구현 불필요
    "Plugin", "WebView", "AdManager", "AccountManager",
)


def is_event_cut(cls: str) -> bool:
    return any(k in cls for k in EVENT_CUT_KEYS)


def classify_tier(cls: str) -> int:
    """ledger에 없는 로직/데이터 클래스용 자체 tier 판정."""
    t1 = ("Battle", "Fight", "Adventure", "Field", "Dungeon", "Dragon", "Egg",
          "Breed", "Mate", "Combine", "Hatch", "Skill", "Monster", "Item", "Bag",
          "Gem", "Equip", "Enchant", "Awak", "Evolv", "World", "Town", "Cave",
          "Map", "Mission", "Reward", "Book", "Aura", "TeamBuff", "Crest",
          "Potential", "Seal", "Field", "Stage", "Race")
    if any(k in cls for k in t1):
        return 1
    t2 = ("Shop", "Gacha", "Box", "Menu", "Setting", "Option", "Status", "Info",
          "Select", "Popup", "Layer", "Scene", "Intro", "Title", "Load", "Tutorial")
    if any(k in cls for k in t2):
        return 2
    return 3


def scan_analysis_mentions() -> dict[str, list[str]]:
    """각 분석문서에서 언급된 클래스명 → 문서 목록. (백틱 안 클래스명 위주)"""
    doc_text = {}
    for p in ANALYSIS_DOCS:
        if p.exists():
            doc_text[p.name] = p.read_text(encoding="utf-8")
    return doc_text


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

    sym, cat_order = parse_symbol_map(DOCS / "ref" / "orig_code" / "symbol_map.md")
    ledger = parse_ledger(DOCS / "ref" / "design" / "scene_port_ledger.md")
    overlay = json.loads((DOCS / "ref" / "design" / "ledger_overlay.json").read_text(encoding="utf-8"))
    impl = overlay.get("impl", {})
    doc_text = scan_analysis_mentions()

    decomp_set = {p.stem for p in DECOMP.glob("*.c")} if DECOMP.exists() else set()
    recipe_set = {p.stem for p in RECIPES.glob("*.json")} if RECIPES.exists() else set()

    # 전체 클래스 = 심볼맵 ∪ ledger ∪ **디컴프한 것**
    # 🔴 2026-07-30: `decomp_set` 을 계산해 두고 합집합에 넣지 않아, **우리가 직접 디컴파일한
    #    클래스가 대장에 안 나타났다.** 실제 사고 — 스토리 진행 조건을 전부 들고 있는
    #    `ScenarioSubQuestData`(80메서드)가 여기서 빠졌다. 원인은 `extract_symbols.py` 의
    #    `categorize()` 가 **키워드 허용목록**이라 이름이 안 걸리는 클래스를 조용히 버리는 것
    #    (통과 357 / 버림 730 — `Scenario*`·`*Data`·`Quest*` 다수 포함). symbol_map 을 고치는
    #    건 별건이고, 최소한 **디컴프한 것은 반드시 대장에 뜨게** 한다.
    all_classes = set(sym) | set(ledger) | decomp_set

    rows = []
    for cls in all_classes:
        info = sym.get(cls, {})
        methods = info.get("methods")
        category = info.get("category")
        led = ledger.get(cls, {})
        # tier / cut: ledger가 권위(build_scene_ledger가 신중히 분류). ledger에 없는
        # 로직/데이터 클래스만 자체 키워드 판정.
        if led:
            tier, cut = led["tier"], led["cut"]
        else:
            cut = is_cut_kw(cls)
            tier = 0 if cut else classify_tier(cls)
        # §1 이벤트/시즌/온라인 재분류: ledger가 keep으로 놓친 명백한 이벤트 클래스를 CUT 오버라이드.
        if not cut and is_event_cut(cls):
            cut = True
            tier = 0
        if category is None:
            category = "render/기타 (ledger 전용)"

        # 근거 수집
        ev = {
            "decomp": cls in decomp_set,
            "recipe": cls in recipe_set,
            "analysis": [name for name, t in doc_text.items() if cls in t],
        }
        ov = impl.get(cls)
        godot = ov.get("godot", []) if ov else []
        note = ov.get("note", "") if ov else ""
        ov_ev = ov.get("evidence", []) if ov else []
        if ov and ov.get("recipe"):
            ev["recipe"] = True

        # 상태 도출
        if ov and ov.get("status"):
            status = ov["status"]
        elif cut:
            status = "CUT"
        elif ev["decomp"] or ev["recipe"] or ev["analysis"]:
            status = "분석중"
        else:
            status = "미분석"

        rows.append({
            "cls": cls, "methods": methods, "category": category, "tier": tier,
            "cut": cut, "status": status, "ev": ev, "godot": godot, "note": note,
            "ov_ev": ov_ev,
        })

    # 집계
    by_status = {s: 0 for s in STATUS_ORDER}
    for r in rows:
        by_status[r["status"]] = by_status.get(r["status"], 0) + 1
    total = len(rows)
    non_cut = total - by_status["CUT"]
    done = by_status["검증완료"]

    def ev_cell(r):
        parts = []
        if r["ev"]["decomp"]:
            parts.append(f"[⚙️](ref/orig_code/decomp/{r['cls']}.c)")
        if r["ev"]["recipe"]:
            parts.append(f"[📋](../data/recipes/{r['cls']}.json)")
        if r["ev"]["analysis"] or r["ov_ev"]:
            parts.append("📖")
        if r["godot"]:
            parts.append("🎮")
        return " ".join(parts) if parts else "—"

    out = []
    out.append("<!-- 자동생성: scripts/tools/build_master_ledger.py. 상태는 docs/ref/design/ledger_overlay.json(수기) + 파일시스템 근거로 도출. -->")
    out.append("# 엔티티 마스터 대장 (Entity Master Ledger)\n")
    out.append("> **goal:** libgame.so의 전 게임 클래스를 디컴파일 근거로 1:1 재현. 이 대장이 완전성 추적의 단일 기준.")
    out.append("> 상태: ✅검증완료(디컴파일근거+계층분리구현+헤드리스검증) · 🟢구현(반영, 검증/잔여폴리시 진행) · 🔬분석중(디컴파일/레시피/분석문서 확보, 미이식) · ⬜미분석 · ✂️CUT(온라인/PvP/이벤트).")
    out.append("> 근거: ⚙️=디컴파일(`docs/ref/orig_code/decomp`) · 📋=레시피(`data/recipes`) · 📖=분석문서 · 🎮=Godot구현. 상태 수기확정은 `docs/ref/design/ledger_overlay.json`.\n")
    out.append("## 요약\n")
    out.append(f"- 전체 **{total}** 클래스 · 비-CUT **{non_cut}** · CUT **{by_status['CUT']}**")
    out.append(f"- 진행: ✅검증완료 **{done}** · 🟢구현 **{by_status['구현']}** · 🔬분석중 **{by_status['분석중']}** · ⬜미분석 **{by_status['미분석']}**")
    pct = (done / non_cut * 100) if non_cut else 0
    out.append(f"- **비-CUT 검증완료율: {pct:.1f}%** ({done}/{non_cut}). goal 완료 = 모든 비-CUT 엔티티 검증완료.\n")

    # 다음 작업 후보: 비-CUT · 미검증 · tier1 우선 · 메서드수 desc
    def sort_key(r):
        st = {"분석중": 0, "미분석": 1, "구현": 2}.get(r["status"], 9)
        return (r["tier"], st, -(r["methods"] or 0), r["cls"])

    cand = [r for r in rows if not r["cut"] and r["status"] not in ("검증완료",)]
    cand.sort(key=sort_key)
    out.append("## 다음 작업 후보 (tier1 → 분석중/미분석 → 메서드수)\n")
    out.append("> 티어·의존 순 진행. 디컴파일 확보(⚙️)된 것부터 이식하면 근거주의 워크플로가 짧아짐.\n")
    out.append("| # | 클래스 | tier | #M | 상태 | 근거 |")
    out.append("|---|---|---|---|---|---|")
    for i, r in enumerate(cand[:25], 1):
        m = r["methods"] if r["methods"] is not None else "?"
        out.append(f"| {i} | `{r['cls']}` | T{r['tier']} | {m} | {STATUS_EMOJI[r['status']]}{r['status']} | {ev_cell(r)} |")
    out.append("")

    # 카테고리별 전수 표(심볼맵 카테고리 순 + render 전용 마지막)
    cat_seq = cat_order + ["render/기타 (ledger 전용)"]
    for cat in cat_seq:
        crows = [r for r in rows if r["category"] == cat]
        if not crows:
            continue
        crows.sort(key=lambda r: (STATUS_ORDER.index(r["status"]), r["tier"], -(r["methods"] or 0), r["cls"]))
        cnt = {s: sum(1 for r in crows if r["status"] == s) for s in STATUS_ORDER}
        badge = " · ".join(f"{STATUS_EMOJI[s]}{cnt[s]}" for s in STATUS_ORDER if cnt[s])
        out.append(f"\n## {cat}  ({len(crows)}) — {badge}\n")
        out.append("| 클래스 | #M | T | 상태 | 근거 | 구현/비고 |")
        out.append("|---|---|---|---|---|---|")
        for r in crows:
            m = r["methods"] if r["methods"] is not None else "?"
            note = r["note"]
            if r["godot"] and not note:
                note = ", ".join(r["godot"])
            note = note.replace("|", "\\|")
            if len(note) > 160:
                note = note[:157] + "…"
            out.append(f"| `{r['cls']}` | {m} | {r['tier'] or '·'} | {STATUS_EMOJI[r['status']]}{r['status']} | {ev_cell(r)} | {note} |")

    # 파일에 직접 기록(리다이렉트 누락으로 스테일되는 사고 방지). stdout으로도 출력해 기존 `> file` 사용과 호환.
    body = "\n".join(out) + "\n"
    out_path = DOCS / "entity_master_ledger.md"
    out_path.write_text(body, encoding="utf-8")
    if not sys.stdout.isatty():
        sys.stdout.write(body)   # `> file` 리다이렉트 시에도 동일 내용(빈 파일 사고 방지)
    sys.stderr.write(f"[master_ledger] wrote {out_path}\n")
    sys.stderr.write(
        f"[master_ledger] {total} classes · non-CUT {non_cut} · "
        f"검증완료 {done} 구현 {by_status['구현']} 분석중 {by_status['분석중']} "
        f"미분석 {by_status['미분석']} CUT {by_status['CUT']}\n"
    )


if __name__ == "__main__":
    main()
