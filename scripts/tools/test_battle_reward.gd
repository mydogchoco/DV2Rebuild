extends SceneTree

const BR := preload("res://scripts/systems/battle_reward.gd")

var _drops: Dictionary

func _init() -> void:
	var fails := 0
	_drops = _json(_data_file("drops.json"))
	var stages: Dictionary = (_json(_data_file("stages.json")).get("stages", {}) as Dictionary)

	for lv in [1, 10, 22, 45, 50]:
		fails += _eq("일반 골드 Lv%d" % lv, _g(lv, false, false), lv * 12 + 30)
		fails += _eq("일반 EXP Lv%d" % lv, _e(lv, false, false), lv * 8 + 20)

	for lv in [1, 22, 45, 50]:
		fails += _eq("보스 골드 Lv%d" % lv, _g(lv, true, false), (lv * 12 + 30) * 16)
	fails += _eq("보스 골드 Lv45 실측", _g(45, true, false), 9120)
	fails += _eq("보스+정예 Lv45", _g(45, true, true), 9120 * 2)
	fails += _eq("일반+정예 Lv45", _g(45, false, true), 570 * 2)

	fails += _eq("보스 EXP Lv45(×3)", _e(45, true, false), (45 * 8 + 20) * 3)
	fails += _eq("정예 EXP Lv45(×2)", _e(45, false, true), (45 * 8 + 20) * 2)

	var stub := {"rewards": {"gold": 1234, "exp": null}}
	fails += _eq("override 일반", BR.amount(BR.GOLD, 45, false, false, _drops, stub), 1234)
	fails += _eq("override 보스(배수는 그대로)",
		BR.amount(BR.GOLD, 45, true, false, _drops, stub), 1234 * 16)
	fails += _eq("override 없는 축은 공식",
		BR.amount(BR.EXP, 45, false, false, _drops, stub), 45 * 8 + 20)
	fails += _eq("stage 안 넘겨도 공식", BR.amount(BR.GOLD, 45, false, false, _drops), 570)
	var authored := 0
	for sid: String in stages:
		if BR.stage_override(BR.GOLD, stages[sid]) >= 0:
			authored += 1
	print("던전별 골드 override 지정: %d/%d" % [authored, stages.size()])

	var lv45 := _run_total(stages, "15")
	print("Lv45 빛의 탑 1바퀴 = %d골드 (조정 전 4,560)" % lv45)
	fails += _eq("Lv45 던전 1바퀴", lv45, 5 * 570 + 9120)
	var total_all := 0
	for sid: String in stages:
		total_all += _run_total(stages, sid)
	print("전 지역 1바퀴 합계 = %d골드 (조정 전 75,054)" % total_all)

	print("=== %s ===" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(0 if fails == 0 else 1)

func _g(lv: int, boss: bool, elite: bool) -> int:
	return BR.amount(BR.GOLD, lv, boss, elite, _drops)

func _e(lv: int, boss: bool, elite: bool) -> int:
	return BR.amount(BR.EXP, lv, boss, elite, _drops)

func _run_total(stages: Dictionary, sid: String) -> int:
	var st: Dictionary = stages.get(sid, {})
	var es: Array = st.get("enemies", [])
	var sum := 0
	for i in es.size():
		var e: Dictionary = es[i]
		var last := i == es.size() - 1
		sum += BR.amount(BR.GOLD, int(e.get("level", 1)),
			last and bool(e.get("boss", false)), false, _drops, st)
	return sum

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text()) as Dictionary

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  ✗ %s: %s (기대 %s)" % [label, got, want])
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
