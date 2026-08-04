"""콜로세움(솔로잉 재설계) 마스터 데이터 생성 — data/colosseum.json.

🟦 사용자 확정 2026-08-04 — 원작 콜로세움은 PvP 라 CLAUDE.md §2-1 에서 CUT 이었으나,
**상대를 봇으로만 채운 솔로 콜로세움**으로 되살린다. 네트워크 코드는 여전히 없다.
설계 근거 전문 = docs/ref/porting/Colosseum.md.

이 파일이 data/colosseum.json 의 **단일 출처**다. JSON 을 손으로 고치면 다음 실행에
지워진다(그래서 값은 여기에 넣는다).

## 원작에서 채굴한 것 (유실 아님)

- **티어 경계** — `StrategyManager::GetTier(int rating)` @0170f130 에 하드코딩:
      < 0x4b0(1200) → 5 · < 0x5dc(1500) → 4 · < 0x76c(1900) → 3 · < 0x8fc(2300) → 2 · 그 이상 → 1
  이름 = `GetTierName` @0170ed74 (1=MASTER … 5=BRONZE).
- **티어 프레임 경로** — `GetTierBorderName` @0170ee4c `common/dragon_frame_%s.png` ·
  `ColosseumProfile::getRatingBorder` @00f15ad8 `common/list_frame_%s.png` ·
  `MakeInterface::ColosseumFightInitWidget` @010519b0 `common/tier_icon_%s.png`.
- **세이브 스키마** — `ColosseumScene::_responseList` @00f4ca90 의 JSON 키
  (single/tournament/straight_single/straight_team/energy/…). docs/ref/porting/Colosseum.md §2.

### 왜 5티어인가 (DIAMOND 제외)

클래식 콜로세움 코드(`getRatingBorder`)는 6티어(…PLATINUM, **DIAMOND**, MASTER)를 부르지만:
  1. `asset_index.py --grep list_frame_` → bronze/silver/gold/platinum/master **5종만 실재**.
  2. `--grep tier_icon_` → 역시 **5종**.
  3. 그 5종이 `StrategyManager::GetTier` 의 5티어·채굴된 경계값과 정확히 일치.
⇒ DIAMOND 는 프레임 미보유(후기 추가분)로 보고 제외. **경계값은 원작 그대로.**

## 유실 → 자작 (# ASSUMPTION)

승/패 레이팅 증감은 원작이 서버가 채운 벡터를 읽기만 했다
(`FightManager::getDuelBaseRankPoint` @0104dc64 = 벡터[0] · `getDuelAddRankPoint` @0104dc88 = 벡터[-1]).
⇒ 아래 `rating` / `ticket` / `streak` / `bots` 블록은 **튜닝 노브**다.

사용:
    python scripts/tools/build_colosseum.py            # data/colosseum.json 재생성
    python scripts/tools/build_colosseum.py --init     # 사용자 기입 CSV 스켈레톤 생성(있으면 보존)
    python scripts/tools/build_colosseum.py --dry      # 쓰지 않고 요약만
"""
from __future__ import annotations
import csv, json, sys, re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "data" / "colosseum.json"
SHEETS = REPO / "docs" / "input" / "sheets"
RANKER_CSV = SHEETS / "colosseum_ranker.csv"
NICK_CSV = SHEETS / "colosseum_nick.csv"
GUARD_CSV = SHEETS / "colosseum_guard.csv"
STRINGS_KR = REPO / "DV2" / "string" / "stringsData_KR.xml"

# 연승방지봇 3단계 — 🟦 사용자 확정 2026-08-04.
#
# 라온·누리는 **원작 캐릭터**이고 콜로세움 대사까지 실재한다
# (ColosseumRaonTalkA/B/C · ColosseumNuriTalkA/B — 유실 아님, stringsData_KR.xml).
# 원작이 A/B/C 로 단계를 나눠 둔 것 자체가 "올라올수록 다른 말을 한다"는 구조다.
#
# 🟦 **선대군은 원작에 없는 오리지널 캐릭터**(사용자 확정) — 원작 문자열 0건.
#   등장 조건 = **999연승**. 대사·드래곤 구성 전부 사용자 CSV.
#
# 🟦 등장 조건 = 사용자 확정 2026-08-04. **연승 기준**이고 둘이 교차한다:
#     25 누리A · 50 라온A · 75 누리B · 100 라온B · 150 라온C · 999 선대군
# 이게 원작 대사 단계 수와 정확히 맞는다 — 누리는 A/B **2단계**, 라온은 A/B/C **3단계**.
# ⇒ `schedule` 한 줄 = (등장 연승, 누가, 어느 대사 단계) 다. 현재 연승에서 **도달한 가장 높은
#   문턱**이 곧 이번 상대이자 그 대사 단계가 된다.
GUARD_NPCS = [
    {"key": "nuri", "name": "누리", "talk_prefix": "ColosseumNuriTalk", "orig": True},
    {"key": "raon", "name": "라온", "talk_prefix": "ColosseumRaonTalk", "orig": True},
    {"key": "sundaegun", "name": "선대군", "talk_prefix": None, "orig": False},
]

# 🟦 사용자 확정 2026-08-04 — 연승방지봇은 **이벤트성 매치**라 일반 매칭과 규칙이 다르다.
#   봇이 끌고 나오는 드래곤의 능력치는 도감·성장곡선과 무관한 **임의 부여 수치**다.
#   ⇒ 시트에 마리별 스탯 칸을 둔다. 적힌 칸만 **최종 능력치를 덮어쓴다**
#     (젬·장비·팀버프·성장 계산을 다 끝낸 뒤 마지막에 대입 — `PartyStats.resolve`).
#   빈 칸은 평소대로 계산한다 ⇒ **선대군은 전 칸을 비워 두면 기존 드래곤 스탯·등급 그대로**다.
GUARD_STAT_COLS = {           # CSV 열 이름 → 스탯 키(전투가 쓰는 이름)
    "HP": "hp", "공격": "att", "방어": "def",
    "크리": "cri", "회피": "evd", "블록": "blk",
}
GUARD_GRADE_COL = "등급"      # 카드에 뜨는 등급 표시(비우면 스탯에서 계산)

GUARD_HEADER = (["키", "이름", "등장연승", "레이팅", "드래곤id", "레벨", "각성"]
                + list(GUARD_STAT_COLS) + [GUARD_GRADE_COL]
                + ["젬", "스킬", "장비", "대사", "비고"])

GUARD_SCHEDULE = [
    {"streak_at": 25,  "key": "nuri",      "talk_stage": "A"},
    {"streak_at": 50,  "key": "raon",      "talk_stage": "A"},
    {"streak_at": 75,  "key": "nuri",      "talk_stage": "B"},
    {"streak_at": 100, "key": "raon",      "talk_stage": "B"},
    {"streak_at": 150, "key": "raon",      "talk_stage": "C"},
    {"streak_at": 999, "key": "sundaegun", "talk_stage": ""},   # 대사는 CSV
]

# ── 원작 채굴값 ────────────────────────────────────────────────────────────
#
# 🔴 2026-08-04 정정 — 처음에 `StrategyManager::GetTier` @0170f130 의 경계
#    (1200/1500/1900/2300, 5티어)를 썼는데 **그건 시즌(Strategy) 시스템이지
#    클래식 콜로세움이 아니다.** 진짜 경계는 문자열 번들에 문장으로 박혀 있었다
#    (`DV2/string/stringsData_KR.xml`):
#        Colosseum_Rating_0 = 1200점 미만      Colosseum_Rating_3 = 1600점 이상
#        Colosseum_Rating_1 = 1200점 이상      Colosseum_Rating_4 = 1800점 이상
#        Colosseum_Rating_2 = 1400점 이상      Colosseum_Rating_5 = 2000점 이상
#    ⇒ **6단계 · 200점 등간격**이고, 이게 `ColosseumProfile::getRatingBorder` @00f15ad8 의
#      6분기(0 BRONZE / 1 SILVER / 2 GOLD / 3 PLATINUM / 4 DIAMOND / 5 MASTER)와 정확히 맞는다.
#    종전의 "프레임이 5종뿐이니 5티어" 추론은 **자산 부재를 규칙 부재로 오독한 것**이었다.
#    id = getRatingBorder 의 case 번호 그대로(0=BRONZE … 5=MASTER, 클수록 높다).
#
# ⚠️ DIAMOND 아이콘(`common/{list_frame,tier_icon}_diamond.png`)은 추출 에셋에 없다.
#    티어는 원작대로 두고 **표시만** platinum 프레임으로 대신한다(`icon_fallback`).
TIERS = [
    {"id": 0, "key": "bronze",   "name": "BRONZE",   "min_rating": 0},
    {"id": 1, "key": "silver",   "name": "SILVER",   "min_rating": 1200},
    {"id": 2, "key": "gold",     "name": "GOLD",     "min_rating": 1400},
    {"id": 3, "key": "platinum", "name": "PLATINUM", "min_rating": 1600},
    {"id": 4, "key": "diamond",  "name": "DIAMOND",  "min_rating": 1800,
     "icon_fallback": "platinum"},
    {"id": 5, "key": "master",   "name": "MASTER",   "min_rating": 2000},
]

TIER_FRAMES = {
    "border": "common/list_frame_%s.png",      # ColosseumProfile::getRatingBorder
    "dragon": "common/dragon_frame_%s.png",    # StrategyManager::GetTierBorderName
    "icon":   "common/tier_icon_%s.png",       # MakeInterface::ColosseumFightInitWidget
    # 원작은 scene/colosseumrank/txt_%s_bar.png 를 부르지만 추출 아틀라스엔 _kr/_en 뿐이다.
    "header": "scene/colosseumrank/txt_%s_kr.png",
}

# ── 자작 노브 ──────────────────────────────────────────────────────────────
RATING = {
    "_note": "# ASSUMPTION — 원작은 서버가 증감치를 내려줬다(getDuelBaseRankPoint/getDuelAddRankPoint). "
             "시작 1000 = BRONZE 중간. 연승 보너스는 위로 갈수록 굳지 않게 하는 장치.",
    "start": 1000,
    "min": 0,
    "win": 24,
    "lose": -18,
    # 연승 1회당 승리 보너스(+2), 상한 +12 → 최대 승리 +36.
    "streak_bonus_per": 2,
    "streak_bonus_max": 12,
    # 티어가 높을수록 패배 손실이 커진다(방어적 정체 방지). 티어 id → 배수.
    # id 는 0=BRONZE … 5=MASTER (getRatingBorder case 번호).
    "lose_mult_by_tier": {"0": 0.5, "1": 0.8, "2": 1.0, "3": 1.1, "4": 1.3, "5": 1.5},
}

# 상대 목록 새로고침 — 원작은 **골드**를 받는다
# (`Colosseum_Refresh_Msg` "새로고침에는 %1$d 골드가 필요합니다." · 부족하면 Colosseum_Refresh_Error).
# 금액은 서버가 내려주던 값이라 유실 → 자작 노브. `Colosseum_Error_2` 가 "무료 갱신 제공"을
# 말하므로 **하루 free_per_day 회는 공짜**로 둔다(원작도 무료 갱신 개념이 있었다).
REFRESH = {
    "_source": "stringsData_KR.xml Colosseum_Refresh_Msg / Colosseum_Refresh_Error / Colosseum_Error_2",
    "gold": 1000,
    "free_per_day": 3,
}

# 콜로세움 전용 재화 — 원작 `Colosseum_Coin` = "콜로세움 주화".
# 일일/주간 보상이 **다이아 + 주화**를 우편함으로 준다
# (Colosseum_Daily_Result_1/2 · Colosseum_Weekly_Result_1/2).
# ⚫ 우편함은 온라인이라 CUT → 우리는 즉시 지급한다. 지급량은 서버 유실 → 자작 노브.
COIN = {
    "_source": "stringsData_KR.xml Colosseum_Coin · Colosseum_Daily_Result_* · Colosseum_Weekly_Result_*",
    "key": "colosseum_coin",
    "name": "콜로세움 주화",
    # 티어(0 BRONZE … 5 MASTER) → {다이아, 주화}. 일일·주간 각각.
    "daily": {"0": {"dia": 1, "coin": 10}, "1": {"dia": 2, "coin": 20},
              "2": {"dia": 3, "coin": 35}, "3": {"dia": 5, "coin": 55},
              "4": {"dia": 7, "coin": 80}, "5": {"dia": 10, "coin": 120}},
    "weekly": {"0": {"dia": 5, "coin": 50}, "1": {"dia": 10, "coin": 100},
               "2": {"dia": 18, "coin": 180}, "3": {"dia": 30, "coin": 300},
               "4": {"dia": 45, "coin": 450}, "5": {"dia": 70, "coin": 700}},
}

TICKET = {
    "_note": "# ASSUMPTION — 원작 `energy` + ColosseumBattleInfo::updateStamina 회복 타이머 구조만 차용.",
    "max": 10,
    "recover_seconds": 600,   # 10분당 1
    "cost_per_match": 1,
}

STREAK = {
    "_note": "🟦 사용자 확정 — 연승방지봇. 첫 등장은 **25연승**(누리A)이고 이후 스케줄대로 "
             "50/75/100/150/999 에서 다시 나온다(GUARD_SCHEDULE). guard_repeat 은 그 문턱을 "
             "넘은 뒤 방지봇이 목록에 유지되는 판 수.",
    "guard_at": 25,
    "guard_repeat": 3,
}

# 봇 분류 — 🟦 사용자 확정 2026-08-04.
BOT_GRADES = {
    "novice": {
        "label": "초급",
        "level": 50,
        "awakened": False,
        "gem": {"categories": ["normal", "hybrid", "soul"], "tier": "random"},
        "skill": {"count": 2, "level_min": 1, "level_max": 5},
        "equip": {"slots": 4, "grade_min": 0, "grade_max": 5, "random_catalog": True},
    },
    "adept": {
        "label": "중급",
        "level": 50,
        "awakened": True,
        # 혼성젬 **또는** 소울젬을 최고 등급으로. 젬마다 max tier 가 다르므로 -1 = 각 젬의 상한.
        "gem": {"categories": ["hybrid", "soul"], "tier": -1},
        "skill": {"count": 2, "level_min": 4, "level_max": 5},
        # 유니크(3) ~ 에픽(4) — data/equipment.json option.grades 인덱스.
        "equip": {"slots": 4, "grade_min": 3, "grade_max": 4, "random_catalog": True},
    },
    "ranker": {
        "label": "랭커",
        "_note": "구성은 colosseum_ranker.csv 가 결정한다(사용자 작성). 아래는 빈 칸 폴백.",
        "level": 50,
        "awakened": True,
        "gem": {"categories": ["hybrid", "soul"], "tier": -1},
        "skill": {"count": 2, "level_min": 5, "level_max": 5},
        "equip": {"slots": 4, "grade_min": 4, "grade_max": 5, "random_catalog": True},
    },
}

# 티어별 상대 분류 가중치 — # ASSUMPTION(튜닝 노브).
TIER_BOT_MIX = {
    "bronze":   {"novice": 100, "adept": 0,   "ranker": 0},
    "silver":   {"novice": 75,  "adept": 25,  "ranker": 0},
    "gold":     {"novice": 40,  "adept": 60,  "ranker": 0},
    "platinum": {"novice": 10,  "adept": 85,  "ranker": 5},
    "diamond":  {"novice": 0,   "adept": 80,  "ranker": 20},
    "master":   {"novice": 0,   "adept": 50,  "ranker": 50},
}

# 한 번에 보여 줄 상대 수(원작 match1_list/match3_list 길이 자리).
LIST_SIZE = 5

# ── 닉네임 기본 풀 ─────────────────────────────────────────────────────────
# 원작엔 닉 생성기가 없다(상대 = 실유저, 서버 소유). 초급·중급 봇용으로 새로 만든다.
# 사용자가 colosseum_nick.csv 를 채우면 그쪽이 이긴다.
DEFAULT_NICK = {
    "prefix": ["붉은", "푸른", "검은", "하얀", "황금", "번개", "폭풍", "심연", "새벽", "고요한",
               "불타는", "얼어붙은", "잊혀진", "떠도는", "굶주린", "은빛", "잿빛", "머나먼"],
    "noun": ["용사", "기사", "마도사", "사냥꾼", "방랑자", "수호자", "파수꾼", "조련사", "연금술사",
             "드래곤", "비룡", "익룡", "화룡", "빙룡", "성기사", "검객", "궁수", "현자", "여행자"],
    "suffix": ["", "", "", "님", "짱", "s", "II", "99", "7", "_1", "0v0"],
}


def read_csv(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8-sig", newline="") as f:
        return [r for r in csv.DictReader(f)]


def build_nick() -> dict:
    rows = read_csv(NICK_CSV)
    if not rows:
        return dict(DEFAULT_NICK)
    out: dict[str, list[str]] = {"prefix": [], "noun": [], "suffix": []}
    for r in rows:
        kind = (r.get("분류") or "").strip()
        val = (r.get("값") or "").strip()
        if kind in out and val:
            out[kind].append(val)
    # 빈 분류는 기본 풀로 메운다(전부 비워 두면 생성 자체가 막히므로).
    for k, v in out.items():
        if not v:
            out[k] = list(DEFAULT_NICK[k])
    return out


def read_orig_talks(prefix: str) -> dict:
    """원작 대사 추출 — `<{prefix}{A|B|C}_{n}>` 를 단계별로 모은다.

    유실이 아니다: 라온·누리의 콜로세움 대사가 `stringsData_KR.xml` 에 그대로 있다.
    단계 문자(A/B/C)가 곧 **등급 구간**이다(A=첫 조우 · B=올라온 뒤 · C=고등급).
    """
    if not prefix or not STRINGS_KR.exists():
        return {}
    t = STRINGS_KR.read_text(encoding="utf-8", errors="replace")
    out: dict[str, list[tuple[int, str]]] = {}
    for m in re.finditer(r"<%s([A-C])_(\d+)>(.*?)</%s\1_\2>" % (prefix, prefix), t, re.S):
        stage, no, txt = m.group(1), int(m.group(2)), m.group(3)
        txt = txt.replace("&#10;", "\n").strip()
        out.setdefault(stage, []).append((no, txt))
    return {k: [s for _, s in sorted(v)] for k, v in out.items()}


def read_stat_override(row: dict) -> dict:
    """연승방지봇 시트 1행의 임의 스탯 칸 → {스탯키: 값}. 빈 칸은 넣지 않는다."""
    out: dict[str, int] = {}
    for col, key in GUARD_STAT_COLS.items():
        v = (row.get(col) or "").strip().replace(",", "")
        if v.lstrip("-").isdigit():
            out[key] = int(v)
    return out


def build_guards() -> list[dict]:
    """연승방지봇 3단계(라온/누리/선대군).

    대사 = 원작에 있으면 원작(라온·누리), 없으면 CSV(선대군).
    드래곤 구성 = 전부 CSV(사용자 작성) — 랭커 시트와 같은 방식.
    """
    rows = read_csv(GUARD_CSV)
    by_key: dict[str, dict] = {}
    for r in rows:
        key = (r.get("키") or "").strip()
        if not key:
            continue
        g = by_key.setdefault(key, {"dragons": [], "talk_csv": []})
        line = (r.get("대사") or "").strip()
        if line:
            g["talk_csv"].append(line)
        did = (r.get("드래곤id") or "").strip()
        if did.isdigit():
            d = {
                "id": int(did),
                "level": int(r.get("레벨") or 50),
                "awakened": (r.get("각성") or "").strip().upper() in ("O", "Y", "TRUE", "1"),
                "gems": [x.strip() for x in (r.get("젬") or "").split("|") if x.strip()],
                "skills": [x.strip() for x in (r.get("스킬") or "").split("|") if x.strip()],
                "equip": [x.strip() for x in (r.get("장비") or "").split("|") if x.strip()],
            }
            # 이벤트성 매치 — 적힌 스탯만 최종값을 덮어쓴다(빈 칸은 계산대로).
            stats = read_stat_override(r)
            if stats:
                d["stats"] = stats
            grade = (r.get(GUARD_GRADE_COL) or "").strip()
            if grade:
                try:
                    d["grade"] = float(grade)
                except ValueError:
                    pass
            g["dragons"].append(d)
        if (r.get("레이팅") or "").strip().isdigit():
            g["rating"] = int(r["레이팅"])

    npcs = {}
    for npc in GUARD_NPCS:
        csvg = by_key.get(npc["key"], {})
        talks = read_orig_talks(npc["talk_prefix"])
        npcs[npc["key"]] = {
            "key": npc["key"], "name": npc["name"], "orig": npc["orig"],
            "talk": talks,                          # 원작 단계별 대사(A/B/C). 없으면 {}
            "talk_csv": csvg.get("talk_csv", []),   # 사용자 대사(선대군 등)
            "rating": csvg.get("rating", 0),
            "dragons": csvg.get("dragons", []),
            "_talk_source": "원작 %s*" % npc["talk_prefix"] if npc["talk_prefix"] else "사용자 CSV",
        }

    # 스케줄 한 줄 = 한 번의 등장. 대사 단계까지 여기서 확정한다.
    out = []
    for i, sch in enumerate(GUARD_SCHEDULE):
        npc = npcs[sch["key"]]
        stage = sch["talk_stage"]
        lines = npc["talk"].get(stage, []) if stage else list(npc["talk_csv"])
        out.append({
            "order": i + 1,
            "streak_at": sch["streak_at"],
            "key": npc["key"], "name": npc["name"], "orig": npc["orig"],
            "talk_stage": stage,
            "lines": lines,                     # 이번 등장에 쓸 대사(확정본)
            "rating": npc["rating"],
            "dragons": npc["dragons"],
            "_talk_source": npc["_talk_source"],
        })
    return out


def build_rankers() -> list[dict]:
    """랭커 풀 — 사용자 CSV. 한 랭커가 여러 줄(드래곤 3마리)일 수 있다."""
    rows = read_csv(RANKER_CSV)
    by_nick: dict[str, dict] = {}
    order: list[str] = []
    for r in rows:
        nick = (r.get("닉네임") or "").strip()
        if not nick:
            continue
        if nick not in by_nick:
            by_nick[nick] = {"nick": nick, "tier": (r.get("티어") or "master").strip() or "master",
                             "rating": int(r.get("레이팅") or 0), "dragons": []}
            order.append(nick)
        did = (r.get("드래곤id") or "").strip()
        if not did.isdigit():
            continue
        by_nick[nick]["dragons"].append({
            "id": int(did),
            "level": int(r.get("레벨") or 50),
            "awakened": (r.get("각성") or "").strip().upper() in ("O", "Y", "TRUE", "1"),
            "gems": [g.strip() for g in (r.get("젬") or "").split("|") if g.strip()],
            "skills": [s.strip() for s in (r.get("스킬") or "").split("|") if s.strip()],
            "equip": [e.strip() for e in (r.get("장비") or "").split("|") if e.strip()],
        })
    return [by_nick[n] for n in order]


def migrate_guard_sheet() -> bool:
    """시트를 **기입한 내용 그대로** 최신 열 구성에 맞춘다.

    사용자가 채우는 시트라 재생성으로 날리면 안 된다 — 없는 열은 빈 칸으로 추가하고
    순서를 GUARD_HEADER 에 맞춰 다시 쓴다(모르는 열은 뒤에 붙여 보존).
    `등장연승` 은 GUARD_SCHEDULE 에서 나오는 파생 표시값이라(빌더가 읽지 않는다)
    스케줄이 바뀌면 여기서 다시 적는다. 그 밖의 칸은 손대지 않는다.
    """
    if not GUARD_CSV.exists():
        return False
    with GUARD_CSV.open(encoding="utf-8-sig", newline="") as f:
        rd = csv.DictReader(f)
        old = list(rd.fieldnames or [])
        rows = list(rd)
    extra = [c for c in old if c and c not in GUARD_HEADER]
    header = GUARD_HEADER + extra
    seen: set[str] = set()
    was = [[(r.get(c) or "") for c in header] for r in rows]     # 손대기 전 스냅샷
    out: list[list[str]] = []
    for r in rows:
        key = (r.get("키") or "").strip()
        if key:
            first = key not in seen
            seen.add(key)
            r["등장연승"] = ",".join(str(s["streak_at"]) for s in GUARD_SCHEDULE
                                   if s["key"] == key) if first else ""
        out.append([(r.get(c) or "") for c in header])
    if old == header and was == out:
        return False
    with GUARD_CSV.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(out)
    added = [c for c in GUARD_HEADER if c not in old]
    print(f"  ~ {GUARD_CSV.relative_to(REPO)} — "
          + (f"열 추가(기입 내용 보존): {', '.join(added)}" if added else "등장연승 갱신"))
    return True


def init_sheets(force: bool = False) -> None:
    SHEETS.mkdir(parents=True, exist_ok=True)
    if force or not RANKER_CSV.exists():
        with RANKER_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["닉네임", "티어", "레이팅", "드래곤id", "레벨", "각성", "젬", "스킬", "장비", "비고"])
            for _ in range(3):
                w.writerow(["", "master", "", "", "50", "O", "", "", "", ""])
        print(f"  + {RANKER_CSV.relative_to(REPO)}")
    if force or not GUARD_CSV.exists():
        with GUARD_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(GUARD_HEADER)
            for npc in GUARD_NPCS:
                at = ",".join(str(s["streak_at"]) for s in GUARD_SCHEDULE
                              if s["key"] == npc["key"])
                note = ("원작 대사 자동 반영 — 대사 칸은 비워 두세요. "
                        "스탯 칸에 적은 값이 최종 능력치가 됩니다(빈 칸은 도감 계산대로)"
                        if npc["talk_prefix"] else
                        "오리지널 캐릭터 — 대사도 채워 주세요. "
                        "스탯 칸은 비워 두면 기존 드래곤 스탯·등급 그대로")
                for i in range(3):          # 드래곤 3마리(3vs3) 자리
                    w.writerow([npc["key"], npc["name"] if i == 0 else "",
                                at if i == 0 else "", "", "", "50", "O",
                                "", "", "", "", "", "", "",   # HP·공격·방어·크리·회피·블록·등급
                                "", "", "", "", note if i == 0 else ""])
        print(f"  + {GUARD_CSV.relative_to(REPO)}")
    if force or not NICK_CSV.exists():
        with NICK_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["분류", "값", "비고"])
            for kind in ("prefix", "noun", "suffix"):
                for v in DEFAULT_NICK[kind]:
                    w.writerow([kind, v, ""])
        print(f"  + {NICK_CSV.relative_to(REPO)}")


def build() -> dict:
    rankers = build_rankers()
    return {
        "_re_basis":
            "콜로세움(솔로잉 재설계). 🟦 사용자 확정 2026-08-04 — 원작은 PvP 라 CUT 이었으나 "
            "상대를 봇으로만 채워 되살린다. 티어 경계·이름·프레임 경로는 원작 클라에서 채굴했고"
            "(StrategyManager::GetTier @0170f130, ColosseumProfile::getRatingBorder @00f15ad8), "
            "레이팅 증감·입장권·봇 구성은 서버 유실이라 자작 노브다. "
            "설계 전문 = docs/ref/porting/Colosseum.md. 이 파일은 build_colosseum.py 가 생성한다.",
        "_source": {
            "tier": "StrategyManager::GetTier @0170f130 / GetTierName @0170ed74 / GetTierBorderName @0170ee4c",
            "frames": "ColosseumProfile::getRatingBorder @00f15ad8 · MakeInterface::ColosseumFightInitWidget @010519b0",
            "save_schema": "ColosseumScene::_responseList @00f4ca90 (match1_list/match3_list/single/tournament/straight_*/energy)",
            "streak_hook": "FightScene::initWinningStreak @00f89290 · ColosseumManager::getWinningStreak @01032494",
        },
        "modes": {
            # 원작 키 그대로 — single=1vs1, team(tournament)=3vs3.
            "single": {"label": "1 vs 1", "party": 1, "rating_key": "single", "streak_key": "straight_single"},
            "team":   {"label": "3 vs 3", "party": 3, "rating_key": "tournament", "streak_key": "straight_team"},
        },
        "tier": {"list": TIERS, "frames": TIER_FRAMES},
        # 입장 조건 — 원작 `ColosseumInError` 가 문장으로 못 박는다(유실 아님).
        # "테이머 자격증 이벤트를 완수하셔야 입장할 수 있습니다. (레벨 25)"
        # ⚫ 자격증 이벤트는 서버 이벤트라 CUT → 레벨 조건만 쓴다.
        # 이게 곧 성체 조건이기도 하다: 공격/피격 모션이 **성체 스파인에만** 있다
        # (실측 2026-08-04 — adult 134/134 vs child·baby 각 1/133).
        "entry": {"min_level": 25,
                  "_source": "stringsData_KR.xml ColosseumInError",
                  "_cut": "테이머 자격증 이벤트(서버 이벤트)"},
        # 원작 문자열 번들에서 채굴한 **규칙 사실**들. 아직 미구현인 것도 있으나
        # "서버 유실"이 아니라 **클라에 있었다**는 근거로 남긴다(사용자 지적 2026-08-04).
        "_orig_rules": {
            "_source": "DV2/string/stringsData_KR.xml — 콜로세움 문자열 162개",
            "entry": "레벨 25 + 테이머 자격증 이벤트 완수 (ColosseumInError)",
            "stamina": "'피로도'라고 부른다(입장권 아님). 최대 10 = ColosseumBattleInfo::"
                       "updateStamina 하드코딩. **1vs1/3vs3 각각 따로**(Colosseum_1vs1_Energy_Msg"
                       " / Colosseum_3vs3_Energy_Msg). 1개 충전 = 다이아 1개.",
            "refresh_cost": "상대 목록 새로고침은 **골드** 소모 (Colosseum_Refresh_Msg "
                            "'새로고침에는 %1$d 골드가 필요합니다'). 실패 시 Colosseum_Refresh_Error.",
            "streak_continue": "패배해도 **다이아로 연승을 이어갈 수 있었다** (ColosseumContinue).",
            "rewards": "일일/주간 보상 = **다이아 + 콜로세움 주화**를 우편함 지급 "
                       "(Colosseum_Daily_Result_1/2 · Colosseum_Weekly_Result_1/2). "
                       "재화 이름 = Colosseum_Coin '콜로세움 주화'.",
            # 🔴 2026-08-04 재정정 — 종전에 "탭은 일반전/등급전이고 1vs1·3vs3 는 별개 축"이라
            #   적었는데 **과잉 해석이었다.** ColosseumScene::initWidget 이 만드는 탭은
            #   TabImage::create ×4 → TitleLayer::setTabImageMenus 이고 프레임이
            #     txt_1vs1_per · txt_3vs3_per · txt_dual_%s · custom_tournament/txt_tournament_%s
            #   ⇒ 로비 탭 = **1vs1 / 3vs3 / 듀얼 / 토너먼트**. 우리 2탭(1vs1·3vs3)이 맞고,
            #   나머지 둘은 우리가 컷한 모드다. 일반전/등급전 문자열은 다른 화면 소유.
            "modes": "로비 탭 = 1vs1 / 3vs3 / 듀얼(⚫CUT) / 토너먼트(⚫CUT). "
                     "근거 = initWidget 의 TabImage 프레임 4종(txt_1vs1_per · txt_3vs3_per · "
                     "txt_dual_%s · addimg/custom_tournament/txt_tournament_%s).",
            # ⚠️ 2026-08-04 — **배선하지 않았다.** 문자열(ColosseumRaonTalkA/B/C ·
            #   ColosseumNuriTalkA/B, 등급 구간별 3단계)은 실재하는데 **호출 지점이
            #   디컴파일된 400+ 클래스 어디에도 없다**(`grep -rn "ColosseumRaon\|ColosseumNuri"` → 0건.
            #   TownNpcManager 의 "RaonTalk" 는 마을 NPC 라 별건).
            #   언제/어느 등급에서 뜨는지 근거가 없어 추측 배선을 하지 않는다(HARD RULE 6).
            #   되살리려면 남은 미디컴프 클래스에서 호출자를 먼저 찾아야 한다.
            "npc": "⚪미배선 — 라온·누리 대사 문자열은 실재(ColosseumRaonTalkA/B/C · "
                   "ColosseumNuriTalkA/B)하나 **호출 지점을 못 찾았다**. 트리거 조건 미상.",
            "cut": "일일매치·토너먼트·리플레이·방어팀·시즌 공지는 온라인 → ⚫CUT 유지.",
        },
        # 전투 로그 문구 — 원작 ColosseumTextBox 가 쓰던 포맷 그대로(유실 아님).
        # `%1$s` 류 위치 지정자는 GDScript 에 없어 순서 인자로 바꿔 둔다.
        "log": {
            "_source": "stringsData_KR.xml Colosseum* (원문 그대로, 위치지정자만 변환)",
            "attack": "%s이(가) %s에게 %s으로(로) %d의 피해를 주었습니다.",
            "defend": "%s이(가) %s의 %s을(를) 방어하여 %d의 피해를 받았습니다.",
            "evade": "%s이(가) %s의 %s을(를) 회피하였습니다.",
            "skill": "%s이(가) %s에게 %s을(를) 사용하였습니다.",
            "buff": "%s이(가) 자신에게 %s을(를) 사용하였습니다.",
            "recover": "%s의 체력이 %d만큼 회복되었습니다.",
            "poison": "%s의 체력이 중독에 의해 %d만큼 감소하였습니다.",
            "reflect": "%s이(가) %d만큼의 반사 피해를 받았습니다.",
            "confuse": "%s가 자신을 공격하여 %d의 피해를 입었습니다.",
            "ultimate": "%s이(가) 각성기를 사용하였습니다.",
            "ultimate_damage": "%s이(가) 각성기에 의해 %d의 피해를 받았습니다.",
            "stun": "%s이(가) 쓰러졌습니다.",
            "stuned": "%s의 움직임이 봉쇄되었습니다.",
            "skillblock": "%s이(가) %s의 %s의 사용을 차단하였습니다.",
            # 위 문구의 `%s`(공격 종류) 자리에 들어가는 이름.
            "atk_normal": "일반 공격",
            "atk_double": "연속 공격",
            "atk_critical": "강력한 공격",
            # 드래곤 HUD 의 낱말 — 원작 `MakeInterface::setHUD` @01050ffc 가 이 문자열을
            # BMFont 로 찍고 바로 오른쪽에 `FightDragon::getLevel()` 을 "%d" 로 붙인다
            # (`<ColosseumLevel>레벨</ColosseumLevel>`). 이름이 아니다 — 2026-08-05 정정.
            "level": "레벨",
            # 그 밖의 확정 문구
            "no_stamina": "피로도가 부족하여 전투에 참여가 불가능합니다.",
            "no_dragon": "전투에 참여가 가능한 드래곤이 없습니다.",
            "select_1vs1": "대전에 참가할 드래곤을 선택해주세요.",
            "select_3vs3": "대전에 참가할 드래곤을 3마리 선택해주세요.",
        },
        "rating": RATING,
        "ticket": TICKET,
        "refresh": REFRESH,
        "coin": COIN,
        "streak": STREAK,
        "bots": {"grades": BOT_GRADES, "tier_mix": TIER_BOT_MIX, "list_size": LIST_SIZE},
        "guards": build_guards(),
        "nick": build_nick(),
        "rankers": rankers,
    }


def main(argv: list[str]) -> int:
    # 윈도우 콘솔 기본 코드페이지(cp949)로는 이모지가 깨져 죽는다.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if "--init" in argv:
        print("[colosseum] 시트 스켈레톤")
        init_sheets(force="--force" in argv)
        migrate_guard_sheet()
        return 0
    migrate_guard_sheet()       # 열이 늘었으면 기입 내용을 지키며 헤더만 맞춘다
    data = build()
    n_rank = len(data["rankers"])
    n_nick = sum(len(v) for v in data["nick"].values())
    n_gd = sum(len(g["dragons"]) for g in data["guards"])
    n_ov = sum(1 for g in data["guards"] for d in g["dragons"] if d.get("stats"))
    print(f"[colosseum] 티어 {len(TIERS)} · 봇분류 {len(BOT_GRADES)} · 랭커 {n_rank} · 닉조각 {n_nick}")
    print(f"  연승방지봇 {len(data['guards'])}회 등장 · 드래곤 {n_gd}칸 · 임의스탯 지정 {n_ov}칸")
    if n_rank == 0:
        print(f"  ⚠️ 랭커 0명 — {RANKER_CSV.relative_to(REPO)} 를 채우면 반영된다(--init 로 생성).")
    if "--dry" in argv:
        return 0
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"-> {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
