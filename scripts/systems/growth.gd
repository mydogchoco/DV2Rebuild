class_name Growth
## logic 층: 드래곤 성장/스탯 규칙. (CLAUDE.md §10)
## 순수 정적 함수 — Node·render·에셋·autoload에 의존하지 않는다(헤드리스 테스트 가능).
## 필요한 정의 데이터(드래곤 정의·스탯 테이블)는 인자로 받는다(data 층=Data가 제공).
## 결과값만 반환하고 연출(애니/사운드)은 하지 않는다.

const MAX_LEVEL := 45                            # ASSUMPTION: 레벨 상한 45 (§E — TODO 확정)
const STAGE_BREAKS := {"baby": 9, "child": 19}   # <=9 baby, <=19 child, else adult

## 레벨 → 성장 단계(에셋 단계 키와 동일: baby/child/adult).
static func stage_for_level(level: int) -> String:
	if level <= STAGE_BREAKS["baby"]:
		return "baby"
	if level <= STAGE_BREAKS["child"]:
		return "child"
	return "adult"

## 최종 스탯 = base + growth*(level-1). cri/evd/blk 고정 10% (§K-1).
## dragon_def = Data.get_dragon(id), stat_table = Data.stat_table.
## TODO: grade(개체등급)/문장/각인 보정(§K-5).
static func compute_stats(dragon_def: Dictionary, stat_table: Dictionary, level: int) -> Dictionary:
	var typ = dragon_def.get("type")
	var tier = dragon_def.get("stat_tier")
	var st = stat_table.get(typ, {}).get(tier)
	if st == null:
		return {"hp": 0, "att": 0, "def": 0, "cri": 10, "evd": 10, "blk": 10}
	var lv := maxi(1, level) - 1
	return {
		"hp": int(st["base"]["hp"] + st["growth"]["hp"] * lv),
		"att": int(st["base"]["att"] + st["growth"]["att"] * lv),
		"def": int(st["base"]["def"] + st["growth"]["def"] * lv),
		"cri": 10, "evd": 10, "blk": 10,
	}

## 레벨업 1회 후 레벨(상한 적용). 결과만 반환 — 경험치/재화 소비는 호출측/별도 규칙(§E,§K).
static func next_level(level: int) -> int:
	return mini(MAX_LEVEL, level + 1)
