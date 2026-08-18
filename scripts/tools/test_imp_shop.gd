extends SceneTree

const S := preload("res://scripts/systems/imp_shop.gd")
const E := preload("res://scripts/systems/equipment.gd")

func _init() -> void:
	var fails := 0
	var t = _json(_data_file("imp_shop.json"))
	var eq = _json(_data_file("equipment.json"))
	var items = _json(_data_file("items.json"))
	items = items.get("items", items)

	var stock := S.stock(t)
	fails += _eq("재고 24품목(3계열×6등급 + 해골요새 6종)", stock.size(), 24)
	fails += _eq("계열 4종", S.kinds(t), ["묘안석", "흑요석", "백금석", "해골요새"])
	for k in S.kinds(t):
		fails += _eq("%s 6품목" % k, S.stock_of(t, String(k)).size(), 6)

	var skull_items: Array = ((eq.get("special", {}) as Dictionary).get("skull", {}) as Dictionary).get("items", [])
	var skull_want := {}
	for it in skull_items:
		skull_want["special:skull:%s" % String((it as Dictionary)["name"])] = true
	var skull_got := {}
	for r in S.stock_of(t, "해골요새"):
		skull_got[String((r as Dictionary)["key"])] = true
	fails += _eq("해골요새 6종 전부 진열", skull_got, skull_want)
	fails += _true("해골요새는 뽑기 제외 표시",
		bool(((eq["special"] as Dictionary)["skull"] as Dictionary).get("gacha_excluded", false)))
	for fam in ["balrog", "fiod"]:
		fails += _true("%s 는 뽑기에 남는다" % fam,
			not bool(((eq["special"] as Dictionary)[fam] as Dictionary).get("gacha_excluded", false)))

	var cat := E.catalog(eq)
	var bad_key := 0
	var multi_cur := 0
	var jewels := {}
	for r in stock:
		var row: Dictionary = r
		if not cat.has(String(row["key"])): bad_key += 1
		var c := String(row.get("currency", ""))
		if typeof(row.get("currency")) != TYPE_STRING or c == "": multi_cur += 1
		if not c.begins_with("jewel_"): multi_cur += 1
		if String((items.get(c, {}) as Dictionary).get("subcategory", "")) != "jewel": multi_cur += 1
		jewels[c] = true
		if int(row.get("price", 0)) <= 0: bad_key += 1
	fails += _eq("카탈로그에 없는 재고 키", bad_key, 0)
	fails += _eq("보석 한 종류가 아닌 품목", multi_cur, 0)
	fails += _eq("쓰이는 보석 4종 전부", jewels.size(), 4)
	fails += _true("골드 가격 없음", not jewels.has("gold"))

	var rank := {"jewel_amethyst": 0, "jewel_emerald": 1, "jewel_ruby": 2, "jewel_sapphire": 3}
	var desc := 0
	for k in S.kinds(t):
		var prev := -1
		for r in S.stock_of(t, String(k)):
			var cr := int(rank[String((r as Dictionary)["currency"])])
			if cr < prev: desc += 1
			prev = cr
	fails += _eq("등급이 오를수록 보석이 귀해진다", desc, 0)

	var row0: Dictionary = stock[0]
	var price := int(row0["price"])
	var cur := String(row0["currency"])
	fails += _true("모자라면 불가", not S.can_buy(row0, {cur: price - 1}))
	fails += _eq("부족분 계산", S.shortfall(row0, {cur: price - 3}), 3)
	fails += _true("딱 맞으면 가능", S.can_buy(row0, {cur: price}))
	fails += _eq("충분하면 부족분 0", S.shortfall(row0, {cur: price * 2}), 0)

	var brng := RandomNumberGenerator.new(); brng.seed = 11
	var fail_buy := S.buy(row0, {cur: price - 1}, brng, eq)
	fails += _true("부족 구매는 실패", not bool(fail_buy["ok"]))
	var ok_buy := S.buy(row0, {cur: price}, brng, eq)
	fails += _true("구매 성공", bool(ok_buy["ok"]))
	fails += _eq("소모 화폐", String(ok_buy["spend_key"]), cur)
	fails += _eq("소모 수량", int(ok_buy["spend_count"]), price)
	var gk := String(ok_buy["give_key"])
	fails += _eq("지급 키가 그 장비", E.parse_item_key(gk), String(row0["key"]))

	var grades: Array = (eq.get("option", {}) as Dictionary).get("grades", [])
	var seen := {}
	var N := 4000
	var rrng := RandomNumberGenerator.new(); rrng.seed = 7
	var bad_opt := 0
	for i in N:
		var r: Dictionary = stock[i % stock.size()]
		var res := S.buy(r, {String(r["currency"]): 99999}, rrng, eq)
		var m := E.item_key_meta(String(res["give_key"]))
		var rar := int(m["rarity"])
		seen[rar] = int(seen.get(rar, 0)) + 1
		fails += 0 if rar == int(res.get("rarity", -1)) else 1
		var want_opt := int((grades[rar] as Dictionary).get("options", 0))
		if (m["options"] as Array).size() != want_opt:
			bad_opt += 1
	fails += _eq("옵션 개수가 등급표와 어긋난 건", bad_opt, 0)
	fails += _true("매직·초월은 안 나온다", not seen.has(1) and not seen.has(5))
	for want in [[0, 0.40], [2, 0.30], [3, 0.20], [4, 0.10]]:
		var ri := int((want as Array)[0])
		var wp := float((want as Array)[1])
		var got := float(seen.get(ri, 0)) / float(N)
		fails += _true("희귀도 %d 약 %d%% (%.1f%%)" % [ri, int(wp * 100.0), got * 100.0],
			absf(got - wp) < 0.03)

	var plain := E.item_key_meta(String(S.buy(row0, {cur: price}, brng, {})["give_key"]))
	fails += _eq("표 없으면 일반", int(plain["rarity"]), 0)
	fails += _eq("표 없으면 옵션 없음", (plain["options"] as Array).size(), 0)

	var other := "jewel_sapphire" if cur != "jewel_sapphire" else "jewel_ruby"
	fails += _true("다른 보석으로는 불가", not S.can_buy(row0, {other: 9999}))

	var r2 := RandomNumberGenerator.new(); r2.seed = 3
	for _i in 200:
		var w := S.welcome_key(r2)
		if not w.begins_with("ShopWelcomeImp"): fails += _true("인사말 키 형식", false); break
		var n := int(w.substr("ShopWelcomeImp".length()))
		if n < 1 or n > 9: fails += _true("인사말 1~9", false); break
	for _i in 200:
		var b := S.buy_line_key(r2)
		var n2 := int(b.substr("ShopBuyImpPong_".length()))
		if n2 < 1 or n2 > 4: fails += _true("구매대사 1~4", false); break

	var md = _json(_data_file("monster_drops.json"))
	var from_imp := {}
	for mid in ["160", "161"]:
		for d in ((md["drops"] as Dictionary).get(mid, []) as Array):
			from_imp[String((d as Dictionary).get("key", ""))] = true
	for c in S.currencies(t):
		fails += _true("%s 는 임프가 떨군다" % c, from_imp.has(String(c)))
	for k in ["jewel_amethyst", "jewel_emerald", "jewel_ruby", "jewel_sapphire"]:
		fails += _eq("%s 입수 가능 표시" % k,
			String((items[k] as Dictionary).get("offline", "")), "impl")

	if fails == 0:
		print("[test_imp_shop] ALL PASS")
		quit(0)
	else:
		printerr("[test_imp_shop] %d FAIL" % fails)
		quit(1)

func _json(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("  FAIL %s" % label)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
