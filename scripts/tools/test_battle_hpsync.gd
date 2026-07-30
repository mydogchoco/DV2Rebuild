extends SceneTree
## 진단용: 전투 UI(scripts/ui/battle.gd)가 이벤트로 누적하는 HP 와
## 로직(Battle.simulate)이 실제로 들고 있는 HP 가 어긋나는지 전수 대조한다.
## 증상 근거: "몬스터 HP 표시가 0인데 죽지 않고 몇 대 더 때려야 끝난다"(사용자 2026-07-27).
## 실행: godot --headless --path . --script res://scripts/tools/test_battle_hpsync.gd

func _init() -> void:
	var cfg := _load("res://data/combat.json")
	var sdb := _load("res://data/skills.json")
	var bad := 0
	var runs := 300
	var causes := {}
	for it in runs:
		var rng := RandomNumberGenerator.new()
		rng.seed = it
		var pa: Array = []
		var keys: Array = sdb.keys()
		for i in 3:
			var sk: Array = []
			# 스킬을 무작위로 3개씩 물려 스킬 경로도 태운다.
			for j in 3:
				sk.append({"id": int(keys[rng.randi() % keys.size()]), "level": 3})
			pa.append(Battle.make_combatant("A%d" % i, "ally", ["fire", "aqua", "light"][i],
				{"hp": 900, "att": 180, "def": 90, "cri": 10, "evd": 8, "blk": 8}, 0.0, sk))
		var eb := Battle.make_combatant("E0", "enemy", "wind",
			{"hp": 3000, "att": 160, "def": 70, "cri": 8, "evd": 6, "blk": 8})
		# UI 미러: 뷰가 들고 있는 hp (battle.gd _hurt/_heal 과 동일한 규칙)
		var mirror := {}
		var mmax := {}
		for c in pa:
			mirror[c["name"]] = int(c["hp"]); mmax[c["name"]] = int(c["hp_max"])
		mirror["E0"] = int(eb["hp"]); mmax["E0"] = int(eb["hp_max"])
		_mmax = mmax
		var res := Battle.simulate(pa, [eb], rng, cfg, sdb)
		for ev in res["events"]:
			_mirror_event(ev, mirror, causes)
		# 대조
		for c in (pa + [eb]):
			var nm := String(c["name"])
			if int(mirror[nm]) != int(c["hp"]):
				bad += 1
				# 증상은 "뷰가 로직보다 적게 남았다"(0 표기인데 살아 있음) 쪽이다.
				var dir := "UI<LOGIC(증상)" if int(mirror[nm]) < int(c["hp"]) else "UI>LOGIC"
				if bad <= 16:
					print("MISMATCH ", dir, " run=", it, " ", nm, " ui=", mirror[nm],
						" logic=", c["hp"], " alive=", c["alive"])
	print("=== runs=", runs, "  mismatch entities=", bad)
	print("이벤트 타입별 뷰 감산 횟수: ", causes)
	quit(0)

## battle.gd `_play_event` 가 뷰 HP 를 건드리는 지점만 그대로 옮긴 것.
func _mirror_event(ev: Dictionary, m: Dictionary, causes: Dictionary) -> void:
	var t := String(ev.get("type", ""))
	match t:
		"normal", "double", "awaken":
			var d := String(ev.get("defender", ""))
			var a := String(ev.get("attacker", ""))
			if not bool(ev.get("miss", false)):
				if int(ev.get("damage", 0)) > 0: _sub(m, d, int(ev["damage"]), causes, t)
				if int(ev.get("lifesteal", 0)) > 0: _add(m, a, int(ev["lifesteal"]))
				if int(ev.get("reflect", 0)) > 0: _sub(m, a, int(ev["reflect"]), causes, t + ":reflect")
		"skill":
			var tg := String(ev.get("target", ""))
			var cs := String(ev.get("caster", ""))
			if bool(ev.get("interrupt", false)): return
			if int(ev.get("damage", 0)) > 0: _sub(m, tg, int(ev["damage"]), causes, "skill")
			if int(ev.get("heal", 0)) > 0: _add(m, tg, int(ev["heal"]))
			if int(ev.get("target_loss", 0)) > 0: _sub(m, tg, int(ev["target_loss"]), causes, "skill:target_loss")
			if int(ev.get("self_loss", 0)) > 0: _sub(m, cs, int(ev["self_loss"]), causes, "skill:self_loss")
		"confused":
			_sub(m, String(ev.get("actor", "")), int(ev.get("damage", 0)), causes, "confused")
		"dot", "timed":
			_sub(m, String(ev.get("target", "")), int(ev.get("damage", 0)), causes, t)

func _sub(m: Dictionary, k: String, v: int, causes: Dictionary, why: String) -> void:
	if not m.has(k): return
	m[k] = maxi(0, int(m[k]) - v)
	causes[why] = int(causes.get(why, 0)) + 1

var _mmax: Dictionary = {}
func _add(m: Dictionary, k: String, v: int) -> void:
	if not m.has(k): return
	m[k] = mini(int(_mmax.get(k, 999999)), int(m[k]) + v)   # _heal 도 hp_max 로 클램프한다

func _load(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}
