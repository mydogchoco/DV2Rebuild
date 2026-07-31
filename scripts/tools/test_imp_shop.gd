extends SceneTree
## 헤드리스 ImpShop(임프상인) 테스트 (§8 — logic은 화면 없이 검증).
##
## 검증 대상 = 사용자 확정(2026-07-31):
##   · 재고 = 묘안석·흑요석·백금석 계열 **전 등급 장비**
##   · 화폐 = **보석**(골드 아님 — 원작 <ShopWelcomeImp7>)
##   · **한 아이템은 한 종류의 보석만** 받는다
##   · 주간 랭킹은 ⚫CUT
## 실행: godot --headless --path . --script res://scripts/tools/test_imp_shop.gd --quit-after 5

const S := preload("res://scripts/systems/imp_shop.gd")
const E := preload("res://scripts/systems/equipment.gd")

func _init() -> void:
	var fails := 0
	var t = _json("res://data/imp_shop.json")
	var eq = _json("res://data/equipment.json")
	var items = _json("res://data/items.json")
	items = items.get("items", items)

	var stock := S.stock(t)
	fails += _eq("재고 18품목(3계열×6등급)", stock.size(), 18)
	fails += _eq("계열 3종", S.kinds(t), ["묘안석", "흑요석", "백금석"])
	for k in S.kinds(t):
		fails += _eq("%s 6등급" % k, S.stock_of(t, String(k)).size(), 6)

	# 재고 키가 실제 장비 카탈로그에 있어야 한다(정의 단일 출처 = equipment.json).
	var cat := E.catalog(eq)
	var bad_key := 0
	var multi_cur := 0
	var jewels := {}
	for r in stock:
		var row: Dictionary = r
		if not cat.has(String(row["key"])): bad_key += 1
		# **한 종류만** — currency 는 문자열 하나여야 하고 보석이어야 한다.
		var c := String(row.get("currency", ""))
		if typeof(row.get("currency")) != TYPE_STRING or c == "": multi_cur += 1
		if not c.begins_with("jewel_"): multi_cur += 1
		if String((items.get(c, {}) as Dictionary).get("subcategory", "")) != "jewel": multi_cur += 1
		jewels[c] = true
		if int(row.get("price", 0)) <= 0: bad_key += 1
	fails += _eq("카탈로그에 없는 재고 키", bad_key, 0)
	fails += _eq("보석 한 종류가 아닌 품목", multi_cur, 0)
	fails += _eq("쓰이는 보석 4종 전부", jewels.size(), 4)
	# 골드를 받지 않는다(원작 <ShopWelcomeImp7>).
	fails += _true("골드 가격 없음", not jewels.has("gold"))

	# 희귀도 순서(자수정<에메랄드<루비<사파이어)가 등급을 따라 올라간다.
	var rank := {"jewel_amethyst": 0, "jewel_emerald": 1, "jewel_ruby": 2, "jewel_sapphire": 3}
	var desc := 0
	for k in S.kinds(t):
		var prev := -1
		for r in S.stock_of(t, String(k)):
			var cr := int(rank[String((r as Dictionary)["currency"])])
			if cr < prev: desc += 1
			prev = cr
	fails += _eq("등급이 오를수록 보석이 귀해진다", desc, 0)

	# 구매 판정 — 보유가 모자라면 못 산다.
	var row0: Dictionary = stock[0]
	var price := int(row0["price"])
	var cur := String(row0["currency"])
	fails += _true("모자라면 불가", not S.can_buy(row0, {cur: price - 1}))
	fails += _eq("부족분 계산", S.shortfall(row0, {cur: price - 3}), 3)
	fails += _true("딱 맞으면 가능", S.can_buy(row0, {cur: price}))
	fails += _eq("충분하면 부족분 0", S.shortfall(row0, {cur: price * 2}), 0)

	var fail_buy := S.buy(row0, {cur: price - 1})
	fails += _true("부족 구매는 실패", not bool(fail_buy["ok"]))
	var ok_buy := S.buy(row0, {cur: price})
	fails += _true("구매 성공", bool(ok_buy["ok"]))
	fails += _eq("소모 화폐", String(ok_buy["spend_key"]), cur)
	fails += _eq("소모 수량", int(ok_buy["spend_count"]), price)
	# 지급 키는 장비 인벤 키 — 상점 구매는 일반 100%(옵션 0개).
	var gk := String(ok_buy["give_key"])
	fails += _eq("지급 키가 그 장비", E.parse_item_key(gk), String(row0["key"]))
	var meta := E.item_key_meta(gk)
	fails += _eq("상점 구매는 일반 등급", int(meta["rarity"]), 0)
	fails += _eq("상점 구매는 옵션 없음", (meta["options"] as Array).size(), 0)

	# 다른 보석으로는 못 산다(한 종류만 받는다).
	var other := "jewel_sapphire" if cur != "jewel_sapphire" else "jewel_ruby"
	fails += _true("다른 보석으로는 불가", not S.can_buy(row0, {other: 9999}))

	# 대사 키(원작 문자열)
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

	# 보석이 실제로 입수 가능해야 한다(임프 드랍) — 아니면 상점이 잠긴 기능이 된다.
	var md = _json("res://data/monster_drops.json")
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
