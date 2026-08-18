extends SceneTree

const Enhance := preload("res://scripts/systems/dragon_enhance.gd")

func _init() -> void:
	var fails := 0
	var items: Dictionary = _json(_data_file("items.json"))
	var shop: Dictionary = _json(_data_file("shop.json"))
	var key := Enhance.TICKET_ITEM

	fails += _true("285번 강화권 아이템 등록", items.has(key))
	if items.has(key):
		var item: Dictionary = items[key]
		fails += _eq("강화권 이름", String(item.get("name", "")), "드래곤 강화권")
		fails += _eq("강화권 아이콘", String(item.get("icon", "")),
			"item_etc/item_etc_five_star_coupon")

	var listings: Array = []
	for tab in shop.get("tabs", []):
		if String((tab as Dictionary).get("id", "")) != "etc":
			continue
		for entry in (tab as Dictionary).get("stock", []):
			if String((entry as Dictionary).get("item", "")) == key:
				listings.append(entry)
	fails += _eq("다이아 샵 강화권 상품 수", listings.size(), 1)
	if listings.size() == 1:
		fails += _eq("강화권 가격", int(listings[0].get("price", 0)), 500)
		fails += _eq("강화권 결제 화폐", String(listings[0].get("cur", "")), "diamond")

	for required_grade in [0.0, 3.0, 6.0, 99.0]:
		fails += _true("강화권으로 요구 등급 %.1f 대체" % required_grade,
			Enhance.material_satisfies(true, 1, 0.0, required_grade))
	fails += _true("강화권이 없으면 대체 불가",
		not Enhance.material_satisfies(true, 0, 99.0, 0.0))
	fails += _true("기존 드래곤 재료는 요구 등급 유지",
		Enhance.material_satisfies(false, 0, 6.0, 6.0)
		and not Enhance.material_satisfies(false, 0, 5.9, 6.0))

	if fails == 0:
		print("[test_dragon_enhance] ALL PASS")
	else:
		print("[test_dragon_enhance] %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	return parsed if parsed is Dictionary else {}

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1

func _true(label: String, value: bool) -> int:
	if value:
		return 0
	print("  FAIL %s" % label)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
