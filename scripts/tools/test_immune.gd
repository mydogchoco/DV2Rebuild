extends SceneTree

const B := preload("res://scripts/systems/battle.gd")
const AW := preload("res://scripts/systems/awaken_skill.gd")

func _init() -> void:
	var fails := 0
	var skills := _json(_data_file("skills.json"))
	var cfg := _json(_data_file("combat.json"))
	var awaken := _json(_data_file("skill_awaken.json"))

	var me := B.make_combatant("A0", "ally", "light", {"hp": 5000, "att": 300, "def": 300})
	me["awaken_no"] = 777
	me["dragon_id"] = 777
	var foe := B.make_combatant("E0", "enemy", "dark", {"hp": 5000, "att": 300, "def": 300})
	AW.apply_battle([me], [foe], awaken, {})
	fails += _eq("① 777 이 status_immune 을 심는다", _has(me, "status_immune"), true)

	var plain := B.make_combatant("A1", "ally", "light", {"hp": 5000, "att": 300, "def": 300})
	fails += _eq("① 대조군은 면역이 없다", _has(plain, "status_immune"), false)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805

	for pair in [["면역", me, false], ["대조군", plain, true]]:
		var tgt: Dictionary = pair[1]
		var want: bool = pair[2]
		var caster := B.make_combatant("E9", "enemy", "dark", {"hp": 100, "att": 10, "def": 10})
		var evs: Array = B._apply_skill_effect(caster, {"id": 150, "level": 5},
			[caster], [tgt], rng, cfg, skills)
		fails += _eq("② %s 에 no_evade 가 걸린다" % pair[0], _has(tgt, "no_evade"), want)
		var has_debuff := false
		for e in evs:
			if String((e as Dictionary).get("debuff", "")) != "":
				has_debuff = true
		fails += _eq("③ %s 이벤트에 debuff 표기" % pair[0], has_debuff, want)

	for spec in [[32, "dot"], [23, "dmg_taken"], [120, "stat"]]:
		var sid := int(spec[0])
		var kind := String(spec[1])
		for pair2 in [["면역", me, false], ["대조군", plain, true]]:
			var tgt2: Dictionary = pair2[1]
			var want2: bool = pair2[2]
			_strip(tgt2, kind)
			var caster2 := B.make_combatant("E8", "enemy", "dark", {"hp": 100, "att": 10, "def": 10})
			B._apply_skill_effect(caster2, {"id": sid, "level": 5},
				[caster2], [tgt2], rng, cfg, skills)
			fails += _eq("④ %s 에 스킬 %d(%s)" % [pair2[0], sid, kind],
				_has_kind(tgt2, kind, sid), want2)

	for sid2 in [15, 22, 23, 32, 46, 54, 120, 130, 140, 150, 160, 170]:
		var mon := B.make_combatant("E7", "enemy", "dark", {"hp": 5000, "att": 300, "def": 300})
		var hero := B.make_combatant("A7", "ally", "light", {"hp": 5000, "att": 300, "def": 300})
		hero["awaken_no"] = 777
		hero["dragon_id"] = 777
		AW.apply_battle([hero], [mon], awaken, {})
		var evs2: Array = B._apply_skill_effect(mon, {"id": sid2, "level": 5},
			[mon], [hero], rng, cfg, skills)
		var shown := false
		var marked := evs2.size() > 0
		for e3 in evs2:
			var d3 := e3 as Dictionary
			if d3.has("debuff") or d3.has("timed_turns"):
				shown = true
			if not bool(d3.get("immune", false)):
				marked = false
		fails += _eq("⑤ 스킬 %d — 면역 대상 이벤트에 디버프 표기 없음" % sid2, shown, false)
		fails += _eq("⑤ 스킬 %d — immune 표시(render 가 이펙트를 끈다)" % sid2, marked, true)
		fails += _eq("⑤ 스킬 %d — 효과도 안 걸린다" % sid2, _has_src(hero, sid2), false)

	print("test_immune: %s (%d fail)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)

func _has(c: Dictionary, flag: String) -> bool:
	for e in c.get("effects", []):
		var d := e as Dictionary
		if String(d.get("kind", "")) == "status" and String(d.get("flag", "")) == flag:
			return true
	return false

func _has_kind(c: Dictionary, kind: String, src: int) -> bool:
	for e in c.get("effects", []):
		var d := e as Dictionary
		if String(d.get("kind", "")) != kind or int(d.get("source", 0)) != src:
			continue
		if kind == "stat" and float(d.get("value", 0.0)) >= 0.0:
			continue
		return true
	return false

func _has_src(c: Dictionary, src: int) -> bool:
	for e in c.get("effects", []):
		if int((e as Dictionary).get("source", 0)) == src:
			return true
	return false

func _strip(c: Dictionary, kind: String) -> void:
	var keep: Array = []
	for e in c.get("effects", []):
		if String((e as Dictionary).get("kind", "")) != kind:
			keep.append(e)
	c["effects"] = keep

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s — got %s, want %s" % [label, str(got), str(want)])
	return 1

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
