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
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CSV_PATH = REPO / "docs/input/sheets/card_codes.csv"
OUT_PATH = REPO / "data/card_codes.json"

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


def norm_code(code: str) -> str:
    """입력 정규화 — 영숫자만 남기고 대문자로. 하이픈·공백 표기 차이를 흡수한다."""
    return re.sub(r"[^0-9A-Za-z]", "", code).upper()


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


# ── CSV ──────────────────────────────────────────────────────────────────────
TEMPLATE_ROWS = 24

TEMPLATE_NOTE = [
    "# 이 파일은 gitignore 대상입니다 — 평문 코드가 공개 레포에 올라가지 않게 합니다.",
    "# 한 코드에 보상이 여러 개면 같은 코드로 행을 늘리세요(box_loot.csv 와 같은 방식).",
    "# 보상종류: 아이템 / 골드 / 다이아 / 알 / 드래곤 / 플래그",
    "#   아이템 → 보상키 = data/items.json 키   (예: potion_hp)",
    "#   골드·다이아 → 보상키는 비우고 개수만",
    "#   알 → 보상키 = 드래곤 id (가방에 egg:<id> 로 들어갑니다)",
    "#   드래곤 → 보상키 = 드래곤 id (레벨1 개체로 지급)",
    "#   플래그 → 보상키 = 플래그 이름 (빌드에는 해시만 실립니다)",
    "# 사용제한: 1회(기본) / 무제한",
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


def parse_reward(row: dict, lineno: int) -> dict | None:
    raw_kind = row.get("보상종류", "").strip()
    if not raw_kind:
        return None
    kind = KIND_MAP.get(raw_kind)
    if kind is None:
        print(f"  ⚠️ {lineno}행: 모르는 보상종류 '{raw_kind}' — 건너뜁니다.", file=sys.stderr)
        return None
    key = row.get("보상키", "").strip()
    try:
        n = int(row.get("개수", "").strip() or 1)
    except ValueError:
        n = 1
    if kind in ("gold", "dia"):
        return {"t": kind, "n": n}
    if kind in ("egg", "dragon"):
        if not key.isdigit():
            print(f"  ⚠️ {lineno}행: {raw_kind} 는 보상키가 드래곤 id(숫자)여야 합니다 — 건너뜁니다.",
                  file=sys.stderr)
            return None
        return {"t": kind, "k": int(key), "n": n}
    if kind == "flag":
        if not key:
            print(f"  ⚠️ {lineno}행: 플래그 이름이 비었습니다 — 건너뜁니다.", file=sys.stderr)
            return None
        return {"t": "flag", "k": flag_key(key)}
    if not key:
        print(f"  ⚠️ {lineno}행: 아이템 키가 비었습니다 — 건너뜁니다.", file=sys.stderr)
        return None
    return {"t": "item", "k": key, "n": n}


def build(verify: bool) -> int:
    rows = read_rows()
    # 코드별로 묶는다(같은 코드 여러 행 = 보상 여러 개).
    grouped: dict[str, dict] = {}
    order: list[str] = []
    for i, row in enumerate(rows, start=2):
        code = norm_code(row.get("코드", ""))
        if not code:
            continue
        rew = parse_reward(row, i)
        if rew is None:
            continue
        g = grouped.setdefault(code, {"rewards": [], "msg": "", "once": True})
        if code not in order:
            order.append(code)
        g["rewards"].append(rew)
        if row.get("문구", "").strip():
            g["msg"] = row["문구"].strip()
        if row.get("사용제한", "").strip() == "무제한":
            g["once"] = False

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
