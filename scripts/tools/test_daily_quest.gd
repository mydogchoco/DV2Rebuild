extends Node

func _ready() -> void:
	_run()

func _run() -> void:
	var fails := 0

	for e: Dictionary in DailyQuest.POOL:
		var kind := String(e["kind"])
		if kind == "crystal":
			continue
		if kind == "currency":
			if not (String(e["key"]) in ["gold", "diamond"]):
				print("  FAIL 알 수 없는 재화: ", e["key"]); fails += 1
			continue
		if not Data.items.has(String(e["key"])):
			print("  FAIL items.json 에 없는 키: ", e["key"]); fails += 1
	for k: String in DailyQuest.CRYSTALS:
		if not Data.items.has(k):
			print("  FAIL items.json 에 없는 결정: ", k); fails += 1
	if DailyQuest.CRYSTALS.size() != 9:
		print("  FAIL 결정 9종이어야 한다(그림자 포함): ", DailyQuest.CRYSTALS.size()); fails += 1

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var seen := {}
	for i in 4000:
		var p := DailyQuest.roll(rng)
		var kind := String(p.get("kind", ""))
		if not (kind in ["item", "currency"]):
			print("  FAIL roll 이 미확정 kind 를 냈다: ", p); fails += 1
			break
		seen[String(p.get("key", ""))] = int(seen.get(String(p.get("key", "")), 0)) + 1
	if seen.size() != 14:
		print("  FAIL 4000회에 %d 가지만 나왔다(기대 14)" % seen.size()); fails += 1
	var crystal_hits := 0
	for k: String in DailyQuest.CRYSTALS:
		crystal_hits += int(seen.get(k, 0))
	var share := float(crystal_hits) / 4000.0
	if share < 0.12 or share > 0.21:
		print("  FAIL 결정 비중 %.3f (기대 ~0.167)" % share); fails += 1

	var before_dia := UserDB.diamond()
	var before := {}
	var keys := ["bless_of_dersa", "colosseum_coin", "stone_heart2", "stone_spirit2", "crystal_shadow"]
	for k: String in keys:
		before[k] = UserDB.item_count(k)
	DailyQuest.grant({"kind": "currency", "key": "diamond", "n": 100})
	if UserDB.diamond() != before_dia + 100:
		print("  FAIL 다이아 100 미지급"); fails += 1
	UserDB.add_currency("diamond", -100)
	for k: String in keys:
		var n := 200 if k == "colosseum_coin" else 1
		DailyQuest.grant({"kind": "item", "key": k, "n": n})
		if UserDB.item_count(k) != int(before[k]) + n:
			print("  FAIL 미지급: ", k); fails += 1
		UserDB.add_item(k, -n)

	if UserDB.diamond() != before_dia:
		print("  FAIL 다이아 원복 실패: %d → %d" % [before_dia, UserDB.diamond()]); fails += 1
	for k: String in keys:
		if UserDB.item_count(k) != int(before[k]):
			print("  FAIL 원복 실패: %s %d → %d" % [k, int(before[k]), UserDB.item_count(k)]); fails += 1

	if DailyQuest.describe({"kind": "currency", "key": "gold", "n": 1000}) != "1000 G":
		print("  FAIL 골드 표기"); fails += 1
	if DailyQuest.describe({"kind": "currency", "key": "diamond", "n": 100}) != "다이아 100개":
		print("  FAIL 다이아 표기"); fails += 1
	if DailyQuest.describe({"kind": "item", "key": "bless_of_dersa", "n": 1}) != "데르사의 축복 1개":
		print("  FAIL 아이템 표기: ", DailyQuest.describe({"kind": "item", "key": "bless_of_dersa", "n": 1}))
		fails += 1

	if (Data.colosseum as Dictionary).has("refresh"):
		print("  FAIL colosseum.json 에 refresh 노브가 남아 있다"); fails += 1
	var src := FileAccess.get_file_as_string("res://scripts/systems/colosseum.gd")
	for m: String in ["refresh_cost", "pay_refresh", "refresh_is_free", "reroll_ladder"]:
		if src.contains("static func %s(" % m):
			print("  FAIL Colosseum.%s 가 남아 있다" % m); fails += 1

	if fails == 0:
		print("[test_daily_quest] ALL PASS")
	else:
		print("[test_daily_quest] %d FAIL" % fails)
	get_tree().quit()
