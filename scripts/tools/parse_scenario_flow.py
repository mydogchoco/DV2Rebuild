"""시나리오 연출 스텝 덤프 → `data/scenario_flow.json`.

`extract_scenario_flow.py` 가 뜬 람다 덤프(`docs/ref/orig_code/decomp/lambda/<Class>.c`)를
읽어 **회차별 연출 스텝 목록**으로 굽는다. 원작 구조 그대로다:

    회차(sn) → [ {op, args}, … ]      # op = setNpcTalk / changeBackGround / drawIllust …

## 어떻게 회차에 붙이나

`<Class>::initScenarioData` 는 `switch(sn)` 안에서 회차별로 `std::function` 을 순서대로
push 한다(디컴프에 `&PTR_FUN_xxxx` 나열로 보인다). 람다는 소스 순서대로 `$_0`, `$_1` … 로
이름이 붙으므로(itanium ABI), **case 별 개수로 인덱스를 잘라** 회차에 배분한다:

    case 82 → $_0..$_39 · case 83 → $_40..$_54 · …

각 `$_N` 태그는 libc++ `__func::target()` 안의 타입명 문자열
(`ZN7cocos2d14Scenario_zimon16initScenarioDataEvE3$_4`)로 식별하고, **그 바로 앞의
호출 본문 함수**가 그 스텝의 실체다(같은 `__func` 특수화가 인접 배치된다).

## 인자 복원

원작은 열거형을 **포인터로** 넘긴다 —
`setNpcTalk(this, (NPC_NAME*)&local_44, (Character_State*)&local_48, …)`.
그래서 호출 직전까지의 `local_XX = <상수>;` 대입을 추적해 값을 되살린다.
문자열(BGM 경로)은 바이트 단위 대입(`local_40[3] = 0x73;`)으로 조립되므로 그대로 재조립한다.

사용:
    python scripts/tools/parse_scenario_flow.py                 # lambda/ 에 있는 것 전부
    python scripts/tools/parse_scenario_flow.py --classes Scenario_zimon --report
"""
from __future__ import annotations
import json, re, struct, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"
LAMBDA = DECOMP / "lambda"
OUT = REPO / "data" / "scenario_flow.json"

## 원작 `ScenarioSupport::getNPCname` 의 NPC_NAME 열거형(회차 클래스가 넘기는 값) →
## `DV2/480/npc/<이름>` 아틀라스 폴더명 = 문자열 키 `<NPC_이름>` 의 접미사.
NPC_SRC = DECOMP / "ScenarioSupport.c"

## 스텝으로 인정할 호출. 값은 인자 이름표(this 제외, 원작 시그니처 순서).
##   근거 = 각 클래스 디컴프의 `/* cocos2d::…::fn(…) */` 원형 주석.
OPS: dict[str, list[str]] = {
    # ScenarioSupport
    "setTalk": ["b1"],
    "setNpcTalk": ["npc", "state", "pos", "emoticon",
                   "b1", "b2", "b3", "b4", "b5", "b6", "b7"],
    "setUserTalk": ["b1"],
    "changeBackGround": ["bg", "pass_"],
    "changeBackGroundPass": ["bg"],
    "drawIllust": ["illust", "kind", "b1"],
    # 컷 시퀀스. 원작 렌더러는 `Cutin::show` 가 아니라 회차 클래스의 `drawillust_N`
    # 메서드다(`Scenario_Kadeath::drawillust_3` @01665ec0 이 sn_94/back.jpg + s1~s3 를 깐다).
    # 이미지 목록은 **경로에 회차 번호가 들어 있어**(`sn_<N>/`) 데이터에서 회차로 바로
    # 찾는다(scenario.json `cuts`) ⇒ op 은 **위치만** 표시한다.
    "drawillust_3": [], "drawillust_8": [], "drawillust_9": [],
    "removeIllust": [],
    "showMonster": ["monsters", "delay", "b1"],
    "deleteMonster": [],
    "walkAction": ["field"],
    # 원형 주석 축자: `delayWalkAction(float, int)` — **필드가 아니라** (지연, 반복수)다.
    # 종전 이름표 ["field","delay"] 는 순서까지 뒤바뀐 오해였다.
    "delayWalkAction": ["delay", "n"],
    "scenarioBlackLayer": [],
    "deleteColorLayer": [],
    "showColorLayer": [],
    "playBackGroundFieldMusic": ["field"],
    "initScenarioTalk": [],
    "setSubQuest": [],
    "miniGameText": ["b1", "n"],
    # 미니게임 레이어를 띄우는 스텝 — 원작 `minigameSpeedTarget()` @0165bc7c 이
    # `ScenarioMiniGameLayer::create(1.8, 150.0)` 를 만든다(속도·판정폭 상수 확정).
    "minigameSpeedTarget": [],
    "passMiniGame": [],
    "miniGameSucEndAct": [],
    # 원형 `scenarioBattle(int fieldNo, int battleNo)` → `AdventureScene::scene(f, b)` 푸시.
    "scenarioBattle": ["field", "battle"],
    # 1~78화는 AdventureScene::scene(field, battleNo) 를 직접 부른다(scenarioBattle 경유 아님).
    "adventureBattle": ["battle"],
    "setChaosFearStart": [],
    "actionSmoke": [],
    "shakeAction": [],
    "shineAction": [],
    "removeNPCAction": [],
    "setNPCAction": [],
    # 원작 `showScenarioItem(ScenarioItem*, float x, float y, float, bool, bool)`.
    # 첫 인자는 열거형 **포인터**라 changeBackGround 와 같은 슬롯 추적으로 푼다.
    "showScenarioItem": ["item", "x", "y", "scale", "b1", "b2"],
    "removeScenarioItem": [],
    "goOutWorldMap": [],
    "setPassEndingPopup": [],
    "sound_CryMonster": [],
    # ScenarioLayer
    "setOutTalker": ["talker", "n", "b1"],
    "setTitleScenario": ["title", "b1"],
    "setHidePassButton": [],
    "close": [],
}
LAYER_OPS = {"setOutTalker", "setTitleScenario", "setHidePassButton", "close"}

## ⚠️ 회차로 등록하지 않는 클래스.
## `Scenario_raon` 의 `initScenarioData` 는 case 62~66 을 갖지만, **디스패처
## `makeScenarioLayer` 는 59~78 을 `Scenario7` 로 보낸다.** 게다가 뽑힌 대사 스텝 수가
## 원작 대사 줄 수와 크게 어긋난다(62화 50 vs 28 · 66화 8 vs 48) ⇒ 그 회차의 본편이 아니라
## **라온 전용 분기/서브 시퀀스**로 보인다. 근거가 설 때까지 `variants` 에만 보관하고
## 재생에는 쓰지 않는다(잘못 붙이면 대사가 빈 채로 넘어간다).
VARIANT_CLASSES = {"Scenario_raon"}


def npc_table() -> dict[int, str]:
    """`getNPCname` 의 case → 폴더명."""
    src = NPC_SRC.read_text(encoding="utf-8", errors="replace")
    ms = list(re.finditer(r"/\* ==== getNPCname @ [0-9a-f]+ \(size=(\d+)\)", src))
    if not ms:
        return {}
    m = max(ms, key=lambda x: int(x.group(1)))
    seg = src[m.start(): src.find("/* ==== ", m.start() + 10)]
    out = {}
    for k, v in re.findall(r'case (0x[0-9a-f]+|\d+):.*?append\s*\(\s*in_x8,"([a-z_0-9]+)"', seg, re.S):
        out[int(k, 0)] = v
    return out


def bg_table() -> dict[int, list[str]]:
    """`changeBackGround` 의 BackGruundName → 경로들(배경 + 전경 아이템)."""
    src = NPC_SRC.read_text(encoding="utf-8", errors="replace")
    ms = list(re.finditer(r"/\* ==== changeBackGround @ [0-9a-f]+ \(size=(\d+)\)", src))
    if not ms:
        return {}
    m = max(ms, key=lambda x: int(x.group(1)))
    seg = src[m.start(): src.find("/* ==== ", m.start() + 10)]
    out: dict[int, list[str]] = {}
    cur: list[int] = []
    for line in seg.splitlines():
        cm = re.search(r"^\s*case (0x[0-9a-f]+|\d+):", line)
        if cm:
            cur.append(int(cm.group(1), 0))
            continue
        for p in re.findall(r'"((?:scenario|scene|addimg)/[^"]+\.(?:jpg|png))"', line):
            for c in cur:
                out.setdefault(c, [])
                if p not in out[c]:
                    out[c].append(p)
            cur = cur[-1:] if cur else []
    return out


def bgm_table() -> dict[int, str]:
    """`playBackGroundFieldMusic(int)` 의 필드 번호 → 트랙 이름(확장자 없이).

    원작 @0165d74c 은 두 갈래다(디스어셈블 확인 2026-07-31):

        cmp w1,#0x10 ; b.gt <이름표>          ← 16 이하
          uVar1 = (param_1 == 0x10) ? 0x18 : param_1
          CCString::createWithFormat("music/bg_%d.mp3", uVar1)
        <이름표>: sub w8,w1,#0x12 ; cmp w8,#0x13 ; b.hi <무시> ; br  ← 18~37, 20엔트리
          switch → "bg_colosseum" … "bg_world_wood"
          CCString::createWithFormat("music/%s.mp3", 이름)

    ⇒ 17(0x11)은 어느 갈래에도 없다(원작도 무음). 여기서 지어내지 않는다.
    """
    src = NPC_SRC.read_text(encoding="utf-8", errors="replace")
    ms = list(re.finditer(
        r"/\* ==== playBackGroundFieldMusic @ [0-9a-f]+ \(size=(\d+)\)", src))
    if not ms:
        return {}
    m = max(ms, key=lambda x: int(x.group(1)))
    seg = src[m.start(): src.find("/* ==== ", m.start() + 10)]
    out: dict[int, str] = {}
    # 숫자 갈래 — 1~16. 16 만 bg_24 로 바뀐다(`uVar1 = 0x18; csel ... eq`).
    if 'createWithFormat("music/bg_%d.mp3"' in seg:
        for n in range(1, 17):
            out[n] = "bg_%d" % (24 if n == 16 else n)
    # 이름 갈래 — case 값이 곧 필드 번호다(`sub #0x12` 는 표 인덱스용이라 case 라벨은 원값).
    cur: list[int] = []
    for line in seg.splitlines():
        cm = re.search(r"^\s*case (0x[0-9a-f]+|\d+):", line)
        if cm:
            cur.append(int(cm.group(1), 0))
            continue
        nm = re.search(r'&local_\w+,"([a-z_0-9]+)",(?:0x[0-9a-f]+|\d+)\)', line)
        if nm and cur:
            for c in cur:
                out[c] = nm.group(1)
            cur = []
    return out


def item_table() -> dict[int, str]:
    """`showScenarioItem(ScenarioItem*, …)` 의 아이템 번호 → 프레임 경로 (원작 @0165cb68).

    0~11 의 12종. 5·6 은 같은 `item/item_small/stone2.png` 를 쓰고 6 만 플래그가 다르다
    (원작이 `param_6 = true` 로 덮어쓴다) — 그대로 둔다.
    """
    src = NPC_SRC.read_text(encoding="utf-8", errors="replace")
    ms = list(re.finditer(r"/\* ==== showScenarioItem @ [0-9a-f]+ \(size=(\d+)\)", src))
    if not ms:
        return {}
    m = max(ms, key=lambda x: int(x.group(1)))
    seg = src[m.start(): src.find("/* ==== ", m.start() + 10)]
    out: dict[int, str] = {}
    cur: list[int] = []
    for line in seg.splitlines():
        cm = re.search(r"^\s*case (0x[0-9a-f]+|\d+):", line)
        if cm:
            cur.append(int(cm.group(1), 0))
            continue
        pm = re.search(r'"((?:scenario|item)/[^"]+\.png)"', line)
        if pm and cur:
            for c in cur:
                out[c] = pm.group(1)
            cur = []
    return out


def monster_npc_table() -> dict[int, str]:
    """`showMonster(vector<int>, float, bool)` 의 몬스터 번호 → 프레임 경로 (원작 @0165dba4).

    0~7 의 8종. 컷신용 **정지 스프라이트**(`scenario/monster_npc/*.png`)지 전투 몬스터가 아니다.
    """
    src = NPC_SRC.read_text(encoding="utf-8", errors="replace")
    ms = list(re.finditer(r"/\* ==== showMonster @ [0-9a-f]+ \(size=(\d+)\)", src))
    if not ms:
        return {}
    m = max(ms, key=lambda x: int(x.group(1)))
    seg = src[m.start(): src.find("/* ==== ", m.start() + 10)]
    out: dict[int, str] = {}
    cur: list[int] = []
    for line in seg.splitlines():
        cm = re.search(r"^\s*case (0x[0-9a-f]+|\d+):", line)
        if cm:
            cur.append(int(cm.group(1), 0))
            continue
        pm = re.search(r'"(scenario/monster_npc/[^"]+\.png)"', line)
        if pm and cur:
            for c in cur:
                out.setdefault(c, pm.group(1))
            cur = []
    return out


def split_blocks(text: str):
    """람다 덤프를 (주소, 본문) 목록으로."""
    out = []
    for b in re.split(r"/\* ==== step ", text)[1:]:
        m = re.match(r"(\S+) @ ([0-9a-f]+) \(size=(\d+)\)", b.split(" ==== ")[0])
        if m:
            out.append((int(m.group(2), 16), b))
    out.sort()
    return out


NUM = r"(0x[0-9a-fA-F]+|-?\d+)"


def parse_body(body: str) -> list[dict]:
    """한 스텝 본문 → 호출 목록(리터럴 인자 복원)."""
    vals: dict[str, int] = {}
    bytes_: dict[str, dict[int, int]] = {}
    ## 구조체 인자(`setNpcTalk(this, NpcData*)` 오버로드)의 필드 — 오프셋→값.
    sfields: dict[str, dict[int, int]] = {}
    ops: list[dict] = []
    # 줄 단위로 훑되, 호출은 여러 줄에 걸치므로 먼저 개행을 정리한다
    flat = re.sub(r"\s*\n\s*", " ", body)
    # 대입/호출을 등장 순서대로
    token = re.compile(
        # `*(undefined8 *)(pNVar1 + 8) = 0x300000001;` — 구조체 필드 묶음 저장
        r"\*\(undefined(?P<fw>8|4|2) \*\)\((?P<fvar>\w+) \+ (?P<foff>0x[0-9a-f]+|\d+)\)\s*=\s*(?P<fval>" + NUM + r");"
        r"|\*\(undefined(?P<gw>8|4|2) \*\)(?P<gvar>\w+)\s*=\s*(?P<gval>" + NUM + r");"
        r"|\b(?P<bvar>\w+)\[(?P<bidx>0x[0-9a-f]+|\d+)\]\s*=\s*(?P<bval>" + NUM + r");"
        r"|\b(?P<cvar>\w+)\s*=\s*CONCAT44\(\s*(?P<chi>" + NUM + r")\s*,\s*(?P<clo>" + NUM + r")\s*\);"
        r"|\b(?P<avar>\w+)\s*=\s*(?P<aval>" + NUM + r");"
        # ⚠️ 회차 클래스(`Scenario_Kadeath` 등) 메서드도 스텝이 될 수 있다 —
        #    컷 시퀀스 렌더러 `drawillust_N` 이 그렇다(원작은 여기서 sn_<회차>/ 컷을 깐다).
        #    종전 패턴은 ScenarioSupport/ScenarioLayer 만 봐서 통째로 놓쳤다.
        r"|cocos2d::(?:ScenarioSupport|ScenarioLayer|Scenario_\w+)::(?P<cname>\w+)"
        r"\s*\((?P<cargs>[^;]*?)\);"
        r"|SoundManager::playBackground\s*\((?P<sargs>[^;]*?)\);"
    )
    for m in token.finditer(flat):
        if m.group("fvar") or m.group("gvar"):
            var = m.group("fvar") or m.group("gvar")
            off = int(m.group("foff"), 0) if m.group("fvar") else 0
            width = int(m.group("fw") or m.group("gw"))
            val = int(m.group("fval") if m.group("fvar") else m.group("gval"), 0)
            f = sfields.setdefault(var, {})
            if width == 8:      # 8바이트 저장 = 4바이트 필드 두 개
                f[off] = val & 0xFFFFFFFF
                f[off + 4] = (val >> 32) & 0xFFFFFFFF
            else:
                f[off] = val
        elif m.group("bvar"):
            bytes_.setdefault(m.group("bvar"), {})[int(m.group("bidx"), 0)] = int(m.group("bval"), 0)
        elif m.group("avar"):
            store(vals, m.group("avar"), int(m.group("aval"), 0))
        elif m.group("cvar"):
            # `local_48 = CONCAT44(hi, lo);` — 인접한 두 4바이트 지역변수를 한 번에 쓴 것
            store(vals, m.group("cvar"),
                  (int(m.group("chi"), 0) << 32) | (int(m.group("clo"), 0) & 0xFFFFFFFF))
        elif m.group("cname"):
            name, argstr = m.group("cname"), m.group("cargs")
            if name not in OPS:
                continue
            args = [a.strip() for a in argstr.split(",")]
            if args and ("this" in args[0] or "param_1" in args[0]):
                args = args[1:]
            rec: dict = {"op": name}
            # 구조체 한 개로 넘기는 오버로드 — 필드 오프셋이 곧 인자 순서(4바이트씩)
            solo = args[0].strip().lstrip("&") if args else ""
            if len(args) == 1 and solo in sfields:
                # ⚠️ 앞쪽 4바이트 필드(npc/state/pos/emoticon)만 읽는다. 뒤의 bool 들은
                #    1바이트씩 packed 인데다 구조체가 레이어에 **상주**(this+0x398)해서
                #    안 쓴 필드는 이전 스텝 값이 남는다 — 복원 근거가 없다.
                for i, label in enumerate(OPS[name]):
                    if label.startswith("b"):
                        break
                    v = sfields[solo].get(i * 4)
                    if v is None:
                        break
                    rec[label] = v
            else:
                for label, raw in zip(OPS[name], args):
                    rec[label] = resolve(raw, vals)
            # float 인자는 비트패턴 정수로 잡힌다(`0x3f800000` = 1.0) — 되돌린다.
            for label in ("x", "y", "scale"):
                v = rec.get(label)
                if isinstance(v, int) and v > 0:
                    rec[label] = round(struct.unpack("<f", struct.pack("<I", v & 0xFFFFFFFF))[0], 3)
            ops.append(rec)
        elif m.group("sargs"):
            args = m.group("sargs").split(",")
            path = None
            for a in args:
                v = a.strip()
                if v in bytes_:
                    path = rebuild(bytes_[v])
            if path:
                ops.append({"op": "playBackground", "path": path})
    return ops


def store(vals: dict[str, int], var: str, val: int) -> None:
    """지역변수 대입. 8바이트 저장은 **인접한 두 4바이트 변수**를 한꺼번에 쓴 것이다.

    Ghidra 는 `local_48`/`uStack_44` 처럼 **프레임 오프셋**으로 이름을 짓는다(주소가 커질수록
    숫자가 작아진다). 그래서 `local_48 = 0x100000009` 는 실제로
    `local_48 = 9` + `local_44 = 1` 이다 — 이걸 안 갈라서 화자 번호가 42억으로 나왔었다.
    """
    if 0 <= val <= 0xFFFFFFFF or not re.search(r"_([0-9a-f]+)$", var):
        vals[var] = val
        return
    lo, hi = val & 0xFFFFFFFF, (val >> 32) & 0xFFFFFFFF
    vals[var] = lo
    m = re.match(r"(.*_)([0-9a-f]+)$", var)
    off = int(m.group(2), 16)
    if off >= 4:
        # 같은 프레임의 +4 위치. 이름 접두사(local_/uStack_)가 다를 수 있어 둘 다 심어 둔다.
        for pre in {m.group(1), "local_", "uStack_"}:
            vals[f"{pre}{off - 4:x}"] = hi


def resolve(raw: str, vals: dict[str, int]):
    """`(NPC_NAME *)&local_44` · `1` · `false` → 값."""
    raw = raw.strip()
    if raw in ("true", "false"):
        return raw == "true"
    m = re.search(r"&?(\w+)$", raw)
    if m and m.group(1) in vals:
        return vals[m.group(1)]
    m = re.fullmatch(r"\(?" + NUM + r"\)?", raw)
    if m:
        return int(m.group(1), 0)
    return None


def rebuild(bmap: dict[int, int]) -> str | None:
    """바이트 단위 대입으로 조립된 문자열 복원(libc++ SSO 버퍼: [0]=길이*2)."""
    if 0 not in bmap:
        return None
    n = bmap[0] >> 1
    chars = []
    for i in range(1, n + 1):
        c = bmap.get(i)
        if c is None or not (0x20 <= c < 0x7F):
            return None
        chars.append(chr(c))
    s = "".join(chars)
    return s if len(s) > 3 else None


def case_counts(cls: str) -> list[tuple[int, int]]:
    """`initScenarioData` 의 case → 그 회차가 쓰는 스텝 수(선언 순서)."""
    p = DECOMP / f"{cls}.c"
    if not p.exists():
        return []
    src = p.read_text(encoding="utf-8", errors="replace")
    i = src.find("==== initScenarioData")
    if i < 0:
        return []
    fn = src[i: src.find("/* ==== ", i + 10)]
    parts = re.split(r"\n\s*case (0x[0-9a-f]+|\d+):", fn)
    out = []
    for k in range(1, len(parts), 2):
        out.append((int(parts[k], 0), len(re.findall(r"PTR_FUN_", parts[k + 1]))))
    return out


## ── switch 형 회차 클래스(`Scenario1`~`Scenario8`) ──────────────────────────────
## 이쪽은 `initScenarioData` 가 없다. `setNext(CCObject*)` 가 **스텝 번호로 switch** 하고,
## case 마다 공유 지역변수(npc/state/pos/emoticon)를 세팅한 뒤 **함수 꼬리에서 한 번**
## `setNpcTalk` 을 부른다(근거: `Scenario8::setNext` @01652880 꼬리 LAB_01653898).
## 대사만 넘기는 case 는 `setUserTalk` 로 goto 한다.
##
## 🔴 **기본 비활성(`--switch` 로만 켠다). 2026-07-31 검수 결과 신뢰할 수 없다.**
##   대사 수 검증(`accept_if_exact`)은 통과해도 **화자가 어긋난다.** 실측: 81화가 수량은
##   43/43 로 맞았지만, 내레이션("나는 피노에게 화를 풀라고 말했다")이 `romini` 로 붙었다.
##   원인 = Ghidra 가 **본문이 같은 case 라벨을 하나로 합쳐** 출력한다
##   (`case 5: case 9: case 6: case 7: case 8:` 처럼 번호 순서까지 뒤섞인다).
##   그래서 스텝별 npc/state/pos 값이 소실된다. 제대로 하려면 점프 테이블을 디스어셈블
##   수준에서 따라가야 한다 — 그 근거가 서기 전에는 붙이지 않는다(HARD RULE 6).
##   코드는 그때를 위해 남겨 둔다.
STEP_SWITCH = re.compile(r"switch\s*\(\s*\*\(int \*\)\(\w+ \+ 0x158\)\s*\)\s*\{")
SN_GUARD = re.compile(r"if \(\w+ != (0x[0-9a-f]+)\)")


def parse_switch_class(cls: str) -> dict[str, list[dict]]:
    p = DECOMP / f"{cls}.c"
    if not p.exists():
        return {}
    src = p.read_text(encoding="utf-8", errors="replace")
    i = src.find("==== setNext @")
    if i < 0:
        return {}
    body = src[i: src.find("/* ==== ", i + 10)]
    flat = re.sub(r"\s*\n\s*", " ", body)
    # 꼬리 호출에서 공유 변수 이름을 알아낸다
    tail = re.search(
        r"setNpcTalk\s*\([^;]*?\(NPC_NAME \*\)&(\w+),\s*\(Character_State \*\)&(\w+),"
        r"\s*\(Character_Pos \*\)&(\w+),\s*\(TalkEmoticon \*\)&(\w+)", flat)
    if not tail:
        return {}
    names = {"npc": tail.group(1), "state": tail.group(2),
             "pos": tail.group(3), "emoticon": tail.group(4)}
    # 꼬리 `setNpcTalk` 을 **건너뛰는** 라벨 = 그 호출 바로 뒤에 정의된 라벨.
    # 이 라벨로 goto 하는 case 는 대사를 내보내지 않는다(연출만 하는 스텝).
    skip_m = re.search(r"setNpcTalk\s*\([^;]*?\);\s*(LAB_\w+):", flat)
    skip_label = skip_m.group(1) if skip_m else None
    # sn 가드는 바깥부터 나오고 switch 는 안쪽부터 나온다 → 가드를 뒤집어 짝짓는다
    guards = [int(g, 0) for g in SN_GUARD.findall(flat)]
    blocks = [m.start() for m in STEP_SWITCH.finditer(flat)]
    if not blocks or len(guards) < len(blocks):
        return {}
    sns = list(reversed(guards[:len(blocks)]))
    out: dict[str, list[dict]] = {}
    for bi, start in enumerate(blocks):
        end = blocks[bi + 1] if bi + 1 < len(blocks) else len(flat)
        seg = flat[start:end]
        cases = list(re.finditer(r"case (0x[0-9a-f]+|\d+):", seg))
        # ⚠️ `case 5: case 9: case 6:` 처럼 **연속된 라벨은 본문을 공유**한다(원작에서 그 스텝들이
        #    같은 코드로 간다 — 실측: Scenario8::setNext 의 case 라벨 119개가 서로 다른 주소 63개).
        #    라벨마다 잘라 버리면 앞쪽 라벨이 빈 본문을 갖게 돼 내레이션 스텝을 놓친다.
        steps: list[tuple[int, str]] = []
        ci = 0
        while ci < len(cases):
            run = [ci]
            while (run[-1] + 1 < len(cases)
                   and seg[cases[run[-1]].end(): cases[run[-1] + 1].start()].strip() == ""):
                run.append(run[-1] + 1)
            last = run[-1]
            cend = cases[last + 1].start() if last + 1 < len(cases) else len(seg)
            body_txt = seg[cases[last].end():cend]
            for k in run:
                steps.append((int(cases[k].group(1), 0), body_txt))
            ci = last + 1
        steps.sort(key=lambda t: t[0])
        # 라벨 블록(공유 꼬리) — case 본문이 `goto LAB_x` 로 여기 합류해 값을 대입한다.
        labels: dict[str, str] = {}
        for lm in re.finditer(r"(LAB_\w+):", seg):
            nxt = re.search(r"(?:LAB_\w+:|case (?:0x[0-9a-f]+|\d+):|default:)", seg[lm.end():])
            labels[lm.group(1)] = seg[lm.end(): lm.end() + (nxt.start() if nxt else 400)]
        flow: list[dict] = []
        # 대부분의 스텝은 화자를 새로 지정하지 않고 **직전 화자가 이어 말한다**
        # (공유 본문으로 가는 case 가 그렇다). 그래서 값은 스텝 간 유지한다.
        carry: dict[str, int | None] = {k: None for k in names}
        for _n, chunk in steps:
            # 실행 경로를 펼친다: 본문 + 따라가는 goto 라벨 블록(최대 4단)
            path, seen_lbl = chunk, set()
            for _ in range(4):
                gm = re.search(r"goto (LAB_\w+);", path)
                if not gm or gm.group(1) in seen_lbl or gm.group(1) not in labels:
                    break
                seen_lbl.add(gm.group(1))
                path += " " + labels[gm.group(1)]
            # 경로 안의 스칼라 대입을 순서대로 추적(중간 변수 uVarNN 포함)
            env: dict[str, int] = {}
            for am in re.finditer(r"\b(\w+)\s*=\s*(?:\([^()]*\))?\s*(?:CONCAT44\([^,]*,\s*)?"
                                  r"(" + NUM + r"|\w+)\s*\)?\s*;", path):
                dst, srcv = am.group(1), am.group(2)
                if re.fullmatch(NUM, srcv):
                    env[dst] = int(srcv, 0)
                elif srcv in env:
                    env[dst] = env[srcv]
            for k, v in names.items():
                if env.get(v) is not None:
                    carry[k] = env[v]
            cur = dict(carry)
            for op, args in (("changeBackGround", ("bg",)), ("drawIllust", ("illust", "kind"))):
                for om in re.finditer(r"ScenarioSupport::" + op + r"\s*\(([^;]*?)\)", chunk):
                    rec: dict = {"op": op}
                    raw = [a.strip() for a in om.group(1).split(",")][1:]
                    for lab, r in zip(args, raw):
                        rec[lab] = resolve(r, {})
                    flow.append(rec)
            if "setOutTalker" in chunk:
                flow.append({"op": "setOutTalker"})
            if "setUserTalk" in chunk or "caseD_3" in chunk:
                flow.append({"op": "setUserTalk"})
            elif skip_label and f"goto {skip_label}" in chunk:
                pass                      # 연출만 하고 대사는 안 넘기는 스텝
            else:
                flow.append({"op": "setNpcTalk", **{k: v for k, v in cur.items() if v is not None}})
        out[str(sns[bi])] = flow
    return out


def inject_story_battles(flows: dict[str, list[dict]]) -> int:
    """1~78화의 스토리 전투를 흐름에 **주입**한다.

    🟦 사용자 확정 2026-07-31: 스토리 전투는 **별도 던전 방문 없이 스토리 중에** 벌어지고
       끝나면 그 시점으로 돌아온다 — 82~101화(`scenarioBattle`)와 같은 구조다.

    ⚠️ 그런데 1~78화는 **어느 스텝인지 코드에서 못 뽑는다.** 원작이 `scenarioBattle` 을
       안 거치고 `AdventureScene::scene` 을 직접 부르는데, 그 호출을 회차에 귀속시키는
       방법을 세 가지 시도해 전부 실패했다(주소 근접 · 스텝 순회 · 개선된 순회 재시도 —
       셋 다 회차가 안 갈린다. 상세 = docs/ref/porting/ScenarioWiring.md §14).

    ⇒ **회차↔전투번호는 사용자 확정값**(data/story_monsters.json `battle_no`)을 쓴다.
      위치도 사용자가 **전투 직전 대사**로 확정해 주면 `battle_after_line` 에 적고
      그 줄 **바로 뒤**에 꽂는다. 없으면 회차 마지막(폴백).
    """
    sm = json.loads((REPO / "data" / "story_monsters.json").read_text(encoding="utf-8"))
    n = 0
    for m in sm.get("monsters", []):
        for ep, bno in (m.get("battle_no") or {}).items():
            ops = flows.get(str(ep))
            if ops is None:
                continue
            if any(o.get("op") == "scenarioBattle" for o in ops):
                continue                     # 원작에서 이미 뽑힌 회차(82~101)는 건드리지 않는다
            after = (m.get("battle_after_line") or {}).get(str(ep))
            rec = {"op": "scenarioBattle", "battle": int(bno)}
            pos = None
            if after is not None:
                want = "ScenarioTalk%s_%d" % (ep, int(after))
                for i, o in enumerate(ops):
                    if o.get("op") == "setTalk" and o.get("key") == want:
                        pos = i + 1          # 그 대사 **바로 뒤**
                        break
            if pos is None:
                rec["_placement"] = "회차 끝(원작 스텝 미확인 · 앵커 대사도 못 찾음)"
                ops.append(rec)
            else:
                rec["_placement"] = "사용자 확정 — 대사 %d줄 직후" % int(after)
                ops.insert(pos, rec)
            n += 1
    return n


def sanitize_names(ops: list[dict], scen: dict) -> list[dict]:
    """화자 칸에 **문자열 리소스 키**가 새는 것을 막는다.

    원작은 대사 함수 직전에 멤버 두 곳에 문자열을 써 둔다 —
    `this+0x1d8`=화자(`NPC_nuri`) · `this+0x1f0`=대사 키(`ScenarioTalk1_1`).
    두 대입이 한 블록에 다 있으면 정확히 갈리지만, 화자 대입이 없는 스텝에서는
    직전 값이 그대로 남아 **대사 키가 화자로 실린다**(`PrologueTalk2` 등).
    ⇒ `<NPC_*>` 전표(62종)에 있는 이름만 화자로 인정하고 나머지는 비운다.
       여기서 추측해 채우지 않는다(HARD RULE 6).
    """
    valid = set(scen.get("npc_names", {}).keys())
    for o in ops:
        nm = o.get("npc_name")
        if isinstance(nm, str) and nm.startswith("NPC_"):
            nm = nm[4:]
            o["npc_name"] = nm
        if nm is not None and nm not in valid:
            o["npc_name"] = None
    return ops


def accept_if_exact(flows: dict[str, list[dict]], scenarios: dict) -> dict[str, list[dict]]:
    """대사 스텝 수가 원작 대사 줄 수와 **정확히 일치**하는 회차만 통과시킨다."""
    ok = {}
    for sn, ops in flows.items():
        # ⚠️ `setTalker` 도 대사 스텝이다 — 1~78화(`Scenario1~7`)는 NPC 를 번호가 아니라
        #    **이름 문자열**로 넘기는 이 오버로드를 쓴다. 종전에는 이걸 안 세서 그 회차들이
        #    전부 "흐름 대사 0" 으로 보였고, 추출이 성공한 뒤에도 게이트가 통째로 막았다.
        talk = sum(1 for o in ops if o["op"] in ("setNpcTalk", "setUserTalk", "setTalker", "setTalk"))
        lines = sum(len(p.get("lines", [])) for p in scenarios.get(sn, {}).get("parts", []))
        if lines and talk == lines:
            ok[sn] = ops
        else:
            print(f"  (보류) ep{sn}: 흐름 대사 {talk} != 원작 {lines} — 채택 안 함")
    return ok


def parse_class(cls: str) -> dict[str, list[dict]]:
    text = (LAMBDA / f"{cls}.c").read_text(encoding="utf-8", errors="replace")
    blocks = split_blocks(text)
    # $_N 태그 → 바로 앞의 호출 본문
    # 같은 본문이 두 태그에 붙지 않도록 **한 번 쓰면 소비**한다(중복 대사의 원인이었다).
    steps: dict[int, list[dict]] = {}
    pending: tuple[int, list[dict]] | None = None
    for addr, b in blocks:
        tag = re.search(r"\$_(\d+)\"", b)
        ops = parse_body(b)
        if tag:
            n = int(tag.group(1))
            if n not in steps:
                steps[n] = pending[1] if pending else []
                pending = None
        if ops:
            pending = (addr, ops)
    counts = case_counts(cls)
    idx = sorted(steps)
    out: dict[str, list[dict]] = {}
    pos = 0
    for sn, cnt in counts:
        flow: list[dict] = []
        for n in idx[pos: pos + cnt]:
            flow.extend(steps[n])
        out[str(sn)] = flow
        pos += cnt
    return out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    argv = sys.argv[1:]
    report = "--report" in argv
    classes = []
    if "--classes" in argv:
        classes = argv[argv.index("--classes") + 1].split(",")
    if not classes:
        classes = sorted(p.stem for p in LAMBDA.glob("*.c"))
    npcs, bgs, bgms = npc_table(), bg_table(), bgm_table()
    items = item_table()
    mnpc = monster_npc_table()
    scen = json.loads((REPO / "data" / "scenario.json").read_text(encoding="utf-8"))
    scenarios = scen.get("scenarios", {})
    flows: dict[str, list[dict]] = {}
    variants: dict[str, dict[str, list[dict]]] = {}
    # switch 형(Scenario1~8) — 점프 테이블에서 뽑은 산출이 있으면 그걸 쓴다.
    # (디컴프 C 로 짜맞추는 아래 `--switch` 경로는 신뢰 불가로 판정됐다. 아래 주석 참조.)
    sw_json = REPO / "data" / "scenario_flow_switch.json"
    if sw_json.exists():
        sw = json.loads(sw_json.read_text(encoding="utf-8")).get("flows", {})
        flows.update(accept_if_exact(sw, scenarios))
    if "--switch" in argv:
        for c in [f"Scenario{i}" for i in range(1, 9)]:
            sw = parse_switch_class(c)
            if sw:
                flows.update(accept_if_exact(sw, scenarios))
    for c in classes:
        f = parse_class(c)
        if c in VARIANT_CLASSES:
            variants[c] = f
        else:
            flows.update(f)
        if report:
            for sn, ops in f.items():
                talk = sum(1 for o in ops if o["op"] in ("setNpcTalk", "setUserTalk"))
                who = {npcs.get(o.get("npc"), o.get("npc")) for o in ops if o["op"] == "setNpcTalk"}
                print(f"  ep{sn}: 스텝 {len(ops):>3} · 대사 {talk:>3} · 화자 {sorted(map(str, who))}")
    n_inj = inject_story_battles(flows)
    doc = {
        "_re_basis": (
            "원작 클라 하드코딩 복원. ScenarioManager::makeScenarioLayer(sn) 이 회차를 "
            "Scenario1~8/_zimon/_mamorudic/_Kadeath 로 가르고, 각 클래스 initScenarioData 가 "
            "std::function 스텝을 push 한다. 102화 이상은 ScenarioCommon=서버 script 라 여기 없다. "
            "추출 = extract_scenario_flow.py → parse_scenario_flow.py"
        ),
        "npc_names": {str(k): v for k, v in sorted(npcs.items())},
        "backgrounds": {str(k): v for k, v in sorted(bgs.items())},
        "bgm": {str(k): v for k, v in sorted(bgms.items())},
        "sc_items": {str(k): v for k, v in sorted(items.items())},
        "monster_npc": {str(k): v for k, v in sorted(mnpc.items())},
        "flows": {k: sanitize_names(flows[k], scen) for k in sorted(flows, key=int)},
        "variants": variants,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"-> {OUT}  회차 {len(flows)} · NPC {len(npcs)} · 배경 {len(bgs)} · BGM {len(bgms)} · 소품 {len(items)} · 컷신몹 {len(mnpc)} · 전투주입 {n_inj}")


if __name__ == "__main__":
    main()
