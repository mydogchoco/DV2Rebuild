"""데이터 트랙 — 속성 조합 팀버프 30종 → data/team_buffs.json.

**출처 = 원작 문자열 테이블**(`DV2/string/stringsData_KR.xml`). 위키가 아니다.
  <Combine1..30>            버프명 30종
  <Combine_Comment_1..30>   효과 (예: "HP+10% ATK+10% CRT+5%")
  <CombineHP/ATK/DEF/EVD/CRI/BLK/PURE/CRIPW/ANTI_PURE/SPECIAL/ACC>  스탯 약어 사전

즉 `info_dragon_team_buf` 의 name·effect 열은 **유실이 아니라 클라 문자열 테이블에 남아 있었다**
(docs/ref/design/team_buff_analysis.md §0 의 "이름·수치 유실" 판정을 이 스크립트가 정정한다).
남은 유실은 `combine`(조합 구성) 한 열뿐이다.

아이콘(img 열): `TeamBuff::createIcon` 이 `battle/<res>/combine_mark.png` ·
`combine_outline.png` 를 만든다(TeamBuff.c:658-669). 추출 에셋의 `battle/*/combine_mark.png`
폴더가 정확히 24개이고 Combine1..24 와 의미가 1:1로 대응해 그 순서로 매핑했다
(flood=대홍수, gaia=가이아, corona=코로나 …). 25~30(그림자 계열)은 후기 추가분이라
우리 구판 덤프에 폴더가 없다.

위키(etc.pdf §2.3.3.1)와 다른 곳 — **원작 문자열이 이긴다**:
  - 10 신의 사자: 원작 `CRT+5% DEF+15%` / 위키 "방어력 15%, 크리티컬 확률 10%"
  - 이름 표기: 원작 "수퍼노바·물빛 섬광·헬파이어" / 위키 "슈퍼노바·물빛섬광·헬 파이어"

사용:  python scripts/tools/build_team_buffs.py
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
XML = REPO / "DV2" / "string" / "stringsData_KR.xml"
OUT = REPO / "data" / "team_buffs.json"
SHEET = REPO / "docs" / "input" / "review" / "team_buff_sheet.md"

# 원작 스탯 약어 → 우리 키 + 적용 방식.
#   pct   = 배수(HP+30% → ×1.30)
#   point = 퍼센트 포인트(CRT+10% → 크리 10 → 20)
#   flat  = 정수 가산
# ⚠️ point/pct 구분은 ASSUMPTION. 확률 스탯을 배수로 읽으면 증가폭이 1%p 수준이라
#    표 수치(EVD+11%, BLK+6% 같은 어중간한 값)가 의미를 잃는다.
STAT = {
    "HP":        ("hp", "pct"),
    "ATK":       ("att", "pct"),
    "DEF":       ("def", "pct"),
    "EVD":       ("evd", "point"),
    "CRT":       ("cri", "point"),
    "CRI":       ("cri", "point"),
    "BLK":       ("blk", "point"),
    "CRIPW":     ("cri_pow", "point"),
    "PURE":      ("pure", "flat"),
    "ANTI_PURE": ("depure", "flat"),
    "SPECIAL":   ("awaken_rate", "point"),
    "ACC":       ("accuracy", "point"),
}

# Combine1..24 ↔ battle/<res>/ 아이콘 폴더(추출 에셋 실재, 의미 1:1 대응).
IMG = {
    1: "flood", 2: "apocalypse", 3: "amagethon", 4: "gaia", 5: "corona",
    6: "highness", 7: "supernova", 8: "hurricane", 9: "legion", 10: "avatar",
    11: "rainbow", 12: "dark", 13: "light", 14: "storm", 15: "aqualight",
    16: "shimmer", 17: "landslide", 18: "blackwind", 19: "tearsofagod",
    20: "hellfire", 21: "lavastorm", 22: "mirinae", 23: "asgard", 24: "dyingbreath",
}


# ── combine(조합 구성) — 추론 채움 (2026-07-27, 사용자 승인) ────────────────
# ⚠️ 이 열만은 **원작 데이터가 아니다.** info_dragon_team_buf.combine 은 서버 갱신분이라
#    어디에도 없고, 위키도 이 열을 이미지로만 실어서 텍스트 추출이 불가능했다.
#    사용자가 "위키 문서를 보고 네가 채워라"라고 승인해(HARD RULE 6 예외) **버프명·효과·
#    아이콘 res명의 의미**로 추론해 채운다. 원작과 다를 수 있으며 사용자 조정 대상이다.
#
# 추론 규칙:
#   1) 9속성 각각에 **단일속성 3마리**(X:3) 조합을 하나씩 배정한다. 이름이 그 속성을
#      직접 가리키는 버프를 골랐다 — 코로나(태양)=fire, 대홍수=aqua, 가이아(대지신)=earth,
#      허리케인=wind, 태초의 빛/어둠/그림자=light/dark/shadow, 신의 사자=holy, 악의 군세=chaos.
#      효과도 이를 뒷받침한다(단일 대형 스탯: ATK+25 / HP+30 / DEF+25 / BLK+15).
#   2) 나머지 21종은 이름이 가리키는 **2속성(2+1) 또는 3속성(1+1+1)** 혼합으로 배정.
#      이름이 조합을 그대로 말해 주는 것부터 고정했다:
#        물빛 섬광=aqua+light · 흑풍(검은 바람)=dark+wind · 빛과 그림자=light+shadow
#        용암폭풍=fire+earth+wind · 이클립스(일식)=dark+light · 헬파이어(지옥불)=fire+dark
#   3) 30종 조합이 **서로 겹치지 않게** 배정했다(겹치면 한 파티에 여러 버프가 동시 발동).
COMBINE = {
    1:  ({"aqua": 3},                        "대홍수 = 물 3"),
    2:  ({"fire": 2, "chaos": 1},            "아포칼립스(종말) = 불2+혼돈1"),
    3:  ({"light": 1, "dark": 1, "holy": 1},  "아마겟돈(선악 최종전) = 빛·어둠·신성 각1"),
    4:  ({"earth": 3},                       "가이아(대지신) = 대지 3"),
    5:  ({"fire": 3},                        "코로나(태양 대기) = 불 3"),
    6:  ({"holy": 2, "earth": 1},            "지고의 영광 = 신성2+대지1"),
    7:  ({"fire": 2, "light": 1},            "수퍼노바(초신성) = 불2+빛1"),
    8:  ({"wind": 3},                        "허리케인 = 바람 3"),
    9:  ({"chaos": 3},                       "악의 군세 = 혼돈 3"),
    10: ({"holy": 3},                        "신의 사자 = 신성 3"),
    11: ({"light": 2, "wind": 1},            "레인보우 선샤인 = 빛2+바람1"),
    12: ({"dark": 3},                        "태초의 어둠 = 어둠 3"),
    13: ({"light": 3},                       "태초의 빛 = 빛 3"),
    14: ({"wind": 2, "dark": 1},             "폭풍우의 밤 = 바람2+어둠1"),
    15: ({"aqua": 2, "light": 1},            "물빛 섬광 = 물2+빛1 (이름 그대로)"),
    16: ({"fire": 2, "earth": 1},            "아지랑이(열기) = 불2+대지1"),
    17: ({"earth": 2, "wind": 1},            "산사태 = 대지2+바람1"),
    18: ({"dark": 2, "wind": 1},             "흑풍(검은 바람) = 어둠2+바람1 (이름 그대로)"),
    19: ({"holy": 2, "aqua": 1},             "신의 눈물 = 신성2+물1"),
    20: ({"fire": 2, "dark": 1},             "헬파이어(지옥불) = 불2+어둠1"),
    21: ({"fire": 1, "earth": 1, "wind": 1},  "용암폭풍 = 불·대지(용암)+바람(폭풍)"),
    22: ({"light": 2, "shadow": 1},          "미리내(은하수) = 빛2+그림자1"),
    23: ({"holy": 2, "wind": 1},             "아스가르드(신들의 나라) = 신성2+바람1"),
    24: ({"dark": 2, "chaos": 1},            "죽음의 숨결 = 어둠2+혼돈1"),
    25: ({"dark": 2, "light": 1},            "이클립스(일식) = 어둠이 빛을 가림"),
    26: ({"shadow": 2, "dark": 1},           "심연의 그림자 = 그림자2+어둠1"),
    27: ({"shadow": 2, "light": 1},          "빛과 그림자 = 그림자2+빛1 (이름 그대로)"),
    28: ({"shadow": 3},                      "태초의 그림자 = 그림자 3"),
    29: ({"shadow": 2, "wind": 1},           "쉐도우 댄스 = 그림자2+바람1"),
    30: ({"earth": 2, "light": 1},           "신기루(사막 아지랑이) = 대지2+빛1"),
}

TOKEN = re.compile(r"([A-Z_]+)\+(\d+)")


def read_tag(text: str, tag: str) -> str | None:
    m = re.search(rf"<{tag}>(.*?)</{tag}>", text, re.S)
    return m.group(1).strip() if m else None


def build() -> dict:
    text = XML.read_text(encoding="utf-8", errors="replace")
    buffs = []
    unknown: set[str] = set()
    for no in range(1, 31):
        name = read_tag(text, f"Combine{no}")
        comment = read_tag(text, f"Combine_Comment_{no}")
        if name is None or comment is None:
            print(f"  ! Combine{no} 없음 — 건너뜀", file=sys.stderr)
            continue
        effect = {}
        for abbr, val in TOKEN.findall(comment):
            if abbr not in STAT:
                unknown.add(abbr)
                continue
            key, mode = STAT[abbr]
            effect[key] = {"mode": mode, "value": int(val)}
        entry = {
            "no": no,
            "name": name,
            "combine": COMBINE.get(no, ({}, ""))[0],   # 추론 채움(원작 데이터 아님) — _combine_basis 참조
            "_combine_basis": COMBINE.get(no, ({}, ""))[1],
            "effect": effect,
            "effect_text": comment,
            "_source": "DV2/string/stringsData_KR.xml <Combine%d>/<Combine_Comment_%d>" % (no, no),
        }
        if no in IMG:
            entry["img"] = IMG[no]
            entry["icon_frames"] = [
                f"battle/{IMG[no]}/combine_mark.png",
                f"battle/{IMG[no]}/combine_outline.png",
            ]
        buffs.append(entry)
    if unknown:
        print(f"  ! 미등록 스탯 약어: {sorted(unknown)}", file=sys.stderr)
    return {
        "_re_basis": (
            "원작 info_dragon_team_buf(no/name/combine/effect/img). "
            "로직=libgame.so 복원(docs/ref/design/team_buff_analysis.md, TeamBuff.c). "
            "**name·effect 는 유실이 아니라 원작 문자열 테이블에 실재** — "
            "DV2/string/stringsData_KR.xml <Combine1..30> + <Combine_Comment_1..30> 에서 그대로 가져왔다. "
            "img 는 TeamBuff::createIcon 이 쓰는 battle/<res>/combine_mark.png 폴더명(추출 에셋 24종 실재). "
            "⚠️combine(조합 구성)만은 원작 데이터가 아니다 — 서버 유실 + 위키가 그 열을 이미지로만 실어 "
            "추출 불가. 사용자 승인(2026-07-27)으로 버프명·효과·아이콘 res명의 의미에서 **추론해 채웠다** "
            "(HARD RULE 6 예외). 각 행 _combine_basis 에 근거. 원작과 다를 수 있고 조정 대상 "
            "(docs/input/review/team_buff_sheet.md)."
        ),
        "race_dim": "element",
        "_race_dim_note": (
            "ASSUMPTION: 원작 DragonRace id 유실. 후보=element(9속성). "
            "원작 UI 문자열이 이 기능을 '조합(Combine)'으로 부르고 위키는 '속성 조합 버프'라 부른다 → element 가 유력."
        ),
        "effect_mode": "typed",
        "_effect_mode_note": (
            "effect[stat].mode: hp/att/def=pct(배수) · cri/evd/blk/cri_pow/awaken_rate/accuracy=point(퍼센트 포인트) · "
            "pure/depure=flat. 원작 툴팁은 전부 '+N%' 표기라 point/pct 구분은 ASSUMPTION."
        ),
        "_wiki_diff": [
            "10 신의 사자: 원작 'CRT+5% DEF+15%' vs 나무위키 '방어력 15%, 크리티컬 확률 10%' → 원작 채택.",
            "이름 표기 차이(원작 우선): 수퍼노바/물빛 섬광/헬파이어 (위키: 슈퍼노바/물빛섬광/헬 파이어).",
            "25 이클립스 PURE 를 원작은 'PURE+10%'로 %까지 붙여 적었으나 관통은 고정수치라 flat 으로 해석.",
        ],
        "buffs": buffs,
    }


SHEET_HEAD = """# 속성 조합 팀버프 — 사용자 검수 시트

> **진행 상황**: 팀버프 **로직**은 libgame.so 복원 완료(`docs/ref/design/team_buff_analysis.md`).
> **버프명 30종과 효과 수치는 원작 문자열 테이블에서 그대로 복원**했습니다 —
> `DV2/string/stringsData_KR.xml` 의 `<Combine1..30>` / `<Combine_Comment_1..30>`.
> (이전에 "이름·수치도 유실"로 판단했던 것을 정정합니다. 위키가 아니라 원작 값입니다.)
> 아이콘도 찾았습니다: `battle/<res>/combine_mark.png` 24종(25~30은 후기 추가분이라 구판 덤프에 없음).

## ✅ combine(조합 구성)도 채웠습니다 — 단, **이것만은 추론값입니다**
`info_dragon_team_buf.combine` = (종족, 개수) 쌍 목록. 이 열만 서버 갱신분이라 어디에도 없고
위키도 이미지로만 실어서, 사용자 승인(2026-07-27) 하에 **버프명·효과·아이콘 res명의 의미로 추론**해 채웠습니다.

추론 규칙:
1. 9속성 각각에 **단일속성 3마리**(X:3) 조합을 하나씩 배정 — 이름이 그 속성을 직접 가리키는 버프로.
   (코로나=불, 대홍수=물, 가이아=대지, 허리케인=바람, 태초의 빛/어둠/그림자, 신의 사자=신성, 악의 군세=혼돈)
   효과도 이를 뒷받침합니다(단일 대형 스탯 ATK+25 / HP+30 / DEF+25 / BLK+15).
2. 나머지 21종은 이름이 가리키는 2속성(2+1) 또는 3속성(1+1+1) 혼합.
   이름이 조합을 그대로 말해 주는 것부터 고정: 물빛 섬광=물+빛 · 흑풍=어둠+바람 · 빛과 그림자 ·
   용암폭풍=불+대지+바람 · 이클립스(일식)=어둠+빛 · 헬파이어=불+어둠.
3. 30종이 서로 겹치지 않게 배정(겹치면 한 파티에 여러 버프가 동시 발동).

**틀린 조합이 있으면 아래 표에서 고쳐 주세요** — `data/team_buffs.json` 의 `combine` 을 바꾸면 즉시 반영됩니다.
표기법: `fire:3` / `fire:1, aqua:1, wind:1`. 속성키: fire aqua wind earth light dark holy chaos shadow

## 그 외 확인 부탁

1. **race_dim**: `element`(9속성)로 두었습니다. 원작이 속성이 아닌 별도 종족 축이었다면 알려주세요. ⬜
2. **CRT/EVD/BLK 의 "+10%" 해석**: 퍼센트 포인트(크리 10 → 20)로 반영했습니다. 배수(×1.1)가 맞다면 알려주세요. ⬜
3. **PURE**: 원작 표기가 `PURE+10%` 지만 관통은 고정 수치라 flat(+10)으로 해석했습니다. ⬜

## 버프 표 (combine 열만 채우면 됩니다)

| no | 버프명 | combine(추론) | 근거 | 효과(원작 문자열) |
|---|---|---|---|---|
"""

SHEET_TAIL = """
## 반영 방법
- `combine` 열을 채워주시면 `data/team_buffs.json` 의 각 버프 `combine` 에 옮기고,
  헤드리스로 (해당 조합 파티 → 버프 발동 → 스탯 증가) 검증 후 전투에 적용합니다.
- 현재 30종 전부 **발동 가능** 상태입니다(추론 조합 기준). 파티 3마리 속성이 조합을 충족하면 적용됩니다.

관련: `docs/ref/design/team_buff_analysis.md`(로직) · `data/team_buffs.json`(반영 대상) ·
`scripts/systems/team_buff.gd`(로직) · `scripts/tools/build_team_buffs.py`(이 표 생성기) ·
`scripts/tools/test_team_buff.gd`(검증).
"""


def write_sheet(data: dict) -> None:
    rows = "".join(
        "| {no} | {name} | ⬜ | {eff} | {img} |\n".format(
            no=b["no"], name=b["name"], eff=b["effect_text"], img=b.get("img", "—"))
        for b in data["buffs"]
    )
    SHEET.write_text(SHEET_HEAD + rows + SHEET_TAIL, encoding="utf-8")


def main() -> None:
    data = build()
    if "--dry" in sys.argv:
        print(json.dumps(data, ensure_ascii=False, indent=2)[:2000])
        return
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    write_sheet(data)
    withimg = sum(1 for b in data["buffs"] if "img" in b)
    filled = sum(1 for b in data["buffs"] if b["combine"])
    print("[build_team_buffs] wrote %s: %d buffs (%d icon, %d combine filled=inferred)" % (
        OUT.relative_to(REPO), len(data["buffs"]), withimg, filled))


if __name__ == "__main__":
    main()
