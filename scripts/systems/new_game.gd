class_name NewGame
## logic 층: 새 게임 초기 상태 구성. (CLAUDE.md §10)
## 초기 로드아웃 "정의"는 data(data/new_game.json)에 있고, 이 logic이 UserDB API로 "적용"한다.
## render·에셋 비의존. 저장 직렬화 세부는 UserDB/SaveSystem이 담당(여기선 모름).

## 진행 중 세이브가 없을 때(보유 드래곤 0)만 초기 로드아웃 적용. 적용했으면 true.
static func ensure(udb, def: Dictionary) -> bool:
	if udb.dragon_count() > 0:
		return false
	apply(udb, def)
	return true

## def(new_game.json)를 그대로 UserDB에 반영. 저장은 1회(begin_batch→save).
static func apply(udb, def: Dictionary) -> void:
	udb.begin_batch()
	for d in def.get("dragons", []):
		udb.add_dragon(int(d["id"]), int(d.get("level", 1)))
	var cur: Dictionary = def.get("currency", {})
	for kind in cur:
		udb.add_currency(kind, int(cur[kind]))
	var inv: Dictionary = def.get("inventory", {})
	for item_name in inv:
		udb.add_item(item_name, int(inv[item_name]))
	udb.save()
