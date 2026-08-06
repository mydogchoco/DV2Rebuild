extends SceneTree
## 스토리 연출 회귀 — ① NPC 등장 연출이 대사마다 반복되지 않는가 ② 건너뛰기 팝업이
## 입력을 받는 레이어에 뜨는가 ③ 삽화·컷 스텝이 실제로 그림을 띄우는가.
##
## 실행: godot --headless --path . --script res://scripts/tools/test_story_staging.gd
##
## 근거: `docs/ref/porting/ScenarioNpcStaging.md` + `ScenarioLayer::setTalker` @016c7848
##       (`param_11` = 등장 플래그) · `ScenarioSupport::setNpcTalk` @0165aab8 (b3 → param_11).

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fails := 0
	var packed: PackedScene = load("res://scenes/story.tscn")
	var data := root.get_node_or_null("/root/Data")

	# ── ① 등장 연출은 데이터가 정한다 ────────────────────────────────────────────
	# 원작은 대사마다 몸통·표정을 다시 만들지만(`NpcManager::setTarget`), **화면 밖에서
	# 밀어 넣는 등장 연출은 `enter` 가 참일 때만** 한다. ⇒ 노드 재생성이 아니라
	# **초상이 제자리에서 시작하는가**로 본다(등장 중이면 x 가 화면 밖에 있다).
	# 종전 버그(표정이 바뀔 때마다 재등장)는 여기서 잡힌다.
	var st := packed.instantiate()
	st.call("enter", {"no": 1, "part": 0, "back": "worldmap"})
	root.add_child(st)
	await process_frame
	fails += _true("1화 첫 스텝에 화자 초상", not (st.get("_npc_slots") as Dictionary).is_empty())
	# 스텝마다 ① 진행 → ② **그 즉시** 위치 확인(등장이 시작됐다면 화면 밖에 놓여 있다)
	# → ③ 다음 스텝 전에 연출이 끝날 때까지 프레임을 흘린다(원작 최장 1.25초).
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
			# 제자리에 세워야 할 초상이 화면 밖에 놓였다 = 지시 없는 재등장.
			if not wants_enter and absf(p.position.x - home.x) > 1.0:
				stray += 1
		for f in 90:                      # 1.5초 — 등장 연출이 끝나 제자리로 돌아온다
			await process_frame
	fails += _true("1화 %d스텝 중 지시 없는 등장 연출 %d회" % [steps, stray], stray == 0)
	st.free()

	# ── ② 건너뛰기 팝업은 대사 캐처(CanvasLayer 8)보다 위에 떠야 누를 수 있다 ────
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
				if g.get_class() == "Control" and g.get_script() != null 						and String(g.get_script().resource_path).ends_with("orig_popup.gd"):
					pop = g
					pop_layer = (c as CanvasLayer).layer
	fails += _true("건너뛰기 팝업 생성", pop != null)
	fails += _true("팝업이 대사 캐처(layer 8)보다 위 (실측 layer=%d)" % pop_layer, pop_layer > 8)
	st.free()

	# ── ③ 삽화·컷 스텝이 그림을 띄운다 ─────────────────────────────────────────
	# 8화 = 원작이 `drawIllust` 를 **인라인**해 둔 회차(호출이 없어 종전엔 한 장도 안 떴다).
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
			if String((o as Dictionary).get("op", "")) in ["drawIllust", "showCut"]:
				art += 1
		fails += _true("%d화 흐름에 그림 스텝 (실측 %d)" % [no, art], art > 0)
		# 그림 스텝에 닿을 때까지 진행
		for i in 200:
			if st.get(field) != null and (st.get(field) as TextureRect).texture != null:
				break
			st.call("_reveal_all")
			st.call("_advance")
			await process_frame
		var tr: TextureRect = st.get(field)
		fails += _true("%d화 %s 텍스처 표시" % [no, field], tr != null and tr.texture != null)
		st.free()

	# ── ④ 스토리 전투가 끝나면 이야기로 돌아갈 버튼이 **실제로 보여야** 한다 ──────────
	# 🔴 종전에는 버튼이 파티 카드 띠(z_index 400) 뒤에 깔려(버튼 124) 눈에도 안 보이고
	#    클릭도 안 먹었다 — 전투가 안 끝나는 것처럼 보였다(사용자 신고 2026-08-04).
	var spec: Dictionary = data.call("story_battle", 14)     # 32화 다크프로스티
	fails += _true("전투번호 14 편성 존재", not spec.is_empty())
	if not spec.is_empty():
		var bt = load("res://scenes/battle.tscn").instantiate()
		bt.call("enter", {"enemy": spec["enemy"], "bg_stage": int(spec.get("field", 0)),
			"story_return": {"no": 32, "part": 0, "resume_flow": 11, "back": "worldmap"}})
		root.add_child(bt)
		for f in 900:                     # 15초 — 이벤트 재생이 끝날 시간
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

	if data == null:
		fails += 1
	print("\n[test_story_staging] %s" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(1 if fails > 0 else 0)


## `_big_button` 은 NinePatchRect + 무텍스트 Button + Label 조합이라, 라벨로 찾아
## 그 부모(실제로 화면을 차지하는 판)를 돌려준다.
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
