"""libgame.so → 서버 JSON 데이터 스키마 복원.

원작 마스터/상태 데이터는 서버에서 rapidjson JSON으로 내려받았고 서비스 종료로 소실됐다.
그러나 바이너리에는 그 구조를 되살릴 단서가 남아있다:
  1) .rodata에 하드코딩된 샘플/테스트 JSON 페이로드 (필드 순서·타입 노출)
  2) .rodata의 JSON 필드 키 토큰
  3) 심볼의 InitJson*/setXxx(rapidjson::Value&) 메서드 이름 = 어떤 JSON 구조가 있는지

출력: docs/ref/orig_code/data_schema.md 용 마크다운(스키마 근거 모음).
사용:  python scripts/tools/extract_schema.py > docs/ref/orig_code/data_schema.md
"""
from __future__ import annotations
import sys, re, json
from so_reader import ELF, demangle, DEFAULT_SO

# 알려진 데이터 필드 어휘(문자열 분석 §A + 샘플 payload 기반). 이 토큰이 들어간
# rodata 식별자는 JSON 키 후보로 본다.
FIELD_HINTS = (
    "att", "def", "hp", "exp", "cri", "evd", "blk", "grade", "star", "gen",
    "level", "lv", "egg", "combine", "skill", "element", "aura", "race",
    "dragon", "monster", "raid", "gold", "diamond", "senz", "soul", "gem",
    "hatch", "breed", "mate", "enchant", "seal", "crest", "rune", "awaken",
    "reward", "drop", "rate", "prob", "cost", "price", "buff", "debuff",
    "nick", "no", "id", "type", "count", "time", "stamina", "point", "tier",
)


def find_embedded_json(elf: ELF):
    """rodata에서 JSON스러운 printable run을 찾아 (offset, text) 리스트로 반환."""
    d = elf.data
    sec = elf.sections[".rodata"]
    blob = d[sec.offset : sec.offset + sec.size]
    out = []
    for m in re.finditer(rb'\{"[a-zA-Z_]', blob):
        s = m.start()
        # 앞뒤 printable 확장
        while s > 0 and 0x20 <= blob[s - 1] <= 0x7E:
            s -= 1
        e = m.start()
        while e < len(blob) and 0x20 <= blob[e] <= 0x7E:
            e += 1
        text = blob[s:e].decode("latin1")
        # 진짜 JSON 조각만: 최소한 콜론 포함, 8자 이상
        if ":" in text and len(text) >= 8:
            out.append((sec.addr + s, text))
    # 중복 제거(같은 시작주소)
    seen = set()
    uniq = []
    for off, t in out:
        if off in seen:
            continue
        seen.add(off)
        uniq.append((off, t))
    return uniq


def rodata_field_keys(elf: ELF):
    """rodata C-string 중 JSON 키로 보이는 식별자 토큰 수집."""
    d = elf.data
    sec = elf.sections[".rodata"]
    blob = d[sec.offset : sec.offset + sec.size]
    keys = set()
    for m in re.finditer(rb"[ -~]{3,40}", blob):
        s = m.group().decode("latin1")
        if re.fullmatch(r"[a-z][a-zA-Z0-9_]{2,30}", s):
            low = s.lower()
            if any(h in low for h in FIELD_HINTS):
                keys.add(s)
    return sorted(keys)


def initjson_methods(elf: ELF):
    """심볼에서 InitJson*/setXxx(rapidjson) 계열 메서드명 수집 = JSON 구조 힌트."""
    hits = []
    for raw in elf.dynsym_names():
        sym = demangle(raw)
        if sym is None:
            continue
        m = sym.member
        if m.startswith("InitJson") or m.startswith("initJson") or m.startswith("parseJson") or m.startswith("setJson"):
            hits.append(f"{sym.cls}::{m}" if sym.cls else m)
    return sorted(set(hits))


def try_pretty(text: str) -> str | None:
    try:
        return json.dumps(json.loads(text), ensure_ascii=False, indent=1)
    except Exception:
        return None


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    elf = ELF(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SO)

    out = ["<!-- 자동생성: scripts/tools/extract_schema.py — 원본 libgame.so 기반. -->"]
    out.append("# 부록 B. 서버 JSON 데이터 스키마 (복원 단서)\n")
    out.append("> 마스터 데이터 값 자체는 서버 소실. 아래는 **데이터 구조**를 되살리는 근거다.")
    out.append("> `data/*.json` 스키마 설계 시 이 필드명·배열순서를 사용해 위키/csv 값을 매핑한다.\n")

    # 1) 임베드 JSON
    blobs = find_embedded_json(elf)
    blobs.sort(key=lambda x: len(x[1]), reverse=True)
    out.append(f"\n## B.1 바이너리에 하드코딩된 샘플 JSON ({len(blobs)}개)\n")
    out.append("주로 테스트/기본 페이로드. **필드 순서·타입**이 그대로 드러나므로 스키마 역설계에 직결.\n")
    for off, text in blobs[:12]:
        out.append(f"\n### `0x{off:x}` ({len(text)}B)\n")
        pretty = try_pretty(text)
        if pretty and len(pretty) < 6000:
            out.append("```json\n" + pretty + "\n```")
        else:
            out.append("```\n" + text[:2000] + ("\n… (truncated)" if len(text) > 2000 else "") + "\n```")

    # 2) InitJson 메서드
    methods = initjson_methods(elf)
    out.append(f"\n## B.2 JSON 파싱 메서드 (구조 힌트, {len(methods)}개)\n")
    out.append("메서드 이름이 곧 '어떤 JSON 오브젝트/필드를 읽는지'를 알려준다.\n")
    for m in methods:
        out.append(f"- `{m}`")

    # 3) 필드 키 후보
    keys = rodata_field_keys(elf)
    out.append(f"\n## B.3 rodata JSON 필드 키 후보 ({len(keys)}개)\n")
    out.append("데이터 관련 어휘를 포함한 rodata 식별자. 실제 서버 JSON 키일 가능성이 높다.\n")
    out.append("```\n" + ", ".join(keys) + "\n```")

    sys.stdout.write("\n".join(out))
    sys.stderr.write(
        f"\n[extract_schema] 임베드 JSON {len(blobs)}, InitJson계열 {len(methods)}, "
        f"필드키 후보 {len(keys)}\n"
    )


if __name__ == "__main__":
    main()
