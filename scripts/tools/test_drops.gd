extends SceneTree
## 헤드리스 Drops 단위 테스트 (§8 — logic은 화면 없이 검증).
## 검증 대상 = 사용자 확정 규칙(2026-07-27):
##   고레벨 지역일수록 / 일반몹 < 보물상자 < 보스 일수록 더 좋은 것
##   상점=낮은 성능·골드 / 가챠=다이아 / 이벤트 장비=가챠 전용 / 아티팩트=카데스 전용
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_drops.gd --quit-after 3

const D := preload("res://scripts/systems/drops.gd")
const G := preload("res://scripts/systems/gem.gd")
const E := preload("res://scripts/systems/equipment.gd")

const N := 4000       # 표본 수(확률 규칙은 통계로 검증한다)

func _init() -> void:
	var fails := 0
	var t = _json("res://data/drops.json")
	var gems = _json("res://data/gems.json")
	var equip = _json("res://data/equipment.json")

	# 0) 표 자체 — 규칙이 데이터에 실제로 들어있는지.
	fails += _true("exploration 있음", t.has("exploration"))
	fails += _true("kades 있음", t.has("kades"))
	fails += _eq("탐험 젬풀=일반 3종", (t["exploration"]["gem_pool"] as Array).size(), 3)
	fails += _true("보스 quality > 상자 quality",
		int(t["exploration"]["sources"]["boss"]["quality"]) > int(t["exploration"]["sources"]["chest"]["quality"]))
	fails += _true("상자 quality > 일반 quality",
		int(t["exploration"]["sources"]["chest"]["quality"]) > int(t["exploration"]["sources"]["normal"]["quality"]))

	# 1) 고레벨 지역일수록 더 좋다 — 같은 source 로 평균 티어/등급 비교.
	var lo := _avg_quality(t, gems, equip, 1, D.SOURCE_BOSS, false)
	var hi := _avg_quality(t, gems, equip, 50, D.SOURCE_BOSS, false)
	fails += _true("고레벨 지역이 더 좋다 (Lv1 %.2f < Lv50 %.2f)" % [lo, hi], hi > lo + 1.0)

	# 2) 일반몹 < 보물상자 < 보스 — 같은 레벨로 비교.
	var q_norm := _avg_quality(t, gems, equip, 30, D.SOURCE_NORMAL, false)
	var q_chest := _avg_quality(t, gems, equip, 30, D.SOURCE_CHEST, false)
	var q_boss := _avg_quality(t, gems, equip, 30, D.SOURCE_BOSS, false)
	fails += _true("보물상자 > 일반몹 (%.2f > %.2f)" % [q_chest, q_norm], q_chest > q_norm)
	fails += _true("보스 > 보물상자 (%.2f > %.2f)" % [q_boss, q_chest], q_boss > q_chest)

	# 3) 드롭 확률 — 보물상자는 항상, 일반몹은 드물게.
	var rng := RandomNumberGenerator.new(); rng.seed = 1234
	var n_chest := 0
	var n_norm := 0
	for _i in N:
		if D.roll_exploration(t, 30, D.SOURCE_CHEST, equip, rng, false) != "": n_chest += 1
		if D.roll_exploration(t, 30, D.SOURCE_NORMAL, equip, rng, false) != "": n_norm += 1
	fails += _eq("보물상자는 항상 드롭", n_chest, N)
	fails += _true("일반몹 드롭률 0<r<0.25 (%.3f)" % (float(n_norm) / N),
		n_norm > 0 and float(n_norm) / N < 0.25)

	# 4) 🔴 아티팩트는 카데스 전용. 카데스 밖에서는 **한 번도** 나와선 안 된다.
	var art_out := 0
	var art_in := 0
	for _i in N:
		for src in [D.SOURCE_NORMAL, D.SOURCE_CHEST, D.SOURCE_BOSS]:
			if D.roll_exploration(t, 50, src, equip, rng, false).begins_with("equip:artifact:"): art_out += 1
			if D.roll_exploration(t, 50, src, equip, rng, true).begins_with("equip:artifact:"): art_in += 1
	fails += _eq("카데스 밖 아티팩트 0건", art_out, 0)
	fails += _true("카데스 안에서는 나온다 (%d건)" % art_in, art_in > 0)

	# 5) 🔴 이벤트 장비는 가챠 전용. 탐험에서는 **한 번도** 나와선 안 된다.
	var ev_explore := 0
	for _i in N:
		for src2 in [D.SOURCE_NORMAL, D.SOURCE_CHEST, D.SOURCE_BOSS]:
			for kd in [false, true]:
				if E.parse_item_key(D.roll_exploration(t, 50, src2, equip, rng, kd)).begins_with("event:"): ev_explore += 1
	fails += _eq("탐험에서 이벤트 장비 0건", ev_explore, 0)
	var ev_gacha := 0
	for _i in N:
		if E.parse_item_key(D.roll_equip_gacha(t, equip, rng)).begins_with("event:"): ev_gacha += 1
	fails += _true("장비 가챠에서는 이벤트가 나온다 (%d건)" % ev_gacha, ev_gacha > 0)

	# 5b) 획득 키에 개체 정보(희귀도·옵션)가 실린다 — 사용자 확정 분포(2026-07-29).
	#     드롭 = 일반70:레어20:유니크8:에픽2 / 상점 골드 = 일반100 / 가챠 = 레어60:유니크30:에픽10
	var rar_drop := {}
	for _i in N:
		var k := D.roll_exploration(t, 50, D.SOURCE_BOSS, equip, rng, false)
		if E.parse_item_key(k) == "" or not E.parse_item_key(k).begins_with("basic:"):
			continue
		var m := E.item_key_meta(k)
		rar_drop[int(m["rarity"])] = int(rar_drop.get(int(m["rarity"]), 0)) + 1
		# 희귀도만큼 옵션이 붙어 있어야 한다.
		if (m["options"] as Array).size() != E.option_count(int(m["rarity"]), equip):
			fails += _true("드롭 옵션 수 = 등급 옵션 수", false)
			break
	var tot_drop := 0
	for g in rar_drop: tot_drop += int(rar_drop[g])
	fails += _true("드롭에 매직(1)·초월(5) 없음",
			not rar_drop.has(1) and not rar_drop.has(5))
	if tot_drop > 200:
		fails += _true("드롭 일반 약 70%%(%d/%d)" % [int(rar_drop.get(0, 0)), tot_drop],
				absf(float(rar_drop.get(0, 0)) / float(tot_drop) - 0.70) < 0.06)
	# 상점 골드 재고는 개체 정보가 없다(일반 100%).
	for row in D.shop_equips(t):
		var mm := E.item_key_meta(String((row as Dictionary)["key"]))
		if int(mm["rarity"]) != 0 or not (mm["options"] as Array).is_empty():
			fails += _true("상점 골드 장비는 일반·옵션없음", false)
			break

	# 6) 상점 = 낮은 성능만(사용자 확정). 젬 티어·장비 등급 상한 확인.
	var sg: Array = D.shop_gems(t)
	fails += _true("상점 젬 재고 있음", sg.size() > 0)
	var worst_ok := true
	for e in sg:
		var g := G.parse_item_key(String((e as Dictionary)["key"]))
		if int(g["tier"]) > 1: worst_ok = false
		if int((e as Dictionary)["price"]) <= 0: worst_ok = false
	fails += _true("상점 젬은 티어 1 이하 + 가격>0", worst_ok)
	var se: Array = D.shop_equips(t)
	var eq_ok := true
	for e2 in se:
		var ck := E.parse_item_key(String((e2 as Dictionary)["key"]))
		if not ck.begins_with("basic:"): eq_ok = false
		if int(ck.split(":")[2]) > 1: eq_ok = false
	fails += _true("상점 장비는 등급 1 이하 일반장비", eq_ok)

	# 7) 젬 가챠 = "높은 등급의 일반 젬"(위키 item.pdf §9.3). 티어 하한 확인 + 가격 위키값.
	var gg: Dictionary = t["gacha"]["gem"]
	fails += _eq("젬 가챠 1회 = 15다이아(위키)", int(gg["price_single"]), 15)
	fails += _eq("젬 가챠 10연속 = 125다이아(위키)", int(gg["price_ten"]), 125)
	# 사용자 확정(2026-07-27): 다이아 가챠 = 혼성 + 샌즈 + 소울, **모든 티어**.
	#   골드 뽑기(점술집) = 일반 3종, 모든 티어.  진귀한 보석 상자 = 일반 고티어(위키).
	var bad_cat := 0
	var soul_seen := false
	var hyb_seen := false
	var tier_hi := 0
	for _i in N:
		var k := G.parse_item_key(D.roll_gem_gacha(t, gems, rng))
		if k.is_empty(): bad_cat += 1; continue
		var cat0 := String(G.gem_def(String(k["name"]), gems).get("category", ""))
		if cat0 == "soul": soul_seen = true
		elif cat0 == "hybrid": hyb_seen = true
		else: bad_cat += 1                       # 일반젬은 다이아 가챠에서 나오면 안 된다
		tier_hi = maxi(tier_hi, int(k["tier"]))
	fails += _eq("다이아 가챠에 일반젬 없음", bad_cat, 0)
	fails += _true("다이아 가챠에 소울젬 나온다", soul_seen)
	fails += _true("다이아 가챠에 혼성젬 나온다", hyb_seen)
	fails += _true("다이아 가챠는 상위 티어까지 나온다(%d)" % tier_hi, tier_hi >= 15)
	# 점술집 뽑기 = **잭팟**(원작 SlotLayer::ResponseSlot :897 — r1==r2==r3 일 때만 지급).
	var scfg: Dictionary = t["slot"]
	var faces: Array = D.slot_faces(t, gems)
	var face_bad := 0
	var want_items: Array = scfg.get("items", [])
	var seen_items: Array = []
	for f in faces:
		var fd: Dictionary = f
		if String(fd.get("kind", "")) == "item":
			seen_items.append(String(fd["key"]))
			if not want_items.has(String(fd["key"])): face_bad += 1
		else:
			var c1 := String(G.gem_def(String(fd["gem_name"]), gems).get("category", ""))
			if not (scfg["gem"]["categories"] as Array).has(c1): face_bad += 1
	fails += _eq("릴 품목은 설정된 젬 분류 + 아이템만", face_bad, 0)
	fails += _eq("릴에 지정 아이템이 전부 있다", seen_items.size(), want_items.size())
	fails += _true("릴 품목이 2종 이상(잭팟이 성립한다)", faces.size() >= 2)
	var wins := 0
	var slot_bad := 0
	var tier_bad := 0
	for _i in N:
		var r: Dictionary = D.roll_slot(t, gems, rng)
		var rl: Array = r["reels"]
		var same: bool = rl[0] == rl[1] and rl[1] == rl[2]
		if bool(r["win"]):
			wins += 1
			# 당첨이면 릴 3개가 같고, 그 얼굴이 곧 지급 품목이어야 한다.
			if not same or String(r["key"]) == "": slot_bad += 1
			var fw: Dictionary = faces[int(rl[0])]
			if String(fw.get("kind", "")) == "gem":
				var k2 := G.parse_item_key(String(r["key"]))
				if k2.is_empty() or String(k2["name"]) != String(fw["gem_name"]): slot_bad += 1
				elif int(k2["tier"]) < int(scfg["gem"]["tier_min"]) \
					or int(k2["tier"]) > int(scfg["gem"]["tier_max"]): tier_bad += 1
			elif String(r["key"]) != String(fw["key"]):
				slot_bad += 1
		else:
			# 꽝이면 **절대** 세 릴이 같으면 안 된다(같으면 화면이 당첨처럼 보인다).
			if same or String(r["key"]) != "": slot_bad += 1
	fails += _eq("잭팟 판정과 릴 표시가 일치", slot_bad, 0)
	fails += _eq("당첨 젬 티어가 설정 범위 안", tier_bad, 0)
	var rate := float(wins) / float(N)
	var want_rate := float(scfg["win_rate"])
	fails += _true("잭팟 성공률 ≈ %.2f (실측 %.3f)" % [want_rate, rate],
		absf(rate - want_rate) < 0.05)
	var box_bad := 0
	var bcfg: Dictionary = (t.get("box", {}) as Dictionary).get("jem_random", {})
	for _i in N:
		var k3 := G.parse_item_key(D.roll_gem_box(t, gems, rng))
		if k3.is_empty() \
			or String(G.gem_def(String(k3["name"]), gems).get("category", "")) != "normal" \
			or int(k3["tier"]) < int(bcfg.get("tier_min", 9)) \
			or int(k3["tier"]) > int(bcfg.get("tier_max", 14)):
			box_bad += 1
	fails += _eq("진귀한 보석 상자 = 일반젬 9~14티어(위키)", box_bad, 0)

	# 8) 카탈로그 정합 — 뽑힌 키가 실제 정의로 되돌아가야 한다(존재하지 않는 장비 생성 방지).
	var cat := E.catalog(equip)
	var bad := ""
	for _i in 600:
		for src3 in [D.SOURCE_NORMAL, D.SOURCE_CHEST, D.SOURCE_BOSS]:
			for kd2 in [false, true]:
				var key := D.roll_exploration(t, 50, src3, equip, rng, kd2)
				if key == "": continue
				var ck2 := E.parse_item_key(key)
				if ck2 != "" and not cat.has(ck2): bad = key
				var gk := G.parse_item_key(key)
				if not gk.is_empty() and G.gem_def(String(gk["name"]), gems).is_empty(): bad = key
	for _i in 600:
		var k2 := D.roll_equip_gacha(t, equip, rng)
		if k2 != "" and not cat.has(E.parse_item_key(k2)): bad = k2
	fails += _eq("정의에 없는 키 생성 없음", bad, "")

	# 9) 표시 이름 — 젬은 티어 모양, 장비는 카탈로그 이름.
	# 이름 양식(사용자 확정 2026-07-27): 일반·혼성 "<종류> +<상승량>" / 소울 "<종류>의 소울젬 +<단계>".
	fails += _eq("일반젬 표시명", D.display_name(G.item_key("체력의 젬", 0), gems, equip), "체력의 젬 +28")
	fails += _eq("일반젬 최고티어", D.display_name(G.item_key("체력의 젬", 18), gems, equip), "체력의 젬 +120")
	fails += _eq("혼성젬은 앞 스탯 수치", D.display_name(G.item_key("체공젬", 0), gems, equip), "체공젬 +36")
	fails += _eq("혼성젬(공체) 앞 스탯", D.display_name(G.item_key("공체젬", 0), gems, equip), "공체젬 +5")
	fails += _eq("소울젬은 단계", D.display_name(G.item_key("공격의 소울젬", 2), gems, equip), "공격의 소울젬 +3")
	fails += _eq("소울젬 10단계", D.display_name(G.item_key("체력의 소울젬", 9), gems, equip), "체력의 소울젬 +10")
	fails += _eq("장비 표시명", D.display_name(E.item_key("basic:깃털:6"), gems, equip), "아만타의 금우")
	# 위키 툴팁 문구 — gems.pdf 의 "효과" 열과 같은 순서/표기.
	fails += _eq("툴팁(일반)", G.effect_text("체력의 젬", 0, gems), "체력 +28")
	fails += _eq("툴팁(혼성)", G.effect_text("체공젬", 0, gems), "체력 +36, 공격력 +4")
	fails += _eq("툴팁(소울)", G.effect_text("공격의 소울젬", 0, gems),
		"공격력 +28, 공격력 +5%, 크리티컬 확률 +1%")
	fails += _eq("툴팁(샌즈 소울)", G.effect_text("샌즈의 소울젬", 0, gems),
		"체력 +6%, 공격력 +6%, 방어력 +6%")
	fails += _eq("모양 표기(일반)", G.shape_label("체력의 젬", 3, gems), "삼각형")
	fails += _eq("모양 표기(소울)", G.shape_label("공격의 소울젬", 3, gems), "4단계")

	# ── 먹이 드롭 = 지역 속성 일치분만 (사용자 확정 2026-07-30) ────────────────
	var items_raw = _json("res://data/items.json")
	var items: Dictionary = items_raw.get("items", items_raw)
	var stages: Dictionary = (_json("res://data/stages.json") as Dictionary)["stages"]

	fails += _true("drops.json 에 food 블록", t.has("food"))
	fails += _true("drops.json 에 egg 블록", t.has("egg"))

	# 지역 element(ground/water)와 먹이 element(earth/aqua) 표기가 달라도 이어져야 한다.
	fails += _eq("정규화 ground→earth", D.normalize_element("ground"), "earth")
	fails += _eq("정규화 water→aqua", D.normalize_element("water"), "aqua")

	var p_ground := D.food_pool(items, "ground")
	var p_fire := D.food_pool(items, "fire")
	fails += _true("ground 먹이풀 비어있지 않음", not p_ground.is_empty())
	fails += _true("ground 먹이풀은 전부 earth", _all_food_element(items, p_ground, "earth"))
	fails += _true("fire 먹이풀은 전부 fire", _all_food_element(items, p_fire, "fire"))
	fails += _true("ground/fire 풀이 겹치지 않음", _disjoint(p_ground, p_fire))
	# 물약·드링크(category=food 이지만 속성 없음)가 새어 들어오면 안 된다.
	fails += _true("풀에 드링크 없음", not p_ground.has("att_drink1") and not p_fire.has("heal_potion1"))
	# 속성이 없는 지역(우노 24·25 = element null)은 **아무것도** 주지 않는다.
	fails += _eq("element null 지역 = 빈 풀", D.food_pool(items, null).size(), 0)
	fails += _eq("element \"\" 지역 = 빈 풀", D.food_pool(items, "").size(), 0)
	# 실제 스테이지 레코드로 왕복 — 모든 지역이 자기 속성 먹이만 준다.
	var frng := RandomNumberGenerator.new(); frng.seed = 7
	for sid in stages:
		var st: Dictionary = stages[sid]
		var want := D.normalize_element(st.get("element", ""))
		for _i in 40:
			var fk := D.roll_food(items, st.get("element", ""), frng)
			if fk == "":
				continue
			var fel := D.normalize_element((items[fk] as Dictionary).get("element", ""))
			if fel != want:
				fails += _eq("스테이지 %s 먹이 속성" % sid, fel, want)
				break

	# ── 알 드롭 = 그 탐험지 팝업 등재 드래곤만, H 는 영웅 전용 ────────────────
	# 빛의 탑(15) = 일반 3(52·61·82) + H 2(21·77) — stages.json `dragons`.
	var st15: Dictionary = stages["15"]
	var normal15 := D.egg_pool(st15, false)
	var hero15 := D.egg_pool(st15, true, true)
	fails += _eq("빛의탑 일반 후보 3종", normal15.size(), 3)
	fails += _eq("빛의탑 H 후보 2종", hero15.size(), 2)
	fails += _true("일반 난이도 후보에 H 없음", not normal15.has(21) and not normal15.has(77))
	fails += _true("H 후보는 H 뿐", hero15.has(21) and hero15.has(77))

	# 일반 난이도로 아무리 굴려도 H 드래곤 알은 나오지 않는다.
	var erng := RandomNumberGenerator.new(); erng.seed = 11
	var hero_leak := 0
	var any_egg := 0
	for _i in N:
		var ek := D.roll_egg(t, st15, D.SOURCE_BOSS, erng, false)
		if ek == "": continue
		any_egg += 1
		var did := int(ek.substr(4))
		if did == 21 or did == 77: hero_leak += 1
	fails += _true("일반 난이도에서 알이 나오긴 한다", any_egg > 0)
	fails += _eq("일반 난이도 H 알 누출", hero_leak, 0)

	# 등재되지 않은 드래곤은 절대 안 나온다 + 영웅에서 H 는 일반보다 희귀하다.
	var allowed := {}
	for x in D.egg_pool(st15, true): allowed[x] = true
	for x in hero15: allowed[x] = true
	var hrng := RandomNumberGenerator.new(); hrng.seed = 13
	var off_roster := 0
	var h_cnt := 0
	var n_cnt := 0
	for _i in N:
		var ek2 := D.roll_egg(t, st15, D.SOURCE_BOSS, hrng, true)
		if ek2 == "": continue
		var did2 := int(ek2.substr(4))
		if not allowed.has(did2): off_roster += 1
		if did2 == 21 or did2 == 77: h_cnt += 1
		else: n_cnt += 1
	fails += _eq("팝업 미등재 드래곤 알 누출", off_roster, 0)
	fails += _true("영웅에서 H 알이 나오긴 한다", h_cnt > 0)
	fails += _true("H 알이 일반 알보다 희귀", h_cnt < n_cnt)

	# 알 후보가 없는 지역(우노 24 = dragons 없음)은 아무것도 주지 않는다.
	var no_rng := RandomNumberGenerator.new(); no_rng.seed = 17
	var uno_eggs := 0
	for _i in 500:
		if D.roll_egg(t, stages["24"], D.SOURCE_BOSS, no_rng, true) != "": uno_eggs += 1
	fails += _eq("드래곤 미등재 지역 알 드롭", uno_eggs, 0)

	# ── 속성 정기 = 그 지역 속성의 것만 (사용자 확정 2026-07-31) ──────────────
	fails += _true("drops.json 에 essence 블록", t.has("essence"))
	fails += _eq("불 지역 정기", D.essence_of(items, "fire"), "ele_fire")
	fails += _eq("ground 지역 정기(earth 표기)", D.essence_of(items, "ground"), "ele_ground")
	fails += _eq("water 지역 정기(aqua 표기)", D.essence_of(items, "water"), "ele_water")
	fails += _eq("속성 없는 지역 정기", D.essence_of(items, null), "")
	var srng := RandomNumberGenerator.new(); srng.seed = 55
	var wrong_ess := 0
	for sid2 in stages:
		var st2: Dictionary = stages[sid2]
		var want2 := D.essence_of(items, st2.get("element", ""))
		for _i in 30:
			var e2 := D.roll_essence(t, items, st2.get("element", ""), D.SOURCE_BOSS, srng)
			if e2.is_empty(): continue
			if String(e2["key"]) != want2: wrong_ess += 1
			if int(e2["count"]) <= 0: wrong_ess += 1
	fails += _eq("지역과 다른 정기 드랍", wrong_ess, 0)

	# ── 특수 드랍 = 그 지역 표(stages.json drops)에 있는 것만 ────────────────
	# 우노 24 = 아니마(일반 5~10 / 영웅 15~20, 위키 item.pdf 각주 [40]).
	var st24: Dictionary = stages["24"]
	var prng := RandomNumberGenerator.new(); prng.seed = 66
	var off24 := 0
	var lo_ok := true
	var hero_ok := true
	for _i in 400:
		for sd in D.roll_special(st24, prng, D.MODE_NORMAL, true):
			if String((sd as Dictionary)["key"]) != "anima": off24 += 1
			var c := int((sd as Dictionary)["count"])
			if c < 5 or c > 10: lo_ok = false
		for sd2 in D.roll_special(st24, prng, D.MODE_HERO, true):
			var hc := int((sd2 as Dictionary)["count"])
			if hc < 15 or hc > 20: hero_ok = false
	fails += _eq("우노24 표 밖 아이템", off24, 0)
	fails += _eq("일반 난이도 수량 5~10", lo_ok, true)
	fails += _eq("영웅 난이도 수량 15~20", hero_ok, true)
	# 표가 빈 지역은 특수 드랍이 없다.
	fails += _eq("보스가 아니면 특수 드랍 없음", D.roll_special(stages["1"], prng, D.MODE_HERO, false).size(), 0)

	# ── 난이도별 풀 분리 (사용자 확정 2026-07-31) ────────────────────────────
	# stages.json `drops` 는 {난이도: [항목]} 이다.
	fails += _eq("mode_of 일반", D.mode_of(false, false, false), D.MODE_NORMAL)
	fails += _eq("mode_of 영웅", D.mode_of(true, false, false), D.MODE_HERO)
	fails += _eq("mode_of 밤이 영웅보다 우선", D.mode_of(true, true, false), D.MODE_NIGHT)
	fails += _eq("mode_of 카데스가 최상위", D.mode_of(true, true, true), D.MODE_KADES)
	# 우노24 는 normal/hero 표가 **따로** 있고 수량이 다르다.
	fails += _eq("우노24 normal 표 1줄", D.special_table(st24, D.MODE_NORMAL).size(), 1)
	fails += _eq("우노24 hero 표 1줄", D.special_table(st24, D.MODE_HERO).size(), 1)
	fails += _eq("normal 수량 상한 10",
		int((D.special_table(st24, D.MODE_NORMAL)[0] as Dictionary)["max"]), 10)
	fails += _eq("hero 수량 상한 20",
		int((D.special_table(st24, D.MODE_HERO)[0] as Dictionary)["max"]), 20)
	# ⛔ 밤은 지역 필드 보상이 **없다**(사용자 확정 2026-07-31) — 일반 표로 폴백하면 안 된다.
	fails += _eq("밤 지역 필드 보상 없음", D.special_table(st24, D.MODE_NIGHT).size(), 0)
	var nrng2 := RandomNumberGenerator.new(); nrng2.seed = 88
	var night_field := 0
	for _i in 500:
		night_field += D.roll_special(st24, nrng2, D.MODE_NIGHT, true).size()
	fails += _eq("밤에 지역 특수 드랍", night_field, 0)
	# 밤 변형이 있는 지역은 12곳(1~14 중 6·8 제외) — 데이터 자체 확인.
	var night_stages := 0
	for sidn in stages:
		if not (stages[sidn] as Dictionary).get("night", {}).is_empty():
			night_stages += 1
	fails += _eq("밤 변형 보유 지역 수", night_stages, 12)

	# ── 화이트리스트 — 탐험 드랍 전 경로를 굴려 **허용 목록 밖이 하나도 없는지** ──
	# 사용자 확정 2026-07-31: 알 / 일반젬 / 먹이 / 그 지역 정기 / CSV 특수 드랍 (+장비 공통)만.
	var wl := RandomNumberGenerator.new(); wl.seed = 909
	var violations: Array = []
	for sid3 in stages:
		var st3: Dictionary = stages[sid3]
		for hero3 in [false, true]:
			for src3 in [D.SOURCE_NORMAL, D.SOURCE_CHEST, D.SOURCE_BOSS]:
				for _i in 60:
					var keys: Array = []
					var k1 := D.roll_egg(t, st3, src3, wl, hero3)
					if k1 != "": keys.append(k1)
					var k2 := D.roll_food(items, st3.get("element", ""), wl)
					if k2 != "": keys.append(k2)
					var e3 := D.roll_essence(t, items, st3.get("element", ""), src3, wl)
					if not e3.is_empty(): keys.append(String(e3["key"]))
					var mode3 := D.mode_of(hero3, false, false)
					for sd3 in D.roll_special(st3, wl, mode3, true):
						keys.append(String((sd3 as Dictionary)["key"]))
					var k4 := D.roll_exploration(t, int(st3.get("level", 1)), src3, equip, wl)
					if k4 != "": keys.append(k4)
					for kk in keys:
						if not D.is_allowed(String(kk), st3, items, t, hero3, mode3):
							violations.append("%s:%s" % [sid3, kk])
	fails += _eq("화이트리스트 위반", violations.size(), 0)
	if not violations.is_empty():
		printerr("    예: ", violations.slice(0, 8))
	# 반대 방향 — 화이트리스트가 무엇이든 통과시키는 게 아닌지(허수 통과 방지).
	fails += _true("무관한 아이템은 불허", not D.is_allowed("heal_potion1", stages["1"], items, t, true))
	fails += _true("타 지역 특수 드랍 불허", not D.is_allowed("anima", stages["1"], items, t, true))
	fails += _true("타 속성 먹이 불허",
		not D.is_allowed("food_fire_chicken", stages["2"], items, t, true))   # 2=난파선(water)
	fails += _true("타 속성 정기 불허", not D.is_allowed("ele_fire", stages["2"], items, t, true))

	# ── 몬스터별 고유 드랍 (사용자 표 2026-07-31) ────────────────────────────
	var L := preload("res://scripts/systems/loadout.gd")
	var md = _json("res://data/monster_drops.json")
	fails += _true("monster_drops 로드", md.has("drops"))
	fails += _eq("표에 실린 몬스터 수", (md["drops"] as Dictionary).size(), 19)

	# 골드 임프(#160) = 보석 4종, 가중 3:2:1:1, 5~15개, 확정 드랍.
	var jr := RandomNumberGenerator.new(); jr.seed = 71
	var jc := {}
	var qty_bad := 0
	var none := 0
	for _i in N:
		var got := D.roll_monster(md, 160, jr)
		if got.is_empty(): none += 1; continue
		for g in got:
			var gd: Dictionary = g
			jc[String(gd["key"])] = int(jc.get(String(gd["key"]), 0)) + 1
			if int(gd["count"]) < 5 or int(gd["count"]) > 15: qty_bad += 1
	fails += _eq("골드임프는 확정 드랍", none, 0)
	fails += _eq("골드임프 수량 5~15", qty_bad, 0)
	fails += _eq("골드임프는 보석 4종만", jc.size(), 4)
	var jt := 0
	for k in jc: jt += int(jc[k])
	fails += _true("자수정 ≈3/7 (%.3f)" % (float(jc.get("jewel_amethyst", 0)) / jt),
		absf(float(jc.get("jewel_amethyst", 0)) / jt - 3.0 / 7.0) < 0.04)
	fails += _true("루비 ≈1/7 (%.3f)" % (float(jc.get("jewel_ruby", 0)) / jt),
		absf(float(jc.get("jewel_ruby", 0)) / jt - 1.0 / 7.0) < 0.04)

	# 밤 보스(#163 포마스) = 신경독소(32) 스크롤, 레벨 가중 7:2:1:1.
	var sr := RandomNumberGenerator.new(); sr.seed = 73
	var lv := {}
	var wrong_skill := 0
	for _i in N:
		for g in D.roll_monster(md, 163, sr):
			var pk := L.parse_item_key(String((g as Dictionary)["key"]))
			if pk.is_empty() or int(pk["id"]) != 32: wrong_skill += 1
			else: lv[int(pk["level"])] = int(lv.get(int(pk["level"]), 0)) + 1
	fails += _eq("포마스는 신경독소 스크롤만", wrong_skill, 0)
	fails += _eq("레벨은 1~4", lv.size(), 4)
	var lt := 0
	for k in lv: lt += int(lv[k])
	fails += _true("Lv1 ≈7/11 (%.3f)" % (float(lv.get(1, 0)) / lt),
		absf(float(lv.get(1, 0)) / lt - 7.0 / 11.0) < 0.04)
	# 스크롤 키는 **가방 '스킬' 탭** 형식이어야 한다(원작 AccountManager::addSkill 대응).
	fails += _true("스크롤 키가 skill: 접두사", L.item_key(32, 3).begins_with(L.ITEM_PREFIX))

	# 혼돈의 틈새 보스(#36 다크닉스) = 그 드래곤 알, 0.2%.
	var er2 := RandomNumberGenerator.new(); er2.seed = 79
	var eggs := 0
	var wrong_egg := 0
	for _i in 200000:
		for g in D.roll_monster(md, 36, er2):
			eggs += 1
			if String((g as Dictionary)["key"]) != EggGacha.key_for(53): wrong_egg += 1
	fails += _eq("다크닉스 알만", wrong_egg, 0)
	fails += _true("0.2%% 근처 (%.4f%%)" % (float(eggs) / 2000.0),
		absf(float(eggs) / 200000.0 - 0.002) < 0.001)

	# 블랙 윗치(#175) = 다이아 재화 100~200, 1%.
	var wr := RandomNumberGenerator.new(); wr.seed = 83
	var dia := 0
	var dq_bad := 0
	var as_item := 0
	for _i in N * 10:
		for g in D.roll_monster(md, 175, wr):
			var gd2: Dictionary = g
			if String(gd2.get("kind", "")) != "currency": as_item += 1
			elif String(gd2["currency"]) != "diamond": as_item += 1
			else:
				dia += 1
				if int(gd2["count"]) < 100 or int(gd2["count"]) > 200: dq_bad += 1
	fails += _eq("다이아는 재화로 지급", as_item, 0)
	fails += _eq("다이아 수량 100~200", dq_bad, 0)
	fails += _true("다이아 1%% 근처 (%.3f%%)" % (float(dia) / float(N * 10) * 100.0),
		absf(float(dia) / float(N * 10) - 0.01) < 0.004)

	# 표에 없는 몬스터는 아무것도 안 준다.
	fails += _eq("표 밖 몬스터", D.roll_monster(md, 1, wr).size(), 0)

	# 화이트리스트가 몬스터 드랍을 통과시킨다(그리고 남의 것은 막는다).
	fails += _true("임프 보석 허용",
		D.is_allowed("jewel_ruby", stages["1"], items, t, false, D.MODE_NIGHT, md, 160))
	fails += _true("포마스 스크롤 허용",
		D.is_allowed(L.item_key(32, 2), stages["1"], items, t, false, D.MODE_NIGHT, md, 163))
	fails += _true("남의 몬스터 드랍은 불허",
		not D.is_allowed(L.item_key(32, 2), stages["1"], items, t, false, D.MODE_NIGHT, md, 160))

	# ── 지역 전용 스킬 스크롤 (사용자 표 2026-07-31) ─────────────────────────
	# 23개 지역이 지역 전용 스킬을 준다 — 일반 Lv1~3 0.1% / 영웅 Lv2~4 0.2%, 레벨비 5:3:2,
	# **보스에서만**.
	var L2 := preload("res://scripts/systems/loadout.gd")
	var scroll_stages := 0
	for sid4 in stages:
		var st4: Dictionary = stages[sid4]
		for row4 in D.special_table(st4, D.MODE_NORMAL):
			if String((row4 as Dictionary).get("kind", "")) == "skill_scroll":
				scroll_stages += 1
	fails += _eq("스크롤 배정 지역 23곳", scroll_stages, 23)

	# 희망의 숲(1) = 신경독소(32). 일반은 Lv1~3, 영웅은 Lv2~4.
	var st1b: Dictionary = stages["1"]
	var lr := RandomNumberGenerator.new(); lr.seed = 91
	var nlv := {}
	var hlv := {}
	var wrong := 0
	for _i in 200000:
		for g in D.roll_special(st1b, lr, D.MODE_NORMAL, true):
			var pk := L2.parse_item_key(String((g as Dictionary)["key"]))
			if pk.is_empty() or int(pk["id"]) != 32: wrong += 1
			else: nlv[int(pk["level"])] = int(nlv.get(int(pk["level"]), 0)) + 1
		for g2 in D.roll_special(st1b, lr, D.MODE_HERO, true):
			var pk2 := L2.parse_item_key(String((g2 as Dictionary)["key"]))
			if pk2.is_empty() or int(pk2["id"]) != 32: wrong += 1
			else: hlv[int(pk2["level"])] = int(hlv.get(int(pk2["level"]), 0)) + 1
	fails += _eq("희망의숲은 신경독소만", wrong, 0)
	fails += _true("일반 레벨 1~3", nlv.has(1) and nlv.has(2) and nlv.has(3) and not nlv.has(4))
	fails += _true("영웅 레벨 2~4", hlv.has(2) and hlv.has(3) and hlv.has(4) and not hlv.has(1))
	var nt := 0
	for k in nlv: nt += int(nlv[k])
	fails += _true("Lv1 ≈5/10 (%.3f)" % (float(nlv.get(1, 0)) / nt),
		absf(float(nlv.get(1, 0)) / nt - 0.5) < 0.05)
	# 영웅이 일반보다 자주 나온다(0.2% vs 0.1%).
	var ht := 0
	for k in hlv: ht += int(hlv[k])
	fails += _true("영웅 드랍이 더 잦다 (%d > %d)" % [ht, nt], ht > nt)

	# 보스가 아니면 안 나온다(boss_only).
	var nb := RandomNumberGenerator.new(); nb.seed = 93
	var nonboss := 0
	for _i in 100000:
		nonboss += D.roll_special(st1b, nb, D.MODE_NORMAL, false).size()
	fails += _eq("일반몹에서 지역 스크롤", nonboss, 0)

	# 화이트리스트가 지역 스크롤을 통과시킨다(그리고 남의 지역 것은 막는다).
	fails += _true("희망의숲 스크롤 허용",
		D.is_allowed(L2.item_key(32, 2), st1b, items, t, false, D.MODE_NORMAL))
	fails += _true("남의 지역 스크롤 불허",
		not D.is_allowed(L2.item_key(23, 2), st1b, items, t, false, D.MODE_NORMAL))
	# 영웅 전용 레벨(4)은 일반 난이도 화이트리스트에 없다.
	fails += _true("일반에 Lv4 없음",
		not D.is_allowed(L2.item_key(32, 4), st1b, items, t, false, D.MODE_NORMAL))
	fails += _true("영웅엔 Lv4 있음",
		D.is_allowed(L2.item_key(32, 4), st1b, items, t, true, D.MODE_HERO))

	if fails == 0:
		print("[test_drops] ALL PASS")
		quit(0)
	else:
		printerr("[test_drops] %d FAIL" % fails)
		quit(1)

## 표본 평균 품질(젬 티어 / 장비 등급×3 로 스케일 맞춤) — 상대비교용.
func _avg_quality(t, gems, equip, level: int, source: String, kades: bool) -> float:
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	var sum := 0.0
	var n := 0
	for _i in N:
		var key := D.roll_exploration(t, level, source, equip, rng, kades)
		if key == "": continue
		var g := G.parse_item_key(key)
		if not g.is_empty():
			sum += float(int(g["tier"])); n += 1
			continue
		var ck := E.parse_item_key(key)
		if ck.begins_with("basic:"):
			sum += float(int(ck.split(":")[2])) * 3.0; n += 1
	return sum / maxf(1.0, float(n))

## 그 키 목록이 전부 같은 속성의 먹이인가.
func _all_food_element(items: Dictionary, keys: Array, want: String) -> bool:
	for k in keys:
		var v: Dictionary = items.get(k, {})
		if String(v.get("category", "")) != "food":
			return false
		if D.normalize_element(v.get("element", "")) != want:
			return false
	return true

func _disjoint(a: Array, b: Array) -> bool:
	for x in a:
		if b.has(x):
			return false
	return true

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
