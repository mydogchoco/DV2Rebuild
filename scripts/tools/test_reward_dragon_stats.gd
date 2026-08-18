extends Node

func _ready() -> void:
	var fails := 0
	var dno := 9
	var ddef := Data.get_dragon(dno)
	var per := Growth.tier_growth(ddef, Data.stat_table)
	fails += _true("기준선 표에 티어가 있다(id=%d)" % dno, int(per.get("hp", 0)) > 0)

	var inst := UserDB._new_dragon(dno, 50, UserDB._zero_bonus())
	fails += _eq("Lv.50 개체 gain_log 길이", (inst.get("gain_log", []) as Array).size(), 49)

	var lv1 := Growth.main_stats(ddef, Data.stat_table, [], UserDB._zero_bonus().get("base", {}))
	var lv50 := Growth.main_stats(ddef, Data.stat_table, inst.get("gain_log", []),
		UserDB._zero_bonus().get("base", {}))
	fails += _true("Lv.50 스탯이 Lv.1 보다 크다(HP)", int(lv50["hp"]) > int(lv1["hp"]))
	fails += _eq("Lv.50 HP = base + 49×성장",
		int(lv50["hp"]), int(lv1["hp"]) + 49 * int(per["hp"]))
	fails += _eq("등급 = 기준선 7.0",
		snappedf(Growth.compute_grade(ddef, Data.stat_table, inst.get("stat_bonus", {}),
			inst.get("gain_log", []), Data.level_curve.get("grade", {})), 0.01), 7.0)

	var fresh := UserDB._new_dragon(dno, 1, UserDB._zero_bonus())
	fails += _eq("Lv.1 개체는 gain_log 비어 있다", (fresh.get("gain_log", []) as Array).size(), 0)

	var inv := {}
	var broken := {"uid": 101, "id": dno, "level": 50, "gain_log": []}
	var mine := {"uid": 102, "id": dno, "level": 5, "gain_log": [
		{"hp": 1, "att": 1, "def": 1}, {"hp": 2, "att": 1, "def": 0}, {"hp": 1, "att": 0, "def": 2}]}
	var fine := {"uid": 103, "id": dno, "level": 3, "gain_log": [
		{"hp": 9, "att": 9, "def": 9}, {"hp": 8, "att": 8, "def": 8}]}
	for dr in [broken, mine, fine]:
		UserDB._ensure_dragon_schema(dr, inv)

	fails += _eq("(a) 빈 성장분이 49개로 복구", (broken["gain_log"] as Array).size(), 49)
	fails += _eq("(b) 꼬리만 채워 4개", (mine["gain_log"] as Array).size(), 4)
	fails += _eq("(b) 기존 롤값 보존", int(((mine["gain_log"] as Array)[1] as Dictionary)["hp"]), 2)
	fails += _eq("(b) 채운 칸은 티어 최대치",
		int(((mine["gain_log"] as Array)[3] as Dictionary)["hp"]), int(per["hp"]))
	fails += _eq("(c) 정합한 개체는 그대로", (fine["gain_log"] as Array).size(), 2)
	fails += _eq("(c) 값도 그대로", int(((fine["gain_log"] as Array)[0] as Dictionary)["hp"]), 9)

	var before := JSON.stringify([broken, mine, fine])
	for dr in [broken, mine, fine]:
		UserDB._ensure_dragon_schema(dr, inv)
	fails += _eq("멱등", JSON.stringify([broken, mine, fine]), before)

	print("[rewardstat] %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("[rewardstat] FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	print("[rewardstat] FAIL %s" % label)
	return 1
