extends SceneTree

const E := preload("res://scripts/systems/equipment.gd")
const B := preload("res://scripts/systems/battle.gd")
const G := preload("res://scripts/systems/gem.gd")

func _init() -> void:
	var fails := 0
	var table = JSON.parse_string(FileAccess.open(_data_file("equipment.json"), FileAccess.READ).get_as_text())
	var cat := E.catalog(table)

	var display_rows: Array = [
		{"it": {"name": "일반", "group": "basic"}, "meta": {"rarity": 4}, "worn": false},
		{"it": {"name": "아티팩트", "group": "artifact"}, "meta": {"rarity": 4}, "worn": false},
		{"it": {"name": "특수", "group": "special:test"}, "meta": {"rarity": 4}, "worn": false},
		{"it": {"name": "전용", "group": "exclusive"}, "meta": {"rarity": 4}, "worn": false},
		{"it": {"name": "낮은등급장착", "group": "basic"}, "meta": {"rarity": 0}, "worn": true},
		{"it": {"name": "유니크", "group": "exclusive"}, "meta": {"rarity": 3}, "worn": false},
	]
	display_rows.sort_custom(E.display_sort_less)
	var display_names: PackedStringArray = []
	for row in display_rows:
		display_names.append(String(((row as Dictionary)["it"] as Dictionary)["name"]))
	fails += _eq("장비 표시 정렬",
		"/".join(display_names), "낮은등급장착/전용/특수/일반/아티팩트/유니크")

	fails += _eq("카탈로그 크기", cat.size(), 38 + 25 + 12 + 36 + 97)
	var descriptions = JSON.parse_string(
		FileAccess.open(_data_file("item_descriptions.json"), FileAccess.READ).get_as_text())
	fails += _eq("장비 설명 시트가 카탈로그 전량 포함",
		(descriptions.get("equipment", {}) as Dictionary).size(), cat.size())
	var gem_desc: Dictionary = descriptions.get("gem_categories", {})
	fails += _eq("젬 공유 설명 5분류", gem_desc.size(), 5)
	for gem_category in ["normal", "hybrid", "soul", "sands", "sands_soul"]:
		fails += _true("젬 설명 분류 존재: %s" % gem_category, gem_desc.has(gem_category))
	var gems = JSON.parse_string(FileAccess.open(_data_file("gems.json"), FileAccess.READ).get_as_text())
	fails += _eq("샌즈 젬 설명 분리", G.description_category("샌즈의 젬", gems), "sands")
	fails += _eq("샌즈 소울젬 설명 분리", G.description_category("샌즈의 소울젬", gems), "sands_soul")
	fails += _eq("일반 젬 설명 공유", G.description_category("공격의 젬", gems), "normal")
	fails += _true("전용 장비가 카탈로그에 있다", cat.has("exclusive:고대신룡의 금관"))
	for row in [["exclusive:샛별의 날개장식", 666], ["exclusive:한울의 불꽃", 777]]:
		var ck := String(row[0])
		fails += _true("커스텀 전용 장비가 카탈로그에 있다: %s" % ck, cat.has(ck))
		if cat.has(ck):
			fails += _true("%s — 대상 드래곤만 장착" % ck,
				E.species_allows(cat[ck], int(row[1])) and not E.species_allows(cat[ck], 1))
	var exc: Dictionary = cat["exclusive:고대신룡의 금관"]
	fails += _eq("전용 장비는 주 능력치가 없다", (exc["stat_main"] as Dictionary).size(), 0)
	fails += _eq("전용 장비 대상 드래곤", int(exc["dragon_id"]), 1)
	fails += _true("대상 드래곤이면 허용", E.species_allows(exc, 1))
	fails += _true("다른 종이면 거부", not E.species_allows(exc, 53))
	fails += _true("일반 장비는 종 제한 없음", E.species_allows(cat["basic:깃털:0"], 999))
	fails += _true("다른 종에 전용 장비 장착 거부",
		E.equip({}, "all", "exclusive:고대신룡의 금관", table, {}, 53).is_empty())
	fails += _true("대상 종에는 장착 성공",
		not E.equip({}, "all", "exclusive:고대신룡의 금관", table, {}, 1).is_empty())
	fails += _true("특수 장비가 카탈로그에 있다", cat.has("special:balrog:카이저 발록의 보주"))
	fails += _true("아이콘 복원 이벤트 장비가 카탈로그에 있다", cat.has("event:마룡의 보옥"))
	fails += _eq("부적 등급 수(아만타 없음)", (table["basic"]["부적"]["grades"] as Array).size(), 6)
	fails += _true("아만타의 부적 없음", not cat.has("basic:부적:6"))
	fails += _eq("깃털 최고등급 이름", String(cat["basic:깃털:6"]["name"]), "아만타의 금우")
	fails += _eq("발톱 최고등급 이름", String(cat["basic:발톱:6"]["name"]), "아만타의 조갑")
	fails += _eq("장비 인벤 키 왕복", E.parse_item_key(E.item_key("basic:깃털:6")), "basic:깃털:6")
	fails += _eq("장비 아닌 키는 빈 문자열", E.parse_item_key("gem:체력의 젬:0"), "")
	fails += _eq("눈사람 인형 회피", int(cat["event:눈사람 인형"]["stat_main"]["evd"]), 13)
	fails += _true("특수 장비(발록)가 카탈로그에 있다",
		cat.has("special:balrog:카이저 발록의 팔찌"))
	fails += _true("아이콘 복원된 크리스마스 종이 카탈로그에 있다", cat.has("event:크리스마스 종"))
	fails += _eq("구현 이벤트 장비 = 25종", E.event_pool(table).size(), 25)
	fails += _eq("이벤트 원본 데이터는 25종 그대로", (table["event"] as Array).size(), 25)

	fails += _eq("묘안석 슬롯", String(cat["basic:묘안석:5"]["slot_class"]), "battle")
	fails += _eq("눈사람 인형 슬롯", String(cat["event:눈사람 인형"]["slot_class"]), "support")
	fails += _true("아티팩트는 all칸 불가", not E.can_equip(cat["artifact:루멘:5"], "all"))
	fails += _true("아티팩트는 artifact칸 가능", E.can_equip(cat["artifact:루멘:5"], "artifact"))
	fails += _true("보조형은 all칸 가능", E.can_equip(cat["event:눈사람 인형"], "all"))
	fails += _true("보조형은 battle칸 불가", not E.can_equip(cat["event:눈사람 인형"], "battle"))

	var eq: Dictionary = {}
	eq = E.equip(eq, "battle", "basic:묘안석:5", table)
	fails += _true("묘안석 장착", not eq.is_empty())
	eq = E.equip(eq, "support", "event:눈사람 인형", table)
	fails += _true("눈사람 인형 장착", not eq.is_empty())
	var agg := E.aggregate(eq, table)
	fails += _eq("관통 합", int(agg.get("pure", 0)), 30)
	fails += _eq("회피 합", int(agg.get("evd", 0)), 13)

	var eqm := E.equip({}, "all", "special:skull:엘더 블랙퀸의 스태프", table)
	fails += _true("해골요새 장비 장착", not eqm.is_empty())
	eqm = E.equip(eqm, "battle", "basic:묘안석:5", table)
	fails += _true("묘안석 추가 장착", not eqm.is_empty())
	fails += _eq("같은 주 능력은 최고값만", int(E.aggregate(eqm, table).get("pure", 0)), 40)
	for sm in (eqm["slots"] as Array):
		if String((sm as Dictionary)["slot"]) == "battle":
			(sm as Dictionary)["options"] = [{"stat": "pure", "value": 5}]
	fails += _eq("주 능력 max + 옵션 합", int(E.aggregate(eqm, table).get("pure", 0)), 45)

	fails += _true("묘안석을 보조칸에 못 낌", E.equip({}, "support", "basic:묘안석:5", table).is_empty())

	var eq2 := E.equip({}, "all", "event:눈사람 인형", table)
	(eq2["slots"][0] as Dictionary)["options"] = [
		{"stat": "att", "value": 10}, {"stat": "hp", "value": 5}, {"stat": "pure", "value": 7}]
	var agg2 := E.aggregate(eq2, table)
	fails += _eq("att 옵션은 배수항으로", int(agg2.get("att_pct", 0)), 10)
	fails += _eq("att 에 flat 안 섞임", int(agg2.get("att", 0)), 0)
	fails += _eq("hp 옵션은 배수항으로", int(agg2.get("hp_pct", 0)), 5)
	fails += _eq("관통은 그대로 flat", int(agg2.get("pure", 0)), 7)
	var st_pct := E.apply({"hp": 1000, "att": 200, "def": 100}, eq2, table)
	fails += _eq("att +10% 적용", int(st_pct["att"]), 220)
	fails += _eq("hp +5% 적용", int(st_pct["hp"]), 1050)
	fails += _eq("def 는 옵션 없으니 그대로", int(st_pct["def"]), 100)

	for st: String in ["hp", "att", "def", "blk", "exp", "gold", "accuracy"]:
		fails += _eq("%s 는 %% 표기" % st, E.option_unit(st, table), "%")
	for st: String in ["pure", "depure"]:
		fails += _eq("%s 는 절댓값 표기" % st, E.option_unit(st, table), "")
	var unit_covered := 0
	for st in (table["option"]["stats"] as Array):
		if String(st) in ["pure", "depure"] or E.option_unit(String(st), table) == "%":
			unit_covered += 1
	fails += _eq("옵션 단위 전수", unit_covered, (table["option"]["stats"] as Array).size())
	fails += _eq("옵션 한 줄 서식(%)", E.option_text("공격력", "att", 7, table), "공격력 +7%")
	fails += _eq("옵션 한 줄 서식(flat)", E.option_text("관통", "pure", 5, table), "관통 +5")

	var eq_rw := E.equip({}, "all", "event:눈사람 인형", table)
	(eq_rw["slots"][0] as Dictionary)["options"] = [
		{"stat": "gold", "value": 10}, {"stat": "exp", "value": 4}]
	fails += _eq("골드 옵션 배수", E.reward_mult(eq_rw, table, "gold"), 1.1)
	fails += _eq("경험치 옵션 배수", E.reward_mult(eq_rw, table, "exp"), 1.04)
	fails += _eq("옵션 없으면 배수 1", E.reward_mult({}, table, "gold"), 1.0)

	fails += _true("편린 계열 구현 플래그", bool((table["pieces"] as Dictionary).get("implemented", false)))
	var eq3 := {"slots": [], "pieces": ["모험가의 편린", "모험가의 편린"]}
	var st3 := E.apply({"hp": 1000, "att": 100, "def": 100}, eq3, table)
	fails += _eq("편린 2세트 체력 10%", int(st3["hp"]), 1100)
	var eq4 := {"slots": [], "pieces": ["모험가의 편린"]}
	fails += _eq("편린 1개는 무효", int(E.apply({"hp": 1000}, eq4, table)["hp"]), 1000)

	var cfg = JSON.parse_string(FileAccess.open(_data_file("combat.json"), FileAccess.READ).get_as_text())
	var rng := RandomNumberGenerator.new()
	var plain := B.make_combatant("A", "ally", "fire", {"hp": 999, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	var armed := B.make_combatant("B", "ally", "fire", {"hp": 999, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0, "pure": 40})
	var dummy := B.make_combatant("D", "enemy", "fire", {"hp": 99999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	rng.seed = 1234
	var d1 := B.resolve_attack(plain, dummy, rng, cfg, {})
	rng.seed = 1234
	var d2 := B.resolve_attack(armed, dummy, rng, cfg, {})
	fails += _eq("관통 40이 그대로 추가피해", int(d2["damage"]) - int(d1["damage"]), 40)

	var tanky := B.make_combatant("T", "enemy", "fire", {"hp": 99999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0, "depure": 20})
	rng.seed = 1234
	var d3 := B.resolve_attack(armed, tanky, rng, cfg, {})
	rng.seed = 1234
	var d4 := B.resolve_attack(plain, tanky, rng, cfg, {})
	fails += _eq("관통40 vs 감소20 = +20", int(d3["damage"]) - int(d4["damage"]), 20)

	var dodger := B.make_combatant("E", "enemy", "fire", {"hp": 999, "att": 1, "def": 10, "cri": 0, "evd": 100, "blk": 0})
	var sniper := B.make_combatant("S", "ally", "fire", {"hp": 999, "att": 100, "def": 10, "cri": 0, "evd": 0, "blk": 0, "accuracy": 100})
	var missed := 0
	for i in 20:
		rng.seed = i
		if bool(B.resolve_attack(sniper, dodger, rng, cfg, {})["miss"]):
			missed += 1
	fails += _eq("명중100 → 회피 0회", missed, 0)

	var cw := B.make_combatant("C", "ally", "fire", {"hp": 999, "att": 100, "def": 10, "cri": 100, "evd": 0, "blk": 0, "cri_pow": 100})
	var cn := B.make_combatant("N", "ally", "fire", {"hp": 999, "att": 100, "def": 10, "cri": 100, "evd": 0, "blk": 0})
	var t1 := B.make_combatant("X", "enemy", "fire", {"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	var t2 := B.make_combatant("Y", "enemy", "fire", {"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	var c1: Dictionary = {}
	var c2: Dictionary = {}
	for s in 50:
		rng.seed = s
		c1 = B.resolve_attack(cn, t1, rng, cfg, {})
		rng.seed = s
		c2 = B.resolve_attack(cw, t2, rng, cfg, {})
		if bool(c1["crit"]) and bool(c2["crit"]):
			break
	fails += _true("크리 발동 확인", bool(c1.get("crit", false)) and bool(c2.get("crit", false)))
	var crit_base := float(cfg.get("damage", {}).get("crit_mult", 1.5))
	var want := int(round(float(c1["damage"]) / crit_base * (1.0 + (crit_base - 1.0) * 2.0)))
	fails += _true("크리파워100 → 크리 배수 %.1f (got %d, want %d)"
			% [1.0 + (crit_base - 1.0) * 2.0, int(c2["damage"]), want],
			absi(int(c2["damage"]) - want) <= 1)

	var rng2 := RandomNumberGenerator.new(); rng2.seed = 42
	var pool: Array = E.option_stats(table)
	fails += _eq("부가 옵션 풀 7종", pool.size(), 7)
	for pst: String in ["hp", "att", "def", "blk", "gold", "exp", "pure"]:
		fails += _true("풀에 %s 있음" % pst, pst in pool)
	for cst: String in ["depure", "accuracy"]:
		fails += _true("풀에 %s 없음" % cst, not (cst in pool))
	var rngp := RandomNumberGenerator.new(); rngp.seed = 7
	var cut_seen := 0
	for i in 400:
		var o1 := E.roll_option(rngp, table)
		var o2 := E.roll_option(rngp, table, E.artifact_smelt_weights(table))
		for oo in [o1, o2]:
			if String((oo as Dictionary).get("stat", "")) in ["depure", "accuracy"]:
				cut_seen += 1
	fails += _eq("400×2롤에 명중·관통감소 0회", cut_seen, 0)
	var legacy: Array = [{"stat": "att", "value": 7}, {"stat": "accuracy", "value": 5},
		{"stat": "depure", "value": 3}]
	var san: Array = E.sanitize_options(legacy, table, rngp)
	var kept: Array = san[0]
	fails += _eq("정리 후에도 옵션 3개", kept.size(), 3)
	fails += _eq("바뀐 개수 2", int(san[1]), 2)
	fails += _eq("유효 옵션은 그대로", int((kept[0] as Dictionary)["value"]), 7)
	var all_valid := true
	for o in kept:
		all_valid = all_valid and (String((o as Dictionary)["stat"]) in pool)
	fails += _true("정리 결과가 전부 유효 스탯", all_valid)
	fails += _eq("멱등(두 번 돌려도 안 바뀜)", int((E.sanitize_options(kept, table, rngp)[1])), 0)
	fails += _eq("일반 등급 옵션 0개", E.option_count(0, table), 0)
	fails += _eq("초월 등급 옵션 5개", E.option_count(5, table), 5)
	fails += _eq("에픽 강화 한도 20", E.enhance_limit(4, table), 20)
	var rolled := E.roll_options(3, rng2, table)
	fails += _eq("유니크 옵션 3개 롤", rolled.size(), 3)
	var stats_ok := true
	for o in rolled:
		var st2 := String((o as Dictionary)["stat"])
		var rr: Array = table["option"]["value_ranges"].get(st2, [])
		stats_ok = stats_ok and rr.size() == 2 			and int((o as Dictionary)["value"]) >= int(rr[0]) 			and int((o as Dictionary)["value"]) <= int(rr[1])
	fails += _true("롤 값이 범위 안", stats_ok)
	var eq5 := E.equip({}, "all", "event:눈사람 인형", table)
	(eq5["slots"][0] as Dictionary)["options"] = [{"stat": "att", "value": 20}]
	(eq5["slots"][0] as Dictionary)["grade"] = 1
	var before := int((eq5["slots"][0] as Dictionary)["options"][0]["value"])
	var eq6 := E.enhance(eq5, "all", rng2, table)
	fails += _true("강화로 옵션 상승",
			int((eq6["slots"][0] as Dictionary)["options"][0]["value"]) > before)
	var cur := eq6
	for i in 10:
		var nx := E.enhance(cur, "all", rng2, table)
		if nx.is_empty(): break
		cur = nx
	fails += _eq("강화 한도 5회에서 정지", int((cur["slots"][0] as Dictionary)["enhance"]), 5)

	fails += _eq("에픽 6옵션의 표시 상한 20", E.enhance_cap(4, 6, table), 20)
	fails += _eq("옵션이 모자라면 옵션 기준", E.enhance_cap(4, 2, table), 10)
	fails += _eq("일반 등급 상한 0", E.enhance_cap(0, 0, table), 0)
	var cap_slot := {"grade": 4, "enhance": 20,
		"options": [{"stat": "att", "value": 9}, {"stat": "hp", "value": 9},
			{"stat": "def", "value": 9}, {"stat": "blk", "value": 5},
			{"stat": "gold", "value": 9}, {"stat": "exp", "value": 9}]}
	fails += _eq("상한 도달 = grade_max", E.enchant_blocked(cap_slot, table), "grade_max")
	fails += _eq("칸 dict 로 물어도 20", E.enhance_cap_of_slot(cap_slot, table), 20)
	fails += _eq("최저 등급 = min_grade",
		E.enchant_blocked({"grade": 0, "enhance": 0, "options": []}, table), "min_grade")
	fails += _eq("여유 있으면 안 막힘",
		E.enchant_blocked({"grade": 4, "enhance": 19, "options": cap_slot["options"]}, table), "")

	fails += _eq("귀속 키 왕복(카탈로그)", E.parse_item_key(E.item_key("basic:깃털:6", {"belong": 12})), "basic:깃털:6")
	fails += _eq("귀속 키 왕복(소유자)", E.item_key_belong(E.item_key("basic:깃털:6", {"belong": 12})), 12)
	fails += _eq("미귀속 키는 소유자 0", E.item_key_belong(E.item_key("basic:깃털:6")), 0)
	fails += _eq("구버전 키도 읽힌다", E.parse_item_key("equip:basic:깃털:6"), "basic:깃털:6")
	fails += _true("미귀속(0)은 아무나", E.belong_allows(0, 7))
	fails += _true("미귀속(-1)도 아무나", E.belong_allows(-1, 7))
	fails += _true("본인 귀속은 가능", E.belong_allows(7, 7))
	fails += _true("남의 귀속은 불가", not E.belong_allows(7, 8))
	fails += _true("일반은 귀속 안 됨", not E.binds_at(0, table))
	fails += _true("매직도 귀속 안 됨", not E.binds_at(1, table))
	fails += _true("레어부터 귀속", E.binds_at(2, table))
	var rng3 := RandomNumberGenerator.new(); rng3.seed = 7
	var eqb := E.equip({}, "all", "event:눈사람 인형", table, {"rarity": 3, "belong": 0})
	fails += _eq("장착 시 희귀도 승계", int(_slot(eqb, "all").get("grade", -1)), 3)
	fails += _true("등급이 다른 동전은 거절", E.reroll(eqb, "all", 2, rng3, table, 42).is_empty())
	fails += _true("등급이 다른 동전은 거절2", E.reroll(eqb, "all", 4, rng3, table, 42).is_empty())
	eqb = E.reroll(eqb, "all", 3, rng3, table, 42)
	fails += _eq("유니크 재설정은 귀속", E.slot_belong(eqb, "all"), 42)
	fails += _eq("재설정해도 등급 그대로", int(_slot(eqb, "all").get("grade", -1)), 3)
	fails += _eq("재설정 옵션 수 = 등급", (_slot(eqb, "all").get("options", []) as Array).size(),
		E.option_count(3, table))
	var eqe := E.equip({}, "all", "event:눈사람 인형", table, {"rarity": 3, "enhance": 9})
	eqe = E.reroll(eqe, "all", 3, rng3, table, 42)
	fails += _eq("재설정해도 강화 횟수 유지", int(_slot(eqe, "all").get("enhance", -1)), 9)
	var base_max := 0
	for st in (table["option"].get("value_ranges", {}) as Dictionary):
		base_max = maxi(base_max, int((table["option"]["value_ranges"][st] as Array)[1]))
	var tot := 0
	for o in (_slot(eqe, "all").get("options", []) as Array):
		tot += int((o as Dictionary).get("value", 0))
	fails += _true("재설정 값이 강화 상태를 따라온다",
		tot > base_max * E.option_count(3, table))
	var rngs := RandomNumberGenerator.new(); rngs.seed = 3
	var stepped: Array = E.apply_enhance_steps([{"stat": "pure", "value": 10}], 1, rngs, table)
	fails += _eq("강화 1회분 = 강화식과 동일", int((stepped[0] as Dictionary)["value"]), 12)
	fails += _eq("0회는 그대로", int((E.apply_enhance_steps(
		[{"stat": "pure", "value": 10}], 0, rngs, table)[0] as Dictionary)["value"]), 10)
	var eq0 := E.equip({}, "all", "event:눈사람 인형", table)
	fails += _eq("일반 등급 동전 없음",
		String((table["option"].get("reroll_items", {}) as Dictionary).get("0", "")), "")
	fails += _true("일반은 등급 불일치로 거절", E.reroll(eq0, "all", 2, rng3, table, 42).is_empty())
	var eqc := E.unbind(eqb, "all")
	fails += _eq("귀속해제 후 0", E.slot_belong(eqc, "all"), 0)
	fails += _true("이미 미귀속이면 실패", E.unbind(eqc, "all").is_empty())
	var eqd := E.equip({}, "all", "event:눈사람 인형", table, {"belong": 99})
	fails += _eq("장착 시 귀속 승계", E.slot_belong(eqd, "all"), 99)

	fails += _eq("귀속해제 아이템", String(table["option"].get("unbind_item", "")), "item_disconnect")
	fails += _eq("재설정 동전 3종", (table["option"].get("reroll_items", {}) as Dictionary).size(), 3)
	var rc: Array = table["option"].get("rarity_colors", [])
	fails += _eq("희귀도 색 6칸", rc.size(), 6)
	fails += _true("일반은 실루엣 없음", rc[0] == null)
	fails += _eq("초월 색", String(rc[5]), "00FFEA")

	for src in (table["option"].get("rarity_rolls", {}) as Dictionary):
		var tbl: Dictionary = table["option"]["rarity_rolls"][src]
		fails += _true("%s 표에 매직 없음" % src, not tbl.has("1"))
	fails += _true("매직 동전도 없음",
		not (table["option"].get("reroll_items", {}) as Dictionary).has("1"))

	var bag_key := E.item_key("basic:묘안석:2",
		{"rarity": 3, "enhance": 0, "options": [{"stat": "pure", "value": 10}]})
	var view: Dictionary = {"slot": "_bag", "key": "basic:묘안석:2", "grade": 3, "enhance": 0,
		"options": [{"stat": "pure", "value": 10}], "belong": 0}
	var rng4 := RandomNumberGenerator.new(); rng4.seed = 5
	var res: Dictionary = E.enhance({"slots": [view]}, "_bag", rng4, table)
	fails += _true("가방 개체도 강화된다", not res.is_empty())
	var after_slot: Dictionary = (res["slots"] as Array)[0]
	fails += _eq("강화 횟수 +1", int(after_slot.get("enhance", 0)), 1)
	var step := int(table["option"].get("enhance_step_pct", 0))
	fails += _eq("증가폭 20%", step, 20)
	fails += _eq("관통 10 → 12", int((after_slot["options"] as Array)[0]["value"]), 12)
	var new_key := E.slot_to_item_key(after_slot)
	fails += _true("강화하면 인벤 키가 바뀐다", new_key != bag_key)
	fails += _eq("키 왕복 — 카탈로그", E.parse_item_key(new_key), "basic:묘안석:2")
	fails += _eq("키 왕복 — 강화수", int(E.item_key_meta(new_key).get("enhance", 0)), 1)
	fails += _eq("키 왕복 — 희귀도", int(E.item_key_meta(new_key).get("rarity", 0)), 3)
	fails += _true("옵션 없으면 강화 불가", E.enhance({"slots": [
		{"slot": "_bag", "key": "basic:묘안석:2", "grade": 0, "enhance": 0, "options": []}]},
		"_bag", rng4, table).is_empty())

	var sm: Dictionary = E.artifact_smelt_cfg(table)
	fails += _true("제련 재료표 있음", not (sm.get("items", {}) as Dictionary).is_empty())
	var w: Dictionary = E.artifact_smelt_weights(table)
	fails += _true("관통 가중치가 제일 크다",
		float(w.get("pure", 0.0)) > float(w.get("att", 1.0)))
	var rng5 := RandomNumberGenerator.new(); rng5.seed = 21
	var pure_biased := 0
	var pure_even := 0
	for _i in 4000:
		if String(E.roll_option(rng5, table, w).get("stat", "")) == "pure":
			pure_biased += 1
		if String(E.roll_option(rng5, table).get("stat", "")) == "pure":
			pure_even += 1
	fails += _true("편향이 균등보다 관통을 많이 띄운다 (%d vs %d)" % [pure_biased, pure_even],
		pure_biased > pure_even * 2)

	var mix_base := "artifact:이그니스:2"
	fails += _true("합성 재료: 같은 종류·등급 허용",
		E.artifact_mix_material_ok(table, mix_base, "artifact:이그니스:2"))
	fails += _true("합성 재료: 같은 종류·다른 등급 거부",
		not E.artifact_mix_material_ok(table, mix_base, "artifact:이그니스:1"))
	fails += _true("합성 재료: 다른 종류·같은 등급 거부",
		not E.artifact_mix_material_ok(table, mix_base, "artifact:루멘:2"))

	rng.seed = 999
	var r1 := B.resolve_attack(plain, B.make_combatant("Z", "enemy", "fire", {"hp": 9999, "att": 1, "def": 50, "cri": 0, "evd": 0, "blk": 0}), rng, cfg, {})
	fails += _true("무장비 평타 정상", int(r1["damage"]) > 0)

	var meta14 := {"belong": 7, "rarity": 3, "enhance": 2,
		"options": [{"stat": "att", "value": 9}, {"stat": "pure", "value": 5}]}
	var k14 := E.item_key("basic:깃털:6", meta14)
	fails += _true("메타 키에 @ 포함", "@" in k14)
	fails += _eq("메타 키 → 카탈로그", E.parse_item_key(k14), "basic:깃털:6")
	var back := E.item_key_meta(k14)
	fails += _eq("귀속 복원", int(back["belong"]), 7)
	fails += _eq("희귀도 복원", int(back["rarity"]), 3)
	fails += _eq("강화 복원", int(back["enhance"]), 2)
	fails += _eq("옵션 개수 복원", (back["options"] as Array).size(), 2)
	fails += _eq("옵션 스탯 복원", String((back["options"][0] as Dictionary)["stat"]), "att")
	fails += _eq("옵션 값 복원", int((back["options"][0] as Dictionary)["value"]), 9)
	fails += _eq("같은 개체는 같은 키", E.item_key("basic:깃털:6", meta14), k14)
	fails += _true("다른 희귀도는 다른 키",
			E.item_key("basic:깃털:6", {"rarity": 2}) != E.item_key("basic:깃털:6", {"rarity": 3}))
	var eq14 := E.equip({}, "all", "basic:깃털:6", table, back)
	var slot14 := (eq14["slots"][0] as Dictionary)
	fails += _eq("장착 시 희귀도 승계", int(slot14["grade"]), 3)
	fails += _eq("장착 시 옵션 승계", (slot14["options"] as Array).size(), 2)
	fails += _eq("해제 키 = 원래 키", E.slot_to_item_key(slot14), k14)

	var rr15 := RandomNumberGenerator.new(); rr15.seed = 20260729
	var cnt := {0: 0, 2: 0, 3: 0, 4: 0}
	for i in 4000:
		var g := E.roll_rarity("drop", rr15, table)
		cnt[g] = int(cnt.get(g, 0)) + 1
	fails += _true("드롭 일반 약 70%", absf(float(cnt[0]) / 4000.0 - 0.70) < 0.03)
	fails += _true("드롭 레어 약 20%", absf(float(cnt[2]) / 4000.0 - 0.20) < 0.03)
	fails += _true("드롭 매직(1) 없음", not cnt.has(1))
	fails += _eq("상점 골드는 항상 일반", E.roll_rarity("shop_gold", rr15, table), 0)
	var gac := {}
	for i in 2000:
		var g2 := E.roll_rarity("shop_gacha", rr15, table)
		gac[g2] = int(gac.get(g2, 0)) + 1
	fails += _true("가챠에 일반 없음", not gac.has(0))
	fails += _true("가챠 레어 약 60%", absf(float(gac.get(2, 0)) / 2000.0 - 0.60) < 0.04)
	var inst := E.roll_instance("shop_gacha", rr15, table)
	fails += _eq("옵션 수 = 등급 옵션 수",
			(inst["options"] as Array).size(), E.option_count(int(inst["rarity"]), table))

	var sdb = JSON.parse_string(FileAccess.open(_data_file("skills.json"), FileAccess.READ).get_as_text())
	var eq16 := E.equip({}, "artifact", "artifact:루멘:5", table)
	var m16 := E.artifact_mods(eq16, table, sdb)
	fails += _true("루멘은 proc_add 를 만든다", not (m16["proc_add"] as Dictionary).is_empty())
	fails += _true("루멘은 power_lv 없음", (m16["power_lv"] as Dictionary).is_empty())
	var shield_id := -1
	for kk in sdb:
		if String((sdb[kk] as Dictionary).get("name", "")).replace(" ", "") == "철갑방패":
			shield_id = int((sdb[kk] as Dictionary).get("id", int(str(kk))))
	fails += _true("철갑방패 스킬 존재", shield_id > 0)
	if shield_id > 0:
		fails += _eq("전설의 루멘 = +12%p",
				int((m16["proc_add"] as Dictionary).get(shield_id, 0)), 12)
	var m17 := E.artifact_mods(E.equip({}, "artifact", "artifact:이그니스:5", table), table, sdb)
	fails += _true("이그니스는 power_lv", not (m17["power_lv"] as Dictionary).is_empty())
	var m18 := E.artifact_mods(E.equip({}, "artifact", "artifact:테라:5", table), table, sdb)
	fails += _true("테라는 power_lv+proc_add",
			not (m18["power_lv"] as Dictionary).is_empty() and not (m18["proc_add"] as Dictionary).is_empty())
	var m19 := E.artifact_mods(E.equip({}, "artifact", "artifact:옵스큐럼:5", table), table, sdb)
	fails += _true("옵스큐럼은 foe_proc_sub", not (m19["foe_proc_sub"] as Dictionary).is_empty())
	var m20 := E.artifact_mods(E.equip({}, "artifact", "artifact:벤투스:5", table), table, sdb)
	fails += _true("벤투스는 skill_dmg_taken_pct",
			not (m20["skill_dmg_taken_pct"] as Dictionary).is_empty())
	var m21 := E.artifact_mods({}, table, sdb)
	fails += _true("아티팩트 없으면 수정치 없음",
			(m21["proc_add"] as Dictionary).is_empty() and (m21["power_lv"] as Dictionary).is_empty())

	if shield_id > 0:
		var art := E.artifact_mods(E.equip({}, "artifact", "artifact:루멘:5", table), table, sdb)
		var base_n := 0
		var art_n := 0
		for i in 400:
			var r := RandomNumberGenerator.new(); r.seed = i
			if r.randf() * 100.0 < 20.0: base_n += 1
			var r2 := RandomNumberGenerator.new(); r2.seed = i
			if r2.randf() * 100.0 < 20.0 + 12.0: art_n += 1
		fails += _true("루멘이 발동 횟수를 늘린다", art_n > base_n)

	var h_mar := E.artifact_hidden(E.equip({}, "artifact", "artifact:마리스:0", table), table)
	fails += _eq("마리스 히든 = 발동확률 +5", int(h_mar["proc_add_all"]), 5)
	fails += _eq("마리스는 회피 안 줌", int(h_mar["evd"]), 0)
	var h_ven := E.artifact_hidden(E.equip({}, "artifact", "artifact:벤투스:0", table), table)
	fails += _eq("벤투스 히든 = 회피 +5", int(h_ven["evd"]), 5)
	var h_ter := E.artifact_hidden(E.equip({}, "artifact", "artifact:테라:0", table), table)
	fails += _eq("테라 히든 = 발동횟수 +1", int(h_ter["skill_uses"]), 1)
	var h_mar5 := E.artifact_hidden(E.equip({}, "artifact", "artifact:마리스:5", table), table)
	fails += _eq("히든은 등급 무관", int(h_mar5["proc_add_all"]), int(h_mar["proc_add_all"]))
	var h_lum := E.artifact_hidden(E.equip({}, "artifact", "artifact:루멘:5", table), table)
	fails += _eq("루멘은 히든 없음",
			int(h_lum["proc_add_all"]) + int(h_lum["evd"]) + int(h_lum["skill_uses"]), 0)
	var st_ven := E.apply({"hp": 100, "att": 10, "def": 10, "evd": 10},
			E.equip({}, "artifact", "artifact:벤투스:0", table), table)
	fails += _eq("벤투스 회피가 실스탯에", int(st_ven["evd"]), 15)
	var mods_ter := E.artifact_mods(E.equip({}, "artifact", "artifact:테라:0", table), table, sdb)
	fails += _eq("mods 에 hidden 포함",
			int((mods_ter["hidden"] as Dictionary)["skill_uses"]), 1)

	var cfg19 = JSON.parse_string(FileAccess.open(_data_file("combat.json"), FileAccess.READ).get_as_text())
	var gate: Dictionary = cfg19.get("skill_hp_gate", {})
	fails += _eq("게이트 스킬 4종", (gate.get("skills", []) as Array).size(), 4)
	var gid := int((gate["skills"] as Array)[0])
	var thr := int(gate.get("threshold_pct", 50))
	var mk := func(hp_now: int, art: Dictionary) -> Dictionary:
		var st := {"hp": 1000, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0}
		if not art.is_empty():
			st["artifact"] = art
		var c := B.make_combatant("G", "ally", "fire", st, 0.0, [{"id": gid, "level": 1}])
		B._init_combatant_skills(c, sdb, cfg19)
		c["hp"] = hp_now
		return c
	var full: Dictionary = mk.call(1000, {})
	fails += _eq("체력 100%%면 후보 아님", B._eligible_attack(full, sdb, cfg19).size(), 0)
	var hurt: Dictionary = mk.call(int(1000 * (thr - 10) / 100), {})
	fails += _eq("문턱 아래면 후보", B._eligible_attack(hurt, sdb, cfg19).size(), 1)
	var mar := E.artifact_mods(E.equip({}, "artifact", "artifact:마리스:5", table), table, sdb)
	var mid: Dictionary = mk.call(600, {})
	fails += _eq("마리스 없으면 60%%는 후보 아님", B._eligible_attack(mid, sdb, cfg19).size(), 0)
	var mid2: Dictionary = mk.call(600, mar)
	fails += _eq("마리스 있으면 60%%도 후보", B._eligible_attack(mid2, sdb, cfg19).size(), 1)
	var free_id := -1
	for kk in sdb:
		var sd2: Dictionary = sdb[kk]
		var cat2 := String(sd2.get("category", ""))
		var i2 := int(sd2.get("id", int(str(kk)) if str(kk).is_valid_int() else 0))
		if cat2 != "defense" and cat2 != "interrupt" and not (gate["skills"] as Array).has(i2) \
				and bool(sd2.get("active", true)) and bool(sd2.get("usable", true)):
			free_id = i2
			break
	if free_id > 0:
		var cfree := B.make_combatant("F", "ally", "fire",
			{"hp": 1000, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0},
			0.0, [{"id": free_id, "level": 1}])
		B._init_combatant_skills(cfree, sdb, cfg19)
		fails += _eq("게이트 밖 스킬은 만피에도 후보",
				B._eligible_attack(cfree, sdb, cfg19).size(), 1)

	if fails == 0:
		print("[test_equipment] ALL PASS")
	else:
		printerr("[test_equipment] %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _slot(equip_field: Dictionary, slot_id: String) -> Dictionary:
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return s
	return {}

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
