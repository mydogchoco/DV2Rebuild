extends Node

func _ready() -> void:
	var fails := 0
	var pool: Array = Equipment.option_stats(Data.equipment)
	fails += _eq("롤 풀 7종", pool.size(), 7)

	var legacy_key := Equipment.item_key("basic:깃털:6", {"rarity": 3, "enhance": 2,
		"options": [{"stat": "att", "value": 7}, {"stat": "accuracy", "value": 5},
			{"stat": "depure", "value": 3}]})
	var clean_key := Equipment.item_key("basic:발톱:2", {"rarity": 2,
		"options": [{"stat": "hp", "value": 4}, {"stat": "pure", "value": 9}]})
	var d := {
		"inventory": {legacy_key: 2, clean_key: 1, "item_potion": 5},
		"dragons": [{"uid": 1, "equip": {"slots": [
			{"slot": "all", "key": "basic:부적:0", "grade": 2, "enhance": 0, "belong": 1,
				"options": [{"stat": "depure", "value": 6}, {"stat": "exp", "value": 3}]}]}}],
		"storage": [],
	}
	UserDB._migrate_equip_options(d)

	var inv: Dictionary = d["inventory"]
	fails += _true("명중이 붙었던 키는 사라졌다", not inv.has(legacy_key))
	fails += _eq("멀쩡한 키는 그대로", int(inv.get(clean_key, 0)), 1)
	fails += _eq("장비가 아닌 아이템은 그대로", int(inv.get("item_potion", 0)), 5)
	var new_key := ""
	for k in inv.keys():
		var ks := String(k)
		if ks.begins_with(Equipment.ITEM_PREFIX) and Equipment.parse_item_key(ks) == "basic:깃털:6":
			new_key = ks
	fails += _true("옮겨 간 키가 있다", new_key != "")
	if new_key != "":
		var m := Equipment.item_key_meta(new_key)
		fails += _eq("개수 보존", int(inv[new_key]), 2)
		fails += _eq("등급 보존", int(m.get("rarity", 0)), 3)
		fails += _eq("강화 보존", int(m.get("enhance", 0)), 2)
		var opts: Array = m.get("options", [])
		fails += _eq("옵션 개수 보존", opts.size(), 3)
		fails += _eq("유효했던 옵션은 값까지 그대로",
			int((opts[0] as Dictionary).get("value", 0)), 7)
		var ok := true
		for o in opts:
			ok = ok and (String((o as Dictionary).get("stat", "")) in pool)
		fails += _true("가방 옵션이 전부 유효 스탯", ok)

	var slot: Dictionary = (d["dragons"][0] as Dictionary)["equip"]["slots"][0]
	var sopts: Array = slot["options"]
	fails += _eq("장착 칸 옵션 개수 보존", sopts.size(), 2)
	var sok := true
	for o in sopts:
		sok = sok and (String((o as Dictionary).get("stat", "")) in pool)
	fails += _true("장착 칸 옵션이 전부 유효 스탯", sok)

	var before := JSON.stringify(d)
	UserDB._migrate_equip_options(d)
	fails += _eq("멱등", JSON.stringify(d), before)

	print("[equipmig] %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("[equipmig] FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	print("[equipmig] FAIL %s" % label)
	return 1
