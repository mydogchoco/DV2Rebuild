extends SceneTree

const SP := preload("res://scripts/systems/sell_price.gd")
const EQ := preload("res://scripts/systems/equipment.gd")
const GEM := preload("res://scripts/systems/gem.gd")

var _tables: Dictionary

func _init() -> void:
	var fails := 0
	var shop := _json(_data_file("shop.json"))
	var items := _json(_data_file("items.json"))
	var gems := _json(_data_file("gems.json"))
	var equip := _json(_data_file("equipment.json"))
	_tables = {"shop": shop, "items": items, "gems": gems, "equipment": equip,
		"buy": _buy_index(shop)}

	fails += _eq("조각 먹이(원작 25)", _p("food_ground_paopao_half"), 25)
	fails += _eq("회복물약(원작 10)", _p("heal_potion1"), 10)
	fails += _eq("축복받은 회복물약(원작 250)", _p("heal_potion2"), 250)
	fails += _eq("여신의 회복물약(원작 500)", _p("heal_potion3"), 500)
	fails += _eq("큰 먹이", _p("food_ground_paopao"), 50)

	var food := 0
	var food_miss := 0
	for k: String in items:
		var it = items[k]
		if not (it is Dictionary) or String((it as Dictionary).get("category", "")) != "food":
			continue
		food += 1
		if _p(k) <= 0:
			food_miss += 1
			fails += _fail("음식인데 판매가 0: %s (%s)" % [k, (it as Dictionary).get("name", "")])
	print("음식 %d종 · 가격 누락 %d" % [food, food_miss])
	fails += _eq("음식 종수", food, 41)

	var prev := 0
	for t in 19:
		var cur := _p(GEM.item_key("공격의 젬", t))
		if cur <= 0:
			fails += _fail("젬 티어 %d 판매가 0" % t)
		elif cur < prev:
			fails += _fail("젬 곡선 역전: 티어 %d(%d) < 티어 %d(%d)" % [t, cur, t - 1, prev])
		prev = cur
	print("젬 공격 t0=%d t6=%d t12=%d t18=%d" % [_p(GEM.item_key("공격의 젬", 0)),
		_p(GEM.item_key("공격의 젬", 6)), _p(GEM.item_key("공격의 젬", 12)),
		_p(GEM.item_key("공격의 젬", 18))])
	var whole := _p(GEM.item_key("공격의 젬", 6))
	var broken := _p(GEM.item_key("공격의 젬", 6, {"broken": true}))
	fails += _eq("파손 젬 반값", broken, int(round(whole * 0.5)))
	var hyb := _hybrid_name(gems)
	if hyb != "":
		fails += _eq("혼성젬 계열 배수", _p(GEM.item_key(hyb, 6)), whole * 2)

	for g in 5:
		var lo := _p(EQ.item_key("artifact:테라:%d" % g))
		var hi := _p(EQ.item_key("artifact:테라:%d" % (g + 1)))
		if lo <= 0 or hi <= 0:
			fails += _fail("아티팩트 등급 %d/%d 판매가 0" % [g, g + 1])
		elif hi != lo * 4:
			fails += _fail("아티팩트 승급 차익: 등급 %d ×4 = %d 인데 등급 %d 는 %d"
				% [g, lo * 4, g + 1, hi])

	for k in ["ele_fire", "mall_ground_egg", "alchemy_courage"]:
		if not items.has(k):
			continue
		fails += _eq("판매 불가여야 함: %s" % k, _p(k), 0)
	fails += _eq("정의 없는 젬", _p("gem:없는젬:3"), 0)
	fails += _eq("빈 키", _p("nonexistent_item"), 0)

	var plain := _p(EQ.item_key("basic:깃털:0"))
	fails += _eq("일반 장비 등급0", plain, 1000)
	fails += _eq("일반 장비 등급6", _p(EQ.item_key("basic:깃털:6")), 7000)
	var rare := _p(EQ.item_key("basic:깃털:0", {"rarity": 2}))
	fails += _eq("레어(×2.5)", rare, int(round(plain * 2.5)))
	var enh := _p(EQ.item_key("basic:깃털:0", {"enhance": 10}))
	fails += _eq("10강(+50%)", enh, int(round(plain * 1.5)))
	var bound := _p(EQ.item_key("basic:깃털:0", {"belong": 77}))
	fails += _eq("귀속 반값", bound, int(round(plain * 0.5)))
	var ex := _first_key(EQ.catalog(equip), "exclusive")
	if ex != "":
		fails += _eq("전용 장비(30다이아=75,000골드)", _p(EQ.item_key(ex)), 18750)
	print("장비 일반0=%d 등급6=%d 레어0=%d" % [plain, _p(EQ.item_key("basic:깃털:6")), rare])

	var th := int((shop.get("sell", {}) as Dictionary).get("talk_price_threshold", 0))
	fails += _eq("대사 임계값", th, 4000)
	fails += _eq("대사: 조각 먹이(25)", SP.talk_index(_p("food_ground_paopao_half"), _tables), 1)
	fails += _eq("대사: 여신의 회복물약(500)", SP.talk_index(_p("heal_potion3"), _tables), 1)
	fails += _eq("대사: 일반 장비 등급0(1,000)", SP.talk_index(plain, _tables), 1)
	fails += _eq("대사: 일반 장비 등급2(3,000)",
		SP.talk_index(_p(EQ.item_key("basic:깃털:2")), _tables), 1)
	fails += _eq("대사: 일반 장비 등급3(4,000)",
		SP.talk_index(_p(EQ.item_key("basic:깃털:3")), _tables), 2)
	fails += _eq("대사: 젬 t3(3,450)",
		SP.talk_index(_p(GEM.item_key("공격의 젬", 3)), _tables), 1)
	fails += _eq("대사: 젬 t4(4,650)",
		SP.talk_index(_p(GEM.item_key("공격의 젬", 4)), _tables), 2)
	fails += _eq("대사: 젬 t6(7,500)", SP.talk_index(whole, _tables), 2)
	fails += _eq("대사: 경계값 정확히", SP.talk_index(th, _tables), 2)
	fails += _eq("대사: 경계 바로 아래", SP.talk_index(th - 1, _tables), 1)

	fails += _eq("젬은 수량판", SP.stacks(GEM.item_key("공격의 젬", 3)), true)
	fails += _eq("장비는 1개씩", SP.stacks(EQ.item_key("basic:깃털:0")), false)

	print("=== %s ===" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(0 if fails == 0 else 1)

func _p(key: String) -> int:
	return SP.unit_price(key, _tables)

func _buy_index(shop: Dictionary) -> Dictionary:
	var idx := {}
	for td in (shop.get("tabs", []) as Array):
		for s in ((td as Dictionary).get("stock", []) as Array):
			var sd := s as Dictionary
			if String(sd.get("cur", "gold")) == "gold":
				idx[String(sd.get("item", ""))] = int(sd.get("price", 0))
	return idx

func _hybrid_name(gems: Dictionary) -> String:
	for n: String in (gems.get("gems", {}) as Dictionary):
		if String((gems["gems"][n] as Dictionary).get("category", "")) == "hybrid":
			return n
	return ""

func _first_key(cat: Dictionary, group: String) -> String:
	for k: String in cat:
		if String((cat[k] as Dictionary).get("group", "")) == group:
			return k
	return ""

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
