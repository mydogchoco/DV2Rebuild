"""Batch-export many dragons' spine skeletons to intermediate JSON.

usage:
  spine_batch.py 1 5 10 20 53            # given ids, all existing stages, all anims
  spine_batch.py --from-data N           # first N dragons listed in data/dragons.json
Scale policy: converter stays native (1:1 spine units). Display scale is applied
by the scene that uses the converted dragon (PC 1080p), not baked here.
"""
import sys, os, json
import spine_export

SRC = "DV2/480/dragon"
# "e" = 각성체 스파인(`dragon_<id>_e_spine.spine_json`, 원본 135종). 원작 Dragon::getImagePathSpineJson
# 이 각성 플래그에서 이 경로를 고르고, 각성 결과 연출(scripts/ui/evol_layer.gd)이 이 씬을 세운다.
# 파일이 있는 드래곤만 변환되므로(아래 exists 검사) 목록에 넣어도 없는 종은 그냥 건너뛴다.
STAGES = ("baby", "child", "adult", "e")


def ids_from_args(argv):
    if "--from-data" in argv:
        n = int(argv[argv.index("--from-data") + 1])
        data = json.load(open("data/dragons.json", encoding="utf-8"))
        return [str(d["id"]) for d in data[:n]]
    return [a for a in argv[1:] if a.isdigit()]


def main():
    ids = ids_from_args(sys.argv)
    done = 0
    for did in ids:
        for st in STAGES:
            if os.path.exists(f"{SRC}/dragon_{did}_{st}_spine.spine_json"):
                try:
                    spine_export.export(did, st, "all")
                    done += 1
                except Exception as e:
                    print(f"  ERROR dragon {did} {st}: {e}")
    print(f"\nbatch done: {done} skeletons exported for ids {ids}")


if __name__ == "__main__":
    main()
