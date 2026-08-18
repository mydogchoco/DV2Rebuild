extends SceneTree

const SP := preload("res://scripts/systems/sell_price.gd")

const CUT_EGGS := ["mall_holy_egg", "mall_chaos_egg"]
const NOT_SOLD := ["dummy", "cut"]

func _init() -> void:
	var fails := 0
	var shop := _json(_data_file("shop.json"))
	var items := _json(_data_file("items.json"))

	var rows := 0
	var unknown := 0
	for t in (shop.get("tabs", []) as Array):
		var td := t as Dictionary
		for s in (td.get("stock", []) as Array):
			rows += 1
			var key := String((s as Dictionary).get("item", ""))
			var it = items.get(key, null)
			if not (it is Dictionary):
				unknown += 1
				continue
			var off := String((it as Dictionary).get("offline", ""))
			if off in NOT_SOLD:
				fails += _fail("%s 탭에 %s 상품 진열: %s (%s)"
					% [td.get("id", "?"), off, key, (it as Dictionary).get("name", "")])
	print("재고 %d줄 · 아이템 DB에 없는 상품 %d줄" % [rows, unknown])

	var egg: Dictionary = {}
	for t in (shop.get("tabs", []) as Array):
		if String((t as Dictionary).get("id", "")) == "egg":
			egg = t
	var egg_keys: Array = []
	for s in (egg.get("stock", []) as Array):
		egg_keys.append(String((s as Dictionary).get("item", "")))
	for k in CUT_EGGS:
		fails += _eq("EGG 탭에 %s 없음" % k, egg_keys.has(k), false)
		fails += _eq("items.json 에 %s 정의는 유지" % k, items.has(k), true)
		fails += _eq("%s offline" % k,
			String((items.get(k, {}) as Dictionary).get("offline", "")), "dummy")
	print("EGG 탭 %d종: %s" % [egg_keys.size(), ", ".join(PackedStringArray(egg_keys))])

	var tables := {"shop": shop, "items": items, "gems": _json(_data_file("gems.json")),
		"equipment": _json(_data_file("equipment.json")), "buy": {}}
	for k in CUT_EGGS:
		fails += _eq("판매 불가: %s" % k, SP.unit_price(k, tables), 0)

	print("=== %s ===" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(0 if fails == 0 else 1)

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text()) as Dictionary

func _fail(msg: String) -> int:
	print("  ✗ ", msg)
	return 1

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	return _fail("%s: %s (기대 %s)" % [label, got, want])

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
