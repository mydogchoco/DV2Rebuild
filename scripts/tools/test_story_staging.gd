extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fails := 0
	var packed: PackedScene = load("res://scenes/story.tscn")
	var data := root.get_node_or_null("/root/Data")

	var st := packed.instantiate()
	st.call("enter", {"no": 1, "part": 0, "back": "worldmap"})
	root.add_child(st)
	await process_frame
	fails += _true("1화 첫 스텝에 화자 초상", not (st.get("_npc_slots") as Dictionary).is_empty())
	var stray := 0
	var steps := 0
	var flow: Array = st.get("_flow")
	while int(st.get("_flow_i")) < flow.size() and steps < 40:
		var before: int = int(st.get("_flow_i"))
		st.call("_reveal_all")
		st.call("_advance")
		var wants_enter := false
		for k in range(before, mini(int(st.get("_flow_i")), flow.size())):
			var o: Dictionary = flow[k]
			if o.get("enter") == true or o.get("b3") == true:
				wants_enter = true
		steps += 1
		var slots: Dictionary = st.get("_npc_slots")
		for pos in slots:
			var p: Node2D = slots[pos]
			var home: Vector2 = st.call("_npc_home", p, int(pos))
			if not wants_enter and absf(p.position.x - home.x) > 1.0:
				stray += 1
		for f in 90:
			await process_frame
	fails += _true("1화 %d스텝 중 지시 없는 등장 연출 %d회" % [steps, stray], stray == 0)
	st.free()

	st = packed.instantiate()
	st.call("enter", {"no": 1, "part": 0, "back": "worldmap"})
	root.add_child(st)
	await process_frame
	st.call("_confirm_skip")
	await process_frame
	var pop: Node = null
	var pop_layer := -1
	for c in st.get_children():
		if c is CanvasLayer:
			for g in c.get_children():
				if g.get_class() == "Control" and g.get_script() != null 						and String(g.get_script().resource_path).ends_with("framed_window.gd"):
					pop = g
					pop_layer = (c as CanvasLayer).layer
	fails += _true("건너뛰기 팝업 생성", pop != null)
	fails += _true("팝업이 대사 캐처(layer 8)보다 위 (실측 layer=%d)" % pop_layer, pop_layer > 8)
	st.free()

	for probe in [[8, "_illust"], [32, "_cut"]]:
		var no := int(probe[0])
		var field := String(probe[1])
		st = packed.instantiate()
		st.call("enter", {"no": no, "part": 0, "back": "worldmap"})
		root.add_child(st)
		await process_frame
		var fl2: Array = st.get("_flow")
		var art := 0
		for o in fl2:
			if String((o as Dictionary).get("op", "")) in ["illust", "cut"]:
				art += 1
		fails += _true("%d화 흐름에 그림 스텝 (실측 %d)" % [no, art], art > 0)
		for i in 200:
			if st.get(field) != null and (st.get(field) as TextureRect).texture != null:
				break
			st.call("_reveal_all")
			st.call("_advance")
			await process_frame
		var tr: TextureRect = st.get(field)
		fails += _true("%d화 %s 텍스처 표시" % [no, field], tr != null and tr.texture != null)
		st.free()

	var spec: Dictionary = data.call("story_battle", 14)
	fails += _true("전투번호 14 편성 존재", not spec.is_empty())
	if not spec.is_empty():
		_ensure_party()
		var bt = load("res://scenes/battle.tscn").instantiate()
		bt.call("enter", {"enemy": spec["enemy"], "bg_stage": int(spec.get("field", 0)),
			"story_return": {"no": 32, "part": 0, "resume_flow": 11, "back": "worldmap"}})
		root.add_child(bt)
		for f in 900:
			await process_frame
			if not bool(bt.get("_playing")):
				break
		for f in 60:
			await process_frame
		var btn: Control = _find_continue(bt)
		fails += _true("전투 후 '이야기 계속' 버튼 존재", btn != null)
		if btn != null:
			var r := btn.get_global_rect()
			var covered := false
			for c in bt.get_children():
				if c is Control and (c as Control).has_meta("party_card") \
						and r.intersects((c as Control).get_global_rect()):
					covered = true
			fails += _true("버튼이 파티 카드에 가리지 않음 (rect %s)" % r, not covered)
		bt.free()

	fails += _true("67화 흐름에 setPlay 배치 인자", _setplay_pos(data, 67).size() > 0)
	var pos67 := _setplay_pos(data, 67)
	fails += _true("67화 자리가 가운데로 몰려 있지 않다 (실측 %s)" % [pos67],
		pos67.has(1) or pos67.has(2))
	var admin_eps: Dictionary = (data.get("admin_story") as Dictionary).get("episodes", {})
	(data.get("admin_story") as Dictionary)["episodes"] = {}
	var st5 := packed.instantiate()
	st5.call("enter", {"no": 67, "part": 0, "back": "worldmap"})
	root.add_child(st5)
	await process_frame
	var seen_pos := {}
	var stray5 := 0
	var flow5: Array = st5.get("_flow")
	for i in 200:
		var from5: int = int(st5.get("_flow_i"))
		if from5 >= flow5.size():
			break
		st5.call("_reveal_all")
		st5.call("_advance")
		var enter5 := false
		for k in range(from5, mini(int(st5.get("_flow_i")), flow5.size())):
			var o5: Dictionary = flow5[k]
			if o5.get("enter") == true or o5.get("b3") == true:
				enter5 = true
		if enter5:
			await create_timer(1.4).timeout
		else:
			for f in 4:
				await process_frame
		var slots5: Dictionary = st5.get("_npc_slots")
		for pos in slots5:
			var p5: Node2D = slots5[pos]
			if not is_instance_valid(p5):
				continue
			seen_pos[int(pos)] = true
			var home5: Vector2 = st5.call("_npc_home", p5, int(pos))
			if absf(p5.position.x - home5.x) > 1.0 or absf(p5.position.y - home5.y) > 1.0:
				stray5 += 1
	fails += _true("67화 초상이 두 자리 이상에 선다 (실측 %s)" % [seen_pos.keys()],
		seen_pos.size() >= 2)
	fails += _true("67화 제자리 이탈 %d회" % stray5, stray5 == 0)
	st5.free()
	(data.get("admin_story") as Dictionary)["episodes"] = admin_eps

	if data == null:
		fails += 1
	print("\n[test_story_staging] %s" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(1 if fails > 0 else 0)

func _ensure_party() -> void:
	var udb := root.get_node_or_null("/root/UserDB")
	if udb == null or int(udb.call("dragon_count")) > 0:
		return
	udb.set("_autosave", false)
	var raw: Dictionary = udb.call("raw")
	var d: Dictionary = udb.call("_new_dragon", 1, 30, udb.call("_zero_bonus"))
	var log: Array = []
	for _i in int(d["level"]) - 1:
		log.append({"hp": 0, "att": 0, "def": 0})
	d["gain_log"] = log
	(raw["dragons"] as Array).append(d)
	if int(raw.get("active_uid", 0)) <= 0:
		raw["active_uid"] = int(d.get("uid", 1))
	print("  (검증용 드래곤 1마리 주입 — 메모리에만)")

func _setplay_pos(data, no: int) -> Array:
	var out := {}
	for o in (data.call("scenario_flow_of", no) as Array):
		var d: Dictionary = o
		if String(d.get("via", "")) == "play" and d.get("pos") != null:
			out[int(d["pos"])] = true
	return out.keys()

func _find_continue(n: Node) -> Control:
	if n is Label and String((n as Label).text).begins_with("이야기 계속"):
		return n.get_parent() as Control
	for c in n.get_children():
		var r := _find_continue(c)
		if r != null:
			return r
	return null

func _true(name: String, ok: bool) -> int:
	if not ok:
		print("FAIL: %s" % name)
		return 1
	print("  ok  %s" % name)
	return 0
