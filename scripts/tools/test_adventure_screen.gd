extends Node
## 탐험 화면 요소 검증 — 레퍼런스 `docs/ref/adventure/*.png` 대조분.
##
## 검사 항목
##   1) 보스 게이지(원작 setAdventureNavi)가 만들어지고 진행도가 `%d/%d` 로 나온다
##      — 레퍼런스 `승리11_탐험재개.png` 우상단.
##   2) 조우 선택지에서 하단 파티 카드가 뜬다 / 배회 중에는 사라진다
##      — 레퍼런스 `전투4.png`(있음) vs `배회1~5.png`(없음).
##   3) 🔴 **드리프트 가드** — 탐험 카드(`PartyStats`)와 전투 카드(`battle.gd::_setup_party`)의
##      능력치가 같은 파이프라인에서 나오는지. 원작은 탐험·전투가 같은 씬이라 카드가 하나였는데
##      우리는 두 씬으로 나눠 놔서, 두 곳에서 따로 계산하면 숫자가 벌어진다(884 vs 1523).
##      각성 스킬은 전투 컨텍스트가 필요해 빠지므로 **미각성 드래곤**으로 비교한다.
##   4) 조우 선택지 버튼 좌우 — 좌=도망(btn1) · 우=싸운다(btn2).
##      근거 setBattleReady@00c57170: btn2+tag0xbbe→center+w/2+50(우), btn1+tag0xbbf→center−w/2−50(좌).
##      레퍼런스 `전투5.png` 와 일치.
##
## Run: godot --headless --path . res://scenes/test_adventure_screen.tscn

func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.size = get_viewport().get_visible_rect().size
	add_child(root)
	Scenes.bind_root(root)
	await get_tree().process_frame
	var fails := 0

	# ── 탐험 진입(영웅 = 3마리라 카드 3장을 볼 수 있다)
	Scenes.goto("adventure", {"stage": "1", "region": "yutakan", "enc": 1, "hero": true})
	await get_tree().process_frame
	await get_tree().process_frame
	var adv := Scenes.current_scene()
	if adv == null:
		print("탐험 씬 진입 실패"); _finish(1); return

	# 1) 보스 게이지
	var cnt: Label = adv.get("_boss_count")
	var ok1 := cnt != null and "/" in cnt.text
	print("%-26s %s  %s" % ["보스 게이지 %d/%d", (cnt.text if cnt else "(없음)"), _v(ok1)])
	fails += 0 if ok1 else 1

	# 2) 파티 카드 — 배회 중 숨김 / 선택지에서 표시
	adv.call("_hide_party_cards")
	var hidden: Array = adv.get("_party_cards")
	var ok2a := hidden.is_empty()
	adv.call("_show_party_cards")
	await get_tree().process_frame
	var shown: Array = adv.get("_party_cards")
	var ok2b := shown.size() > 0
	print("%-26s 배회중=%d · 선택지=%d  %s" % ["파티 카드 표시", hidden.size(), shown.size(),
		_v(ok2a and ok2b)])
	fails += 0 if (ok2a and ok2b) else 1

	# 3) 드리프트 가드 — 탐험 카드 vs 전투 카드
	var uids: Array = adv.get("_run_party")
	if uids.is_empty():
		uids = [UserDB.active_uid()]
	var adv_party := PartyStats.summary(uids, false, "")
	Scenes.goto("battle", {"stage": "1", "region": "yutakan", "enc": 1,
		"party_uids": uids.duplicate()})
	await get_tree().process_frame
	var bat := Scenes.current_scene()
	var bp: Array = bat.get("_party") if bat else []
	var drift := 0
	var compared := 0
	for i in mini(adv_party.size(), bp.size()):
		var a: Dictionary = adv_party[i]
		var b: Dictionary = bp[i]
		# 각성 스킬은 전투에서만 얹히므로 미각성 개체만 비교한다.
		if bool(b.get("awakened", false)):
			continue
		compared += 1
		for k in ["hp", "att", "def"]:
			var av := int((a["stats"] as Dictionary).get(k, 0))
			var bv := int((b["stats"] as Dictionary).get(k, 0))
			if av != bv:
				drift += 1
				print("    DRIFT uid=%d %s 탐험=%d 전투=%d" % [int(a["uid"]), k, av, bv])
	var ok3 := drift == 0 and compared > 0
	print("%-26s 비교 %d마리 · 불일치 %d  %s" % ["카드 능력치 드리프트", compared, drift, _v(ok3)])
	fails += 0 if ok3 else 1

	# 4) 선택지 버튼 좌우
	Scenes.goto("adventure", {"stage": "1", "region": "yutakan", "enc": 1, "hero": true})
	await get_tree().process_frame
	var adv2 := Scenes.current_scene()
	adv2.set("_done_battle_ready", false)
	adv2.call("_show_battle_ready", false)
	await get_tree().process_frame
	var layer: CanvasLayer = adv2.get("_ready_layer")
	# 생성 순서 = 좌(도망/btn1) → 우(싸운다/btn2). 목표 x 로 좌우를 확인한다
	# (등장 트윈이 화면 밖에서 들어오므로 트윈 목표값이 아니라 최종 배치 기준으로 본다).
	var ok4 := layer != null and layer.get_child_count() >= 2
	if ok4:
		var vis: Vector2 = adv2.call("_vis")
		var run_btn := layer.get_child(0) as Node2D
		var fight_btn := layer.get_child(1) as Node2D
		# 좌 버튼은 화면 중앙보다 왼쪽에서 끝나야 한다(트윈 목표 = meta 로 남겨 둔 최종 위치).
		var run_x: float = float(run_btn.get_meta("target_x", run_btn.position.x))
		var fight_x: float = float(fight_btn.get_meta("target_x", fight_btn.position.x))
		ok4 = run_x < vis.x * 0.5 and fight_x > vis.x * 0.5
		print("%-26s 도망 x=%.0f · 싸운다 x=%.0f (중앙 %.0f)  %s"
			% ["선택지 버튼 좌우", run_x, fight_x, vis.x * 0.5, _v(ok4)])
	else:
		print("%-26s 버튼 %d개  FAIL" % ["선택지 버튼 좌우", (layer.get_child_count() if layer else 0)])
	fails += 0 if ok4 else 1

	_finish(fails)


func _v(ok: bool) -> String:
	return "OK" if ok else "FAIL"


func _finish(fails: int) -> void:
	print("\n=== 실패 %d건 ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
