"""에셋 색인 — 원본 자산 전수 × 원작 참조(orig) × 우리 사용(ours) 대조표.

CLAUDE.md §3(HARD RULE: 원본 우선)의 집행 도구. "원본에 없는 줄 알고 직접 만들었다"를
구조적으로 막는다. 원본 트리를 **전수 열거**하고, 원작 코드(libgame.so)가 무엇을 참조했는지
**역색인**하고, 우리 구현이 그중 무엇을 **실제로 쓰는지** 대조해 갭을 숫자로 낸다.

파이프라인
  1) 전수 열거  DV2/ rglob + 확장자 화이트리스트 + **img_plist 프레임 전개**
                (UI 요소는 파일이 아니라 아틀라스 안 프레임이다 — 여기가 직접 만들기의 주범)
  2) orig 플래그  libgame.so 문자열(NUL 경계) + docs/ref/orig_code/decomp/*.c → {자산: [참조 클래스]}
                  `%d/%s` 포맷 문자열은 정규식으로 전개해 매칭
  3) ours 플래그  scripts/ scenes/ data/ 의 문자열 리터럴 → 스템 정규화 후 대조
                  (`scene/cave/bag.png` → flat `scene_cave_bag` = 우리 매니페스트 키 규약)
  3b) 변환본 사슬 우리가 원본 파일명이 아니라 **변환본 경로**를 참조하는 경우(스파인 씬)를
                  코드→.tscn→변환본→원본 3단 검증으로 잇는다. 리터럴만 보면 거짓 갭이 된다.
  4) scope=out   구현 계획 없는 기능(PvP/경매/친구/광고…)은 SCOPE_OUT으로 집계 분리(⚫)
  5) 표 출력      카테고리별 |파일|orig|ours|미사용| + **🟠 orig 있고 ours 없는 것** 하이라이트
  6) 기준선 기록  --baseline 으로 docs/asset_coverage.md에 측정치를 박고, --check로 회귀 감지

사용
  python scripts/tools/asset_index.py                  # 요약 표
  python scripts/tools/asset_index.py --gap scene/cave # 갭 목록(카테고리 접두 필터)
  python scripts/tools/asset_index.py --grep btn_star  # 키워드 조회(원본에 뭐가 있나)
  python scripts/tools/asset_index.py --why common/btn_star.png   # 원작 어느 클래스가 쓰나
  python scripts/tools/asset_index.py --baseline       # 기준선 기록(docs/asset_coverage.md)
  python scripts/tools/asset_index.py --check          # 기준선 대비 회귀 시 exit 1
  python scripts/tools/asset_index.py --json out.json  # 기계 판독 인덱스

읽기 전용: DV2/ 와 libgame.so 는 절대 수정하지 않는다.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from bisect import bisect_left
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ORIG = REPO / "DV2"            # 원본 에셋 트리
SO = REPO / "libgame.so"       # 원작 코드(네이티브 바이너리)
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"   # 디컴파일 출력(클래스 귀속용, 있으면 사용)
BASELINE_DOC = REPO / "docs" / "asset_coverage.md"

# ── 1) 전수 열거 설정 ────────────────────────────────────────────────────────
# 원본 확장자 화이트리스트. (Godot 파생물 .import/.tres/.tscn/.uid 는 원본이 아니다)
EXT_CAT = {
    ".spine_json": "spine",
    ".mp3": "sound",
    ".jpg": "image",
    ".png": "image",       # 아틀라스 시트(plist와 동명)는 열거에서 제외 — 아래에서 걸러냄
    ".fnt": "font",
    ".fsh": "shader",
    ".vsh": "shader",
    ".h": "shader",        # DV2/shader/*.h = 셰이더 소스
    ".xml": "string",
    ".txt": "string",
}
# 열거에서 통째로 빼는 경로 조각
SKIP_PARTS = {".git", "__pycache__", "converted"}   # DV2/converted = 우리 변환 산출물(파생)

ASSET_EXTS = ("png", "jpg", "img_plist", "spine_json", "plist", "mp3", "fnt", "ccz", "xml", "fsh")

# ── 4) scope=out: 구현 계획이 없는 기능 경로 (CLAUDE.md §5 삭제 대상) ──────────
# 보수적으로만 적는다 — 잘못 빼면 진짜 갭이 숨는다. 애매하면 넣지 말 것.
SCOPE_OUT: list[tuple[str, str]] = [
    ("scene/colosseum", "PvP 콜로세움 — 삭제"),
    ("scene/colosseumrank", "PvP 랭킹 — 삭제"),
    ("scene/auction", "경매/거래 — 삭제"),
    ("scene/social", "친구 — 삭제"),
    ("scene/guild", "길드(온라인) — 삭제"),
    ("scene/mailbox", "우편(서버) — 삭제"),
    ("card", "PVP 카드 이미지 — 사용 금지"),
    ("icon_pvp", "PvP 아이콘 — 삭제"),
    ("event", "서버 이벤트 — 삭제"),
    ("banner", "광고 배너 — 삭제"),
    ("banner_guide", "광고 배너 — 삭제"),
    ("free_ad", "광고 — 삭제"),
    ("freecharge", "무료충전소(과금) — 삭제"),
    ("onAir", "온에어(서버 방송) — 삭제"),
    ("updaters", "업데이터(네트워크) — 삭제"),
]

# ── 3) ours 코퍼스 ───────────────────────────────────────────────────────────
OURS_GLOBS = [
    ("scripts", "*.gd"),
    ("scripts", "*.py"),
    ("scenes", "*.tscn"),
    ("data", "*.json"),
]
# data/recipes/*.json 은 "원작에서 추출한 것"이지 우리 구현이 아니다.
# 단, 우리 gd가 실제로 로드하는 레시피만 ours 코퍼스에 포함한다(아래 build_ours에서 판정).
RECIPE_DIR = REPO / "data" / "recipes"

FMT = re.compile(r"%[0-9.#+-]*(?:ld|lu|[dsu])")
STR_LIT = re.compile(r'"([^"\n\\]{2,160})"')


def fmt_to_regex(s: str, open_str: bool = True) -> re.Pattern | None:
    """`dragon/dragon_%d/box_adult.png` → 정규식. 포맷이 없거나 너무 헐거우면 None.

    ⚠️ 헐거운 패턴 차단이 이 함수의 핵심이다. 두 가지 안전장치:
      · `%s`는 **한 세그먼트**만 먹는다(`_`/`/` 불포함). 안 그러면 `scene_cave_%s` 하나가
        cave 아틀라스 전체를 삼켜 "다 쓰고 있다"는 거짓 결과가 된다.
      · `open_str=False`(ours 측)면 뒤가 열린 `%s` 패턴을 거부한다. 우리 코드의
        `"scene_cave_%s" % it["bg"]` 는 대입될 이름이 같은 파일에 리터럴로 또 있으므로
        패턴 없이도 잡힌다 — 열어두면 손해(거짓 커버리지)만 본다.
        숫자 계열 `%d`(skill_%d, dragon_%d)는 자산 패밀리 전체 참조라 열어둔다.

    비대칭 설계: orig은 관대하게(=원작이 쓴 것을 넓게 인정), ours는 엄격하게(=우리가 쓴다고
    쉽게 인정하지 않게). 두 오차 모두 **갭이 늘어나는 쪽**으로 작용한다 — 거짓 커버리지로
    직접 만든 자산을 놓치는 것보다, 거짓 갭을 한 번 확인하는 편이 싸다.
    """
    if not FMT.search(s):
        return None
    out, last, lits, has_str = [], 0, [], False
    for m in FMT.finditer(s):
        lits.append(s[last:m.start()])
        out.append(re.escape(lits[-1]))
        numeric = m.group().endswith(("d", "u"))
        has_str |= not numeric
        out.append(r"\d+" if numeric else r"[A-Za-z0-9]+")
        last = m.end()
    lits.append(s[last:])
    out.append(re.escape(lits[-1]))

    meat = [re.sub(r"[^A-Za-z0-9]", "", x) for x in lits]
    if sum(len(x) for x in meat) < 4 or max((len(x) for x in meat), default=0) < 4:
        return None
    if has_str and not open_str:
        tail = re.sub(r"\.(png|jpg|img_plist|spine_json|plist|mp3|fnt|tres|ccz)$", "", lits[-1])
        if len(re.sub(r"[^A-Za-z0-9]", "", tail)) < 3:
            return None      # 뒤가 열린 %s — 아틀라스를 통째로 삼킨다
    try:
        return re.compile("".join(out) + r"\Z")
    except re.error:
        return None


def flatten(canon: str) -> str:
    """`scene/cave/bag.png` → `scene_cave_bag` (우리 _manifest.json 키 규약).

    ⚠️ 하이픈은 보존한다. cocos_export가 `att_icon-hd`를 그대로 두므로 `_`로 바꾸면
    실제로 쓰는 자산이 미사용으로 잡힌다(거짓 갭).
    """
    stem = canon.rsplit(".", 1)[0] if "." in canon.rsplit("/", 1)[-1] else canon
    return stem.replace("/", "_")


@dataclass
class Asset:
    canon: str          # 표준 식별자 (원작 코드가 쓰는 형태)
    cat: str            # 카테고리 (dragon, scene/cave, monster, sound, ...)
    kind: str           # atlas_frame | spine | image | sound | particle | font | shader | string
    src: str            # 실제 파일 경로 (아틀라스 프레임이면 그 아틀라스)
    orig: list[str] = field(default_factory=list)   # 원작 참조처
    ours: list[str] = field(default_factory=list)   # 우리 참조처
    scope_out: str = ""                              # 사유(있으면 ⚫)

    @property
    def keys(self) -> tuple[str, ...]:
        flat = flatten(self.canon)
        base_stem = self.canon.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        ks = {self.canon, flat, base_stem, flat.replace("-", "_")}
        # 아틀라스 프레임의 basename은 다른 아틀라스/데이터 키와 충돌한다
        # (`item/item_small/ele_fire.png` vs items.json의 아이템 키 `ele_fire`) → 일반 토큰 매칭에서 제외.
        # 대신 **경로 리터럴에서 뽑힌 스템**과만 대조한다(`path_key` 참조).
        if self.kind == "atlas_frame":
            ks.discard(base_stem)
        return tuple(k for k in ks if len(k) >= 3)

    @property
    def path_key(self) -> str:
        """경로 리터럴로 참조될 때의 스템. 회전 아틀라스를 표준 PNG로 재추출해
        `battle_extra/hp_bar10.png`처럼 직접 로드하는 케이스를 잡는다."""
        return self.canon.rsplit("/", 1)[-1].rsplit(".", 1)[0]


def category_of(canon: str, kind: str) -> str:
    parts = canon.split("/")
    if kind in ("sound", "particle", "shader", "string", "font"):
        return kind
    if parts[0] == "scene" and len(parts) > 2:
        return f"scene/{parts[1]}"
    if parts[0] == "scene":
        return f"scene/{parts[1].rsplit('.', 1)[0]}"
    if len(parts) > 1:
        return parts[0]
    return parts[0].rsplit(".", 1)[0]


# scope=out 경로에 있지만 **구현 대상 씬이 실제로 쓰는** 예외.
# 잘못 ⚫ 처리하면 진짜 갭이 숨는다 — 근거(원작 코드 위치)를 반드시 함께 적는다.
SCOPE_OUT_EXCEPT: dict[str, str] = {
    # 모험 전투 EXP 패널 배경. 콜로세움 폴더에 있지만 AdventureScene::setExpAddIcon 이 쓴다.
    #   docs/ref/orig_code/decomp/AdventureScene.c:46633 CCScale9Sprite("scene/colosseum/week_time_bg.png")
    "scene/colosseum/week_time_bg.png": "AdventureScene::setExpAddIcon 사용",
}


# 다국어 로케일 변형 — 원작은 KR/EN/JP(+CN/TW) 병행 출시였고 **우리는 한국어판만 구현**한다.
# 따라서 비-KR 로케일 자산은 영원히 쓰지 않는다(구조적 갭) → 집계에서 분리한다.
# ⚠️ 잘못 빼면 진짜 갭이 숨으므로(§4) **한국어 형제가 실재할 때만** 제외한다.
#    `block_en.png`는 `block_kr.png`가 같이 있어야 로케일 변형임이 증명된다.
#    형제가 없으면(예: `card/card_name/en/`) 판단을 보류하고 그대로 집계에 남긴다.
LOCALE_SUFFIX = re.compile(r"_(en|jp|cn|tw|th)(\.[A-Za-z_]+)$", re.I)
LOCALE_WHY = "다국어(비한국어) — 한국어판만 구현"


def locale_scope_out(canon: str, all_canons: set[str]) -> str:
    m = LOCALE_SUFFIX.search(canon)
    if not m:
        return ""
    for kr in (canon[:m.start()] + "_kr" + m.group(2), canon[:m.start()] + "_KR" + m.group(2)):
        if kr in all_canons:
            return LOCALE_WHY
    return ""


def scope_reason(canon: str) -> str:
    """경로 어디에 있든 세그먼트 단위로 매칭 (`particle/scene/colosseum/…` 도 잡아야 한다)."""
    if canon in SCOPE_OUT_EXCEPT:
        return ""
    segs = [s.rsplit(".", 1)[0] for s in canon.split("/")]
    for prefix, why in SCOPE_OUT:
        pp = prefix.split("/")
        for i in range(len(segs) - len(pp) + 1):
            if segs[i:i + len(pp)] != pp:
                continue
            # SCOPE_OUT 항목은 전부 **디렉터리** 이름이다(card/, scene/colosseum/, event/ …).
            # 매칭이 마지막 조각(=파일명)에서 끝나면 동명이인 파일이다 — 제외하지 않는다.
            #   예) `scene/cave/card.png`(동굴 카드 메뉴 아이콘)는 PVP `card/` 폴더와 무관.
            if i + len(pp) >= len(segs):
                continue
            return why
    return ""


# ── 1) 전수 열거 ─────────────────────────────────────────────────────────────
def enumerate_assets() -> dict[str, Asset]:
    if not ORIG.is_dir():
        sys.exit(f"[에러] 원본 에셋 트리 없음: {ORIG}  (DV2 에셋 레포를 여기에 두세요)")
    assets: dict[str, Asset] = {}
    plist_stems: set[Path] = set()

    def add(canon: str, kind: str, src: Path):
        if canon in assets:
            return
        a = Asset(canon=canon, cat=category_of(canon, kind), kind=kind,
                  src=str(src.relative_to(REPO)).replace("\\", "/"))
        a.scope_out = scope_reason(canon)
        assets[canon] = a

    files = [p for p in ORIG.rglob("*")
             if p.is_file() and not (SKIP_PARTS & set(p.parts))]

    # (a) 아틀라스: XML plist는 프레임 전개, libgdx 텍스트(.img_plist)는 spine 부속이므로 스킵
    for p in (f for f in files if f.suffix == ".img_plist"):
        plist_stems.add(p.with_suffix(""))
        try:
            d = plistlib.loads(p.read_bytes())
        except Exception:
            continue    # libgdx atlas(spine 부속) — 리전은 스켈레톤 내부이므로 단위로 세지 않음
        for frame in d.get("frames", {}):
            add(frame.replace("\\", "/"), "atlas_frame", p)

    # (b) 개별 파일
    for p in files:
        rel = p.relative_to(ORIG)
        ext = p.suffix.lower()
        if ext == ".img_plist":
            continue
        if ext == ".png" and p.with_suffix("") in plist_stems:
            continue            # 아틀라스 시트 자체 = 프레임의 컨테이너
        if ext == ".plist":
            if rel.parts[0] == "particle":
                add("/".join(rel.parts), "particle", p)
            continue
        kind = EXT_CAT.get(ext)
        if not kind:
            continue
        if kind == "image" and rel.parts[0] == "480" and rel.parts[1] == "font":
            continue            # 폰트 시트 = .fnt에 종속
        # 480/ 접두는 해상도 폴더일 뿐 — 원작 코드 참조형과 맞추려 벗긴다
        canon = "/".join(rel.parts[1:] if rel.parts[0] == "480" else rel.parts)
        add(canon, kind, p)

    # 로케일 변형은 형제(KR) 존재 여부로 판정하므로 **전수 열거가 끝난 뒤** 후처리한다.
    all_canons = set(assets)
    for a in assets.values():
        if not a.scope_out:
            a.scope_out = locale_scope_out(a.canon, all_canons)

    return assets


# ── 2) orig 역색인 ───────────────────────────────────────────────────────────
PATHISH = re.compile(r"[A-Za-z0-9_%./+-]{4,120}")


def _asset_like(s: str) -> bool:
    return bool(PATHISH.fullmatch(s)) and s.rsplit(".", 1)[-1] in ASSET_EXTS


def _prefix_like(s: str) -> bool:
    """확장자 없는 경로 조각(런타임 조립용). 원작은 `"title/%d_" + lang + ".png"` 처럼 쓴다.

    이걸 안 잡으면 title 298프레임이 통째로 "원작도 안 쓴다"로 잘못 집계된다.
    과잉매칭 방지: `common/` 처럼 아틀라스 전체를 삼키는 짧은 접두는 거부.
    """
    if not PATHISH.fullmatch(s) or "/" not in s or s.rsplit(".", 1)[-1] in ASSET_EXTS:
        return False
    meat = len(re.sub(r"[^A-Za-z0-9]", "", s))
    return meat >= (8 if s.endswith("/") else 6)


def build_orig_index(canons: list[str]) -> tuple[dict[str, list[str]], list[tuple[re.Pattern, str]]]:
    """원작 코드의 자산 참조 → {문자열: [참조처]} + 포맷패턴 목록."""
    refs: dict[str, list[str]] = defaultdict(list)
    prefixes: dict[str, list[str]] = defaultdict(list)

    if SO.exists():
        blob = SO.read_bytes()
        for chunk in blob.split(b"\x00"):        # C 문자열 경계
            if not (3 < len(chunk) < 160):
                continue
            try:
                s = chunk.decode("ascii")
            except UnicodeDecodeError:
                continue
            if _asset_like(s):
                refs[s].append("libgame.so")
            elif _prefix_like(s):
                prefixes[s].append("libgame.so")
    else:
        print(f"[경고] {SO.name} 없음 — orig 플래그는 docs/ref/orig_code/decomp 만으로 산출됩니다.", file=sys.stderr)

    # 클래스 귀속: 디컴파일 출력이 있으면 어느 클래스가 쓰는지까지
    if DECOMP.is_dir():
        lit = re.compile(r'"([A-Za-z0-9_%./+-]{3,120})"')
        for c in DECOMP.glob("*.c"):
            seen = set()
            for m in lit.finditer(c.read_text(encoding="utf-8", errors="ignore")):
                s = m.group(1)
                if s in seen:
                    continue
                seen.add(s)
                if _asset_like(s):
                    refs[s].append(c.stem)
                elif _prefix_like(s):
                    prefixes[s].append(c.stem)

    # 접두 참조 전개: 열거된 자산 중 이 접두로 시작하는 것에 귀속시킨다(열거 결과가 오라클).
    ordered = sorted(canons)
    for s, who in prefixes.items():
        src = f"prefix:{s}({who[0]})"
        if FMT.search(s):
            rx = fmt_to_regex(s + "\x00", open_str=True)      # 접두 → 앞부분만 매칭
            rx = re.compile(rx.pattern.replace(re.escape("\x00") + r"\Z", "")) if rx else None
            if rx is None:
                continue
            for canon in canons:
                if rx.match(canon):
                    refs.setdefault(canon, []).append(src)
        else:
            i = bisect_left(ordered, s)
            while i < len(ordered) and ordered[i].startswith(s):
                refs.setdefault(ordered[i], []).append(src)
                i += 1

    pats = []
    for s in refs:
        r = fmt_to_regex(s, open_str=True)     # orig: 관대
        if r:
            pats.append((r, s))
    return refs, pats


# ── 3) ours 색인 ─────────────────────────────────────────────────────────────
IDENT = re.compile(r"[A-Za-z0-9_]{2,40}\Z")


def _capture_regex(s: str) -> re.Pattern | None:
    """`scene_cave_%s` → `scene_cave_([A-Za-z0-9_]+)` (대입 세그먼트를 캡처).

    캡처값이 우리 코퍼스의 리터럴인지 따로 검증하므로 여기서는 `_`를 넘어 먹어도 안전하다
    (`bag_bg` 같은 이름을 놓치지 않는다).
    """
    out, last, meat = [], 0, 0
    for m in FMT.finditer(s):
        lit = s[last:m.start()]
        meat += len(re.sub(r"[^A-Za-z0-9]", "", lit))
        out.append(re.escape(lit))
        # 숫자는 비캡처(검증 불필요), 문자열 대입만 캡처해 리터럴 존재를 검증한다
        out.append(r"\d+" if m.group().endswith(("d", "u")) else r"([A-Za-z0-9_]+)")
        last = m.end()
    lit = s[last:]
    meat += len(re.sub(r"[^A-Za-z0-9]", "", lit))
    out.append(re.escape(lit))
    if meat < 4:
        return None
    try:
        return re.compile("".join(out))
    except re.error:
        return None


def build_ours_index(valid_keys: set[str]) -> tuple[dict, list, dict, list, set]:
    refs: dict[str, list[str]] = defaultdict(list)
    stem_refs: dict[str, list[str]] = defaultdict(list)   # 경로 리터럴에서 뽑힌 basename 스템만
    corpus: list[Path] = []
    for sub, pat in OURS_GLOBS:
        d = REPO / sub
        if d.is_dir():
            corpus += [p for p in d.rglob(pat) if not (SKIP_PARTS & set(p.parts))]
    corpus = [p for p in corpus if RECIPE_DIR not in p.parents]

    # 우리 gd가 실제로 로드하는 레시피만 ours로 인정
    gd_text = "\n".join(p.read_text(encoding="utf-8", errors="ignore")
                        for p in corpus if p.suffix == ".gd")
    # ⚠️ 클래스명이 **주석에** 나오는 것만으로 인정하면 안 된다(거짓 커버리지).
    # 실제 로드 경로(`recipes/X.json`)가 코드에 있을 때만 ours 코퍼스에 넣는다.
    if RECIPE_DIR.is_dir():
        corpus += [r for r in RECIPE_DIR.glob("*.json") if f"recipes/{r.name}" in gd_text]

    for p in corpus:
        where = str(p.relative_to(REPO)).replace("\\", "/")
        txt = p.read_text(encoding="utf-8", errors="ignore")
        for m in STR_LIT.finditer(txt):
            tok = m.group(1)
            refs[tok].append(where)
            # 경로 리터럴이면 basename 스템도 토큰으로 (res://.../scene_cave_bag.tres)
            if "/" in tok or "." in tok:
                base = tok.rsplit("/", 1)[-1]
                stem = base.rsplit(".", 1)[0]
                if len(stem) >= 3:
                    refs[stem].append(where)
                    stem_refs[stem].append(where)

    # `"scene_cave_%s" % it["bg"]` — GDScript의 실제 의미대로 처리한다: **대입될 이름이 우리
    # 코퍼스에 리터럴로 존재하고**(`bag_bg`) **그 조합이 실존 자산일 때만**(`scene_cave_bag_bg`)
    # 사용으로 인정. 와일드카드 정규식과 달리 아틀라스를 통째로 삼키지 않는다.
    idents = {t for t in refs if IDENT.fullmatch(t)}
    caps: list[tuple[re.Pattern, str]] = []
    pats: list[tuple[re.Pattern, str]] = []
    for s in list(refs):
        if "%" not in s:
            continue
        if "%s" in s:
            r = _capture_regex(s)
            if r:
                caps.append((r, s))
        else:
            r = fmt_to_regex(s, open_str=False)   # 숫자 패밀리(skill_%d, cavebg%d)
            if r:
                pats.append((r, s))
    for key in valid_keys:
        for r, s in caps:
            m = r.fullmatch(key)
            if m and all(g in idents for g in m.groups()):
                refs[key].append(refs[s][0])
                break
    return refs, pats, stem_refs, caps, idents


# ── 3b) 변환본 사슬 (derived) ────────────────────────────────────────────────
# 우리 코드가 **원본 파일명이 아니라 변환본 경로**를 참조하는 경우가 있다.
#   `battle.gd:275` → `res://scenes/monsters/monster_1.tscn` ← `monster/1/1_monster_spine.spine_json`
# 파일명이 달라 리터럴 대조로는 "안 쓴다"가 되고, 실측에서 **거짓 갭**이 된다(몬스터 스파인 172종).
#
# 완화하되 **거짓 배정(쓰지도 않는 것을 사용으로 계상)은 만들지 않는다.** 3단 사슬이 모두
# 확인될 때만 인정하고, 하나라도 끊기면 아무것도 인정하지 않는다:
#   (1) 우리 코퍼스가 그 .tscn 경로를 참조한다 — 기존 ours 규칙(리터럴·`%d`패밀리·`%s`캡처검증) 재사용
#   (2) 그 .tscn 이 `res://assets/converted/<dir>/` 를 **실제로 참조한다** — 파일 내용으로 검증
#       (씬 파일만 있고 텍스처 링크가 없는 깨진 산출물을 사용으로 세지 않기 위한 고리다)
#   (3) `<dir>/<stage>.json` 의 `{id, stage}` 를 **변환기 자신의 경로 규약**(spine_export.py)으로
#       되돌린 원본이 열거된 자산에 실재하고, 그 해가 **유일**하다
#
# 인정 범위는 **그 스켈레톤 1개**뿐이다. 같은 폴더의 다른 프레임(`att_effect`·`hit` 등)은
# 코드가 따로 참조해야 사용으로 잡힌다 — 폴더 단위 일괄 인정은 하지 않는다.
CONVERTED_ROOT = REPO / "assets" / "converted"
CONV_REF = re.compile(r"res://assets/converted/([A-Za-z0-9_.-]+)/")
DRAGON_STAGES = ("baby", "child", "adult")


def _spine_source_canon(meta_id: str, stage: str, spine_by_stem: dict[str, list[str]]) -> str | None:
    """변환본 메타(id/stage) → 원본 canon. 규약 출처는 scripts/tools/spine_export.py."""
    # 변환기가 경로를 고정하는 두 계열은 규약 그대로 되돌린다.
    if stage == "monster":                                   # spine_export.py:268-273
        cand = f"monster/{meta_id}/{meta_id}_monster_spine.spine_json"
        return cand if cand in spine_by_stem.get("__all__", ()) else None
    if stage in DRAGON_STAGES:                               # spine_export.py:59-62
        cand = f"dragon/dragon_{meta_id}_{stage}_spine.spine_json"
        return cand if cand in spine_by_stem.get("__all__", ()) else None
    # 그 외(scene/npc/fx…)는 변환기가 **원본 디렉터리를 기록하지 않는다**(export_scene).
    # 파일명으로 역탐색하되, 후보가 정확히 하나일 때만 인정한다.
    # (DV2 전체에서 .spine_json basename 중복이 없음을 확인했으나, 규약이 아니라 관찰이므로
    #  유일성은 여기서 매번 강제한다.)
    hits: set[str] = set()
    for stem in (f"{meta_id}_{stage}", f"{meta_id}_{stage}_spine", meta_id, f"{meta_id}_spine"):
        hits.update(spine_by_stem.get(stem, ()))
    return next(iter(hits)) if len(hits) == 1 else None


def build_derived_index(assets: dict[str, Asset], refs: dict, pats: list,
                        caps: list, idents: set) -> dict[str, list[str]]:
    scenes_dir = REPO / "scenes"
    if not scenes_dir.is_dir() or not CONVERTED_ROOT.is_dir():
        return {}

    # 스파인 원본 색인: basename 스템 → canon (+ 전체 canon 집합)
    spine_by_stem: dict[str, list[str]] = defaultdict(list)
    all_spines = {a.canon for a in assets.values() if a.kind == "spine"}
    spine_by_stem["__all__"] = list(all_spines)
    for c in all_spines:
        spine_by_stem[c.rsplit("/", 1)[-1].rsplit(".", 1)[0]].append(c)

    # 변환본 디렉터리 메타 캐시: dir → (id, stage)
    meta_cache: dict[str, tuple[str, str] | None] = {}

    def meta_of(d: str) -> tuple[str, str] | None:
        if d not in meta_cache:
            meta_cache[d] = None
            p = CONVERTED_ROOT / d
            if p.is_dir():
                for j in sorted(p.glob("*.json")):
                    if j.name == "_manifest.json":
                        continue
                    try:
                        m = json.loads(j.read_text(encoding="utf-8"))
                    except Exception:
                        continue
                    if m.get("id") is not None and m.get("stage"):
                        meta_cache[d] = (str(m["id"]), str(m["stage"]))
                        break
        return meta_cache[d]

    derived: dict[str, list[str]] = defaultdict(list)
    for tscn in scenes_dir.rglob("*.tscn"):
        res_path = "res://" + str(tscn.relative_to(REPO)).replace("\\", "/")
        # (1) 우리 코드가 이 씬을 참조하는가
        wheres: list[str] = list(refs.get(res_path, ()))
        for r, s in caps:
            m = r.fullmatch(res_path)
            if m and all(g in idents for g in m.groups()):
                wheres += refs[s]
        for r, s in pats:
            if r.fullmatch(res_path):
                wheres += refs[s]
        if not wheres:
            continue
        # 귀속처는 **게임 코드 우선**으로 적는다 — 검증/변환 도구만 참조하는 경우
        # (`scripts/tools/*`) 를 게임이 쓰는 것처럼 보이게 하지 않기 위해서다.
        where = sorted(set(wheres), key=lambda w: (w.startswith("scripts/tools/"), w))[0]
        # (2) 그 씬이 변환본을 실제로 참조하는가
        txt = tscn.read_text(encoding="utf-8", errors="ignore")
        for d in sorted(set(CONV_REF.findall(txt))):
            # (3) 변환기 규약으로 원본을 되돌릴 수 있는가
            m = meta_of(d)
            if not m:
                continue
            canon = _spine_source_canon(m[0], m[1], spine_by_stem)
            if canon:
                derived[canon].append(f"{where}→{res_path.removeprefix('res://')}")
    return derived


def annotate(assets: dict[str, Asset]) -> None:
    orig_refs, orig_pats = build_orig_index(list(assets))
    valid: set[str] = set()
    for a in assets.values():
        valid.update(a.keys)
    ours_refs, ours_pats, ours_stems, ours_caps, ours_idents = build_ours_index(valid)
    derived = build_derived_index(assets, ours_refs, ours_pats, ours_caps, ours_idents)
    for a in assets.values():
        ks = a.keys
        for k in ks:
            if k in orig_refs:
                a.orig += sorted(set(orig_refs[k]))[:6]
            if k in ours_refs:
                a.ours += sorted(set(ours_refs[k]))[:6]
        if a.kind == "atlas_frame" and a.path_key in ours_stems:
            a.ours += sorted(set(ours_stems[a.path_key]))[:6]
        if not a.orig:
            for r, s in orig_pats:
                if any(r.match(k) for k in ks):
                    a.orig.append(f"pattern:{s}")
                    break
        if not a.ours:
            for r, s in ours_pats:
                if any(r.match(k) for k in ks):
                    a.ours.append(f"pattern:{s}")
                    break
        if not a.ours and a.canon in derived:
            a.ours += sorted(set(derived[a.canon]))[:6]


# ── 5) 표 출력 ───────────────────────────────────────────────────────────────
def summarize(assets: dict[str, Asset]) -> tuple[list[tuple], dict]:
    tot, orig, ours, gap = Counter(), Counter(), Counter(), Counter()
    out_n = Counter()
    for a in assets.values():
        if a.scope_out:
            out_n[a.cat] += 1
            continue
        tot[a.cat] += 1
        if a.orig:
            orig[a.cat] += 1
        if a.ours:
            ours[a.cat] += 1
        if a.orig and not a.ours:
            gap[a.cat] += 1
    rows = []
    for cat in sorted(tot, key=lambda c: (-gap[c], -tot[c], c)):
        rows.append((cat, tot[cat], orig[cat], ours[cat], tot[cat] - ours[cat], gap[cat]))
    why = Counter(a.scope_out for a in assets.values() if a.scope_out)
    totals = {
        "files": sum(tot.values()), "orig": sum(orig.values()), "ours": sum(ours.values()),
        "unused": sum(tot.values()) - sum(ours.values()), "gap": sum(gap.values()),
        "scope_out": sum(out_n.values()), "scope_why": why.most_common(),
    }
    return rows, totals


def print_table(rows, totals) -> None:
    print(f"{'카테고리':<22}{'파일':>7}{'orig':>7}{'ours':>7}{'미사용':>8}{'🟠갭':>7}")
    print("-" * 60)
    for cat, t, o, u, un, g in rows:
        mark = " 🟠" if g else ""
        print(f"{cat:<22}{t:>7}{o:>7}{u:>7}{un:>8}{g:>7}{mark}")
    print("-" * 60)
    print(f"{'합계':<22}{totals['files']:>7}{totals['orig']:>7}{totals['ours']:>7}"
          f"{totals['unused']:>8}{totals['gap']:>7}")
    print(f"\n⚫ scope=out(구현 계획 없음): {totals['scope_out']}개")
    for why, n in totals["scope_why"]:
        print(f"     {n:>5}  {why}")
    print(f"🟠 갭 = 원작이 쓰는데 우리는 안 쓰는 자산: {totals['gap']}개 "
          f"→ python scripts/tools/asset_index.py --gap <카테고리>")


# ── 6) 기준선 ────────────────────────────────────────────────────────────────
BASE_HDR = "| 카테고리 | 파일 | orig | ours | 미사용 | 갭 |"


def write_baseline(rows, totals) -> None:
    import subprocess
    from datetime import date
    try:
        rev = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO,
                             capture_output=True, text=True).stdout.strip()
    except Exception:
        rev = "?"
    L = [
        "# 에셋 커버리지 기준선 (Asset Coverage Baseline)",
        "",
        "> `python scripts/tools/asset_index.py --baseline` 이 갱신한다. **손으로 고치지 말 것.**",
        "> 회귀 감지: `python scripts/tools/asset_index.py --check` (커버리지가 떨어지면 exit 1).",
        f"> 최초 측정 기준: {date.today().isoformat()} / rev {rev}",
        "",
        "- **파일** = 원본 자산 수(아틀라스 프레임 전개 포함, scope=out 제외)",
        "- **orig** = 원작 코드(libgame.so/_decomp)가 참조하는 것",
        "- **ours** = 우리 구현(scripts/scenes/data)이 참조하는 것",
        "- **갭** = orig ∧ ¬ours → 🟠직접 만들었거나 빠뜨렸을 후보",
        "",
        "## 읽는 법 (중요)",
        "",
        "**갭 총계는 '버그 수'가 아니다.** 대부분은 아직 이식하지 않은 씬의 자산(⚪미구현)이다.",
        "위험한 건 **이미 구현했다고 표시된 기능의 갭** — 원본이 있는데 직접 만들었다는 뜻이다(🟠).",
        "그래서 총계보다 **카테고리별 추이**가 의미 있다: 어떤 기능을 구현했는데 그 카테고리 ours가",
        "안 늘었다면, 원본을 안 쓰고 만든 것이다.",
        "",
        "판정 한계(의도적으로 보수적 — 거짓 커버리지보다 거짓 갭이 싸다):",
        "- ours는 **문자열 리터럴** 기반이라 완전 런타임 조립 참조는 놓칠 수 있다(→ 거짓 갭).",
        "  단 **변환본 경로로 참조하는 스파인 씬**은 코드→.tscn→변환본→원본 3단 검증으로 잇는다",
        "  (`build_derived_index`). 씬 파일만 있고 텍스처 링크가 없는 깨진 산출물은 인정하지 않는다.",
        "- orig은 접두/포맷 패턴까지 넓게 인정한다(→ 원작이 실제로 안 쓴 것도 일부 orig로 잡힘).",
        "- 애매하면 `--why <자산>`으로 근거를 직접 확인할 것.",
        "",
        BASE_HDR, "|---|---:|---:|---:|---:|---:|",
    ]
    for cat, t, o, u, un, g in rows:
        L.append(f"| {cat} | {t} | {o} | {u} | {un} | {g} |")
    L.append(f"| **합계** | **{totals['files']}** | **{totals['orig']}** | **{totals['ours']}** "
             f"| **{totals['unused']}** | **{totals['gap']}** |")
    L += ["", f"## scope=out (⚫ 구현 계획 없음) — {totals['scope_out']}개", "",
          "집계에서 제외. 사유별 내역(`asset_index.py` SCOPE_OUT 표가 근거):", ""]
    L += [f"- {n}개 — {why}" for why, n in totals["scope_why"]]
    L.append("")
    BASELINE_DOC.write_text("\n".join(L), encoding="utf-8")
    print(f"기준선 기록 → {BASELINE_DOC.relative_to(REPO)}")


def read_baseline() -> dict[str, tuple[int, int, int, int, int]]:
    if not BASELINE_DOC.exists():
        sys.exit("[에러] 기준선 없음 — 먼저 --baseline 실행")
    out = {}
    for line in BASELINE_DOC.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| ") or line.startswith(("| 카테고리", "|---")):
            continue
        c = [x.strip().strip("*") for x in line.strip("|").split("|")]
        if len(c) != 6 or not c[1].isdigit():
            continue
        out[c[0]] = tuple(int(x) for x in c[1:])
    return out


def check(rows, totals) -> int:
    base = read_baseline()
    cur = {r[0]: r[1:] for r in rows}
    bad = []
    for cat, b in base.items():
        if cat == "합계":
            continue
        c = cur.get(cat)
        if c is None:
            bad.append(f"  {cat}: 카테고리가 사라짐(기준선 {b[0]}개)")
            continue
        if c[2] < b[2]:
            bad.append(f"  {cat}: ours {b[2]} → {c[2]} (사용 자산이 줄었다)")
        if c[4] > b[4]:
            bad.append(f"  {cat}: 갭 {b[4]} → {c[4]} (직접 만들었거나 빠뜨린 자산이 늘었다)")
    if bad:
        print("🔴 커버리지 회귀:\n" + "\n".join(bad))
        return 1
    print(f"✅ 회귀 없음 (ours {totals['ours']}, 갭 {totals['gap']})")
    return 0


# ── CLI ──────────────────────────────────────────────────────────────────────
def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="원본 자산 색인/대조표")
    ap.add_argument("--gap", nargs="?", const="", metavar="CAT",
                    help="orig 있고 ours 없는 자산 목록(카테고리 접두 필터)")
    ap.add_argument("--grep", metavar="KW", help="키워드로 원본 자산 조회")
    ap.add_argument("--why", metavar="ASSET", help="이 자산을 원작 어느 클래스가 쓰는지")
    ap.add_argument("--unused", action="store_true", help="--grep/--gap 결과 중 ours 없는 것만")
    ap.add_argument("--baseline", action="store_true", help="기준선 기록")
    ap.add_argument("--check", action="store_true", help="기준선 대비 회귀 검사")
    ap.add_argument("--json", metavar="OUT", help="전체 인덱스를 JSON으로 저장")
    ap.add_argument("--limit", type=int, default=60)
    args = ap.parse_args()

    assets = enumerate_assets()
    annotate(assets)
    rows, totals = summarize(assets)

    if args.grep:
        kw = args.grep.lower()
        hits = [a for a in assets.values() if kw in a.canon.lower() or kw in flatten(a.canon).lower()]
        if args.unused:
            hits = [a for a in hits if not a.ours]
        print(f"'{args.grep}' → {len(hits)}건" + (" (ours 없는 것만)" if args.unused else ""))
        for a in sorted(hits, key=lambda x: x.canon)[:args.limit]:
            f = "⚫" if a.scope_out else ("✔" if a.ours else ("🟠" if a.orig else "✗"))
            print(f"  {f} {a.canon:<52} [{a.kind}] orig={a.orig[0] if a.orig else '-':<22} "
                  f"ours={a.ours[0] if a.ours else '-'}")
        if len(hits) > args.limit:
            print(f"  … +{len(hits) - args.limit}건 (--limit)")
        return 0

    if args.why:
        a = assets.get(args.why) or next(
            (x for x in assets.values() if flatten(x.canon) == args.why), None)
        if not a:
            print(f"원본에 없음: {args.why}  (--grep 로 이름 확인)")
            return 1
        print(f"{a.canon}\n  종류 : {a.kind}\n  카테고리: {a.cat}\n  파일 : {a.src}")
        print(f"  orig : {', '.join(a.orig) or '(원작 코드에서 참조 안 됨)'}")
        print(f"  ours : {', '.join(a.ours) or '(우리 구현에서 미사용)'}")
        if a.scope_out:
            print(f"  ⚫ scope=out: {a.scope_out}")
        return 0

    if args.gap is not None:
        sel = [a for a in assets.values()
               if a.orig and not a.ours and not a.scope_out and a.cat.startswith(args.gap)]
        print(f"🟠 갭 {len(sel)}건" + (f" (카테고리 {args.gap}*)" if args.gap else ""))
        for a in sorted(sel, key=lambda x: (x.cat, x.canon))[:args.limit]:
            src = a.orig[0]
            print(f"  {a.cat:<18} {a.canon:<52} ← {src}")
        if len(sel) > args.limit:
            print(f"  … +{len(sel) - args.limit}건 (--limit)")
        return 0

    if args.json:
        Path(args.json).write_text(json.dumps(
            {a.canon: {"cat": a.cat, "kind": a.kind, "src": a.src, "orig": a.orig,
                       "ours": a.ours, "scope_out": a.scope_out}
             for a in assets.values()}, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"인덱스 저장 → {args.json} ({len(assets)}건)")
        return 0

    print_table(rows, totals)
    if args.baseline:
        write_baseline(rows, totals)
    if args.check:
        return check(rows, totals)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
