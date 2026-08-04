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
import csv, json, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "data" / "colosseum.json"
SHEETS = REPO / "docs" / "input" / "sheets"
RANKER_CSV = SHEETS / "colosseum_ranker.csv"
NICK_CSV = SHEETS / "colosseum_nick.csv"

# ── 원작 채굴값 ────────────────────────────────────────────────────────────
# StrategyManager::GetTier — id 는 원작 그대로(1=MASTER 가 최상위, 숫자가 작을수록 높다).
TIERS = [
    {"id": 5, "key": "bronze",   "name": "BRONZE",   "min_rating": 0},
    {"id": 4, "key": "silver",   "name": "SILVER",   "min_rating": 1200},
    {"id": 3, "key": "gold",     "name": "GOLD",     "min_rating": 1500},
    {"id": 2, "key": "platinum", "name": "PLATINUM", "min_rating": 1900},
    {"id": 1, "key": "master",   "name": "MASTER",   "min_rating": 2300},
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
    "lose_mult_by_tier": {"5": 0.5, "4": 0.8, "3": 1.0, "2": 1.2, "1": 1.5},
}

TICKET = {
    "_note": "# ASSUMPTION — 원작 `energy` + ColosseumBattleInfo::updateStamina 회복 타이머 구조만 차용.",
    "max": 10,
    "recover_seconds": 600,   # 10분당 1
    "cost_per_match": 1,
}

STREAK = {
    "_note": "🟦 사용자 확정 — 연승방지봇. 연승이 guard_at 에 닿으면 그 다음 상대는 "
             "한 단계 위 분류에서 나오고, guard_repeat 회 연속 유지된다.",
    "guard_at": 5,
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
    "silver":   {"novice": 70,  "adept": 30,  "ranker": 0},
    "gold":     {"novice": 30,  "adept": 70,  "ranker": 0},
    "platinum": {"novice": 5,   "adept": 80,  "ranker": 15},
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


def init_sheets(force: bool = False) -> None:
    SHEETS.mkdir(parents=True, exist_ok=True)
    if force or not RANKER_CSV.exists():
        with RANKER_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["닉네임", "티어", "레이팅", "드래곤id", "레벨", "각성", "젬", "스킬", "장비", "비고"])
            for _ in range(3):
                w.writerow(["", "master", "", "", "50", "O", "", "", "", ""])
        print(f"  + {RANKER_CSV.relative_to(REPO)}")
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
        "rating": RATING,
        "ticket": TICKET,
        "streak": STREAK,
        "bots": {"grades": BOT_GRADES, "tier_mix": TIER_BOT_MIX, "list_size": LIST_SIZE},
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
        return 0
    data = build()
    n_rank = len(data["rankers"])
    n_nick = sum(len(v) for v in data["nick"].values())
    print(f"[colosseum] 티어 {len(TIERS)} · 봇분류 {len(BOT_GRADES)} · 랭커 {n_rank} · 닉조각 {n_nick}")
    if n_rank == 0:
        print(f"  ⚠️ 랭커 0명 — {RANKER_CSV.relative_to(REPO)} 를 채우면 반영된다(--init 로 생성).")
    if "--dry" in argv:
        return 0
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"-> {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
