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
STAGES = ("baby", "child", "adult")


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
