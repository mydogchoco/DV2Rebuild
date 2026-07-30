"""원작 문자열 테이블에서 **NPC 대사**를 뽑아 `data/npc_talk.json` 으로 만든다.

CLAUDE.md §1-2 대로 대사는 **유실이 아니다** — `DV2/string/stringsData_KR.xml` 에 전부 남아 있다.
그런데 상점/연구소/점술집/육성 화면이 대사를 한 줄씩만 하드코딩하고 있어서(2026-07-28 검수 지적)
원작처럼 여러 대사 + 표정이 돌지 않았다. 그 근거 데이터를 여기서 만든다.

담는 것

  idle    NPC별 평상시 대사 8종 — `<PinoTalk1~8>` `<AnnieTalk1~8>` `<UriaTalk1~8>` …
          원작은 화면에 들어오거나 대사창을 다시 채울 때 이 중 하나를 무작위로 고른다.
  screen  화면·메뉴별 대사 묶음 — `<LabWelcomeMsg1~8>` `<LabEggEnforceMsg1~2>` `<MagicWelcomeGem>` …
          원작 `LaboratoryScene::setTextStart/setTextAgain`, `MagicShopScene::setText*` 가 쓴다.

이모티콘(말풍선) 번호는 코드에 하드코딩돼 있어 문자열에서 못 뽑는다 →
`EMOTICON` 표에 디컴프에서 읽은 값을 적어 두고 그대로 내보낸다.
근거: docs/ref/orig_code/decomp/LaboratoryScene.c :: setTextStart / setTextAgain 의
`NpcManager::setEmoticon(mgr, <N>, true)` 호출.

    python scripts/tools/build_npc_talk.py
"""
from __future__ import annotations

import html
import json
import re
from collections import OrderedDict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "DV2" / "string" / "stringsData_KR.xml"
OUT = REPO / "data" / "npc_talk.json"

# 원작 문자열 키 접두사 → 우리 NPC 폴더명(npc/<name>/).
# 폴더명 확인: ls DV2/480/npc/ · assets/converted/npc_*
IDLE = OrderedDict([
    ("PinoTalk", "pino"),
    ("PopoTalk", "popo"),
    ("RandolfTalk", "randolph"),
    ("RaonTalk", "raon"),
    ("RuminiTalk", "romini"),
    ("BarosTalk", "baruseu"),
    ("AnnieTalk", "annie"),
    ("UriaTalk", "yulia"),
    ("DelisTalk", "dilis"),
    ("NooriTalk", "nuri"),
    ("KangaloTalk", "kanggalo"),
    ("ZumunTalk", "jimon"),
])

# 화면별 대사 묶음. (그룹키, 문자열 접두사, 개수) — 개수는 아래에서 실측으로 잘라낸다.
SCREEN_FAMILIES = [
    # 연구소 — LaboratoryScene::setTextStart / setTextAgain
    ("lab.welcome", "LabWelcomeMsg"),
    ("lab.egg_up", "LabEggEnforceMsg"),
    ("lab.egg_mix", "LabEggCombineMsg"),
    ("lab.crystal_make", "LabGenerateMsg"),
    ("lab.crystal_extract", "LabExtractMsg"),
    ("lab.floor_up", "LabFloorUpMsg"),
    ("lab.floor_down", "LabFloorDownMsg"),
    ("lab.success", "LabSuccessMsg"),
    ("lab.skill", "LabSkillMsg"),
    ("lab.smelt", "LabSmeltMsg"),
    ("lab.normal", "LabNormalMsg"),
    ("lab.upgrade_talk", "LabUpgradeTalk"),
    # ⚠️ `LabUpgradeMsg*` · `LaboratoryEggPieceMsg*` 는 **대사가 아니라 UI 문자열**이라 뺐다
    #    (2026-07-28). 원문 확인:
    #      LabUpgradeMsg1~4 = "%1$d개" "%1$d원" "%1$d다이아 감소" "(1, 4, 7, 10 단계에서 수치 증가)"
    #      LaboratoryEggPieceMsg1~3 = "%1$s의 알조각" "조합하기" "알 조각이 부족합니다."
    #    이걸 대사 묶음으로 들고 있어서 연구소 화면 대사창에 `%1$d개` 가 그대로 찍혔다.
    #    연구소 강화의 **진짜 대사**는 `LabUpgradeTalk*` 다.
    # 점술집 — MagicShopScene
    ("magic.welcome", "MagicWelcomeMsg"),
    # 연금술사(점술집 지하) — `AlchemyTalk1~8` 은 **기능별 2줄씩 4묶음**이다.
    # 근거: 원문이 기능을 직접 말한다(1·2 혼성젬 제작 / 3·4 젬 분해 / 5·6 용액 제작 /
    #   7·8 용액 상점). 원작 `onClickAlchemyItem` 도 `rand()%2` 로 **2줄 중 하나**를 고른다.
    #   `MagicAlchemy_menu1~6`(혼성젬 강화·제작·젬 분해·용액 제작·용액 상점·소울젬)와 대조하면
    #   혼성젬 **강화**와 소울젬에는 전용 대사가 없다 → 그 둘은 `magic.gem` 안내문을 쓴다.
    ("magic.alchemy_talk", "AlchemyTalk"),
    # 육성 — PromoteScene
    ("promote.talk", "NurtureTalk"),
    ("promote.breed_talk", "NurtureBreedTalk"),
    # 마모루딕 연구소(우노) — DragonAwaken::drawNpcTalk
    #   `drawNpcTalk(kind)`: kind==1 이면 `MamorudicLabTalkAwake_%d`, 그 외에는
    #   **탭과 무관하게** 언제나 `MamorudicLabTalk_1_%d` 를 rand 로 고른다
    #   (DragonAwaken.c:1273-1422). `MamorudicLabTalk_0_*` 는 후기판 `MamorudicLab`
    #   (5카드 메뉴, 디컴프에 없음) 것이라 여기서는 안 쓴다.
    ("mamorudic.idle", "MamorudicLabTalk_1_"),
    ("mamorudic.awake", "MamorudicLabTalkAwake_"),
    ("mamorudic.success", "MamorudicLabTalkSuc_"),
    ("mamorudic.bye", "MamorudicLabTalkBye_"),
    ("mamorudic.err_material", "MamorudicLabTalkErro_0_"),
    ("mamorudic.err_target", "MamorudicLabTalkErro_2_"),
]

# 접두사가 아니라 **키 하나**로 끝나는 안내문(메뉴 진입 시 1회).
SINGLE = OrderedDict([
    ("magic.egg", "MagicWelcomeEgg"),
    ("magic.drink", "MagicWelcomeDrink"),
    ("magic.gem", "MagicWelcomeGem"),
    ("magic.slot", "MagicWelcomeSlot"),
    ("magic.code", "MagicWelcomeCode"),
    ("magic.premium_code", "MagicWelcomePrimiumCode"),
])

# 원작 문자열을 **오프라인 재구현 사정에 맞게 갈아 끼우는** 자리. 원문을 지우지 않고 여기 남겨
# 무엇을 왜 바꿨는지 보이게 한다. (원본 XML 은 읽기 전용 — HARD RULE §4)
#
# `magic.code` — 원작은 "드래곤빌리지 오피셜 카드 코드를 입력하는 곳입니다.\n카드 코드 16자리를…"
#   이었다. 우리 카드 코드는 서버 인증이 유실돼(§2-1) **사용자가 채우는 이스터에그 표**로
#   바뀌었고(`docs/input/sheets/card_codes.csv`) 자릿수 고정도 없앴다 ⇒ 원문의 "오피셜"·
#   "16자리"가 둘 다 사실이 아니다. 문구는 사용자 확정(2026-07-30).
OVERRIDE = {
    "magic.code": ["세계의 비밀에 대해 얼마나 알고 계신가요?"],
}

# 원작 setEmoticon 번호. `null` = 그 분기에서 이모티콘을 안 띄운다.
# 근거: docs/ref/orig_code/decomp/LaboratoryScene.c setTextStart(=8) / setTextAgain(switch 0~9).
#   여러 개면 그 묶음의 index 순서와 짝이다(1번 대사 → 첫 번호).
EMOTICON = {
    "lab.welcome": [8],
    "lab.egg_up": [3, 5],
    "lab.egg_mix": [4, 8],
    "lab.crystal_make": [5, 3],
    "lab.crystal_extract": [8, 6],
    "lab.floor_up": [4, 5, 3],
    "lab.floor_down": [1, 4, 5],
    "lab.success": [4, 8],
    "lab.skill": [5, 7, 4],
    "lab.smelt": [5, 7, 4],
    "lab.normal": [1],
}

# 원작 **표정(NpcManager 의 emotion)** ↔ 대사 짝.
# 근거: LaboratoryScene.c `setTextAgain` 은 표정을 바꾸는 게 아니라 **현재 표정으로 대사를 고른다** —
#   case 5/7  `getEmotion()==1 → Msg1 · ==2 → Msg2 · else → Msg3`
#   case 8/9/10 `==1 → Msg1 · ==3 → Msg2 · else → Msg3`
#   case 1     `==1 → Msg2 · else → Msg1`      case 4/6 `==1 → Msg1 · else → Msg2`
# 우리는 대사를 먼저 고르므로 이 대응을 **뒤집어**(대사 index → 표정) 쓴다. 결과는 같은 짝이다.
# 분기하지 않는 묶음(egg_up·crystal_make·welcome·normal)은 여기 없고 `entry_face` 를 쓴다.
FACE = {
    "lab.egg_mix": [2, 1],
    "lab.crystal_extract": [1, 2],
    "lab.floor_up": [1, 2, 3],
    "lab.floor_down": [1, 2, 3],
    "lab.success": [1, 2],
    "lab.skill": [1, 3, 2],
    "lab.smelt": [1, 3, 2],
    "lab.upgrade_talk": [1, 3, 2],
}

# 그 화면에 **들어갈 때** 원작이 setTalker 로 지정하는 표정(여럿이면 그중 무작위).
# 근거: LaboratoryScene.c `initWidget`(=welcome, iVar20 ∈ {1,3}) · `onClickSkillInfo`(rand%3+1) ·
#   `selectTab` case 0(알강화)=1 / case 0 지하(결정생산)=1 / case 1 지하(결정추출) ∈ {1,3} /
#   case 1(알조합) ∈ {1,2} / case 2(방생)=1.
ENTRY_FACE = {
    "lab.welcome": [1, 3],
    "lab.egg_up": [1],
    "lab.crystal_make": [1],
    "lab.normal": [1],
}


def load_strings() -> dict[str, str]:
    raw = SRC.read_text(encoding="utf-8", errors="replace")
    out: dict[str, str] = {}
    for key, val in re.findall(r"<([A-Za-z0-9_]+)>([^<]*)</\1>", raw):
        out[key] = html.unescape(val).replace("&#10;", "\n")
    return out


def family(strings: dict[str, str], prefix: str) -> list[str]:
    """`<Prefix1>`, `<Prefix2>` … 를 번호 순으로 모은다. 없으면 빈 리스트."""
    got: list[tuple[int, str]] = []
    for k, v in strings.items():
        m = re.fullmatch(re.escape(prefix) + r"(\d+)", k)
        if m:
            got.append((int(m.group(1)), v))
    return [v for _, v in sorted(got)]


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"원본 문자열 테이블 없음: {SRC}")
    s = load_strings()

    idle: dict[str, list[str]] = {}
    for prefix, npc in IDLE.items():
        lines = family(s, prefix)
        if lines:
            idle[npc] = lines

    # `AlchemyTalk1~8` → 기능별 2줄 묶음(위 SCREEN_FAMILIES 주석의 근거).
    ALCHEMY_SPLIT = [
        ("magic.alchemy_make", (1, 2)),    # 혼성젬 제작
        ("magic.disassemble", (3, 4)),     # 젬 분해
        ("magic.potion_make", (5, 6)),     # 용액 제작
        ("magic.potion_shop", (7, 8)),     # 용액 상점
    ]
    screen: dict[str, dict] = {}
    for gkey, (a, b) in ALCHEMY_SPLIT:
        lines = [s[f"AlchemyTalk{n}"] for n in (a, b) if f"AlchemyTalk{n}" in s]
        if lines:
            screen[gkey] = {"lines": lines}
    for key, prefix in SCREEN_FAMILIES:
        lines = family(s, prefix)
        if not lines:
            continue
        entry: dict = {"lines": lines}
        if key in EMOTICON:
            entry["emoticon"] = EMOTICON[key]
        if key in FACE:
            entry["face"] = FACE[key]
        if key in ENTRY_FACE:
            entry["entry_face"] = ENTRY_FACE[key]
        screen[key] = entry
    for key, single_key in SINGLE.items():
        if single_key in s:
            screen[key] = {"lines": [s[single_key]]}
    for key, lines in OVERRIDE.items():
        screen.setdefault(key, {})["lines"] = list(lines)

    doc = OrderedDict([
        ("_source", "DV2/string/stringsData_KR.xml (원작 문자열 테이블 — 대사는 유실이 아니다)."
                    " 생성기: scripts/tools/build_npc_talk.py"),
        ("_emoticon_source", "이모티콘 번호는 문자열이 아니라 코드에 있다 —"
                             " docs/ref/orig_code/decomp/LaboratoryScene.c setTextStart/setTextAgain 의"
                             " NpcManager::setEmoticon(mgr, N, true). 프레임 = npc/emoticon/<N>.png"),
        ("_face_source", "face = 대사 index → NPC **표정**(emoticon 과 다른 것: 얼굴 프레임)."
                         " 원작 setTextAgain 은 `getEmotion()` 으로 대사를 고르므로 그 분기를 뒤집어 얻었다."
                         " entry_face = 그 화면에 들어갈 때 setTalker 가 주는 표정(여럿이면 무작위)."
                         " 생성기 주석에 case 별 근거가 있다."),
        ("idle", idle),
        ("screen", screen),
    ])
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[npc_talk] idle {len(idle)}종 / screen {len(screen)}묶음 → {OUT.relative_to(REPO)}")
    for k, v in idle.items():
        print(f"   idle {k}: {len(v)}줄")
    for k, v in screen.items():
        print(f"   screen {k}: {len(v['lines'])}줄"
              + (f" emo={v['emoticon']}" if "emoticon" in v else ""))


if __name__ == "__main__":
    main()
