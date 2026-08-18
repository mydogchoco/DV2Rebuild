extends SceneTree

const Gem := preload("res://scripts/systems/gem.gd")

func _init() -> void:
	var t: Dictionary = JSON.parse_string(FileAccess.open(
		_data_file("gems.json"), FileAccess.READ).get_as_text())
	var fails := 0

	var video_counts := [12, 11, 642, 597, 439, 1207]
	var total := 0
	for c in video_counts:
		total += int(c)
	fails += _eq("젬분해4 총 개수", total, 2908)
	fails += _eq("젬분해4 골드", Gem.disassemble_gold(total, t), 1454000)
	fails += _eq("골드 1개", Gem.disassemble_gold(1, t), 500)

	for pair in [[0, 1], [1, 1], [5, 1], [9, 5], [12, 19], [16, 110], [18, 266]]:
		var tier := int((pair as Array)[0])
		fails += _eq("가루 tier=%d" % tier, Gem.disassemble_dust(tier, t), int((pair as Array)[1]))

	fails += _eq("point_bonus(0)", Gem.point_bonus(0, t), 0)
	fails += _eq("point_bonus(2)", Gem.point_bonus(2, t), 1)
	fails += _eq("point_bonus(6)", Gem.point_bonus(6, t), 3)
	fails += _eq("point_bonus(100)", Gem.point_bonus(100, t), 50)

	var want := {"ATTDEF": "SOULATT", "ATTHP": "SOULATT", "DEFATT": "SOULDEF",
		"DEFHP": "SOULDEF", "HPATT": "SOULHP", "HPDEF": "SOULHP", "ATTDEFHP": "SOULALL"}
	for nm: String in (t["gems"] as Dictionary):
		var gd: Dictionary = (t["gems"] as Dictionary)[nm]
		var code := String(gd.get("code", ""))
		if want.has(code):
			fails += _eq("%s promote_to" % code, String(gd.get("promote_to", "")), String(want[code]))
		elif String(gd.get("category", "")) != "soul":
			fails += _eq("%s 는 승급 대상 아님" % code, String(gd.get("promote_to", "")), "")

	print("[test_gem_disassemble] %s" % ("OK" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)

func _eq(what: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  ✗ %s: got %s, want %s" % [what, str(got), str(want)])
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
