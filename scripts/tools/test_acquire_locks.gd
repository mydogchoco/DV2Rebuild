extends Node

const EQ := preload("res://scripts/systems/equipment.gd")
const DR := preload("res://scripts/systems/drops.gd")
const EG := preload("res://scripts/systems/egg_gacha.gd")

const LOCKED := [600, 700, 666, 777]

var _log: FileAccess = null

func _ready() -> void:
	_log = FileAccess.open("user://test_acquire_locks.txt", FileAccess.WRITE)
	var fails := 0
	fails += _compiles()
	fails += _equipment_icons()
	fails += _dragon_locks()
	_say("")
	_say("=== %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	if _log:
		_log.flush()

func _compiles() -> int:
	var fails := 0
	_say("[컴파일] 수정한 화면 스크립트")
	for p in ["res://scripts/ui/shop.gd", "res://scripts/ui/breeding.gd",
			"res://scripts/ui/cave.gd", "res://scripts/tools/test_equipment.gd"]:
		fails += _true(String(p).get_file(), load(String(p)) != null)
	return fails

func _equipment_icons() -> int:
	var fails := 0
	_say("[장비] 아이콘 미보유분 제외")
	var cat: Dictionary = EQ.catalog(Data.equipment)
	var ev_all: int = (Data.equipment.get("event", []) as Array).size()
	var ev_on: int = EQ.event_pool(Data.equipment).size()
	fails += _eq("이벤트 장비 원본 25종", ev_all, 25)
	fails += _eq("그중 구현 25종(아이콘 보유분)", ev_on, 25)
	fails += _true("특수 장비 계열도 복원됨", cat.has("special:balrog:카이저 발록의 팔찌"))

	var noicon: Array = []
	for k in cat:
		if Icons.equip_texture(cat[k]) == null:
			noicon.append(String(k))
	fails += _eq("카탈로그 전체가 아이콘 보유", noicon.size(), 0)
	if not noicon.is_empty():
		_say("      아이콘 없음: %s" % str(noicon.slice(0, 8)))

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730
	var ghost := 0
	for _i in 3000:
		var key := DR.roll_equip_gacha(Data.drops, Data.equipment, rng)
		var ck := EQ.parse_item_key(key)
		if ck == "" or not cat.has(ck):
			ghost += 1
	fails += _eq("장신구 뽑기 3000회 중 카탈로그 밖 = 0", ghost, 0)
	var exclusive_pool := DR._exclusive_pool(Data.equipment)
	var exclusive_names: Array = []
	for x in exclusive_pool:
		exclusive_names.append(String((x as Dictionary).get("name", "")))
	fails += _eq("전용 뽑기 풀은 원작 전용 장비 95종", exclusive_pool.size(), 95)
	fails += _true("샛별 장비는 전용 뽑기 제외", not exclusive_names.has("샛별의 날개장식"))
	fails += _true("한울 장비는 전용 뽑기 제외", not exclusive_names.has("한울의 불꽃"))
	var only_bad := 0
	var only_ok := 0
	var custom_leak := 0
	for _i in 500:
		var ck2 := EQ.parse_item_key(DR.roll_equip_gacha(Data.drops, Data.equipment, rng, "only"))
		var it2: Dictionary = cat.get(ck2, {})
		if String(it2.get("group", "")) == "exclusive":
			only_ok += 1
			if ck2 in ["exclusive:샛별의 날개장식", "exclusive:한울의 불꽃"]:
				custom_leak += 1
		else:
			only_bad += 1
	fails += _eq("전용 뽑기 500회가 전부 전용 장비", only_bad, 0)
	fails += _true("전용 뽑기가 실제로 나온다 (%d건)" % only_ok, only_ok > 0)
	fails += _eq("전용 뽑기에 샛별·한울 장비 누출 = 0", custom_leak, 0)
	var leak := 0
	for _i in 1000:
		for gid in ["normal", "high"]:
			var ck3 := EQ.parse_item_key(DR.roll_equip_gacha(Data.drops, Data.equipment, rng, gid))
			if String((cat.get(ck3, {}) as Dictionary).get("group", "")) == "exclusive":
				leak += 1
	fails += _eq("일반·고급 뽑기에 전용 장비 누출 = 0", leak, 0)
	fails += _grade_split(cat, rng)
	return fails

func _grade_split(cat: Dictionary, rng: RandomNumberGenerator) -> int:
	var fails := 0
	_say("[장신구 뽑기] 상품 등급별 풀")
	var stat := {"normal": {"ev": 0, "gmax": -1, "rar": 0}, "high": {"ev": 0, "gmin": 99, "rar_lo": 0}}
	for _i in 3000:
		for gid in ["normal", "high"]:
			var key := DR.roll_equip_gacha(Data.drops, Data.equipment, rng, String(gid))
			var ck := EQ.parse_item_key(key)
			if ck == "":
				continue
			var meta := EQ.item_key_meta(key)
			var grade := int((cat.get(ck, {}) as Dictionary).get("grade", -1))
			var s: Dictionary = stat[gid]
			if ck.begins_with("event:"):
				s["ev"] = int(s["ev"]) + 1
			if gid == "normal":
				s["gmax"] = maxi(int(s["gmax"]), grade)
				if int(meta.get("rarity", 0)) != 0:
					s["rar"] = int(s["rar"]) + 1
			else:
				if grade >= 0:
					s["gmin"] = mini(int(s["gmin"]), grade)
				if int(meta.get("rarity", 0)) < 2:
					s["rar_lo"] = int(s["rar_lo"]) + 1
	fails += _eq("일반: 이벤트 장비 0건", int(stat["normal"]["ev"]), 0)
	fails += _eq("일반: 최고 등급 3 이하", int(stat["normal"]["gmax"]), 3)
	fails += _eq("일반: 희귀도는 전부 일반", int(stat["normal"]["rar"]), 0)
	fails += _true("고급: 이벤트 장비가 나온다 (%d건)" % int(stat["high"]["ev"]),
		int(stat["high"]["ev"]) > 0)
	fails += _true("고급: 일반 장비 최저 등급 4 이상 (실측 %d)" % int(stat["high"]["gmin"]),
		int(stat["high"]["gmin"]) >= 4)
	fails += _eq("고급: 레어 미만 0건", int(stat["high"]["rar_lo"]), 0)
	fails += _true("only 등급이 결과를 준다",
		DR.roll_equip_gacha(Data.drops, Data.equipment, rng, "only").length() > 0)
	var only_left := 0
	for t in (Data.shop.get("tabs", []) as Array):
		for g in ((t as Dictionary).get("gacha", []) as Array):
			if String((g as Dictionary).get("grade", "")) == "only":
				only_left += 1
	fails += _eq("상점에 전용 뽑기 상품 2개", only_left, 2)
	var special_bad := 0
	for _i in 500:
		var ck4 := EQ.parse_item_key(DR.roll_equip_gacha(Data.drops, Data.equipment, rng, "special"))
		if not String((cat.get(ck4, {}) as Dictionary).get("group", "")).begins_with("special:"):
			special_bad += 1
	fails += _eq("특수장비 뽑기 500회가 전부 특수 장비", special_bad, 0)
	var special_stock: Array = []
	for t in (Data.shop.get("tabs", []) as Array):
		for g in ((t as Dictionary).get("gacha", []) as Array):
			if String((g as Dictionary).get("grade", "")) == "special":
				special_stock.append(g)
	fails += _eq("상점에 특수장비 뽑기 상품 1개", special_stock.size(), 1)
	if special_stock.size() == 1:
		fails += _eq("특수장비 뽑기 가격", int((special_stock[0] as Dictionary).get("price", 0)), 777)
		fails += _true("특수장비 뽑기 재화 = colosseum_coin",
			String((special_stock[0] as Dictionary).get("cur", "")) == "colosseum_coin")
	return fails

func _dragon_locks() -> int:
	var fails := 0
	_say("[드래곤] 커스텀 세대 무작위 입수 차단")
	for id in LOCKED:
		fails += _true("%d 은 acquire_locked" % id, Data.dragon_acquire_locked(int(id)))

	var pool: Array = Data.dragon_ids_random()
	var leak: Array = []
	for id in LOCKED:
		if pool.has(int(id)):
			leak.append(int(id))
	fails += _eq("dragon_ids_random() 누출 = 0", leak.size(), 0)
	fails += _true("도감 목록엔 666·777 이 남아 있다",
		Data.dragon_ids().has(666) and Data.dragon_ids().has(777))

	var cand_leak: Array = []
	for star in [2, 3, 4, 5, 6]:
		for el in ["", "fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos"]:
			for id in EG.candidates(Data.dragons, int(star), String(el), {}, []):
				if LOCKED.has(int(id)):
					cand_leak.append(int(id))
	fails += _eq("EggGacha.candidates 누출 = 0", cand_leak.size(), 0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730
	var hit := 0
	var rolled := 0
	for key in ["mall_question_egg", "mall_question_egg2"]:
		var item: Dictionary = Data.items.get(key, {})
		for _i in 3000:
			var did := EG.roll(key, item, Data.gacha_eggs, Data.dragons, rng)
			if did > 0:
				rolled += 1
			if LOCKED.has(did):
				hit += 1
	fails += _true("개봉 표본 %d회 정상" % rolled, rolled > 5000)
	fails += _eq("의문의 알/빛문알 개봉에서 커스텀 종 = 0", hit, 0)
	return fails

func _eq(label: String, got: int, want: int) -> int:
	var ok := got == want
	_say("  %s %s: %d (기대 %d)" % ["OK " if ok else "FAIL", label, got, want])
	return 0 if ok else 1

func _true(label: String, ok: bool) -> int:
	_say("  %s %s" % ["OK " if ok else "FAIL", label])
	return 0 if ok else 1

func _say(s: String) -> void:
	print(s)
	if _log:
		_log.store_line(s)
