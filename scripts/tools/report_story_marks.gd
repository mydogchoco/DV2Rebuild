extends SceneTree

var _name: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var udb := root.get_node_or_null("/root/UserDB")
	var data := root.get_node_or_null("/root/Data")
	if udb == null or data == null:
		print("FAIL: 오토로드 없음"); quit(1); return
	var SP: GDScript = load("res://scripts/core/story_progress.gd")
	_build_names(data)

	var raw: Dictionary = udb.call("raw")
	raw["dragons"] = [{"uid": 9001, "id": 1, "level": 45}]
	if not raw.has("meta"):
		raw["meta"] = {}

	var by_src: Dictionary = {}
	var by_field: Dictionary = {}
	var by_phase: Dictionary = {}
	print("회차 | 필드 | 자리                        | 위상  | 출처")
	print("-----+------+-----------------------------+-------+------------------")
	for ep in (data.call("story_episodes") as Array):
		var n := int(ep)
		var prog: Dictionary = {}
		for k in range(1, n):
			prog["scenario_%d_0" % k] = true
		raw["progress"] = prog

		var sm: Dictionary = data.call("story_scenario_mark", n)
		var phase := _required_phase(SP, n, sm)
		raw["meta"]["kades_space"] = phase == "kades"
		raw["meta"]["yutakan_night"] = phase == "night"
		var f := int(SP.mark_field())
		var src := _source(SP, data, n, sm)
		by_src[src] = int(by_src.get(src, 0)) + 1
		by_field[f] = int(by_field.get(f, 0)) + 1
		by_phase[phase] = int(by_phase.get(phase, 0)) + 1
		print("%4d | %4d | %-27s | %-5s | %s" % [n, f, _label(f), phase, src])
	raw["meta"]["yutakan_night"] = false
	raw["meta"]["kades_space"] = false

	print("\n── 출처별 회차 수 ──")
	for k in _sorted(by_src.keys()):
		print("  %-22s %d" % [k, int(by_src[k])])
	print("\n── 위상별 회차 수 ──")
	for kp in _sorted(by_phase.keys()):
		print("  %-8s %d" % [String(kp), int(by_phase[kp])])
	print("\n── 필드별 회차 수 ──")
	for k2 in _sorted_int(by_field.keys()):
		print("  %-4d %-25s %d" % [int(k2), _label(int(k2)), int(by_field[k2])])

	raw["progress"] = {}
	raw["dragons"] = []
	quit(0)

func _required_phase(SP: GDScript, n: int, sm: Dictionary) -> String:
	var ov := SP.MARK_OVERRIDE as Dictionary
	if ov.has(n):
		var e = ov[n]
		return String((e as Dictionary).get("phase", "")) if e is Dictionary else ""
	if sm.has("night"):
		return "night" if bool(sm["night"]) else "day"
	return ""

func _source(SP: GDScript, data: Node, n: int, sm: Dictionary) -> String:
	if (SP.MARK_OVERRIDE as Dictionary).has(n):
		return "사용자지정"
	if not sm.is_empty():
		var f = sm.get("field", 0)
		if f is String:
			var mf := int(data.call("story_mark_field", n))
			return "원작배지(event_mark)" if mf > 0 else "마을폴백"
		var fi := int(f)
		if fi <= 0 or fi == 999:
			return "마을폴백"
		return "원작배지"
	var arrow := int(SP.notify_field())
	if arrow <= 0 or arrow == 999:
		return "마을폴백"
	var sq: Dictionary = SP.spec(n)
	if not sq.is_empty() and not bool(SP.gate_cleared(n)):
		return "원작서브퀘스트"
	if int(data.call("story_notify_field", n)) > 0:
		return "원작화살표"
	if not (data.call("story_notify_conditional", n) as Dictionary).is_empty():
		return "원작화살표(조건부)"
	return "원작이벤트마크"

func _label(f: int) -> String:
	if f <= 0:
		return "— (마커 없음)"
	return String(_name.get(f, "필드 %d (월드맵 조각 없음)" % f))

func _build_names(data: Node) -> void:
	for r in (data.get("worldmap").get("regions", []) as Array):
		var rid := String((r as Dictionary).get("id", ""))
		for p in ((r as Dictionary).get("pieces", []) as Array):
			var f := int((p as Dictionary).get("field", -1))
			var lb := String((p as Dictionary).get("label", ""))
			if f > 0 and lb != "":
				_name[f] = "%s · %s" % [rid, lb]

func _sorted(keys: Array) -> Array:
	var a := keys.duplicate()
	a.sort()
	return a

func _sorted_int(keys: Array) -> Array:
	var a: Array = []
	for k in keys:
		a.append(int(k))
	a.sort()
	return a
