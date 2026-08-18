extends SceneTree

const MARK_EXPECT := {
	1: 1,
	2: 1,
	3: 1002,
	5: 1002,
	11: 4,
	26: 9,
	35: 1002,
	48: 21,
	49: 1003,
	50: 1003,
	51: 1003,
	52: 23,
	53: 16,
	54: 1004,
	55: 1004,
	56: 1004,
	57: 19,
	74: {"field": 6, "phase": "night"},
	79: {"field": 7, "phase": "night"},
	86: {"field": 1, "phase": "night"},
	87: 1002,
	92: {"field": 1002, "phase": "kades"},
	96: 1004,
	100: {"field": 15, "phase": "kades"},
	101: 1002,
}

const PHASE_WAIT := {
	74: "night",
	92: "kades",
	58: "night",
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fails := 0
	var udb := root.get_node_or_null("/root/UserDB")
	if udb == null:
		print("FAIL: UserDB 오토로드 없음"); quit(1); return
	var SP: GDScript = load("res://scripts/core/story_progress.gd")
	var raw: Dictionary = udb.call("raw")
	raw["dragons"] = [{"uid": 9001, "id": 1, "level": 45}]
	raw["progress"] = {}

	fails += _true("1화는 앞 회차가 없어 바로 열린다", bool(SP.unlocked(1)))
	fails += _true("2화는 1화를 안 보면 잠긴다", not bool(SP.unlocked(2)))
	fails += _true("35화는 레벨이 차도 앞 회차 미관람이면 잠긴다", not bool(SP.unlocked(35)))
	raw["progress"]["scenario_1_0"] = true
	fails += _true("1화를 보면 2화가 열린다", bool(SP.unlocked(2)))
	fails += _eq("발급 전에는 수행 중 미션 없음", SP.pending_episode(), 0)
	raw["progress"]["story_mission_at_2"] = 24
	fails += _eq("멈춰 선 회차가 곧 수행 중 미션", SP.pending_episode(), 2)
	fails += _true("미완 상태에선 3화 잠김(2화 미관람)", not bool(SP.unlocked(3)))
	raw["progress"]["story_sq_2"] = 4
	fails += _eq("진행도 4/5 면 아직 수행 중", SP.pending_episode(), 2)
	raw["progress"]["story_sq_2"] = 5
	fails += _eq("5/5 채우면 수행 중 미션 없음", SP.pending_episode(), 0)
	fails += _true("미션만 끝내고 이어보기 전엔 3화 잠김", not bool(SP.unlocked(3)))
	raw["progress"]["scenario_2_0"] = true
	fails += _true("2화를 끝까지 보면 3화가 열린다", bool(SP.unlocked(3)))
	raw["progress"]["scenario_3_0"] = true
	fails += _true("3화(서브미션 없음) → 4화 해금", bool(SP.unlocked(4)))
	raw["dragons"] = [{"uid": 9001, "id": 1, "level": 1}]
	fails += _true("2화는 레벨 조건도 함께 본다", not bool(SP.unlocked(2)))
	raw["dragons"] = [{"uid": 9001, "id": 1, "level": 45}]

	if not raw.has("meta"):
		raw["meta"] = {}

	for no in MARK_EXPECT.keys():
		var ep := int(no)
		_goto_episode(raw, ep)
		var want = MARK_EXPECT[no]
		_set_phase(raw, String(want.get("phase", "")) if want is Dictionary else "")
		var want_f: int = int(want["field"]) if want is Dictionary else int(want)
		fails += _eq("%d화 마커 필드" % ep, int(SP.mark_field()), want_f)

	for no2 in PHASE_WAIT.keys():
		var ep2b := int(no2)
		_goto_episode(raw, ep2b)
		_set_phase(raw, "day" if String(PHASE_WAIT[no2]) != "day" else "night")
		fails += _eq("%d화 위상 어긋남 → 배지 없음" % ep2b, int(SP.mark_field()), 0)
		fails += _eq("%d화 대기 위상" % ep2b, String(SP.mark_pending_phase()), String(PHASE_WAIT[no2]))
		_set_phase(raw, String(PHASE_WAIT[no2]))
		fails += _eq("%d화 위상 맞으면 대기 해제" % ep2b, String(SP.mark_pending_phase()), "")
	_set_phase(raw, "day")

	var data := root.get_node_or_null("/root/Data")
	var blank: Array = []
	for ep2 in (data.call("story_episodes") as Array):
		var n := int(ep2)
		_goto_episode(raw, n)
		_set_phase(raw, _required_phase(SP, data, n))
		var f := int(SP.mark_field())
		if f <= 0:
			blank.append(n)
		if f == 999:
			blank.append(n)
	fails += _eq("마커 없는 회차 수(요구 위상으로 맞춘 뒤)", blank.size(), 0)
	if not blank.is_empty():
		print("   마커 0: ", blank)

	_set_phase(raw, "day")
	raw["progress"] = {}
	raw["dragons"] = []
	if fails == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAIL %d건" % fails)
		quit(1)

func _goto_episode(raw: Dictionary, ep: int) -> void:
	var prog: Dictionary = {}
	for k in range(1, ep):
		prog["scenario_%d_0" % k] = true
	raw["progress"] = prog

func _set_phase(raw: Dictionary, phase: String) -> void:
	raw["meta"]["kades_space"] = phase == "kades"
	raw["meta"]["yutakan_night"] = phase == "night"

func _required_phase(SP: GDScript, data: Node, n: int) -> String:
	var ov := SP.MARK_OVERRIDE as Dictionary
	if ov.has(n):
		var e = ov[n]
		return String((e as Dictionary).get("phase", "")) if e is Dictionary else ""
	var sm: Dictionary = data.call("story_scenario_mark", n)
	if sm.has("night"):
		return "night" if bool(sm["night"]) else "day"
	return ""

func _true(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1

func _eq(label: String, got, want) -> int:
	var ok: bool = got == want
	print(("  ok   " if ok else "  FAIL ") + "%s = %s (기대 %s)" % [label, str(got), str(want)])
	return 0 if ok else 1
