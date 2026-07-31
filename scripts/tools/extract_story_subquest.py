"""스토리 서브퀘스트 표 추출 — 원작 `ScenarioSubQuestData` 하드코딩분 → `data/story_subquest.json`.

## 왜 필요한가

스토리(시나리오) **해금·진행 조건**은 서버가 아니라 **클라이언트가 전부 가지고 있었다**.
`ScenarioSubQuestData`(싱글턴, 80메서드)가 회차별로

  · 어느 던전에서 서브퀘스트를 하는지 (`getScenarioSubQuestFiled`)
  · 다음 시나리오까지 탐험 클릭 몇 번인지 (`scenairoClickCountCheck`)
  · 배틀 완료 후 클릭 몇 번인지 (`isBattleCountClick`)
  · 월드맵 이벤트 마크를 어느 필드에 찍는지 (`getEventMarkFieldValue`, .rodata 표)
  · 스토리 이벤트 전투의 몬스터·스탯·배경 (`getEventBattleData`)

을 **switch 문과 .rodata 상수표**로 들고 있다. 원작 로그 문구가 직접 증언한다(libgame.so):
  `"@@@ %s = 서브퀘스트 완료시 다음 시나리오 클릭카운트 …시나리오 Count 추가"`  @ 0x224edba
  `"%s = 배틀 완료시 다음 시나리오 클릭카운트 …Count 추가 isSetting == true"`   @ 0x224f1d4

## 무엇이 여전히 유실인가

- 회차 제목·개방레벨은 **로컬 SQLite** `info_scenario_v2`
  (`select db_no, min_lv, point, title, daynight from info_scenario_v2 where no=%d and sub_no=%d`,
  `ScenarioData::setInfo`)에 있었다 — 서버가 아니다. 다만 그 `.db` 파일이 우리 덤프에 없어
  값은 못 살렸다. `data/story.json` 의 `_unlock` 보간식이 그 자리를 메우고 있다.
- `isSubQuestExtant` / `isBattleScenario` / `isRealBattle` / `isScenarioAftercheck` /
  `isSubQeustBattle` 는 **.bss 의 `std::vector<int>` 전역**(회차 목록)을 훑는다.
  그 정적 초기화자를 특정하지 못해 목록은 미추출이다(아래 `_unresolved` 참조).

## 사용

    python scripts/tools/extract_story_subquest.py            # data/story_subquest.json 생성
    python scripts/tools/extract_story_subquest.py --print    # 표만 출력(파일 안 씀)

디컴프 텍스트가 바뀌어 케이스를 놓치면 **조용히 빠지지 않고 예외로 죽는다**(파서가
함수 안의 `case` 라벨 전부를 소비했는지 검증). 근거가 사라진 걸 모른 채 지나가는 게
제일 위험하기 때문이다.
"""
from __future__ import annotations
import json
import re
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1].parent
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp" / "ScenarioSubQuestData.c"
DECOMP_SM = REPO / "docs" / "ref" / "orig_code" / "decomp" / "ScenarioManager.c"
SO = REPO / "libgame.so"
OUT = REPO / "data" / "story_subquest.json"

# Ghidra 리스팅 주소 − 파일 오프셋. 검증: Ghidra `DAT_0224ed32` 가 가리키는 문자열이
# 파일 0x214ed32 에서 "int cocos2d::ScenarioSubQuestData::getScenarioSubQuestFiled(int, bool)" 로 읽힌다.
GHIDRA_BIAS = 0x100000
# `getEventMarkFieldValue` 의 `*(undefined4 *)(&DAT_0224f6e0 + (sn - 0x4f) * 4)`.
MARK_TABLE_ADDR = 0x0224F6E0
MARK_TABLE_FIRST_SN = 0x4F
MARK_TABLE_N = 0x44  # 원작 경계검사 `if (param_1 - 0x4fU < 0x44)`


# ─────────────────────────────────────────────────────────────── 디컴프 함수 본문 꺼내기
def _funcs(path: Path = None) -> dict[str, str]:
    """`/* ==== <name> @ <addr> (size=N) ==== */` 로 잘라 {name@addr: 본문}.

    ⚠️ `batch_decompile.py` 산출물은 줄바꿈이 `\\r\\r\\n` 이라 파이썬 universal-newline 변환을
    거치면 **모든 코드줄 사이에 공백행**이 생긴다. 그래서 `case A:` / `case B:` 폴스루가
    인접 줄이 아니게 되고, 줄 인덱스로 블록을 자르면 앞쪽 라벨이 통째로 빈 블록이 된다
    (실제로 그렇게 12개 케이스를 놓쳤다). 여기서 공백행을 걷어내 그 함정을 원천 차단한다.
    """
    text = (path or DECOMP).read_text(encoding="utf-8", errors="replace")
    marks = list(re.finditer(r"/\* ==== (\w+) @ ([0-9a-f]+) \(size=(\d+)\) ==== \*/", text))
    out: dict[str, str] = {}
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        body = text[m.end():end]
        out[f"{m.group(1)}@{m.group(2)}"] = "\n".join(
            l for l in body.split("\n") if l.strip() != "")
    return out


def _num(tok: str) -> int:
    return int(tok, 16) if tok.startswith("0x") else int(tok)


def _case_labels(body: str) -> list[int]:
    """본문의 `case X:` 라벨 전부(중복 없이, 등장 순)."""
    seen: list[int] = []
    for m in re.finditer(r"^\s*case (0x[0-9a-f]+|\d+):", body, re.M):
        v = _num(m.group(1))
        if v not in seen:
            seen.append(v)
    return seen


def _blocks(body: str) -> list[tuple[list[int], str]]:
    """연속된 `case` 라벨 묶음 → 그 다음 라벨(또는 끝)까지의 코드."""
    lines = body.split("\n")
    idx = [i for i, l in enumerate(lines) if re.match(r"\s*(case (0x[0-9a-f]+|\d+)|default):", l)]
    out: list[tuple[list[int], str]] = []
    i = 0
    while i < len(idx):
        labels: list[int] = []
        j = i
        while j < len(idx) and idx[j] == idx[i] + (j - i):
            m = re.match(r"\s*case (0x[0-9a-f]+|\d+):", lines[idx[j]])
            if m:
                labels.append(_num(m.group(1)))
            j += 1
        end = idx[j] if j < len(idx) else len(lines)
        out.append((labels, "\n".join(lines[idx[i]:end])))
        i = j
    return out


def _assert_covered(fn: str, body: str, got: dict[int, object]) -> None:
    missing = [c for c in _case_labels(body) if c not in got]
    if missing:
        raise SystemExit(
            f"[{fn}] case 라벨 {[hex(c) for c in missing]} 를 파싱하지 못했다 — "
            "디컴프 텍스트가 바뀌었는지 확인하고 파서를 고칠 것(값을 지어내지 말 것)."
        )


# ─────────────────────────────────────────────── ① 회차 → 서브퀘스트 던전 (+ 밤/변형 조건)
def parse_subquest_field(fns: dict[str, str]) -> dict[str, dict]:
    """`getScenarioSubQuestFiled(sn_s, isNight)` — switch 는 sn(회차) 기준.

    호출부: `WorldMapLayer::setScenarioNotification` (:3164)
      `getScenarioSubQuestFiled(ScenarioManager+0x16c /*sn_s*/, getDBYutakanNight() != 0)`
    원작은 맨 앞에서 `if (param_1 != 2) return 0` → **서브 단계 2에서만** 필드가 있다.
    """
    body = fns["getScenarioSubQuestFiled@01657770"]
    out: dict[int, dict] = {}
    for labels, blk in _blocks(body):
        if not labels:
            continue  # default
        ent: dict | None = None
        # (a) `if (param_1 != 2 || !param_2) return 0;  return N;`  /  두 줄로 갈린 같은 형태
        #     ⚠️ 가드절의 `return 0;` 이 먼저 나오므로 **0 이 아닌 마지막 return** 을 값으로 본다.
        rets = [_num(v) for v in re.findall(r"return (0x[0-9a-f]+|\d+);", blk)]
        nonzero = [v for v in rets if v != 0]
        needs_night = "!param_2" in blk
        # (b) `return (uint)(param_1 == 2 && param_2);`  → 필드 1, 밤 조건
        if re.search(r"return \(uint\)\(param_1 == 2 && param_2\);", blk):
            ent = {"field": 1, "night": True}
        # (c) `return (uint)(param_1 == 2) << 5;`        → 필드 32, 조건 없음
        elif re.search(r"return \(uint\)\(param_1 == 2\) << 5;", blk):
            ent = {"field": 32, "night": False}
        # (d) 카데스/선택맵 분기: `getDBYutakanKades()`/`getDBSelectmap()` == V  +  uVar4 = FIELD
        elif "getDBYutakanKades" in blk or "getDBSelectmap" in blk:
            var = "kades" if "getDBYutakanKades" in blk else "selectmap"
            mv = re.search(r"bVar1 = iVar2 == (\d+);", blk)
            mf = re.search(r"uVar4 = (0x[0-9a-f]+|\d+);", blk)
            if mv and mf:
                ent = {"field": _num(mf.group(1)), "night": False, "requires": {var: int(mv.group(1))}}
            elif mv:  # `return (uint)(iVar2 == 1);` → 필드 1
                ent = {"field": 1, "night": False, "requires": {var: int(mv.group(1))}}
            else:
                mr = re.search(r"return \(uint\)\(iVar2 == (\d+)\);", blk)
                if mr:
                    ent = {"field": 1, "night": False, "requires": {var: int(mr.group(1))}}
        # (e) `bVar1 = param_1 == 2; uVar4 = FIELD;`     → 조건 없음
        elif re.search(r"bVar1 = param_1 == 2;", blk):
            mf = re.search(r"uVar4 = (0x[0-9a-f]+|\d+);", blk)
            if mf:
                ent = {"field": _num(mf.group(1)), "night": False}
        # (a) 처리 — 위 어느 형태도 아니고 순수 `return N`
        elif nonzero:
            ent = {"field": nonzero[-1], "night": needs_night}
        if ent is None:
            continue
        for sn in labels:
            out[sn] = ent
    _assert_covered("getScenarioSubQuestFiled", body, out)
    return {str(k): out[k] for k in sorted(out)}


# ───────────────────────────────────────────────────── ② 회차 → 탐험 클릭 수 / 배틀 후 클릭 수
def _parse_count_switch(fn: str, body: str, initial_var: str) -> dict[str, int]:
    """`uVarN = <초기값>; switch(...) { case: uVarN = V; break; ... }` 형태."""
    mi = re.search(rf"{initial_var} = (0x[0-9a-f]+|\d+);\s*\n\s*switch", body)
    if not mi:
        raise SystemExit(f"[{fn}] 초기값({initial_var})을 못 찾았다 — 파서 수정 필요")
    initial = _num(mi.group(1))
    out: dict[int, int] = {}
    for labels, blk in _blocks(body):
        if not labels:
            continue
        # 라벨 줄(폴스루 포함)을 걷어낸 실제 코드.
        code = [l.strip() for l in blk.split("\n")[len(labels):] if l.strip()]
        m = re.search(rf"{initial_var} = (0x[0-9a-f]+|\d+);", blk)
        if m:
            val = _num(m.group(1))
        elif code and (code[0] == "break;" or code[0].startswith("goto ")):
            val = initial  # 할당 없이 break/goto → switch 앞의 초기값 유지
        else:
            continue
        if val == 0:
            continue
        for sn in labels:
            out[sn] = val
    _assert_covered(fn, body, out)
    return {str(k): out[k] for k in sorted(out)}


def parse_click_counts(fns: dict[str, str]) -> dict[str, int]:
    """`scenairoClickCountCheck()` — 서브퀘스트 완료 후 다음 시나리오까지의 탐험 클릭 수."""
    return _parse_count_switch(
        "scenairoClickCountCheck", fns["scenairoClickCountCheck@01657b34"], "uVar3")


def parse_battle_click_counts(fns: dict[str, str]) -> dict[str, int]:
    """`isBattleCountClick(sn, isSetting)` — 배틀 완료 후 다음 시나리오까지의 클릭 수.

    회차 0x5b 는 `ScenarioManager+0x184 == 1` 이면 20, 아니면 59 (조건부) — 아래 `_conditional`.
    """
    return _parse_count_switch(
        "isBattleCountClick", fns["isBattleCountClick@016586dc"], "uVar2")


# ─────────────────────────────────────────────────────────── ③ 월드맵 이벤트 마크 필드(.rodata)
def parse_mark_fields() -> dict[str, int]:
    data = SO.read_bytes()
    off = MARK_TABLE_ADDR - GHIDRA_BIAS
    # 바이어스 검증 — 같은 함수가 쓰는 로그 문자열이 제자리에 있어야 한다.
    probe = 0x0224ED32 - GHIDRA_BIAS
    if not data[probe:probe + 64].startswith(b"int cocos2d::ScenarioSubQuestData::getScenarioSubQuestFiled"):
        raise SystemExit("GHIDRA_BIAS 검증 실패 — libgame.so 판본이 다르다")
    vals = struct.unpack_from(f"<{MARK_TABLE_N}i", data, off)
    return {str(MARK_TABLE_FIRST_SN + i): v for i, v in enumerate(vals)}


# ────────────────────────────────────────────────────────────── ④ 스토리 이벤트 전투 정의

def parse_adventure_battles() -> dict:
    """`AdventureScene` 의 `switch(battleNo)` → {battleNo: {monster_no, level}}.

    `isEventBattle` 이 아닌 전투번호는 **여기서** 몬스터와 레벨을 얻는다.
    앵커 = `"AdventureEvent" << mScenarioManager()->0x168`(=회차 sn) 직후의 스위치.
    각 case 는 `Monster::create(no)` → `setMonster(this, no, lv, hp, att, def, 0, name, 1)` 로
    합류하고, hp/att/def 는 그 몬스터 DB 값이라 리터럴이 아니다(우리는 monsters/stages 표를 쓴다).

    ⇒ 이걸로 **91화(전투 28)** 편성이 채워진다: #181 관문의 수호자 Lv100.
      26·27·29 는 `isEventBattle` 이라 `getEventBattleData` 쪽이 이긴다.
    """
    src = (DECOMP.parent / "AdventureScene.c").read_text(encoding="utf-8", errors="replace")
    i = src.index('"AdventureEvent",0xe')
    seg = src[i:i + 40000]
    out: dict[str, dict] = {}
    cur: list[int] = []
    for line in seg.splitlines():
        m = re.match(r"\s*case (0x[0-9a-f]+|\d+):", line)
        if m:
            cur.append(_num(m.group(1)))
            continue
        m = re.search(r"setMonster\(this,(0x[0-9a-f]+|\d+),(0x[0-9a-f]+|\d+),", line)
        if m and cur:
            for b in cur:
                out[str(b)] = {"monster_no": _num(m.group(1)), "level": _num(m.group(2))}
            cur = []
    if not out:
        raise SystemExit("[adventure_battle] 스위치를 못 읽었다 — 파서 수정 필요")
    return out


def parse_event_battles(fns: dict[str, str]) -> dict[str, dict]:
    """`getEventBattleData(eventNo)` — 키는 **AdventureScene 이벤트 번호**(회차 아님).

    `isEventBattle` 이 인라인으로 만드는 배열 {0x1a, 0x1b, 0x1d, 100} 이 대상 전부다.
    구조체 int 슬롯의 의미는 소비처가 확정한다:
      `AdventureScene::setMonster(no, lv, hp, att, def, 0, name, true)` — 레이드 경로가
      `RaidNormal::getMonsterNo()` · `Monster::getHp/getAtt/getDef()` 를 그 순서로 넘긴다
      (`AdventureScene.c:15856` 부근). 그래서 [0]=no [1]=lv [2]=hp [3]=att [4]=def [5]=field.
    """
    body = fns["getEventBattleData@01658250"]
    # 원작 제어흐름(축자):
    #   if (in_w1 < 0x1d) { if (in_w1 == 0x1a) {…602…} else { if (in_w1 != 0x1b) return; …24… }
    #                       uVar8=<A>; uVar7=<A>; uVar6=0; }
    #   else { if (in_w1 != 0x1d) { …100/1000: m_stBattle + 런타임 전역… }
    #          …601…; uVar8=<B>; uVar7=<B>; uVar6=1; }
    # ⇒ 0x1a·0x1b 는 **스탯 triple A 를 공유**하고 0x1d 는 B 를 쓴다. 그래서
    #    "몬스터 블록 뒤에 처음 나오는 리터럴 triple" 이 그 블록의 스탯이다.
    triples = [(m.start(), m) for m in re.finditer(
        r"uVar8 = (0x[0-9a-f]+);\s*\n\s*uVar7 = (0x[0-9a-f]+);\s*\n\s*uVar6 = (\d+);", body)]
    if len(triples) != 2:
        raise SystemExit(f"[getEventBattleData] 리터럴 스탯 triple 이 2개가 아니다({len(triples)}) — 파서 수정 필요")

    # 이벤트 번호 배정: `in_w1` 비교값을 등장 순서로 중복 없이 모으면 [0x1a, 0x1b, 0x1d, 100, 1000].
    # 이 중 100·1000 은 **런타임 전역(m_stBattle)** 분기가 쓰므로, 리터럴 블록이 순서대로
    # 나머지 [0x1a, 0x1b, 0x1d] 를 가져간다. (블록 직전 비교를 쓰면 0x1d 블록이 `!= 1000`
    # 안쪽에 있어 1000 으로 잘못 잡힌다 — 실제로 그렇게 틀렸다.)
    seen_cmp: list[int] = []
    for c in re.findall(r"in_w1 [!=]= (0x[0-9a-f]+|\d+)", body):
        v = _num(c)
        if v not in seen_cmp:
            seen_cmp.append(v)
    literal_ids = [v for v in seen_cmp if v not in (100, 1000)]
    blocks = [m for m in re.finditer(r"\*in_x8 = (0x[0-9a-f]+|\d+|m_stBattle);", body)
              if m.group(1) != "m_stBattle"]
    if len(blocks) != len(literal_ids):
        raise SystemExit(
            f"[getEventBattleData] 리터럴 블록 {len(blocks)}개 vs 이벤트 번호 {len(literal_ids)}개 "
            "불일치 — 파서 수정 필요")

    out: dict[str, dict] = {}
    for eid, m in zip(literal_ids, blocks):
        seg = body[m.start():]
        field = _num(re.search(r"in_x8\[5\] = (0x[0-9a-f]+|\d+);", seg).group(1))
        anim = re.search(r'assign\(this,"([^"]+)"', seg)
        evt = re.search(r'\(in_x8 \+ 0xe\),"([^"]+)"', seg)
        tri = next((t for p, t in triples if p > m.start()), None)
        if tri is None:
            raise SystemExit(f"[getEventBattleData] 이벤트 {eid:#x} 의 스탯 triple 을 못 찾았다")
        a, b = _num(tri.group(1)), _num(tri.group(2))
        out[str(eid)] = {
            "monster_no": _num(m.group(1)),
            # 슬롯 의미는 소비처가 확정: setMonster(no, lv, hp, att, def, …).
            "lv": b & 0xFFFFFFFF, "hp": (b >> 32) & 0xFFFFFFFF,
            "att": a & 0xFFFFFFFF, "def": (a >> 32) & 0xFFFFFFFF,
            "field_no": field,
            "monster_anim": anim.group(1) if anim else "",
            "event_key": evt.group(1) if evt else "",
            "bg": "scene/adventure/bg/%d/bg.jpg" % field,
            "bg_item": "scene/adventure/bg/%d/item/bg_item.png" % field,
            # uVar6 — 0x1d(격파 가능 스탯)만 1, 0x1a·0x1b(lv99/9만 벽몬스터)는 0.
            # `isRealBattle()` 과 짝이라고 볼 근거는 있으나 확정 아님. ASSUMPTION.
            "flag6": int(tri.group(3)),
        }
    return out


# ────────────────────────────────────────────────── ⑤ 회차별 특별보상(드래곤) — ScenarioManager
## `ScenarioManager::setSpecialReward` 가 `ScenarioSpecialReward::create(sn, "DRAGON:…")` 를
## **3건** 하드코딩한다. 문자열은 .rodata 가 아니라 **즉치 스토어**(8바이트 정수 + strncpy)로
## 스택 버퍼에 조립되므로, 기록 순서대로 버퍼를 시뮬레이션해 복원한다.
##
## 포맷(소비처 `ScenarioSpecialRewardPopup::setRewardInfo` + 문자열 키로 확정):
##   `DRAGON:<no>:<lv>:<rating>:<gem1>:<gem2>:<gem3>:<c1>:<c2>:<c3>:<skillNo>_<lv>,…`
##   · `<lv>` → `ScenarioRewardTitle2` = "Lv.%1$d %2$s"(레벨 + 드래곤 이름)
##   · `<rating>` → `CCLabelBMFont("font/font_rating.fnt")` + `"%.1f "` (등급 표시)
##   · 젬 3칸 + 색 3개 → `ScenarioRewardGem` = "보유\n젬" 섹션(`newCommon/ncb_s_jewel`)
##   · 스킬 목록 → `ScenarioRewardSkill` = "보유\n스킬" 섹션(`Skill::create` + `setLevel`)
##   · 지급 시점 → `ScenarioRewardNoti1` = "해당 시나리오 클리어시 지급되며, 해당 드래곤은
##     하늘둥지에 맡겨집니다."
SPECIAL_FN = "setSpecialReward@014db39c"


def _sim_buffer(stmts: list[tuple[int, object]], size: int) -> str:
    buf = bytearray(size)
    for off, val in stmts:
        if isinstance(val, str):
            b = val.encode()
        else:
            b = struct.pack("<Q", val)
        buf[off:off + len(b)] = b
    return bytes(buf).split(b"\0")[0].decode("utf-8", errors="replace")


def parse_special_rewards() -> dict[str, dict]:
    body = _funcs(DECOMP_SM)[SPECIAL_FN]
    out: dict[str, dict] = {}
    # `operator_new(SIZE)` 로 블록이 시작하고 `ScenarioSpecialReward::create(SN, …)` 로 닫힌다.
    chunks = re.split(r"(?=operator_new\(0x[0-9a-f]+\);)", body)
    for ch in chunks:
        mcreate = re.search(r"ScenarioSpecialReward::create\((0x[0-9a-f]+|\d+),", ch)
        msize = re.search(r"operator_new\((0x[0-9a-f]+)\);", ch)
        if not (mcreate and msize):
            continue
        size = _num(msize.group(1)) + 8      # 종단 NUL 여유
        # ⚠️ **기록 순서**가 결과를 바꾼다(뒤 기록이 앞을 덮는다) → 문장 단위로 순서대로 훑는다.
        stmts: list[tuple[int, object]] = []
        for raw in ch.split(";"):
            st = " ".join(raw.split())
            m = re.match(r'builtin_strncpy\((.+?),"(.*)",\s*(?:0x[0-9a-f]+|\d+)\)$', st)
            if m:
                arg, text = m.group(1), m.group(2)
                # `(char *)((long)p + 0x26)` = **바이트** 오프셋 / `(char *)(p + 5)` =
                # undefined8 포인터 산술이라 **8배**가 실제 바이트 오프셋이다.
                mo = re.search(r"\+\s*(0x[0-9a-f]+|\d+)", arg)
                if mo is None:
                    off = 0
                elif "(long)" in arg:
                    off = _num(mo.group(1))
                else:
                    off = _num(mo.group(1)) * 8
                stmts.append((off, text))
                continue
            m = re.match(r"(\w+)\[(\d+)\] = (0x[0-9a-f]+)$", st)
            if m:
                stmts.append((int(m.group(2)) * 8, _num(m.group(3))))
                continue
            m = re.match(r"\*(\w+) = (0x[0-9a-f]+)$", st)
            if m:
                stmts.append((0, _num(m.group(2))))
        s = _sim_buffer(stmts, size)
        if not s.startswith("DRAGON:"):
            raise SystemExit(f"[setSpecialReward] 복원 실패: {s!r} — 파서 수정 필요")
        f = s.split(":")
        if len(f) != 11:
            raise SystemExit(f"[setSpecialReward] 필드 수 {len(f)} (11 기대): {s!r}")
        skills = []
        for tok in f[10].split(","):
            if "_" in tok:
                n, lv = tok.split("_", 1)
                skills.append({"no": int(n), "lv": int(lv)})
        out[str(_num(mcreate.group(1)))] = {
            "raw": s,
            "dragon_no": int(f[1]),
            "level": int(f[2]),
            "rating": int(f[3]),
            "gems": [int(f[4]), int(f[5]), int(f[6])],
            "gem_colors": [f[7], f[8], f[9]],
            "skills": skills,
        }
    if not out:
        raise SystemExit("[setSpecialReward] 항목을 하나도 못 읽었다 — 파서 수정 필요")
    return out


def main() -> int:
    fns = _funcs()
    doc = {
        "_source": "원작 libgame.so `ScenarioSubQuestData` — scripts/tools/extract_story_subquest.py 자동생성",
        "_evidence": {
            "class": "docs/ref/orig_code/decomp/ScenarioSubQuestData.c (80메서드, [skip>8000] 0건)",
            "caller_field": "WorldMapLayer::setScenarioNotification :3164 — getScenarioSubQuestFiled(sn_s, isNight)",
            "caller_click": "WorldMapScene :4116 isBattleCountClick(sn, true) / :4133 scenairoClickCountSetting(true)",
            "caller_mark": "WorldMapScene :5858 / :5947 getEventMarkFieldValue(sn, isNight)",
            "struct_names": "AdventureScene::setMonster(no, lv, hp, att, def, 0, name, bool) — 레이드 경로 대조",
            "log_strings": "libgame.so 0x224edba '서브퀘스트 완료시 다음 시나리오 클릭카운트' · 0x224f1d4 '배틀 완료시 …'",
        },
        "_unresolved": {
            "note": "아래 판정은 .bss 의 std::vector<int> 전역(회차 목록)을 훑는다. "
                    "정적 초기화자를 특정하지 못해 목록 미추출 — 우리 구현은 이 표에 "
                    "등장하는 회차를 '서브퀘스트 있음'으로 본다(ASSUMPTION).",
            "vectors": {
                "isScenarioAftercheck/isScenarioEndCheck": "DAT_029f3c50..c58",
                "isSubQeustBattle": "DAT_029f3c68..c70",
                "getEventMarkFieldValue_kades_gate": "DAT_029f3c80..c88",
                "isSubQuestExtant": "DAT_029f3ce0..ce8",
                "isBattleScenario": "DAT_029f3cf8..d00",
                "isRealBattle": "DAT_029f3d40..d48",
            },
        },
        "_lost": {
            "info_scenario_v2": "select db_no, min_lv, point, title, daynight from info_scenario_v2 "
                                "where no=%d and sub_no=%d (ScenarioData::setInfo) — 로컬 SQLite였다. "
                                "서버 소유가 아니지만 .db 파일이 덤프에 없어 값은 유실.",
            "info_quest_v2": "QuestData::setInfo — 퀘스트 정의(type/target/max/보상) 로컬 SQLite. 동일.",
        },
        # 원작 `if (param_1 != 2) return 0` — 서브퀘스트 필드는 서브 단계 2에서만.
        "subquest_substep": 2,
        "subquest_field": parse_subquest_field(fns),
        "click_count": parse_click_counts(fns),
        "battle_click_count": parse_battle_click_counts(fns),
        # 회차 0x5b(91): ScenarioManager+0x184 == 1 → 20, 아니면 59.
        "battle_click_conditional": {"91": {"if_state_1": 20, "else": 59}},
        # `endEventBattle` 재시도 마스크 0xc900200a53 << (sn - 0x67) 로 걸리는 회차.
        "battle_retry_scenarios": [0x67 + b for b in range(64) if 0xC900200A53 >> b & 1],
        "mark_field": parse_mark_fields(),
        # `isEventBattle` 인라인 배열 {0x1a, 0x1b, 0x1d, 100}. 1000 은 100 과 같은 분기.
        "event_battle_ids": [0x1A, 0x1B, 0x1D, 100],
        "event_battle": parse_event_battles(fns),
        "adventure_battle": parse_adventure_battles(),
        # 회차별 특별보상(드래곤) — `ScenarioManager::setSpecialReward` 3건.
        "special_reward": parse_special_rewards(),
    }
    if "--print" in sys.argv:
        print(json.dumps(doc, ensure_ascii=False, indent=1))
        return 0
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"-> {OUT.relative_to(REPO)}")
    print(f"   서브퀘스트 필드 {len(doc['subquest_field'])}회차 · 탐험클릭 {len(doc['click_count'])}회차 "
          f"· 배틀클릭 {len(doc['battle_click_count'])}회차 · 마크필드 {len(doc['mark_field'])}엔트리 "
          f"· 이벤트전투 {len(doc['event_battle'])}종")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
