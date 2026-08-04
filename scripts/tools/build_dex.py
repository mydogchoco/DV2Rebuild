"""도감 에셋/메타 빌드.
- 속성 탭 아이콘: DV2/480/item/etc.img_plist -> assets/converted/item_etc
- 드래곤 초상(box 스프라이트): dragons.json의 모든 id -> assets/converted/portrait_{id}
- data/dex_meta.json: id별 {awaken(box_s01 보유), evo(box_evolution 보유)}
usage: build_dex.py
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import atlas as atlaslib
import cocos_export

DRAGONS = "data/dragons.json"
OUT_META = "data/dex_meta.json"


def main():
    cocos_export.export("DV2/480/item/etc.img_plist", "item_etc")
    dragons = json.load(open(DRAGONS, encoding="utf-8"))
    meta, converted, missing = {}, 0, []
    for d in dragons:
        did = d["id"]
        # 자작 드래곤은 원본 아틀라스가 없고 다른 드래곤의 아트를 빌려 쓴다(dragons.json art_id).
        # 초상 폴더는 build_dragon_art_alias.py 가 별칭으로 만들고, 여기서는 **도감 메타만**
        # 아트 출처에서 물려받는다(각성/진화 초상 보유 여부는 그림에 딸린 성질이라).
        art = int(d.get("art_id", did))
        plist = "DV2/480/dragon/dragon_%d.img_plist" % art
        if not os.path.exists(plist):
            # 원본 아틀라스가 없는 종 — **외부 팩에서 이식한 드래곤**은 전용 빌더가 초상을
            # 미리 구워 둔다(예: 800 로키 = `build_loki800.py --portrait`). 그 매니페스트를
            # 그대로 읽어 도감 메타만 세운다. 초상 폴더도 없으면 진짜 미보유다.
            man = "assets/converted/portrait_%d/_manifest.json" % art
            if not os.path.exists(man):
                missing.append(did); continue
            names = set(k.replace("dragon_dragon_%d_" % art, "")
                        for k in json.load(open(man, encoding="utf-8")))
            box = set(n for n in names if n.startswith("box_") and "skin" not in n)
            meta[str(did)] = {"awaken": "box_s01" in box, "evo": "box_evolution" in box}
            converted += 1
            continue
        if art == did:
            cocos_export.export(plist, "portrait_%d" % did)
        names = set(n.split("/")[-1].replace(".png", "")
                    for n in atlaslib.parse_cocos_plist(plist)["frames"])
        box = set(n for n in names if n.startswith("box_") and "skin" not in n)
        meta[str(did)] = {"awaken": "box_s01" in box, "evo": "box_evolution" in box}
        converted += 1
    # indent=1 — 커밋된 판이 들여쓴 형태다. 한 줄로 쓰면 diff 가 통째로 바뀌어 검수가 막힌다.
    json.dump(meta, open(OUT_META, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    aw = sum(1 for v in meta.values() if v["awaken"])
    ev = sum(1 for v in meta.values() if v["evo"])
    print("portraits=%d missing=%d  awaken=%d evo=%d  -> %s" % (converted, len(missing), aw, ev, OUT_META))
    if missing:
        print("missing ids:", missing[:30])


if __name__ == "__main__":
    main()
