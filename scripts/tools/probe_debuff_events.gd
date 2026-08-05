extends SceneTree
## 임시 프로브 — 디버프 스킬이 실제로 어떤 이벤트를 흘리는지 본다.
## 사용자 지적 2026-08-05: "뼈 부수기(46)가 발동돼도 상대 HP바에 디버프 아이콘이 안 뜬다."
## 화면을 안 띄우고 `Battle` 이 내는 이벤트만 찍어 render 문제인지 logic 문제인지 가른다.
##
## 실행: godot --headless --path . --script res://scripts/tools/probe_debuff_events.gd --quit-after 8

const B := preload("res://scripts/systems/battle.gd")

func _init() -> void:
	var skills := _json("res://data/skills.json")
	var cfg := _json("res://data/combat.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805

	for sid in [46, 15, 23, 32, 150]:
		var caster := B.make_combatant("A0", "ally", "fire", {"hp": 5000, "att": 300, "def": 300})
		var foe := B.make_combatant("E0", "enemy", "dark", {"hp": 5000, "att": 300, "def": 300})
		var evs: Array = B._apply_skill_effect(caster, {"id": sid, "level": 5},
			[caster], [foe], rng, cfg, skills)
		var names: Array = []
		for e in evs:
			var d := e as Dictionary
			names.append("{target=%s debuff=%s skill_id=%s turns=%s}" % [
				str(d.get("target", "")), str(d.get("debuff", "-")),
				str(d.get("skill_id", "-")), str(d.get("turns", "-"))])
		print("skill %-4d events=%d %s" % [sid, evs.size(), ", ".join(PackedStringArray(names))])
		var kinds: Array = []
		for e2 in foe.get("effects", []):
			var f := e2 as Dictionary
			kinds.append("%s/%s(src=%s,t=%s)" % [String(f.get("kind", "")),
				String(f.get("flag", f.get("stat", ""))), str(f.get("source", "")),
				str(f.get("turns", ""))])
		print("          foe.effects = %s" % ", ".join(PackedStringArray(kinds)))
	quit(0)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}
