extends SceneTree

func _init() -> void:
	var fails := 0
	var skills: Dictionary = JSON.parse_string(FileAccess.open(
		_data_file("skills.json"), FileAccess.READ).get_as_text())
	var combat: Dictionary = JSON.parse_string(FileAccess.open(
		_data_file("combat.json"), FileAccess.READ).get_as_text())

	var shapes := {}
	var n := 0
	for k: String in skills:
		var sd = skills[k]
		if not (sd is Dictionary) or not (sd as Dictionary).has("slot"):
			continue
		var sh := String((sd as Dictionary)["slot"])
		if sh == "":
			continue
		shapes[sh] = int(shapes.get(sh, 0)) + 1
		n += 1
		if not Loadout.slot_matches("star", sd):
			fails += _fail("☆칸이 스킬 %s(%s)를 일치로 안 본다 — 조커가 깨졌다" % [k, sh])
		for other: String in ["tri", "sq", "cir"]:
			var got := Loadout.slot_matches(other, sd)
			if got != (other == sh):
				fails += _fail("%s칸 × %s스킬 판정이 %s (기대 %s)"
					% [other, sh, got, other == sh])
	print("스킬 %d종 모양 분포 %s" % [n, shapes])
	if int(shapes.get("star", 0)) > 0:
		fails += _fail("skills.json 에 ☆ 모양 스킬이 %d종 생겼다 — 이 시험의 전제를 다시 볼 것"
			% int(shapes["star"]))

	var tri_id := 0
	for k: String in skills:
		var sd = skills[k]
		if sd is Dictionary and String((sd as Dictionary).get("slot", "")) == "tri" \
				and bool((sd as Dictionary).get("active", true)):
			tri_id = int(k)
			break
	if tri_id == 0:
		fails += _fail("△ 스킬을 못 찾았다(테스트 표본 부재)")
	else:
		var pct := float((combat.get("skill_slot_match", {}) as Dictionary).get("power_pct", 0.0))
		var caster := {"skills": [{"id": tri_id, "level": 1}], "skill_slots": ["star"]}
		var m := Battle.slot_match_mult(caster, tri_id, combat, skills)
		if not is_equal_approx(m, 1.0 + pct / 100.0):
			fails += _fail("☆칸 피해 배수 %.3f (기대 %.3f)" % [m, 1.0 + pct / 100.0])
		caster["skill_slots"] = ["sq"]
		var m2 := Battle.slot_match_mult(caster, tri_id, combat, skills)
		if not is_equal_approx(m2, 1.0):
			fails += _fail("불일치 칸인데 배수가 %.3f" % m2)

		var lvb := int((combat.get("skill_slot_match", {}) as Dictionary).get("level_bonus", 0))
		if lvb <= 0:
			fails += _fail("combat.json 에 level_bonus 가 없다(칸 일치 공통 보너스 소실)")
		for pair: Array in [["star", lvb], ["sq", 0]]:
			var s := {"id": tri_id, "level": 1}
			var c := {"skills": [s], "skill_slots": [String(pair[0])]}
			Battle._init_combatant_skills(c, skills, combat)
			var got := Battle._lv(c, s)
			if got != 1 + int(pair[1]):
				fails += _fail("%s칸 △스킬 효과 레벨 %d (기대 %d)"
					% [pair[0], got, 1 + int(pair[1])])
		var lbl := Loadout.slot_match_label(skills[str(tri_id)], combat)
		if not ("레벨" in lbl) or not ("%" in lbl):
			fails += _fail("툴팁 표기 '%s' — 레벨/피해 두 몫이 다 안 보인다" % lbl)
		var cats: Array = (combat.get("skill_slot_match", {}) as Dictionary).get("heal_categories", [])
		for k2: String in skills:
			var hd = skills[k2]
			if not (hd is Dictionary) or not (String((hd as Dictionary).get("category", "")) in cats):
				continue
			var hs := {"id": int(k2), "level": 1}
			var hc := {"skills": [hs], "skill_slots": ["star"]}
			Battle._init_combatant_skills(hc, skills, combat)
			if Battle._lv(hc, hs) != 1 + lvb:
				fails += _fail("회복 계열 %s 가 레벨 보너스를 못 받았다" % k2)
			var hc2 := {"skills": [{"id": int(k2), "level": 1}], "skill_slots": ["sq"]}
			Battle._init_combatant_skills(hc2, skills, combat)
			var use_on := int((hc["skill_uses"] as Dictionary).get(int(k2), 0))
			var use_off := int((hc2["skill_uses"] as Dictionary).get(int(k2), 0))
			if use_on <= use_off:
				fails += _fail("회복 계열 %s 사용횟수 일치 %d ≤ 불일치 %d" % [k2, use_on, use_off])

	for shape: String in ["triangle", "square", "circle", "star"]:
		for suffix: String in ["", "_bg", "_light"]:
			var p := "res://assets/converted/common_ui/common_skill_%s%s.tres" % [shape, suffix]
			if not ResourceLoader.exists(p):
				fails += _fail("프레임 없음 %s" % p)
	for snd: String in ["effect_skill_ok", "effect_skill_ok2"]:
		var found := false
		for dir: String in ["res://assets/music/%s.mp3", "res://DV2/music/%s.mp3"]:
			if ResourceLoader.exists(dir % snd):
				found = true
				break
		if not found:
			fails += _fail("효과음 없음 %s" % snd)

	print("=== %s ===" % ("ALL PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)

func _fail(msg: String) -> int:
	print("FAIL: ", msg)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
