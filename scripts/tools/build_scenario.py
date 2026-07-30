"""시나리오(스토리) 대사 추출 — stringsData_KR.xml → data/scenario.json

## 왜 이게 가능한가

CLAUDE.md §1-2 의 "수치·공식만 서버와 함께 소실" 원칙 그대로다.
스토리에서 **유실된 것은 흐름 데이터(JSON)뿐이고, 대사 텍스트는 전부 클라에 남아 있다.**

- `ScenarioManager::ResponseScriptJson` 이 서버 응답의 `"script"` 배열을 읽어
  `ScenarioScript` 객체 목록으로 만든다. 그 객체의 필드(= libgame.so `.dynsym` 심볼에서 확정):

      scenarioNo scenarioMNo scriptNo stateNo npcNo emotionNo posNo
      bgNo bgmNo cutNo questItemNo  |  moveData eventData sceneAction (문자열)

  ⇒ **누가/어디서/어떤 배경으로 말하는가는 서버 데이터라 유실.**

- 대사 본문은 `StringManager` 가 키로 찾는다. libgame.so 안의 포맷 문자열 3종:

      "ScenarioTalk%d_%d"        (scenarioNo, scriptNo)
      "ScenarioTalk%d_%d_%d"     (scenarioNo, scenarioMNo, scriptNo)
      "ScenarioTalk%d_F_%d"      (scenarioNo, scriptNo)   ← 여성 주인공 분기

  ⇒ **키가 순서를 인코딩하고 있어서 대사 순서까지 복원된다.** 5,000줄 전량 실재.

## 산출 스키마 (data/scenario.json)

    {
      "_re_basis": "...",
      "npc_names": { "<folder>": "<표시이름>" },        # <NPC_*> 63종. 폴더명 = npc/<folder>
      "scenarios": {
        "<scenarioNo>": {
          "parts": [                                    # scenarioMNo 오름차순(없으면 [0])
            { "m": <int|null>, "gender": "" | "F",
              "lines": [ {"k": <scriptNo>, "text": "..."} ] }
          ],
          "illust": ["sn_12_1_illust.jpg", ...],       # assets/converted/scenario/ 아래 파일명
          "cuts":   ["sn_20_1.png", ...]               # sn_<no>/<파일> → sn_<no>_<파일>
        }
      }
    }

## 채워야 할 것(유실)

`docs/input/review/scenario_sheet.md` 참고 — 줄마다 npcNo(화자)/bgNo(배경)가 없다.
여기서 지어내지 않는다(HARD RULE 6). 화자 미상이면 story.gd 가 이름칸을 비운다.

사용: python scripts/tools/build_scenario.py
"""
from __future__ import annotations
import io, json, re, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
XML = ROOT / "DV2" / "string" / "stringsData_KR.xml"
OUT = ROOT / "data" / "scenario.json"
SN_DIR = ROOT / "DV2" / "480" / "scenario" / "main_story"
# 삽화는 아틀라스가 아니라 낱장 jpg 라 build_adventure_bg.py 와 같이 그대로 복사한다.
ART_OUT = ROOT / "assets" / "converted" / "scenario"

TALK = re.compile(r"<(ScenarioTalk(\d+)(?:_(F|\d+))?(?:_(\d+))?)>(.*?)</\1>", re.S)
NPC = re.compile(r"<NPC_([A-Za-z0-9_]+)>(.*?)</NPC_\1>", re.S)


def unescape(s: str) -> str:
    # 원작 문자열은 줄바꿈을 &#10; 로 넣는다. 그 외 XML 엔티티도 정리.
    return (s.replace("&#10;", "\n").replace("&amp;", "&")
             .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"'))


def main() -> None:
    if not XML.exists():
        raise SystemExit(f"원본 문자열 리소스가 없다: {XML}")
    raw = io.open(XML, encoding="utf-8").read()

    npc_names = {k: unescape(v).strip() for k, v in NPC.findall(raw)}

    # (scenarioNo, mNo|None, gender) → [(scriptNo, text)]
    buckets: dict[tuple, list] = {}
    for _key, sno, mid, tail, text in TALK.findall(raw):
        sno_i = int(sno)
        if tail:                       # ScenarioTalk<N>_<M>_<K>  또는  <N>_F_<K>
            if mid == "F":
                bucket = (sno_i, None, "F")
            else:
                bucket = (sno_i, int(mid), "")
            k = int(tail)
        elif mid and mid != "F":       # ScenarioTalk<N>_<K>
            bucket = (sno_i, None, "")
            k = int(mid)
        else:
            continue
        buckets.setdefault(bucket, []).append((k, unescape(text).strip()))

    # 삽화/컷 파일 인덱스(실재하는 것만 — 없는 경로를 적지 않는다) + assets/converted/scenario 로 복사
    illust: dict[int, list] = {}
    cuts: dict[int, list] = {}
    if SN_DIR.exists():
        ART_OUT.mkdir(parents=True, exist_ok=True)
        for p in sorted(SN_DIR.iterdir()):
            m = re.match(r"sn_(\d+)_(\d+)_illust\.jpg$", p.name)
            if m:
                dst = ART_OUT / p.name
                if not dst.exists():
                    shutil.copyfile(p, dst)
                illust.setdefault(int(m.group(1)), []).append(p.name)
                continue
            m = re.match(r"sn_(\d+)$", p.name)
            if m and p.is_dir():
                for f in sorted(p.iterdir()):
                    if f.suffix.lower() in (".png", ".jpg"):
                        name = f"{p.name}_{f.name}"
                        dst = ART_OUT / name
                        if not dst.exists():
                            shutil.copyfile(f, dst)
                        cuts.setdefault(int(m.group(1)), []).append(name)

    # 장면 배경 6장(주/야 × townsquare·bighouse·townfarm). 원작 `ScenarioSupport::changeBackGround`
    # 의 BackGruundName 1~6 이 이걸 가리킨다 — 나머지 번호는 탐험 배경 재사용이라
    # `assets/converted/adventure_bg/` 로 이미 변환돼 있다(story.gd `_bg_res` 가 해석).
    bg_dir = SN_DIR / "bg"
    if bg_dir.exists():
        out = ART_OUT / "bg"
        out.mkdir(parents=True, exist_ok=True)
        for f in sorted(bg_dir.glob("*.jpg")):
            dst = out / f.name
            if not dst.exists():
                shutil.copyfile(f, dst)

    scenarios: dict[str, dict] = {}
    for (sno, mno, gender), lines in sorted(buckets.items(),
                                           key=lambda kv: (kv[0][0], kv[0][1] or 0, kv[0][2])):
        lines.sort(key=lambda t: t[0])
        e = scenarios.setdefault(str(sno), {"parts": [], "illust": [], "cuts": []})
        e["parts"].append({
            "m": mno, "gender": gender,
            "lines": [{"k": k, "text": t} for k, t in lines],
        })
    for sno, paths in illust.items():
        scenarios.setdefault(str(sno), {"parts": [], "illust": [], "cuts": []})["illust"] = paths
    for sno, paths in cuts.items():
        scenarios.setdefault(str(sno), {"parts": [], "illust": [], "cuts": []})["cuts"] = paths

    doc = {
        "_re_basis": (
            "대사 텍스트 = DV2/string/stringsData_KR.xml 전량 실재(추출, 무손실). "
            "키 포맷 3종은 libgame.so 상수: ScenarioTalk%d_%d / %d_%d_%d / %d_F_%d. "
            "흐름 데이터(ScenarioScript: npcNo/emotionNo/posNo/bgNo/bgmNo/cutNo/questItemNo/"
            "moveData/eventData/sceneAction)는 서버 JSON(ResponseScriptJson)이라 **유실**. "
            "→ 화자·배경·연출은 docs/input/review/scenario_sheet.md 로 사용자가 채운다."),
        "_generated": "scripts/tools/build_scenario.py",
        "npc_names": npc_names,
        "scenarios": scenarios,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(
        json.dumps(doc, ensure_ascii=False, indent=1))

    nlines = sum(len(p["lines"]) for s in scenarios.values() for p in s["parts"])
    print(f"[scenario] 시나리오 {len(scenarios)}편 · 파트 "
          f"{sum(len(s['parts']) for s in scenarios.values())} · 대사 {nlines}줄")
    print(f"[scenario] NPC 이름 {len(npc_names)}종 · 삽화 {sum(len(v) for v in illust.values())}장 "
          f"· 컷 {sum(len(v) for v in cuts.values())}장 → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
