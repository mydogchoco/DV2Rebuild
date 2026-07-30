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
	var slot_bad := 0
	var slot_lo := 99
	var slot_hi := 0
	for _i in N:
		var k2 := G.parse_item_key(D.roll_gem_slot(t, gems, rng))
		if k2.is_empty():
			slot_bad += 1; continue
		if String(G.gem_def(String(k2["name"]), gems).get("category", "")) != "normal":
			slot_bad += 1
		slot_lo = mini(slot_lo, int(k2["tier"]))
		slot_hi = maxi(slot_hi, int(k2["tier"]))
	fails += _eq("골드 뽑기는 일반젬만", slot_bad, 0)
	fails += _eq("골드 뽑기 최소 단계 = 0", slot_lo, 0)
	fails += _eq("골드 뽑기 최대 단계 = 18(원형)", slot_hi, 18)
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
