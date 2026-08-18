extends Node

func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.size = get_viewport().get_visible_rect().size
	add_child(root)
	Scenes.bind_root(root)
	await get_tree().process_frame
	var fails := 0

	Scenes.goto("adventure", {"stage": "1", "region": "yutakan", "enc": 1, "hero": true})
	await get_tree().process_frame
	await get_tree().process_frame
	var adv := Scenes.current_scene()
	if adv == null:
		print("탐험 씬 진입 실패"); _finish(1); return

	var cnt: Label = adv.get("_boss_count")
	var ok1 := cnt != null and "/" in cnt.text
	print("%-26s %s  %s" % ["보스 게이지 %d/%d", (cnt.text if cnt else "(없음)"), _v(ok1)])
	fails += 0 if ok1 else 1

	adv.call("_hide_party_cards")
	var hidden: Array = adv.get("_party_cards")
	var ok2a := hidden.is_empty()
	adv.call("_show_party_cards")
	await get_tree().process_frame
	var shown: Array = adv.get("_party_cards")
	var ok2b := shown.size() > 0
	var ok2c := true
	for card: Control in shown:
		ok2c = ok2c and card.z_index == 400
	print("%-26s 배회중=%d · 선택지=%d · z=400:%s  %s" % ["파티 카드 표시", hidden.size(), shown.size(),
		str(ok2c), _v(ok2a and ok2b and ok2c)])
	fails += 0 if (ok2a and ok2b and ok2c) else 1

	var uids: Array = adv.get("_run_party")
	if uids.is_empty():
		uids = [UserDB.active_uid()]
	var adv_party := PartyStats.summary(uids, adv.call("_is_kades"), adv.call("_field_element_key"))
	PartyStats.apply_passives(adv_party, adv.call("_next_enemy_ref"), {
		"field_element": adv.call("_field_element_key"), "enemy_boss": adv.call("_next_is_boss"),
		"team_buffs": PartyStats.team_buff_names(uids),
		"explore_gold_pct": int((adv.call("_awaken_explore") as Dictionary).get("gold_pct", 0))})
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
		compared += 1
		for k in ["hp", "att", "def"]:
			var av := int((a["stats"] as Dictionary).get(k, 0))
			var bv := int((b["stats"] as Dictionary).get(k, 0))
			if av != bv:
				drift += 1
				print("    DRIFT uid=%d stats.%s 탐험=%d 전투=%d" % [int(a["uid"]), k, av, bv])
		for k in ["hp_max", "hp"]:
			var av2 := int(a.get(k, 0))
			var bv2 := int(b.get(k, 0))
			if av2 != bv2:
				drift += 1
				print("    DRIFT uid=%d %s 탐험=%d 전투=%d" % [int(a["uid"]), k, av2, bv2])
	var ok3 := drift == 0 and compared > 0
	print("%-26s 비교 %d마리 · 불일치 %d  %s" % ["카드 능력치 드리프트", compared, drift, _v(ok3)])
	fails += 0 if ok3 else 1

	var auid := int(uids[0])
	var base_max := int((PartyStats.summary([auid], false, "")[0] as Dictionary)["hp_max"])
	UserDB.set_dragon_field(auid, "awakened", true)
	UserDB.set_dragon_field(auid, "awaken_skill", 12)
	var aw_party := PartyStats.summary([auid], false, "")
	PartyStats.apply_passives(aw_party, {"element": "", "hp": 1},
		{"field_element": "", "enemy_boss": false, "team_buffs": [], "explore_gold_pct": 0})
	var aw_adv := int((aw_party[0] as Dictionary)["hp_max"])
	Scenes.goto("worldmap", {"region": "yutakan"})
	await get_tree().process_frame
	Scenes.goto("battle", {"stage": "1", "region": "yutakan", "enc": 1, "party_uids": [auid]})
	await get_tree().process_frame
	var bat2 := Scenes.current_scene()
	var bp2: Array = bat2.get("_party") if bat2 else []
	var aw_bat := int((bp2[0] as Dictionary).get("hp_max", 0)) if not bp2.is_empty() else -1
	var ok3b := aw_adv == aw_bat and aw_adv > base_max
	print("%-26s 기본 %d → 각성 탐험 %d / 전투 %d  %s"
		% ["각성 스킬 반영", base_max, aw_adv, aw_bat, _v(ok3b)])
	fails += 0 if ok3b else 1
	UserDB.set_dragon_field(auid, "awakened", false)
	UserDB.set_dragon_field(auid, "awaken_skill", 0)

	Scenes.goto("adventure", {"stage": "1", "region": "yutakan", "enc": 1, "hero": true})
	await get_tree().process_frame
	var adv2 := Scenes.current_scene()
	adv2.set("_done_battle_ready", false)
	adv2.call("_show_battle_ready", false)
	await get_tree().process_frame
	var layer: CanvasLayer = adv2.get("_ready_layer")
	var ok4 := layer != null and layer.get_child_count() >= 2
	if ok4:
		var vis: Vector2 = adv2.call("_vis")
		var run_btn := layer.get_child(0) as Node2D
		var fight_btn := layer.get_child(1) as Node2D
		var run_x: float = float(run_btn.get_meta("target_x", run_btn.position.x))
		var fight_x: float = float(fight_btn.get_meta("target_x", fight_btn.position.x))
		ok4 = run_x < vis.x * 0.5 and fight_x > vis.x * 0.5
		print("%-26s 도망 x=%.0f · 싸운다 x=%.0f (중앙 %.0f)  %s"
			% ["선택지 버튼 좌우", run_x, fight_x, vis.x * 0.5, _v(ok4)])
	else:
		print("%-26s 버튼 %d개  FAIL" % ["선택지 버튼 좌우", (layer.get_child_count() if layer else 0)])
	fails += 0 if ok4 else 1

	var uid := int(uids[0])
	var lv := int(UserDB.get_dragon(uid).get("level", 1))
	var pkey := ""
	for t in (Data.item_effects.get("heal_potion", {}).get("tiers", []) as Array):
		var k := String((t as Dictionary).get("key", ""))
		if ItemEffect.heal_usable(Data.item_effects, k, lv):
			pkey = k
			break
	var ok5 := false
	if pkey == "":
		print("%-26s 레벨 %d 에 맞는 물약 등급 없음  FAIL" % ["회복 물약 버튼", lv])
	else:
		UserDB.add_item(pkey, 5)
		var full := int((PartyStats.summary([uid], false, "")[0] as Dictionary)["hp_max"])
		adv2.set("_params", {"stage": "1", "region": "yutakan", "enc": 1, "hero": true,
			"hp_state": {str(uid): int(full * 0.4)}})
		adv2.call("_show_party_cards")
		await get_tree().process_frame
		var before := UserDB.item_count(pkey)
		adv2.call("_use_heal_potion", uid, pkey)
		await get_tree().process_frame
		var after := UserDB.item_count(pkey)
		var hp_after := int((adv2.get("_params") as Dictionary).get("hp_state", {}).get(str(uid), 0))
		adv2.set("_params", {"stage": "1", "region": "yutakan", "enc": 1, "hero": true,
			"hp_state": {str(uid): full}})
		var full_before := UserDB.item_count(pkey)
		adv2.call("_use_heal_potion", uid, pkey)
		var full_after := UserDB.item_count(pkey)
		ok5 = after == before - 1 and hp_after > int(full * 0.4) and full_after == full_before
		print("%-26s 물약 %d→%d · HP %d→%d(최대 %d)  %s"
			% ["회복 물약 버튼", before, after, int(full * 0.4), hp_after, full, _v(ok5)])
		UserDB.add_item(pkey, -(after - (before - 5)))
	fails += 0 if ok5 else 1

	var seen_treasure := 0
	var trials := 4000
	for i in trials:
		var rr := RandomNumberGenerator.new()
		rr.seed = i * 7919 + 13
		for st2 in AdventureRun.build_steps({"enemies": [{}, {}, {}, {}, {}]},
				Data.adventure_events, i % 4, {"hurt": true, "fortress": true}, rr):
			if String((st2 as Dictionary).get("type", "")) == AdventureRun.TREASURE:
				seen_treasure += 1
	var ok6 := seen_treasure == 0
	print("%-26s %d회 시행 · 보물 조우 %d  %s" % ["보물 조우 배제", trials, seen_treasure, _v(ok6)])
	fails += 0 if ok6 else 1

	_finish(fails)

func _v(ok: bool) -> String:
	return "OK" if ok else "FAIL"

func _finish(fails: int) -> void:
	print("\n=== 실패 %d건 ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
