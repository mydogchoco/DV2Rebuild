"""데이터 트랙 — 나무위키 던전 PDF 텍스트 → 몬스터/스테이지 데이터.

유실된 서버 데이터(던전별 등장 몬스터·유형·속성·스탯·레벨)가 위키에 문서화돼 있다.
`docs/ref/wiki/dungeon_*.pdf`를 pymupdf로 텍스트 추출 → 라벨 블록(이름/유형/속성/스탯/스킬)을
파싱해 `data/monsters.json`(몬스터 도감) + `data/stages.json`(스테이지 로스터)로 구조화한다.

몬스터 블록 포맷(반복):
  이름 / <name>
  유형 / <form> - <size>
 [속성 / <element>]          (없으면 무속성)
  스탯 / 공격력 : A 방어력 : D 생명력 : H
 [스킬 / <skills...>]
  설명 / <desc...>

던전 구획: 본문 헤더 `N.N.N. [Lv.X ]던전이름`. 각 던전의 마지막 몬스터=보스(관례).

사용:  python scripts/tools/extract_wiki.py            # 전 지역
       python scripts/tools/extract_wiki.py yutakan    # 특정 지역만(검증)

⚠️ 위키 서술은 검증 안 됨(오탈자·페이지분할 노이즈 가능) → 결과는 사용자 검수 대상.
값 출처는 [출처: 나무위키 dungeon_N]로 monsters.json에 기록.
"""
from __future__ import annotations
import re, sys, json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WIKI = REPO / "docs" / "ref" / "wiki"
# 스크래치의 기추출 텍스트 우선(있으면 재사용), 없으면 PDF에서 추출
TXT_DIR_CANDIDATES = [
    REPO / "scratch_shots" / "wiki_txt",
    Path.home() / "AppData/Local/Temp/claude" / "C--Users-mydog-OneDrive-Desktop-DV2",
]

# dungeon_N → region id/이름 (파일 1행에서도 확인)
REGION_BY_FILE = {
    "dungeon_1": ("yutakan", "유타칸"),
    "dungeon_2": ("dwarf", "메탈타워"),
    "dungeon_3": ("elf", "엘리시움"),
    "dungeon_4": ("uno", "우노"),
    "dungeon_5": ("berna", "베르나"),
}

HEADER_RE = re.compile(r"^\s*(\d+(?:\.\d+)*)\.\s+(?:Lv\.(\d+)\s+)?(.+?)\s*$")
STAT_RE = re.compile(r"공격력\s*[:：]\s*(\d+)\s*방어력\s*[:：]\s*(\d+)\s*생명력\s*[:：]\s*(\d+)")
LABELS = {"이름", "유형", "속성", "스탯", "스킬", "설명", "등장", "등장 회차", "진행 조건", "스텟"}


def get_text(dungeon_file: str) -> str | None:
    """기추출 txt가 있으면 사용, 없으면 PDF에서 pymupdf로 추출."""
    for d in TXT_DIR_CANDIDATES:
        p = d / f"{dungeon_file}.txt"
        if p.exists():
            return p.read_text(encoding="utf-8", errors="ignore")
    pdf = WIKI / f"{dungeon_file}.pdf"
    if not pdf.exists():
        return None
    import fitz
    doc = fitz.open(pdf)
    return "\n".join(page.get_text() for page in doc)


def clean(s: str) -> str:
    return re.sub(r"\[[^\]]*\]", "", s).strip()  # 각주 [a][11] 제거


def parse_dungeon_section(lines: list[str], start: int, end: int, region: str,
                          dungeon: str, level, day_night: str) -> list[dict]:
    """한 던전 구획[start,end) 안의 몬스터 블록들을 파싱."""
    mons = []
    i = start
    while i < end:
        if lines[i].strip() == "이름":
            m = {"name": "", "form": "", "size": "", "element": "무", "att": None,
                 "def": None, "hp": None, "skills": [], "region": region,
                 "dungeon": dungeon, "level": level, "phase": day_night}
            j = i + 1
            # 이름 다음 non-empty 라인 = 이름값
            while j < end and not lines[j].strip():
                j += 1
            if j < end:
                m["name"] = clean(lines[j])
            # 다음 "이름" 또는 헤더 전까지 라벨 스캔
            k = j + 1
            while k < end:
                ln = lines[k].strip()
                if ln == "이름" or HEADER_RE.match(lines[k]):
                    break
                if ln == "유형":
                    val = _next_val(lines, k, end)
                    parts = [p.strip() for p in re.split(r"[-–]", clean(val))]
                    m["form"] = parts[0] if parts else ""
                    m["size"] = parts[1] if len(parts) > 1 else ""
                elif ln == "속성":
                    m["element"] = clean(_next_val(lines, k, end))
                elif ln in ("스탯", "스텟"):
                    val = _next_val(lines, k, end)
                    sm = STAT_RE.search(val) or STAT_RE.search(val.replace(" ", ""))
                    if sm:
                        m["att"], m["def"], m["hp"] = int(sm[1]), int(sm[2]), int(sm[3])
                elif ln == "스킬":
                    sk = clean(_next_val(lines, k, end))
                    m["skills"] = [s.strip() for s in re.split(r"[,·]", sk) if s.strip()]
                k += 1
            if m["name"] and m["att"] is not None:
                mons.append(m)
            i = j + 1
        else:
            i += 1
    if mons:
        mons[-1]["boss"] = True  # 관례: 마지막 = 보스
    return mons


def _next_val(lines, k, end) -> str:
    j = k + 1
    while j < end and not lines[j].strip():
        j += 1
    return lines[j] if j < end else ""


def parse_region(dungeon_file: str):
    text = get_text(dungeon_file)
    if text is None:
        return None, None
    region, region_kr = REGION_BY_FILE[dungeon_file]
    lines = text.splitlines()
    # 본문 헤더 위치 수집(TOC 제외: 상단 목차 블록). numbering 깊이로 구획/던전 구분.
    headers = []  # (idx, depth, level, name)
    for idx, ln in enumerate(lines):
        hm = HEADER_RE.match(ln)
        if hm and idx > 40:  # TOC 영역(상단) 건너뜀
            numbering = hm[1]
            depth = numbering.count(".") + 1  # "1.1"→2, "1.1.1"→3
            lvl = int(hm[2]) if hm[2] else None
            name = clean(hm[3])
            # 이름에 남은 "Lv.N " 접두 분리
            nm = re.match(r"Lv\.(\d+)\s+(.+)", name)
            if nm:
                lvl = lvl or int(nm[1]); name = nm[2]
            headers.append((idx, depth, lvl, name))
    all_mons, stages = [], []
    cur_phase = "day"
    for h in range(len(headers)):
        idx, depth, lvl, name = headers[h]
        nxt = headers[h + 1][0] if h + 1 < len(headers) else len(lines)
        # 낮/밤 구획명으로 phase 문맥 설정(구획 헤더 자체 범위는 다음 헤더까지라 몬스터 없음).
        # depth로 던전/구획을 가르지 않음 — 지역마다 던전 depth가 다름(유타칸=3, 메탈타워=2).
        if "밤" in name and depth <= 2:
            cur_phase = "night"
        elif "낮" in name and depth <= 2:
            cur_phase = "day"
        mons = parse_dungeon_section(lines, idx + 1, nxt, region, name, lvl, cur_phase)
        if mons:
            all_mons.extend(mons)
            stages.append({"region": region, "name": name, "level": lvl, "phase": cur_phase,
                           "monsters": [m["name"] for m in mons],
                           "boss": mons[-1]["name"]})
    return all_mons, stages


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    pos = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = pos[0] if pos else None
    files = [f for f in REGION_BY_FILE if only is None or REGION_BY_FILE[f][0] == only]
    all_mons, all_stages = [], []
    for f in files:
        mons, stages = parse_region(f)
        if mons is None:
            print(f"[skip] {f}: 텍스트 없음"); continue
        print(f"[{f}] {REGION_BY_FILE[f][1]}: 몬스터 {len(mons)}, 스테이지 {len(stages)}")
        all_mons.extend(mons); all_stages.extend(stages)
    # 요약 출력(검증용) — 파일 기록은 --write 시에만
    for s in all_stages:
        lv = f"Lv.{s['level']}" if s['level'] else "  -  "
        print(f"  {s['region']:8s} {s['phase']:5s} {lv:6s} {s['name']:16s} "
              f"몹{len(s['monsters'])} 보스={s['boss']}")
    print(f"\n총 몬스터 {len(all_mons)}, 스테이지 {len(all_stages)}")
    if "--write" in sys.argv:
        _write(all_mons, all_stages)


def _write(mons, stages):
    # 몬스터 중복(같은 이름) 병합 — 최초 등장 기준
    seen = {}
    for m in mons:
        if m["name"] not in seen:
            m2 = dict(m); m2.pop("dungeon", None); m2.pop("level", None); m2.pop("phase", None)
            seen[m["name"]] = m2
    out_m = {"_source": "나무위키 dungeon_*.pdf (extract_wiki.py). 값=위키 서술, 사용자 검수 대상. asset_id(스프라이트)=이미지 매칭 TODO.",
             "monsters": list(seen.values())}
    (REPO / "data" / "monsters.json").write_text(
        json.dumps(out_m, ensure_ascii=False, indent=2), encoding="utf-8")
    out_s = {"_source": "나무위키 dungeon_*.pdf. region/name/level/phase/monsters/boss. bg=배경프레임 매칭 TODO.",
             "stages": stages}
    (REPO / "data" / "stages_wiki.json").write_text(
        json.dumps(out_s, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"-> data/monsters.json ({len(seen)}), data/stages_wiki.json ({len(stages)})")


if __name__ == "__main__":
    main()
