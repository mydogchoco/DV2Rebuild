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
# 선대군 대사별 표정(🟦 사용자 기입 2026-08-07) — 초상 입 프레임이 표정 1~6 로 갈린다.
TALK_EMO_CSV = SHEETS / "sundaegun_talk.csv"
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
#
# 🟦 `skip_if_admin` (사용자 확정 2026-08-06) — **관리자 모드에서는 선대군이 등장하지 않는다.**
#   선대군은 이 세계를 다시 세운 사람 쪽 캐릭터라 관리자 본인과 마주칠 자리가 아니다.
#   판정은 `Colosseum.pending_guard` 가 `UserDB.is_admin()` 으로 한다(같은 플래그가 상점
#   PVP 탭 판매원도 가른다 — 관리자면 원작대로 라온).
GUARD_NPCS = [
    {"key": "nuri", "name": "누리", "talk_prefix": "ColosseumNuriTalk", "orig": True},
    {"key": "raon", "name": "라온", "talk_prefix": "ColosseumRaonTalk", "orig": True},
    {"key": "sundaegun", "name": "선대군", "talk_prefix": None, "orig": False,
     "skip_if_admin": True},
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

# 랭커 시트 열 — 🟦 2026-08-05 사용자 기입본에 맞춘다(`레이팅` 자리를 `등급`이 대신한다.
# 레이팅은 티어에서 나오고, 등급은 카드에 뜨는 드래곤 등급이다). `레이팅` 열이 있으면 읽는다.
RANKER_HEADER = ["닉네임", "티어", "등급", "드래곤id", "레벨", "각성", "젬", "스킬", "장비", "비고"]
RANKER_NOTE = ("드래곤은 이름으로 적어도 됩니다. 젬·스킬·장비는 쉼표로 나열. "
               "비고에 '모든 스킬 5레벨, 모든 장비 [에픽] 최대 강화, "
               "최적 옵션 장착(<전투유형들>: <옵션들> / …)' 형식으로 적으면 그대로 반영됩니다.")

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
    # 🟩 **환율은 자작이 아니라 위 표에서 파생된다.** `weekly` 6티어가 전부 정확히
    #    coin = dia × 10 이다(50/5 · 100/10 · 180/18 · 300/30 · 450/45 · 700/70).
    #    ⇒ 1 다이아 = 10 주화. 환전소(drops.json `cash.gold_pack` 1다이아=1000골드) 경유로
    #    1 주화 = 100 골드. 상점 PVP 탭 가격표(data/shop.json)가 이 축 하나에 걸려 있다.
    "_rate_note": "1 다이아 = 10 주화 = 1,000 골드. weekly 표 6티어 전부 coin=dia×10 에서 파생.",
    # 판당 지급 — 🟦 사용자 확정 2026-08-06. **원작엔 판당 주화가 없다**(서버가 일일/주간만
    # 내려줬다) → 자작 노브. 우편함 보상만으로는 계속 싸울 이유가 없어서 주 수도꼭지를 여기 둔다.
    # 패배 보상을 낮게 둔 건 일부러 지는 반복 파밍을 막기 위해서다.
    "per_match": {
        "_authored": True,
        "win": 6,
        "lose": 2,
        # 연승 1회당 +1, 최대 +10 (레이팅의 streak_bonus 와 같은 형태).
        "streak_bonus_per": 1,
        "streak_bonus_max": 10,
        # 3vs3 는 드래곤 3마리·판당 시간이 배라 배수를 준다.
        "mode_mult": {"single": 1.0, "team": 2.0},
    },
    # 티어 **최초** 승급 1회 보너스. 같은 티어를 다시 밟아도 주지 않는다(state `tier_paid`).
    "tier_up": {"1": 50, "2": 100, "3": 200, "4": 350, "5": 500},
}

# ── 대전 무대(스테이지) 속성 ───────────────────────────────────────────────
#
# 원작: 전투 시작에 무대 속성이 **룰렛으로** 정해지고, 그 속성과 **같은 종족**의 드래곤에게
# 버프 스파인이 붙는다. 네 조각 전부 클라에 남아 있다 —
#
#   ① 룰렛      `MakeInterface::addBottomPropertyUI` @01055d28
#                  `scene/colosseum/stage_bg.png`(anchor 0.5,0 · 화면 바닥 · 가로 꽉 채움, z=15)에
#                  Delay(1.0) → `createElement` → Delay((idx+11)×0.1) → …fade out
#              `MakeInterface::createElement` @0105daf0
#                  `item/etc/ele_*.png` 9칸을 150pt 간격으로 늘어놓고 0.1초마다 −150 이동.
#                  `checkElementMatch` 가 +450 에서 fade-in(0.3s, scale 0.825),
#                  중앙(0)에서 fade-out, −600 에서 +600 으로 되돌린다.
#                  당첨 칸만 마지막에 ScaleTo(0.1,0.9)→ScaleTo(0.05,0.825) 로 튄다.
#                  큰 도장 = 같은 아이콘 scale 2.5·alpha 0 → Delay(idx×0.1+1.0) →
#                  FadeTo(0.25,200)+ScaleTo(0.25,0.825) → 제거.
#   ② 속성→종족 `DAT_021c4ac4` — libgame.so 직접 디코드 = **[1,7,5,0,2,6,4,3,8]**
#                  (VA−0x100000 오프셋, [[dv2-rodata-constants-readable]]).
#                  createElement 의 칸 순서와 9/9 일치한다(교차검증).
#   ③ 버프 표시 `MakeInterface::checkStageBuff` @0105f368 → `showStageBuff` @0105f4b8
#                  종족이 일치하는 **양 진영 전원**에게 `battle/stage_<race>_buff_spine` 을
#                  드래곤 레이어 중앙에 scale **1.5**, z=10 으로 붙이고 "animation" 1회.
#   ④ 배경      `DualManager::getAttributeBgImage` @00f88b28 — 종족 → `stage_N.jpg`.
#
# 🟦 **보정치 +10% 는 사용자 확정 2026-08-05.** 클라의 `checkStageBuff` 는 **연출만** 하고
#    스탯을 건드리지 않는다(전수 확인 — 수치는 서버와 함께 유실).
STAGE = {
    "_source": "MakeInterface::createElement @0105daf0 · checkStageBuff @0105f368 · "
               "showStageBuff @0105f4b8 · DualManager::getAttributeBgImage @00f88b28 · "
               "DAT_021c4ac4 [1,7,5,0,2,6,4,3,8] (libgame.so 직접 디코드)",
    # 룰렛 칸 순서 = createElement 의 스프라이트 배열 순서(인덱스 0..8 = getStageElement 값).
    "wheel": ["aqua", "chaos", "dark", "earth", "fire", "holy", "light", "wind", "shadow"],
    # 종족 → 배경 jpg 번호(getAttributeBgImage 의 switch 그대로).
    # shadow 는 원작에 분기가 없어 default 인 stage_3 으로 떨어진다.
    "bg": {"earth": 3, "aqua": 0, "fire": 4, "wind": 7, "light": 6,
           "dark": 2, "holy": 5, "chaos": 1, "shadow": 3},
    # 🟦 사용자 확정 — 무대 속성과 같은 속성의 드래곤은 스탯 +10%.
    "buff_pct": 10,
    # ASSUMPTION: **어느 칸에 걸리는지는 근거가 없다.** 주 능력치 3종에만 건다 —
    #   cri/evd/blk 는 그 자체가 %라 "10% 상대 증가"가 뜻이 어긋난다.
    "buff_stats": ["hp", "att", "def"],
    # 연출 상수(원작 그대로). fight.gd 가 읽는다.
    "anim": {
        "step_sec": 0.1,     # createElement: MoveBy(0.1, (−150,0))
        "step_px": 150.0,    # 칸 간격
        "base_steps": 11,    # Delay((idx + 11) × 0.1) — 당첨까지의 총 스텝
        "window": 3,         # +450 = 3칸 밖에서 fade-in
        "fade_sec": 0.3,     # checkElementMatch 의 FadeTo/ScaleTo
        "icon_scale": 0.825,
        "stamp_scale": 2.5,  # 큰 도장 시작 배율
        "stamp_alpha": 200,  # FadeTo(0.25, 200)
        "stamp_sec": 0.25,
        "lead_sec": 1.0,     # addBottomPropertyUI 의 첫 Delay(1.0)
        "hold_sec": 1.0,     # 결정 후 Delay(1.0)
        "out_sec": 0.5,      # FadeTo(0.5, 0)
        "buff_scale": 1.5,   # showStageBuff 의 spine+0x150
    },
}

# ── BGM ────────────────────────────────────────────────────────────────────
#
# 로비는 원작이 명시한다 — `ColosseumScene::onEnterTransitionDidFinish` @00f41e00 이
# `SoundManager::playBackground("music/bg_colosseum.mp3", loop=1)`.
#
# 🟦 **대전 BGM 이 매 판 랜덤이라는 것은 사용자 확정 2026-08-05.**
#   디컴프한 `FightScene` · `FightManager` · `MakeInterface` 어디에도 전투 BGM 재생 호출이
#   없다(전수 grep) — 곡 목록도 서버/유실 경로라 클라에서 확인할 수 없다. 그래서 목록은
#   **이름이 그 용도를 말하는 보유 음원**으로 시작하고, 여기가 곧 튜닝 노브다.
#   (`DV2/music/` 에 `bg_colosseum_battle_1.mp3` · `_2.mp3` 실재. 더 넣고 싶으면 이 배열에.)
BGM = {
    "_source": "로비 = ColosseumScene::onEnterTransitionDidFinish @00f41e00. "
               "대전 랜덤 = 🟦 사용자 확정 2026-08-05(클라에 재생 호출 없음 — 전수 확인).",
    "lobby": "bg_colosseum",
    "battle": ["bg_colosseum_battle_1", "bg_colosseum_battle_2"],
}

TICKET = {
    "_note": "# ASSUMPTION — 원작 `energy` + ColosseumBattleInfo::updateStamina 회복 타이머 구조만 차용.",
    "max": 10,
    "recover_seconds": 600,   # 10분당 1
    "cost_per_match": 1,
}

STREAK = {
    "_note": "🟦 사용자 확정 — 연승방지봇. 첫 등장은 **25연승**(누리A)이고 이후 스케줄대로 "
             "50/75/100/150/999 에서 다시 나온다(GUARD_SCHEDULE). **문턱당 딱 한 판**만 "
             "나오고(2026-08-06 확정), 그 판이 끝나면 다음 문턱까지는 일반 봇이다. "
             "판정은 Colosseum.pending_guard() — 세이브의 `guard_served`(모드별로 붙어 본 "
             "문턱)를 보고, 연승이 끊기면 그 기록을 비운다. **예외는 없다** — 선대군(999)도 "
             "한 번뿐이고, 다시 만나려면 패배로 연승을 끊고 999를 다시 쌓아야 한다(약한 "
             "드래곤을 대신 출전시켜 일부러 질 수 있으므로 해금이 막히지 않는다 — 사용자 "
             "확정 2026-08-06). 종전의 guard_repeat(3판 유지)은 그래서 폐기했다.",
    "guard_at": 25,
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


# ── 대사 연출표(화자·표정) — 🔴 2026-08-06 원작 채굴 ──────────────────────────
#
# 종전에는 대사 문자열만 뽑아 **누리 혼자 전부 읽었고 표정도 없었다.** 원작은 그렇지 않다:
# 등장 이벤트를 만드는 곳이 `cocos2d::MatchingLayer::showNuriEvent` @00fb45e0(6,204B) ·
# `showRaonEvent` @00fb6574(4,600B) 이고, 거기서 **한 줄 = `TalkNpc` 한 개**를 만들어
# `NpcTalkLayer::create(CCArray, false)` 에 넘긴다.
#
#   TalkNpc::create(눈속도0.1, 눈유지3.0, 입0.03, 입0.03, <npc 폴더명>, <대사>,
#                   NpcType 몸통, NpcType 표정, NpcPosition 자리, isFirstShow, isStartSmall, ?)
#
# ⇒ **누리 이벤트에는 화자가 둘**이다 — `nuri`(자리 2 = 오른쪽)와 `jimon`(자리 1 = 왼쪽).
#    라온 이벤트만 혼자(자리 3 = 가운데)다. 자리 열거값은 `NpcManager::setTarget` 의 좌표식으로
#    확정했다(1 왼쪽 / 2 오른쪽 / 3 가운데 — `scripts/ui/npc_talk_layer.gd` 머리주석).
#
# 아래 표는 그 함수의 `TalkNpc::create` 인자를 **순서대로** 옮긴 것이다.
#   · 함수 분기 ↔ 단계는 `*(this + 0x200) = <줄 수>` 로 확정 — 누리 8=B / 10=A,
#     라온 6=C / 4=B / 3=A(단계별 줄 수가 서로 달라 유일하게 갈린다).
#   · 문자열 키 순서는 libgame.so 의 `.rodata` 참조를 직접 디코드해 대조했고
#     (`ColosseumNuriTalkA_1`…`A_10` · `B_1`…`B_8`), 내용으로도 교차검증된다:
#     A_9 "물론~ 나의 드래곤은 즈믄!" = 누리 / A_10 "왜 맨날! 나만 싸우는 건데!" = 즈믄 /
#     B_4 "정확히는 내가 싸우는 거지만...." = 즈믄.
#   · 표정 번호는 `npc_<name>/eye_<표정>_<프레임>` 그대로다(즈믄 1~7 · 누리 1~6 · 라온 1~6 보유).
#
# 한 줄 = (npc 폴더명, 몸통, 표정, 자리, isFirstShow, isStartSmall).
TALK_STAGING = {
    "ColosseumNuriTalk": {
        # showNuriEvent 분기2 (this+0x200 = 10)
        "A": [
            ("nuri",  1, 1, 2, 1, 0),
            ("nuri",  1, 1, 2, 0, 0),
            ("jimon", 1, 1, 1, 1, 0),
            ("jimon", 1, 1, 1, 0, 0),
            ("nuri",  2, 2, 2, 0, 1),
            ("jimon", 2, 2, 1, 0, 1),
            ("nuri",  1, 3, 2, 0, 1),
            ("nuri",  1, 3, 2, 0, 0),
            ("nuri",  2, 2, 2, 0, 0),
            ("jimon", 3, 7, 1, 0, 1),
        ],
        # showNuriEvent 분기1 (this+0x200 = 8)
        "B": [
            ("jimon", 1, 1, 1, 1, 0),
            ("jimon", 2, 2, 1, 0, 0),
            ("nuri",  2, 2, 2, 1, 0),
            ("jimon", 3, 7, 1, 0, 1),
            ("nuri",  2, 2, 2, 0, 1),
            ("nuri",  1, 1, 2, 0, 0),
            ("jimon", 1, 1, 1, 0, 1),
            ("jimon", 2, 2, 1, 0, 0),
        ],
    },
    "ColosseumRaonTalk": {
        # showRaonEvent — 라온 혼자(자리 3 = 가운데), 몸통 1 고정.
        "A": [
            ("raon", 1, 1, 3, 1, 0),
            ("raon", 1, 1, 3, 0, 0),
            ("raon", 1, 3, 3, 0, 0),
        ],
        "B": [
            ("raon", 1, 1, 3, 1, 0),
            ("raon", 1, 1, 3, 0, 0),
            ("raon", 1, 2, 3, 0, 0),
            ("raon", 1, 3, 3, 0, 0),
        ],
        "C": [
            ("raon", 1, 2, 3, 1, 0),
            ("raon", 1, 1, 3, 0, 0),
            ("raon", 1, 1, 3, 0, 0),
            ("raon", 1, 1, 3, 0, 0),
            ("raon", 1, 3, 3, 0, 0),
            ("raon", 1, 3, 3, 0, 0),
        ],
    },
}

# 화자 이름표는 원작이 `NpcTalkLayer::setTalk` 에서 `getString("NPC_" + 폴더명)` 으로 만든다.
# 우리는 화면이 문자열 번들을 읽지 않으므로 빌드 때 여기서 확정해 데이터에 싣는다.
NPC_NAME_KEY = "NPC_%s"


def read_npc_names(ids: set[str]) -> dict:
    """`<NPC_nuri>누리` 같은 원작 이름표. 없으면 그 id 는 빼고 화면이 봇 이름을 쓴다."""
    if not STRINGS_KR.exists():
        return {}
    t = STRINGS_KR.read_text(encoding="utf-8", errors="replace")
    out = {}
    for npc in sorted(ids):
        m = re.search(r"<%s>(.*?)</%s>" % (NPC_NAME_KEY % npc, NPC_NAME_KEY % npc), t, re.S)
        if m:
            out[npc] = m.group(1).strip()
    return out


def read_orig_talks(prefix: str) -> dict:
    """원작 대사 추출 — `<{prefix}{A|B|C}_{n}>` 를 단계별로 모은다.

    유실이 아니다: 라온·누리의 콜로세움 대사가 `stringsData_KR.xml` 에 그대로 있다.
    단계 문자(A/B/C)가 곧 **등급 구간**이다(A=첫 조우 · B=올라온 뒤 · C=고등급).

    한 줄은 **연출까지 포함한 dict** 로 나온다(위 `TALK_STAGING` — 화자·표정·자리).
    """
    if not prefix or not STRINGS_KR.exists():
        return {}
    t = STRINGS_KR.read_text(encoding="utf-8", errors="replace")
    raw: dict[str, list[tuple[int, str]]] = {}
    for m in re.finditer(r"<%s([A-C])_(\d+)>(.*?)</%s\1_\2>" % (prefix, prefix), t, re.S):
        stage, no, txt = m.group(1), int(m.group(2)), m.group(3)
        txt = txt.replace("&#10;", "\n").strip()
        raw.setdefault(stage, []).append((no, txt))
    stage_rows = TALK_STAGING.get(prefix, {})
    names = read_npc_names({r[0] for rows in stage_rows.values() for r in rows})
    out = {}
    for stage, pairs in raw.items():
        texts = [s for _, s in sorted(pairs)]
        rows = stage_rows.get(stage, [])
        # 연출표와 줄 수가 어긋나면 **조용히 넘어가지 않는다** — 원작 채굴본과 문자열 번들이
        # 어긋났다는 뜻이고, 그대로 실으면 엉뚱한 화자가 엉뚱한 대사를 읽는다.
        if len(rows) != len(texts):
            _err("대사 %s%s" % (prefix, stage),
                 "원작 연출표 %d줄 ↔ 문자열 %d줄 — TALK_STAGING 을 다시 채굴할 것"
                 % (len(rows), len(texts)))
            rows = []
        lines = []
        for i, txt in enumerate(texts):
            npc, body, emo, pos, first, small = rows[i] if rows else ("", 1, 1, 3, int(i == 0), 0)
            lines.append({
                "text": txt, "npc": npc, "name": names.get(npc, ""),
                "body": body, "emotion": emo, "pos": pos,
                "first_show": bool(first), "small": bool(small),
            })
        out[stage] = lines
    return out


# ── 시트 자유기입 해석기 ───────────────────────────────────────────────────
#
# 연승방지봇 시트의 젬·스킬·장비·비고 칸은 사람이 말로 적는다("일반젬 중간 등급 공공체").
# 여기서 **실제 id·키로 확정**해 data/colosseum.json 에 싣는다. 못 알아들으면 조용히
# 넘어가지 않고 **에러로 멈춘다**(CLAUDE.md §2-6 — 임의 대체 금지).
GEMS_JSON = REPO / "data" / "gems.json"
SKILLS_JSON = REPO / "data" / "skills.json"
EQUIP_JSON = REPO / "data" / "equipment.json"
DRAGONS_JSON = REPO / "data" / "dragons.json"

_ERRORS: list[str] = []


def _err(where: str, msg: str) -> None:
    _ERRORS.append(f"{where}: {msg}")


def _load(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def _norm(s: str) -> str:
    """이름 대조용 정규화 — 공백을 지우고 로마숫자를 아라비아로 맞춘다.

    '고속 이동' ↔ '고속이동' · '다크닉스 II' ↔ '다크닉스2' (시트는 아라비아로 적는다).
    """
    t = re.sub(r"\s+", "", s or "")
    for rom, ar in (("III", "3"), ("II", "2"), ("Ⅲ", "3"), ("Ⅱ", "2")):
        if t.endswith(rom):
            t = t[: -len(rom)] + ar
    return t


def dragon_index() -> dict:
    """정규화 이름 → 도감 id. 같은 이름이 둘이면 **뒤엣것을 쓰지 않고** 에러로 남긴다."""
    out: dict[str, int] = {}
    dup: set[str] = set()
    for d in (json.loads(DRAGONS_JSON.read_text(encoding="utf-8"))
              if DRAGONS_JSON.exists() else []):
        nm = _norm(str(d.get("name", "")))
        if not nm:
            continue
        if nm in out:
            dup.add(nm)
        out[nm] = int(d.get("id", 0))
    for nm in dup:
        out.pop(nm, None)
    return out


def resolve_dragon(text: str, where: str, index: dict) -> int:
    """`드래곤id` 칸 → 도감 id. **번호도 이름도 받는다**(랭커 시트는 이름으로 적혀 있다)."""
    t = (text or "").strip()
    if not t:
        return 0
    if t.isdigit():
        return int(t)
    did = index.get(_norm(t))
    if did is None:
        _err(where, f"드래곤 '{t}' 을 data/dragons.json 에서 못 찾았다"
                    f"(이름 그대로 적거나 도감 번호를 적어 주세요)")
        return 0
    return did


# 젬 code → 그 젬이 들어갈 슬롯 타입(원작 Dragon::getGemType 0=ATT 1=DEF 2=HP 3=ALL).
# 시트가 젬을 지정하면 **칸 타입도 그 젬에 맞춰 준다**(봇은 부화를 거치지 않으므로
# 랜덤 칸 타입 때문에 지정한 젬이 안 들어가는 일이 없어야 한다).
GEM_SLOT_TYPE = {
    "ATT": "ATT", "DEF": "DEF", "HP": "HP",
    "ATTDEF": "ATT", "ATTHP": "ATT", "DEFATT": "DEF", "DEFHP": "DEF",
    "HPATT": "HP", "HPDEF": "HP", "ATTDEFHP": "ALL",
    "SOULATT": "ATT", "SOULDEF": "DEF", "SOULHP": "HP", "SOULALL": "ALL",
}
GEM_AXIS = {"공": "ATT", "방": "DEF", "체": "HP"}     # '공공체' 표기의 글자 → 스탯 축
GEM_CATEGORY_WORD = {"일반젬": "normal", "일반": "normal",
                     "혼성젬": "hybrid", "혼성": "hybrid",
                     "소울젬": "soul", "소울": "soul"}


def _gem_part(part: str, where: str, table: dict, default_cnt: int) -> list[dict]:
    """젬 칸의 **한 토막** → [{"name","tier"} …] (칸 배정은 부르는 쪽이 한다)."""

    def tier_of(name: str) -> int:
        mx = max(0, len(table[name].get("tiers", [])) - 1)
        m = re.search(r"(\d+)\s*(?:티어|단계|등급)", part)
        if m:
            return max(0, min(mx, int(m.group(1))))
        if "최대" in part or "최고" in part or "만렙" in part:
            return mx
        if "중간" in part:
            return mx // 2
        if "최소" in part or "최하" in part or "최저" in part:
            return 0
        _err(where, f"젬 티어를 못 읽었다 — '{part}' (최대/중간/최소/N티어 중 하나를 적어 주세요)")
        return mx

    # ① 젬 이름이 그대로 적혀 있나(가장 확실한 표기).
    named = [nm for nm in table if _norm(nm) in _norm(part)]
    named.sort(key=len, reverse=True)
    if named:
        name = named[0]
        cnt = default_cnt
        m = re.search(r"(\d+)\s*개", part)
        if m:
            cnt = max(1, min(3, int(m.group(1))))
        return [{"name": name, "tier": tier_of(name)} for _ in range(cnt)]

    # ② 분류 + 축 글자(공/방/체) 3개.
    cat = ""
    for word, c in GEM_CATEGORY_WORD.items():
        if word in part:
            cat = c
            break
    axis = re.search(r"([공방체]{2,3})", part)
    if not cat or not axis:
        _err(where, f"젬 표기를 못 읽었다 — '{part.strip()}' (젬 이름을 그대로 적거나 "
                    f"'일반젬 중간 등급 공공체' 형식으로 적어 주세요)")
        return []
    by_code = {str(v.get("code", "")): k for k, v in table.items()
               if str(v.get("category", "")) == cat}
    out: list[dict] = []
    for ch in axis.group(1):
        code = GEM_AXIS[ch]
        if cat == "soul":
            code = "SOUL" + code
        name = by_code.get(code)
        if not name:
            _err(where, f"'{ch}' 축의 {cat} 젬이 data/gems.json 에 없다")
            continue
        out.append({"name": name, "tier": tier_of(name)})
    return out


def parse_gems(text: str, where: str) -> dict:
    """젬 칸 → {"types": [슬롯타입 ×3], "list": [{"slot","name","tier"} …]}.

    받는 표기(시트 실제 기입 기준):
      · `일반젬 중간 등급 공공체`      분류 + 티어말 + **축 글자 3개**(칸 순서대로)
      · `샌즈의 소울젬 최대 티어 3개`  젬 이름 + 티어말 + 개수
      · `체력의 소울젬 최대 티어 2개, 방어의 소울젬 최대 티어 1개`
                                       ← **쉼표로 여러 젬**(랭커 시트 표기). 적은 순서대로 칸을 채운다.
    티어말: 최대/최고 = 만렙 · 중간 = 가운데 단계 · 최소/최하 = 0 · `N티어` = 그 index.
    개수 생략 시 = 토막이 하나면 3칸, 여럿이면 1칸.
    """
    text = (text or "").strip()
    if not text:
        return {}
    gems = _load(GEMS_JSON)
    table = gems.get("gems", {})
    if not table:
        _err(where, "data/gems.json 을 읽지 못했다")
        return {}
    parts = [p for p in (q.strip() for q in text.split(",")) if p]
    entries: list[dict] = []
    for p in parts:
        entries += _gem_part(p, where, table, 3 if len(parts) == 1 else 1)
    if len(entries) > 3:
        _err(where, f"젬이 3칸을 넘는다({len(entries)}개) — '{text}'")
        return {}
    types: list[str] = []
    lst: list[dict] = []
    for i, e in enumerate(entries):
        code = str(table[e["name"]].get("code", ""))
        types.append(GEM_SLOT_TYPE.get(code, "ALL"))
        lst.append({"slot": i, "name": e["name"], "tier": e["tier"]})
    while len(types) < 3:
        types.append("ALL")
    return {"types": types, "list": lst}


def parse_skills(text: str, where: str, fallback_lv: int = 1) -> list[dict]:
    """스킬 칸 → [{"id", "level"} …].

    표기: `철갑 방패, 복수의 거울 5레벨` — 끝의 `N레벨` 은 **앞의 스킬 전부**에 걸린다
    (스킬마다 따로 적으면 그 스킬에만 걸린다). 이름은 공백을 무시하고 대조한다.
    `fallback_lv` = 칸에 레벨이 전혀 안 적혔을 때 쓸 값(랭커 시트는 비고의 '모든 스킬 N레벨').
    """
    text = (text or "").strip()
    if not text:
        return []
    db = _load(SKILLS_JSON)
    by_name = {_norm(v.get("name", "")): int(k) for k, v in db.items()}
    tail = re.search(r"(\d+)\s*레벨\s*$", text)
    default_lv = int(tail.group(1)) if tail else fallback_lv
    out: list[dict] = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.search(r"(\d+)\s*레벨", part)
        lv = int(m.group(1)) if m else default_lv
        nm = _norm(re.sub(r"\d+\s*레벨", "", part))
        if not nm:
            continue
        sid = by_name.get(nm)
        if sid is None:
            _err(where, f"스킬 '{part.strip()}' 을 data/skills.json 에서 못 찾았다")
            continue
        mx = int(db[str(sid)].get("max_level", 5))
        out.append({"id": sid, "level": max(1, min(mx, lv))})
    return out


def equip_catalog() -> dict:
    """`Equipment.catalog()` 와 **같은 키**를 파이썬에서 만든다(이름 → 키·칸).

    ⚠️ 키 규약이 어긋나면 게임이 장비를 못 찾는다 — scripts/systems/equipment.gd
       `catalog()` 의 키 조립과 1:1로 맞춘 것이다.
    """
    eq = _load(EQUIP_JSON)
    slots = eq.get("slots", [])

    def slot_of(main: dict) -> str:
        for s in slots:
            acc = s.get("accepts")
            if not isinstance(acc, list):
                continue
            for stat in main:
                if stat in acc:
                    return str(s.get("id"))
        return "all"

    out: dict[str, dict] = {}
    for kind, spec in (eq.get("basic") or {}).items():
        for g in spec.get("grades", []):
            out[g["name"]] = {"key": f"basic:{kind}:{int(g['grade'])}",
                              "slot": str(spec.get("slot", "all")), "dragon_id": 0}
    for e in (eq.get("event") or []):
        if not e.get("implemented", True):
            continue
        out[e["name"]] = {"key": f"event:{e['name']}",
                          "slot": slot_of(e.get("main", {})), "dragon_id": 0}
    for fam, famd in (eq.get("special") or {}).items():
        if not famd.get("implemented", True):
            continue
        for it in famd.get("items", []):
            out[it["name"]] = {"key": f"special:{fam}:{it['name']}",
                               "slot": slot_of(it.get("main", {})), "dragon_id": 0}
    for x in ((eq.get("exclusive") or {}).get("list") or []):
        if not x.get("implemented", False):
            continue
        out[x["name"]] = {"key": f"exclusive:{x['name']}", "slot": "all",
                          "dragon_id": int(x.get("dragon_id", 0))}
    art = eq.get("artifacts") or {}
    for a in art.get("types", []):
        for gi, gname in enumerate(art.get("grades", [])):
            out[f"{gname} {a['name']}"] = {"key": f"artifact:{a['name']}:{gi}",
                                           "slot": "artifact", "dragon_id": 0}
    return out


# 장비 칸의 **지시형 표기**(랭커 시트) — 이름 대신 "무엇을 끼울지"를 말로 적는다.
#   `전용장비(없을 경우 카이저 발록의 팔찌)` → 그 드래곤의 전용 장비, 없으면 괄호 안의 것
#   `위대한 아티팩트(이그니스)`              → 카탈로그 이름 '위대한 이그니스'
RE_EXCLUSIVE = re.compile(r"^전용\s*장비\s*(?:[(（]\s*(?:없을\s*경우|없으면)?\s*(.+?)\s*[)）])?$")
RE_ARTIFACT = re.compile(r"^(.+?)\s*아티팩트\s*[(（]\s*(.+?)\s*[)）]$")


def _equip_lookup(part: str, dragon_id: int, where: str,
                  cat: dict, norm: dict) -> dict | None:
    """장비 칸의 한 토막 → 카탈로그 항목. 못 읽으면 None(이미 _err 남김)."""
    part = part.strip()
    m = RE_EXCLUSIVE.match(part)
    if m:
        for v in cat.values():
            if v["dragon_id"] == dragon_id:
                return v
        alt = (m.group(1) or "").strip()
        if not alt:
            _err(where, f"드래곤 {dragon_id} 의 전용 장비가 없는데 대체 장비가 안 적혀 있다 "
                        f"— '{part}' (‘전용장비(없을 경우 …)’ 로 적어 주세요)")
            return None
        return _equip_lookup(alt, dragon_id, where, cat, norm)
    m = RE_ARTIFACT.match(part)
    if m:
        it = norm.get(_norm("%s %s" % (m.group(1), m.group(2))))
        if it is None:
            _err(where, f"아티팩트 '{part}' 을 못 찾았다 — 등급은 "
                        f"{(_load(EQUIP_JSON).get('artifacts') or {}).get('grades', [])} 중 하나")
        return it
    it = norm.get(_norm(part))
    if it is None:
        _err(where, f"장비 '{part}' 을 data/equipment.json 에서 못 찾았다")
    return it


def parse_equip(text: str, dragon_id: int, where: str,
                preset: dict | None = None) -> list[dict]:
    """장비 칸 → [{"key", "slot", (희귀도·옵션·강화)} …].

    쉼표로 나눈 **장비 이름**(또는 위 지시형 표기)을 카탈로그 키로 확정한다.
    칸(all/battle/support/artifact)은 장비의 주 능력치가 정한다(위키 §2 슬롯 표).

    칸이 겹칠 때 — 🟦 **사용자 확정 2026-08-06**: 첫 칸(`all`)은 `accepts:"*"` 라
    **아무 장비나 들어가는 범용 칸**이다(위키 §2 "전용장비를 포함한 말 그대로 모든 장비").
    그래서 같은 칸을 두 장비가 다투면 **먼저 적은 쪽을 `all` 로 올리고**, 뒤엣것이 제 칸을
    가져간다. 시트에 적은 순서가 곧 칸 순서로 읽히게 하기 위해서다.

    🔴 종전에는 반대로 **뒤엣것**을 `all` 로 밀었다. 그래서 선대군 800 번이
    `팔찌[support] · 모래시계[all]` 로 나왔는데, 사용자가 적은 순서대로면
    `팔찌[all] · 모래시계[support]` 여야 한다(전용 장비가 없어 첫 칸이 비는 줄이다).
    장착 개수는 어느 쪽이든 4개로 같았지만 배치가 시트와 어긋났다.

    `preset` = 비고에서 읽은 희귀도/옵션/강화(랭커 시트). 없으면 주 능력치만 있는 맨 장비.
    """
    text = (text or "").strip()
    if not text:
        return []
    cat = equip_catalog()
    norm = {_norm(k): v for k, v in cat.items()}
    out: list[dict] = []
    used: set[str] = set()
    for part in text.split(","):
        if not _norm(part):
            continue
        it = _equip_lookup(part, dragon_id, where, cat, norm)
        if it is None:
            continue
        if it["dragon_id"] and it["dragon_id"] != dragon_id:
            _err(where, f"장비 '{part.strip()}' 은 전용 장비라 드래곤 {it['dragon_id']} "
                        f"에게만 장착된다(이 줄은 {dragon_id})")
            continue
        slot = it["slot"]
        if slot in used:
            # ① 먼저 그 칸을 쓰고 있던 장비를 범용 칸(`all`)으로 올려 자리를 내준다.
            if "all" not in used:
                for prev in out:
                    if prev["slot"] == slot:
                        prev["slot"] = "all"
                        used.discard(slot)
                        used.add("all")
                        break
            # ② 그래도 못 앉으면(이미 `all` 까지 찼다) 남는 칸을 찾는다.
            if slot in used:
                slot = next((s for s in ("all", "battle", "support", "artifact")
                             if s not in used and (s == "all" or s == it["slot"])), "")
            if not slot:
                _err(where, f"장비 '{part.strip()}' 을 넣을 칸이 없다(칸 4개를 이미 썼다)")
                continue
        used.add(slot)
        e = {"key": it["key"], "slot": slot}
        if preset:
            e.update(preset)
        out.append(e)
    return out


# 비고 칸의 **면역** 표기. 원작에 없는 이벤트성 규칙이라 어휘를 여기에 고정한다.
#   `관통` `추가데미지` → 방어를 우회해 더해지는 피해(우리 `pure` + 장비 on-attack 추가피해)
#   그 밖에 문장에 등장하는 **스킬 이름** → 그 스킬로 받는 피해 0
IMMUNE_WORD_PURE = ("관통",)
IMMUNE_WORD_BONUS = ("추가데미지", "추가 데미지", "추가대미지", "추가 대미지")


def parse_immune(note: str, where: str) -> dict:
    text = (note or "").strip()
    if "면역" not in text:
        return {}
    db = _load(SKILLS_JSON)
    head = text.split("면역")[0]
    skills = sorted({int(k) for k, v in db.items()
                     if v.get("name") and _norm(v["name"]) in _norm(head)})
    out: dict = {}
    if skills:
        out["skills"] = skills
    if any(w in text for w in IMMUNE_WORD_PURE):
        out["pure"] = True
    if any(_norm(w) in _norm(text) for w in IMMUNE_WORD_BONUS):
        out["bonus"] = True
    if not out:
        _err(where, f"'면역' 이라 적혀 있는데 무엇에 면역인지 못 읽었다 — '{text}'")
    out["_text"] = text
    return out


# ── 랭커 시트 비고 칸 해석 ────────────────────────────────────────────────
#
# 랭커 줄의 비고는 **장비 스펙**을 말로 적는다(사용자 기입 원문):
#   "모든 스킬 5레벨, 모든 장비 [에픽] 최대 강화,
#    최적 옵션 장착(공격형, 체공형, 공방형: 관통, 크리, 공격 / 체력형, 방어형, 체방형: 관통, 회피, 체력)"
#
# ⚠️ **크리·회피는 부가 옵션으로 존재하지 않는다.** 원작 옵션 테이블은
#    `select hp, atk, def, blk, gold, exp, pure, depure, accuracy from info_item_acc`
#    9컬럼뿐이고(OptionSelectLayer.c:2343), 크리티컬·회피는 **장비 주 능력치** 쪽 축이다
#    (`Dragon::getCriticalRateAdd` / `getAvoidRateAdd` 가 `Item::getTypeParam` 을 읽는다).
#    ⇒ 그 두 낱말은 옵션으로 옮길 수 없어 **빌드 로그에 알리고 건너뛴다**(임의 대체 금지).
NOTE_OPTION_WORD = {
    "관통": "pure", "공격": "att", "체력": "hp", "생명": "hp", "방어": "def",
    "방어율": "blk", "블록": "blk", "골드": "gold", "경험치": "exp",
    "명중": "accuracy", "관통감소": "depure", "관통저항": "depure",
}
# 시트가 쓰는 전투유형 이름 → dragons.json `type` 코드(battle.gd:58 주석의 어휘 그대로).
NOTE_TYPE_CODE = {"공격형": "atk", "체력형": "hp", "방어형": "def",
                  "체방형": "hd", "체공형": "ha", "공방형": "ad"}

_NOTE_DROPPED: set[str] = set()      # 옮길 수 없는 옵션 낱말(로그용)


def parse_ranker_note(note: str, where: str) -> dict:
    """랭커 비고 → {"rarity", "skill_level", "options_by_type", "enhance_max"}.

    빈 칸이면 {} — 그때는 랭커 분류(BOT_GRADES["ranker"])의 폴백 규칙이 그대로 산다.
    """
    text = (note or "").strip()
    if not text:
        return {}
    eq = _load(EQUIP_JSON)
    opt = eq.get("option", {})
    grades = [str(g.get("name", "")) for g in opt.get("grades", [])]
    out: dict = {}
    # ① 장비 희귀도 — `[에픽]` 처럼 등급 이름이 적혀 있으면 그 인덱스.
    for i, g in enumerate(grades):
        if g and g in text:
            out["rarity"] = i
    # ② 강화 — '최대 강화'면 그 등급의 상한까지(원작 = 옵션 수 × enhance_per_option).
    if "최대 강화" in text or "최대강화" in text:
        out["enhance_max"] = True
    # ③ 스킬 레벨 — '모든 스킬 5레벨'.
    m = re.search(r"모든\s*스킬\s*(\d+)\s*레벨", text)
    if m:
        out["skill_level"] = int(m.group(1))
    # ④ 최적 옵션 — `최적 옵션 장착(<유형들>: <옵션들> / <유형들>: <옵션들>)`.
    m = re.search(r"최적\s*옵션[^(（]*[(（](.+)[)）]", text, re.S)
    if m:
        by_type: dict[str, list[str]] = {}
        for chunk in m.group(1).split("/"):
            if ":" not in chunk:
                continue
            types_s, stats_s = chunk.split(":", 1)
            codes = []
            for t in types_s.split(","):
                t = t.strip()
                if not t:
                    continue
                c = NOTE_TYPE_CODE.get(t)
                if c is None:
                    _err(where, f"비고의 전투유형 '{t}' 을 못 읽었다"
                                f"({'/'.join(NOTE_TYPE_CODE)} 중 하나)")
                    continue
                codes.append(c)
            stats = []
            for s in stats_s.split(","):
                s = s.strip()
                if not s:
                    continue
                k = NOTE_OPTION_WORD.get(s)
                if k is None:
                    _NOTE_DROPPED.add(s)          # 원작 옵션 테이블에 없는 축(크리·회피)
                    continue
                if k in opt.get("stats", []):
                    stats.append(k)
                else:
                    _NOTE_DROPPED.add(s)
            for c in codes:
                by_type[c] = list(stats)
        if by_type:
            out["options_by_type"] = by_type
    return out


def note_preset(note_spec: dict, dragon_type: str) -> dict:
    """비고 해석 결과 + 그 드래곤의 전투유형 → 장비 1점에 얹을 {rarity, options, enhance}.

    옵션 값은 **그 스탯의 상한**(option.value_ranges 최대)을 쓴다 — 비고의 '최적'.
    강화는 횟수만 싣고, 실제 증가는 게임 쪽(`Colosseum._apply_sheet_spec`)이
    `Equipment.enhance` 로 원작 규칙대로 굴린다(빌더가 수치를 짓지 않는다).
    """
    if not note_spec:
        return {}
    eq = _load(EQUIP_JSON)
    opt = eq.get("option", {})
    rarity = int(note_spec.get("rarity", 0))
    n_opt = 0
    grades = opt.get("grades", [])
    if 0 <= rarity < len(grades):
        n_opt = int(grades[rarity].get("options", 0))
    prefs: list[str] = list((note_spec.get("options_by_type", {}) or {}).get(dragon_type, []))
    ranges = opt.get("value_ranges", {})
    options: list[dict] = []
    for i in range(n_opt):
        if not prefs:
            break
        stat = prefs[i % len(prefs)]              # 적은 것이 모자라면 순서대로 돌려 채운다
        rng = ranges.get(stat, [1, 1])
        options.append({"stat": stat, "value": int(rng[-1])})
    out: dict = {"rarity": rarity}
    if options:
        out["options"] = options
    if note_spec.get("enhance_max"):
        out["enhance"] = rarity * int(opt.get("enhance_per_option", 5))
    return out


# 대사 칸의 구역 머리말 — `(최초 조우 시)` / `(반복)` 처럼 **괄호만 있는 줄**이다.
# 🟦 사용자 확정 2026-08-05: 최초 조우와 반복 조우의 대사를 다르게 쓴다.
TALK_HEAD_FIRST = ("최초", "처음", "첫")
TALK_HEAD_REPEAT = ("반복", "이후", "다시", "재")


def parse_talk(cell: str, where: str) -> dict:
    """대사 칸 → {"first": [...], "repeat": [...]}.

    **줄바꿈 한 번이 대화창 한 번**이다(사용자 확정 2026-08-05 — 원작 NPC 대사와 같다).
    빈 줄은 구역을 나눌 뿐 대화창이 되지 않는다.

    구역 머리말은 괄호만 있는 줄이다:
      `(최초 조우 시)` 아래 → 처음 만났을 때만
      `(반복)`         아래 → 두 번째부터
    머리말이 하나도 없으면 전부 **공통**(두 경우 다 같은 대사)이다.
    """
    first: list[str] = []
    repeat: list[str] = []
    cur = "both"
    for raw in (cell or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("(") and line.endswith(")"):
            head = line[1:-1]
            if any(w in head for w in TALK_HEAD_FIRST):
                cur = "first"
            elif any(w in head for w in TALK_HEAD_REPEAT):
                cur = "repeat"
            else:
                _err(where, f"대사 칸의 '{line}' 이 최초/반복 중 무엇인지 못 읽었다")
            continue
        if cur in ("first", "both"):
            first.append(line)
        if cur in ("repeat", "both"):
            repeat.append(line)
    return {"first": first, "repeat": repeat}


def read_stat_override(row: dict, where: str) -> tuple[dict, dict]:
    """임의 스탯 칸 → ({확정값}, {범위값}). 빈 칸은 넣지 않는다.

    받는 표기: `929` · `2.70%`(퍼센트 기호는 떼고 읽는다) · `15~40`(범위 — 상대를
    만들 때마다 그 사이에서 굴린다) · `1,200`(자릿점).
    """
    fixed: dict[str, float] = {}
    ranged: dict[str, list] = {}
    for col, key in GUARD_STAT_COLS.items():
        v = (row.get(col) or "").strip().replace(",", "").replace("%", "")
        if not v:
            continue
        m = re.fullmatch(r"(-?\d+(?:\.\d+)?)\s*[~∼-]\s*(-?\d+(?:\.\d+)?)", v)
        if m:
            lo, hi = float(m.group(1)), float(m.group(2))
            ranged[key] = [min(lo, hi), max(lo, hi)]
            continue
        try:
            f = float(v)
        except ValueError:
            _err(where, f"'{col}' 칸을 숫자로 못 읽었다 — '{v}'")
            continue
        fixed[key] = int(f) if f == int(f) else f
    return fixed, ranged


def talk_emotions() -> dict[str, int]:
    """선대군 표정 시트(`sundaegun_talk.csv`) → {대사 원문: 표정 1~6}.

    🟦 사용자 기입 2026-08-07. **대사 원문으로 매칭**한다 — 시트의 대사 열은 이 빌더가
    guard CSV 에서 뽑아 써 준 것이라 원문이 같고, 순번 매칭보다 줄 추가·삭제에 강하다.
    시트가 없거나 칸이 비면 1(웃음)로 남는다.
    """
    if not TALK_EMO_CSV.exists():
        return {}
    out: dict[str, int] = {}
    for r in read_csv(TALK_EMO_CSV):
        t = (r.get("대사") or "").strip()
        e = (r.get("표정(1~6)") or "").strip()
        if t and e.isdigit() and 1 <= int(e) <= 6:
            out[t] = int(e)
    return out


def csv_talk_lines(npc: dict, texts: list) -> list[dict]:
    """CSV 대사(선대군) → 원작 대사와 **같은 모양**의 줄.

    원작에 없는 캐릭터라 연출 근거가 없다 ⇒ 혼자(자리 3 = 가운데) · 몸통 1 로 두고,
    첫 줄에만 등장 연출을 준다. 표정은 사용자 표정 시트(`talk_emotions`)가 줄별로 정한다.
    """
    emo = talk_emotions()
    return [{
        "text": str(t), "npc": npc["key"], "name": npc["name"],
        "body": 1, "emotion": emo.get(str(t).strip(), 1), "pos": 3,
        "first_show": i == 0, "small": False,
    } for i, t in enumerate(texts)]


def build_guards() -> list[dict]:
    """연승방지봇 3단계(라온/누리/선대군).

    대사 = 원작에 있으면 원작(라온·누리), 없으면 CSV(선대군).
    드래곤 구성 = 전부 CSV(사용자 작성) — 랭커 시트와 같은 방식.
    """
    rows = read_csv(GUARD_CSV)
    # 행 → NPC 는 **이름 칸 우선**으로 묶는다. 키 칸은 사용자가 자유롭게 적을 수 있고
    # (실제로 선대군 줄의 키가 `sundaegun` → `LinearAlgebra` 로 바뀌었다), 우리 코드가
    # 아는 것은 GUARD_NPCS 의 이름이다. 키만 있고 이름이 없는 줄은 **바로 위 줄에 이어 붙는다**
    # (드래곤 3마리를 세 줄에 나눠 적는 시트 구조).
    name_to_key = {n["name"]: n["key"] for n in GUARD_NPCS}
    dindex = dragon_index()
    by_key: dict[str, dict] = {}
    sheet_key_to_npc: dict[str, str] = {}
    cur = ""
    for r in rows:
        raw_key = (r.get("키") or "").strip()
        name = (r.get("이름") or "").strip()
        if name and name in name_to_key:
            cur = name_to_key[name]
            if raw_key:
                sheet_key_to_npc[raw_key] = cur
        elif raw_key and raw_key in sheet_key_to_npc:
            cur = sheet_key_to_npc[raw_key]
        elif raw_key and raw_key in name_to_key.values():
            cur = raw_key
        elif name:
            _err(f"시트 '{name}'", "GUARD_NPCS 에 없는 이름이다(라온/누리/선대군 중 하나여야 한다)")
            continue
        if not cur:
            continue
        key = cur
        g = by_key.setdefault(key, {"dragons": [], "talk_csv": {"first": [], "repeat": []}})
        cell = (r.get("대사") or "").strip()
        if cell:
            t = parse_talk(cell, f"시트 {key} 대사")
            g["talk_csv"]["first"] += t["first"]
            g["talk_csv"]["repeat"] += t["repeat"]
        did = (r.get("드래곤id") or "").strip()
        if did:
            where = "%s 드래곤 %s" % (key, did)
            dnum = resolve_dragon(did, where, dindex)      # 번호도 이름도 받는다
            if dnum <= 0:
                continue
            d = {
                "id": dnum,
                "level": int(r.get("레벨") or 50),
                "awakened": (r.get("각성") or "").strip().upper() in ("O", "Y", "TRUE", "1"),
            }
            # 젬·스킬·장비는 말로 적힌 칸이라 여기서 **실제 id·키로 확정**한다.
            gem = parse_gems(r.get("젬", ""), where)
            if gem:
                d["gems"] = gem
            sk = parse_skills(r.get("스킬", ""), where)
            if sk:
                d["skills"] = sk
            ep = parse_equip(r.get("장비", ""), int(did), where)
            if ep:
                d["equip"] = ep
            # 이벤트성 매치 — 적힌 스탯만 최종값을 덮어쓴다(빈 칸은 계산대로).
            stats, ranged = read_stat_override(r, where)
            if stats:
                d["stats"] = stats
            if ranged:
                d["stats_roll"] = ranged
            imm = parse_immune(r.get("비고", ""), where)
            if imm:
                d["immune"] = imm
            grade = (r.get(GUARD_GRADE_COL) or "").strip()
            if grade:
                try:
                    d["grade"] = float(grade)
                except ValueError:
                    _err(where, f"'등급' 칸을 숫자로 못 읽었다 — '{grade}'")
            g["dragons"].append(d)
        if (r.get("레이팅") or "").strip().isdigit():
            g["rating"] = int(r["레이팅"])

    npcs = {}
    for npc in GUARD_NPCS:
        csvg = by_key.get(npc["key"], {})
        talks = read_orig_talks(npc["talk_prefix"])
        npcs[npc["key"]] = {
            "key": npc["key"], "name": npc["name"], "orig": npc["orig"],
            "skip_if_admin": npc.get("skip_if_admin", False),
            "talk": talks,                          # 원작 단계별 대사(A/B/C). 없으면 {}
            # 사용자 대사(선대군 등) — 최초 조우 / 반복 조우 두 벌.
            "talk_csv": csvg.get("talk_csv", {"first": [], "repeat": []}),
            "rating": csvg.get("rating", 0),
            "dragons": csvg.get("dragons", []),
            "_talk_source": "원작 %s*" % npc["talk_prefix"] if npc["talk_prefix"] else "사용자 CSV",
        }

    # 스케줄 한 줄 = 한 번의 등장. 대사 단계까지 여기서 확정한다.
    out = []
    for i, sch in enumerate(GUARD_SCHEDULE):
        npc = npcs[sch["key"]]
        stage = sch["talk_stage"]
        # 원작 대사(라온·누리)는 단계 자체가 등장마다 다르므로 최초/반복 구분이 없다.
        if stage:
            lines = npc["talk"].get(stage, [])
            first = []
        else:
            lines = csv_talk_lines(npc, npc["talk_csv"]["repeat"])
            first = csv_talk_lines(npc, npc["talk_csv"]["first"])
            if first == lines:
                first = []                      # 공통 대사뿐이면 갈라 둘 것이 없다
        out.append({
            "order": i + 1,
            "streak_at": sch["streak_at"],
            "key": npc["key"], "name": npc["name"], "orig": npc["orig"],
            "skip_if_admin": npc["skip_if_admin"],
            "talk_stage": stage,
            "lines": lines,                     # 이번 등장에 쓸 대사(확정본 · 반복 조우분)
            "lines_first": first,               # 최초 조우 전용(없으면 빈 배열 → lines 를 쓴다)
            "rating": npc["rating"],
            "dragons": npc["dragons"],
            "_talk_source": npc["_talk_source"],
        })
    return out


def build_rankers() -> list[dict]:
    """랭커 풀 — 사용자 CSV. 한 랭커가 여러 줄(드래곤 3~4마리)일 수 있다.

    🟦 2026-08-05 — 시트가 채워지면서 표기가 연승방지봇 시트와 같아졌다:
      · `드래곤id` 칸에 **이름**을 적는다("다크닉스2" → 도감 4208 '다크닉스 II')
      · 젬·스킬·장비를 **쉼표로 나열**한다(종전 `|` 구분 원시 문자열 저장은 폐기 —
        게임 쪽(`Colosseum._apply_sheet_spec`)이 파싱된 형태만 받는다)
      · `등급` 칸 = 카드에 뜨는 드래곤 등급(연승방지봇 시트와 같은 뜻)
      · `비고` 칸 = 장비 희귀도·강화·최적 옵션·스킬 레벨(위 parse_ranker_note)
    ⇒ 여기서 **실제 id·키로 확정**하고, 못 읽으면 빌드를 멈춘다(main 의 _ERRORS).
    """
    rows = read_csv(RANKER_CSV)
    dindex = dragon_index()
    dtype = {int(d.get("id", 0)): str(d.get("type", ""))
             for d in (json.loads(DRAGONS_JSON.read_text(encoding="utf-8"))
                       if DRAGONS_JSON.exists() else [])}
    by_nick: dict[str, dict] = {}
    order: list[str] = []
    for r in rows:
        nick = (r.get("닉네임") or "").strip()
        if not nick:
            continue
        if nick not in by_nick:
            by_nick[nick] = {"nick": nick, "tier": (r.get("티어") or "master").strip() or "master",
                             "rating": int((r.get("레이팅") or "0").strip() or 0),
                             "dragons": []}
            order.append(nick)
        raw = (r.get("드래곤id") or "").strip()
        if not raw:
            continue
        where = "랭커 %s / %s" % (nick, raw)
        did = resolve_dragon(raw, where, dindex)
        if did <= 0:
            continue
        note = parse_ranker_note(r.get("비고", ""), where)
        d = {
            "id": did,
            "level": int(r.get("레벨") or 50),
            "awakened": (r.get("각성") or "").strip().upper() in ("O", "Y", "TRUE", "1"),
        }
        gem = parse_gems(r.get("젬", ""), where)
        if gem:
            d["gems"] = gem
        sk = parse_skills(r.get("스킬", ""), where, int(note.get("skill_level", 1)))
        if sk:
            d["skills"] = sk
        ep = parse_equip(r.get("장비", ""), did, where,
                         note_preset(note, dtype.get(did, "")))
        if ep:
            d["equip"] = ep
        grade = (r.get(GUARD_GRADE_COL) or "").strip()
        if grade:
            try:
                d["grade"] = float(grade)
            except ValueError:
                _err(where, f"'등급' 칸을 숫자로 못 읽었다 — '{grade}'")
        by_nick[nick]["dragons"].append(d)
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
    # 사용자가 엑셀로 열어 둔 채 빌드를 돌리는 일이 잦다. 시트 갱신 실패로 **데이터 빌드까지**
    # 죽이지 않는다 — 경고만 하고 기존 내용 그대로 진행한다(읽기는 이미 끝났다).
    try:
        with GUARD_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(out)
    except PermissionError:
        print(f"  ⚠️ {GUARD_CSV.relative_to(REPO)} 가 잠겨 있어 시트 갱신을 건너뛴다"
              " (엑셀 등에서 열려 있는지 확인). 데이터 빌드는 계속한다.")
        return False
    added = [c for c in GUARD_HEADER if c not in old]
    print(f"  ~ {GUARD_CSV.relative_to(REPO)} — "
          + (f"열 추가(기입 내용 보존): {', '.join(added)}" if added else "등장연승 갱신"))
    return True


def init_sheets(force: bool = False) -> None:
    SHEETS.mkdir(parents=True, exist_ok=True)
    if force or not RANKER_CSV.exists():
        with RANKER_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(RANKER_HEADER)
            for i in range(3):
                w.writerow(["", "master", "", "", "50", "O", "", "", "",
                            RANKER_NOTE if i == 0 else ""])
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
                        "오리지널 캐릭터 — 대사도 채워 주세요(줄바꿈 하나 = 대화창 하나, "
                        "'(최초 조우 시)' / '(반복)' 줄로 나눕니다). "
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
                  # 🟦 매칭 대기 시간(초) — 사용자 확정 2026-08-05.
                  #   원작은 서버 응답까지 걸린 시간이라 고정값이 아니었다(`MatchingLayer` 가
                  #   `repeatRequest_VS*` 를 반복하며 기다린다). 우리는 상대가 이미 정해져
                  #   있으므로 연출 길이만 고정한다.
                  "matching_seconds": 3,
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
            # ✅ **2026-08-05 해결 — 주인은 `MatchingLayer` 였다.**
            #   `MatchingLayer::showNuriEvent` @00fb45e0(6,204B) ·
            #   `showRaonEvent` @00fb6574(4,600B). 못 찾았던 이유는 그때 매칭 화면을 통째로
            #   컷해 둬서 그 클래스를 조회 대상에 넣지 않았기 때문이다(매칭 연출은 부활했다 —
            #   `scripts/ui/matching.gd`). 대사 배선 자체는 아직 ⚪ 미이식이다.
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
            # 면역 — 낱말은 원작 `<Immunity>면역</Immunity>` 이고, 문장만 우리가 짰다
            # (연승방지봇 전용 이벤트 규칙이라 원작에 대응 문장이 없다).
            "immune": "%s은(는) %s에 면역입니다.",
            "atk_normal": "일반 공격",
            "atk_double": "연속 공격",
            "atk_critical": "강력한 공격",
            # 드래곤 HUD 의 낱말 — 원작 `MakeInterface::setHUD` @01050ffc 가 이 문자열을
            # BMFont 로 찍고 바로 오른쪽에 `FightDragon::getLevel()` 을 "%d" 로 붙인다
            # (`<ColosseumLevel>레벨</ColosseumLevel>`). 이름이 아니다 — 2026-08-05 정정.
            "level": "레벨",
            # 매칭 대기 화면 문구 — 원작 `MatchingLayer::init` @00fae280 이
            # `LoadingLayer::initString` 으로 넘긴다. 원문 그대로.
            "matching": "상대를 찾는 중",
            # 그 밖의 확정 문구
            "no_stamina": "피로도가 부족하여 전투에 참여가 불가능합니다.",
            "no_dragon": "전투에 참여가 가능한 드래곤이 없습니다.",
            "select_1vs1": "대전에 참가할 드래곤을 선택해주세요.",
            "select_3vs3": "대전에 참가할 드래곤을 3마리 선택해주세요.",
        },
        "stage": STAGE,
        "bgm": BGM,
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


def _talk_peek(lines: list) -> str:
    """대사 미리보기 한 토막 — 줄은 `{text, npc, …}` dict 다."""
    if not lines:
        return "“”"
    ln = lines[0]
    who = (ln.get("name") or ln.get("npc") or "").strip()
    return "“%s%s…”" % (f"[{who}] " if who else "", str(ln.get("text", ""))[:28])


def _talk_cast(lines: list) -> str:
    """그 단계에 나오는 화자를 등장 순서대로 — 누리 이벤트가 2인극인지 눈으로 보라고."""
    seen = []
    for ln in lines:
        who = (ln.get("name") or ln.get("npc") or "").strip()
        if who and who not in seen:
            seen.append(who)
    return "+".join(seen) if seen else "-"


def _print_guards(guards: list[dict]) -> None:
    """해석 결과를 사람이 읽는 형태로 찍는다 — 사용자가 시트 의도와 대조할 수 있게."""
    db = _load(SKILLS_JSON)
    seen: set[str] = set()
    for g in guards:
        if g["key"] in seen:
            continue
        seen.add(g["key"])
        print(f"  [{g['name']}] 등장 {[s['streak_at'] for s in GUARD_SCHEDULE if s['key'] == g['key']]}"
              f" · 드래곤 {len(g['dragons'])}마리")
        # 대사는 등장(스케줄 줄)마다 다를 수 있으므로 NPC 단위가 아니라 여기서 전부 찍는다.
        for h in guards:
            if h["key"] != g["key"]:
                continue
            tag = f"{h['streak_at']}연승" + (f" 대사{h['talk_stage']}" if h["talk_stage"] else "")
            if h.get("lines_first"):
                print(f"        대사 {tag} · 최초 조우 {len(h['lines_first'])}창"
                      f"  {_talk_peek(h['lines_first'])}")
                print(f"        대사 {tag} · 반복     {len(h['lines'])}창"
                      f"  {_talk_peek(h['lines'])}")
            elif h.get("lines"):
                print(f"        대사 {tag} · {len(h['lines'])}창"
                      f"  {_talk_peek(h['lines'])}  화자 {_talk_cast(h['lines'])}")
        for d in g["dragons"]:
            bits = []
            if d.get("stats"):
                bits.append(" ".join(f"{k}={v}" for k, v in d["stats"].items()))
            if d.get("stats_roll"):
                bits.append(" ".join(f"{k}={v[0]}~{v[1]}" for k, v in d["stats_roll"].items()))
            if d.get("grade"):
                bits.append(f"등급={d['grade']}")
            print(f"    · id {d['id']} Lv{d['level']}{' 각성' if d.get('awakened') else ''}"
                  f"  {' | '.join(bits) if bits else '스탯=계산대로'}")
            if d.get("gems"):
                gm = d["gems"]
                print("        젬  " + ", ".join(f"{e['name']}(T{e['tier']})" for e in gm["list"])
                      + f"  칸타입 {gm['types']}")
            if d.get("skills"):
                print("        스킬 " + ", ".join(
                    f"{db.get(str(s['id']), {}).get('name', s['id'])} Lv{s['level']}"
                    for s in d["skills"]))
            if d.get("equip"):
                print("        장비 " + ", ".join(f"{e['key'].split(':')[-1]}[{e['slot']}]"
                                                 for e in d["equip"]))
            if d.get("immune"):
                im = d["immune"]
                names = [db.get(str(i), {}).get("name", str(i)) for i in im.get("skills", [])]
                extra = [w for w, on in (("관통", im.get("pure")), ("추가피해", im.get("bonus"))) if on]
                print("        면역 " + ", ".join(names + extra))


def _print_rankers(rankers: list[dict]) -> None:
    """랭커 해석 결과 — 시트 의도와 대조할 수 있게 사람이 읽는 형태로."""
    db = _load(SKILLS_JSON)
    ds = {int(d.get("id", 0)): str(d.get("name", ""))
          for d in (json.loads(DRAGONS_JSON.read_text(encoding="utf-8"))
                    if DRAGONS_JSON.exists() else [])}
    grades = [str(g.get("name", "")) for g in _load(EQUIP_JSON).get("option", {}).get("grades", [])]
    key_name = {v["key"]: k for k, v in equip_catalog().items()}
    for r in rankers:
        print(f"  [{r['nick']}] {r['tier']}"
              + (f" · 레이팅 {r['rating']}" if r.get("rating") else "")
              + f" · 드래곤 {len(r['dragons'])}마리")
        for d in r["dragons"]:
            print(f"    · {ds.get(d['id'], '?')}({d['id']}) Lv{d['level']}"
                  f"{' 각성' if d.get('awakened') else ''}"
                  + (f" 등급 {d['grade']:g}" if d.get("grade") else ""))
            if d.get("gems"):
                print("        젬  " + ", ".join(f"{e['name']}(T{e['tier']})"
                                                 for e in d["gems"]["list"]))
            if d.get("skills"):
                names = [f"{db.get(str(s['id']), {}).get('name', s['id'])} Lv{s['level']}"
                         for s in d["skills"]]
                # 장착 칸은 2개다(원작 Dragon::getSkill(0/1)).
                # 🟦 2개보다 많이 적으면 **전투마다 그 중 랜덤 2개**를 장착한다(사용자 확정 2026-08-05).
                tag = f"{len(names)}개 중 전투마다 랜덤 2개" if len(names) > 2 else "장착"
                print(f"        스킬 {tag}: " + ", ".join(names))
            for e in d.get("equip", []):
                bits = f"{key_name.get(e['key'], e['key'])}[{e['slot']}]"
                if "rarity" in e and 0 <= int(e["rarity"]) < len(grades):
                    bits += f" {grades[int(e['rarity'])]}"
                if e.get("options"):
                    bits += " " + "+".join(f"{o['stat']}{o['value']}" for o in e["options"])
                if e.get("enhance"):
                    bits += f" 강화{e['enhance']}"
                print("        장비 " + bits)


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
    print(f"[colosseum] 티어 {len(TIERS)} · 봇분류 {len(BOT_GRADES)} · 랭커 {n_rank} · 닉조각 {n_nick}")
    _print_guards(data["guards"])
    _print_rankers(data["rankers"])
    if _NOTE_DROPPED:
        # 임의 대체 금지 — 옮길 수 없는 낱말은 조용히 버리지 않고 매번 알린다.
        print("\n  ⚠️ 비고의 옵션 낱말 중 **부가 옵션으로 존재하지 않는 축**은 뺐다: "
              + ", ".join(sorted(_NOTE_DROPPED))
              + "\n     원작 옵션 테이블(info_item_acc)은 hp/atk/def/blk/gold/exp/pure/depure/"
                "accuracy 9컬럼뿐이고,\n     크리티컬·회피는 **장비 주 능력치** 축이다"
                "(그 장비를 끼우는 것으로만 얻는다).")
    if _ERRORS:
        # 못 알아들은 칸이 있으면 **쓰지 않는다** — 반쯤 반영된 봇이 더 나쁘다.
        print("\n  ⛔ 시트에서 못 읽은 칸 %d 건 — data/colosseum.json 을 쓰지 않았다:" % len(_ERRORS))
        for e in _ERRORS:
            print("     · " + e)
        return 1
    if n_rank == 0:
        print(f"  ⚠️ 랭커 0명 — {RANKER_CSV.relative_to(REPO)} 를 채우면 반영된다(--init 로 생성).")
    if "--dry" in argv:
        return 0
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"-> {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
