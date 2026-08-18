extends SceneTree

const K := preload("res://scripts/systems/kades.gd")
const I := preload("res://scripts/systems/incapacitation.gd")
const D := preload("res://scripts/systems/drops.gd")
const E := preload("res://scripts/systems/equipment.gd")

func _init() -> void:
	var fails := 0
	var kd = _json(_data_file("kades.json"))
	var ic = _json(_data_file("incapacitation.json"))
	var drops = _json(_data_file("drops.json"))
	var equip = _json(_data_file("equipment.json"))

	fails += _eq("각성했으면 페널티 0", K.penalty_pct(kd, true, "fire", "fire"), 0)
	fails += _eq("혼돈 = 35", K.penalty_pct(kd, false, "chaos", "fire"), 35)
	fails += _eq("신성 = 35", K.penalty_pct(kd, false, "holy", "holy"), 35)
	fails += _eq("던전과 같은 속성 = 25", K.penalty_pct(kd, false, "fire", "fire"), 25)
	fails += _eq("그 외 = 50", K.penalty_pct(kd, false, "fire", "aqua"), 50)
	fails += _eq("혼돈은 속성일치보다 우선", K.penalty_pct(kd, false, "chaos", "chaos"), 35)

	var st := {"hp": 1000, "att": 200, "def": 100, "cri": 30}
	var pen := K.apply_penalty(st, 50)
	fails += _eq("hp -50%", int(pen["hp"]), 500)
	fails += _eq("att -50%", int(pen["att"]), 100)
	fails += _eq("def -50%", int(pen["def"]), 50)
	fails += _eq("확률 스탯은 안 깎는다", int(pen["cri"]), 30)
	fails += _eq("원본 불변(순수함수)", int(st["hp"]), 1000)

	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var lo := 999
	var hi := 0
	for _i in 500:
		var lv := K.boss_level(kd, rng)
		lo = mini(lo, lv); hi = maxi(hi, lv)
	fails += _true("보스 레벨 >= 120", lo >= 120)
	fails += _true("보스 레벨 <= 200", hi <= 200)

	var by: Dictionary = drops["kades"]["artifact_by_dungeon"]
	fails += _eq("배정 던전 수", by.size(), 15)
	var tally := {}
	for k in by:
		var ts: Array = by[k]
		fails += _eq("던전 %s 는 4종" % k, ts.size(), 4)
		for t in ts:
			tally[t] = int(tally.get(t, 0)) + 1
	fails += _eq("아티팩트 종류 수", tally.size(), 6)
	for t in tally:
		fails += _eq("%s 등장 횟수(균등)" % t, int(tally[t]), 10)

	var rng2 := RandomNumberGenerator.new(); rng2.seed = 11
	var field := 3
	var allowed: Array = by[str(field)]
	var bad := 0
	var got := 0
	for _i in 3000:
		var key := D.roll_artifact(drops, D.SOURCE_BOSS, rng2, field)
		if key == "": continue
		got += 1
		var parsed := E.parse_item_key(key)
		var kind := parsed.split(":")[1]
		if not (kind in allowed):
			bad += 1
	fails += _true("아티팩트가 실제로 나온다", got > 0)
	fails += _eq("배정 밖 종류 0건", bad, 0)

	var rng3 := RandomNumberGenerator.new(); rng3.seed = 13
	var leaked := 0
	for _i in 3000:
		var key2 := D.roll_exploration(drops, 40, D.SOURCE_BOSS, equip, rng3, false, field)
		if not E.artifact_of(key2).is_empty():
			leaked += 1
	fails += _eq("카데스 밖 아티팩트 0건", leaked, 0)

	var now := 1_000_000
	fails += _eq("정상이면 안 걸림", I.is_down(0, now), false)
	fails += _eq("미래 시각이면 행동불능", I.is_down(now + 10, now), true)
	fails += _eq("과거 시각이면 회복됨", I.is_down(now - 10, now), false)
	fails += _eq("기본 회복 1시간", I.down_until(ic, now) - now, 3600)

	fails += _eq("남은 1시간 = 3다이아", I.instant_cost(ic, now + 3600, now), 3)
	fails += _eq("남은 30분 = 2다이아", I.instant_cost(ic, now + 1800, now), 2)
	fails += _eq("남은 29분 = 1다이아(최소 1)", I.instant_cost(ic, now + 1740, now), 1)
	fails += _eq("1초만 남아도 1다이아", I.instant_cost(ic, now + 1, now), 1)
	fails += _eq("정상이면 0다이아", I.instant_cost(ic, 0, now), 0)
	fails += _eq("이미 지난 시각도 0다이아", I.instant_cost(ic, now - 10, now), 0)
	var pay_bad := 0
	for r in [1, 1740, 1800, 3599, 3600, 5400, 7200]:
		var cost: int = I.instant_cost(ic, now + int(r), now)
		var orig_ok_min := int(r) / 1800 + 1
		if cost != orig_ok_min:
			pay_bad += 1
	fails += _eq("원작 지불검사와 동일", pay_bad, 0)

	var rng4 := RandomNumberGenerator.new(); rng4.seed = 17
	fails += _eq("cure 0 이면 절대 못 피함", I.avoids(0, rng4), false)
	fails += _eq("cure 100 이면 항상 피함", I.avoids(100, rng4), true)
	var avoided := 0
	for _i in 4000:
		if I.avoids(50, rng4):
			avoided += 1
	fails += _true("cure 50 이면 대략 절반(%d/4000)" % avoided,
		avoided > 1800 and avoided < 2200)

	fails += _eq("치료제 표가 비어 있다", (ic.get("cure_items", []) as Array).size(), 0)
	fails += _eq("elixir 는 치료제가 아니다", I.is_cure_item(ic, "elixir"), false)
	fails += _eq("아무 아이템이나 치료제는 아니다", I.is_cure_item(ic, "heal_potion1"), false)

	if fails == 0:
		print("[test_kades_incap] ALL PASS")
		quit(0)
	else:
		printerr("[test_kades_incap] %d FAIL" % fails)
		quit(1)

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

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
