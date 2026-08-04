extends SceneTree
## 헤드리스 상태이상 **면역** 검증 (§8 — logic 은 화면 없이 검증).
##
## 사용자 지적 2026-08-05: "한울 각성스킬이 '모든 상태이상 무시' 인데 빙결의 표식 등을
## 받으면 HP바 위에 디버프가 그대로 올라간다."
## 여기서 확인하는 것:
##   ① 각성스킬 777(성좌의 주권자)이 `status_immune` 플래그를 실제로 심는가
##   ② 면역 대상에게 플래그형 디버프(150 빙결의 표식 = no_evade)가 **안 걸리는가**
##   ③ 그 이벤트에 `debuff` 가 남지 않는가(= 화면에 아이콘이 안 뜬다)
##   ④ 🟦 확장분 — 지속피해(32)·받는피해증가(23)·능력치감소(120)도 막히는가
##
## 실행: godot --headless --path . --script res://scripts/tools/test_immune.gd --quit-after 5

const B := preload("res://scripts/systems/battle.gd")
const AW := preload("res://scripts/systems/awaken_skill.gd")

func _init() -> void:
	var fails := 0
	var skills := _json("res://data/skills.json")
	var cfg := _json("res://data/combat.json")
	var awaken := _json("res://data/skill_awaken.json")

	# ① 면역 플래그가 심어지는가
	var me := B.make_combatant("A0", "ally", "light", {"hp": 5000, "att": 300, "def": 300})
	me["awaken_no"] = 777
	me["dragon_id"] = 777
	var foe := B.make_combatant("E0", "enemy", "dark", {"hp": 5000, "att": 300, "def": 300})
	AW.apply_battle([me], [foe], awaken, {})
	fails += _eq("① 777 이 status_immune 을 심는다", _has(me, "status_immune"), true)

	# 대조군 — 각성스킬 없는 드래곤
	var plain := B.make_combatant("A1", "ally", "light", {"hp": 5000, "att": 300, "def": 300})
	fails += _eq("① 대조군은 면역이 없다", _has(plain, "status_immune"), false)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805

	# ②③ 플래그형 — 150 빙결의 표식(적 전체 no_evade 3턴)
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

	# ④ 플래그가 아닌 해로운 효과들
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

	print("test_immune: %s (%d fail)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _has(c: Dictionary, flag: String) -> bool:
	for e in c.get("effects", []):
		var d := e as Dictionary
		if String(d.get("kind", "")) == "status" and String(d.get("flag", "")) == flag:
			return true
	return false

## 그 스킬이 남긴 그 종류의 효과가 있는가. `stat` 은 **감소(음수)** 만 본다.
func _has_kind(c: Dictionary, kind: String, src: int) -> bool:
	for e in c.get("effects", []):
		var d := e as Dictionary
		if String(d.get("kind", "")) != kind or int(d.get("source", 0)) != src:
			continue
		if kind == "stat" and float(d.get("value", 0.0)) >= 0.0:
			continue
		return true
	return false

## 앞 검사가 남긴 효과를 치운다(대조군이 누적되면 판정이 흐려진다).
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
