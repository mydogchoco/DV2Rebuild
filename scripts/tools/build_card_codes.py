"""카드 코드(이스터에그) 표 빌드 — 평문 CSV → **복호 불가능한** `data/card_codes.json`.

왜 암호화하나
-------------
빌드된 게임 파일을 뜯어서 "쓸 수 있는 코드 목록"과 "무슨 보상이 나오나"를 미리 보는 것을
막는다(사용자 요청 2026-07-30). 다만 **키를 빌드에 같이 넣는 방식은 난독화일 뿐**이라
(뜯는 사람이 데이터를 찾으면 키도 찾는다) 여기서는 **코드 자체를 키로 쓴다.**

    조회 키 = iter_sha256(SALT_ID  + 정규화코드)      ← 단방향. 역산 불가
    암호 키 = iter_sha256(SALT_KEY + 정규화코드)      ← 빌드에 존재하지 않는다
    보상    = XOR(보상JSON, SHA256 키스트림(암호키, nonce))

게임은 플레이어가 **입력한 코드**로 같은 키를 만들어 조회·복호한다. 즉 빌드 안에는 키가 없고,
파일을 뜯어도 나오는 것은 "코드가 몇 개인가" 뿐이다. 유일한 공격은 무차별 대입인데
16자리 영숫자면 36^16 ≈ 8e24 라 사실상 불가능하다.

⚠️ **평문 CSV 는 절대 커밋하지 않는다** — 이 레포는 공개다(`mydogchoco/DV2Rebuild`).
`docs/input/sheets/card_codes.csv` 는 `.gitignore` 에 있다. 사용자 로컬 원본이 정본이고,
커밋되는 것은 암호화 산출물뿐이다.

암호 구성이 AES 가 아닌 이유
---------------------------
이 환경의 Python 에 AES 라이브러리가 없고(`pycryptodome`·`cryptography` 둘 다 미설치),
Godot 쪽 `AESContext` 와 바이트 단위로 맞추는 비용도 있다. SHA-256 은 **양쪽 다 내장**이라
(`hashlib` / `HashingContext`) 의존성 없이 동일 구현을 보장할 수 있다. 여기 쓰는 구성은
표준 CTR 모드(키스트림 = 해시(키‖nonce‖카운터))로, 항목마다 nonce 가 달라 키스트림 재사용이 없다.

사용법
------
    python scripts/tools/build_card_codes.py --init      # 빈 CSV 템플릿 생성(있으면 보존)
    python scripts/tools/build_card_codes.py             # CSV → data/card_codes.json
    python scripts/tools/build_card_codes.py --verify    # 빌드 후 전 코드 복호 왕복 검증
    python scripts/tools/build_card_codes.py --flag 이름  # 플래그 해시 키 출력(GDScript 상수용)
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CSV_PATH = REPO / "docs/input/sheets/card_codes.csv"
OUT_PATH = REPO / "data/card_codes.json"
ITEMS_PATH = REPO / "data/items.json"
GEMS_PATH = REPO / "data/gems.json"
DRAGONS_PATH = REPO / "data/dragons.json"

# `--csv` / `--out` 으로 갈아 끼운다. 회귀 테스트용 픽스처
# (`scripts/tools/fixtures/card_codes_test.csv` → `card_codes_test.json`)를 굽는 데 쓴다 —
# 그래야 검증이 사용자의 **실제 코드표에 의존하지 않는다**.

# ── 암호 상수 — GDScript `scripts/systems/card_code.gd` 와 **반드시 같아야 한다** ──────────
SALT_ID = b"dv2.cc.id.v1"
SALT_KEY = b"dv2.cc.key.v1"
SALT_FLAG = b"dv2.flag.v1:"
ITER = 10000  # 반복 해시 횟수. 무차별 대입 비용을 올린다(정상 조회는 1회라 체감 없음)

HEADER = [
    "코드",
    "보상종류",
    "보상키",
    "개수",
    "사용제한",
    "문구",
    "비고",
]

KIND_MAP = {
    "아이템": "item",
    "골드": "gold",
    "다이아": "dia",
    "다이아몬드": "dia",
    "알": "egg",
    "드래곤": "dragon",
    "플래그": "flag",
}


# ── 해시/암호 ────────────────────────────────────────────────────────────────
def _rel(p: Path) -> str:
    try:
        return str(p.relative_to(REPO))
    except ValueError:
        return str(p)


# 한글 코드에 섞여 들어오는 문장부호. 여기 있는 것만 버린다(글자는 무엇이든 남긴다).
# ⚠️ `scripts/systems/card_code.gd` 의 `PUNCT_EXTRA` 와 **한 글자도 다르면 안 된다.**
PUNCT_EXTRA = "·—–―…“”‘’、。，．！？：；（）［］｛｝「」『』〈〉《》〜～"
# 눈에 안 보이는 공백류 — 소스에 그대로 넣으면 편집기·파서가 삼킬 수 있어 **코드포인트로** 적는다.
SPACE_CP = {0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
            0x2007, 0x2008, 0x2009, 0x200A, 0x200B, 0x2028, 0x2029, 0x202F, 0x205F,
            0x3000, 0xFEFF}


def norm_code(code: str) -> str:
    """입력 정규화 — 글자·숫자만 남기고 ASCII 는 대문자로.

    하이픈·공백·문장부호 표기 차이를 흡수한다. **한글 코드를 지원한다**(사용자가 한국어
    문장을 코드로 쓴다 — 2026-07-31). 종전 구현은 `[^0-9A-Za-z]` 를 전부 지워서 한글 코드가
    빈 문자열이 되고 그 행이 **조용히 사라졌다.**

    - ASCII 영숫자: 그대로(소문자→대문자)
    - 그 밖의 ASCII(공백·하이픈·마침표·콜론…): 버린다
    - 비-ASCII: `PUNCT_EXTRA` 와 공백류만 버리고 **나머지는 그대로 남긴다**
      (대소문자 변환을 걸지 않는다 — Python `.upper()` 와 GDScript `to_upper()` 가
       특수 문자에서 갈라질 수 있어 ASCII 로만 제한한다)

    ⚠️ 한글은 NFC 로 통일한다. Windows/IME 입력은 NFC 라 게임 쪽 입력과 일치한다.
    """
    out = []
    for ch in unicodedata.normalize("NFC", code):
        if "0" <= ch <= "9" or "A" <= ch <= "Z":
            out.append(ch)
        elif "a" <= ch <= "z":
            out.append(ch.upper())
        elif ord(ch) >= 0x80 and ch not in PUNCT_EXTRA and ord(ch) not in SPACE_CP:
            out.append(ch)
    return "".join(out)


def iter_sha256(salt: bytes, code: str, iterations: int = ITER) -> bytes:
    h = hashlib.sha256(salt + code.encode("utf-8")).digest()
    for _ in range(iterations - 1):
        h = hashlib.sha256(h).digest()
    return h


def keystream(key: bytes, nonce: bytes, length: int) -> bytes:
    """SHA-256 CTR 키스트림. 블록 i = sha256(key ‖ nonce ‖ i(4바이트 빅엔디안))."""
    out = bytearray()
    counter = 0
    while len(out) < length:
        out += hashlib.sha256(key + nonce + counter.to_bytes(4, "big")).digest()
        counter += 1
    return bytes(out[:length])


def xor(data: bytes, stream: bytes) -> bytes:
    return bytes(a ^ b for a, b in zip(data, stream))


def tag_of(key: bytes, nonce: bytes, cipher: bytes) -> str:
    """무결성 태그 — 복호 결과가 맞는 코드로 푼 것인지 확인한다(보안 경계가 아니라 정합성 검사)."""
    return hashlib.sha256(key + nonce + cipher).hexdigest()[:32]


def flag_key(name: str) -> str:
    """트리거 플래그의 저장 키. 평문 이름을 빌드·세이브 어디에도 남기지 않기 위한 해시."""
    return hashlib.sha256(SALT_FLAG + name.strip().encode("utf-8")).hexdigest()[:32]


# ── 보상키 해석 — 자연어 이름 → 실제 키 ────────────────────────────────────────
#
# 사용자는 시트에 `data/items.json` 키가 아니라 **게임에 보이는 이름**을 적는다
# (2026-07-31 확정). 여기서 이름을 키로 옮긴다. 못 찾으면 **빌드를 실패시킨다** —
# 조용히 건너뛰면 코드는 살아 있는데 보상만 빠진 표가 나온다(HARD RULE 6: 지어내지 않는다).
#
#   1) `data/items.json` 키와 정확히 같으면 그대로
#   2) `gem:` 으로 시작하면 그대로(고급 표기)
#   3) `items.json` 의 `name` 과 일치(공백·괄호 무시)
#   4) 젬 이름 + 티어 표기 → `Gem.item_key()` 가상 인벤 키 `gem:<젬이름>:<0-base 티어>`
#      "방어의 소울젬 10등급" → `gem:방어의 소울젬:9`
#      "샌즈의 젬 80/15/15"  → 티어 수치로 역조회(유일하게 맞는 티어가 있어야 한다)

_ITEMS: dict | None = None
_GEMS: dict | None = None
_DRAGON_IDS: set | None = None


def _nrm_name(s: str) -> str:
    """이름 비교용 정규화 — 공백·괄호·하이픈을 무시한다('권능 5레벨' == '권능(5레벨)')."""
    return re.sub(r"[\s()（）\[\]\-_·]", "", unicodedata.normalize("NFC", s)).lower()


def _load_masters() -> None:
    global _ITEMS, _GEMS, _DRAGON_IDS
    if _ITEMS is not None:
        return
    _ITEMS = json.loads(ITEMS_PATH.read_text(encoding="utf-8"))
    _GEMS = json.loads(GEMS_PATH.read_text(encoding="utf-8")).get("gems", {})
    try:
        dragons = json.loads(DRAGONS_PATH.read_text(encoding="utf-8"))
        _DRAGON_IDS = {int(d["id"]) for d in dragons if isinstance(d, dict) and "id" in d}
    except Exception:
        _DRAGON_IDS = set()


def _item_by_name(text: str) -> str | None:
    want = _nrm_name(text)
    hits = [k for k, v in _ITEMS.items()
            if isinstance(v, dict) and _nrm_name(str(v.get("name", ""))) == want]
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        raise ValueError(f"이름 '{text}' 이 아이템 {hits} 여러 개와 맞는다 — 키로 적어 주세요")
    return None


def _gem_by_name(text: str) -> str | None:
    """'<젬 이름> <티어표기>' → 가상 인벤 키. 젬 이름으로 시작하지 않으면 None."""
    t = re.sub(r"\s+", "", unicodedata.normalize("NFC", text))
    for name in sorted(_GEMS, key=len, reverse=True):
        if not t.startswith(re.sub(r"\s+", "", name)):
            continue
        spec = t[len(re.sub(r"\s+", "", name)):].strip()
        tiers = _GEMS[name].get("tiers", [])
        if not spec:
            raise ValueError(f"'{text}' — 젬은 티어를 함께 적어야 합니다"
                             f"(예: '{name} 10등급', 1~{len(tiers)})")
        # (a) "10등급" / "10단계" / "10티어" / "10" → 1-base 티어
        m = re.fullmatch(r"(\d+)\s*(등급|단계|티어|레벨|tier)?", spec)
        if m:
            idx = int(m.group(1)) - 1
            if not (0 <= idx < len(tiers)):
                raise ValueError(f"'{text}' — 티어는 1~{len(tiers)} 범위여야 합니다")
            return "gem:%s:%d" % (name, idx)
        # (b) "80/15/15" → 능력치 수치로 티어 역조회
        nums = sorted(int(x) for x in re.findall(r"\d+", spec))
        if not nums:
            raise ValueError(f"'{text}' — 젬 티어 표기를 알아볼 수 없습니다: '{spec}'")
        hits = [i for i, tr in enumerate(tiers) if sorted(int(v) for v in tr.values()) == nums]
        if len(hits) == 1:
            return "gem:%s:%d" % (name, hits[0])
        if not hits:
            raise ValueError(f"'{text}' — 그 수치와 맞는 {name} 티어가 없습니다"
                             f"(수치는 data/gems.json 기준)")
        raise ValueError(f"'{text}' — 그 수치가 {name} 티어 {[h + 1 for h in hits]} 와 겹칩니다"
                         f" — '<N>등급' 으로 적어 주세요")
    return None


def resolve_item_key(text: str) -> str:
    """자연어 보상키 → 인벤토리 키. 못 찾으면 ValueError."""
    _load_masters()
    key = text.strip()
    if key in _ITEMS or key.startswith("gem:") or key.startswith("egg:"):
        return key
    got = _item_by_name(key)
    if got:
        return got
    got = _gem_by_name(key)
    if got:
        return got
    raise ValueError(f"'{text}' — data/items.json 에도 data/gems.json 에도 없는 이름입니다")


# ── CSV ──────────────────────────────────────────────────────────────────────
TEMPLATE_ROWS = 24

TEMPLATE_NOTE = [
    "# 이 파일은 gitignore 대상입니다 — 평문 코드가 공개 레포에 올라가지 않게 합니다.",
    "# 한 코드에 보상이 여러 개면 같은 코드로 행을 늘리세요(box_loot.csv 와 같은 방식).",
    "# 보상종류: 아이템 / 골드 / 다이아 / 알 / 드래곤 / 플래그",
    "#   아이템 → 보상키 = 게임에 보이는 이름(예: 데르사의 축복) 또는 data/items.json 키",
    "#           젬은 '<젬 이름> <티어>' (예: 방어의 소울젬 10등급 / 샌즈의 젬 80/15/15)",
    "#   골드·다이아 → 보상키는 비우고 개수만",
    "#   알 → 보상키 = 드래곤 id (가방에 egg:<id> 로 들어갑니다)",
    "#   드래곤 → 보상키 = 드래곤 id (레벨1 개체로 지급)",
    "#   플래그 → 보상키 = 플래그 이름 (빌드에는 해시만 실립니다)",
    "# 사용제한: 1(기본) / N=N번까지 / 무제한",
    "# 모르는 칸은 비워 두세요. 코드 칸이 비면 그 행은 무시됩니다.",
]


def write_template(force: bool) -> int:
    if CSV_PATH.exists() and not force:
        print(f"이미 있음(보존): {_rel(CSV_PATH)}")
        return 0
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    with CSV_PATH.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        for line in TEMPLATE_NOTE:
            w.writerow([line])
        w.writerow(HEADER)
        for _ in range(TEMPLATE_ROWS):
            w.writerow([""] * len(HEADER))
    print(f"생성: {_rel(CSV_PATH)}  (헤더 + 빈 {TEMPLATE_ROWS}행)")
    return 0


def read_rows() -> list[dict]:
    if not CSV_PATH.exists():
        print(f"CSV 가 없습니다: {_rel(CSV_PATH)}\n"
              f"  python scripts/tools/build_card_codes.py --init  로 만드세요.", file=sys.stderr)
        raise SystemExit(2)
    with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))
    # 주석(#) 줄을 걷어내고 헤더 줄을 찾는다.
    head_i = next((i for i, r in enumerate(rows) if r and r[0].strip() == HEADER[0]), None)
    if head_i is None:
        print("CSV 에 헤더 줄(첫 칸 '코드')이 없습니다.", file=sys.stderr)
        raise SystemExit(2)
    head = [c.strip() for c in rows[head_i]]
    out = []
    for r in rows[head_i + 1:]:
        if not r or not r[0].strip() or r[0].lstrip().startswith("#"):
            continue
        out.append({head[i]: (r[i].strip() if i < len(r) else "") for i in range(len(head))})
    return out


def parse_reward(row: dict) -> tuple[dict | None, str]:
    """CSV 한 행 → 보상 1건. 돌려주는 둘째 값은 **해석 로그**(사용자 검수용, 없으면 "")."""
    raw_kind = row.get("보상종류", "").strip()
    if not raw_kind:
        return None, ""
    kind = KIND_MAP.get(raw_kind)
    if kind is None:
        raise ValueError(f"모르는 보상종류 '{raw_kind}'")
    key = row.get("보상키", "").strip()
    try:
        n = int(row.get("개수", "").strip() or 1)
    except ValueError:
        n = 1
    if kind in ("gold", "dia"):
        return {"t": kind, "n": n}, ""
    if kind in ("egg", "dragon"):
        if not key.isdigit():
            raise ValueError(f"{raw_kind} 는 보상키가 드래곤 id(숫자)여야 합니다: '{key}'")
        _load_masters()
        if _DRAGON_IDS and int(key) not in _DRAGON_IDS:
            raise ValueError(f"드래곤 id {key} 가 data/dragons.json 에 없습니다")
        return {"t": kind, "k": int(key), "n": n}, ""
    if kind == "flag":
        if not key:
            raise ValueError("플래그 이름이 비었습니다")
        return {"t": "flag", "k": flag_key(key)}, ""
    if not key:
        raise ValueError("아이템 이름/키가 비었습니다")
    resolved = resolve_item_key(key)
    return {"t": "item", "k": resolved, "n": n}, ("" if resolved == key else f"{key} → {resolved}")


# 사용제한 열 — "무제한"/"0" = 제한 없음, "N"/"N회" = N번까지, 빈 칸 = 1회.
def parse_uses(text: str) -> int:
    t = re.sub(r"\s+", "", text or "")
    if not t:
        return 1
    if t in ("무제한", "무한", "unlimited", "0", "0회"):
        return 0
    m = re.fullmatch(r"(\d+)\s*(회|번|times)?", t)
    if m:
        return int(m.group(1))
    if t in ("1회", "일회", "once"):
        return 1
    raise ValueError(f"사용제한을 알아볼 수 없습니다: '{text}' (예: 1 / 10 / 무제한)")


def build(verify: bool) -> int:
    rows = read_rows()
    # 코드별로 묶는다(같은 코드 여러 행 = 보상 여러 개).
    grouped: dict[str, dict] = {}
    order: list[str] = []
    errors: list[str] = []
    resolved_log: list[str] = []
    for i, row in enumerate(rows, start=2):
        raw_code = row.get("코드", "")
        code = norm_code(raw_code)
        if not code:
            if raw_code.strip():
                errors.append(f"{i}행: 코드 '{raw_code.strip()}' 이 정규화하면 빈 문자열이 됩니다"
                              " (글자·숫자가 하나도 없습니다)")
            continue
        try:
            rew, note = parse_reward(row)
            uses = parse_uses(row.get("사용제한", ""))
        except ValueError as e:
            errors.append(f"{i}행: {e}")
            continue
        if rew is None:
            continue
        if note:
            resolved_log.append(f"  {i}행: {note}")
        g = grouped.setdefault(code, {"rewards": [], "msg": "", "once": True, "uses": 1})
        if code not in order:
            order.append(code)
        g["rewards"].append(rew)
        if row.get("문구", "").strip():
            g["msg"] = row["문구"].strip()
        # 같은 코드의 여러 행에 사용제한이 적혀 있으면 **가장 느슨한 값**을 쓴다
        # (0=무제한이 가장 느슨하다). 행마다 다르면 아래에서 알려 준다.
        g["uses"] = 0 if 0 in (g["uses"], uses) else max(g["uses"], uses)
        g["once"] = g["uses"] == 1

    if errors:
        print("빌드 중단 — 아래를 고친 뒤 다시 실행하세요:", file=sys.stderr)
        for e in errors:
            print("  ❌ " + e, file=sys.stderr)
        return 2
    if resolved_log:
        print("이름 → 키 변환:")
        for line in resolved_log:
            print(line)

    entries = []
    for code in order:
        payload = grouped[code]
        if not payload["rewards"]:
            continue
        plain = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        # nonce 는 항목마다 다르게 — 같은 보상이라도 암호문이 겹치지 않는다.
        nonce = os.urandom(16)
        key = iter_sha256(SALT_KEY, code)
        cipher = xor(plain, keystream(key, nonce, len(plain)))
        entries.append({
            "id": iter_sha256(SALT_ID, code).hex(),
            "n": nonce.hex(),
            "d": cipher.hex(),
            "t": tag_of(key, nonce, cipher),
        })

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps({
        "_basis": ("점술집 '카드 코드' 이스터에그 표. 원작 판정은 서버 몫이라 유실 — 사용자가 채운다. "
                   "원본은 docs/input/sheets/card_codes.csv(gitignore, 평문). "
                   "여기 실리는 것은 코드로만 풀리는 암호문이라 목록·보상을 역산할 수 없다."),
        "_tool": "scripts/tools/build_card_codes.py",
        "iter": ITER,
        "entries": entries,
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"빌드: {_rel(OUT_PATH)}  코드 {len(entries)}개")
    for code in order:
        g = grouped[code]
        lim = "무제한" if g["uses"] == 0 else f"{g['uses']}회"
        print(f"  · 보상 {len(g['rewards'])}건 / {lim}")

    if verify:
        ok = 0
        for code in order:
            got = decrypt(code, {"entries": entries})
            if got == grouped[code]:
                ok += 1
            else:
                print(f"  ❌ 왕복 실패: {code}", file=sys.stderr)
        print(f"검증: {ok}/{len(order)} 왕복 성공")
        if ok != len(order):
            return 1
    return 0


def decrypt(code: str, table: dict) -> dict:
    """게임(GDScript)이 하는 것과 같은 절차 — 검증용 참조 구현."""
    c = norm_code(code)
    want = iter_sha256(SALT_ID, c).hex()
    for e in table.get("entries", []):
        if e.get("id") != want:
            continue
        key = iter_sha256(SALT_KEY, c)
        nonce = bytes.fromhex(e["n"])
        cipher = bytes.fromhex(e["d"])
        if tag_of(key, nonce, cipher) != e.get("t"):
            return {}
        return json.loads(xor(cipher, keystream(key, nonce, len(cipher))).decode("utf-8"))
    return {}


def main() -> int:
    ap = argparse.ArgumentParser(description="카드 코드 표 빌드(평문 CSV → 암호화 JSON)")
    ap.add_argument("--init", action="store_true", help="빈 CSV 템플릿 생성")
    ap.add_argument("--force", action="store_true", help="--init 이 기존 CSV 를 덮어쓴다")
    ap.add_argument("--verify", action="store_true", help="빌드 후 전 코드 복호 왕복 검증")
    ap.add_argument("--flag", metavar="이름", help="플래그 해시 키 출력(GDScript 상수용)")
    ap.add_argument("--csv", metavar="경로", help="읽을 CSV(기본 docs/input/sheets/card_codes.csv)")
    ap.add_argument("--out", metavar="경로", help="쓸 JSON(기본 data/card_codes.json)")
    a = ap.parse_args()
    global CSV_PATH, OUT_PATH
    if a.csv:
        CSV_PATH = Path(a.csv)
    if a.out:
        OUT_PATH = Path(a.out)
    if a.flag:
        print(flag_key(a.flag))
        return 0
    if a.init:
        return write_template(a.force)
    return build(a.verify)


if __name__ == "__main__":
    raise SystemExit(main())
