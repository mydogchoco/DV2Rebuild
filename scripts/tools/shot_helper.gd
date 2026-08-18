extends Node

func _ready() -> void:
	if "--no-ocean=1" in OS.get_cmdline_user_args():
		Engine.set_meta("wm_no_ocean", true)
	var has_shot := false
	for a0 in OS.get_cmdline_user_args():
		if a0.begins_with("--shot="):
			has_shot = true
			break
	if not has_shot:
		return

	var shot := "battle"
	var out := "user://shot.png"
	var wait := 3.0
	var stage := "1"
	var extra := "0"
	var guard := 0
	var ranker := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--wait="): wait = float(a.substr(7))
		elif a.begins_with("--stage="): stage = a.substr(8)
		elif a.begins_with("--extra="): extra = a.substr(8)
		elif a.begins_with("--guard="): guard = int(a.substr(8))
		elif a.begins_with("--ranker="): ranker = a.substr(9)

	if not UserDB.has_user_nickname():
		UserDB.begin_batch()
		UserDB.set_user_nickname("계란")

	if shot == "intro" and (stage == "old" or stage == "2020"):
		UserDB.begin_batch()
		UserDB.set_pmeta("title_screen", stage)

	for i in 20: await get_tree().process_frame
	match shot:
		"advfountain":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": 1})
			for i in 30: await get_tree().process_frame
			var fv := _node_with_method(get_tree().root, "_show_fountain")
			if fv:
				fv.call("_show_fountain", extra == "1")
		"advready":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": 1, "hero": false})
			for i in 30: await get_tree().process_frame
			var av := _node_with_method(get_tree().root, "_show_battle_ready")
			if av:
				av.set("_done_battle_ready", false)
				av.call("_show_battle_ready", false)
		"battle":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
		"skillfx":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			var bs := get_tree().current_scene
			if bs and bs.has_method("_play_skill_spine"):
				var sid := 12
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--sid="): sid = int(a.split("=")[1])
				for rep in 20:
					bs.call("_play_skill_spine", sid, bs.get("_views").get("E0", {}))
					await get_tree().create_timer(0.4).timeout
		"bicon":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			var bs2 := _node_with_method(get_tree().root, "_bicon_add")
			if bs2:
				bs2.set("_gen", int(bs2.get("_gen")) + 1)
				var views: Dictionary = bs2.get("_views")
				for pair in [[23, false, -1, 3], [32, false, 2, 0], [140, false, 4, 0]]:
					bs2.call("_bicon_add", views.get("E0", {}), pair[0], pair[1], pair[2], pair[3])
				for pair in [[14, true, 2, 0], [60, true, 3, 0]]:
					bs2.call("_bicon_add", views.get("A0", {}), pair[0], pair[1], pair[2], pair[3])
		"teambuff":
			var uids := _pick_team_buff_party()
			if uids.is_empty():
				print("SHOT teambuff: 보유 드래곤으로 발동 가능한(아이콘 있는) 조합이 없다")
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0, "party_uids": uids, "run_seed": randi()})
		"colosseum":
			if extra == "season":
				UserDB.begin_batch()
				var cs: Dictionary = UserDB.get_pmeta(Colosseum.PMETA_KEY, {}).duplicate(true)
				cs["season_start"] = int(Time.get_unix_time_from_system()) - Colosseum.season_span() - 60
				cs["tournament"] = 4321
				cs["straight_team"] = 7
				UserDB.set_pmeta(Colosseum.PMETA_KEY, cs)
				print("SHOT season: 앵커를 %d초 전으로 — 레이팅 4321/연승 7 심음"
					% (Colosseum.season_span() + 60))
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 20: await get_tree().process_frame
			if extra == "seasonbtn":
				var cl := _find_method_node(get_tree().root, "_ask_season_reset")
				if cl == null:
					print("SHOT: 콜로세움 로비 노드 없음")
				else:
					cl.call("_ask_season_reset")
					for i in 10: await get_tree().process_frame
		"coloselect":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 20: await get_tree().process_frame
			var clobby := Scenes.current_scene()
			if clobby != null:
				if extra == "commit":
					clobby.call("_start", "team")
					for i in 6: await get_tree().process_frame
					for ch in clobby.get_children():
						if ch is ColosseumSelect:
							ch.call("_commit")
							break
				else:
					var cmode := "single" if extra == "single" else "team"
					var cseed: Array = Colosseum.eligible_uids()
					var csel := ColosseumSelect.open(clobby, cmode,
						cseed.slice(0, Colosseum.party_size(cmode)), Callable())
					if extra == "toggle" and cseed.size() > 1:
						for i in 6: await get_tree().process_frame
						csel.call("_toggle", int(cseed[cseed.size() - 1]))
		"matching":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 20: await get_tree().process_frame
			var lobby := Scenes.current_scene()
			if lobby != null:
				MatchingWait.open(lobby, 30.0, Callable())
		"fight":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 10: await get_tree().process_frame
			var frng := RandomNumberGenerator.new()
			frng.seed = 20260804
			var fmode := extra if extra != "0" else "team"
			var foe: Dictionary = {}
			if guard > 0:
				var gg := Colosseum.guard_for(guard)
				if not gg.is_empty():
					foe = Colosseum.make_guard(gg, fmode, frng)
			if ranker != "":
				var rlist: Array = Data.colosseum.get("rankers", [])
				for ri in rlist.size():
					var rr: Dictionary = rlist[ri]
					if String(rr.get("nick", "")) == ranker or str(ri) == ranker:
						foe = Colosseum._make_ranker(rr, fmode, frng)
						break
				if foe.is_empty():
					push_warning("[shot] --ranker=%s 를 랭커 시트에서 못 찾았다" % ranker)
			if foe.is_empty():
				foe = Colosseum.roll_match(fmode, frng)
			var fparty: Array = Colosseum.eligible_uids()
			if fparty.is_empty():
				fparty = UserDB.party()
			var fp := {"mode": extra if extra != "0" else "team",
				"opponent": foe, "party": fparty}
			if stage != "" and stage != "0":
				fp["stage_element"] = stage
			Scenes.goto("fight", fp)
			for i in 20: await get_tree().process_frame
			await _advance_talk(999)
		"guardtalk":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 10: await get_tree().process_frame
			var trng := RandomNumberGenerator.new()
			trng.seed = 20260805
			var tmode := "team"
			if stage == "repeat":
				UserDB.begin_batch()
				var ts := Colosseum.state()
				ts["guard_met"] = {"sundaegun": 1, "nuri": 1, "raon": 1}
				Colosseum.save_state(ts)
			var tg := Colosseum.guard_for(guard if guard > 0 else 999)
			if tg.is_empty():
				push_warning("[shot] --guard=%d 에 해당하는 방지봇이 없다" % guard)
			var tfoe := Colosseum.make_guard(tg, tmode, trng)
			var tparty: Array = Colosseum.eligible_uids()
			if tparty.is_empty():
				tparty = UserDB.party()
			Scenes.goto("fight", {"mode": tmode, "opponent": tfoe, "party": tparty})
			for i in 30: await get_tree().process_frame
			await _advance_talk(maxi(0, int(extra) - 1))
		"fightinfo":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 10: await get_tree().process_frame
			var irng := RandomNumberGenerator.new()
			irng.seed = 20260805
			var ifoe := Colosseum.make_guard(Colosseum.guard_for(guard), "team", irng) \
				if guard > 0 else Colosseum.roll_match("team", irng)
			var iparty: Array = Colosseum.eligible_uids()
			if iparty.is_empty():
				iparty = UserDB.party()
			Scenes.goto("fight", {"mode": "team", "opponent": ifoe, "party": iparty,
				"stage_element": stage if stage != "" and stage != "0" else "fire"})
			for i in 20: await get_tree().process_frame
			var fs := Scenes.current_scene()
			if fs != null:
				var vws: Dictionary = fs.get("_views")
				var want := "E0" if extra == "foe" else "A0"
				if vws.has(want):
					var rec: Dictionary = (vws[want] as Dictionary).get("rec", {})
					if not rec.is_empty():
						StatusPanel.open_panel(fs, rec, extra != "foe")
		"fightfx":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 10: await get_tree().process_frame
			var xrng := RandomNumberGenerator.new()
			xrng.seed = 20260805
			var xfoe := Colosseum.roll_match("team", xrng)
			var xparty: Array = Colosseum.eligible_uids()
			if xparty.is_empty():
				xparty = UserDB.party()
			Scenes.goto("fight", {"mode": "team", "opponent": xfoe, "party": xparty})
			for i in 30: await get_tree().process_frame
			var fs := Scenes.current_scene()
			if extra == "ult" and fs != null and fs.has_method("_awaken_fx"):
				var uvs: Dictionary = fs.get("_views")
				var ua: Dictionary = uvs.get("A0", {})
				if not ua.is_empty():
					fs.call("_cutin", ua)
					fs.call("_awaken_fx", ua, ua.get("pos", Vector2.ZERO))
				for i in 12: await get_tree().process_frame
			elif fs != null and fs.has_method("_skill_banner"):
				fs.call("_skill_banner", "철갑 방패", 11)
				var vws: Dictionary = fs.get("_views")
				var kk := 0
				for tag in vws:
					fs.call("_status_icon", vws[tag], [11, 30, 56][kk % 3], kk % 2 == 0, 2 + kk)
					fs.call("_status_icon", vws[tag], 23, false, -1, 3)
					kk += 1
			for i in 12: await get_tree().process_frame
		"getitem":
			Scenes.goto("shop", {"area": "elpis"})
			for i in 20: await get_tree().process_frame
			var gi := get_tree().current_scene
			var gn := 3
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--n="): gn = int(a.split("=")[1])
			var gitems: Array = []
			var gnm := ""
			for gk in (Data.gems.get("gems", {}) as Dictionary):
				gnm = String(gk); break
			var cke := ""
			for c in Equipment.catalog(Data.equipment):
				cke = String(c); break
			var pool := ["heal_potion1", "gem:%s:6" % gnm, Equipment.item_key(cke),
				"egg:1", "skill:11:1", "food_fire_chicken"]
			for i in gn:
				gitems.append({"key": pool[i % pool.size()], "count": 1 + i})
			var gp: ItemRewardView = null
			if gn > 0:
				gp = ItemRewardView.open(gi, gitems)
			await get_tree().process_frame
		"adventure":
			var a_enc := 0
			var a_hurt := false
			var a_hero := false
			var a_night := false
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--enc="): a_enc = int(a2.substr(6))
				elif a2 == "--hurt=1": a_hurt = true
				elif a2 == "--hero=1": a_hero = true
				elif a2 == "--night=1": a_night = true
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			var apar := {"stage": stage, "region": "yutakan", "enc": a_enc,
				"hero": a_hero, "night": a_night, "streak": 0, "run_seed": randi()}
			apar["hp_state"] = {"dummy": 1} if a_hurt else {}
			Scenes.goto("adventure", apar)
			for i in 10: await get_tree().process_frame
			var advn := _find_method_node(get_tree().root, "_monster_meet")
			if advn != null:
				print("SHOT adv seed=", apar.get("run_seed"), " steps=", advn.get("_steps"))
				var sr = advn.get("_stage")
				if sr != null:
					print("SHOT adv variant=", (sr as Dictionary).get("variant", "-"),
						" lv=", (sr as Dictionary).get("level", "-"),
						" enemy0=", ((sr as Dictionary).get("enemies", [{}])[0] as Dictionary).get("name", "-"))
		"bossalert":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			var ba_st: Dictionary = Data.stage(stage)
			var last := maxi(0, int((ba_st.get("enemies", []) as Array).size()) - 1)
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": last,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			var bav := _find_method_node(get_tree().root, "_monster_meet")
			if bav != null: bav.call("_monster_meet")
			else: print("SHOT: _monster_meet 노드 없음")
		"lvresult":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			var lr_uid := UserDB.active_uid()
			var lr_d: Dictionary = UserDB.get_dragon(lr_uid)
			var lr_lv := int(lr_d.get("level", 10))
			var lr_ms: Dictionary = Growth.tier_growth(
				Data.get_dragon(int(lr_d.get("id", 1))), Data.stat_table)
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0,
				"levelups": [{"uid": lr_uid, "name": String(lr_d.get("name", "드래곤")),
					"from_lv": lr_lv - 1, "to_lv": lr_lv,
					"gains": [{"hp": int(lr_ms.get("hp", 0)), "att": int(lr_ms.get("att", 0)),
						"def": maxi(0, int(lr_ms.get("def", 0)) - 1),
						"is_max": {"hp": true, "att": true, "def": false},
						"tmax": {}}],
					"max_stats": lr_ms}]})
		"storybattle":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("story", {"no": int(stage), "part": 0, "back": "worldmap",
				"resume_flow": int(extra)})
		"story":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("story", {"no": int(stage), "part": 0, "back": "worldmap"})
			if extra == "complete":
				UserDB.begin_batch()
				UserDB.set_progress("scenario_%d_0" % int(stage), false)
				print("SHOT story: 진행도(처음 보기여야 false)=",
					UserDB.get_progress("scenario_%d_0" % int(stage), false))
				for i in 25: await get_tree().process_frame
				var stn := Scenes.current_scene()
				if stn == null or not stn.has_method("_confirm_skip"):
					print("SHOT: story 씬 아님")
				else:
					stn.call("_confirm_skip")
					for i in 12: await get_tree().process_frame
					await _click_label_button(get_tree().root, "취소")
					for i in 10: await get_tree().process_frame
					print("SHOT story: 취소 뒤 팝업 살아있나=", _find_popup(get_tree().root) != null,
						" state=", Scenes.current_state())
					stn.call("_confirm_skip")
					for i in 12: await get_tree().process_frame
					await _click_label_button(get_tree().root, "확인")
					for i in 25: await get_tree().process_frame
					print("SHOT story: 완료알림 떴나=", _find_popup(get_tree().root) != null,
						" state=", Scenes.current_state(),
						" 진행도=", UserDB.get_progress("scenario_%d_0" % int(stage), false))
					await _click_label_button(get_tree().root, "확인")
					for i in 25: await get_tree().process_frame
					var dst := Scenes.current_scene()
					print("SHOT story: 도착 state=", Scenes.current_state(),
						" mode=", dst.get("_mode") if dst != null and "_mode" in dst else "-")
		"tutorial":
			UserDB.begin_batch()
			var tu_step := ""
			var tu_scene := "worldmap"
			for a7 in OS.get_cmdline_user_args():
				if a7.begins_with("--step="): tu_step = a7.substr(7)
				elif a7.begins_with("--scene="): tu_scene = a7.substr(8)
			UserDB.set_pmeta("tutorial_done", false)
			UserDB.set_pmeta("tutorial_step", tu_step)
			if "--eggonly=1" in OS.get_cmdline_user_args():
				var keep: Array = []
				for d in UserDB.dragons():
					if UserDB.is_egg(d): keep.append(d)
				UserDB.raw()["dragons"] = keep
				if keep.is_empty():
					UserDB.add_egg(1, 5.0, 3600)
				UserDB.raw()["active_uid"] = int(UserDB.dragons()[0]["uid"])
				print("SHOT tutorial: eggonly — 부화완료 보유=", UserDB.has_hatched_dragon())
			Scenes.goto("worldmap", {"region": "yutakan"})
			if tu_scene != "worldmap":
				for i in 10: await get_tree().process_frame
				Scenes.goto(tu_scene, {})
			for i in 25: await get_tree().process_frame
			var tu_app := get_tree().current_scene
			if tu_app != null and tu_app.has_method("start_tutorial"):
				tu_app.call("start_tutorial")
			for i in 10: await get_tree().process_frame
			var tu := _find_method_node(get_tree().root, "_advance")
			print("SHOT tutorial: 스텝=", UserDB.get_pmeta("tutorial_step", "?"),
				" 가이드=", tu != null)
		"cave":
			Scenes.goto("cave", {})
		"caveegg":
			UserDB.begin_batch()
			var ce_did := 1
			var ce_remain := 143997
			var ce_blessed := false
			var ce_enh := 0
			var ce_tap := false
			var ce_art := 0
			for a6 in OS.get_cmdline_user_args():
				if a6.begins_with("--did="): ce_did = int(a6.substr(6))
				elif a6.begins_with("--remain="): ce_remain = int(a6.substr(9))
				elif a6 == "--blessed=1": ce_blessed = true
				elif a6.begins_with("--enh="): ce_enh = int(a6.substr(6))
				elif a6 == "--tap=1": ce_tap = true
				elif a6.begins_with("--art="): ce_art = int(a6.substr(6))
			var ce_grade := 7.5 if ce_blessed else 6.6
			var ce_inh := {}
			if ce_art > 0:
				ce_inh = {"art_id": ce_art,
					"element": Data.get_dragon(ce_art).get("element", "")}
			var ce_egg := UserDB.add_egg(ce_did, ce_grade, ce_remain, ce_enh, ce_inh, ce_blessed)
			UserDB.set_active(int(ce_egg["uid"]))
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			print("SHOT caveegg: uid=", ce_egg["uid"], " 남은=", UserDB.hatch_remain(
				UserDB.get_dragon(int(ce_egg["uid"]))), " 등급=", ce_grade, " 축복=", ce_blessed)
			if ce_tap:
				var ce_node := _node_with_method(get_tree().root, "_on_egg_tap")
				if ce_node != null: ce_node.call("_on_egg_tap")
				else: print("SHOT caveegg: _on_egg_tap 노드 없음")
			if "--click=1" in OS.get_cmdline_user_args():
				var ce_vis := get_viewport().get_visible_rect().size
				var ce_at := Vector2(ce_vis.x * 0.5 + 5.0, ce_vis.y * 0.5 - 30.0)
				_click_at(ce_at)
				await get_tree().process_frame
				var ce_c := _node_with_method(get_tree().root, "_on_egg_tap")
				print("SHOT caveegg click@", ce_at, " busy=", ce_c.get("_egg_busy") if ce_c else "?",
					" done=", ce_c.get("_egg_done") if ce_c else "?")
		"status":
			UserDB.begin_batch()
			for sa in OS.get_cmdline_user_args():
				if sa.begins_with("--uid="): UserDB.set_active(int(sa.split("=")[1]))
			var su := UserDB.active_uid()
			var sd := UserDB.get_dragon(su)
			if int(sd.get("level", 1)) < 35:
				UserDB.set_dragon_field(su, "level", 40)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 12: await get_tree().process_frame
			var sw := get_tree().current_scene
			var sl := StatusPanel.open(sw)
			sl.action_requested.connect(func(a, arg): print("SHOT status action: ", a, " ", arg))
			if extra == "drink":
				UserDB.add_item("att_drink1", 3)
				UserDB.add_item("hp_drink3", 1)
				for i in 8: await get_tree().process_frame
				DrinkMenu.open(sw, su, func() -> void: print("SHOT drink used"))
		"statuscave":
			Scenes.goto("cave", {"open": "status"})
		"dex":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var dx := _find_method_node(get_tree().root, "_open_dex")
			if dx == null:
				print("SHOT: _open_dex 노드 없음")
			else:
				dx.call("_open_dex")
				for i in 10: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--sel="):
						dx.call("_dex_on_click_dragon", int(a.substr(6)))
						for i in 10: await get_tree().process_frame
					elif a.begins_with("--pick="):
						dx.call("_dex_pick_step", int(a.substr(7)))
					elif a.begins_with("--ele="):
						var ei := int(a.substr(6))
						var els := ["all", "fire", "aqua", "earth", "wind",
							"light", "dark", "holy", "chaos", "shadow"]
						var btns: Array = dx.get("_dex_ele_btns")
						if ei < btns.size():
							dx.call("_dex_on_click_element", String(els[ei]), btns[ei])
		"dexinfo":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var di := _find_method_node(get_tree().root, "_open_dragon_book_info")
			if di == null:
				print("SHOT: cave 없음")
			else:
				var did := int(UserDB.get_dragon(UserDB.active_uid()).get("id", 1))
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--sel="): did = int(a.substr(6))
				di.call("_open_dragon_book_info", did)
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--tap=1"):
						for i in 15: await get_tree().process_frame
						var subj := _find_node_named(get_tree().root, "subject")
						if subj != null: di.call("_dbi_on_tap", subj)
		"caveslot":
			UserDB.begin_batch()
			var cs_uid := UserDB.active_uid()
			var cs_sk: Array = UserDB.dragon_skill_equip(cs_uid)
			var cs_star := "--star=1" in OS.get_cmdline_user_args()
			if cs_star and _cs_fill_slot1(cs_uid, cs_sk) > 0:
				cs_sk = UserDB.dragon_skill_equip(cs_uid)
			if cs_sk.size() >= 1 and int(cs_sk[0]) > 0:
				var t0 := String(Data.skills.get(str(int(cs_sk[0])), {}).get("slot", "cir"))
				var t1 := "star"
				if cs_star:
					t1 = "star"
				elif cs_sk.size() >= 2 and int(cs_sk[1]) > 0:
					var s1 := String(Data.skills.get(str(int(cs_sk[1])), {}).get("slot", "cir"))
					t1 = "sq" if s1 != "sq" else "tri"
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--slot1="): t1 = a.substr(8)
				UserDB.set_dragon_field(cs_uid, "skill_slots", [t0, t1])
				print("SHOT caveslot: skill_slots=", [t0, t1], " skills=", cs_sk,
					"  1번칸 스킬 모양=", String(Data.skills.get(
						str(int(cs_sk[1])) if cs_sk.size() >= 2 else "0", {}).get("slot", "-")))
			if int(UserDB.get_dragon(cs_uid).get("level", 1)) < 35:
				UserDB.set_dragon_field(cs_uid, "level", 40)
			Scenes.goto("cave", {})
			var cs_fx := -1.0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--equipfx="): cs_fx = float(a.substr(10))
			if cs_fx >= 0.0:
				for i in 30: await get_tree().process_frame
				var cs_cave := _find_method_node(get_tree().root, "_open_skill_select")
				if cs_cave == null:
					print("SHOT: cave 없음")
				else:
					UserDB.set_dragon_skill_equip(cs_uid, 1, 0)
					cs_cave.call("_refresh")
					for i in 6: await get_tree().process_frame
					cs_cave.call("_open_skill_select", 1)
					for i in 20: await get_tree().process_frame
					var cs_pop := _find_node_of_class(get_tree().root, "SkillLoadoutWindow")
					if cs_pop == null:
						print("SHOT: SkillLoadoutWindow 안 열림")
					else:
						var cs_list: Array = cs_pop.get("_list")
						var cs_pick := -1
						for li in cs_list.size():
							if int((cs_list[li] as Dictionary).get("id", 0)) != int(cs_sk[0]):
								cs_pick = li
								break
						if cs_pick < 0:
							print("SHOT: 1번칸에 꽂을 다른 스킬이 없다")
						else:
							cs_pop.call("_on_click_skill", cs_pick)
							for i in 4: await get_tree().process_frame
							cs_pop.call("_on_action")
							for i in 2: await get_tree().process_frame
							cs_pop.call("close")
							print("SHOT equipfx: 장착=", UserDB.dragon_skill_equip(cs_uid),
								" fx_slot=", cs_cave.get("_skill_fx_slot"))
							print("SHOT equipfx: 칸1 ← 스킬 %d (모양 %s), 칸 타입 %s" % [
								int((cs_list[cs_pick] as Dictionary).get("id", 0)),
								String(Data.skills.get(str(int((cs_list[cs_pick] as Dictionary).get(
									"id", 0))), {}).get("slot", "-")),
								String(UserDB.get_dragon(cs_uid).get("skill_slots", ["?", "?"])[1])])
							await get_tree().create_timer(cs_fx).timeout
			if "--party=1" in OS.get_cmdline_user_args():
				for i in 30: await get_tree().process_frame
				var cs_host := _find_method_node(get_tree().root, "_refresh_dragon")
				if cs_host == null:
					print("SHOT: cave 없음")
				else:
					var cs_party: Array = UserDB.party()
					if cs_party.is_empty():
						cs_party = [cs_uid]
					PartySelect.open_run(cs_host, cs_party, func(_picked: Array): pass)
		"equipfx":
			UserDB.begin_batch()
			UserDB.add_currency("gold", 900000)
			UserDB.add_item("ginu_coin_red", 5)
			var ef_uid := UserDB.active_uid()
			var ef_eq: Dictionary = UserDB.get_dragon(ef_uid).get("equip", {}).duplicate(true)
			var ef_slots: Array = ef_eq.get("slots", [])
			if ef_slots.is_empty():
				var ef_rng := RandomNumberGenerator.new(); ef_rng.randomize()
				ef_slots = [{"slot": "all", "key": "basic:깃털:6", "grade": 4, "enhance": 0,
					"belong": 0, "options": Equipment.roll_options(4, ef_rng, Data.equipment)}]
				ef_eq["slots"] = ef_slots
				UserDB.set_dragon_field(ef_uid, "equip", ef_eq)
			var ef_slot := String((ef_slots[0] as Dictionary).get("slot", "all"))
			var ef_mrng := RandomNumberGenerator.new(); ef_mrng.seed = 4242
			for ef_spec in [["basic:발톱:2", 1, 3], ["basic:비늘:4", 3, 9], ["basic:묘안석:3", 2, 8],
					["basic:흑요석:1", 2, 1], ["basic:백금석:5", 4, 1], ["basic:부적:0", 0, 0],
					["basic:깃털:3", 3, 5], ["basic:발톱:5", 2, 2]]:
				var ef_key := String((ef_spec as Array)[0])
				if not Equipment.catalog(Data.equipment).has(ef_key):
					continue
				var ef_r := int((ef_spec as Array)[1])
				UserDB.add_item(Equipment.item_key(ef_key, {
					"rarity": ef_r, "enhance": int((ef_spec as Array)[2]),
					"options": Equipment.roll_options(ef_r, ef_mrng, Data.equipment)}), 1)
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var ef_n := _find_method_node(get_tree().root, "_enhance_option")
			if ef_n == null:
				print("SHOT: cave 없음")
			else:
				var ef_tab := "enchant"
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--tab="): ef_tab = a.substr(6)
				if ef_tab == "enchant":
					var ef_pop := ItemEnchantView.open(ef_n,
						ItemEnchantView.target_worn(ef_uid, ef_slot))
					for i in 10: await get_tree().process_frame
					var ef_n2: int = (ef_pop.get("_pool") as PackedStringArray).size()
					for ef_k in 3:
						ef_pop.call("_on_cell_click", maxi(0, ef_n2 - 3 + ef_k))
						if ef_k < 2: ef_pop.call("_on_pick")
						await get_tree().process_frame

				elif ef_tab == "coinpick":
					var cp_g := int((UserDB.get_dragon(ef_uid).get("equip", {})
						.get("slots", [])[0] as Dictionary).get("grade", 4))
					var cp_coin := String((Data.equipment.get("option", {})
						.get("reroll_items", {}) as Dictionary).get(str(cp_g), "ginu_coin_red"))
					UserDB.add_item(cp_coin, 7)
					var cp_kind := String(ef_n.call("_consumable_action", cp_coin,
						Data.get_item(cp_coin)))
					print("SHOT coinpick: 동전=", cp_coin, " 등급=", cp_g, " kind=", cp_kind)
					ef_n.call("_open_inventory")
					for i in 10: await get_tree().process_frame
					ef_n.call("_use_consumable", cp_coin, cp_kind)
					for i in 10: await get_tree().process_frame
					var cp_pop := _find_method_node(get_tree().root, "_on_select")
					if cp_pop == null:
						print("SHOT coinpick: 장비 선택 창이 안 떴다")
					else:
						print("SHOT coinpick: 목록 ", (cp_pop.get("_list") as Array).size(),
							"개 · 선택 index=", int(cp_pop.get("_sel")))
						if extra == "go":
							var cp_before := UserDB.item_count(cp_coin)
							cp_pop.call("_do_regen",
								(cp_pop.get("_list") as Array)[int(cp_pop.get("_sel"))])
							for i in 160: await get_tree().process_frame
							var cp_lay := _find_method_node(get_tree().root, "_rebuild_result")
							print("SHOT coinpick: 동전 ", cp_before, "→",
								UserDB.item_count(cp_coin), " 제련창=", cp_lay != null)
							if cp_lay != null:
								cp_lay.set("_pick", 1)
								cp_lay.call("_rebuild_result")

				elif ef_tab == "smeltbag":
					var bag_key := ""
					var bag_grade := 0
					for k in UserDB.inventory().keys():
						var ks := String(k)
						if not ks.begins_with(Equipment.ITEM_PREFIX):
							continue
						var g := int(Equipment.item_key_meta(ks).get("rarity", 0))
						if String((Data.equipment.get("option", {})
								.get("reroll_items", {}) as Dictionary).get(str(g), "")) == "":
							continue
						bag_key = ks
						bag_grade = g
						break
					if bag_key == "":
						print("SHOT smeltbag: 동전을 쓸 수 있는 가방 장비가 없다")
					else:
						var bcoin := String((Data.equipment.get("option", {})
							.get("reroll_items", {}) as Dictionary).get(str(bag_grade), ""))
						UserDB.add_item(bcoin, 3)
						ef_n.call("_open_inventory")
						for i in 10: await get_tree().process_frame
						print("SHOT smeltbag: ", bag_key, " 등급=", bag_grade, " 동전=", bcoin)
						var bp = EquipOptionView.open_bag(ef_n, bag_key, bcoin, bag_grade)
						for i in 160: await get_tree().process_frame
						bp.set("_pick", 1)
						bp.call("_rebuild_result")
				else:
					var ef_sd: Dictionary = {}
					for ef_s in (UserDB.get_dragon(ef_uid).get("equip", {}).get("slots", []) as Array):
						if String((ef_s as Dictionary).get("slot", "")) == ef_slot:
							ef_sd = ef_s
					var ef_g := int(ef_sd.get("grade", 0))
					var ef_coin := String((Data.equipment.get("option", {})
						.get("reroll_items", {}) as Dictionary).get(str(ef_g), "ginu_coin_green"))
					print("SHOT eqopt 등급=", ef_g, " 동전=", ef_coin)
					var ef_p = EquipOptionView.open(ef_n, ef_uid, ef_slot, ef_coin, ef_g)
					for i in 160: await get_tree().process_frame
					ef_p.set("_pick", 1)
					ef_p.call("_rebuild_result")
		"equipslots":
			UserDB.begin_batch()
			var es_lock := false
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--tab="): es_lock = a.substr(6) == "locked"
			_seed_equip_slots(UserDB.active_uid(), es_lock)
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var es_n := _find_method_node(get_tree().root, "_open_equipment")
			if es_n == null:
				print("SHOT: cave 없음")
			else:
				es_n.call("_open_equipment")
				if es_lock:
					pass
				else:
					for a2 in OS.get_cmdline_user_args():
						if a2 == "--select":
							await get_tree().process_frame
							es_n.call("_open_item_popup", "all")
		"labslots":
			UserDB.begin_batch()
			_seed_equip_slots(UserDB.active_uid(), true)
			Scenes.goto("laboratory", {})
			for i in 30: await get_tree().process_frame
			var ls_n := _find_method_node(get_tree().root, "_open_slot_expand")
			if ls_n == null:
				print("SHOT: laboratory 없음")
			else:
				ls_n.call("_open_slot_expand", UserDB.active_uid())
		"gemshop":
			UserDB.begin_batch()
			UserDB.add_currency("gold", 9000000)
			var gs_want := "disassemble"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--tab="): gs_want = a.substr(6)
			for gs_n in ["공격의 젬", "방어의 젬", "체력의 젬"]:
				for gs_t in [0, 4, 13]:
					UserDB.add_item(Gem.item_key(gs_n, gs_t), 12 + gs_t * 30)
			UserDB.add_item(Gem.item_key("공격의 소울젬", 8), 1)
			UserDB.add_item("att_powder", 5000)
			UserDB.add_item("balrog_core", 5)
			Scenes.goto("magicshop", {})
			for i in 20: await get_tree().process_frame
			var gs := _find_method_node(get_tree().root, "_open_feature")
			if gs == null:
				print("SHOT: magicshop 없음")
			else:
				gs.set("_floor", 1)
				gs.call("_rebuild")
				for i in 8: await get_tree().process_frame
				var gs_items: Array = gs.call("_items")
				for gi in gs_items.size():
					if String((gs_items[gi] as Dictionary)["key"]) == gs_want:
						gs.call("_open_feature", gi)
						break
				for i in 8: await get_tree().process_frame
				if gs_want == "disassemble":
					var gs_keys: Array = []
					for k in UserDB.inventory().keys():
						if not Gem.parse_item_key(String(k)).is_empty(): gs_keys.append(String(k))
					gs_keys.sort()
					gs.set("_dis_slots", (gs_keys.slice(0, 6) + ["", "", "", "", "", ""]).slice(0, 6))
				else:
					gs.set("_soul_key", Gem.item_key("공격의 소울젬", 8))
				gs.call("_refresh_feature")
		"artmix":
			UserDB.begin_batch()
			var am_base := Equipment.item_key("artifact:이그니스:4")
			var am_mat := Equipment.item_key("artifact:이그니스:3")
			UserDB.add_item(am_base, 1)
			UserDB.add_item(am_mat, 3)
			UserDB.add_currency("gold", 1000000)
			Scenes.goto("mamorudiclab", {})
			for i in 30: await get_tree().process_frame
			var am_n := _find_method_node(get_tree().root, "_open_artifact_mix")
			if am_n == null:
				print("SHOT: mamorudiclab 없음")
			else:
				var am_p = ArtifactMixView.open(am_n, am_base)
				for i in 10: await get_tree().process_frame
				am_p.set("_mats", [am_mat, am_mat, am_mat])
				am_p.call("_refresh")
				print("SHOT artmix cost=", am_p.call("_cost"))
		"skillpop":
			UserDB.begin_batch()
			var sp_uid := UserDB.active_uid()
			if int(UserDB.get_dragon(sp_uid).get("level", 1)) < 35:
				UserDB.set_dragon_field(sp_uid, "level", 40)
			var sp_pool: Array = UserDB.dragon_skills(sp_uid).duplicate(true)
			var sp_have := {}
			for sp_e in sp_pool: sp_have[int((sp_e as Dictionary).get("id", 0))] = true
			for sp_k in Data.skills.keys():
				if sp_pool.size() >= 7: break
				var sp_d: Dictionary = Data.skills[sp_k]
				if not bool(sp_d.get("usable", false)): continue
				if sp_have.has(int(sp_d["id"])): continue
				sp_pool.append({"id": int(sp_d["id"]), "level": 1 + (sp_pool.size() % 3)})
			UserDB.set_dragon_field(sp_uid, "skills", sp_pool)
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var sp_n := _find_method_node(get_tree().root, "_open_skill_select")
			if sp_n == null:
				print("SHOT: _open_skill_select 노드 없음")
			else:
				sp_n.call("_open_skill_select", int(stage))
				for i in 15: await get_tree().process_frame
				var sp_pop := _find_node_of_class(get_tree().root, "SkillLoadoutWindow")
				if sp_pop != null and int(sp_pop.get("_list").size()) > 1:
					sp_pop.call("_on_click_skill", 1)
		"npc":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			var av := _find_method_node(get_tree().root, "_show_npc")
			if av != null:
				av.call("_show_npc", "nuri", 1, "4_1", "3_2")
				av.call("_narrate_npc", "누리", "탐색을 마쳤어요. 다시 길을 나서죠!")
			else:
				print("SHOT: _show_npc 노드 없음")
		"partysel":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0, "hero": true})
		"loot":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 40: await get_tree().process_frame
			var lv := _find_method_node(get_tree().root, "_play_reward_phases")
			if lv != null:
				lv.call("_play_reward_phases",
					[{"kind": "gold", "total": 290, "base": 163, "bonus": 38},
					 {"key": "att_drink2", "count": 5}],
					func() -> void: print("SHOT: reward phases done"))
			else:
				print("SHOT: _play_reward_phases 노드 없음")
		"rewardbuff":
			UserDB.begin_batch()
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var rb_on := extra != "off"
			if rb_on:
				var cv_rb := _find_method_node(get_tree().root, "_use_consumable")
				for rk in ["expx2", "goldx4"]:
					UserDB.add_item(rk, 1)
					var rkind := String(cv_rb.call("_consumable_action", rk, Data.items[rk]))
					print("SHOT rewardbuff: %s → use_kind=%s" % [rk, rkind])
					if rkind != "":
						cv_rb.call("_use_consumable", rk, rkind)
			var rb_now := int(Time.get_unix_time_from_system())
			print("SHOT rewardbuff: state=", UserDB.reward_buff(),
				" exp×", ItemEffect.reward_buff_mult(UserDB.reward_buff(), "exp", rb_now),
				" gold×", ItemEffect.reward_buff_mult(UserDB.reward_buff(), "gold", rb_now),
				" 남은=", ItemEffect.reward_buff_left_text(
					ItemEffect.reward_buff_left(UserDB.reward_buff(), "gold", rb_now)))
			var rb_json = JSON.parse_string(JSON.stringify(UserDB.reward_buff()))
			print("SHOT rewardbuff: JSON 왕복 후 gold×",
				ItemEffect.reward_buff_mult(rb_json, "gold", rb_now),
				" (1시간 뒤 ", ItemEffect.reward_buff_mult(rb_json, "gold", rb_now + 3601), ")")
			var rb_gold0 := UserDB.gold()
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			var bt := _find_method_node(get_tree().root, "_play_reward_phases")
			if bt != null:
				bt.set("_skip", true)
			for i in 600:
				await get_tree().process_frame
				if UserDB.gold() != rb_gold0:
					break
			var rb_exp := 0
			var rb_bt := _find_method_node(get_tree().root, "_play_reward_phases")
			if rb_bt != null and rb_bt.get("_exp_gained") != null:
				rb_exp = int(rb_bt.get("_exp_gained"))
			print("SHOT rewardbuff: 전투 골드 획득 = %d · EXP = %d (버프 %s)"
				% [UserDB.gold() - rb_gold0, rb_exp, "ON" if rb_on else "OFF"])
		"cutin":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 40: await get_tree().process_frame
			var bt := _find_method_node(get_tree().root, "_critical_cutin")
			if bt != null:
				bt.call("_critical_cutin", bt.get("_party")[0])
			else:
				print("SHOT: _critical_cutin 노드 없음")
		"darknix":
			var dk_status := 1
			var dk_frac := 0.28
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--status="): dk_status = int(a.substr(9))
				elif a.begins_with("--scroll="): dk_frac = float(a.substr(9))
			var dk_face := 1
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--appear="): dk_face = 0 if a.substr(9) == "1" else 1
			UserDB.darknix_summon({"status": dk_status,
				"until": int(Time.get_unix_time_from_system()) + 3600, "face": dk_face})
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 40: await get_tree().process_frame
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--revisit=") and a.substr(10) == "1":
					Scenes.goto("shop", {})
					for i2 in 20: await get_tree().process_frame
					Scenes.goto("worldmap", {"region": "yutakan"})
					for i2 in 40: await get_tree().process_frame
			var dwm := _find_method_node(get_tree().root, "_build_region_native")
			if dwm and dwm.get("_max_scroll") != null and dwm.get("_content") != null:
				var dms := float(dwm.get("_max_scroll"))
				var dcn := dwm.get("_content") as Node2D
				if dcn != null: dcn.position.x = -dms * dk_frac
			print("SHOT: darknix status=%d spine=%s" % [dk_status,
				str(dwm.get("_boss_spine") if dwm else null)])
		"dkboss":
			var bs := 2
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--status="): bs = int(a.substr(9))
			UserDB.darknix_summon({"status": bs,
				"until": int(Time.get_unix_time_from_system()) + 3600, "face": 0})
			var want_i := bs - 1
			for tryn in 3:
				Scenes.goto("worldmap", {"region": "yutakan"})
				for i in 6: await get_tree().process_frame
				Scenes.goto("adventure", {"stage": "8", "region": "yutakan", "run_seed": randi()})
				for i in 20: await get_tree().process_frame
				var av2 := _find_method_node(get_tree().root, "_party_capacity")
				var got_i := int(av2.get("_rboss_enc")) if av2 else -99
				var stp: Array = (av2.get("_steps") as Array) if av2 else []
				var kinds: Array = []
				for sv in stp: kinds.append(String((sv as Dictionary).get("type", "?")))
				print("SHOT: dkboss 진입%d — _rboss_enc=%d (기대 %d) %s | 스텝 %d개 %s"
					% [tryn + 1, got_i, want_i, "OK" if got_i == want_i else "✘ 불일치",
					   stp.size(), str(kinds)])
		"hittest":
			Scenes.goto("worldmap", {"region": stage})
			for i in 30: await get_tree().process_frame
			var hwm := _find_method_node(get_tree().root, "_resolve_click")
			if hwm == null:
				print("SHOT: worldmap 노드 없음")
			else:
				var hits: Array = hwm.get("_hits")
				var bad := 0
				var tot := 0
				for h in hits:
					if String(h.get("kind", "")) != "node" or not h.has("center"): continue
					if h.get("spr") == null: continue
					var want := String(h["arg"])
					var rc: Rect2 = h["rect"]
					for gx in 9:
						for gy in 9:
							var pt := rc.position + Vector2(rc.size.x * (gx + 0.5) / 9.0,
								rc.size.y * (gy + 0.5) / 9.0)
							if not bool(hwm.call("_opaque_at", h, pt)):
								continue
							tot += 1
							var got: Dictionary = hwm.call("_resolve_click", pt)
							if got.is_empty():
								bad += 1
								print("  ✘ %-14s 보이는데 무반응 @%d,%d" % [want, int(pt.x), int(pt.y)])
								continue
							if String(got.get("arg", "")) == want:
								continue
							if bool(hwm.call("_opaque_at", got, pt)):
								continue
							bad += 1
							print("  ✘ %-14s 를 눌렀는데 안 보이는 %s 가 가로챔 @%d,%d"
								% [want, String(got.get("arg", "")), int(pt.x), int(pt.y)])
				print("SHOT: hittest %s — 오판 %d / 보이는점 %d" % [stage, bad, tot])
		"wmclick":
			Scenes.goto("worldmap", {"region": stage})
			for i in 30: await get_tree().process_frame
			var cwm := _find_method_node(get_tree().root, "_try_click")
			if cwm == null:
				print("SHOT: wmclick — worldmap 노드 없음")
			else:
				var thit := {}
				for h in (cwm.get("_hits") as Array):
					if String(h.get("arg", "")) == extra and h.has("center"):
						thit = h
						break
				if thit.is_empty():
					print("SHOT: wmclick — '%s' 히트영역이 없다(조각이 아직 비클릭)" % extra)
				else:
					var ctr: Vector2 = thit["center"]
					var sp := (Vector2(ctr.x - float(cwm.get("_scroll")), ctr.y)
						if bool(cwm.get("_horizontal"))
						else Vector2(ctr.x, ctr.y - float(cwm.get("_scroll"))))
					cwm.call("_try_click", sp)
					await get_tree().create_timer(2.0).timeout
					print("SHOT: wmclick %s/%s → 씬 '%s' %s" % [stage, extra,
						Scenes.current_state(),
						"OK" if Scenes.current_state() == extra else "✘ 기대와 다름"])
		"dkfinish":
			var fs := 1
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--status="): fs = int(a.substr(9))
			UserDB.darknix_summon({"status": fs,
				"until": int(Time.get_unix_time_from_system()) + 3600, "face": 0})
			var fidx := fs - 1
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": "8", "region": "yutakan", "enc": fidx,
				"hp_state": {}, "streak": 0, "party_uids": [UserDB.active_uid()]})
			for i in 30: await get_tree().process_frame
			var bt2 := _find_method_node(get_tree().root, "_cycle_speed")
			if bt2 != null:
				for r in 2: bt2.call("_cycle_speed")
			var fpress := false
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--press="): fpress = a.substr(8) == "1"
			if fpress:
				await get_tree().create_timer(60.0).timeout
				var hit_it := false
				var labs: Array = []
				_all_labels(get_tree().root, labs)
				for lb in labs:
					if String((lb as Label).text) != "마무리 일격":
						continue
					_click_at(get_viewport().get_screen_transform() * (lb as Label).get_global_rect().get_center())
					hit_it = true
					break
				print("SHOT: 마무리 일격 클릭=", hit_it)
				for i in 30: await get_tree().process_frame
		"dkgate":
			var gp := 1
			var gd := 999
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--portal="): gp = int(a.substr(9))
				elif a.begins_with("--dia="): gd = int(a.substr(6))
			UserDB.begin_batch()
			UserDB.darknix_clear()
			UserDB.use_item("portal", UserDB.item_count("portal"))
			if gp > 0: UserDB.add_item("portal", gp)
			UserDB.add_currency("diamond", gd - UserDB.diamond())
			UserDB.save()
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
			var gwm := _find_method_node(get_tree().root, "_build_region_native")
			if gwm != null and gwm.has_method("_goto_target"):
				gwm.call("_goto_target", "battle:8")
			for i in 20: await get_tree().process_frame
			for btn in _all_buttons(get_tree().root):
				var bl := _find_node_named(btn.get_parent(), "label")
				if bl is Label and String((bl as Label).text) == "일반":
					_click_at(get_viewport().get_screen_transform() * btn.get_global_rect().get_center())
					break
			for i in 20: await get_tree().process_frame
		"worldmap":
			var wm_p := {"region": stage}
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--night="): wm_p["night"] = a.substr(8) == "1"
				elif a.begins_with("--kades="): wm_p["kades"] = a.substr(8) == "1"
			Scenes.goto("worldmap", wm_p)
			for i in 30: await get_tree().process_frame
			var wm := _find_method_node(get_tree().root, "_build_region_native")
			var frac := 0.5
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--scroll="): frac = float(a.substr(9))
			if wm and wm.get("_max_scroll") != null and wm.get("_content") != null:
				var ms := float(wm.get("_max_scroll"))
				var cn := wm.get("_content") as Node2D
				if cn != null: cn.position.x = -ms * frac
			for a3 in OS.get_cmdline_user_args():
				if a3.begins_with("--notice=") and wm != null and wm.has_method("_notice"):
					wm.call("_notice", a3.substr(9))
				elif a3.begins_with("--fieldfx=") and wm != null and wm.has_method("_play_field_fx"):
					wm.call("_play_field_fx", int(a3.substr(10)))
				elif a3.begins_with("--goto=") and wm != null and wm.has_method("_goto_target"):
					wm.call("_goto_target", a3.substr(7))
		"town":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			var t_area := "elpis"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--area="): t_area = a.substr(7)
			var t_night := -1
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--night="): t_night = 1 if a2.substr(8) == "1" else 0
			var t_p := {"area": t_area}
			if t_night >= 0: t_p["night"] = (t_night == 1)
			Scenes.goto("town", t_p)
			for i in 20: await get_tree().process_frame
			var tn := _find_method_node(get_tree().root, "_place_ambient")
			if tn != null:
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--scroll=") and tn != null:
						tn.set("_scroll_x", float(tn.get("_max_scroll")) * float(a.substr(9)))
						tn.call("_apply_scroll")
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--npc=") and tn != null:
						var nid := a.substr(6)
						for r in (tn.get("_npcs") as Array):
							if String(r["id"]) == nid:
								var nd := r["node"] as Node2D
								tn.set("_scroll_x", clampf(nd.position.x - 600.0, 0.0,
									float(tn.get("_max_scroll"))))
								tn.call("_apply_scroll")
								break
						tn.call("_on_npc_click", nid)
					for qa in OS.get_cmdline_user_args():
						if qa == "--qm=1" and tn != null:
							for r in (tn.get("_npcs") as Array):
								var st: String = tn.call("_npc_quest_state", int(r.get("qslot", -1)))
								if st != "": print("QM ", r["id"], " slot=", r.get("qslot"), " -> ", st)
					for fa in OS.get_cmdline_user_args():
						if fa.begins_with("--face=") and tn != null:
							var f := -1 if fa.substr(7) == "L" else 1
							for r in (tn.get("_npcs") as Array):
								r["facing"] = f
								tn.call("_npc_face", r)
								tn.call("_npc_play", r, "walk")
		"questflow":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			UserDB.set_pmeta("quests", {"date": Time.get_date_string_from_system()})
			var qs := Scenes.current_scene()
			print("QF state0=", qs.call("_npc_quest_state", 1))
			qs.call("_on_npc_click", "kanggalo")
			await get_tree().create_timer(2.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_offer.png")
			var ch := _find_label_button(qs, "수락")
			if ch != null: ch.emit_signal("pressed")
			for i in 10: await get_tree().process_frame
			print("QF accepted=", UserDB.quest_accepted("hatches"), " state1=", qs.call("_npc_quest_state", 1))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_ok.png")
			UserDB.bump_quest("hatches")
			print("QF progress=", UserDB.quest_progress("hatches"), " state2=", qs.call("_npc_quest_state", 1))
			var g0 := UserDB.gold()
			qs.call("_on_npc_click", "kanggalo")
			for i in 10: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_talk.png")
			for c4 in qs.get_children():
				if c4 is NpcDialogue: c4.emit_signal("advanced")
			for i in 10: await get_tree().process_frame
			print("QF cleared=", UserDB.quest_claimed("hatches"), " gold+", UserDB.gold() - g0)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_clear.png")
			UserDB.set_pmeta("quests", {"date": Time.get_date_string_from_system()})
			qs.call("_on_npc_click", "pino")
			for i in 8: await get_tree().process_frame
			var nb := _find_label_button(qs, "거절")
			if nb != null: nb.emit_signal("pressed")
			for i in 8: await get_tree().process_frame
			print("QF refused gaveup=", UserDB.quest_gaveup("feeds"), " state=", qs.call("_npc_quest_state", 2))
			get_tree().quit()
		"townwire":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 30: await get_tree().process_frame
			var tw_town := Scenes.current_scene()
			var tw_acts := []
			for ha in (tw_town.get("_hit_areas") as Array):
				tw_acts.append(String(ha.get("action", "")))
			print("WIRE hit_actions=", tw_acts)
			print("WIRE cave=", "cave" in tw_acts, " quest_board_removed=", not ("quest" in tw_acts))
			var tw_vis := get_viewport().get_visible_rect().size
			var tw_k: Vector2 = Vector2(DisplayServer.window_get_size()) / tw_vis
			_click_at(Vector2(tw_vis.x - 50.0, 50.0) * tw_k)
			for i in 30: await get_tree().process_frame
			print("WIRE after_close=", Scenes.current_state())
			Scenes.goto("town", {"area": "elpis"})
			for i in 30: await get_tree().process_frame
			_click_at(Vector2(180.0, 60.0) * tw_k)
			for i in 10: await get_tree().process_frame
			var tw_pop := false
			for c in Scenes.current_scene().get_children():
				if c is CanvasLayer and (c as CanvasLayer).layer == 30: tw_pop = true
			print("WIRE quest_popup=", tw_pop)
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_questpop.png")
			print("WIRE shot=res://scratch_shots/_questpop.png")
			UserDB.begin_batch()
			var tw_scene := Scenes.current_scene()
			for q in (tw_scene.get("_QUESTS") as Array):
				UserDB.claim_quest(String((q as Dictionary)["key"]))
			for c2 in tw_scene.get_children():
				if c2 is CanvasLayer and (c2 as CanvasLayer).layer == 30: c2.queue_free()
			var qmeta: Dictionary = (UserDB.get_pmeta("quests", {}) as Dictionary).duplicate()
			qmeta.erase("claimed_town_total")
			UserDB.set_pmeta("quests", qmeta)
			for i in 5: await get_tree().process_frame
			tw_scene.call("_open_quests")
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_questpop_done.png")
			print("WIRE shot_done=res://scratch_shots/_questpop_done.png")
			var tot_g0 := UserDB.gold()
			var totb := _find_label_button(tw_scene, "보상 받기")
			print("WIRE quest_total_btn_enabled=", totb != null and not totb.disabled)
			if totb != null:
				totb.emit_signal("pressed")
				await get_tree().create_timer(0.8).timeout
				var tot_pop := false
				for c7 in tw_scene.get_children():
					if c7 is CanvasLayer and (c7 as CanvasLayer).layer == 40: tot_pop = true
				print("WIRE quest_total claimed=", UserDB.quest_claimed("town_total"),
					" reward_popup=", tot_pop,
					" gold_delta=", UserDB.gold() - tot_g0, "(0 이어야 한다 — 골드 보상 폐기)")
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://scratch_shots/_questtotal.png")
				print("WIRE shot_total=res://scratch_shots/_questtotal.png")
			else:
				print("WIRE quest_total: 보상 받기 버튼 없음")
			UserDB.set_pmeta("quests", {"date": Time.get_date_string_from_system()})
			UserDB.accept_quest("battles")
			for c3 in tw_scene.get_children():
				if c3 is CanvasLayer and (c3 as CanvasLayer).layer >= 30: c3.queue_free()
			for i in 5: await get_tree().process_frame
			tw_scene.call("_open_quests")
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			var tw_call := tw_scene.find_child("RaonCallButton", true, false)
			print("WIRE raon_button=", tw_call != null)
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_raoncall.png")
			print("WIRE shot_raon_call=res://scratch_shots/_raoncall.png")
			for c6 in tw_scene.get_children():
				if c6 is CanvasLayer and (c6 as CanvasLayer).layer >= 30: c6.queue_free()
			for i in 5: await get_tree().process_frame
			tw_scene.call("_open_raon_help")
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			var tw_talk: NpcDialogue = null
			for c4 in tw_scene.get_children():
				if c4 is NpcDialogue: tw_talk = c4
			print("WIRE raon_talk=", tw_talk != null)
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_raontalk.png")
			print("WIRE shot_raon_talk=res://scratch_shots/_raontalk.png")
			if tw_talk != null:
				tw_talk.call("_tap")
				await get_tree().process_frame
				if is_instance_valid(tw_talk):
					tw_talk.call("_tap")
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_raonhelp.png")
			print("WIRE shot_raon=res://scratch_shots/_raonhelp.png")
			var dia0 := UserDB.diamond()
			var okb := _find_label_button(tw_scene, "확인")
			if okb != null:
				okb.emit_signal("pressed")
				await get_tree().create_timer(1.0).timeout
				var tw_talk2: NpcDialogue = null
				for c5 in tw_scene.get_children():
					if c5 is NpcDialogue: tw_talk2 = c5
				print("WIRE raon_clear_talk=", tw_talk2 != null)
				print("WIRE raon_pay dia=", dia0, "->", UserDB.diamond(),
					" claimed=", UserDB.quest_claimed("battles"),
					" progress=", UserDB.quest_progress("battles"),
					" cnt=", UserDB.quest_count("dia_clear"),
					" next_price=", tw_scene.call("_raon_price"))
			else:
				print("WIRE raon_pay: 확인 버튼 없음")
			get_tree().quit()
		"raontest":
			UserDB.begin_batch()
			Scenes.goto("town", {"area": "elpis"})
			for i in 30: await get_tree().process_frame
			var rt_scene := Scenes.current_scene()
			UserDB.set_pmeta("quests", {"date": Time.get_date_string_from_system()})
			UserDB.accept_quest("battles")
			for i in 5: await get_tree().process_frame
			rt_scene.call("_open_quests")
			print("[raontest] 미션판을 열었다. 왼쪽 라온(말풍선 '도움이 필요한가?')을 누르면")
			print("[raontest]   제안 대사창 → 확인 팝업 → 확인/취소 → 수락/거절 대사창 순으로 간다.")
			print("[raontest] 세이브는 잠겨 있다(begin_batch) — 다이아를 써도 실제로 안 빠진다.")
		"shop":
			var shop_tab := ""
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--tab="): shop_tab = a2.substr(6)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("shop", {"tab": shop_tab} if shop_tab != "" else {})
		"magicshop":
			var feat := 3
			var ms_floor := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--feat="): feat = int(a.substr(7))
				elif a.begins_with("--floor="): ms_floor = int(a.substr(8))
				elif a == "--sands=1":
					UserDB.begin_batch()
					UserDB.add_item("alchemy_platinum_01", 3)
					UserDB.add_item("alchemy_platinum_02", 2)
					for pk in ["hp_powder", "att_powder", "def_powder"]:
						UserDB.add_item(pk, 60)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("magicshop", {})
			var ms: Node = null
			for i in 180:
				await get_tree().process_frame
				var c := Scenes.current_scene()
				if c != null and c.has_method("_open_feature") \
						and c.is_inside_tree() and c.is_node_ready():
					ms = c
					break
			for i in 5: await get_tree().process_frame
			if ms == null:
				push_error("[shot] magicshop 진입 실패")
			else:
				if ms_floor != 0:
					ms.call("_set_floor", ms_floor)
					for i in 20: await get_tree().process_frame
				ms.call("_open_feature", feat)
				for i in 20: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--pick="):
						for _p in int(a.substr(7)):
							ms.call("_cycle_sands")
							for i in 6: await get_tree().process_frame
				print("SHOT magicshop: floor=", ms.get("_floor"), " feat=", feat,
					" 눈물=", ms.get("_sands_key"),
					" 확률=", Gem.sands_chance(Data.gems, ms.call("_sands_bonus_pct")))
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--reveal="):
						ms.set("_egg_reveal", [int(a.substr(9))])
						ms.call("_reveal_eggs", "코드에 응답하여 %s의 알이 나타났습니다.")
						for i in 20: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if not a.begins_with("--redeem="):
						continue
					UserDB.begin_batch()
					for t in 4:
						var got: Dictionary = ms.call("_redeem_code", a.substr(9))
						var line := "[shot] 코드 %d회차 → " % (t + 1)
						if got.is_empty():
							line += "거부"
						else:
							var lim := int(got.get("uses", 1))
							line += "성공(보상 %d건, 제한 %s)" % [
								(got.get("rewards", []) as Array).size(),
								"무제한" if lim == 0 else "%d회" % lim]
						print(line)
						await get_tree().process_frame
				if OS.get_cmdline_user_args().has("--pickmat"):
					UserDB.begin_batch()
					UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
					for d in UserDB.dragons():
						if UserDB.is_egg(d) or Summon.SPECIES.has(int(d.get("id", 0))):
							continue
						d["level"] = maxi(int(d.get("level", 1)), Summon.MATERIAL_MIN_LEVEL)
						if Summon.can_be_material(d, ms.call("_grade_of", d)):
							ms.set("_summon_uid", int(d["uid"]))
							break
					ms.call("_refresh_feature")
					for i in 20: await get_tree().process_frame
				if OS.get_cmdline_user_args().has("--summon"):
					UserDB.begin_batch()
					UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
					for d in UserDB.dragons():
						if UserDB.is_egg(d) or Summon.SPECIES.has(int(d.get("id", 0))):
							continue
						d["level"] = maxi(int(d.get("level", 1)), Summon.MATERIAL_MIN_LEVEL)
						if Summon.can_be_material(d, ms.call("_grade_of", d)):
							ms.set("_summon_uid", int(d["uid"]))
							break
					ms.call("_refresh_feature")
					for i in 10: await get_tree().process_frame
					var mat_uid := int(ms.get("_summon_uid"))
					var mat := UserDB.get_dragon(mat_uid)
					var mat_name := Icons.name_of(mat)
					ms.call("_do_summon")
					for i in 20: await get_tree().process_frame
					var sp_id := int(ms.get("_summon_species"))
					print("SHOT summon: 재료='", mat_name, "'  종이름(", sp_id, ")='",
						UserDB.species_name(sp_id), "'  Icons.species_name='",
						Icons.species_name(sp_id), "'")
					var sk := EggItem.key(EggGacha.key_for(sp_id), Summon.EGG_ENHANCE_STEP)
					print("SHOT summon: 가방키='", sk, "' 개수=", UserDB.item_count(sk),
						"  종art=", UserDB.species_art(sp_id),
						"  알그림=", Icons.dragon_egg_texture(sp_id) != null,
						"  가방표시명='", Icons.egg_item_name(sp_id), "'")
					if OS.get_cmdline_user_args().has("--bag=1"):
						var stack: Array = [get_tree().root]
						while not stack.is_empty():
							var n: Node = stack.pop_back()
							if n is EggResultView:
								n.queue_free()
								continue
							for c in n.get_children():
								stack.append(c)
						await get_tree().process_frame
						ms.call("_leave")
						for i in 30: await get_tree().process_frame
						Scenes.goto("cave", {})
						for i in 40: await get_tree().process_frame
						var sb := _find_method_node(get_tree().root, "_open_inventory")
						if sb != null:
							sb.set("_inv_tab", "egg")
							sb.set("_inv_selected", sk)
							sb.call("_open_inventory")
						else:
							print("SHOT summon: _open_inventory 노드 없음")
						for i in 10: await get_tree().process_frame
				for pa in OS.get_cmdline_user_args():
					if pa.begins_with("--pull=") and ms.has_method("_pull_slot"):
						UserDB.begin_batch()
						var pn := int(pa.substr(7))
						var pprice := int((Data.drops.get("slot", {}) as Dictionary)
							.get("price_gold", 1000))
						var g0 := UserDB.gold()
						ms.call("_pull_slot", pprice, pn)
						await get_tree().create_timer(3.6).timeout
						var inv := UserDB.inventory()
						print("SHOT slot: n=", pn, " 골드 ", g0, "->", UserDB.gold(),
							"  보유 포탈=", int(inv.get("portal", 0)),
							" 의문의알=", int(inv.get("mall_question_egg", 0)))
		"unodaily":
			Scenes.goto("worldmap", {"region": "uno"})
			for i in 30: await get_tree().process_frame
			var wu := _find_method_node(get_tree().root, "_open_dungeon_popup")
			if wu != null:
				UserDB.begin_batch()
				var sid := stage if stage != "1" else "24"
				print("SHOT daily(before stamp) ok=", wu.call("_daily_ok", sid))
				wu.call("_daily_stamp", sid)
				print("SHOT daily(after  stamp) ok=", wu.call("_daily_ok", sid))
				wu.call("_open_dungeon_popup", sid)
				for i in 10: await get_tree().process_frame
				wu.call("_confirm_daily_extra", Callable(), false)
			else: print("SHOT: worldmap 아님")
		"mamomenu":
			Scenes.goto("mamorudiclab", {})
		"mamosmelt":
			UserDB.begin_batch()
			UserDB.add_item("anima", 9)
			UserDB.add_item("bonner", 9)
			UserDB.add_item(Equipment.item_key("artifact:루멘:5",
				{"rarity": 3, "options": [{"stat": "att", "value": 7},
					{"stat": "hp", "value": 4}, {"stat": "gold", "value": 3}]}), 1)
			UserDB.add_item(Equipment.item_key("artifact:테라:2",
				{"rarity": 4, "options": [{"stat": "pure", "value": 9},
					{"stat": "def", "value": 5}, {"stat": "blk", "value": 2},
					{"stat": "exp", "value": 6}]}), 1)
			Scenes.goto("mamorudiclab", {})
			for i in 40: await get_tree().process_frame
			var ms := _find_method_node(get_tree().root, "_open_artifact_smelt")
			if ms == null:
				print("SHOT: _open_artifact_smelt 노드 없음")
			else:
				ms.call("_open_artifact_smelt")
				for i in 20: await get_tree().process_frame
				var n_rows := 0
				for b in _all_buttons(get_tree().root):
					if b is Button and String((b as Button).text).begins_with("  "):
						n_rows += 1
				print("SHOT mamosmelt 목록행=", n_rows,
					" (아니마=", UserDB.item_count("anima"),
					" 보네르=", UserDB.item_count("bonner"), ")")
		"mamolab":
			Scenes.goto("mamorudiclab", {"tab": 0})
		"mamostone":
			UserDB.begin_batch()
			UserDB.set_pmeta("awaken_stone", {"star": 5, "points": 10230})
			Scenes.goto("mamorudiclab", {"tab": 1})
		"mamostonemake":
			var over_case := false
			var done_case := false
			for a in OS.get_cmdline_user_args():
				if a == "--stage2=over": over_case = true
				elif a == "--stage2=done": over_case = true; done_case = true
			UserDB.begin_batch()
			UserDB.set_pmeta("awaken_stone", {"star": 5, "points": 19500 if over_case else 10230})
			for did in [1, 54, 100]:
				UserDB.add_item(EggGacha.key_for(did), 3)
			Scenes.goto("mamorudiclab", {"tab": 1})
			for i in 30: await get_tree().process_frame
			var mm := _find_method_node(get_tree().root, "_open_stone_make")
			if mm != null: mm.call("_open_stone_make")
			else: print("SHOT: mamorudiclab 아님")
			if over_case:
				for i in 20: await get_tree().process_frame
				var spop := _find_method_node(get_tree().root, "add_action_button")
				var ups: Array = []
				if spop != null: _all_texture_buttons(spop, ups)
				if ups.size() >= 2: (ups[1] as TextureButton).emit_signal("pressed")
				else: print("SHOT: ▲ 버튼 못 찾음 (", ups.size(), ")")
				for i in 10: await get_tree().process_frame
				_press_label_button(get_tree().root, "강화")
				for i in 15: await get_tree().process_frame
				if done_case:
					_press_label_button(get_tree().root, "확인")
					for i in 30: await get_tree().process_frame
		"mamoselect":
			Scenes.goto("mamorudiclab", {"tab": 0})
			for i in 30: await get_tree().process_frame
			var ms := _find_method_node(get_tree().root, "_open_dragon_select")
			if ms != null:
				UserDB.begin_batch()
				for k in ["anima", "bonner"]: UserDB.add_item(k, 200)
				for g in [3, 4, 5, 6]: UserDB.add_item("evol_jewel_%d" % g, 2)
				ms.call("_open_dragon_select")
			else: print("SHOT: mamorudiclab 아님")
		"mamodex":
			Scenes.goto("mamorudiclab", {"tab": 0})
			for i in 30: await get_tree().process_frame
			var md := _find_method_node(get_tree().root, "_open_awaken_dex")
			if md != null:
				UserDB.begin_batch()
				for d in UserDB.dragons():
					if UserDB.is_egg(d): continue
					var dno := Data.awaken_skill_of(int(d.get("id", 0)))
					if dno > 0:
						UserDB.set_dragon_field(int(d["uid"]), "awakened", true)
						UserDB.set_dragon_field(int(d["uid"]), "awaken_skill", dno)
				md.call("_open_awaken_dex")
			else: print("SHOT: mamorudiclab 아님")
		"unopop":
			Scenes.goto("worldmap", {"region": "uno"})
			for i in 30: await get_tree().process_frame
			var up := _find_method_node(get_tree().root, "_open_dungeon_popup")
			if up != null: up.call("_open_dungeon_popup", stage if stage != "1" else "24")
			else: print("SHOT: worldmap 아님")
		"awakenpop":
			Scenes.goto("mamorudiclab", {"from": "worldmap"})
			for i in 30: await get_tree().process_frame
			var ml := _find_method_node(get_tree().root, "_open_awaken_confirm")
			if ml != null:
				UserDB.begin_batch()
				for k in ["anima", "bonner"]:
					UserDB.add_item(k, 40)
				UserDB.add_item("evol_jewel_5", 2)
				var cand: Array = UserDB.dragons().filter(func(d):
					return not UserDB.is_egg(d) and not bool(d.get("awakened", false)))
				if cand.is_empty(): print("SHOT: 각성 대상 없음")
				else: ml.call("_open_awaken_confirm", cand[0])
			else: print("SHOT: mamorudiclab 아님")
		"dragongate":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			var dg := _find_method_node(get_tree().root, "_selected_gate")
			if dg == null:
				print("SHOT: worldmap 아님")
			else:
				UserDB.begin_batch()
				var duid := int(UserDB.active_uid())
				var dfmax: int = ItemEffect.food_max(Data.item_effects)
				var dpop := func() -> int:
					var c := 0
					for ch in dg.get_children():
						if ch is CanvasLayer: c += 1
					return c
				UserDB.set_dragon_field(duid, "food", dfmax)
				UserDB.set_cure_time(duid, 0)
				var dbase: int = dpop.call()
				print("SHOT dragongate 정상: gate=", dg.call("_selected_gate"),
					" 팝업+", dpop.call() - dbase)
				UserDB.set_cure_time(duid, int(Time.get_unix_time_from_system()) + 3600)
				print("SHOT dragongate 행동불능: gate=", dg.call("_selected_gate"),
					" 팝업+", dpop.call() - dbase,
					" 비용=", Incapacitation.instant_cost(Data.incapacitation,
						UserDB.cure_time(duid), int(Time.get_unix_time_from_system())), "다이아")
				for t in _dump_texts(dg, dbase): print("   | ", t)
				_free_popups(dg, dbase)
				UserDB.set_cure_time(duid, 0)
				UserDB.set_dragon_field(duid, "food", 0)
				var del := String(Data.get_dragon(int(UserDB.get_dragon(duid)
					.get("id", 0))).get("element", ""))
				print("SHOT dragongate 허기(먹이없음): 속성=", del, " 보유먹이='",
					ItemEffect.find_matching_feed(UserDB.inventory(), Data.items, del),
					"' gate=", dg.call("_selected_gate"), " 팝업+", dpop.call() - dbase)
				for t in _dump_texts(dg, dbase): print("   | ", t)
				_free_popups(dg, dbase)
				var dfeed := ""
				for dk in Data.items:
					var didef: Dictionary = Data.items[dk]
					if ItemEffect.is_feed(didef) and ItemEffect.feed_matches(didef, del):
						dfeed = String(dk); break
				if dfeed != "":
					UserDB.add_item(dfeed, 1)
					print("SHOT dragongate 허기(먹이있음): 먹이=", dfeed,
						" gate=", dg.call("_selected_gate"), " 팝업+", dpop.call() - dbase)
					for t in _dump_texts(dg, dbase): print("   | ", t)
					var dhad := int(UserDB.inventory().get(dfeed, 0))
					for db2 in _all_buttons(dg):
						if (db2 as Button).text == "확인":
							(db2 as Button).emit_signal("pressed"); break
					print("SHOT dragongate 먹인 뒤: food=",
						int(UserDB.get_dragon(duid).get("food", -1)), "/", dfmax,
						" 먹이 ", dhad, "→", int(UserDB.inventory().get(dfeed, 0)))
				UserDB.set_dragon_field(duid, "food", dfmax)
		"cardgate":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": stage if stage != "1" else "1",
				"region": "yutakan", "enc": 0, "hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			var gt := _find_method_node(get_tree().root, "_is_fortress")
			if gt != null:
				print("SHOT gate stage=", stage, " is_fortress=", gt.call("_is_fortress"),
					" event_open=", gt.get("_event_open"))
			else: print("SHOT: adventure 아님")
		"cardadv":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": "6", "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			var cg_chk := _find_method_node(get_tree().root, "_is_fortress")
			if cg_chk != null:
				print("SHOT cardadv is_fortress=", cg_chk.call("_is_fortress"))
			var ca := _find_method_node(get_tree().root, "_open_cardgame")
			if ca != null:
				var cmode := "match"
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--mode="): cmode = a.substr(7)
				ca.call("_open_cardgame", cmode)
			else: print("SHOT: adventure 아님")
		"cardgame":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			var cg_mode := stage if (stage == "match" or stage == "avoid") else "match"
			var cg := CardMatchGame.open(get_tree().current_scene, cg_mode,
				func(res): print("SHOT cardgame result=", res))
			for i in 20: await get_tree().process_frame
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--pick="):
					for sidx in a.substr(7).split(","):
						if is_instance_valid(cg):
							cg.call("_on_pick", int(sidx))
							await get_tree().create_timer(0.7).timeout
			if is_instance_valid(cg):
				var dk = cg.get("_deck")
				if dk is Dictionary:
					var ks: Array = []
					for c in (dk.get("cards", []) as Array):
						ks.append(String(c.get("label", "?")))
					print("SHOT cardgame deck=", ks)
		"shopbuy", "shopbuymax":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("shop", {"tab": stage if stage != "1" else "food"})
			for i in 30: await get_tree().process_frame
			var sh := _find_method_node(get_tree().root, "_on_card")
			if sh != null:
				var ents: Array = sh.call("_entries")
				if ents.is_empty(): print("SHOT: 진열 상품 없음")
				else: sh.call("_on_card", ents[0])
				if shot == "shopbuymax":
					for i in 10: await get_tree().process_frame
					var mb := _find_button_text(get_tree().root, "MAX")
					if mb == null:
						print("SHOT: MAX 버튼 없음")
					else:
						mb.emit_signal("pressed")
						await get_tree().process_frame
			else: print("SHOT: shop 씬 아님")
		"shophot", "shoppvp", "shopfood", "shopitem", "shopegg", "shopetc", "shopsell":
			if extra == "owned":
				UserDB.begin_batch()
				UserDB.set_pmeta("blessed_nest", true)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("shop", {"tab": shot.substr(4)})
			if extra == "boxtouch":
				for i in 90: await get_tree().process_frame
				var bx := _find_bottom_box(get_tree().root)
				if bx == null:
					print("SHOT: BottomTextBox 없음")
				else:
					var before := _box_text(bx)
					var bp2 := get_viewport().get_screen_transform() * bx.get_global_rect().get_center()
					_click_at(bp2)
					for i in 90: await get_tree().process_frame
					print("SHOT box touch: 대사 바뀜=", _box_text(bx) != before,
						"\n  before=", before, "\n  after =", _box_text(bx))
			if extra == "touch":
				for i in 25: await get_tree().process_frame
				var tb := get_tree().root.find_child("NpcTouchButton", true, false) as Control
				if tb == null:
					print("SHOT: NpcTouchButton 없음 — 대체 판매원이 아니다")
				else:
					var tp := get_viewport().get_screen_transform() * tb.get_global_rect().get_center()
					for _t in maxi(1, int(stage)):
						_click_at(tp)
						for i in 8: await get_tree().process_frame
					var thov := get_viewport().gui_get_hovered_control()
					print("SHOT npc touch: click=", tp, " hovered=",
						thov.get_path() if thov else "<없음>")
		"gachapull":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("shop", {"tab": "item"})
			for i in 25: await get_tree().process_frame
			var gp := _find_method_node(get_tree().root, "_confirm_gacha")
			if gp == null:
				print("SHOT: _confirm_gacha 노드 없음")
			else:
				UserDB.begin_batch()
				UserDB.add_currency("diamond", 2000)
				var before := 0
				for k in UserDB.inventory().keys():
					if String(k).begins_with("equip:event:"): before += int(UserDB.inventory()[k])
				gp.call("_confirm_gacha", {"pool": "equip", "price": 0, "cur": "diamond",
					"n": 10, "label": "장비 뽑기 10연속"})
				for i in 6: await get_tree().process_frame
				var gb := _find_label_button(get_tree().root, "뽑기")
				if gb != null: gb.emit_signal("pressed")
				else: print("SHOT: 뽑기 버튼 없음")
				for i in 25: await get_tree().process_frame
				var after := 0
				var kinds := {}
				for k2 in UserDB.inventory().keys():
					if String(k2).begins_with("equip:"):
						kinds[String(k2)] = int(UserDB.inventory()[k2])
						if String(k2).begins_with("equip:event:"): after += int(UserDB.inventory()[k2])
				print("SHOT gacha event_equip ", before, "->", after, " total_equip_keys=", kinds.size())
		"main", "main_night":
			UserDB.begin_batch()
			if not UserDB.has_user_nickname():
				UserDB.set_user_nickname("계란")
			if UserDB.user_title_no() <= 0:
				UserDB.set_pmeta("title_no", 1)
			UserDB.set_pmeta("yutakan_night", shot == "main_night")
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
		"setting":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
			var st_hud := _find_method_node(get_tree().root, "_act")
			if st_hud == null:
				print("SHOT: MainHud 없음")
			else:
				st_hud.call("_act", "setting")
				for i in 15: await get_tree().process_frame
				print("SHOT setting: 볼륨 music=", Bgm.music_volume(),
					" effect=", Bgm.effects_volume())
				if stage == "confirm" or stage == "doreset":
					_press_label_button(get_tree().root, "세이브 데이터 초기화")
					for i in 15: await get_tree().process_frame
				if stage == "doreset":
					_press_label_button(get_tree().root, "초기화")
					for i in 40: await get_tree().process_frame
					var wm := _find_method_node(get_tree().root, "_region_bgm")
					print("SHOT doreset: state=", Scenes.current_state(),
						" region=", (wm.get("_mode") if wm != null else "?"),
						" 밤=", bool(UserDB.get_pmeta("yutakan_night", false)),
						" 드래곤=", UserDB.dragon_count(),
						" 골드=", UserDB.gold(), " 다이아=", UserDB.diamond(),
						" 빛문알=", int(UserDB.inventory().get("mall_question_egg2", 0)),
						" 닉네임팝업=", _find_builtin(get_tree().root, "LineEdit") != null)
		"mainnav":
			for i in 30: await get_tree().process_frame
			var hud := _find_method_node(get_tree().root, "_act")
			if hud == null:
				print("SHOT: MainHud 없음")
			else:
				hud.call("_act", stage)
				for i in 40: await get_tree().process_frame
				print("SHOT nav -> state=", Scenes.current_state())
		"intro":
			for i in 60: await get_tree().process_frame
			var it := _find_method_node(get_tree().root, "_build_start_prompt")
			print("SHOT intro: state=", Scenes.current_state(),
				" 씬=", it != null, " bgm=", Bgm._cur)
			if stage == "start":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				ev.position = get_viewport().get_visible_rect().size * 0.5
				Input.parse_input_event(ev)
				for i in 60: await get_tree().process_frame
				print("SHOT intro start -> state=", Scenes.current_state())
		"nick":
			for i in 20: await get_tree().process_frame
			RenameDialog.open(get_tree().root.get_node("Main"), false)
			if stage == "confirm":
				UserDB.begin_batch()
				for i in 10: await get_tree().process_frame
				var le := _find_builtin(get_tree().root, "LineEdit") as LineEdit
				var btn := _find_button_text(get_tree().root, "확인")
				print("SHOT nick: 입력칸=", le != null, " 확인버튼=", btn != null,
					" 포커스뺏김방지=", btn != null and btn.focus_mode == Control.FOCUS_NONE)
				if le != null and btn != null:
					le.text = "테스트닉"
					btn.emit_signal("pressed")
					for i in 10: await get_tree().process_frame
					print("SHOT nick 저장=", UserDB.user_nickname(),
						" 팝업닫힘=", _find_builtin(get_tree().root, "LineEdit") == null)
		"status":
			for i in 30: await get_tree().process_frame
			var dv := _find_method_node(get_tree().root, "_open_dragon_detail")
			if dv != null: dv.call("_open_dragon_detail")
			else: print("SHOT: _open_dragon_detail 노드 없음")
		"quests":
			for i in 30: await get_tree().process_frame
			MissionBoard.open(get_tree().current_scene, 0, "worldmap", {})
			for i in 5: await get_tree().process_frame
		"inven":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var iv := _find_method_node(get_tree().root, "_open_inventory")
			if iv != null: iv.call("_open_inventory")
			else: print("SHOT: _open_inventory 노드 없음")
		"invenegg":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var ie_did := 1
			var ie_gacha := false
			var ie_grade := true
			for a3 in OS.get_cmdline_user_args():
				if a3.begins_with("--did="): ie_did = int(a3.substr(6))
				elif a3 == "--gacha=1": ie_gacha = true
				elif a3 == "--grade=0": ie_grade = false
			var ie_sel := 0
			for a4 in OS.get_cmdline_user_args():
				if a4.begins_with("--sel="): ie_sel = int(a4.substr(6))
			var ie_key := "mall_question_egg" if ie_gacha else EggItem.key(
				EggGacha.key_for(ie_did), ie_sel)
			var ie_base := EggItem.base_of(ie_key)
			UserDB.add_item(ie_key, 3)
			UserDB.add_item(ie_base, 3)
			if ie_grade and not ie_gacha:
				UserDB.add_item(EggItem.key(ie_base, 1), 2)
				UserDB.add_item(EggItem.key(ie_base, 3), 1)
			var ie := _find_method_node(get_tree().root, "_open_inventory")
			if ie != null:
				ie.call("_open_inventory")
				for i in 5: await get_tree().process_frame
				ie.set("_inv_tab", "egg")
				ie.set("_inv_selected", ie_key)
				ie.call("_inventory_refresh_grid")
				ie.call("_inventory_refresh_detail")
				var ie_slots: Array = []
				for g in [0, 1, 2, 3]:
					var gk := EggItem.key(EggItem.base_of(ie_key), g)
					if UserDB.item_count(gk) > 0:
						ie_slots.append("%s=%d" % [gk, UserDB.item_count(gk)])
				print("SHOT invenegg: 선택=", ie_key, " 등급=", EggItem.grade_of(ie_key),
					"  등급별 칸: ", ", ".join(ie_slots))
			else: print("SHOT: _open_inventory 노드 없음")
		"inven_detail":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var id_uid := UserDB.active_uid()
			for k in ["food_fire_chicken", "att_drink1",
					"eggmix1", "mix_book",
					"anima", "crystal2_chaos",
					"ascension", "bless_of_amor",
					"gem:공격의 젬:3", "gem:공격의 소울젬:2",
					Loadout.item_key(13, 2),
					Loadout.item_key(11, 1),
					"equip:basic:발톱:0",
					"equip:artifact:루멘:5",
					"equip:b%d,r4,e2,oA7.P5@basic:깃털:6" % id_uid]:
				UserDB.add_item(k, 2)
			var id_tab := "food"
			var id_key := ""
			var id_gridx := -1
			var id_fill := false
			for a5 in OS.get_cmdline_user_args():
				if a5.begins_with("--tab="): id_tab = a5.substr(6)
				elif a5.begins_with("--key="): id_key = a5.substr(6)
				elif a5.begins_with("--gridx="): id_gridx = int(a5.substr(8))
				elif a5 == "--fill=1": id_fill = true
			if id_fill:
				for ik in Data.items:
					if Data.items[ik] is Dictionary and Data.items[ik].has("category"):
						UserDB.add_item(String(ik), 1)
			var idv := _find_method_node(get_tree().root, "_open_inventory")
			if idv == null:
				print("SHOT: _open_inventory 노드 없음")
			else:
				idv.set("_inv_tab", id_tab)
				idv.set("_inv_selected", id_key)
				idv.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				var id_sc: ScrollContainer = idv.get("_inv_grid_sc")
				if id_gridx >= 0 and is_instance_valid(id_sc):
					id_sc.scroll_horizontal = id_gridx
					for i in 5: await get_tree().process_frame
				print("SHOT inven_detail: 탭=", id_tab, " 선택=", idv.get("_inv_selected"),
					" 패널=", _find_node_named(get_tree().root, "item_detail") != null,
					" 그리드폭=", id_sc.get_child(0).size.x if is_instance_valid(id_sc) else -1,
					" 스크롤=", id_sc.scroll_horizontal if is_instance_valid(id_sc) else -1,
					"/", id_sc.get_h_scroll_bar().max_value if is_instance_valid(id_sc) else -1)
		"custom_dragon":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 15: await get_tree().process_frame
			UserDB.begin_batch()
			var cids: Array = []
			for did in [666, 777]:
				var rec := UserDB.add_dragon(did, 1)
				var uid := int(rec.get("uid", 0))
				if uid <= 0: continue
				var lr := RandomNumberGenerator.new(); lr.seed = 7
				var ldef := Data.get_dragon(did)
				for _i in 49:
					UserDB.level_up_with(uid, LevelSystem.roll_level(
						Data.level_curve.get("roll", {}),
						Growth.tier_growth(ldef, Data.stat_table), lr, 0.0, ""))
				UserDB.set_dragon_field(uid, "awakened", true)
				UserDB.set_dragon_field(uid, "awaken_skill", Data.awaken_skill_of(did))
				cids.append(uid)
				var dd := Data.get_dragon(did)
				print("SHOT %s id=%d art_id=%s 스파인=%s 각성스킬=%d" % [
					String(dd.get("name", "")), did, str(dd.get("art_id", did)),
					str(dd.get("stages", {})), Data.awaken_skill_of(did)])
				print("SHOT   씬 존재=%s  초상 존재=%s" % [
					ResourceLoader.exists("res://scenes/dragons/dragon_%d_adult.tscn" % did),
					ResourceLoader.exists("res://assets/converted/portrait_%d/dragon_dragon_%d_box_adult.tres" % [did, did])])
			print("SHOT 지급 uid=", cids)
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0, "party_uids": cids})
			for i in 40: await get_tree().process_frame
			var cb := _find_method_node(get_tree().root, "_apply_awaken_skills")
			if cb != null:
				print("SHOT awaken_fired=", cb.get("_awaken_fired"))
				for pv in (cb.get("_party") as Array):
					var pd := pv as Dictionary
					print("SHOT  %s  hp_max=%d  효과 %d건" % [String(pd.get("name", "")),
						int(pd.get("hp_max", 0)), (pd.get("awaken_effects", []) as Array).size()])
		"awaken":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			UserDB.begin_batch()
			var awk: Array = []
			for d in UserDB.dragons():
				var no := Data.awaken_skill_of(int(d["id"]))
				if no <= 0: continue
				UserDB.set_dragon_field(int(d["uid"]), "awakened", true)
				UserDB.set_dragon_field(int(d["uid"]), "awaken_skill", no)
				awk.append(int(d["uid"]))
				if awk.size() >= 3: break
			print("SHOT awaken 대상 uid=", awk)
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0, "party_uids": awk})
			for i in 40: await get_tree().process_frame
			var bsc := _find_method_node(get_tree().root, "_apply_awaken_skills")
			if bsc == null:
				print("SHOT battle 씬을 못 찾음")
			else:
				print("SHOT awaken_fired=", bsc.get("_awaken_fired"))
				for pv in (bsc.get("_party") as Array):
					var pd := pv as Dictionary
					print("SHOT  %s  awaken_no=%d  hp_max=%d  효과 %d건" % [
						String(pd.get("name", "")), int(pd.get("awaken_skill", 0)),
						int(pd.get("hp_max", 0)), (pd.get("awaken_effects", []) as Array).size()])
		"eggup":
			UserDB.begin_batch()
			for pair in [["mall_back_egg", 3], ["stone_spirit2", 30], ["stone_heart2", 30],
					["crystal_light", 30], ["stone_spirit1", 40], ["stone_heart1", 40]]:
				UserDB.add_item(String(pair[0]), int(pair[1]))
			if stage == "run":
				Scenes.goto("laboratory")
				for i in 30: await get_tree().process_frame
				var rl := _find_method_node(get_tree().root, "_upgrade_egg")
				if rl == null:
					print("SHOT: _upgrade_egg 노드 없음")
				else:
					rl.set("_sel_egg_up", "mall_back_egg")
					rl.call("_open_feature", 0)
					for i in 5: await get_tree().process_frame
					var g0 := UserDB.gold()
					rl.call("_upgrade_egg")
					print("SHOT eggup: 1강=", UserDB.item_count("mall_back_egg#1"),
						" 0강=", UserDB.item_count("mall_back_egg"),
						" 정령석=", UserDB.item_count("stone_spirit2"),
						" 골드차=", g0 - UserDB.gold())
					rl.call("_upgrade_egg")
					print("SHOT eggup2: 2강=", UserDB.item_count("mall_back_egg#2"),
						" 완벽한정령석=", UserDB.item_count("stone_spirit3"))
					Scenes.goto("worldmap", {"region": "yutakan"})
					for i in 20: await get_tree().process_frame
					Scenes.goto("cave")
					for i in 30: await get_tree().process_frame
					var hc := _find_method_node(get_tree().root, "_start_hatch")
					if hc == null:
						print("SHOT: _start_hatch 노드 없음")
					else:
						hc.call("_start_hatch", "mall_back_egg#2")
						for i in 5: await get_tree().process_frame
						var eg := {}
						for d in UserDB.dragons():
							if UserDB.is_egg(d): eg = d
						print("SHOT hatch: egg_grade=", eg.get("egg_grade"),
							" enhance=", eg.get("egg_enhance"),
							" 남은2강=", UserDB.item_count("mall_back_egg#2"))
			elif stage == "smelt":
				Scenes.goto("cave")
				for i in 30: await get_tree().process_frame
				var sm := _find_method_node(get_tree().root, "_open_inventory")
				if sm == null:
					print("SHOT: _open_inventory 노드 없음")
				else:
					sm.call("_open_inventory")
					for i in 10: await get_tree().process_frame
					sm.call("_inventory_select", "stone_spirit1")
					for i in 5: await get_tree().process_frame
					sm.call("_open_smelt", "stone_spirit1")
			else:
				UserDB.add_item("mall_back_egg#1", 1)
				Scenes.goto("laboratory")
				for i in 30: await get_tree().process_frame
				var lb := _find_method_node(get_tree().root, "_open_feature")
				if lb == null:
					print("SHOT: _open_feature 노드 없음")
				else:
					if stage == "select":
						lb.call("_open_feature", 0)
						for i in 10: await get_tree().process_frame
						lb.call("_open_egg_select", func(_k): pass, true)
					else:
						if stage != "empty":
							lb.set("_sel_egg_up", "mall_back_egg#1")
						lb.call("_open_feature", 0)
		"inven_use":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var uk: String = stage if stage != "1" else "energy_drink"
			UserDB.add_item(uk, 3)
			var ivu := _find_method_node(get_tree().root, "_open_inventory")
			if ivu != null:
				ivu.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				ivu.call("_inventory_select", uk)
			else: print("SHOT: _open_inventory 노드 없음")
		"skillscroll":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			UserDB.add_item("scroll_gold", 3)
			UserDB.add_item("s_skillbook3", 3)
			UserDB.add_item(Loadout.item_key(11, 3), 2)
			UserDB.add_item(Loadout.item_key(12, 5), 1)
			var ss := _find_method_node(get_tree().root, "_open_inventory")
			if ss == null:
				print("SHOT: _open_inventory 노드 없음")
			else:
				match stage:
					"book":
						ss.set("_inv_tab", "doc")
						ss.call("_open_inventory")
						for i in 10: await get_tree().process_frame
						ss.call("_inventory_select", "s_skillbook3")
						for i in 5: await get_tree().process_frame
						ss.call("_use_skill_scroll", "s_skillbook3")
					"item":
						ss.set("_inv_tab", "skill")
						ss.call("_open_inventory")
						for i in 10: await get_tree().process_frame
						ss.call("_inventory_select", Loadout.item_key(11, 3))
					"equip":
						var su := UserDB.active_uid()
						var sp: Array = UserDB.dragon_skills(su)
						for pair in [[11, 3], [12, 5], [13, 1]]:
							for lv in range(1, int(pair[1]) + 1):
								sp = Loadout.learn_from_item(sp, int(pair[0]), lv, Data.skills)["skills"]
						UserDB.set_dragon_skills(su, sp)
						ss.call("_open_skill_select", 0)
					_:
						ss.set("_inv_tab", "doc")
						ss.call("_open_inventory")
						for i in 10: await get_tree().process_frame
						ss.call("_inventory_select", "scroll_gold")
						for i in 5: await get_tree().process_frame
						ss.call("_use_skill_scroll", "scroll_gold")
		"inven_m":
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			for k in ["mall_back_egg", "mall_black_egg", "mall_darkpoll_egg",
					"mall_bagma_egg", "mall_chaos_egg"]:
				UserDB.add_item(k, 1)
			UserDB.mark_dex_master(54)
			UserDB.mark_dex_master(175)
			var im := _find_method_node(get_tree().root, "_open_inventory")
			if im != null:
				im.set("_inv_tab", "egg")
				im.call("_open_inventory")
			else: print("SHOT: _open_inventory 노드 없음")
		"eggopen":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var ek: String = stage if stage != "1" else "mall_question_egg2"
			UserDB.add_item(ek, 5)
			var iv2 := _find_method_node(get_tree().root, "_open_inventory")
			if iv2 != null:
				iv2.set("_inv_tab", "egg")
				iv2.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				iv2.call("_inventory_select", ek)
				for i in 5: await get_tree().process_frame
				iv2.call("_open_gacha_egg", ek)
			else: print("SHOT: _open_inventory 노드 없음")
		"blackisland":
			var bi_n := clampi(int(stage), 1, 3)
			var bi_hero := false
			for a in OS.get_cmdline_user_args():
				if a == "--stage2=hero": bi_hero = true
			var bi_party: Array = []
			for d in UserDB.dragons():
				if UserDB.is_egg(d): continue
				bi_party.append(int(d["uid"]))
				if bi_party.size() >= bi_n: break
			Scenes.goto("battle", {"stage": "24", "region": "uno", "enc": 0,
				"hp_state": {}, "streak": 0, "party_uids": bi_party, "hero": bi_hero})
			for i in 40: await get_tree().process_frame
			var bsc := _find_method_node(get_tree().root, "_apply_party_count_scaling")
			if bsc != null:
				var en = bsc.get("_enemy")
				print("SHOT blackisland n=%d hero=%s → %s" % [bi_party.size(), str(bi_hero), str(en)])
			else: print("SHOT: battle 노드 없음")
		"rename":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var rn := _find_method_node(get_tree().root, "_rename_gate")
			if rn != null:
				if OS.get_cmdline_user_args().has("--stage2=have"):
					UserDB.add_item("dragon_namechange", 2)
				else:
					UserDB.use_item("dragon_namechange",
						UserDB.item_count("dragon_namechange"))
				rn.call("_rename_gate")
			else: print("SHOT: _rename_gate 노드 없음")
		"eggreveal":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			var rv := _find_method_node(get_tree().root, "_show_egg_result")
			if rv != null:
				rv.call("_show_egg_result", int(stage) if int(stage) > 0 else 1, "mall_question_egg2")
			else: print("SHOT: _show_egg_result 노드 없음")
		"eggopen10":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var tk: String = stage if stage != "1" else "mall_question_egg2"
			UserDB.add_item(tk, 12)
			var go10 := false
			for a in OS.get_cmdline_user_args():
				if a == "--stage2=go": go10 = true
			var iv3 := _find_method_node(get_tree().root, "_open_inventory")
			if iv3 != null:
				iv3.set("_inv_tab", "egg" if tk.ends_with("egg") or tk.ends_with("egg2") else "item")
				iv3.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				iv3.call("_inventory_select", tk)
				for i in 5: await get_tree().process_frame
				if go10:
					iv3.call("_use_batch", tk, iv3.call("_batch_use_kind", tk, Data.get_item(tk)), 10)
					for i in 5: await get_tree().process_frame
					var okb := _find_button_text(get_tree().root, "확인")
					if okb != null: okb.emit_signal("pressed")
					else: print("SHOT: 확인 버튼 없음")
					for i in 20: await get_tree().process_frame
			else: print("SHOT: _open_inventory 노드 없음")
		"gemequip":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var ge_uid := UserDB.active_uid()
			var ge_pre = {"name": "공격의 젬", "tier": 1}
			UserDB.set_dragon_field(ge_uid, "gems", {"types": ["ATT", "ATT", "ATT"],
				"slots": [ge_pre, ge_pre, ge_pre] if stage == "full" else [null, null, null]})
			var ge_fit := "gem:공격의 젬:3"
			var ge_miss := "gem:체력의 젬:0"
			UserDB.add_item(ge_fit, 2)
			UserDB.add_item(ge_miss, 2)
			var ge_key: String = ge_miss if stage == "miss" else ge_fit
			var ge := _find_method_node(get_tree().root, "_open_inventory")
			if ge == null:
				print("SHOT: _open_inventory 노드 없음")
			else:
				ge.set("_inv_tab", "gem")
				ge.call("_open_inventory")
				for i in 15: await get_tree().process_frame
				ge.call("_inventory_select", ge_key)
				for i in 10: await get_tree().process_frame
				var ge_btn := _find_label_button(get_tree().root, "장착")
				print("SHOT gemequip key=", ge_key, " 장착버튼=", ge_btn != null,
					" 보유=", UserDB.item_count(ge_key))
				if ge_btn == null:
					print("SHOT gemequip FAIL: '장착' 버튼 없음")
				else:
					ge_btn.emit_signal("pressed")
					for i in 30: await get_tree().process_frame
					var ge_names: Array = []
					for e in Gem.entries(UserDB.get_dragon(ge_uid).get("gems", {})):
						ge_names.append("(빈칸)" if e == null else String(e["name"]))
					print("SHOT gemequip 칸=", ge_names,
						" 남은보유=", UserDB.item_count(ge_key),
						" 젬목록재개=", _find_label_button(get_tree().root, "젬 장착") != null,
						" 안내모달확인=", _find_button_text(get_tree().root, "확인") != null,
						" 취소버튼=", _find_button_text(get_tree().root, "취소") != null)
		"inven_gem", "inven_gear", "gemsel", "eqsel":
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			for k in ["gem:체력의 젬:0", "gem:공격의 젬:3", "gem:방어의 젬:18",
					"gem:체공젬:7", "gem:샌즈의 젬:12", "gem:공격의 소울젬:2",
					"equip:basic:깃털:6", "equip:basic:발톱:0", "equip:basic:부적:5",
					"equip:basic:묘안석:2", "equip:basic:흑요석:4", "equip:basic:백금석:1",
					"equip:artifact:루멘:5", "equip:event:눈사람 인형"]:
				UserDB.add_item(k, 2)
			match shot:
				"inven_gem", "inven_gear":
					Scenes.goto("cave")
					for i in 30: await get_tree().process_frame
					var iw := _find_method_node(get_tree().root, "_open_inventory")
					if iw == null:
						print("SHOT: _open_inventory 노드 없음")
					else:
						iw.set("_inv_tab", "gem" if shot == "inven_gem" else "gear")
						iw.call("_open_inventory")
						for i in 20: await get_tree().process_frame
						if shot == "inven_gear":
							var gk := "equip:basic:묘안석:2"
							iw.call("_inventory_select", gk)
							for i in 15: await get_tree().process_frame
							print("SHOT inven_gear 강화=",
								_find_button_text(get_tree().root, "강화") != null,
								" 옵션변경=", _find_button_text(get_tree().root, "옵션 변경") != null,
								" 장착=", _find_button_text(get_tree().root, "장착") != null)
				"gemsel":
					Scenes.goto("cave")
					for i in 30: await get_tree().process_frame
					var gcv := _find_method_node(get_tree().root, "_open_gem_tab")
					if gcv == null:
						print("SHOT: _open_gem_tab 노드 없음")
					else:
						var guid := UserDB.active_uid()
						UserDB.set_dragon_field(guid, "gems",
							{"types": ["ATT", "DEF", "HP"], "slots": [null, null, null]})
						gcv.call("_refresh")
						for i in 10: await get_tree().process_frame
						var ghit := _find_button_tooltip_prefix(get_tree().root, "1번 칸")
						print("SHOT gemsel 빈칸히트=", ghit != null,
							" tip=", ghit.tooltip_text.replace("
", " / ") if ghit != null else "-")
						if ghit != null:
							ghit.emit_signal("pressed")
							for i in 15: await get_tree().process_frame
							print("SHOT gemsel 열린탭=", gcv.get("_inv_tab"),
								" 가방열림=", _find_label_button(get_tree().root, "장착") != null,
								" 자작팝업=", gcv.has_method("_open_gem_select"))
				"eqsel":
					Scenes.goto("cave")
					for i in 30: await get_tree().process_frame
					var es := _find_method_node(get_tree().root, "_open_item_popup")
					if es == null:
						print("SHOT: _open_item_popup 노드 없음")
					else:
						es.call("_open_item_popup", "all")
						for i in 20: await get_tree().process_frame
						print("SHOT eqsel 장착버튼=",
							_find_label_button(get_tree().root, "장착") != null,
							" 강화버튼=", _find_label_button(get_tree().root, "강화") != null)
		"bless":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			UserDB.add_item("bless_of_amor", 3)
			var cv3 := _find_method_node(get_tree().root, "_open_inventory")
			if cv3 == null:
				print("SHOT bless FAIL: _open_inventory 노드 없음")
			else:
				cv3.set("_inv_tab", "etc")
				cv3.call("_open_inventory")
				for i in 20: await get_tree().process_frame
				cv3.call("_inventory_select", "bless_of_amor")
				for i in 20: await get_tree().process_frame
				var ub := _find_label_button(get_tree().root, "사용")
				var lv0 := int(UserDB.get_dragon(UserDB.active_uid()).get("level", 0))
				print("SHOT bless use_button=", ub != null, " lv_before=", lv0,
					" count=", UserDB.item_count("bless_of_amor"))
				if ub == null:
					print("SHOT bless FAIL: '사용' 버튼 없음")
				else:
					ub.emit_signal("pressed")
					for i in 40: await get_tree().process_frame
					print("SHOT bless after lv=",
						int(UserDB.get_dragon(UserDB.active_uid()).get("level", 0)),
						" count=", UserDB.item_count("bless_of_amor"))
		"bless10":
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			var bk10: String = stage if stage != "1" else "bless_of_amor"
			UserDB.add_item(bk10, 9 if extra == "few" else 12)
			var bgo := false
			for a in OS.get_cmdline_user_args():
				if a == "--stage2=go": bgo = true
			if extra == "cap":
				var cuid := UserDB.active_uid()
				var ccap := Growth.level_cap(bool(UserDB.get_dragon(cuid).get("awakened", false)))
				while int(UserDB.get_dragon(cuid).get("level", 1)) < ccap - 3:
					UserDB.level_up_with(cuid, {"hp": 0, "att": 0, "def": 0})
			var bv := _find_method_node(get_tree().root, "_open_inventory")
			if bv == null:
				print("SHOT: _open_inventory 노드 없음")
			else:
				bv.set("_inv_tab", "etc")
				bv.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				bv.call("_inventory_select", bk10)
				for i in 10: await get_tree().process_frame
				var b10 := _find_label_button(get_tree().root, "10회 사용")
				var buid := UserDB.active_uid()
				print("SHOT bless10 button=", b10 != null,
					" lv_before=", int(UserDB.get_dragon(buid).get("level", 0)),
					" count=", UserDB.item_count(bk10))
				if b10 == null:
					print("SHOT bless10 OK: 9개라 버튼 없음" if extra == "few"
						else "SHOT bless10 FAIL: '10회 사용' 버튼 없음")
				elif bgo:
					b10.emit_signal("pressed")
					for i in 10: await get_tree().process_frame
					var bok := _find_button_text(get_tree().root, "확인")
					if bok == null:
						print("SHOT bless10 FAIL: 확인 버튼 없음")
					else:
						bok.emit_signal("pressed")
						for i in 40: await get_tree().process_frame
						print("SHOT bless10 after lv=",
							int(UserDB.get_dragon(UserDB.active_uid()).get("level", 0)),
							" count=", UserDB.item_count(bk10))
		"storage":
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			UserDB.add_item("bridle", 2)
			var n_before := UserDB.dragon_count()
			var cv4 := _find_method_node(get_tree().root, "_use_consumable")
			cv4.call("_use_consumable", "bridle", "bridle")
			for i in 20: await get_tree().process_frame
			var f2: BaseButton = null
			var st2: Array = [get_tree().root]
			while not st2.is_empty() and f2 == null:
				var n2: Node = st2.pop_front()
				if n2 is Button and (n2 as Button).text.begins_with("Lv."): f2 = n2
				for c in n2.get_children(): st2.append(c)
			if f2 != null: f2.emit_signal("pressed")
			for i in 30: await get_tree().process_frame
			print("SHOT storage dragons ", n_before, "->", UserDB.dragon_count(),
				" stored=", UserDB.storage_dragons().size(),
				" bridle=", UserDB.item_count("bridle"))
			var cv5 := _find_method_node(get_tree().root, "_open_dragon_storage")
			if cv5 != null: cv5.call("_open_dragon_storage")
			else: print("SHOT: _open_dragon_storage 노드 없음")
		"ascend":
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			UserDB.add_item("ascension", 2)
			var n0 := UserDB.dragon_count()
			var dia0 := UserDB.diamond()
			var cv6 := _find_method_node(get_tree().root, "_use_consumable")
			cv6.call("_use_consumable", "ascension", "ascension")
			for i in 20: await get_tree().process_frame
			var f3: BaseButton = null
			var st3: Array = [get_tree().root]
			while not st3.is_empty() and f3 == null:
				var n3: Node = st3.pop_front()
				if n3 is Button and (n3 as Button).text.begins_with("Lv."): f3 = n3
				for c in n3.get_children(): st3.append(c)
			print("SHOT ascend label=", f3.text if f3 != null else "(없음)")
			if f3 != null: f3.emit_signal("pressed")
			for i in 40: await get_tree().process_frame
			print("SHOT ascend dragons ", n0, "->", UserDB.dragon_count(),
				" diamond ", dia0, "->", UserDB.diamond(),
				" item=", UserDB.item_count("ascension"))
		"partycancel":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
			var wmc := _find_method_node(get_tree().root, "_open_dungeon_popup")
			wmc.set("_busy", true)
			wmc.call("_open_dungeon_popup", stage)
			for i in 20: await get_tree().process_frame
			_press_label_button(get_tree().root, "일반")
			for i in 20: await get_tree().process_frame
			print("SHOT party_overlay_open=", _find_label_button(get_tree().root, "취소") != null)
			_press_label_button(get_tree().root, "취소")
			for i in 40: await get_tree().process_frame
			print("SHOT busy=", wmc.get("_busy"),
				" party_left=", _find_label_button(get_tree().root, "취소") != null,
				" popup_left=", _find_label_button(get_tree().root, "일반") != null,
				" scale=", wmc.get("_content").scale)
		"partydim":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
			var wmd := _find_method_node(get_tree().root, "_open_dungeon_popup")
			wmd.set("_busy", true)
			wmd.call("_open_dungeon_popup", stage)
			for i in 20: await get_tree().process_frame
			_click_at(Vector2(30, 30))
			for i in 40: await get_tree().process_frame
			print("SHOT popup_outside_click busy=", wmd.get("_busy"),
				" popup_left=", _find_label_button(get_tree().root, "일반") != null,
				" scale=", wmd.get("_content").scale)
			wmd.set("_busy", true)
			wmd.call("_open_dungeon_popup", stage)
			for i in 20: await get_tree().process_frame
			_press_label_button(get_tree().root, "일반")
			for i in 20: await get_tree().process_frame
			_click_at(Vector2(30, 30))
			for i in 40: await get_tree().process_frame
			print("SHOT party_outside_click busy=", wmd.get("_busy"),
				" party_left=", _find_label_button(get_tree().root, "취소") != null,
				" scale=", wmd.get("_content").scale)
		"dpopup":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 40: await get_tree().process_frame
			var wm := _find_method_node(get_tree().root, "_open_dungeon_popup")
			if wm != null: wm.call("_open_dungeon_popup", stage)
			else: print("SHOT: _open_dungeon_popup 노드 없음")
		"dpopupdrag":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 40: await get_tree().process_frame
			var wmp := _find_method_node(get_tree().root, "_open_dungeon_popup")
			if wmp == null:
				print("SHOT: _open_dungeon_popup 노드 없음")
			else:
				wmp.call("_open_dungeon_popup", stage)
				for i in 25: await get_tree().process_frame
				var slot_list: Array = [0]
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--slot="):
						slot_list = Array(a.substr(7).split(",")).map(func(x): return int(x))
				var hits: Array = []
				var q: Array = [get_tree().root]
				while not q.is_empty():
					var n: Node = q.pop_front()
					for c in n.get_children(): q.append(c)
					if n is CanvasLayer and (n as CanvasLayer).layer == 26:
						for c in n.get_children():
							if c is Button and (c as Button).flat \
									and absf((c as Button).size.x - (c as Button).size.y) < 20.0:
								hits.append(c)
				print("SHOT dpopupdrag slot_hits=", hits.size())
				for si in slot_list:
					if int(si) < hits.size():
						(hits[int(si)] as Button).emit_signal("pressed")
						await get_tree().create_timer(0.5).timeout
					else: print("SHOT: 슬롯 없음 idx=", si)
		"impshop":
			UserDB.begin_batch()
			for jk in ["jewel_amethyst", "jewel_emerald", "jewel_ruby", "jewel_sapphire"]:
				UserDB.add_item(jk, 60)
			Scenes.goto("worldmap", {"region": "yutakan", "night": true})
			for i in 30: await get_tree().process_frame
			var wm := _find_method_node(get_tree().root, "_open_imp_shop")
			if wm != null:
				var only_map := false
				for a3 in OS.get_cmdline_user_args():
					if a3 == "--map=1": only_map = true
				if not only_map:
					wm.call("_open_imp_shop")
			else:
				print("SHOT: _open_imp_shop 노드 없음")
		"lvpanel":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var cv2 := _find_method_node(get_tree().root, "_open_levelup")
			if cv2 != null: cv2.call("_open_levelup")
			else: print("SHOT: _open_levelup 노드 없음")
		"awakenevol":
			UserDB.begin_batch()
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var aw_uid := UserDB.active_uid()
			UserDB.set_dragon_field(aw_uid, "awakened", false)
			var aw_cv := get_tree().current_scene
			var aw_vis := get_viewport().get_visible_rect().size
			AwakenSequence.open(aw_cv, aw_uid, Vector2(aw_vis.x * 0.5, aw_vis.y * 0.5), Callable())
			var aw_d: Dictionary = UserDB.get_dragon(aw_uid)
			print("SHOT awaken: uid=", aw_uid, " id=", aw_d.get("id"), " lv=", aw_d.get("level"),
				"  각성체씬=", ResourceLoader.exists("res://scenes/dragons/dragon_%d_e.tscn" % int(aw_d.get("id", 0))))
		"lvevolve":
			UserDB.begin_batch()
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var ev_cv := _find_method_node(get_tree().root, "_open_levelup")
			if ev_cv == null:
				print("SHOT: _open_levelup 노드 없음")
			else:
				var ev_uid := UserDB.active_uid()
				var ev_d: Dictionary = UserDB.get_dragon(ev_uid)
				while int(UserDB.get_dragon(ev_uid).get("level", 1)) > 9:
					UserDB.level_down(ev_uid)
				while int(UserDB.get_dragon(ev_uid).get("level", 1)) < 9:
					UserDB.level_up_with(ev_uid, {"hp": 3, "att": 1, "def": 1})
				UserDB.add_item("level_up", 1)
				ev_cv.call("_open_levelup")
				for i in 20: await get_tree().process_frame
				var ev_before := _spine_scene_of(ev_cv.get("_lvup_dragon_holder"))
				var ev_btn := _find_button_tooltip_prefix(get_tree().root, Data.item_name("level_up"))
				if ev_btn == null:
					print("SHOT lvevolve: level_up 슬롯 버튼 없음")
				else:
					var ec := ev_btn as Control
					_click_at(get_viewport().get_screen_transform() * ec.get_global_rect().get_center())
					for i in 25: await get_tree().process_frame
					var ev_lv := int(UserDB.get_dragon(ev_uid).get("level", 0))
					var ev_after := _spine_scene_of(ev_cv.get("_lvup_dragon_holder"))
					var ev_cave := _spine_scene_of(ev_cv.get("_stage"))
					print("SHOT lvevolve: 레벨 9->", ev_lv,
						"  화면드래곤 ", ev_before, " -> ", ev_after,
						"  동굴받침대 ", ev_cave,
						"  즉시반영=", ev_before != ev_after and ev_after.ends_with("child"))
		"lvitem":
			for i in 30: await get_tree().process_frame
			var li_cv := _find_method_node(get_tree().root, "_open_levelup")
			if li_cv == null:
				print("SHOT: _open_levelup 노드 없음")
			else:
				li_cv.call("_open_levelup")
				for i in 20: await get_tree().process_frame
				var li_uid := UserDB.active_uid()
				var li_lv := int(UserDB.get_dragon(li_uid).get("level", 0))
				var li_key := ""
				for k in ["level_up", "bless_of_dragon", "bless_of_maia", "bless_of_dersa", "bless_of_amor"]:
					if UserDB.item_count(k) > 0: li_key = k; break
				var li_cnt := UserDB.item_count(li_key) if li_key != "" else 0
				var li_btn := _find_button_tooltip_prefix(get_tree().root, Data.item_name(li_key)) if li_key != "" else null
				if li_btn == null:
					print("SHOT lvitem: 슬롯 버튼 없음 (보유 레벨아이템 없음)")
				else:
					var lc := li_btn as Control
					var lscr := get_viewport().get_screen_transform() * lc.get_global_rect().get_center()
					_click_at(lscr)
					for i in 25: await get_tree().process_frame
					var li_lv2 := int(UserDB.get_dragon(li_uid).get("level", 0))
					var ltx: Array = []
					_collect_labels(get_tree().root, "레벨", ltx)
					print("SHOT lvitem: 레벨 ", li_lv, "->", li_lv2, "  아이템 ", li_cnt, "->",
						UserDB.item_count("level_up"), "  갱신됨=", li_lv2 == li_lv + 1)
		"lvtriple":
			UserDB.begin_batch()
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var tp_cv := _find_method_node(get_tree().root, "_open_levelup")
			if tp_cv == null:
				print("SHOT: _open_levelup 노드 없음")
			else:
				var tp_uid := UserDB.active_uid()
				var tp_want := int({"baby": 5, "child": 15, "adult": 30}.get(stage, 0))
				if tp_want > 0:
					while int(UserDB.get_dragon(tp_uid).get("level", 1)) > tp_want:
						UserDB.level_down(tp_uid)
					while int(UserDB.get_dragon(tp_uid).get("level", 1)) < tp_want:
						UserDB.level_up_with(tp_uid, {"hp": 3, "att": 1, "def": 1})
				if UserDB.item_count("bless_of_dersa") <= 0:
					UserDB.add_item("bless_of_dersa", 3)
				tp_cv.call("_open_levelup")
				for i in 20: await get_tree().process_frame
				var tp_btn := _find_button_tooltip_prefix(get_tree().root, Data.item_name("bless_of_dersa"))
				if tp_btn == null:
					print("SHOT lvtriple: 데르사 슬롯 없음 (보유=", UserDB.item_count("bless_of_dersa"), ")")
				else:
					var tc := tp_btn as Control
					_click_at(get_viewport().get_screen_transform() * tc.get_global_rect().get_center())
					var tp_t := 0.0
					var tt: Array = []
					while tp_t < 25.0:
						tt.clear()
						_collect_labels(get_tree().root, "트리플", tt)
						if not tt.is_empty(): break
						await get_tree().process_frame
						tp_t += get_process_delta_time()
					var tp_d: Dictionary = UserDB.get_dragon(tp_uid)
					print("SHOT lvtriple: stage=",
						Growth.stage_for_level(int(tp_d.get("level", 1))),
						"  레벨=", tp_d.get("level"), "  id=", tp_d.get("id"),
						"  컷인문구=", tt, "  등장t=%.1fs" % tp_t)
		"lvreroll":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var rr_cv := _find_method_node(get_tree().root, "_open_levelup")
			if rr_cv == null:
				print("SHOT: _open_levelup 노드 없음")
			else:
				rr_cv.call("_open_levelup")
				for i in 20: await get_tree().process_frame
				var rr_uid := UserDB.active_uid()
				var rr_before: Array = (UserDB.get_dragon(rr_uid).get("gain_log", []) as Array).duplicate(true)
				var rr_dia := UserDB.diamond()
				var rr_btn := get_tree().root.find_child("RerollButton", true, false) as Button
				if rr_btn == null:
					print("SHOT reroll: 버튼 자체를 못 찾음")
				else:
					var rc := rr_btn as Control
					var canvas_c := rc.get_global_rect().get_center()
					var scr := get_viewport().get_screen_transform() * canvas_c
					print("SHOT reroll: canvas=", rc.get_global_rect(), " click(screen)=", scr,
						" disabled=", rr_btn.disabled, " visible=", rc.is_visible_in_tree())
					var mm := InputEventMouseMotion.new()
					mm.position = scr; mm.global_position = scr
					Input.parse_input_event(mm)
					for i in 3: await get_tree().process_frame
					var hov := get_viewport().gui_get_hovered_control()
					print("SHOT reroll: hovered=", hov.get_path() if hov else "<없음>",
						" class=", hov.get_class() if hov else "-",
						" filter=", hov.mouse_filter if hov else -1)
					_click_at(scr)
					for i in 20: await get_tree().process_frame
					print("SHOT reroll: 확인창 떴나 = ", _find_label_button(get_tree().root, "확인") != null)
					_press_label_button(get_tree().root, "확인")
					for i in 20: await get_tree().process_frame
					var rr_after: Array = UserDB.get_dragon(rr_uid).get("gain_log", [])
					print("SHOT reroll: gain_log last  before=",
						rr_before[rr_before.size() - 1] if not rr_before.is_empty() else "{}",
						"  after=", rr_after[rr_after.size() - 1] if not rr_after.is_empty() else "{}")
					print("SHOT reroll: 클릭으로 롤이 바뀌었나 = ", rr_before != rr_after,
						" / dia ", rr_dia, "->", UserDB.diamond(), " gold=", UserDB.gold())
					var texts: Array = []
					_collect_labels(get_tree().root, "(+", texts)
					print("SHOT reroll: 화면 증가분 라벨 = ", texts)
		"lvup":
			for i in 30: await get_tree().process_frame
			var cv := _find_method_node(get_tree().root, "_open_training_result")
			if cv != null:
				cv.call("_open_training_result", 1, 10, 11)
			else:
				print("SHOT: _open_training_result 노드 없음")
		"promote_select":
			Scenes.goto("cave", {})
			for i in 10: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("promote", {"tab": "train", "from": "town"})
			for i in 30: await get_tree().process_frame
			var ps := _find_method_node(get_tree().root, "_open_dragon_select")
			if ps != null: ps.call("_open_dragon_select", 1)
			else: print("SHOT: _open_dragon_select 노드 없음")
		"promote_train":
			Scenes.goto("cave", {})
			for i in 10: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("promote", {"tab": "train", "from": "town"})
			for i in 30: await get_tree().process_frame
			var pt := _find_method_node(get_tree().root, "_open_dragon_select")
			if pt != null:
				pt.call("_open_dragon_select", 1)
				for i in 10: await get_tree().process_frame
				for b in _all_buttons(get_tree().root):
					if b.size.x > 300.0 and b.size.y > 300.0:
						b.emit_signal("pressed"); break
			else: print("SHOT: _open_dragon_select 노드 없음")
		"mission":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			var mt := 1
			var mep := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--tab="): mt = int(a.substr(6))
				elif a.begins_with("--ep="): mep = int(a.substr(5))
			var ml := MissionBoard.open(get_tree().current_scene, mt, "worldmap", {})
			if mep > 0:
				ml.set("_story_sel", mep)
				ml.call("_rebuild", mt)
			for i in 10: await get_tree().process_frame
		"storymark":
			UserDB.begin_batch()
			for n in range(1, 79): UserDB.set_progress("scenario_%d_0" % n, true)
			UserDB.set_progress("story_sq_79", 0)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 25: await get_tree().process_frame
			print("SHOT storymark: active=", StoryProgress.active_episode(),
				" spec=", StoryProgress.spec(StoryProgress.active_episode()),
				" mark_field=", StoryProgress.mark_field())
		"prologue":
			Scenes.goto("prologue", {"back": "worldmap"})
			for i in 25: await get_tree().process_frame
			var pl_line := -1
			for a8 in OS.get_cmdline_user_args():
				if a8.begins_with("--line="): pl_line = int(a8.substr(7))
			if pl_line >= 0:
				var pn := _find_method_node(get_tree().root, "_show_line")
				if pn != null:
					pn.call("_show_line", pl_line)
					for i in 5: await get_tree().process_frame
			print("SHOT prologue: 대사 ", Data.prologue_lines().size(), "줄 화자표 ",
				Data.tutorial_flow.get("speakers", {}).keys())
		"storyauto":
			UserDB.begin_batch()
			for n in range(1, 79): UserDB.set_progress("scenario_%d_0" % n, true)
			UserDB.set_progress("story_sq_79", 99)
			Scenes.goto("worldmap", {})
			for i in 30: await get_tree().process_frame
			var sa := get_tree().root.get_node_or_null("Main")
			var cur := "?"
			if sa != null and sa.get_child_count() > 0:
				cur = sa.get_child(sa.get_child_count() - 1).name
			print("SHOT storyauto: 다음회차=", StoryProgress.next_episode(),
				" 해금=", StoryProgress.unlocked(StoryProgress.next_episode()),
				" 현재씬=", cur)
			if OS.get_cmdline_user_args().has("--skip=1"):
				var sk := _find_method_node(get_tree().root, "_confirm_skip")
				if sk == null:
					print("SHOT storyauto: story 씬 없음")
				else:
					sk.call("_confirm_skip")
					for i in 15: await get_tree().process_frame
		"storyreward":
			var rep := 78
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--ep="): rep = int(a.substr(5))
			UserDB.begin_batch()
			UserDB.set_progress("story_reward_%d" % rep, false)
			Scenes.goto("story", {"no": rep, "part": 0, "back": "worldmap", "back_params": {}})
			for i in 20: await get_tree().process_frame
			var sv := _find_method_node(get_tree().root, "_show_special_reward")
			if sv != null: sv.call("_finish")
			else: print("SHOT: story 노드 없음")
			for i in 20: await get_tree().process_frame
		"sound":
			for rid in ["yutakan", "elf", "dwarf"]:
				Scenes.goto("worldmap", {"region": rid})
				for i in 20: await get_tree().process_frame
				var wm := get_tree().current_scene
				for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
					if wm and wm.get("_max_scroll") != null:
						wm.set("_scroll", float(wm.get("_max_scroll")) * f)
						wm.call("_apply_scroll")
					await get_tree().process_frame
					print("SOUND %-8s scroll=%.2f → %s" % [rid, f, _area_state()])
			for dest in ["town", "shop", "cave"]:
				if dest == "town": Scenes.goto("town", {"area": "elpis"})
				else: Scenes.goto(dest, {"from": "town"})
				for i in 10: await get_tree().process_frame
				print("SOUND %-8s → %s" % [dest, _area_state()])
		"promote", "promote_mate", "promote_nest", "promote_latea":
			Scenes.goto("cave", {})
			for i in 10: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			var ptab: String = {"promote": "train", "promote_mate": "mate",
				"promote_nest": "nest", "promote_latea": "latea"}[shot]
			if ptab == "mate":
				Data.promote["breed_enable"] = 1
			Scenes.goto("promote", {"tab": ptab, "from": "town"})
			if ptab == "mate":
				for i in 20: await get_tree().process_frame
				if not OS.get_cmdline_user_args().has("--pick=0"):
					var pm := _find_method_node(get_tree().root, "_build_mate")
					var pool := UserDB.dragons()
					if pm != null and pool.size() >= 2:
						pm.set("_mate_pick", {0: int(pool[0]["uid"]), 1: int(pool[1]["uid"])})
						pm.call("_rebuild")
		"magicshop", "laboratory", "shop", "mamorudiclab":
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			Scenes.goto(shot, {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			var sc := _find_method_node(get_tree().root, "_open_feature")
			if sc == null:
				print("SHOT: _open_feature 노드 없음")
			else:
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--floor="):
						sc.set("_floor", int(a.split("=")[1]))
						sc.call("_rebuild")
						for i in 10: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--item="):
						sc.call("_open_feature", int(a.split("=")[1]))
						for i in 20: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a == "--summonpick=1":
						sc.call("_open_summon_picker")
						for i in 20: await get_tree().process_frame
					elif a.begins_with("--summonuid="):
						sc.set("_summon_uid", int(a.split("=")[1]))
						sc.call("_refresh_feature")
						for i in 20: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--react="):
						sc.call("_say", "반응 대사(표정 %s)" % a.substr(8), int(a.substr(8)))
						for i in 20: await get_tree().process_frame
						var npr = sc.get("_npc")
						print("SHOT react: emotion=", npr.get("emotion") if npr else -1)
						if OS.get_cmdline_user_args().has("--react2=1"):
							sc.call("_say", "다음 대사")
							for i in 20: await get_tree().process_frame
							npr = sc.get("_npc")
							print("SHOT react2: emotion=", npr.get("emotion") if npr else -1)
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--face="):
						var old = sc.get("_npc")
						if old != null:
							var par: Node = old.get_parent()
							var opos = old.position
							var oz = old.z_index
							var nm: String = String(old.get("npc_name"))
							par.remove_child(old)
							old.queue_free()
							var n2 = NpcPortrait.create(nm, int(a.split("=")[1]))
							n2.position = opos
							n2.z_index = oz
							par.add_child(n2)
							sc.set("_npc", n2)
							for i in 10: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--emo="):
						var np = sc.get("_npc")
						if np != null:
							np.set("emotion", 2)
							NpcEmoticon.show_on(np, int(a.split("=")[1]))
							for i in 30: await get_tree().process_frame
						else:
							print("SHOT: _npc 없음")
				for a in OS.get_cmdline_user_args():
					if a == "--skill=1" and sc.has_method("_show_lab_info"):
						sc.call("_show_lab_info")
						for i in 20: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--result=") and sc.has_method("_show_upgrade_result"):
						sc.call("_show_upgrade_result", a.substr(9) == "ok",
							"체력의 젬+104  체력 +104", "체력의 젬+108  체력 +108", null)
						for i in 20: await get_tree().process_frame
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--sub=") and sc.has_method("_open_potion_buy"):
						sc.call("_open_potion_buy", a.substr(6), 25, "diamond")
						for i in 20: await get_tree().process_frame
		"slotreset":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var srcv := _find_method_node(get_tree().root, "_apply_slot_reset")
			if srcv == null:
				print("SHOT slotreset: cave 노드 없음")
			else:
				UserDB.begin_batch()
				var srkind := "skill" if stage == "skill" else "gem"
				var srkey := "skillslot_change" if srkind == "skill" else "gemslot_change"
				UserDB.add_item(srkey, 3)
				var sruid := UserDB.active_uid()
				var srd := UserDB.get_dragon(sruid)
				var srbefore := UserDB.get_dragon(sruid)
				srcv.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				srcv.call("_use_consumable", srkey,
					"skillslot" if srkind == "skill" else "gemslot")
				for i in 5: await get_tree().process_frame
				var srname: String = Icons.name_of(srd)
				var srpicked := false
				for b in _all_buttons(srcv):
					if String((b as Button).text).find(srname) >= 0:
						(b as Button).pressed.emit(); srpicked = true
						break
				print("SHOT slotreset 대상선택=", srpicked, " (", srname, ")")
				var srpop := _find_node_of_class(srcv, "ItemDetailView")
				await get_tree().create_timer(1.0).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out.get_basename() + "_00.png")
				print("SHOT slotreset 확인창: ", out.get_basename() + "_00.png",
					"  before gems=", Gem.types(srbefore.get("gems", {})),
					" skill_slots=", Loadout.slot_types(srbefore))
				var srhit := false
				for b in _all_buttons(srpop if srpop != null else srcv):
					var par := (b as Button).get_parent()
					for l in _all_labels(par):
						if String((l as Label).text) == "확인":
							(b as Button).pressed.emit(); srhit = true
							break
					if srhit: break
				print("SHOT slotreset 확인클릭=", srhit)
				var srt := [0.9, 1.7, 2.0, 3.0]
				var srprev := 0.0
				for ti in srt.size():
					await get_tree().create_timer(float(srt[ti]) - srprev).timeout
					srprev = float(srt[ti])
					await RenderingServer.frame_post_draw
					var sro := out.get_basename() + ("_%02d.png" % (ti + 1))
					get_viewport().get_texture().get_image().save_png(sro)
					print("SHOT slotreset t=%.1f saved: %s" % [srt[ti], sro])
				var srnew := UserDB.get_dragon(sruid)
				print("SHOT slotreset gems=", Gem.types(srnew.get("gems", {})),
					" skill_slots=", Loadout.slot_types(srnew),
					" equip=", Loadout.equipped_ids(srnew))
				get_tree().quit()
		"lvfx":
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var fxcv := _find_method_node(get_tree().root, "_open_levelup")
			if fxcv == null:
				print("SHOT lvfx: _open_levelup 노드 없음")
			else:
				UserDB.begin_batch()
				UserDB.add_item("bless_of_dersa", 1)
				fxcv.call("_open_levelup")
				for i in 20: await get_tree().process_frame
				var lv0 := int(UserDB.get_dragon(UserDB.active_uid()).get("level", 0))
				fxcv.call("_lvup_use_item", "bless_of_dersa")
				var times := [1.2, 2.6, 4.2, 5.6, 7.2, 9.0, 12.0]
				var prev := 0.0
				for ti in times.size():
					await get_tree().create_timer(float(times[ti]) - prev).timeout
					prev = float(times[ti])
					await RenderingServer.frame_post_draw
					var fimg := get_viewport().get_texture().get_image()
					var fout := out.get_basename() + ("_%02d.png" % ti)
					fimg.save_png(fout)
					print("SHOT lvfx t=%.1f saved: %s" % [times[ti], fout])
				print("SHOT lvfx: 레벨 ", lv0, " -> ",
					int(UserDB.get_dragon(UserDB.active_uid()).get("level", 0)),
					"  busy=", fxcv.get("_lvup_fx_busy"))
				var ok_rr: bool = fxcv.call("_lvup_do_reroll_once")
				await get_tree().create_timer(3.0).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out.get_basename() + "_rr.png")
				print("SHOT lvfx reroll=", ok_rr, " busy@3s=", fxcv.get("_lvup_fx_busy"))
				await get_tree().create_timer(6.0).timeout
				print("SHOT lvfx reroll busy@9s=", fxcv.get("_lvup_fx_busy"))
				get_tree().quit()
		_:
			Scenes.goto(shot, {})

	await get_tree().create_timer(wait).timeout
	print("SHOT bgm=", Bgm._cur)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT saved: ", out)
	if "--noquit" in OS.get_cmdline_user_args():
		print("SHOT: --noquit — 창을 유지한다")
		return
	get_tree().quit()

func _advance_talk(n: int) -> void:
	var tl: Node = null
	for w in 600:
		tl = _find_node_of_class(get_tree().root, "NpcDialogue")
		if tl != null:
			break
		await get_tree().process_frame
	for i in n:
		tl = _find_node_of_class(get_tree().root, "NpcDialogue")
		if tl == null:
			return
		tl.emit_signal("advanced")
		for f in 3: await get_tree().process_frame

func _click_at(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)

func _find_label_button(n: Node, text: String) -> BaseButton:
	if n is Label and (n as Label).text == text:
		for sib in n.get_parent().get_children():
			if sib is BaseButton: return sib
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_label_button(c, text)
		if r != null: return r
	return null

func _press_label_button(n: Node, text: String) -> void:
	var b := _find_label_button(n, text)
	if b != null: b.emit_signal("pressed")
	else: print("SHOT: 버튼 없음 — ", text)

func _find_bottom_box(n: Node) -> BottomTextBox:
	if n is BottomTextBox and not n.is_queued_for_deletion():
		return n
	for c in n.get_children():
		var r := _find_bottom_box(c)
		if r != null: return r
	return null

func _box_text(b: BottomTextBox) -> String:
	var l = b.get("_text_lbl")
	return String((l as Label).text) if l is Label else ""

func _find_popup(n: Node) -> FramedWindow:
	if n is FramedWindow and not n.is_queued_for_deletion():
		return n
	for c in n.get_children():
		var r := _find_popup(c)
		if r != null: return r
	return null

func _click_label_button(n: Node, text: String) -> String:
	var b := _find_label_button(n, text)
	if b == null:
		print("SHOT: 버튼 없음 — ", text)
		return ""
	var c := b as Control
	var p := get_viewport().get_screen_transform() * c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = p; mm.global_position = p
	Input.parse_input_event(mm)
	for i in 3: await get_tree().process_frame
	var hov := get_viewport().gui_get_hovered_control()
	_click_at(p)
	for i in 6: await get_tree().process_frame
	return String(hov.get_path()) if hov else ""

func _collect_labels(n: Node, sub: String, out: Array) -> void:
	if n is Label and sub in (n as Label).text and not n.is_queued_for_deletion():
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_labels(c, sub, out)

func _find_button_tooltip_prefix(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).tooltip_text.begins_with(prefix):
		return n
	for c in n.get_children():
		var r := _find_button_tooltip_prefix(c, prefix)
		if r != null: return r
	return null

func _find_first_button_prefix(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var r := _find_first_button_prefix(c, prefix)
		if r != null: return r
	return null

func _spine_scene_of(n) -> String:
	if not (n is Node): return "(없음)"
	var node := n as Node
	var p := node.scene_file_path
	if p.contains("/dragons/dragon_"):
		return p.get_file().get_basename()
	for c in node.get_children():
		var r := _spine_scene_of(c)
		if r != "(없음)": return r
	return "(없음)"

func _area_state() -> String:
	var out: Array = []
	for a in Bgm._areas:
		var p: AudioStreamPlayer = a["player"]
		if is_instance_valid(p) and p.playing:
			out.append("%s %.0fdB" % [a["track"], p.volume_db])
	return "(없음)" if out.is_empty() else ", ".join(out)

func _find_button_text(n: Node, t: String) -> Button:
	if n is Button and (n as Button).text == t:
		return n as Button
	for c in n.get_children():
		var r := _find_button_text(c, t)
		if r != null: return r
	return null

func _dump_texts(n: Node, base: int) -> Array:
	var out: Array = []
	var seen := 0
	for ch in n.get_children():
		if ch is CanvasLayer:
			seen += 1
			if seen > base:
				out.append_array(_texts_of(ch))
	return out

func _texts_of(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button and (c as Button).text != "":
			out.append("[%s]" % (c as Button).text)
		elif c is Sprite2D and (c as Sprite2D).texture != null:
			out.append("<%s>" % (c as Sprite2D).texture.resource_path.get_file())
		out.append_array(_texts_of(c))
	return out

func _free_popups(n: Node, base: int) -> void:
	var seen := 0
	for ch in n.get_children():
		if ch is CanvasLayer:
			seen += 1
			if seen > base:
				n.remove_child(ch)
				ch.free()

func _find_method_node(n: Node, method: String) -> Node:
	if n.has_method(method): return n
	for c in n.get_children():
		var r := _find_method_node(c, method)
		if r != null: return r
	return null

func _find_node_of_class(n: Node, cls: String) -> Node:
	var sc: Variant = n.get_script()
	if sc is Script and String((sc as Script).get_global_name()) == cls:
		return n
	for c in n.get_children():
		var r := _find_node_of_class(c, cls)
		if r != null: return r
	return null

func _find_builtin(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _find_builtin(c, cls)
		if r != null: return r
	return null

func _cs_fill_slot1(uid: int, equipped: Array) -> int:
	if equipped.size() >= 2 and int(equipped[1]) > 0:
		return 0
	var slot0 := int(equipped[0]) if equipped.size() >= 1 else 0
	var pool: Array = (UserDB.dragon_skills(uid) as Array).duplicate(true)
	var pick := 0
	for e in pool:
		var eid := int((e as Dictionary).get("id", 0))
		if eid > 0 and eid != slot0:
			pick = eid
			break
	if pick == 0:
		for k in Data.skills:
			var kid := int(k)
			if kid > 0 and kid != slot0:
				pick = kid
				break
		if pick == 0:
			return 0
		pool.append({"id": pick, "level": 1, "dedicated": false})
		UserDB.set_dragon_field(uid, "skills", pool)
	UserDB.set_dragon_skill_equip(uid, 1, pick)
	return pick

func _find_node_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm: return n
	for c in n.get_children():
		var r := _find_node_named(c, nm)
		if r != null: return r
	return null

func _all_buttons(n: Node, out: Array = []) -> Array:
	if n is Button: out.append(n)
	for c in n.get_children(): _all_buttons(c, out)
	return out

func _all_labels(n: Node, out: Array = []) -> Array:
	if n is Label: out.append(n)
	for c in n.get_children(): _all_labels(c, out)
	return out

func _all_texture_buttons(n: Node, out: Array = []) -> Array:
	if n is TextureButton: out.append(n)
	for c in n.get_children(): _all_texture_buttons(c, out)
	return out

func _pick_team_buff_party() -> Array:
	var table: Dictionary = Data.team_buffs
	var race_dim := String(table.get("race_dim", "element"))
	var owned: Array = UserDB.dragons()
	var by_elem: Dictionary = {}
	for d in owned:
		var e := String(Data.get_dragon(int(d["id"])).get(race_dim, ""))
		if e == "": continue
		if not by_elem.has(e): by_elem[e] = []
		(by_elem[e] as Array).append(int(d["uid"]))
	for b in (table.get("buffs", []) as Array):
		var buff: Dictionary = b
		if String(buff.get("img", "")) == "": continue
		var need: Dictionary = buff.get("combine", {})
		var uids: Array = []
		var ok := true
		for e in need:
			var pool: Array = by_elem.get(String(e), [])
			if pool.size() < int(need[e]):
				ok = false; break
			for i in int(need[e]): uids.append(pool[i])
		if ok and uids.size() == 3:
			print("SHOT teambuff: no=%d %s combine=%s uids=%s" % [
				int(buff["no"]), buff["name"], str(need), str(uids)])
			return uids
	return []

func _node_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for c in n.get_children():
		var r := _node_with_method(c, m)
		if r != null:
			return r
	return null

func _seed_equip_slots(uid: int, locked: bool) -> void:
	if locked:
		UserDB.set_dragon_field(uid, "equip_slots", ["all"])
		UserDB.set_dragon_field(uid, "equip", {"slots": []})
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var rows: Array = [
		["all", "special:skull:G스컬의 붉은장갑", 5, 25],
		["battle", "basic:묘안석:5", 4, 12],
		["support", "special:balrog:카이저 발록의 팔찌", 5, 25],
		["artifact", "artifact:옵스큐럼:5", 3, 8]]
	var cat := Equipment.catalog(Data.equipment)
	var slots: Array = []
	for r in rows:
		var key := String((r as Array)[1])
		if not cat.has(key):
			continue
		var g := int((r as Array)[2])
		slots.append({"slot": String((r as Array)[0]), "key": key, "grade": g,
			"enhance": int((r as Array)[3]), "belong": uid,
			"options": Equipment.roll_options(g, rng, Data.equipment)})
	UserDB.set_dragon_field(uid, "equip_slots", ["all", "battle", "support", "artifact"])
	UserDB.set_dragon_field(uid, "equip", {"slots": slots})
