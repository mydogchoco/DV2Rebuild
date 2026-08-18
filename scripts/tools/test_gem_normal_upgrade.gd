extends SceneTree

const Gem := preload("res://scripts/systems/gem.gd")

func _init() -> void:
	var t: Dictionary = JSON.parse_string(FileAccess.open(
		_data_file("gems.json"), FileAccess.READ).get_as_text())
	var fails := 0

	var cfg: Dictionary = (t.get("upgrade", {}) as Dictionary).get("normal", {})
	fails += _eq("upgrade.normal 존재", not cfg.is_empty(), true)
	fails += _eq("gold_per_tier", int(cfg.get("gold_per_tier", 0)), 500)

	fails += _eq("골드 tier0 ×1", Gem.normal_upgrade_gold(0, t), 500)
	fails += _eq("골드 tier9 ×1", Gem.normal_upgrade_gold(9, t), 5000)
	fails += _eq("골드 tier9 ×3", Gem.normal_upgrade_gold(9, t, 3), 15000)
	fails += _eq("골드 tier18 ×1", Gem.normal_upgrade_gold(18, t), 9500)

	fails += _near("성공률 대상10 재료10", Gem.normal_success_rate(9, 9, t), 0.80)
	fails += _near("성공률 대상14 재료14", Gem.normal_success_rate(13, 13, t), 0.56)
	fails += _near("성공률 하한", Gem.normal_success_rate(18, 0, t), 0.05)
	fails += _eq("저티어는 1.0 초과", Gem.normal_success_rate(0, 0, t) > 1.0, true)
	fails += _eq("재료가 높을수록 유리",
		Gem.normal_success_rate(13, 18, t) > Gem.normal_success_rate(13, 5, t), true)
	fails += _eq("대상이 높을수록 불리",
		Gem.normal_success_rate(15, 9, t) < Gem.normal_success_rate(5, 9, t), true)

	fails += _eq("표시 상한 100", Gem.normal_success_pct(0, 0, t), 100)
	fails += _eq("표시 대상10 재료10", Gem.normal_success_pct(9, 9, t), 80)
	fails += _eq("표시 하한 5", Gem.normal_success_pct(18, 0, t), 5)

	var nm := _first_normal_name(t)
	fails += _eq("일반 젬 이름을 찾았다", nm != "", true)
	if nm != "":
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var r: Dictionary = Gem.roll_normal_upgrade({"name": nm, "tier": 0}, 0, t, rng)
		fails += _eq("확정 성공", bool(r.get("ok", false)), true)
		fails += _eq("성공 → 티어 +1", int((r["inst"] as Dictionary)["tier"]), 1)
		fails += _eq("성공 → 파손 없음", (r["inst"] as Dictionary).has("broken"), false)
		var maxt := Gem.max_tier(nm, t)
		fails += _eq("최대 티어는 {}",
			Gem.roll_normal_upgrade({"name": nm, "tier": maxt}, 0, t, rng).is_empty(), true)
		fails += _eq("파손 젬은 {}",
			Gem.roll_normal_upgrade({"name": nm, "tier": 3, "broken": true}, 5, t, rng).is_empty(),
			true)
		var ok_n := 0
		var broke := false
		for _i in 5000:
			var rr: Dictionary = Gem.roll_normal_upgrade({"name": nm, "tier": 17}, 0, t, rng)
			if rr.is_empty():
				break
			if bool(rr["ok"]):
				ok_n += 1
			elif bool((rr["inst"] as Dictionary).get("broken", false)):
				broke = true
		fails += _eq("실패는 파손", broke, true)
		fails += _eq("5%% 근처 (%d/5000)" % ok_n, ok_n > 100 and ok_n < 450, true)

	var cats := {"normal": 0, "hybrid": 0, "soul": 0}
	for gn: String in (t["gems"] as Dictionary):
		var c := String(((t["gems"] as Dictionary)[gn] as Dictionary).get("category", ""))
		if cats.has(c):
			cats[c] = int(cats[c]) + 1
	fails += _eq("일반 3종", int(cats["normal"]), 3)
	fails += _eq("혼성 7종", int(cats["hybrid"]), 7)
	fails += _eq("소울 4종", int(cats["soul"]), 4)
	if nm != "":
		fails += _eq("is_category(일반)", Gem.is_category(nm, t, "normal"), true)
		fails += _eq("is_category(혼성 아님)", Gem.is_category(nm, t, "hybrid"), false)

	print("[test_gem_normal_upgrade] %s" % ("OK" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)

func _first_normal_name(t: Dictionary) -> String:
	var names: Array = (t["gems"] as Dictionary).keys()
	names.sort()
	for gn in names:
		if String(((t["gems"] as Dictionary)[gn] as Dictionary).get("category", "")) == "normal":
			return String(gn)
	return ""

func _eq(what: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  X %s: got %s, want %s" % [what, str(got), str(want)])
	return 1

func _near(what: String, got: float, want: float, eps := 0.0001) -> int:
	if absf(got - want) <= eps:
		return 0
	printerr("  X %s: got %f, want %f" % [what, got, want])
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
