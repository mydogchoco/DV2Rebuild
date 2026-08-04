extends Node
# 임시 오토로드: 지정 씬으로 이동한 뒤 뷰포트를 PNG로 저장한다.
# 사용: godot --path . --script ... 대신 project.godot 오토로드에 등록 후 실행.
#   godot --path . -- --shot=<key> --out=<png> --wait=<sec>

func _ready() -> void:
	# 월드맵 조각의 투명 슬롯을 검사할 때 바다층을 마젠타 판으로 대체한다.
	# 오토로드가 WorldMap보다 먼저 준비되므로 맵 생성 전에 메타를 세팅할 수 있다.
	if "--no-ocean=1" in OS.get_cmdline_user_args():
		Engine.set_meta("wm_no_ocean", true)
	# ⚠️ 2026-07-30: `--shot=` 인자가 **없으면 아무것도 하지 않는다**.
	#   종전엔 shot 기본값이 "battle" 이라, 오토로드가 등록된 채로 게임을 그냥 실행하면
	#   전투로 끌고 가 스크린샷을 찍고 **`get_tree().quit()` 으로 창을 닫아 버렸다**
	#   (플레이 검수를 하려는데 3초 뒤 게임이 꺼졌다). 캡처 워크플로는 항상 `--shot=` 을
	#   넘기므로 이 가드는 그쪽에 영향이 없다.
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
	var extra := "0"          # 모드별 두 번째 인자(--extra=)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--wait="): wait = float(a.substr(7))
		elif a.begins_with("--stage="): stage = a.substr(8)
		elif a.begins_with("--extra="): extra = a.substr(8)

	# ⚠️ 오토로드 _ready 는 main.gd 보다 먼저 돈다 — 닉네임을 여기서 미리 넣어야
	#    main.gd 의 "최초 1회 강제 입력" 팝업이 뜨지 않는다. begin_batch = 디스크 미기록.
	if not UserDB.has_user_nickname():
		UserDB.begin_batch()
		UserDB.set_user_nickname("계란")

	# 타이틀 화면 종류(2020/구판) 검수 — **오토로드는 main.gd 보다 먼저 돌기 때문에** 여기서
	# 미리 정해 둬야 인트로가 그 값으로 지어진다. begin_batch = 디스크 미기록.
	if shot == "intro" and (stage == "old" or stage == "2020"):
		UserDB.begin_batch()
		UserDB.set_pmeta("title_screen", stage)

	for i in 20: await get_tree().process_frame
	match shot:
		"advfountain":
			# 회복샘 워드아트 검수 — 원작 setEventHealArea(플래시+회전 워드아트+파티클+샘 스프라이트).
			# ⚠️ 종전 `advtreasure` 모드를 여기로 바꿨다 — 보물 조우는 ⚫CUT 되어
			#   `_open_treasure` 자체가 없다(data/adventure_events.json `steps._cut_treasure`).
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": 1})
			for i in 30: await get_tree().process_frame
			var fv := _node_with_method(get_tree().root, "_show_fountain")
			if fv:
				fv.call("_show_fountain", extra == "1")
		"advready":
			# 탐험 조우 선택지 화면 검수 — 레퍼런스 docs/ref/adventure/전투4.png · 전투5.png 대조용.
			# 보스 게이지(우상단) + 하단 파티 카드 + 좌'도망간다'/우'싸운다' 가 한 화면에 나온다.
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
			# 스킬 이펙트 스파인 배치 검수 — 전투를 띄우고 이펙트를 강제 재생한다.
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
				# 0.7초면 사라지므로 캡처 타이밍을 맞추기 어렵다 → 계속 다시 켠다.
				for rep in 20:
					bs.call("_play_skill_spine", sid, bs.get("_views").get("E0", {}))
					await get_tree().create_timer(0.4).timeout
		"bicon":
			# 버프/디버프 아이콘(원작 Bicon) 검수 — 전투를 띄우고 아이콘을 직접 붙인다(결정적).
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			# ⚠️ `get_tree().current_scene` 는 항상 Main 이다 — Scenes.goto 는 Main 안의 자식을
			# 갈아 끼우지 트리 루트 씬을 바꾸지 않는다. 메서드를 가진 노드를 직접 찾는다.
			var bs2 := _node_with_method(get_tree().root, "_bicon_add")
			if bs2:
				# 전투 재생 코루틴을 무효화해 몬스터 사망/화면 전환이 검수 아이콘을 지우지 못하게 한다.
				bs2.set("_gen", int(bs2.get("_gen")) + 1)
				var views: Dictionary = bs2.get("_views")
				# 상처 파악(23)·신경독소(32)는 시전자가 아니라 **적**에게 귀속되는 디버프다.
				for pair in [[23, false, 3], [32, false, 2], [140, false, 4]]:
					bs2.call("_bicon_add", views.get("E0", {}), pair[0], pair[1], pair[2])
				for pair in [[14, true, 2], [60, true, 3]]:
					bs2.call("_bicon_add", views.get("A0", {}), pair[0], pair[1], pair[2])
		"teambuff":
			# 조합 팀버프 연출(원작 CombineElementsLayer) 통합 검수 — **전투 씬 안에서** 확인한다.
			# 보유 드래곤 중 아이콘 있는 버프를 발동시키는 3마리를 골라 party_uids 로 넘긴다.
			var uids := _pick_team_buff_party()
			if uids.is_empty():
				print("SHOT teambuff: 보유 드래곤으로 발동 가능한(아이콘 있는) 조합이 없다")
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("battle", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0, "party_uids": uids, "run_seed": randi()})
		"colosseum":
			# 콜로세움 로비(원작 ColosseumScene) 배치 검수.
			# ⚠️ intro→colosseum 은 상태기계가 막는다(TRANSITIONS) — 다른 케이스와 같이
			#   메인 허브(월드맵)를 한 번 거친다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 20: await get_tree().process_frame
		"fight":
			# 콜로세움 대전 씬(원작 FightScene) 검수 — 봇 상대를 하나 굴려 바로 붙인다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			Scenes.goto("colosseum", {})
			for i in 10: await get_tree().process_frame
			var frng := RandomNumberGenerator.new()
			frng.seed = 20260804
			var foe := Colosseum.roll_match(extra if extra != "0" else "team", frng)
			# ⚠️ 콜로세움은 레벨 25 이상(=성체)만 나간다. 공격 모션이 성체에만 있어서
			#   저레벨 개체를 넣으면 아무 모션도 안 나온다(사용자 지적 2026-08-04).
			var fparty: Array = Colosseum.eligible_uids()
			if fparty.is_empty():
				fparty = UserDB.party()
			Scenes.goto("fight", {"mode": extra if extra != "0" else "team",
				"opponent": foe, "party": fparty})
			for i in 20: await get_tree().process_frame
		"fightfx":
			# 대전 중 **간헐 연출** 검수 — 스킬 이름 배너(createIcon 상단)와 상태이상 아이콘은
			# 실제 전투에서 언제 뜰지 알 수 없어 타이밍 캡처가 안 된다. 직접 세워 놓고 찍는다.
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
			if fs != null and fs.has_method("_skill_banner"):
				fs.call("_skill_banner", "철갑 방패", 11)
				var vws: Dictionary = fs.get("_views")
				var kk := 0
				for tag in vws:
					fs.call("_status_icon", vws[tag], [11, 30, 56][kk % 3], kk % 2 == 0, 2 + kk)
					kk += 1
			for i in 12: await get_tree().process_frame
		"getitem":
			# 획득 공개 팝업(원작 ShowGetItemDetailLayer) 배치 검수 — N개를 원형으로 놓는다.
			Scenes.goto("shop", {"area": "elpis"})
			for i in 20: await get_tree().process_frame
			var gi := get_tree().current_scene
			var gn := 3
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--n="): gn = int(a.split("=")[1])
			var gitems: Array = []
			# 키 5종을 섞어 resolve 분기를 눈으로 검수한다(아이템·젬·장비·알·스킬).
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
			var gp: GetItemPopup = null
			if gn > 0:
				gp = GetItemPopup.open(gi, gitems)
			await get_tree().process_frame
		"adventure":
			# 탐험 이벤트 큐 + 조우 전 선택지(원작 setBattleReady) 검수.
			#   --stage=<id> · --enc=<n> · --hurt=1(회복샘 게이트 열기) · --hero=1
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
			# hp_state 가 비어 있지 않아야 회복샘 게이트(needs_hurt)가 열린다.
			apar["hp_state"] = {"dummy": 1} if a_hurt else {}
			Scenes.goto("adventure", apar)
			for i in 10: await get_tree().process_frame
			# ⚠️ `current_scene` 은 어드벤처 노드가 아니다(Scenes.goto 가 하위에 붙인다) →
			#    메서드로 찾는다. 종전엔 여기서 조용히 null 이 나와 검수가 무의미했다.
			var advn := _find_method_node(get_tree().root, "_monster_meet")
			if advn != null:
				print("SHOT adv seed=", apar.get("run_seed"), " steps=", advn.get("_steps"))
				var sr = advn.get("_stage")
				if sr != null:
					print("SHOT adv variant=", (sr as Dictionary).get("variant", "-"),
						" lv=", (sr as Dictionary).get("level", "-"),
						" enemy0=", ((sr as Dictionary).get("enemies", [{}])[0] as Dictionary).get("name", "-"))
		"bossalert":
			# 보스 조우 컷인(원작 setAlertMonster) 검수 — 마지막 조우로 바로 진입시킨다.
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
			# 탐험 중 레벨업 결과창(LevelUpResult) 검수.
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
			# 스토리 전투 배선 검수 — 전투 스텝 직전부터 재생시킨다.
			#   --stage=<회차> --extra=<재개 스텝 index>
			# ⚠️ `Scenes` 는 `intro → story` 전환을 막는다(허용표: story 는 worldmap/cave/town/
			#    adventure/battle 에서만 온다) — 월드맵을 한 번 거쳐야 한다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("story", {"no": int(stage), "part": 0, "back": "worldmap",
				"resume_flow": int(extra)})
		"story":
			# 스토리 재생 검수. --stage=<시나리오번호> 로 고른다(삽화 있는 편: 12·19·20·21·101).
			# ⚠️ intro → story 는 막혀 있다(§Scenes 허용표) — 월드맵을 거친다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("story", {"no": int(stage), "part": 0, "back": "worldmap"})
		"tutorial":
			# 오프닝 튜토리얼(원작 시나리오 0 의 `SN_0_*`) 검수.
			#   --step=<SN_0_…> : 그 스텝부터 시작(기본은 처음부터)
			# ⚠️ 세이브를 건드리지 않으려고 begin_batch 로 연다.
			UserDB.begin_batch()
			var tu_step := ""
			var tu_scene := "worldmap"        # --scene=cave 로 동굴 스텝 검수
			for a7 in OS.get_cmdline_user_args():
				if a7.begins_with("--step="): tu_step = a7.substr(7)
				elif a7.begins_with("--scene="): tu_scene = a7.substr(8)
			UserDB.set_pmeta("tutorial_done", false)
			UserDB.set_pmeta("tutorial_step", tu_step)
			# --eggonly=1 : 부화 완료 드래곤을 없애 **게이트가 실제로 막는지** 본다(알만 남긴다).
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
			# 알(부화) 검수 — 원작 CaveScene 알 분기 이식본(docs/ref/porting/EggHatch.md).
			#   --did=<종id>    부화 대상 드래곤(기본 1)
			#   --remain=<초>   남은 시간. 0 이면 "완료" 상태로 뜬다(기본 143997 = 39:59:57)
			#   --blessed=1     축복 둥지(황금 월계관 nest_holy + 먼지 + 보너스 성급 분리 연출)
			#   --enh=<0~3>     알 강화 단계(ani_egg_up1 오라 + 이름 "+N")
			#   --tap=1         완료 상태에서 알을 탭해 부화 연출을 태운다(--wait 로 시점 선택)
			#   --click=1       같은 일을 **실제 마우스 클릭 주입**으로 — 히트테스트까지 태운다
			#                   (드래곤 터치영역이 알 탭을 덮던 회귀를 잡는 용도)
			UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
			var ce_did := 1
			var ce_remain := 143997
			var ce_blessed := false
			var ce_enh := 0
			var ce_tap := false
			for a6 in OS.get_cmdline_user_args():
				if a6.begins_with("--did="): ce_did = int(a6.substr(6))
				elif a6.begins_with("--remain="): ce_remain = int(a6.substr(9))
				elif a6 == "--blessed=1": ce_blessed = true
				elif a6.begins_with("--enh="): ce_enh = int(a6.substr(6))
				elif a6 == "--tap=1": ce_tap = true
			var ce_grade := 7.5 if ce_blessed else 6.6
			var ce_egg := UserDB.add_egg(ce_did, ce_grade, ce_remain, ce_enh, {}, ce_blessed)
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
				# 알 중심(원작 탭 영역 250×300 의 한가운데) 화면 좌표에 실제 클릭을 넣는다.
				var ce_vis := get_viewport().get_visible_rect().size
				var ce_at := Vector2(ce_vis.x * 0.5 + 5.0, ce_vis.y * 0.5 - 30.0)
				_click_at(ce_at)
				await get_tree().process_frame
				var ce_c := _node_with_method(get_tree().root, "_on_egg_tap")
				print("SHOT caveegg click@", ce_at, " busy=", ce_c.get("_egg_busy") if ce_c else "?",
					" done=", ce_c.get("_egg_done") if ce_c else "?")
		"status":
			# 상태창(StatusLayer) 검수 — 원작 진입점 그대로 **월드맵 위**에서 띄운다.
			# 젬/스킬/장비 칸이 실제 장착분을 그리는지 보려고 임시로 채운다(begin_batch = 디스크 미기록).
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
			var sl := StatusLayer.open(sw)
			sl.action_requested.connect(func(a, arg): print("SHOT status action: ", a, " ", arg))
		"statuscave":
			Scenes.goto("cave", {"open": "status"})
		"dex":
			# 도감(BookPopup 재이식) 검수. --sel=<종id> 로 우측 패널까지, --step=<i> 로 단계 선택.
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
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
						# 속성 필터 강제(링 이동 검수) — 버튼 루트를 인덱스로 찾는다.
						var ei := int(a.substr(6))
						var els := ["all", "fire", "aqua", "earth", "wind",
							"light", "dark", "holy", "chaos", "shadow"]
						var btns: Array = dx.get("_dex_ele_btns")
						if ei < btns.size():
							dx.call("_dex_on_click_element", String(els[ei]), btns[ei])
		"dexinfo":
			# 도감 돋보기 전체화면(DragonBookInfoLayer 재이식). --sel=<종id> (기본 = 활성 드래곤 종).
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
			# 하단 스킬 칸 검수 — 0번칸은 **스킬 타입과 일치**시키고 1번칸은 일부러 어긋나게 둔다.
			# 일치 칸에서 모양 프레임 + 스킬 아이콘이 **둘 다** 보여야 한다(원작 setDragonInfo).
			# begin_batch = 디스크에 쓰지 않는다(사용자 세이브 보호).
			UserDB.begin_batch()
			var cs_uid := UserDB.active_uid()
			# 칸에 그려지는 건 **장착분**이다(v9: 학습 풀과 분리) → 장착 번호로 타입을 맞춘다.
			var cs_sk: Array = UserDB.dragon_skill_equip(cs_uid)
			if cs_sk.size() >= 1 and int(cs_sk[0]) > 0:
				var t0 := String(Data.skills.get(str(int(cs_sk[0])), {}).get("slot", "cir"))
				var t1 := "star"
				if cs_sk.size() >= 2 and int(cs_sk[1]) > 0:
					# 1번칸은 그 스킬의 타입이 **아닌** 값으로 → 불일치(아이콘만) 케이스
					var s1 := String(Data.skills.get(str(int(cs_sk[1])), {}).get("slot", "cir"))
					t1 = "sq" if s1 != "sq" else "tri"
				UserDB.set_dragon_field(cs_uid, "skill_slots", [t0, t1])
				print("SHOT caveslot: skill_slots=", [t0, t1], " skills=", cs_sk)
			# 레벨 35 미만이면 1번칸이 잠겨 있어 검수가 안 된다 → 임시로 올린다.
			if int(UserDB.get_dragon(cs_uid).get("level", 1)) < 35:
				UserDB.set_dragon_field(cs_uid, "level", 40)
			Scenes.goto("cave", {})
		"equipfx":
			# 장비 강화(ItemEnchantPopup) / 제련(EquipOptionLayer) 검수.
			# `--tab=enchant|smelt`. 장비가 없으면 하나 끼워 준다. begin_batch = 디스크 미기록.
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
			# 강화 재료 후보(= 보유 장비) — 원작 목록이 비면 격자를 볼 수 없다.
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
					var ef_pop := ItemEnchantPopup.open(ef_n,
						ItemEnchantPopup.target_worn(ef_uid, ef_slot))
					for i in 10: await get_tree().process_frame
					# 재료 두 칸을 채우고 세 번째를 하이라이트한 상태로 잡는다(확률 가산 확인).
					var ef_n2: int = (ef_pop.get("_pool") as PackedStringArray).size()
					for ef_k in 3:
						ef_pop.call("_on_cell_click", maxi(0, ef_n2 - 3 + ef_k))
						if ef_k < 2: ef_pop.call("_on_pick")
						await get_tree().process_frame

				else:
					# ⚠️ 2026-08-01 부터 동전은 **등급을 바꾸지 않는다**(`Equipment.reroll` 이
					#   슬롯 등급과 다르면 거절). 하드코딩 4(에픽) 대신 낀 장비의 실제 등급과
					#   그 등급의 동전을 쓴다 — 안 그러면 `선택` 을 눌러도 아무 일도 없다.
					var ef_sd: Dictionary = {}
					for ef_s in (UserDB.get_dragon(ef_uid).get("equip", {}).get("slots", []) as Array):
						if String((ef_s as Dictionary).get("slot", "")) == ef_slot:
							ef_sd = ef_s
					var ef_g := int(ef_sd.get("grade", 0))
					var ef_coin := String((Data.equipment.get("option", {})
						.get("reroll_items", {}) as Dictionary).get(str(ef_g), "ginu_coin_green"))
					print("SHOT eqopt 등급=", ef_g, " 동전=", ef_coin)
					var ef_p = EquipOptionLayer.open(ef_n, ef_uid, ef_slot, ef_coin, ef_g)
					for i in 160: await get_tree().process_frame     # 마법진 연출이 끝나길 기다린다
					ef_p.set("_pick", 1)
					ef_p.call("_rebuild_result")
		"equipslots":
			# 동굴 장비 4칸 창(원작 MultyEquipPop). `--tab=locked` 로 잠긴 칸 상태도 본다.
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
			# 연구소 B1 '드래곤 강화' → 장비 슬롯 확장(동굴과 같은 MultyEquipPop 위젯).
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
			# 점술집 지하 — `--tab=disassemble|soul` 로 기능 창을 연다(원작 UpgradeGemLayer(2) /
			# UpgradeSoulGemLayer). 젬·재료를 임시로 넣는다. begin_batch = 디스크 미기록.
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
			# 아티펙트 합성(원작 ArtifactMix) 검수 — 아티팩트 4개를 임시로 넣고 창을 연다.
			# begin_batch = 디스크 미기록.
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
				var am_p = ArtifactMixPopup.open(am_n, am_base)
				for i in 10: await get_tree().process_frame
				# 재료 3칸을 채운 상태(참조 아티팩트합성5.png)로 맞춘다.
				am_p.set("_mats", [am_mat, am_mat, am_mat])
				am_p.call("_refresh")
				print("SHOT artmix cost=", am_p.call("_cost"))
		"skillpop":
			# 스킬 장착 창(원작 SkillsPopup 이식) 검수 — 학습 풀을 임시로 채우고 칸 0 을 연다.
			# begin_batch = 디스크 미기록.
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
				# 선택 상태까지 보려고 두 번째 항목을 고른다.
				var sp_pop := _find_node_of_class(get_tree().root, "SkillsPopup")
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
			# 파티 편성창(원작 setAddDragonPopupLayer + AddDragonCell) — 영웅 난이도로 진입.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": stage, "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0, "hero": true})
		"loot":
			# 2026-08-01: 자작 _show_loot 삭제 → 원작 setEventReward 이식(_play_reward_phases)을 찍는다.
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
			# 탐험 보상 배수권(경험치·골드 N배) 실동작 검수 — 2026-08-04.
			#   ① 가방에서 **실제 사용 경로**(_consumable_action → _use_consumable)로 켠다
			#   ② UserDB pmeta 에 실시간 만료로 저장되는지
			#   ③ 전투 승리 보상에 배수가 실제로 곱해지는지(골드 획득량 비교)
			# `--extra=off` 로 주면 버프 없이 같은 전투를 돌려 기준값을 찍는다.
			UserDB.begin_batch()          # ⚠️ 검수용 — 디스크에 쓰지 않는다
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
			# 세이브 왕복(JSON) — 게임을 껐다 켜도 남아 있어야 한다. int 가 float 로 돌아오는
			# JSON 함정까지 같이 본다.
			var rb_json = JSON.parse_string(JSON.stringify(UserDB.reward_buff()))
			print("SHOT rewardbuff: JSON 왕복 후 gold×",
				ItemEffect.reward_buff_mult(rb_json, "gold", rb_now),
				" (1시간 뒤 ", ItemEffect.reward_buff_mult(rb_json, "gold", rb_now + 3601), ")")
			# 전투 1회 — 골드 획득량으로 배수 확인. 스킵을 켜서 빨리 끝낸다.
			var rb_gold0 := UserDB.gold()
			Scenes.goto("worldmap", {"region": "yutakan"})   # 씬 매니저가 cave→battle 직행을 막는다
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
			# 혼돈의 틈새 소환 보스 검수 — 월드맵 스파인 3변형(원작 showDarknix).
			#   --status=1|2|3 (기본 1 = 다크닉스). --scroll= 로 좌우 위치.
			# 소환 상태를 세이브에 직접 심고 월드맵을 띄운다(포탈 소모 흐름은 별도 검수).
			var dk_status := 1
			var dk_frac := 0.28
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--status="): dk_status = int(a.substr(9))
				elif a.begins_with("--scroll="): dk_frac = float(a.substr(9))
			# face=1 → 등장(appear) 연출을 건너뛰고 곧바로 breath 루프. 크기·위치 검수는
			# 정상 상태에서 봐야 한다(appear 중간은 슬롯이 아직 안 켜져 유령처럼 보인다).
			# --appear=1 을 주면 등장 연출부터 본다.
			var dk_face := 1
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--appear="): dk_face = 0 if a.substr(9) == "1" else 1
			UserDB.darknix_summon({"status": dk_status,
				"until": int(Time.get_unix_time_from_system()) + 3600, "face": dk_face})
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 40: await get_tree().process_frame
			# --revisit=1 : 상점에 갔다가 월드맵으로 **돌아온 뒤** 캡처(사용자 신고 재현).
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
			# 소환한 보스가 **재진입해도 같은지** 검수(2026-07-31 사용자 신고 회귀 테스트).
			# --status=1|2|3 으로 소환해 두고 탐험을 3번 새로 지어 매번 어떤 보스가 잡히는지 본다.
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
			# 월드맵 조각 클릭 판정 감사 — 조각마다 중심 + 8방향 오프셋을 찍어 **어느 타깃이
			# 잡히는지** 표로 뽑는다(부작용 없는 `_resolve_click` 만 부른다).
			# 지역은 --stage=(yutakan/elf/dwarf/uno).
			Scenes.goto("worldmap", {"region": stage})
			for i in 30: await get_tree().process_frame
			var hwm := _find_method_node(get_tree().root, "_resolve_click")
			if hwm == null:
				print("SHOT: worldmap 노드 없음")
			else:
				# 오라클 = "**그 조각의 그림이 실제로 보이는 지점**을 누르면 그 조각이 잡혀야
				# 한다". 중심에서 ±N px 같은 고정 오프셋은 오라클이 못 된다 — 조각이 촘촘해서
				# 70px 옆은 정말로 이웃 조각 영역이다.
				# 실패로 세는 것은 **그 지점에서 그림이 안 보이는 조각이 잡힌 경우**뿐이다
				# (= 보이지 않는 것이 보이는 것을 가로챈, 사용자가 신고한 그 버그).
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
								continue          # 그 조각이 안 보이는 지점 — 오라클 밖
							tot += 1
							var got: Dictionary = hwm.call("_resolve_click", pt)
							if got.is_empty():
								bad += 1
								print("  ✘ %-14s 보이는데 무반응 @%d,%d" % [want, int(pt.x), int(pt.y)])
								continue
							if String(got.get("arg", "")) == want:
								continue
							# 다른 조각이 잡혔다 — 그쪽도 **그 지점에서 보이면** 정상(위에 있는 것).
							if bool(hwm.call("_opaque_at", got, pt)):
								continue
							bad += 1
							print("  ✘ %-14s 를 눌렀는데 안 보이는 %s 가 가로챔 @%d,%d"
								% [want, String(got.get("arg", "")), int(pt.x), int(pt.y)])
				print("SHOT: hittest %s — 오판 %d / 보이는점 %d" % [stage, bad, tot])
		"dkfinish":
			# 2단 대면 검수 — 보스를 소환해 두고 혼돈의 틈새 전투를 실제로 끝까지 돌린 뒤
			# '마무리 일격' 버튼이 뜨는지 본다(원작 setEventFightEnd face==1 가지).
			# --status= 로 보스 지정. --wait= 은 전투가 끝날 만큼 넉넉히(40 이상).
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
				for r in 2: bt2.call("_cycle_speed")   # 1x → 4x
			# --press=1 : 전투가 끝나기를 기다렸다가 '마무리 일격' 을 실제로 눌러 본다.
			var fpress := false
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--press="): fpress = a.substr(8) == "1"
			if fpress:
				await get_tree().create_timer(60.0).timeout
				# 라벨은 NinePatchRect 의 자식이고 투명 Button 은 씬 루트에 따로 붙어 있다
				# (`_darknix_finish_button`). 라벨 위치를 찾아 그 지점을 클릭하면 버튼에 맞는다.
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
			# 혼돈의 틈새 입장 게이트 검수(원작 getIsExistSomething 의 4분기).
			#   --portal=N  보유 포탈 수(기본 1)   --dia=N  다이아(기본 999)
			# 던전 팝업을 열고 '일반' 을 눌러 소환 팝업이 뜨는지까지 본다.
			var gp := 1
			var gd := 999
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--portal="): gp = int(a.substr(9))
				elif a.begins_with("--dia="): gd = int(a.substr(6))
			UserDB.begin_batch()
			UserDB.darknix_clear()
			UserDB.use_item("portal", UserDB.item_count("portal"))   # 0 으로 비우고
			if gp > 0: UserDB.add_item("portal", gp)
			UserDB.add_currency("diamond", gd - UserDB.diamond())
			UserDB.save()
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
			var gwm := _find_method_node(get_tree().root, "_build_region_native")
			if gwm != null and gwm.has_method("_goto_target"):
				gwm.call("_goto_target", "battle:8")
			for i in 20: await get_tree().process_frame
			# 던전 팝업의 '일반' 버튼을 눌러 게이트를 태운다.
			for btn in _all_buttons(get_tree().root):
				var bl := _find_node_named(btn.get_parent(), "label")
				if bl is Label and String((bl as Label).text) == "일반":
					_click_at(get_viewport().get_screen_transform() * btn.get_global_rect().get_center())
					break
			for i in 20: await get_tree().process_frame
		"worldmap":
			# 지역 앰비언트 검수. 지역명은 --stage= 로 넘긴다(yutakan/elf/dwarf).
			# 스크롤 위치는 --scroll= (0.0~1.0, 기본 0.5 = 가운데).
			# 유타칸 변형은 --night=1 / --kades=1 (원작 getDBYutakanNight/Kades 대체 플래그).
			var wm_p := {"region": stage}
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--night="): wm_p["night"] = a.substr(8) == "1"
				elif a.begins_with("--kades="): wm_p["kades"] = a.substr(8) == "1"
			Scenes.goto("worldmap", wm_p)
			for i in 30: await get_tree().process_frame
			# ⚠️ `current_scene` 은 Main(main.gd) 이다 — 월드맵은 그 자식이라 메서드로 찾아야 한다.
			var wm := _find_method_node(get_tree().root, "_build_region_native")
			var frac := 0.5
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--scroll="): frac = float(a.substr(9))
			if wm and wm.get("_max_scroll") != null and wm.get("_content") != null:
				var ms := float(wm.get("_max_scroll"))
				var cn := wm.get("_content") as Node2D
				if cn != null: cn.position.x = -ms * frac
			# --notice=<문구> : 진입 불가 안내 토스트(원작 GameManager::showToast) 검수용.
			for a3 in OS.get_cmdline_user_args():
				if a3.begins_with("--notice=") and wm != null and wm.has_method("_notice"):
					wm.call("_notice", a3.substr(9))
				# --fieldfx=<필드번호> : 필드 터치 연출(원작 setMapAnimation) 검수.
				elif a3.begins_with("--fieldfx=") and wm != null and wm.has_method("_play_field_fx"):
					wm.call("_play_field_fx", int(a3.substr(10)))
				# --goto=<target> : 진입 게이트 검수(예 town:elpis / battle:15). 막히면 토스트가 뜬다.
				elif a3.begins_with("--goto=") and wm != null and wm.has_method("_goto_target"):
					wm.call("_goto_target", a3.substr(7))
		"town":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			var t_area := "elpis"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--area="): t_area = a.substr(7)
			# 밤 여부는 params 로 넘긴다 — town.gd `_resolve_night` 가 params → UserDB pmeta 순으로 본다.
			# (종전엔 `_night` 를 직접 찔렀는데, 그러면 --night=0 이 "낮 강제"가 되지 않는다.)
			var t_night := -1
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--night="): t_night = 1 if a2.substr(8) == "1" else 0
			var t_p := {"area": t_area}
			if t_night >= 0: t_p["night"] = (t_night == 1)
			Scenes.goto("town", t_p)
			# --scroll=0~1 로 가로 스크롤 위치 지정(마을 배치 검수용). --night=1 로 밤.
			for i in 20: await get_tree().process_frame
			# ⚠️ `_apply_scroll` 은 worldmap.gd 에도 있다 — 해제 중인 월드맵 노드를 잡으면
			# 그쪽을 스크롤시키고(엉뚱한 화면) 이어서 오류로 캡처가 조용히 죽는다.
			# 타운에만 있는 `_place_ambient` 로 특정한다.
			var tn := _find_method_node(get_tree().root, "_place_ambient")
			if tn != null:
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--scroll=") and tn != null:
						tn.set("_scroll_x", float(tn.get("_max_scroll")) * float(a.substr(9)))
						tn.call("_apply_scroll")
				# --npc=<id> : 그 NPC 를 화면 안으로 스크롤하고 말풍선을 띄운다(대사 검수).
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
					# --qm=1 : 퀘스트 마크 보유 NPC 를 출력(검수용)
					for qa in OS.get_cmdline_user_args():
						if qa == "--qm=1" and tn != null:
							for r in (tn.get("_npcs") as Array):
								var st: String = tn.call("_npc_quest_state", int(r.get("qslot", -1)))
								if st != "": print("QM ", r["id"], " slot=", r.get("qslot"), " -> ", st)
					# --face=L|R : 모든 NPC 의 몸 방향을 강제(반전 부호 실측용).
					for fa in OS.get_cmdline_user_args():
						if fa.begins_with("--face=") and tn != null:
							var f := -1 if fa.substr(7) == "L" else 1
							for r in (tn.get("_npcs") as Array):
								r["facing"] = f
								tn.call("_npc_face", r)
								tn.call("_npc_play", r, "walk")
		"questflow":
			# 마을 미션 대사 흐름 회귀(원작 TownQuestManager) — 세이브 미기록(begin_batch).
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()
			UserDB.set_pmeta("quests", {"date": Time.get_date_string_from_system()})
			var qs := Scenes.current_scene()
			print("QF state0=", qs.call("_npc_quest_state", 1))          # kanggalo = 알 부화
			qs.call("_on_npc_click", "kanggalo")
			await get_tree().create_timer(2.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_offer.png")
			# 수락 버튼(선택 레이어의 첫 버튼)
			var ch := _find_label_button(qs, "수락")
			if ch != null: ch.emit_signal("pressed")
			for i in 10: await get_tree().process_frame
			print("QF accepted=", UserDB.quest_accepted("hatches"), " state1=", qs.call("_npc_quest_state", 1))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_ok.png")
			# 진행 → 목표 달성 → 다시 말 걸면 완료 대사 + 보상
			UserDB.bump_quest("hatches")
			print("QF progress=", UserDB.quest_progress("hatches"), " state2=", qs.call("_npc_quest_state", 1))
			var g0 := UserDB.gold()
			qs.call("_on_npc_click", "kanggalo")
			for i in 10: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_talk.png")
			# 원작 NpcTalkLayer 는 대사를 넘겨야(탭) 다음으로 간다 → advanced 를 직접 쏜다.
			for c4 in qs.get_children():
				if c4 is NpcTalkLayer: c4.emit_signal("advanced")
			for i in 10: await get_tree().process_frame
			print("QF cleared=", UserDB.quest_claimed("hatches"), " gold+", UserDB.gold() - g0)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_qf_clear.png")
			# 거절 경로 + 레벨 게이트(yuria = 전투 승리, lv 5)
			UserDB.set_pmeta("quests", {"date": Time.get_date_string_from_system()})
			qs.call("_on_npc_click", "pino")
			for i in 8: await get_tree().process_frame
			var nb := _find_label_button(qs, "거절")
			if nb != null: nb.emit_signal("pressed")
			for i in 8: await get_tree().process_frame
			print("QF refused gaveup=", UserDB.quest_gaveup("feeds"), " state=", qs.call("_npc_quest_state", 2))
			get_tree().quit()
		"townwire":
			# 마을 배선 회귀 검사 — 원작 `TownMainMenuLayer` 이식(2026-07-31) 검증용.
			#   ① 우상단 close_btn(tag 700) → 월드맵 복귀   ② 두루마리(tag 0x2c1) → 퀘스트 팝업
			#   ③ 둥지 표지판(tag 0x208) 히트영역 존재      ④ 의뢰 게시판은 히트영역이 **없어야** 한다
			# 실제 마우스 이벤트를 주입해 히트테스트까지 태운다.
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
			# ⚠️ `_click_at` 은 **창 픽셀**을 받는데 UI 좌표는 디자인 공간(1231×692)이다
			#    (stretch 로 1366×768 에 늘어난다) → 반드시 변환해서 넣는다.
			var tw_vis := get_viewport().get_visible_rect().size
			var tw_k: Vector2 = Vector2(DisplayServer.window_get_size()) / tw_vis
			# ① 닫기(tag 700) → 월드맵. **가장 먼저** 시험한다 — 팝업을 띄웠다 닫은 뒤에
			#    누르면 해제 대기 중인 오버레이가 클릭을 먹어 오탐이 난다.
			_click_at(Vector2(tw_vis.x - 50.0, 50.0) * tw_k)
			for i in 30: await get_tree().process_frame
			print("WIRE after_close=", Scenes.current_state())
			# ② 두루마리(tag 0x2c1) — 다시 마을로 들어가 팝업이 뜨는지 본다.
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
			# 6/6 상태 렌더링 검증 — 회전 후광·클리어 도장·[보상 받기] 활성.
			# `begin_batch()` 로 디스크 기록을 막아 **사용자 세이브를 건드리지 않는다**.
			UserDB.begin_batch()
			var tw_scene := Scenes.current_scene()
			for q in (tw_scene.get("_QUESTS") as Array):
				UserDB.claim_quest(String((q as Dictionary)["key"]))
			for c2 in tw_scene.get_children():
				if c2 is CanvasLayer and (c2 as CanvasLayer).layer == 30: c2.queue_free()
			for i in 5: await get_tree().process_frame
			tw_scene.call("_open_quests")
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_questpop_done.png")
			print("WIRE shot_done=res://scratch_shots/_questpop_done.png")
			# 라온 도움 창(다이아 결제) — 미션을 다시 미완료로 되돌리고 연다.
			# 라온 도움은 **수락한 미션**이 대상이다(원작 getTargetQuest) → 하나 수락시켜 둔다.
			UserDB.set_pmeta("quests", {"date": Time.get_date_string_from_system()})
			UserDB.accept_quest("battles")
			for c3 in tw_scene.get_children():
				if c3 is CanvasLayer and (c3 as CanvasLayer).layer >= 30: c3.queue_free()
			for i in 5: await get_tree().process_frame
			tw_scene.call("_open_raon_help")
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://scratch_shots/_raonhelp.png")
			print("WIRE shot_raon=res://scratch_shots/_raonhelp.png")
			# 결제 경로 검증: 확인 누르면 다이아 차감 + 미션 완료 + 다음 요금 상승.
			var dia0 := UserDB.diamond()
			var okb := _find_label_button(tw_scene, "확인")
			if okb != null:
				okb.emit_signal("pressed")
				for i in 5: await get_tree().process_frame
				print("WIRE raon_pay dia=", dia0, "->", UserDB.diamond(),
					" cleared=", UserDB.quest_claimed("battles"),
					" cnt=", UserDB.quest_count("dia_clear"),
					" next_price=", tw_scene.call("_raon_price"))
			else:
				print("WIRE raon_pay: 확인 버튼 없음")
			get_tree().quit()
		"shop":
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("shop", {})
		"magicshop":
			# 점술집 1층 기능 팝업 검수. `--feat=<ITEMS[0] 인덱스>`
			#   0 드링크 강화 · 1 젬 강화 · 2 뽑기 · 3 카드 코드 · 4 드래곤 소환 · 5 연금술(층전환)
			# `--floor=1` = 지하(연금술 층). 지하 메뉴 = 혼성젬 강화 0 · 혼성젬 제작 1 ·
			#   젬 분해 2 · 용액 제작 3 · 용액 상점 4 (magicshop.gd AL_ITEMS 순서).
			# `--sands=1` = 샌즈의 눈물 2종을 지급(제작 화면 투입 칸 검수용).
			var feat := 3
			var ms_floor := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--feat="): feat = int(a.substr(7))
				elif a.begins_with("--floor="): ms_floor = int(a.substr(8))
				elif a == "--sands=1":
					UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
					UserDB.add_item("alchemy_platinum_01", 3)
					UserDB.add_item("alchemy_platinum_02", 2)
					for pk in ["hp_powder", "att_powder", "def_powder"]:
						UserDB.add_item(pk, 60)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("magicshop", {})
			# ⚠️ `get_tree().current_scene` 는 **main.tscn 루트**다 — 씬 매니저가 관리하는
			#    화면은 `Scenes.current_scene()` 로 잡아야 한다(이걸 틀리면 팝업이 조용히
			#    안 열려 메뉴 격자만 찍힌다). 프레임 수로 어림하지 말고 실제로 뜰 때까지 기다린다.
			# ⚠️ `Scenes.current_scene()` 는 **add_child 전에** 이미 새 씬을 가리킨다.
			#    그때 `_open_feature` 를 부르면 뒤이어 도는 `_ready` → `_rebuild()` 가
			#    자식을 전부 queue_free 해서 팝업이 조용히 사라진다(메뉴 격자만 찍힌다).
			#    트리에 들어가 `_ready` 까지 끝난 뒤에 부른다.
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
				# `--pick=<n>` : 샌즈의 눈물 투입 칸을 n 번 눌러 둔다(1=10%, 2=20%, 3=미투입).
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--pick="):
						for _p in int(a.substr(7)):
							ms.call("_cycle_sands")
							for i in 6: await get_tree().process_frame
				print("SHOT magicshop: floor=", ms.get("_floor"), " feat=", feat,
					" 눈물=", ms.get("_sands_key"),
					" 확률=", Gem.sands_chance(Data.gems, ms.call("_sands_bonus_pct")))
				# --reveal=<드래곤id> : 알 획득 공개창(코드 보상·소환이 쓰는 것)을 띄운다.
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--reveal="):
						ms.set("_egg_reveal", [int(a.substr(9))])
						ms.call("_reveal_eggs", "코드에 응답하여 %s의 알이 나타났습니다.")
						for i in 20: await get_tree().process_frame
				# --redeem=<코드> : 카드 코드 판정을 실제로 돌려 **사용제한(N회)** 을 검수한다.
				#   같은 코드를 4번 넣어 N번째까지만 통과하는지 본다.
				#   ⚠️ begin_batch = 디스크 미기록. 세이브(보상·사용이력)는 건드리지 않는다.
				#   ⚠️ 코드 평문은 인자로만 받고 로그에는 **결과만** 남긴다(코드가 콘솔에 남지 않게).
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
				# --pickmat : 재료만 올려 둔다(소환은 하지 않는다) — 받침대 위 스파인 검수용.
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
				# --summon : 실제 소환을 끝까지 돌린다(해금 플래그 + 재료를 검수용으로 채운다).
				#            ⚠️ begin_batch = 디스크 미기록. 세이브는 건드리지 않는다.
				if OS.get_cmdline_user_args().has("--summon"):
					UserDB.begin_batch()
					UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
					# 재료 자격(레벨 45 · 등급 10.0)을 넘는 개체가 세이브에 없을 수 있으므로
					# 검수용으로 레벨을 올려 준다(begin_batch = 디스크 미기록).
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
					# 종 이름이 재료를 따라가는지(사용자 확정 2026-07-30) — 둥지 표시명까지 확인.
					var sp_id := int(ms.get("_summon_species"))
					print("SHOT summon: 재료='", mat_name, "'  종이름(", sp_id, ")='",
						UserDB.species_name(sp_id), "'  Icons.species_name='",
						Icons.species_name(sp_id), "'")
					for d in UserDB.dragons():
						if int(d.get("id", 0)) == sp_id:
							print("SHOT summon: 둥지 표시명='", Icons.name_of(d),
								"' 알=", UserDB.is_egg(d))
				# --pull=<n> : 뽑기(잭팟) 실행까지 검수. 릴은 2.0+i×0.5 초에 순차 정지하므로
				#   결과를 보려면 --wait 를 3초 이상 준다.
				for pa in OS.get_cmdline_user_args():
					if pa.begins_with("--pull=") and ms.has_method("_pull_slot"):
						UserDB.begin_batch()          # ⚠️ 검수용 — 디스크에 쓰지 않는다
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
			# 하루 1회 던전 초과입장 확인창 검수 — 오늘 자 도장을 미리 찍고 던전 팝업을 연다.
			Scenes.goto("worldmap", {"region": "uno"})
			for i in 30: await get_tree().process_frame
			var wu := _find_method_node(get_tree().root, "_open_dungeon_popup")
			if wu != null:
				UserDB.begin_batch()          # ⚠️ 검수용 — 디스크에 쓰지 않는다
				var sid := stage if stage != "1" else "24"
				print("SHOT daily(before stamp) ok=", wu.call("_daily_ok", sid))
				wu.call("_daily_stamp", sid)
				print("SHOT daily(after  stamp) ok=", wu.call("_daily_ok", sid))
				wu.call("_open_dungeon_popup", sid)
				for i in 10: await get_tree().process_frame
				# 팝업의 '일반'은 9patch 로 만든 커스텀 Control 이라 Button 검색으로 못 잡는다
				# → 초과입장 확인창을 직접 띄워 그림만 검수한다.
				wu.call("_confirm_daily_extra", Callable(), false)
			else: print("SHOT: worldmap 아님")
		"mamomenu":
			# 후기판 메인 카드 메뉴(연구소메인.png) — 탭 인자 없이 진입(지역맵 경로와 동일).
			Scenes.goto("mamorudiclab", {})
		"mamosmelt":
			# 아티펙트 제련(원작 `ArtifactBox` → `OptionSelectLayer` 모드 2) 검수.
			# 재료(아니마·보네르)와 레어 이상 아티팩트를 지급하고 목록을 연다.
			# ⚠️ begin_batch 로만 만지고 save() 하지 않는다(사용자 세이브 오염 금지).
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
			# 마모루딕 연구소 탭 0(드래곤 각성) — 제단 스파인 + 각성 도감 + 제목/탭/재화/NPC.
			Scenes.goto("mamorudiclab", {"tab": 0})
		"mamostone":
			# 탭 1(각성마석 제작) — 화로 스파인 + 손가락 + 진행 게이지.
			# 5성 마석을 고른 상태로 만들어 게이지가 `10230/20000` 처럼 나오게 한다.
			UserDB.begin_batch()          # ⚠️ 검수용 — 디스크에 쓰지 않는다
			UserDB.set_pmeta("awaken_stone", {"star": 5, "points": 10230})
			Scenes.goto("mamorudiclab", {"tab": 1})
		"mamostonemake":
			# 각성의마석 제작 팝업 — 알 목록·포인트·"a + b / c" 머리글.
			# --stage2=over : 목표 직전(19500/20000)까지 채운 상태에서 알을 넣고 `강화` →
			#   초과 경고가 **한 번** 뜨고 확인하면 제작이 진행되는지 검수(2026-07-30 규칙 변경).
			# --stage2=done : 그 경고까지 확인해 **제작 성공 팝업**(원작 MakeMasicStonePopup)까지 본다.
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
				# 우측 패널의 ▲(TextureButton)를 눌러 1개 투입 → 목표 초과 상태를 만든다.
				# ⚠️ 트리 전체에서 찾으면 **씬의 뒤로가기 버튼**이 먼저 걸린다(월드맵으로 나가 버렸다)
				#    → 팝업(OrigPopup = `add_action_button` 보유) 하위에서만 찾는다.
				var spop := _find_method_node(get_tree().root, "add_action_button")
				var ups: Array = []
				if spop != null: _all_texture_buttons(spop, ups)
				# 닫기(×)가 0번이므로 ▲ 는 그 다음이다.
				if ups.size() >= 2: (ups[1] as TextureButton).emit_signal("pressed")
				else: print("SHOT: ▲ 버튼 못 찾음 (", ups.size(), ")")
				for i in 10: await get_tree().process_frame
				# `강화` 는 OrigPopup.add_action_button = Label + 투명 Button 구조다.
				_press_label_button(get_tree().root, "강화")
				for i in 15: await get_tree().process_frame
				if done_case:
					# 초과 경고의 `확인` → commit → 제작 성공 팝업.
					_press_label_button(get_tree().root, "확인")
					for i in 30: await get_tree().process_frame
		"mamoselect":
			# 드래곤 선택(원작 DragonAwakeSelectLayer) — 카드 + 재료 충족표 + 안내문.
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
			# 각성 도감(원작 AwakenDragonLayer) — 격자 + 우측 상세 + 속성 필터.
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
			# 던전 정보 팝업 리팩토링 검수 — 보상 아이템 줄(개수 + 영웅 H) + 입장 횟수 줄.
			Scenes.goto("worldmap", {"region": "uno"})
			for i in 30: await get_tree().process_frame
			var up := _find_method_node(get_tree().root, "_open_dungeon_popup")
			if up != null: up.call("_open_dungeon_popup", stage if stage != "1" else "24")
			else: print("SHOT: worldmap 아님")
		"awakenpop":
			# 각성 확인 팝업(원작 AwakenPopup) 검수 — 마모루딕 연구소에서 대상 하나를 골라 연다.
			# 재료 충족표(레벨/아니마/보네르/마석)가 ○✕ 로 나와야 한다.
			Scenes.goto("mamorudiclab", {"from": "worldmap"})
			for i in 30: await get_tree().process_frame
			var ml := _find_method_node(get_tree().root, "_open_awaken_confirm")
			if ml != null:
				UserDB.begin_batch()      # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
				for k in ["anima", "bonner"]:
					UserDB.add_item(k, 40)
				UserDB.add_item("evol_jewel_5", 2)
				var cand: Array = UserDB.dragons().filter(func(d):
					return not UserDB.is_egg(d) and not bool(d.get("awakened", false)))
				if cand.is_empty(): print("SHOT: 각성 대상 없음")
				else: ml.call("_open_awaken_confirm", cand[0])
			else: print("SHOT: mamorudiclab 아님")
		"dragongate":
			# 🔴 회귀: 던전 입장 검사는 **선택 중인 드래곤 한 마리만** 보고(원작
			#   `WorldMapPopupLayer::getDragonStatus`), 불능이면 다른 드래곤으로 대체하지 않고
			#   원작 팝업(`setDragonStun` 다이아 즉시부활 / `setDragonFood` 먹이)을 띄운다.
			#   종전 버그: 굶거나 행동불능이면 멀쩡한 다른 드래곤이 대신 출전했다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			var dg := _find_method_node(get_tree().root, "_selected_gate")
			if dg == null:
				print("SHOT: worldmap 아님")
			else:
				UserDB.begin_batch()      # ⚠️ 검수용 조작 — 디스크에 쓰지 않는다
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
				# 같은 속성 먹이를 지급하면 '상점 이동'이 아니라 '사용' 팝업이어야 한다.
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
					# 확인을 눌러 실제로 먹는지(FOOD 회복 + 아이템 1개 소모) 확인한다.
					var dhad := int(UserDB.inventory().get(dfeed, 0))
					for db2 in _all_buttons(dg):
						if (db2 as Button).text == "확인":
							(db2 as Button).emit_signal("pressed"); break
					print("SHOT dragongate 먹인 뒤: food=",
						int(UserDB.get_dragon(duid).get("food", -1)), "/", dfmax,
						" 먹이 ", dhad, "→", int(UserDB.inventory().get(dfeed, 0)))
				UserDB.set_dragon_field(duid, "food", dfmax)
		"cardgate":
			# 🔴 회귀: 일반 스테이지(1)에서는 Dungeon 계열 이벤트가 **뜨면 안 된다**.
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
			# 탐험 이벤트로서의 카드게임 검수 — 진입 훅(_open_cardgame)을 직접 호출한다.
			# --stage2=match|avoid 로 종류를 고른다(--stage 는 던전 id 로 이미 쓰인다).
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("adventure", {"stage": "6", "region": "yutakan", "enc": 0,
				"hp_state": {}, "streak": 0})
			for i in 30: await get_tree().process_frame
			# 게이트 검증도 함께 — 일반 스테이지에서는 _maybe_* 가 아무것도 안 띄워야 한다.
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
			# 탐험 카드 미니게임 검수. --stage=match|avoid 로 두 종류를 고른다.
			# 진입 훅(해골요새 카드 칸)은 아직 없으므로 여기서 직접 띄운다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			var cg_mode := stage if (stage == "match" or stage == "avoid") else "match"
			var cg := CardMiniGame.open(get_tree().current_scene, cg_mode,
				func(res): print("SHOT cardgame result=", res))
			for i in 20: await get_tree().process_frame
			# --pick=a,b 로 카드를 뒤집어 앞면·짝판정까지 검수한다.
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--pick="):
					for sidx in a.substr(7).split(","):
						if is_instance_valid(cg):
							cg.call("_on_pick", int(sidx))
							await get_tree().create_timer(0.7).timeout
			# 덱 내용을 로그로도 남긴다(앞면이 무엇인지 눈으로 못 볼 때 대조용).
			if is_instance_valid(cg):
				var dk = cg.get("_deck")
				if dk is Dictionary:
					var ks: Array = []
					for c in (dk.get("cards", []) as Array):
						ks.append(String(c.get("label", "?")))
					print("SHOT cardgame deck=", ks)
		"shopbuy", "shopbuymax":
			# 구매 수량 카운터(원작 ItemDetailLayer ◀ N ▶) 검수 — 첫 상품 카드를 눌러 팝업을 연다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("shop", {"tab": stage if stage != "1" else "food"})
			for i in 30: await get_tree().process_frame
			var sh := _find_method_node(get_tree().root, "_on_card")
			if sh != null:
				var ents: Array = sh.call("_entries")
				if ents.is_empty(): print("SHOT: 진열 상품 없음")
				else: sh.call("_on_card", ents[0])
				# shopbuymax = MAX 버튼을 눌러 수량·총액이 실제로 바뀌는지 확인
				if shot == "shopbuymax":
					for i in 10: await get_tree().process_frame
					var mb := _find_button_text(get_tree().root, "MAX")
					if mb == null:
						print("SHOT: MAX 버튼 없음")
					else:
						mb.emit_signal("pressed")
						await get_tree().process_frame
			else: print("SHOT: shop 씬 아님")
		"shophot", "shopfood", "shopitem", "shopegg", "shopetc", "shopsell":
			# 원작 ShopScene 탭별 검수. 탭 id = data/shop.json `tabs[].id`.
			#   (구 `shopgem/shopequip/shopgacha` 는 젬·장비·뽑기가 ITEM 탭으로,
			#    환전이 ETC 탭으로 접히면서 `shopitem`/`shopetc` 로 대체됐다.)
			# `--extra=owned` = 영구 1회 상품(축복받은 둥지)을 이미 산 상태로 진입 —
			#   진열 제외(원작 ShopScene.c:4180-4186 의 getNestLevel 필터)를 검수한다.
			if extra == "owned":
				UserDB.begin_batch()          # 검수용 — save() 안 함
				UserDB.set_pmeta("blessed_nest", true)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 8: await get_tree().process_frame
			Scenes.goto("town", {"area": "elpis"})
			for i in 12: await get_tree().process_frame
			Scenes.goto("shop", {"tab": shot.substr(4)})
		"gachapull":
			# 장비 10연속 뽑기 실행 → 결과 팝업 + 이벤트 장비가 실제로 인벤에 들어오는지.
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
				UserDB.begin_batch()          # 검수용 — save() 안 함
				UserDB.add_currency("diamond", 2000)
				var before := 0
				for k in UserDB.inventory().keys():
					if String(k).begins_with("equip:event:"): before += int(UserDB.inventory()[k])
				gp.call("_confirm_gacha", {"pool": "equip", "price": 0, "cur": "diamond",
					"n": 10, "label": "장비 뽑기 10연속"})
				for i in 6: await get_tree().process_frame
				# 상세 팝업(원작 ItemDetailLayer)의 실행 버튼을 눌러 실제로 뽑는다.
				# ⚠️ 2026-07-30 이식 후 버튼 문구는 '확인'이 아니라 동작명('뽑기')이고,
				#    라벨과 투명 Button 이 분리돼 있어 `_find_label_button` 으로 잡는다.
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
			# 메인 화면(유타칸) — 좌상단 프로필 / 우상단 재화 / 하단 메뉴바 검수.
			# ⚠️ 닉네임·칭호는 검수용으로만 채운다 — begin_batch 로 **디스크에 쓰지 않는다**.
			UserDB.begin_batch()
			if not UserDB.has_user_nickname():
				UserDB.set_user_nickname("계란")
			if UserDB.user_title_no() <= 0:
				UserDB.set_pmeta("title_no", 1)
			UserDB.set_pmeta("yutakan_night", shot == "main_night")
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
		"setting":
			# 설정창(원작 SettingLayer 이식) 검수 — 원작 진입점 그대로 **메인 화면 위**에서 띄운다.
			#   --stage=confirm : '세이브 데이터 초기화' 를 눌러 확인 팝업(PopupType)까지 본다.
			#                     ⚠️ 확인창의 '초기화' 는 누르지 않는다 — 진짜 세이브가 날아간다.
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
					# ⚠️ **진짜로 세이브를 지운다** — 확인창의 '초기화'까지 누른다.
					#    초기화 = 새 게임(Main.begin_new_game)이 다시 도는지 검증하는 모드다:
					#    초기 로드아웃(튜토리얼 보상)과 닉네임 팝업이 살아나야 한다.
					#    돌리기 전에 user://save_0.json 을 따로 복사해 둘 것.
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
			# 메인 하단 메뉴 → 각 씬 라우팅 검수. --stage=<action> (shop/laboratory/magicshop/
			# breeding/dex/bag/quests/titles/status/cashshop/overview).
			for i in 30: await get_tree().process_frame
			var hud := _find_method_node(get_tree().root, "_act")
			if hud == null:
				print("SHOT: MainHud 없음")
			else:
				hud.call("_act", stage)
				for i in 40: await get_tree().process_frame
				print("SHOT nav -> state=", Scenes.current_state())
		"intro":
			# 게임 시작 화면(원작 IntroScene 이식) 검수 — 부팅 첫 화면이라 별도 이동이 없다.
			#   --stage=start : "화면을 터치해주세요"를 눌러 게임 진입까지 본다.
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
			# 닉네임 팝업(NickNameLayer) 검수. 세이브에 닉네임이 있으면 '변경' 모드로 강제한다.
			#   --stage=confirm : 입력 후 확인을 눌러 **저장까지** 확인(IME 조합 함정 회귀용).
			#                     ⚠️ 위에서 begin_batch 를 걸어 뒀으므로 디스크에는 안 쓴다.
			for i in 20: await get_tree().process_frame
			NickNamePopup.open(get_tree().root.get_node("Main"), false)
			if stage == "confirm":
				# ⚠️ **디스크 보호** — 이 검수는 진짜 닉네임을 덮어쓴다. 위쪽 begin_batch 는
				#    닉네임이 이미 있으면 걸리지 않으므로(2026-07-31 실제로 사용자 세이브를
				#    덮어써 복구했다) 여기서 무조건 배치 모드로 만든다.
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
			# 일일 퀘스트 탭 — 미션 창은 2026-07-30 부터 `MissionLayer`(어느 씬 위에서든) 다.
			for i in 30: await get_tree().process_frame
			MissionLayer.open(get_tree().current_scene, 0, "worldmap", {})
			for i in 5: await get_tree().process_frame
		"inven":
			# ⚠️ 2026-07-31 수정: goto 없이 30프레임만 기다려서 **월드맵**에 서 있었고
			#   `_open_inventory` 를 못 찾아 조용히 빈 화면을 찍고 있었다. 가방은 동굴 소유다.
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var iv := _find_method_node(get_tree().root, "_open_inventory")
			if iv != null: iv.call("_open_inventory")
			else: print("SHOT: _open_inventory 노드 없음")
		"invenegg":
			# 가방 **알 탭** 상세창 검수(원작 `BagPopup::onClickItem` case 3 이식).
			#   --did=<드래곤id> : 그 드래곤 알을 고른다(기본 1)
			#   --gacha=1        : 드래곤이 정해지지 않은 '의문의 알'(별·유형 없음 분기)
			#   --grade=0        : 강화 등급을 심지 않는다(ani_egg_up1 애니 off 확인용)
			#   --sel=<등급>     : 그 등급 칸을 선택한 상태로 연다(v15 = 등급별 인벤 칸, EggItem)
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
			var ie_did := 1
			var ie_gacha := false
			var ie_grade := true
			for a3 in OS.get_cmdline_user_args():
				if a3.begins_with("--did="): ie_did = int(a3.substr(6))
				elif a3 == "--gacha=1": ie_gacha = true
				elif a3 == "--grade=0": ie_grade = false
			var ie_sel := 0                    # --sel=<등급> : 그 등급 칸을 선택한 상태로 연다
			for a4 in OS.get_cmdline_user_args():
				if a4.begins_with("--sel="): ie_sel = int(a4.substr(6))
			var ie_key := "mall_question_egg" if ie_gacha else EggItem.key(
				EggGacha.key_for(ie_did), ie_sel)
			var ie_base := EggItem.base_of(ie_key)
			UserDB.add_item(ie_key, 3)
			UserDB.add_item(ie_base, 3)
			if ie_grade and not ie_gacha:
				# v15: 등급은 인벤 키에 실린다(EggItem) — 등급별 칸을 직접 채운다.
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
			# 가방 **알 이외 탭** 상세창 검수 — 원작 `BagPopup::onClickItem`
			# case 0(FOOD) / 1(EQUIP) / 2·5·6·7(GEM·DOC·MTR·ETC) / default(SKILL) 이식.
			#   --tab=<food|gear|gem|skill|doc|mtr|etc>   (기본 food)
			#   --key=<인벤키>                            (생략하면 그 탭 첫 칸)
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
			var id_uid := UserDB.active_uid()
			for k in ["food_fire_chicken", "att_drink1",          # FOOD(속성 먹이 / 드링크)
					"eggmix1", "mix_book",                        # DOC
					"anima", "crystal2_chaos",                    # MTR(속성 있는 재료 = 아이콘 없어야 원작)
					"ascension", "bless_of_amor",                 # ETC
					"gem:공격의 젬:3", "gem:공격의 소울젬:2",       # GEM
					Loadout.item_key(13, 2),                      # SKILL(○ 복수의 거울)
					Loadout.item_key(11, 1),                      # SKILL(△ 철갑 방패)
					"equip:basic:발톱:0",                          # EQUIP(메타 없음 = 일반)
					"equip:artifact:루멘:5",                       # EQUIP(아티팩트)
					# EQUIP(희귀도 4 유니크 + 강화 2 + 귀속 + 부가옵션 2) — 토큰 순서 b→r→e→o
					"equip:b%d,r4,e2,oA7.P5@basic:깃털:6" % id_uid]:
				UserDB.add_item(k, 2)
			var id_tab := "food"
			var id_key := ""
			var id_gridx := -1        # --gridx=<px> : 그리드를 그만큼 가로 스크롤(행 넘침 확인용)
			var id_fill := false      # --fill=1    : items.json 전 항목 지급(가로 스크롤 발생시키기)
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
				idv.set("_inv_selected", id_key)   # ""면 refresh 가 그 탭 첫 칸을 고른다
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
			# 자작 드래곤(666 샛별 · 777 한울) 인게임 검수 — 지급 → 각성 → 전투 진입.
			# 아트 별칭(build_dragon_art_alias.py)과 각성스킬 효과가 실제로 붙는지 본다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 15: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
			var cids: Array = []
			for did in [666, 777]:
				var rec := UserDB.add_dragon(did, 1)
				var uid := int(rec.get("uid", 0))
				if uid <= 0: continue
				# 레벨업 롤을 실제로 태워 Lv50 까지 올린다 — add_dragon(did,50) 만 하면
				# gain_log 가 비어 있어 **1레벨 기준선 스탯**만 남는다(스탯이 낮아 보이던 원인).
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
			# 각성 스킬 효과 배선 검수(2026-07-29). 파티를 강제로 각성시켜 전투에 넣고,
			# `_awaken_fired`(실제 발동 목록)와 스탯 변화를 찍는다.
			# --stage=<던전> 으로 필드 속성 조건(4·6~10)도 볼 수 있다.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 10: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
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
			# 연구소 알 강화 + 가방 재료 제련 검수(2026-07-30, docs/ref/porting/LaboratoryEggUpgrade.md).
			#   --stage=lab     알 강화 팝업(알 선택 + 재료 3칸 충족)
			#   --stage=empty   알 미선택 상태(원작 알강화.png 와 대조)
			#   --stage=select  알 선택창(종류 × 강화 등급)
			#   --stage=smelt   가방 → 조각난 정령석 → 제련 팝업
			UserDB.begin_batch()   # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
			for pair in [["mall_back_egg", 3], ["stone_spirit2", 30], ["stone_heart2", 30],
					["crystal_light", 30], ["stone_spirit1", 40], ["stone_heart1", 40]]:
				UserDB.add_item(String(pair[0]), int(pair[1]))
			if stage == "run":
				# 끝단 검증: 강화 실행 → 등급 곁 테이블 → 부화 시 확정 등급/배지까지.
				Scenes.goto("laboratory")
				for i in 30: await get_tree().process_frame
				var rl := _find_method_node(get_tree().root, "_upgrade_egg")
				if rl == null:
					print("SHOT: _upgrade_egg 노드 없음")
				else:
					rl.set("_sel_egg_up", "mall_back_egg")   # v15: 선택 id = 인벤 키 그대로
					rl.call("_open_feature", 0)
					for i in 5: await get_tree().process_frame
					var g0 := UserDB.gold()
					rl.call("_upgrade_egg")
					print("SHOT eggup: 1강=", UserDB.item_count("mall_back_egg#1"),
						" 0강=", UserDB.item_count("mall_back_egg"),
						" 정령석=", UserDB.item_count("stone_spirit2"),
						" 골드차=", g0 - UserDB.gold())
					rl.call("_upgrade_egg")     # 1강 → 2강 (연속 강화)
					print("SHOT eggup2: 2강=", UserDB.item_count("mall_back_egg#2"),
						" 완벽한정령석=", UserDB.item_count("stone_spirit3"))
					Scenes.goto("worldmap", {"region": "yutakan"})   # 연구소 → 동굴은 허브 경유
					for i in 20: await get_tree().process_frame
					Scenes.goto("cave")
					for i in 30: await get_tree().process_frame
					var hc := _find_method_node(get_tree().root, "_start_hatch")
					if hc == null:
						print("SHOT: _start_hatch 노드 없음")
					else:
						hc.call("_start_hatch", "mall_back_egg#2")   # v15: 2강 칸을 그대로 부화
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
				# 1강 알 1개를 미리 만들어 두고(등급 곁 테이블) 2강 재료가 보이게 한다.
				UserDB.add_item("mall_back_egg#1", 1)   # v15: 등급별 인벤 칸
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
			# 가방 상세의 **용도** 표기 검수(2026-07-29). docs/input/items/groups.csv 39분류 답이
			# items.json `use` 로 들어갔고, 상세 패널이 "용도: …" 를 찍는다.
			# --stage=<아이템키> 로 대상 지정(기본 = 원작에도 더미인 '에너지 드링크').
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
			var uk: String = stage if stage != "1" else "energy_drink"
			UserDB.add_item(uk, 3)
			var ivu := _find_method_node(get_tree().root, "_open_inventory")
			if ivu != null:
				ivu.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				ivu.call("_inventory_select", uk)
			else: print("SHOT: _open_inventory 노드 없음")
		"skillscroll":
			# 에자녹 스크롤 → 스킬 아이템 → 습득 흐름 검수(2026-07-29, docs/ref/porting/SkillScroll.md).
			#   --stage=scroll        무작위 스크롤 상세(확인 팝업까지)
			#   --stage=book          선택 스크롤 → 스킬 목록 팝업
			#   --stage=item          스킬 아이템 상세('스킬' 탭)
			#   --stage=equip         스킬 칸 클릭 → 장착 목록
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
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
						# 학습 풀을 채워 두고 0번 칸 장착 목록을 연다.
						var su := UserDB.active_uid()
						var sp: Array = UserDB.dragon_skills(su)
						# ⚠️ 순차 학습(Loadout.can_learn) 때문에 Lv.1 부터 차례로 올려야 한다.
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
			# 가방 알 탭 `M` 배지 검수. 배지 조건(오라성체 도달 기록)은 아직 세우는 곳이 없으므로
			# (오라성체 진화 ⚪미구현) 여기서 직접 기록해 대조군과 함께 그린다:
			#   54·175 = 기록 있음(M) / 34·4021 = 기록 없음 / chaos = 속성알(dragon_id 없음)
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 지급이므로 **디스크에 쓰지 않는다**(사용자 세이브 오염 금지)
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
			# 뽑기 알 개봉 검수 — 가방 알 탭에서 '빛나는 의문의 알' 을 골라 사용한다.
			# --stage=<아이템키> 로 다른 뽑기 알(의문의 알·속성알)도 볼 수 있다.
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
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
			# 검은 섬(스테이지 24) 관문의 수호자 검수(2026-07-30) —
			#   스탯 = 기본(543/180/130) × (출전 드래곤 수)² · 영웅에서만 철갑 방패(11).
			#   --stage=<마리수>(1~3, 기본 3) · --stage2=hero → 영웅 난이도
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
			# 이름 바꾸기 관문(깃펜) 검수 — `--stage2=have` 면 드래곤 포스를 미리 쥐여 준다.
			#   보유  → 확인 팝업("1개를 사용합니다")
			#   미보유 → 구매 팝업(상점표 가격)
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 — 디스크에 쓰지 않는다
			var rn := _find_method_node(get_tree().root, "_rename_gate")
			if rn != null:
				if OS.get_cmdline_user_args().has("--stage2=have"):
					UserDB.add_item("dragon_namechange", 2)
				else:
					UserDB.use_item("dragon_namechange",
						UserDB.item_count("dragon_namechange"))   # 0 으로 비운다
				rn.call("_rename_gate")
			else: print("SHOT: _rename_gate 노드 없음")
		"eggreveal":
			# 알 획득 공개창(`EggResultPopup`) 단독 검수 — 개봉/코드/소환이 **같은 창**을 쓴다.
			#   --stage=<드래곤id>(기본 1)
			# 뒤 후광이 계속 도는지 보려면 `--wait` 을 후광 1주기(14초)보다 크게 준다.
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			var rv := _find_method_node(get_tree().root, "_show_egg_result")
			if rv != null:
				rv.call("_show_egg_result", int(stage) if int(stage) > 0 else 1, "mall_question_egg2")
			else: print("SHOT: _show_egg_result 노드 없음")
		"eggopen10":
			# '10회 사용' 검수(2026-07-30) — 10개 이상 보유 시 상세창에 2번째 버튼이 붙고,
			# 누르면 확인 → 결과가 원작 다건 팝업(GetItemPopup)에 한 번에 뜬다.
			#   --stage=<아이템키>  기본 = 빛나는 의문의 알 / `jem_random` 도 같은 경로
			#   --stage2=go        확인까지 눌러 결과창을 띄운다(생략하면 버튼만 확인)
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()   # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
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
					# 확인 팝업(PopupType)의 '확인' 버튼을 찾아 눌러 결과창까지 간다.
					var okb := _find_button_text(get_tree().root, "확인")
					if okb != null: okb.emit_signal("pressed")
					else: print("SHOT: 확인 버튼 없음")
					for i in 20: await get_tree().process_frame
			else: print("SHOT: _open_inventory 노드 없음")
		"gemequip":
			# 가방 젬 탭 "장착" 검수(2026-07-30) — 원작 BagPopup::onClickConfirm case 2.
			# 젬 목록을 다시 띄우지 않고 **그 자리에서** 맞는 칸에 들어가야 한다.
			#   --stage=fit  : 칸 타입에 맞는 젬 → 장착 성공 + 토스트 + 가방 닫힘
			#   --stage=miss : 칸 타입에 안 맞는 젬 → 안내 모달(1버튼), 장착 안 됨
			Scenes.goto("cave")
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()      # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
			var ge_uid := UserDB.active_uid()
			# 3칸을 전부 ATT 로 고정하면 "맞는 젬 / 안 맞는 젬"을 확정적으로 만들 수 있다.
			# --stage=full 은 3칸을 미리 채워 "칸이 다 찼다" 토스트 경로를 태운다.
			var ge_pre = {"name": "공격의 젬", "tier": 1}
			UserDB.set_dragon_field(ge_uid, "gems", {"types": ["ATT", "ATT", "ATT"],
				"slots": [ge_pre, ge_pre, ge_pre] if stage == "full" else [null, null, null]})
			var ge_fit := "gem:공격의 젬:3"      # ATT → ATT 칸 OK
			var ge_miss := "gem:체력의 젬:0"     # HP  → ATT 칸 불가
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
			# 젬/장비 인벤토리 검수. 기존 세이브엔 없으므로 여기서 지급한다 —
			# ⚠️ begin_batch 로만 만지고 save() 하지 않는다(사용자 세이브 오염 금지).
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
					# ⚠️ 가방은 동굴 소유다 — goto 없이 월드맵에서 찾으면 노드가 없다.
					Scenes.goto("cave")
					for i in 30: await get_tree().process_frame
					var iw := _find_method_node(get_tree().root, "_open_inventory")
					if iw == null:
						print("SHOT: _open_inventory 노드 없음")
					else:
						iw.set("_inv_tab", "gem" if shot == "inven_gem" else "gear")
						iw.call("_open_inventory")
						for i in 20: await get_tree().process_frame
						# 장비 탭은 원작대로 [강화][옵션 변경] 2버튼이고 '장착'은 없다.
						if shot == "inven_gear":
							var gk := "equip:basic:묘안석:2"
							iw.call("_inventory_select", gk)
							for i in 15: await get_tree().process_frame
							print("SHOT inven_gear 강화=",
								_find_button_text(get_tree().root, "강화") != null,
								" 옵션변경=", _find_button_text(get_tree().root, "옵션 변경") != null,
								" 장착=", _find_button_text(get_tree().root, "장착") != null)
				"gemsel":
					# 동굴 하단 **빈 젬 칸**을 실제로 클릭 → 가방 '젬' 탭이 열려야 한다
					# (2026-07-30 사용자 확정: 자작 젬선택 팝업 폐기). 칸을 비워 두고 히트를 찾는다.
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
					# 동굴 장비 칸 → 원작 `ItemPopup` 이식본(2026-08-01, 자작 목록창 폐기).
					# ⚠️ 종전엔 goto 가 없어 월드맵에서 노드를 찾다 실패했다.
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
			# 축복 아이템을 **가방에서** 쓰는 흐름 검증: 기타 탭 → 아모르의 축복 선택 →
			# 버튼 라벨이 "사용" 인지 → 눌러서 대상 드래곤 목록이 뜨는지 → 적용 후 레벨이 올랐는지.
			for i in 30: await get_tree().process_frame
			UserDB.begin_batch()      # ⚠️ 검수용 — save() 하지 않는다
			UserDB.add_item("bless_of_amor", 3)
			var cv3 := _find_method_node(get_tree().root, "_open_inventory")
			cv3.set("_inv_tab", "etc")
			cv3.call("_open_inventory")
			for i in 20: await get_tree().process_frame
			cv3.call("_inventory_select", "bless_of_amor")
			for i in 20: await get_tree().process_frame
			var ub := _find_label_button(get_tree().root, "사용")
			print("SHOT bless use_button=", ub != null, " count=", UserDB.item_count("bless_of_amor"))
			if ub == null:
				print("SHOT bless FAIL: '사용' 버튼 없음")
			else:
				ub.emit_signal("pressed")
				for i in 25: await get_tree().process_frame
				var uid0 := UserDB.active_uid()
				var lv0 := int(UserDB.get_dragon(uid0).get("level", 0))
				# 대상 목록의 첫 버튼(활성 드래곤이 아닐 수도 있으니 uid 를 다시 읽는다)
				var first: BaseButton = null
				var stack: Array = [get_tree().root]
				while not stack.is_empty() and first == null:
					var n: Node = stack.pop_front()
					if n is Button and (n as Button).text.begins_with("Lv."): first = n
					for c in n.get_children(): stack.append(c)
				print("SHOT bless target_list=", first != null, " lv_before=", lv0)
				if first != null:
					first.emit_signal("pressed")
					for i in 40: await get_tree().process_frame
					print("SHOT bless after lv=", int(UserDB.get_dragon(UserDB.active_uid()).get("level", 0)),
						" count=", UserDB.item_count("bless_of_amor"))
		"storage":
			# 드래곤의 고삐 → 보관소 이동 → 상태창 '보관소' 버튼 → 꺼내기.
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
			# 드래곤의 승천: 드래곤 삭제 + 다이아 지급(기본 5, 5레벨당 +5).
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
			# 던전 팝업 → 일반 → 파티 편성 취소 → **던전 클릭 이전 상태로 복귀**하는지 검증.
			# (취소 후 월드맵이 줌인+_busy 로 잠기던 버그 회귀 방지)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
			var wmc := _find_method_node(get_tree().root, "_open_dungeon_popup")
			wmc.set("_busy", true)              # 실제 경로(_closeup_then_goto)와 동일한 상태
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
			# 위와 같은 흐름이되 **화면 구석을 실제로 클릭**해서 빠져나오는지 검증
			# (사용자 요청: "화면 아무 곳이나 터치하면 던전 클릭 전 상태로").
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 30: await get_tree().process_frame
			var wmd := _find_method_node(get_tree().root, "_open_dungeon_popup")
			wmd.set("_busy", true)
			wmd.call("_open_dungeon_popup", stage)
			for i in 20: await get_tree().process_frame
			# (1) 던전 팝업 단계에서 바깥 클릭
			_click_at(Vector2(30, 30))
			for i in 40: await get_tree().process_frame
			print("SHOT popup_outside_click busy=", wmd.get("_busy"),
				" popup_left=", _find_label_button(get_tree().root, "일반") != null,
				" scale=", wmd.get("_content").scale)
			# (2) 다시 열어 파티 편성까지 간 뒤 바깥 클릭
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
			# 던전 팝업 드래곤 슬롯 클릭 미리보기(onClickDragon) 검수.
			# --slot=<0부터> 로 누를 슬롯을 고른다. 캡처는 클릭 후 wait 시점.
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 40: await get_tree().process_frame
			var wmp := _find_method_node(get_tree().root, "_open_dungeon_popup")
			if wmp == null:
				print("SHOT: _open_dungeon_popup 노드 없음")
			else:
				wmp.call("_open_dungeon_popup", stage)
				for i in 25: await get_tree().process_frame
				# --slot=3 또는 --slot=3,0 (쉼표 = 순서대로 클릭, 사이 0.5s — 교체 검증용)
				var slot_list: Array = [0]
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--slot="):
						slot_list = Array(a.substr(7).split(",")).map(func(x): return int(x))
				# 팝업 레이어(layer=26)의 flat Button 중 슬롯 히트(정사각형 근처)만 모은다.
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
			# 임프상인 검수 — 보석을 넣고 **밤 월드맵의 스파인**을 눌러 오버레이를 연다.
			UserDB.begin_batch()
			for jk in ["jewel_amethyst", "jewel_emerald", "jewel_ruby", "jewel_sapphire"]:
				UserDB.add_item(jk, 60)
			Scenes.goto("worldmap", {"region": "yutakan", "night": true})
			for i in 30: await get_tree().process_frame
			var wm := _find_method_node(get_tree().root, "_open_imp_shop")
			if wm != null:
				# `--map=1` 이면 지도만 보고(스파인 위치 확인), 아니면 상점을 연다.
				var only_map := false
				for a3 in OS.get_cmdline_user_args():
					if a3 == "--map=1": only_map = true
				if not only_map:
					wm.call("_open_imp_shop")
			else:
				print("SHOT: _open_imp_shop 노드 없음")
		"lvpanel":
			# ⚠️ 게임은 메인(월드맵)으로 부팅한다 — 동굴로 먼저 가야 `_open_levelup` 이 있다.
			#   (2026-07-31: 이 모드가 "노드 없음"으로 조용히 빈 화면을 찍고 있었다.)
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var cv2 := _find_method_node(get_tree().root, "_open_levelup")
			if cv2 != null: cv2.call("_open_levelup")
			else: print("SHOT: _open_levelup 노드 없음")
		"awakenevol":
			# 각성(원작 '진화') 결과 연출 = EvolLayer 이식 검증.
			# `--at=<초>` 로 시퀀스의 특정 시점을 잡는다(날개가 솟는 구간은 2~4초).
			# ⚠️ begin_batch = 디스크 미기록(검증용 각성이 세이브에 남지 않게).
			UserDB.begin_batch()
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var aw_uid := UserDB.active_uid()
			UserDB.set_dragon_field(aw_uid, "awakened", false)
			var aw_cv := get_tree().current_scene
			var aw_vis := get_viewport().get_visible_rect().size
			EvolLayer.open(aw_cv, aw_uid, Vector2(aw_vis.x * 0.5, aw_vis.y * 0.5), Callable())
			var aw_d: Dictionary = UserDB.get_dragon(aw_uid)
			print("SHOT awaken: uid=", aw_uid, " id=", aw_d.get("id"), " lv=", aw_d.get("level"),
				"  각성체씬=", ResourceLoader.exists("res://scenes/dragons/dragon_%d_e.tscn" % int(aw_d.get("id", 0))))
		"lvevolve":
			# 진화 즉시 반영 검증 — 성장 단계 경계(레벨 10) 직전으로 맞추고 레벨 아이템을 실제로 클릭해,
			# 레벨업 화면의 좌측 드래곤 스파인이 **그 자리에서** 다음 단계로 바뀌는지 본다.
			# ⚠️ begin_batch = 디스크 미기록(검증용 레벨 조작이 세이브에 남지 않게).
			UserDB.begin_batch()
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var ev_cv := _find_method_node(get_tree().root, "_open_levelup")
			if ev_cv == null:
				print("SHOT: _open_levelup 노드 없음")
			else:
				var ev_uid := UserDB.active_uid()
				# 경계 직전(9)로 맞춘다. gain_log 불변식(level==1+size)도 함께 맞춘다.
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
			# 레벨 아이템 슬롯(아이콘 버튼) 실제 클릭 — 리롤과 같은 갱신 버그 계열이라 함께 검증한다.
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
			# 트리플맥스 컷인 검증 — 데르사의 축복(guarantee=triple)을 슬롯에서 실제로 클릭한다.
			# `--stage=baby|child|adult` 로 성장 단계를 강제한다(사용자 신고 2026-07-31:
			# 해치/해츨링에서 트리플맥스 컷인이 안 뜬다). begin_batch = 디스크 미기록.
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
					# 컷인은 타임라인 끝(3MAX 뱃지 착지)에 뜬다 — 최대 25초까지 **폴링**한다.
					# (종전 12프레임 고정 관측은 늘 이르러서 어느 단계든 빈손이었다.)
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
			# 리롤 버튼 재현 — 실제 마우스 이벤트를 주입해 "입력이 안 닿는가 / 표시가 안 바뀌는가"를 가른다.
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
					# ⚠️ get_global_rect() 는 캔버스 좌표다. Input.parse_input_event 는 화면 좌표를
					#    받으므로 스트레치 배율(창768 / 디자인692 ≈ 1.11)만큼 어긋난다 → get_screen_position().
					var rc := rr_btn as Control
					var canvas_c := rc.get_global_rect().get_center()
					var scr := get_viewport().get_screen_transform() * canvas_c   # 캔버스→화면
					print("SHOT reroll: canvas=", rc.get_global_rect(), " click(screen)=", scr,
						" disabled=", rr_btn.disabled, " visible=", rc.is_visible_in_tree())
					# 그 좌표에서 실제로 무엇이 입력을 먹는지(=히트테스트 승자) 이름을 찍는다.
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
					# 원작 DragonResetConfirm 확인창이 뜬다 → 확인을 눌러야 실제로 뽑힌다.
					print("SHOT reroll: 확인창 떴나 = ", _find_label_button(get_tree().root, "확인") != null)
					_press_label_button(get_tree().root, "확인")
					for i in 20: await get_tree().process_frame
					var rr_after: Array = UserDB.get_dragon(rr_uid).get("gain_log", [])
					print("SHOT reroll: gain_log last  before=",
						rr_before[rr_before.size() - 1] if not rr_before.is_empty() else "{}",
						"  after=", rr_after[rr_after.size() - 1] if not rr_after.is_empty() else "{}")
					print("SHOT reroll: 클릭으로 롤이 바뀌었나 = ", rr_before != rr_after,
						" / dia ", rr_dia, "->", UserDB.diamond(), " gold=", UserDB.gold())
					# 화면이 갱신됐는지 = 증가분 라벨 "(+d/m)" 이 새 롤을 반영하는가
					var texts: Array = []
					_collect_labels(get_tree().root, "(+", texts)   # 리롤 후 rr_btn 은 재생성돼 해제된다
					print("SHOT reroll: 화면 증가분 라벨 = ", texts)
		"lvup":
			for i in 30: await get_tree().process_frame
			var cv := _find_method_node(get_tree().root, "_open_training_result")
			if cv != null:
				cv.call("_open_training_result", 1, 10, 11)
			else:
				print("SHOT: _open_training_result 노드 없음")
		"promote_select":
			# 원작 TrainingSelectLayer 카드 목록 검수 — 훈련 캠프 1번을 눌러 선택창을 연다.
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("promote", {"tab": "train", "from": "town"})
			for i in 30: await get_tree().process_frame
			var ps := _find_method_node(get_tree().root, "_open_send")
			if ps != null: ps.call("_open_send", 0)
			else: print("SHOT: _open_send 노드 없음")
		"promote_train":
			# 원작 TrainingSelectCell(훈련 종류) 검수 — 드래곤 선택까지 진행한 뒤 캡처.
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			Scenes.goto("promote", {"tab": "train", "from": "town"})
			for i in 30: await get_tree().process_frame
			var pt := _find_method_node(get_tree().root, "_open_send")
			if pt != null:
				pt.call("_open_send", 0)
				for i in 10: await get_tree().process_frame
				for b in _all_buttons(get_tree().root):
					if b.size.x > 300.0 and b.size.y > 300.0:   # 선택 카드
						b.emit_signal("pressed"); break
			else: print("SHOT: _open_send 노드 없음")
		"mission":
			# 미션 창(원작 MissionLayer) — --tab=0 미션 / 1 스토리, --ep=N 배너 회차.
			# 원작대로 **메인 화면(월드맵) 위**에 띄운다(2026-07-30 이전에는 동굴 씬을 거쳤다).
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 20: await get_tree().process_frame
			var mt := 1
			var mep := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--tab="): mt = int(a.substr(6))
				elif a.begins_with("--ep="): mep = int(a.substr(5))
			var ml := MissionLayer.open(get_tree().current_scene, mt, "worldmap", {})
			if mep > 0:
				ml.set("_story_sel", mep)
				ml.call("_rebuild", mt)
			for i in 10: await get_tree().process_frame
		"storymark":
			# 월드맵 스토리 안내 화살표(원작 WorldMapLayer::setScenarioNotification, storyguide_arrow).
			# 표는 회차 79~146 만 담으므로, 78화까지 관람한 상태를 **메모리에만** 만든다
			# (begin_batch = 디스크 미기록 → 사용자 세이브 안전).
			UserDB.begin_batch()
			for n in range(1, 79): UserDB.set_progress("scenario_%d_0" % n, true)
			UserDB.set_progress("story_sq_79", 0)
			Scenes.goto("worldmap", {"region": "yutakan"})
			for i in 25: await get_tree().process_frame
			print("SHOT storymark: active=", StoryProgress.active_episode(),
				" spec=", StoryProgress.spec(StoryProgress.active_episode()),
				" mark_field=", StoryProgress.mark_field())
		"prologue":
			# 프롤로그 검수(원작 <PrologueTalk0~33> + scenario/prologue 삽화).
			#   --line=<i> : 그 줄부터(화자 초상 검수용)
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
			# 시나리오 **자동 발동** 검수(원작 WorldMapScene.c:21999 launchScenarioIfAvailable).
			# 흐름 데이터가 있는 첫 회차(79) 직전 상태를 메모리에만 만들고 메인 화면으로 간다.
			# 통과 = story 씬이 스스로 떠 있어야 한다.
			UserDB.begin_batch()
			for n in range(1, 79): UserDB.set_progress("scenario_%d_0" % n, true)
			UserDB.set_progress("story_sq_79", 99)      # 서브퀘스트 게이트 통과
			Scenes.goto("worldmap", {})                 # region 미지정 = 개요(메인 화면)
			for i in 30: await get_tree().process_frame
			var sa := get_tree().root.get_node_or_null("Main")
			var cur := "?"
			if sa != null and sa.get_child_count() > 0:
				cur = sa.get_child(sa.get_child_count() - 1).name
			print("SHOT storyauto: 다음회차=", StoryProgress.next_episode(),
				" 해금=", StoryProgress.unlocked(StoryProgress.next_episode()),
				" 현재씬=", cur)
			# --skip=1 이면 건너뛰기 확인 팝업까지 띄운다(원작 ScenarioSkipTitle).
			if OS.get_cmdline_user_args().has("--skip=1"):
				var sk := _find_method_node(get_tree().root, "_confirm_skip")
				if sk == null:
					print("SHOT storyauto: story 씬 없음")
				else:
					sk.call("_confirm_skip")
					for i in 15: await get_tree().process_frame
		"storyreward":
			# 회차별 특별보상(원작 ScenarioSpecialRewardPopup) — 26·58·78화. --ep=N 으로 고른다.
			# 지급은 멱등이라 이미 받았으면 안 뜨므로 검수용으로 수령 플래그를 지운다(begin_batch=디스크 미기록).
			var rep := 78
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--ep="): rep = int(a.substr(5))
			UserDB.begin_batch()
			UserDB.set_progress("story_reward_%d" % rep, false)
			Scenes.goto("story", {"no": rep, "part": 0, "back": "worldmap", "back_params": {}})
			for i in 20: await get_tree().process_frame
			# ⚠️ `current_scene` 은 Main 껍데기다 — 실제 스토리 노드는 그 자식이다.
			var sv := _find_method_node(get_tree().root, "_show_special_reward")
			if sv != null: sv.call("_finish")
			else: print("SHOT: story 노드 없음")
			for i in 20: await get_tree().process_frame
		"sound":
			# 구역 앰비언트 검수(원작 setWorldMapSound). 지역맵을 좌→우로 훑으며 어느 트랙이
			# 켜지는지, 그리고 다른 씬으로 나갔을 때 **전부 꺼지는지**를 출력한다.
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
		"promote", "promote_mate", "promote_nest":
			# 육성(원작 PromoteScene) — 훈련 캠프 / 라티아(교배) / 하늘둥지 탭.
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			var ptab: String = {"promote": "train", "promote_mate": "mate", "promote_nest": "nest"}[shot]
			Scenes.goto("promote", {"tab": ptab, "from": "town"})
		"magicshop", "laboratory", "shop", "mamorudiclab":
			# 씬 매니저의 허용 전이(scene_manager ALLOWED)가 town 경유만 허락한다 →
			# 바로 goto 하면 거부돼 동굴이 그대로 남는다(스크린샷이 조용히 엉뚱한 화면).
			Scenes.goto("town", {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			Scenes.goto(shot, {"area": "elpis"})
			for i in 10: await get_tree().process_frame
			# --floor=N(점술집 층) · --item=N(메뉴 카드 index)
			# ⚠️ 2026-07-28 구조 변경: 기능 화면은 이제 **원작대로 딤 팝업**이라
			#    `_tab` 을 세우고 `_rebuild` 해도 안 열린다 → `_open_feature(N)` 을 부른다.
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
				# --summonpick=1 : 드래곤 소환(--item=4)의 **드래곤 선택 목록** 검수.
				#   해금 플래그가 서 있어야 소환 본문이 그려진다(잠김이면 목록도 안 뜬다).
				# --summonuid=<uid> : 그 개체를 고른 상태로 본문을 다시 그린다(받침대 위 초상 검수).
				for a in OS.get_cmdline_user_args():
					if a == "--summonpick=1":
						sc.call("_open_summon_picker")
						for i in 20: await get_tree().process_frame
					elif a.begins_with("--summonuid="):
						sc.set("_summon_uid", int(a.split("=")[1]))
						sc.call("_refresh_feature")
						for i in 20: await get_tree().process_frame
				# --react=<N> : 반응 표정으로 대사 1줄 → 다음 대사에서 기본으로 돌아오는지 검수.
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
				# --face=<N> : NPC 를 그 표정으로 다시 만든다(얼굴 파츠 정렬 검수).
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
				# --emo=<N> : NPC 말풍선(이모티콘) 위치 검수. 웃는 표정으로 강제한 뒤 띄운다.
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--emo="):
						var np = sc.get("_npc")
						if np != null:
							np.set("emotion", 2)
							NpcEmoticon.show_on(np, int(a.split("=")[1]))
							for i in 30: await get_tree().process_frame
						else:
							print("SHOT: _npc 없음")
				# --skill=1 : 연구소 스킬 트리 팝업 검수
				for a in OS.get_cmdline_user_args():
					if a == "--skill=1" and sc.has_method("_show_lab_info"):
						sc.call("_show_lab_info")
						for i in 20: await get_tree().process_frame
				# --result=ok|fail : 젬 강화 결과 연출 검수
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--result=") and sc.has_method("_show_upgrade_result"):
						sc.call("_show_upgrade_result", a.substr(9) == "ok",
							"체력의 젬+104  체력 +104", "체력의 젬+108  체력 +108", null)
						for i in 20: await get_tree().process_frame
				# --sub=<아이템키> : 용액 상점 상품 상세 팝업 검수
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--sub=") and sc.has_method("_open_potion_buy"):
						sc.call("_open_potion_buy", a.substr(6), 25, "diamond")
						for i in 20: await get_tree().process_frame
		"slotreset":
			# 젬/스킬 슬롯 재추첨 검수(원작 ItemCommentPopup → ResetLayer,
			# docs/ref/porting/SlotResetScreens.md). --stage=gem|skill.
			# 시계열: 확인창 → 롤 중 → 흰 섬광 → 확정 → 결과문.
			Scenes.goto("cave", {})
			for i in 30: await get_tree().process_frame
			var srcv := _find_method_node(get_tree().root, "_apply_slot_reset")
			if srcv == null:
				print("SHOT slotreset: cave 노드 없음")
			else:
				UserDB.begin_batch()   # ⚠️ 검수용 지급 — 디스크에 쓰지 않는다
				var srkind := "skill" if stage == "skill" else "gem"
				var srkey := "skillslot_change" if srkind == "skill" else "gemslot_change"
				UserDB.add_item(srkey, 3)
				var sruid := UserDB.active_uid()
				var srd := UserDB.get_dragon(sruid)
				var srbefore := UserDB.get_dragon(sruid)
				# **실제 경로**로 들어간다 — 가방 → 아이템 사용 → 대상 선택 → 확인창.
				srcv.call("_open_inventory")
				for i in 10: await get_tree().process_frame
				srcv.call("_use_consumable", srkey,
					"skillslot" if srkind == "skill" else "gemslot")
				for i in 5: await get_tree().process_frame
				# 대상 선택 모달에서 활성 드래곤 줄을 누른다.
				var srname: String = Icons.name_of(srd)
				var srpicked := false
				for b in _all_buttons(srcv):
					if String((b as Button).text).find(srname) >= 0:
						(b as Button).pressed.emit(); srpicked = true
						break
				print("SHOT slotreset 대상선택=", srpicked, " (", srname, ")")
				var srpop := _find_node_of_class(srcv, "ItemCommentPopup")
				await get_tree().create_timer(1.0).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out.get_basename() + "_00.png")
				print("SHOT slotreset 확인창: ", out.get_basename() + "_00.png",
					"  before gems=", Gem.types(srbefore.get("gems", {})),
					" skill_slots=", Loadout.slot_types(srbefore))
				# 확인 버튼을 **팝업 안에서** 라벨로 찾아 누른다(배선까지 함께 검증).
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
			# 레벨업 연출 타임라인(원작 ExpLayer 안무) 검수 — 데르사 축복 = 트리플맥스 보장.
			# 시계열 캡처: 워드아트 비행 → 숫자 롤 → MAX 뱃지 → 컷인 → 슬롯개방 → 최종.
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
				# 이어서 리롤(reset 안무) 경로 1회 — gain_log 가 생겼으니 활성이다.
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
	print("SHOT bgm=", Bgm._cur)   # 씬별 BGM 선택 검증용(던전 BGM 회귀 잡기)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT saved: ", out)
	# `--noquit` = 상태만 세팅해 두고 **창을 닫지 않는다**(사용자가 직접 눈으로 보고 조작하는 검수용).
	if "--noquit" in OS.get_cmdline_user_args():
		print("SHOT: --noquit — 창을 유지한다")
		return
	get_tree().quit()

## 라벨 텍스트로 버튼 찾기(_popup_button 은 NinePatchRect + Label + 투명 Button 구조).
## 화면 좌표에 실제 마우스 클릭을 주입한다(히트테스트까지 태워 검증).
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
	if n is Button and (n as Button).text == text:   # TextureButton 엔 text 가 없다
		return n
	for c in n.get_children():
		var r := _find_label_button(c, text)
		if r != null: return r
	return null

func _press_label_button(n: Node, text: String) -> void:
	var b := _find_label_button(n, text)
	if b != null: b.emit_signal("pressed")
	else: print("SHOT: 버튼 없음 — ", text)

## sub 를 포함하는 Label 텍스트를 모은다(해제 예약된 노드는 제외 — 갱신 판정을 흐리지 않게).
func _collect_labels(n: Node, sub: String, out: Array) -> void:
	if n is Label and sub in (n as Label).text and not n.is_queued_for_deletion():
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_labels(c, sub, out)

## 툴팁이 prefix 로 시작하는 첫 Button(아이콘 버튼은 text 가 없다).
func _find_button_tooltip_prefix(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).tooltip_text.begins_with(prefix):
		return n
	for c in n.get_children():
		var r := _find_button_tooltip_prefix(c, prefix)
		if r != null: return r
	return null

## 텍스트가 prefix 로 시작하는 첫 Button(비용 표기가 붙는 버튼을 라벨 전문 없이 잡기 위함).
func _find_first_button_prefix(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var r := _find_first_button_prefix(c, prefix)
		if r != null: return r
	return null

## 서브트리에서 첫 드래곤 스파인 씬의 파일명(`dragon_<id>_<stage>`)을 찾는다.
## 진화 검증용 — "지금 서 있는 게 어느 성장 단계인가"를 노드에서 직접 읽는다.
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

## 지금 울리고 있는 구역 앰비언트(트랙 + 볼륨). "(없음)" 이면 전부 정지 상태.
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

## 기준선 뒤에 새로 붙은 팝업(CanvasLayer)의 라벨·버튼 문구 — 팝업 내용 검수용.
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

## 트리에서 그 스크립트 class_name 을 가진 첫 노드(팝업 인스턴스 찾기용).
func _find_node_of_class(n: Node, cls: String) -> Node:
	var sc: Variant = n.get_script()
	if sc is Script and String((sc as Script).get_global_name()) == cls:
		return n
	for c in n.get_children():
		var r := _find_node_of_class(c, cls)
		if r != null: return r
	return null

## `_find_node_of_class` 는 **스크립트 global name** 으로 찾는다(class_name 있는 우리 클래스).
## 내장 타입(LineEdit 등)은 스크립트가 없으므로 이쪽을 쓴다.
func _find_builtin(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _find_builtin(c, cls)
		if r != null: return r
	return null

func _find_node_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm: return n
	for c in n.get_children():
		var r := _find_node_named(c, nm)
		if r != null: return r
	return null

## 트리 안의 모든 Button (검수용 클릭 시뮬레이션).
func _all_buttons(n: Node, out: Array = []) -> Array:
	if n is Button: out.append(n)
	for c in n.get_children(): _all_buttons(c, out)
	return out

## 트리 안의 모든 Label (라벨 문구로 UI 를 찾을 때).
func _all_labels(n: Node, out: Array = []) -> Array:
	if n is Label: out.append(n)
	for c in n.get_children(): _all_labels(c, out)
	return out

## 트리 안의 모든 TextureButton (▲▼ 처럼 라벨이 없는 버튼을 찾을 때).
func _all_texture_buttons(n: Node, out: Array = []) -> Array:
	if n is TextureButton: out.append(n)
	for c in n.get_children(): _all_texture_buttons(c, out)
	return out

## 조합 팀버프 검수용 — 보유 드래곤에서 **아이콘 있는 버프**를 발동시키는 3마리를 찾는다.
## 원작 판정과 같은 코드(`TeamBuff.active_buffs`)로 확인하므로 "고르면 반드시 뜬다".
func _pick_team_buff_party() -> Array:
	var table: Dictionary = Data.team_buffs
	var race_dim := String(table.get("race_dim", "element"))
	var owned: Array = UserDB.dragons()
	# 속성 → 그 속성 드래곤 uid 목록
	var by_elem: Dictionary = {}
	for d in owned:
		var e := String(Data.get_dragon(int(d["id"])).get(race_dim, ""))
		if e == "": continue
		if not by_elem.has(e): by_elem[e] = []
		(by_elem[e] as Array).append(int(d["uid"]))
	for b in (table.get("buffs", []) as Array):
		var buff: Dictionary = b
		if String(buff.get("img", "")) == "": continue     # 아이콘 없는 25~30 은 연출을 생략한다
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


## 트리에서 그 메서드를 가진 첫 노드. `get_tree().current_scene` 이 Main 고정이라 필요하다.
func _node_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for c in n.get_children():
		var r := _node_with_method(c, m)
		if r != null:
			return r
	return null


## `equipslots` 촬영용 — 그 드래곤의 4칸을 열고 장비를 끼워 둔다(begin_batch 라 디스크 미기록).
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
