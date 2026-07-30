"""libgame.so ELF 리더 + 경량 Itanium C++ 디맹글러.

원작 네이티브 엔진(lib/*/libgame.so)은 스트립되지 않아 C++ 심볼이 살아있다.
외부 도구(nm/c++filt/binutils) 없이 순수 Python으로:
  - ELF64 섹션(.dynsym/.dynstr/.rodata/.text 등) 파싱
  - 동적 심볼 이름 열거
  - Class::method 수준의 디맹글(재구현 청사진 용도 — 파라미터 타입 완전복원은 하지 않음)

주의: 원본 .so는 절대 수정하지 않는다(읽기 전용).
"""
from __future__ import annotations
import struct
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]  # scripts/tools/ -> repo root
# .so 위치는 레포마다 다름: DV2는 루트, 원작 추출 레포는 lib/arm64-v8a/. 존재하는 쪽을 자동 선택.
_SO_CANDIDATES = [REPO_ROOT / "libgame.so", REPO_ROOT / "lib" / "arm64-v8a" / "libgame.so"]
DEFAULT_SO = str(next((p for p in _SO_CANDIDATES if p.exists()), _SO_CANDIDATES[0]))


@dataclass
class Section:
    name: str
    type: int
    flags: int
    addr: int
    offset: int
    size: int


class ELF:
    """최소 ELF64(little-endian) 리더. 이 프로젝트의 arm64 .so 전용."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        d = self.data
        if d[:4] != b"\x7fELF":
            raise ValueError(f"ELF 아님: {path}")
        if d[4] != 2:
            raise ValueError("64-bit ELF만 지원")
        e_shoff = struct.unpack_from("<Q", d, 0x28)[0]
        e_shentsize = struct.unpack_from("<H", d, 0x3A)[0]
        e_shnum = struct.unpack_from("<H", d, 0x3C)[0]
        e_shstrndx = struct.unpack_from("<H", d, 0x3E)[0]

        def raw(i):
            o = e_shoff + i * e_shentsize
            return struct.unpack_from("<IIQQQQ", d, o)  # name,type,flags,addr,off,size

        shstr_off = raw(e_shstrndx)[4]

        def sname(n):
            e = d.index(b"\0", shstr_off + n)
            return d[shstr_off + n : e].decode("latin1")

        self.sections: dict[str, Section] = {}
        for i in range(e_shnum):
            name, typ, flags, addr, off, size = raw(i)
            s = Section(sname(name), typ, flags, addr, off, size)
            self.sections[s.name] = s

    def section_bytes(self, name: str) -> bytes:
        s = self.sections[name]
        return self.data[s.offset : s.offset + s.size]

    def dynsym_names(self) -> list[str]:
        """.dynsym이 가리키는 .dynstr 이름을 전부 반환(빈 문자열 제외)."""
        dynstr = self.section_bytes(".dynstr")
        return [b.decode("latin1") for b in dynstr.split(b"\0") if b]


# ---------------------------------------------------------------------------
# 경량 Itanium 디맹글러 (nested-name 위주)
# ---------------------------------------------------------------------------
_OPERATORS = {
    "nw": "operator new", "na": "operator new[]", "dl": "operator delete",
    "da": "operator delete[]", "pl": "operator+", "mi": "operator-",
    "ml": "operator*", "dv": "operator/", "eq": "operator==", "ne": "operator!=",
    "lt": "operator<", "gt": "operator>", "le": "operator<=", "ge": "operator>=",
    "aS": "operator=", "ix": "operator[]", "cl": "operator()", "cv": "operator T",
}


@dataclass
class Sym:
    raw: str
    namespaces: list[str]   # 클래스/네임스페이스 경로 (마지막 요소 제외)
    member: str             # 메서드/생성자/소멸자 이름
    kind: str               # 'method' | 'ctor' | 'dtor' | 'data' | 'operator' | 'other'

    @property
    def cls(self) -> str:
        return "::".join(self.namespaces) if self.namespaces else ""

    @property
    def full(self) -> str:
        parts = self.namespaces + [self.member]
        return "::".join(parts)


def _read_len_name(s: str, i: int):
    """<int><identifier> 형태 하나를 읽어 (identifier, next_index) 반환. 실패 시 (None, i)."""
    j = i
    while j < len(s) and s[j].isdigit():
        j += 1
    if j == i:
        return None, i
    n = int(s[i:j])
    if j + n > len(s):
        return None, i
    return s[j : j + n], j + n


def demangle(raw: str) -> Sym | None:
    """Class::method 수준으로 디맹글. 파라미터 타입은 복원하지 않는다.

    지원: _ZN...E (nested), 생성자 C1/C2/C3, 소멸자 D0/D1/D2, 연산자 일부.
    미지원 형태는 None 반환(호출측에서 raw 그대로 분류).
    """
    if not raw.startswith("_Z"):
        return None
    s = raw[2:]
    if not s.startswith("N"):
        # 단순 형태 _Z<len><name>... (전역 함수) — 이름만 추출
        name, _ = _read_len_name(s, 0)
        if name:
            return Sym(raw, [], name, "other")
        return None
    # nested: 반복적으로 <len><name> 수집, C*/D*/연산자 처리, E에서 종료
    i = 1
    parts: list[str] = []
    kind = "method"
    while i < len(s):
        c = s[i]
        if c == "E":
            break
        if c in "KVr":  # cv-qualifier (const/volatile/restrict) — 스킵
            i += 1
            continue
        if c == "C" and i + 1 < len(s) and s[i + 1] in "123":
            # 생성자: 클래스명과 동일
            base = parts[-1] if parts else "?"
            parts.append(base)
            kind = "ctor"
            i += 2
            continue
        if c == "D" and i + 1 < len(s) and s[i + 1] in "012":
            base = parts[-1] if parts else "?"
            parts.append("~" + base)
            kind = "dtor"
            i += 2
            continue
        if s[i : i + 2] in _OPERATORS:
            parts.append(_OPERATORS[s[i : i + 2]])
            kind = "operator"
            i += 2
            continue
        name, ni = _read_len_name(s, i)
        if name is None:
            # 치환(S_ 등)·템플릿(I..E) 등 미지원 → 여기서 종료
            break
        parts.append(name)
        i = ni
    if not parts:
        return None
    if len(parts) == 1:
        return Sym(raw, [], parts[0], kind)
    return Sym(raw, parts[:-1], parts[-1], kind)


if __name__ == "__main__":
    import sys
    so = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SO
    elf = ELF(so)
    print(f"[so_reader] {so}")
    for n, sec in sorted(elf.sections.items()):
        if sec.size > 1024:
            print(f"  {n:16} {sec.size:>10}B")
    names = elf.dynsym_names()
    print(f"동적 심볼: {len(names)}")
    for t in ("_ZN7cocos2d6Dragon12getHatchTimeEv",
              "_ZN7cocos2d11BattleScene14calculateDamageEPNS_11FightDragonEi",
              "_ZN7cocos2d15EggCombineLayerD1Ev"):
        print(f"  {t}  ->  {demangle(t) and demangle(t).full}")
