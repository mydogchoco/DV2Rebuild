extends SceneTree
## 헤드리스 Gem 단위 테스트 (§8 — logic은 화면 없이 검증).
## 원작 근거: 젬 슬롯 3칸 + typeDetail 코드(docs/ref/orig_code/decomp/Dragon.c), 값=data/gems.json(위키 전량).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_gem.gd

const G := preload("res://scripts/systems/gem.gd")

func _init() -> void:
	var fails := 0
	var table = JSON.parse_string(FileAccess.open("res://data/gems.json", FileAccess.READ).get_as_text())

	# 0) 데이터 무결성 — 14종, 일반/혼성 19티어, 소울 10단계.
	var gems: Dictionary = table["gems"]
	fails += _eq("젬 종류 수", gems.size(), 14)
	for n in gems:
		var gd: Dictionary = gems[n]
		var want := 10 if String(gd["category"]) == "soul" else 19
		fails += _eq("%s 티어수" % n, (gd["tiers"] as Array).size(), want)
	fails += _eq("슬롯 수", int(table["slots"]), G.SLOTS)

	# 1) 혼성젬은 두 스탯을 모두 준다(구 스키마가 잃던 부분).
	var hpatt := G.tier_stats("체공젬", 18, table)
	fails += _eq("체공젬 최종 hp", int(hpatt.get("hp", 0)), 112)
	fails += _eq("체공젬 최종 att", int(hpatt.get("att", 0)), 13)

	# 2) 소울젬은 flat + % + 부가확률을 함께 준다.
	var soul := G.tier_stats("공격의 소울젬", 9, table)
	fails += _eq("공소울 flat", int(soul.get("att", 0)), 40)
	fails += _eq("공소울 pct", int(soul.get("att_pct", 0)), 18)
	fails += _eq("공소울 cri", int(soul.get("cri", 0)), 5)

	# 3) 장착 — 슬롯 3칸까지만.
	var f: Dictionary = {}
	for i in 4:
		var nx: Dictionary = G.equip(f, "체력의 젬", 0, table)
		if i < 3:
			fails += _true("슬롯 %d 장착" % i, not nx.is_empty())
			f = nx
		else:
			fails += _true("4번째 장착 거부", nx.is_empty())
	fails += _eq("장착 수", G.slots(f).size(), 3)

	# 4) 집계 + 적용 — flat 가산 후 % 배수, 부가확률 가산.
	#    공격의 소울젬 10단계(att+40, +18%, cri+5) 하나만 낀 상태에서 att 100 → (100+40)*1.18 = 165.2 → 165.
	var one: Dictionary = G.equip({}, "공격의 소울젬", 9, table)
	var st := G.apply({"hp": 500, "att": 100, "def": 50, "cri": 10, "evd": 10, "blk": 10}, one, table)
	fails += _eq("소울젬 att 적용", int(st["att"]), 165)
	fails += _eq("소울젬 cri 적용", int(st["cri"]), 15)
	fails += _eq("소울젬 hp 무영향", int(st["hp"]), 500)

	# 5) 강화 — 티어 1 상승, 최대에서 실패.
	var up: Dictionary = G.upgrade_at(one, 0, table)
	fails += _true("최대 단계에서 강화 실패", up.is_empty())
	var low: Dictionary = G.equip({}, "체력의 젬", 0, table)
	var up2: Dictionary = G.upgrade_at(low, 0, table)
	fails += _eq("강화 후 티어", int(G.slots(up2)[0]["tier"]), 1)

	# 6) 승급 — 원형(최대 티어) 혼성젬만 소울젬이 된다.
	var hyb: Dictionary = G.equip({}, "체공젬", 18, table)
	var pro: Dictionary = G.promote_at(hyb, 0, table)
	fails += _eq("체공젬 승급 결과", String(G.slots(pro)[0]["name"]), "체력의 소울젬")
	var hyb_low: Dictionary = G.equip({}, "체공젬", 5, table)
	fails += _true("미최대 승급 거부", G.promote_at(hyb_low, 0, table).is_empty())

	# 7) 구형 저장 형식(_name_<stat>/_tier_<stat>) 자동 마이그레이션.
	var old := {"hp": 84, "_slots": 1, "_tier_hp": 9, "_name_hp": "체력의 젬"}
	var mig := G.slots(old)
	fails += _eq("구형 마이그레이션 수", mig.size(), 1)
	fails += _eq("구형 마이그레이션 티어", int(mig[0]["tier"]), 9)
	fails += _eq("구형 값 재계산", int(G.aggregate(old, table)["flat"]["hp"]), 84)

	# 8) 해제.
	fails += _eq("해제 후 수", G.slots(G.unequip_at(f, 0)).size(), 2)

	# 9) 인벤토리 가상 키(젬 인벤 도입 2026-07-27). 젬 이름에 ':' 이 없다는 가정 없이 왕복해야 한다.
	fails += _eq("젬 인벤 키", G.item_key("체력의 젬", 7), "gem:체력의 젬:7")
	var rt := G.parse_item_key("gem:체력의 젬:7")
	fails += _eq("왕복 이름", String(rt.get("name", "")), "체력의 젬")
	fails += _eq("왕복 티어", int(rt.get("tier", -1)), 7)
	fails += _true("젬 아닌 키는 빈 dict", G.parse_item_key("equip:basic:깃털:6").is_empty())
	fails += _true("접두어만 있는 키 거부", G.parse_item_key("gem:").is_empty())

	# 10) 슬롯 타입(원작 Dragon::getGemType + GemsPopup::setGemsList 필터) — 2026-07-27 도입.
	fails += _eq("타입 없으면 ALL 폴백", G.types({}), ["ALL", "ALL", "ALL"])
	fails += _eq("타입 길이 보정", G.types({"types": ["ATT"]}), ["ATT", "ALL", "ALL"])
	# 허용표: ATT 칸엔 공격계열만. 체력의 젬(HP)은 못 들어간다.
	fails += _true("ATT칸 ← 공격의 젬", G.accepts("ATT", "공격의 젬", table))
	fails += _true("ATT칸 ← 공방젬(ATTDEF)", G.accepts("ATT", "공방젬", table))
	fails += _true("ATT칸 ← 공격의 소울젬", G.accepts("ATT", "공격의 소울젬", table))
	fails += _true("ATT칸 ← 샌즈의 젬(ATTDEFHP)", G.accepts("ATT", "샌즈의 젬", table))
	fails += _true("ATT칸 ✗ 체력의 젬", not G.accepts("ATT", "체력의 젬", table))
	fails += _true("ATT칸 ✗ 체공젬(HPATT)", not G.accepts("ATT", "체공젬", table))
	# 샌즈의 소울젬(SOULALL)은 **세 칸 모두** 받는다. 원작 코드는 ATT 분기에만 비교가
	# 빠져 있었는데(DEF·HP 는 있다) 오타로 판단 — 사용자 확정(2026-07-27)으로 정정했다.
	fails += _true("ATT칸 ← 샌즈의 소울젬(오타 정정)", G.accepts("ATT", "샌즈의 소울젬", table))
	fails += _true("DEF칸 ← 샌즈의 소울젬", G.accepts("DEF", "샌즈의 소울젬", table))
	fails += _true("HP칸 ← 샌즈의 소울젬", G.accepts("HP", "샌즈의 소울젬", table))
	fails += _true("ALL칸은 전부 허용", G.accepts("ALL", "체공젬", table) and G.accepts("ALL", "샌즈의 소울젬", table))
	# 칸 지정 장착 — 타입 불일치는 거부, 일치는 그 칸에 정확히 들어간다.
	var typed := {"types": ["ATT", "HP", "ALL"], "slots": [null, null, null]}
	fails += _true("불일치 칸 장착 거부", G.equip_at(typed, 0, "체력의 젬", 0, table).is_empty())
	var e1 := G.equip_at(typed, 1, "체력의 젬", 0, table)
	fails += _eq("지정 칸에 들어감", String(G.entries(e1)[1]["name"]), "체력의 젬")
	fails += _true("다른 칸은 빈 채로", G.entries(e1)[0] == null and G.entries(e1)[2] == null)
	fails += _true("이미 찬 칸 재장착 거부", G.equip_at(e1, 1, "체력의 젬", 0, table).is_empty())
	fails += _eq("자동 배치는 맞는 칸을 찾는다", G.fit_slot(typed, "체력의 젬", table), 1)
	fails += _eq("맞는 칸 없으면 -1", G.fit_slot({"types": ["ATT", "ATT", "ATT"], "slots": [null, null, null]}, "체력의 젬", table), -1)
	# 칸 index 가 보존돼야 한다 — 1번칸만 채운 뒤 해제하면 다시 전부 빈다.
	fails += _true("칸 해제", G.entries(G.unequip_at(e1, 1))[1] == null)
	fails += _true("타입은 해제 후에도 유지", G.types(G.unequip_at(e1, 1)) == ["ATT", "HP", "ALL"])
	# 랜덤 부여 — 항상 SLOTS 개, 전부 정의된 타입.
	var rt2 := G.random_types(table)
	fails += _eq("랜덤 타입 개수", rt2.size(), G.SLOTS)
	for t2 in rt2:
		fails += _true("랜덤 타입이 정의에 있음(%s)" % str(t2), G.type_order(table).has(String(t2)))
	# 승급은 그 칸 타입이 소울젬을 받을 때만 — ATT 칸의 원형 공방젬은 SOULATT 라 통과한다.
	var pslot := G.equip_at({"types": ["ATT", "ALL", "ALL"], "slots": [null, null, null]}, 0, "공방젬", 18, table)
	fails += _eq("ATT칸 공방젬 승급", String(G.entries(G.promote_at(pslot, 0, table))[0]["name"]), "공격의 소울젬")

	# 11) 강화 실패 · 다이아 복구 · 연금술 포인트 (2026-07-27, C 트랙).
	var rg := RandomNumberGenerator.new()
	var f11 := G.equip_at({"types": ["ALL", "ALL", "ALL"], "slots": [null, null, null]},
		0, "체력의 젬", 5, table)
	# 기본 성공률 = **위키 실측표**(gems.json upgrade.success.by_tier_pct). tier 는 0-base 라
	# 표에서는 6강 칸을 본다 → 46%.
	# ⚠️ 종전 기대값(75)은 폐기된 ASSUMPTION 공식(100 − 5×티어)의 값이었다. 위키 실측표가
	#   확보되면서 build_gems.py 가 표로 갈아탔는데(`_supersedes`) 이 테스트만 남아 있었다.
	#   사용자 확답(2026-07-29 open_questions.csv "assumption대로 유지")은 **당시 시트에 적힌
	#   현재값을 유지하라**는 뜻이고, 그 사이 근거가 실측표로 올라갔으므로 표를 정답으로 둔다.
	var want5 := int((((table.get("upgrade", {}) as Dictionary).get("success", {}) as Dictionary)
		.get("by_tier_pct", {}) as Dictionary).get("6", 46))
	fails += _eq("기본 성공률(티어5=6강)", G.base_success("체력의 젬", 5, table), want5)
	fails += _eq("성공률=기본(포인트 0)", G.success_chance(f11, 0, table), want5)
	# 용액 투입 → 포인트 상승, 투입 횟수 소모
	var pot: Dictionary = (table.get("upgrade", {}) as Dictionary).get("potions", [])[0]   # 절제 1~5
	rg.seed = 12345
	var ap := G.add_potion(f11, 0, pot, table, rg)
	fails += _true("용액 투입 성공", not ap.is_empty())
	fails += _true("포인트 1~5 증가", int(ap.get("gained", 0)) >= 1 and int(ap.get("gained", 0)) <= 5)
	fails += _eq("남은 투입 수", int(ap.get("uses_left", -1)), 4)
	fails += _eq("성공률에 포인트 가산", G.success_chance(ap["field"], 0, table), want5 + int(ap["points"]))
	# 5회 넘게는 못 넣는다(원작 "남은 용액 투입 수")
	var f5: Dictionary = f11
	for _k in 5:
		var r5 := G.add_potion(f5, 0, pot, table, rg)
		if not r5.is_empty(): f5 = r5["field"]
	fails += _true("6번째 투입 거부", G.add_potion(f5, 0, pot, table, rg).is_empty())
	# 100 초과 → 0 초기화(사용자 확정)
	var big := {"points": [200, 200]}
	var over := G.add_potion(f11, 0, big, table, rg)
	fails += _true("100 초과 시 초기화", bool(over.get("reset", false)) and int(over["points"]) == 0)
	# 강화 판정 — 성공률 100 이면 항상 성공, 0 이면 항상 실패(파손)
	var sure := G.equip_at({"types": ["ALL", "ALL", "ALL"], "slots": [null, null, null]},
		0, "체력의 젬", 0, table)                       # 티어0 → 기본 100%
	var win := G.roll_upgrade(sure, 0, table, rg)
	fails += _true("100% 는 성공", bool(win.get("ok", false)))
	fails += _eq("성공 시 티어+1", int(G.entries(win["field"])[0]["tier"]), 1)
	fails += _true("성공하면 파손 아님", not G.is_broken(G.entries(win["field"])[0]))
	var low2 := G.equip_at({"types": ["ALL", "ALL", "ALL"], "slots": [null, null, null]},
		0, "체력의 젬", 18, table)                      # 최대 티어 → 강화 불가
	fails += _true("최대 티어는 강화 거부", G.roll_upgrade(low2, 0, table, rg).is_empty())
	# 실패 시나리오 — floor_pct 까지 내려간 고티어로 여러 번 굴려 파손을 하나 만든다
	var broke: Dictionary = {}
	for _t in 200:
		var cand := G.equip_at({"types": ["ALL", "ALL", "ALL"], "slots": [null, null, null]},
			0, "체력의 젬", 17, table)                  # 기본 10%
		var r := G.roll_upgrade(cand, 0, table, rg)
		if not bool(r.get("ok", true)):
			broke = r["field"]
			break
	fails += _true("실패가 발생한다", not broke.is_empty())
	if not broke.is_empty():
		var be = G.entries(broke)[0]
		fails += _true("실패 시 파손 표시", G.is_broken(be))
		fails += _eq("파손돼도 티어 유지", int(be["tier"]), 17)
		# 파손 젬은 효과가 0 (aggregate 제외)
		fails += _eq("파손 젬 효과 0", int(G.aggregate(broke, table)["flat"]["hp"]), 0)
		fails += _true("파손 젬은 재강화 거부", G.roll_upgrade(broke, 0, table, rg).is_empty())
		# 복구 다이아 = 위키 표(순서 = 티어) → 티어17 = 18
		fails += _eq("복구 다이아(티어17)", G.repair_cost(17, table), 18)
		fails += _eq("복구 다이아(티어0)", G.repair_cost(0, table), 1)
		var fixed := G.repair(broke, 0)
		fails += _true("복구되면 파손 해제", not G.is_broken(G.entries(fixed)[0]))
		fails += _true("복구 후 효과 부활", int(G.aggregate(fixed, table)["flat"]["hp"]) > 0)
	# ── 혼성젬 제작 + 샌즈의 눈물(위키 §2.2 — 제작 시 샌즈젬 확률 +10/+20%) ──────────
	fails += _eq("혼성젬 풀", G.hybrid_pool(table).size(), 7)
	fails += _eq("눈물 보너스 10%", G.sands_bonus("alchemy_platinum_01", table), 10)
	fails += _eq("눈물 보너스 20%", G.sands_bonus("alchemy_platinum_02", table), 20)
	fails += _eq("눈물 없음 = 균등", G.sands_chance(table, 0), 14)      # round(100/7)
	fails += _eq("눈물 10% 투입", G.sands_chance(table, 10), 24)
	fails += _eq("눈물 20% 투입", G.sands_chance(table, 20), 34)
	# 실제 굴림이 그 확률에 수렴하나(시드 고정 5,000회, ±3%p 허용).
	for probe in [[0, 14], [10, 24], [20, 34]]:
		var rc := RandomNumberGenerator.new()
		rc.seed = 20260731
		var hit := 0
		var seen: Dictionary = {}
		for i in 5000:
			var got := G.craft_hybrid(table, int(probe[0]), rc)
			seen[got] = true
			if got == "샌즈의 젬":
				hit += 1
		var pct := hit * 100.0 / 5000.0
		fails += _true("제작 샌즈율(보너스 %d) %.1f%% ≈ %d%%" % [probe[0], pct, probe[1]],
			absf(pct - float(probe[1])) <= 3.0)
		fails += _eq("제작 결과 종류(보너스 %d)" % probe[0], seen.size(), 7)

	# 연금 상태(points/potions)가 entries 왕복에서 보존돼야 한다
	var keep := G.entries(ap["field"])
	fails += _eq("entries 가 포인트 보존", int((keep[0] as Dictionary).get("points", -1)), int(ap["points"]))
	fails += _eq("entries 가 투입수 보존", int((keep[0] as Dictionary).get("potions", -1)), 1)

	if fails == 0:
		print("[test_gem] ALL PASS")
		quit(0)
	else:
		printerr("[test_gem] %d FAIL" % fails)
		quit(1)

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
