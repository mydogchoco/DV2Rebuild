class_name NewGame
## logic 층: 새 게임 초기 상태 구성. (CLAUDE.md §10)
## 초기 로드아웃 "정의"는 data(data/new_game.json)에 있고, 이 logic이 UserDB API로 "적용"한다.
## render·에셋 비의존. 저장 직렬화 세부는 UserDB/SaveSystem이 담당(여기선 모름).

## 이미 지급했는지 기록하는 세이브 플래그. `UserDB.reset()` 이 세이브를 통째로 갈아 끼우므로
## 초기화하면 자연히 false 로 돌아간다.
const SEEDED_KEY := "new_game_seeded"

## 진행 중 세이브가 없을 때만 초기 로드아웃 적용. 적용했으면 true.
##
## 🔴 2026-08-01: 종전 판정은 **보유 드래곤 0**이었다. 시작 드래곤을 빼자(디버그 지급분이었다)
##    그 조건이 영영 참이라 타이틀을 터치할 때마다 재화·알이 **다시 지급**된다. 그래서
##    "지급했다"는 사실 자체를 세이브에 남긴다. 드래곤을 이미 갖고 있는 기존 세이브는
##    플래그가 없어도 지급받은 것으로 본다(이중 지급 방지).
static func ensure(udb, def: Dictionary) -> bool:
	if bool(udb.get_pmeta(SEEDED_KEY, false)) or udb.dragon_count() > 0:
		return false
	apply(udb, def)
	return true

## def(new_game.json)를 그대로 UserDB에 반영. 저장은 1회(begin_batch→save).
static func apply(udb, def: Dictionary) -> void:
	udb.begin_batch()
	udb.set_pmeta(SEEDED_KEY, true)
	for d in def.get("dragons", []):
		udb.add_dragon(int(d["id"]), int(d.get("level", 1)))
	var cur: Dictionary = def.get("currency", {})
	for kind in cur:
		udb.add_currency(kind, int(cur[kind]))
	var inv: Dictionary = def.get("inventory", {})
	for item_name in inv:
		udb.add_item(item_name, int(inv[item_name]))
	udb.save()
