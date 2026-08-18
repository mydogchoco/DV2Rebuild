extends Control

const FLOOR := 692.0

var _pma: CanvasItemMaterial
var _adv: Dictionary = {}
var _params: Dictionary = {}
var _stage: Dictionary = {}
var _speed := 1.0
var _t := 0.0
var _dur := 1.8
var _done := false
var _healed := false
var _event_open := false
var _cam: Camera2D
var _walking := false
var _walk_sfx: AudioStreamPlayer
var _speed_btn: Button

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_adv = _man("adventure_ui")
	_rebuild()

func _explore_bgm() -> String:
	var b := String(_stage.get("bgm", ""))
	if b != "": return b
	var fid := DungeonBG.field_id(_stage)
	if fid > 0 and ResourceLoader.exists("res://assets/music/bg_%d.mp3" % fid):
		return "bg_%d" % fid
	var bfid := DungeonBG.base_field(fid)
	if bfid != fid and bfid > 0 and ResourceLoader.exists("res://assets/music/bg_%d.mp3" % bfid):
		return "bg_%d" % bfid
	var region := String(_stage.get("region", ""))
	if region == "":
		region = String(_params.get("region", "yutakan"))
	for r in Data.worldmap_regions():
		if String(r.get("id", "")) == region:
			var rb := String(r.get("bgm", ""))
			if rb != "": return rb
	return "bg_yutakan"

func _party_capacity() -> int:
	if bool(_params.get("hero", false)):
		return 3
	if bool(_stage.get("random_boss", false)) or bool(_stage.get("party3", false)):
		return 3
	return 1

var _run_party: Array = []

func _leader_party() -> Array:
	var uid := UserDB.active_uid()
	if uid > 0 and not UserDB.get_dragon(uid).is_empty():
		return [uid]
	return []

var _pending_levelup_after_party := false
func _open_party_select() -> void:
	_event_open = true
	_narrate(Data.ui("#0ffa8384"))
	PartySelect.open_run(self, _run_party, func(picked: Array):
		_run_party = picked
		_params["party_ready"] = true
		_event_open = false
		if _pending_levelup_after_party:
			_pending_levelup_after_party = false
			if _open_levelup_result():
				return
		_advance_step())

var _rboss_enc := -1
var _dk_pin := -1
func _rebuild() -> void:
	_stop_walk_sfx()
	for c in get_children():
		c.queue_free()
	_done = false; _t = 0.0
	_done_battle_ready = false
	_ready_layer = null
	_stage = Field.apply_variant(Data.stage(String(_params.get("stage", ""))),
		Drops.mode_of(bool(_params.get("hero", false)),
			bool(_params.get("night", false)), bool(_params.get("kades", false))))
	if _stage.get("bg") != null and not _params.has("bg"):
		_params["bg"] = int(_stage["bg"])
	Bgm.play(_explore_bgm())
	_rboss_enc = -1
	if bool(_stage.get("random_boss", false)):
		var bosses: Array = _stage.get("enemies", [])
		if not bosses.is_empty():
			var rr := RandomNumberGenerator.new(); rr.randomize()
			_rboss_enc = _pick_weighted(bosses, rr)
	_dk_pin = -1
	if Darknix.is_summon_stage(_stage):
		_dk_pin = Darknix.enemy_index(_stage["summon"], UserDB.darknix(),
			int(Time.get_unix_time_from_system()))
		if _dk_pin >= 0:
			_rboss_enc = _dk_pin
	_build_bg()
	_build_walk()
	_build_topinfo()
	_build_narration()
	_steps = AdventureRun.build_steps(_stage, Data.adventure_events,
		int(_params.get("enc", 0)),
		{
			"hurt": not (_params.get("hp_state", {}) as Dictionary).is_empty(),
			"fortress": _is_fortress(),
			"random_boss": _rboss_enc >= 0,
			"night": _is_night(),
			"single_boss": _dk_pin >= 0,
		},
		_step_rng())
	_step_i = 0
	for s in _steps:
		if String((s as Dictionary).get("type", "")) == AdventureRun.MONSTER \
				and (s as Dictionary).has("enemy_index"):
			_rboss_enc = int((s as Dictionary)["enemy_index"])
	if _dk_pin >= 0:
		_rboss_enc = _dk_pin
	_build_hud()
	_maybe_dungeon_tutorial()
	var carried_party: Array = (_params.get("party_uids", []) as Array).duplicate()
	_run_party = carried_party if not carried_party.is_empty() else _leader_party()
	if not carried_party.is_empty():
		_params["party_ready"] = true
	else:
		_note_dungeon_entry()
	if _check_starving_end():
		return
	_after_food_gate()

func _after_food_gate() -> void:
	if _party_capacity() == 3 and not bool(_params.get("party_ready", false)):
		_pending_levelup_after_party = true
		_open_party_select()
	elif not _open_levelup_result():
		_advance_step()

var _steps: Array = []
var _step_i := 0
const _STEP_DELAY := 0.3

func _step_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("advq_%s_%d_%d" % [String(_params.get("stage", "")),
		int(_params.get("enc", 0)), int(_params.get("run_seed", 0))])
	return r

func _advance_step() -> void:
	if _done or not is_inside_tree():
		return
	while _step_i < _steps.size():
		var ev: Dictionary = _steps[_step_i]
		_step_i += 1
		if String(ev.get("type", "")) == AdventureRun.MONSTER:
			_begin_walk()
			return
		if _play_event(ev):
			return
	_begin_walk()

func _play_event(ev: Dictionary) -> bool:
	match String(ev.get("type", "")):
		AdventureRun.NOTHING:
			_narrate(Data.ui("#312e493f"))
			if AdventureRun.is_final(ev):
				_end_run_after(2.0)
				return true
			return false
		AdventureRun.HEAL_HOLY:
			_show_fountain(true)
			return true
		AdventureRun.HEAL_PLAIN:
			_show_fountain(false)
			return true
		AdventureRun.SHOP:
			_open_shop(_event_rng("shop"))
			return true
		AdventureRun.CARDGAME:
			var r := _event_rng("card")
			_open_cardgame("match" if r.randf() < 0.5 else "avoid")
			return true
	return false

func _event_rng(tag: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s_%s_%d" % [tag, String(_params.get("stage", "")), int(_params.get("enc", 0))])
	return r

func _step_done() -> void:
	_event_open = false
	if _done or not is_inside_tree():
		return
	get_tree().create_timer(_STEP_DELAY).timeout.connect(func():
		if is_instance_valid(self):
			_advance_step())

func _is_night() -> bool:
	if _params.has("night"):
		return bool(_params.get("night"))
	return String(_stage.get("variant", "")) == "night"

func _end_run_after(secs: float) -> void:
	_done = true
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(self):
			Scenes.goto("worldmap", {"region": _params.get("region", "yutakan"),
				"night": _is_night()}))

func _begin_walk() -> void:
	if _done:
		return
	_walking = true
	_stop_walk_sfx()
	_walk_sfx = Bgm.loop_sfx("effect_walk")
	if _walk_sfx:
		add_child(_walk_sfx)
	_hide_party_cards()
	_start_walk_cycle()

func _stop_walk_sfx() -> void:
	if is_instance_valid(_walk_sfx):
		_walk_sfx.stop()
		_walk_sfx.queue_free()
	_walk_sfx = null

func _check_starving_end() -> bool:
	var starved := ItemEffect.starving_uids(Data.item_effects, _run_party,
		func(uid: int): return UserDB.get_dragon(uid))
	if starved.is_empty():
		return false
	_ask_feed_starving(int(starved[0]))
	return true

func _ask_feed_starving(uid: int) -> void:
	var d := UserDB.get_dragon(uid)
	var nm := String(d.get("name", "드래곤"))
	var el := String(Data.get_dragon(int(d.get("id", 0))).get("element", ""))
	var key := ItemEffect.find_matching_feed(UserDB.inventory(), Data.items, el)
	var leave := func():
		Scenes.goto("worldmap", {"region": _params.get("region", "yutakan")})
	if key == "":
		MessageWindow.open(self, "먹이", "%s이(가) 먹을 수 있는 음식이 없습니다.\n\n상점으로 이동하시겠습니까?" % nm,
			func(): Scenes.goto("shop", {"area": "elpis"}),
			"확인", "취소", -1, 0, leave)
		return
	if AdvAuto.enabled():
		_feed_and_continue(uid, key, nm, el)
		return
	var much := "상당히" if ItemEffect.feed_is_full(Data.item_effects, key) else "약간"
	MessageWindow.open(self, "먹이",
		"%s 아이템을 사용하면\n%s의 배고픔이 %s 채워집니다.\n사용하시겠습니까?"
			% [Data.item_name(key), nm, much],
		func(): _feed_and_continue(uid, key, nm, el),
		"확인", "취소", -1, 0, leave)

func _feed_and_continue(uid: int, key: String, nm: String, el: String) -> void:
	var before := int(UserDB.get_dragon(uid).get("food", 0))
	if int(UserDB.inventory().get(key, 0)) > 0:
		UserDB.add_item(key, -1)
		UserDB.set_dragon_field(uid, "food",
			ItemEffect.food_after_feed(Data.item_effects, Data.get_item(key), key, el,
				int(UserDB.get_dragon(uid).get("food", 0))))
		Bgm.sfx("effect_button")
		_narrate("%s이(가) 맛있게 먹이를 먹었습니다." % nm)
	if AdvAuto.enabled() and int(UserDB.get_dragon(uid).get("food", 0)) <= before:
		AdvAuto.off()
	if not _check_starving_end():
		_after_food_gate()

func _open_levelup_result() -> bool:
	var q: Array = _params.get("levelups", [])
	if q.is_empty():
		return false
	_params.erase("levelups")
	_event_open = true
	LevelUpScreen.open_queue(self, q, func():
		_event_open = false
		_advance_step(),
		{"auto_close": AdvAuto.LVUP_CLOSE_SECS} if AdvAuto.enabled() else {})
	return true

const _TUT_PAGES := 2
func _maybe_dungeon_tutorial() -> void:
	if not _is_fortress():
		return
	if bool(UserDB.get_pmeta("dungeon_tut_seen", false)):
		return
	UserDB.set_pmeta("dungeon_tut_seen", true)
	_open_dungeon_tutorial(0)

func _open_dungeon_tutorial(page: int) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.82); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var p := "res://assets/converted/tutorial_ui/dungeon_tutorial_%d_KR.jpg" % (page + 1)
	if ResourceLoader.exists(p):
		var tr := TextureRect.new(); tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tr)
	var last := page + 1 >= _TUT_PAGES
	var nb := Button.new()
	nb.text = "시작하기" if last else "다음 ▶"
	nb.add_theme_font_size_override("font_size", 22); nb.size = Vector2(160, 48)
	nb.position = Vector2(vis.x - 184, vis.y - 68)
	nb.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		if not last: _open_dungeon_tutorial(page + 1))
	layer.add_child(nb)
	var pg := Label.new(); pg.text = "%d / %d" % [page + 1, _TUT_PAGES]
	pg.add_theme_font_size_override("font_size", 18); pg.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	pg.position = Vector2(24, vis.y - 60); layer.add_child(pg)

const FORTRESS_STAGE := "6"

func _is_fortress() -> bool:
	return String(_params.get("stage", "")) == FORTRESS_STAGE

func _is_kades() -> bool:
	if _params.has("kades"):
		return bool(_params.get("kades"))
	return String(_stage.get("variant", "")) == "kades"

func _base_field() -> int:
	return DungeonBG.base_field(DungeonBG.field_id(_stage))

func _note_dungeon_entry() -> void:
	var done := StoryProgress.note_event({
		"kind": "ADVENTURE",
		"field": _base_field(),
		"region": String(_params.get("region", "")),
		"night": bool(UserDB.get_pmeta("yutakan_night", false)),
		"kades": 1 if _is_kades() else 0,
	})
	if done > 0:
		Toast.show(self, "서브미션 완료! %d화의 이야기가 이어집니다." % done)

func _awaken_explore() -> Dictionary:
	var lst: Array = []
	for uid in _run_party:
		var d := UserDB.get_dragon(int(uid))
		if d.is_empty() or not bool(d.get("awakened", false)):
			continue
		lst.append({"awaken_no": int(d.get("awaken_skill", 0))})
	return AwakenSkill.explore_bonus(lst, Data.skill_awaken)

func _grant_gold(amount: int) -> int:
	var g := int(round(float(amount) * AwakenSkill.mult_of(_awaken_explore(), "gold_pct")
		* _equip_gold_mult()))
	UserDB.add_currency("gold", g)
	return g

func _equip_gold_mult() -> float:
	var pct := 0.0
	for uid in _run_party:
		var d := UserDB.get_dragon(int(uid))
		if d.is_empty():
			continue
		pct += Equipment.reward_rate_pct(d.get("equip", {}), Data.equipment, "gold")
	return 1.0 + pct / 100.0

func _open_cardgame(mode: String) -> void:
	_event_open = true
	Bgm.sfx("effect_card_shuffle")
	var vis := _vis()
	var golayer := CanvasLayer.new()
	golayer.layer = 90
	add_child(golayer)
	var go := _spr("card_game", "scene_adventure_card_game_txt_go", _man("card_game"),
		Design.ASSET_SCALE)
	if go:
		go.position = Vector2(vis.x * 0.5, vis.y * 0.13)
		golayer.add_child(go)
		go.scale *= 0.4
		var gt := go.create_tween()
		gt.tween_property(go, "scale", go.scale * 2.5, 0.22).set_trans(Tween.TRANS_BACK)
		gt.tween_interval(0.7)
		gt.tween_property(go, "modulate:a", 0.0, 0.3)
		gt.tween_callback(golayer.queue_free)
	else:
		golayer.queue_free()
	var rr := RandomNumberGenerator.new()
	rr.seed = hash("cardtalk_%s_%d" % [String(_params.get("stage", "")), int(_params.get("enc", 0))])
	var ready: Array = Data.card_game.get("talk", {}).get("dungeon", {}).get("ready", [])
	if not ready.is_empty():
		var set_: Array = ready[rr.randi_range(0, ready.size() - 1)]
		for line in set_:
			_narrate_npc("아임", String(line))
	var g := CardMatchGame.open(self, mode, func(res): _on_cardgame_done(res))
	if AdvAuto.enabled():
		g.auto_play(AdvAuto.CARD_PICK_SECS)

func _on_cardgame_done(res: Dictionary) -> void:
	var win := bool(res.get("win", false))
	var rw: Dictionary = res.get("reward", {})
	var msg := "꽝!"
	if win and not rw.is_empty():
		msg = _grant_card_reward(rw)
	if _is_fortress():
		var tk: Dictionary = Data.card_game.get("talk", {}).get("dungeon", {})
		var pool: Array = tk.get("success" if win else "fail", [])
		var line := String(pool[0]) if not pool.is_empty() else ("좋았어!" if win else "다음 기회에!")
		_narrate_npc("아임", ("%s
(%s)" % [line, msg]) if win else line)
	else:
		_narrate("%s" % msg if win else "꽝!")
	_step_done()

func _grant_card_reward(rw: Dictionary) -> String:
	match String(rw.get("kind", "")):
		"gold":
			var g := _grant_gold(int(rw.get("amount", 0)))
			return "골드 +%d" % g
		"diamond":
			var dm := int(rw.get("amount", 0))
			UserDB.add_currency("diamond", dm)
			return "다이아 +%d" % dm
		"egg":
			var did := int(rw.get("dragon_id", 0))
			if did > 0:
				UserDB.add_item(EggGacha.key_for(did), 1)
				return "%s의 알" % String(Data.get_dragon(did).get("name", "드래곤"))
			return "알"
		"heal":
			_healed = true
			return "체력 회복"
		"buff_att", "buff_def":
			var stat := "att" if String(rw.get("kind", "")) == "buff_att" else "def"
			var per := int(Data.item_effects.get("drink", {}).get("pct_per_tier", 5))
			var turns := int(Data.item_effects.get("drink", {}).get("duration_turns", 10))
			var tier := int(rw.get("tier", 1))
			var eff := {"stat": stat, "tier": tier, "pct": per * tier, "turns": turns}
			for uid in _run_party:
				var cur: Dictionary = UserDB.get_dragon(int(uid)).get("drink_buffs", {})
				UserDB.set_dragon_field(int(uid), "drink_buffs",
					ItemEffect.apply_drink(cur, eff))
			return "%s +%d%% (%d턴)" % ["공격력" if stat == "att" else "방어력",
				per * tier, turns]
	return "꽝"

func _open_shop(r: RandomNumberGenerator) -> void:
	if AdvAuto.enabled():
		_narrate("떠돌이 상인을 지나쳤다.")
		_step_done()
		return
	_event_open = true
	Bgm.play("bg_shop")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 20; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.75); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	if ResourceLoader.exists("res://scenes/npc/wonder.tscn"):
		var mh := Node2D.new(); mh.position = Vector2(vis.x * 0.22, vis.y * 0.55); mh.scale = Vector2(0.7, 0.7)
		layer.add_child(mh)
		var mi = (load("res://scenes/npc/wonder.tscn") as PackedScene).instantiate(); mh.add_child(mi)
		var ap := mi.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.get_animation_list().size() > 0:
			ap.get_animation(ap.get_animation_list()[0]).loop_mode = Animation.LOOP_LINEAR
			ap.play(ap.get_animation_list()[0])
	var title := Label.new(); title.text = "떠돌이 상인  —  필요한 것을 사세요"
	title.add_theme_font_size_override("font_size", 24); title.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 34); title.position = Vector2(0, vis.y * 0.16)
	layer.add_child(title)
	var cman := _man("common_ui")
	var gcoin := _spr("common_ui", "common_coin_small1", cman, 1.0)
	if gcoin: gcoin.position = Vector2(vis.x * 0.5 - 96, vis.y * 0.24); layer.add_child(gcoin)
	var glabel := Label.new()
	glabel.add_theme_font_size_override("font_size", 20); glabel.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	glabel.size = Vector2(160, 26); glabel.position = Vector2(vis.x * 0.5 - 78, vis.y * 0.24 - 12)
	layer.add_child(glabel)
	var upd_gold := func(): glabel.text = "%d" % UserDB.gold()
	upd_gold.call()
	var pool: Array = Data.items_by("consumable") + Data.items_by("material")
	for i in 3:
		if pool.is_empty(): break
		var key: String = pool[r.randi() % pool.size()]
		var price := 150 + r.randi() % 350
		var cx := vis.x * 0.5; var cy := vis.y * 0.36 + i * 92.0
		var slot := _spr("common_ui", "common_item_bg", cman, 1.0)
		if slot: slot.position = Vector2(cx - 150, cy); layer.add_child(slot)
		var ip := Data.item_icon_path(key)
		if ResourceLoader.exists(ip):
			var icon := Sprite2D.new(); icon.texture = load(ip); icon.material = _pma
			icon.scale = Vector2(0.62, 0.62); icon.position = Vector2(cx - 150, cy); layer.add_child(icon)
		var nm := Label.new(); nm.text = Data.item_name(key)
		nm.add_theme_font_size_override("font_size", 20); nm.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		nm.position = Vector2(cx - 110, cy - 16); nm.size = Vector2(200, 24); layer.add_child(nm)
		var pcoin := _spr("common_ui", "common_coin_small1", cman, 0.8)
		if pcoin: pcoin.position = Vector2(cx + 96, cy); layer.add_child(pcoin)
		var pl := Label.new(); pl.text = "%d" % price
		pl.add_theme_font_size_override("font_size", 18); pl.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
		pl.position = Vector2(cx + 108, cy - 12); pl.size = Vector2(70, 22); layer.add_child(pl)
		var buy := Button.new(); buy.text = "구매"; buy.size = Vector2(80, 40); buy.position = Vector2(cx + 150, cy - 20)
		layer.add_child(buy)
		buy.pressed.connect(func():
			if UserDB.spend("gold", price):
				UserDB.add_item(key, 1); Bgm.sfx("effect_coin")
				buy.text = "✓"; buy.disabled = true; upd_gold.call()
			else:
				buy.text = "부족")
	var leave := Button.new(); leave.text = "떠나기"; leave.size = Vector2(160, 44)
	leave.position = Vector2(vis.x * 0.5 - 80, vis.y * 0.36 + 3 * 92.0)
	leave.pressed.connect(func():
		Bgm.play(_explore_bgm())
		if is_instance_valid(layer): layer.queue_free()
		_step_done())
	layer.add_child(leave)

const _WORDART_SECS := WordArt.SECS

func _wordart_burst(text: String) -> void:
	var vis := _vis()
	WordArt.burst(self, text, vis, 195, 100.0, true)
	CocosParticle.spawn(self, "pt_monster_income_1", Vector2(vis.x * 0.5, vis.y * 0.3), 194, 0.8)

var _event_dim: ColorRect
func _event_dim_show() -> void:
	if is_instance_valid(_event_dim):
		return
	_event_dim = ColorRect.new()
	_event_dim.color = Color(0, 0, 0, 0)
	_event_dim.size = _vis()
	_event_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_dim.z_index = 188
	add_child(_event_dim)
	_event_dim.create_tween().tween_property(_event_dim, "color:a", 200.0 / 255.0, 0.5)

func _event_dim_clear() -> void:
	if not is_instance_valid(_event_dim):
		return
	var d := _event_dim
	_event_dim = null
	var t := d.create_tween()
	t.tween_property(d, "color:a", 0.0, 0.3)
	t.tween_callback(d.queue_free)

func _show_fountain(holy: bool) -> void:
	_event_open = true
	_healed = true
	Bgm.sfx("effect_holy_well_2" if holy else "effect_water_in")
	var vis := _vis()
	_event_dim_show()
	var S := Design.ASSET_SCALE
	var fman := _man("adventure_fountain")
	var f := _spr("adventure_fountain", "scene_adventure_fountain_dv2_fountain_base", fman, S * 0.7)
	if f:
		var fh := float(fman.get("scene_adventure_fountain_dv2_fountain_base", {}).get("h", 400)) * S * 0.7
		var end_y := vis.y * 0.5 - 10.0
		f.position = Vector2(vis.x * 0.5, end_y - fh)
		f.z_index = 189
		add_child(f)
		_fountain_node = f
		var dt := f.create_tween()
		dt.tween_interval(0.5)
		dt.tween_property(f, "position:y", end_y, 0.25) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		var frames: Array = []
		for i in range(1, 6):
			var tp := "res://assets/converted/adventure_fountain/scene_adventure_fountain_dv2_fountain_%02d.tres" % i
			if ResourceLoader.exists(tp):
				frames.append(load(tp))
		if not frames.is_empty():
			var wave := Sprite2D.new()
			wave.texture = frames[0]
			wave.material = f.material
			var bh := float(fman.get("scene_adventure_fountain_dv2_fountain_base", {}).get("h", 400))
			wave.position = Vector2(0, bh * 0.12)
			f.add_child(wave)
			if frames.size() > 1:
				var wt := wave.create_tween().set_loops()
				for tex in frames:
					wt.tween_callback(func(): wave.texture = tex)
					wt.tween_interval(0.1)
	CocosParticle.spawn(self, "pt_monster_income_1",
		Vector2(vis.x * 0.5, FLOOR * 0.5), 194, 0.7)
	_wordart_burst(Data.ui("#a1eb3533"))
	_narrate(Data.ui("#e671b9c5"))
	get_tree().create_timer((_WORDART_SECS + 0.6) / maxf(_speed, 1.0)).timeout.connect(_end_fountain)

var _fountain_node: Sprite2D
func _end_fountain() -> void:
	_event_dim_clear()
	if is_instance_valid(_fountain_node):
		var f := _fountain_node
		_fountain_node = null
		var t := f.create_tween()
		t.tween_property(f, "modulate:a", 0.0, 0.3)
		t.tween_callback(f.queue_free)
	_step_done()

func _build_chaos_fire() -> void:
	if not Darknix.is_summon_stage(_stage):
		return
	var f := FileAccess.open("res://assets/converted/particles/pt_monster_fire_back.json", FileAccess.READ)
	if f == null:
		return
	var c = JSON.parse_string(f.get_as_text())
	if typeof(c) != TYPE_DICTIONARY:
		return
	var vis := get_viewport_rect().size
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32; tex.height = 32
	var p := CPUParticles2D.new()
	p.texture = tex
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if bool(c.get("additive", true)) \
		else CanvasItemMaterial.BLEND_MODE_MIX
	p.material = m
	p.amount = int(c.get("amount", 30))
	p.lifetime = float(c.get("lifetime", 6.0))
	p.lifetime_randomness = float(c.get("lifetime_randomness", 0.0))
	p.direction = Vector2(float(c["direction"][0]), float(c["direction"][1]))
	p.spread = float(c.get("spread", 0.0))
	p.initial_velocity_min = maxf(0.0, float(c.get("vmin", 0.0)))
	p.initial_velocity_max = maxf(0.0, float(c.get("vmax", 0.0)))
	p.gravity = Vector2(float(c["gravity"][0]), float(c["gravity"][1]))
	p.radial_accel_min = float(c.get("radial_min", 0.0))
	p.radial_accel_max = float(c.get("radial_max", 0.0))
	p.tangential_accel_min = float(c.get("tangential_min", 0.0))
	p.tangential_accel_max = float(c.get("tangential_max", 0.0))
	p.scale_amount_min = float(c.get("scale_min", 0.1))
	p.scale_amount_max = float(c.get("scale_max", 1.0))
	var er := float(c.get("scale_end_ratio", 1.0))
	if not is_equal_approx(er, 1.0):
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 1.0))
		sc.add_point(Vector2(1.0, maxf(0.01, er)))
		p.scale_amount_curve = sc
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(float(c["emit_rect"][0]), maxf(1.0, float(c["emit_rect"][1])))
	var cs: Array = c.get("color_start", [1, 1, 1, 1])
	var ce: Array = c.get("color_end", [0, 0, 0, 0])
	var cg := Gradient.new()
	cg.set_color(0, Color(float(cs[0]), float(cs[1]), float(cs[2]), float(cs[3])))
	cg.set_color(1, Color(float(ce[0]), float(ce[1]), float(ce[2]), float(ce[3])))
	p.color_ramp = cg
	p.position = Vector2(vis.x * 0.5, vis.y)
	p.z_index = 60
	add_child(p)

var _bg_node: Control

func _build_bg() -> void:
	_bg_node = DungeonBG.build(self, _stage)
	_build_chaos_fire()
	if _bg_node != null:
		return
	var bg := TextureRect.new()
	var p := "res://assets/converted/battle_bg/bg_%d.jpg" % int(_params.get("bg", 1))
	if ResourceLoader.exists(p):
		bg.texture = load(p)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_bg_node = bg

const _WALK_STEP := 0.3
const _WALK_SCALES := [1.1, 1.155, 1.21275, 1.279456, 1.343429, 1.417316]
const _WALK_OFFS := [Vector2(0, 20), Vector2(-50, 10), Vector2(-50, 30),
	Vector2(50, 20), Vector2(50, 40), Vector2(0, 30)]

var _walk_layer: TextureRect
var _walk_tw: Tween

func _build_walk() -> void:
	var vis := _vis()
	_cam = Camera2D.new()
	_cam.position = vis * 0.5
	add_child(_cam); _cam.make_current()

func _start_walk_cycle() -> void:
	if _done or not _walking:
		return
	var vis := _vis()
	var p := DungeonBG.path_for(_stage)
	if p == "":
		p = "res://assets/converted/battle_bg/bg_%d.jpg" % int(_params.get("bg", 1))
	if not ResourceLoader.exists(p):
		return
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.size = vis
	tr.position = Vector2.ZERO
	tr.pivot_offset = vis * 0.5
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	tr.z_index = 0
	add_child(tr)
	if is_instance_valid(_bg_node) and _bg_node.get_parent() == self:
		move_child(tr, _bg_node.get_index() + 1)
	else:
		move_child(tr, 1)
	DungeonBG.add_overlay(tr, _stage)
	_walk_layer = tr
	var t := _WALK_STEP
	_walk_tw = tr.create_tween()
	for i in 6:
		var st := float(_WALK_SCALES[i])
		var of: Vector2 = _WALK_OFFS[i]
		if i == 0:
			_walk_tw.tween_property(tr, "modulate:a", 1.0, t)
			_walk_tw.parallel().tween_property(tr, "scale", Vector2(st, st), t)
			_walk_tw.parallel().tween_property(tr, "position", of, t)
		else:
			_walk_tw.tween_property(tr, "scale", Vector2(st, st), t)
			_walk_tw.parallel().tween_property(tr, "position", of, t)
	_walk_tw.tween_property(tr, "modulate:a", 0.0, t)
	_walk_tw.set_speed_scale(_speed)
	_walk_tw.finished.connect(func() -> void:
		if is_instance_valid(tr):
			tr.queue_free()
		if _done or not _walking:
			return
		if _t >= _dur:
			_done = true
			_monster_meet()
		else:
			_start_walk_cycle())

func _build_topinfo() -> void:
	pass

const _NARR_H := 120.0
var _narr_label: Label
var _narr_arrow: Sprite2D
func _build_narration() -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 6
	add_child(lay)
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 10.0, _NARR_H)
	box.position = Vector2(5.0, vis.y - _NARR_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(box)
	_narr_label = Label.new()
	_narr_label.add_theme_font_size_override("font_size", 28)
	_narr_label.add_theme_color_override("font_color", Color.WHITE)
	_narr_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narr_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_narr_label.size = Vector2(box.size.x - 20.0, _NARR_H - 8.0)
	_narr_label.position = Vector2(10.0, 4.0)
	_narr_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_narr_label)
	_narr_arrow = _spr("common_ui", "common_btn_arrow2", _man("common_ui"), Design.ASSET_SCALE)
	if _narr_arrow:
		_narr_arrow.position = Vector2(box.size.x - 40.0, _NARR_H * 0.5)
		box.add_child(_narr_arrow)
		var at := _narr_arrow.create_tween().set_loops()
		at.tween_property(_narr_arrow, "modulate:a", 0.25, 0.5)
		at.tween_property(_narr_arrow, "modulate:a", 1.0, 0.5)
	var field_text := String(_stage.get("field_text", ""))
	var lines := field_text.split("\n") if field_text != "" else PackedStringArray()
	var line := ""
	if lines.size() > 0 and String(_stage.get("variant_label", "")) == "":
		line = field_text
	else:
		var nm := Data.stage_display_name(_stage)
		line = "당신은 %s%s 모험을 떠났습니다." % [nm, _josa_ro(nm)]
		if lines.size() > 1:
			line += "\n" + lines[1]
	_narrate(line)

func _narrate(text: String) -> void:
	if is_instance_valid(_narr_label):
		_narr_label.text = text

func _narrate_npc(display_name: String, line: String) -> void:
	_narrate("[ %s ]\n%s" % [display_name, line])

var _npc_node: Node2D
func _show_npc(npc: String, body := 1, eye := "4_1", mouth := "3_2") -> void:
	_hide_npc()
	var dir := "npc_%s" % npc
	var man := _man(dir)
	if man.is_empty(): return
	var bkey := "npc_%s_body_%d" % [npc, body]
	var bi: Dictionary = man.get(bkey, {})
	if bi.is_empty(): return
	var S := Design.ASSET_SCALE
	var bw := float(bi.get("w", 219)) * S
	var bh := float(bi.get("h", 351)) * S
	var vis := _vis()
	_npc_node = Node2D.new()
	_npc_node.position = Vector2(vis.x * 0.5, vis.y - _NARR_H)
	_npc_node.z_index = 4
	add_child(_npc_node)
	var b := _spr(dir, bkey, man, S)
	if b == null: return
	b.position = Vector2(0, -bh * 0.5)
	_npc_node.add_child(b)
	var bw_px := float(bi.get("w", 219))
	var bh_px := float(bi.get("h", 351))
	for part in [["mouth", mouth, Vector2(103, 310)], ["eye", eye, Vector2(104, 346)]]:
		var key := "npc_%s_%s_%s" % [npc, part[0], part[1]]
		if not man.has(key): continue
		var ps := _spr(dir, key, man, 1.0)
		if ps == null: continue
		var pos: Vector2 = part[2]
		ps.position = Vector2(pos.x / S - bw_px * 0.5, bh_px * 0.5 - pos.y / S)
		b.add_child(ps)
	_npc_node.position.y += bh
	create_tween().tween_property(_npc_node, "position:y", vis.y - _NARR_H, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _hide_npc() -> void:
	if is_instance_valid(_npc_node):
		_npc_node.queue_free()
	_npc_node = null

func _josa_ro(word: String) -> String:
	var w := _josa_stem(word)
	if w.is_empty(): return "로"
	var c := w.unicode_at(w.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return "로"
	var jong := (c - 0xAC00) % 28
	return "로" if (jong == 0 or jong == 8) else "으로"

func _josa_stem(word: String) -> String:
	var w := word.strip_edges()
	if w.ends_with(")"):
		var i := w.rfind("(")
		if i >= 0:
			return w.substr(i + 1, w.length() - i - 2).strip_edges()
	return w

func _josa(word: String, with_batchim: String, without: String) -> String:
	var w := _josa_stem(word)
	if w.is_empty(): return without
	var c := w.unicode_at(w.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

func _build_hud() -> void:
	var vis := _vis()
	_speed_btn = Button.new()
	_speed_btn.text = "▶ x1"; _speed_btn.position = Vector2(vis.x - 90, 12); _speed_btn.size = Vector2(74, 30)
	_speed_btn.pressed.connect(_cycle_speed)
	add_child(_speed_btn)
	var out := Button.new()
	out.text = "나가기"; out.position = Vector2(16, 12); out.size = Vector2(74, 30)
	out.pressed.connect(func(): Scenes.goto("worldmap", {"region": _params.get("region", "yutakan")}))
	add_child(out)
	_build_objective(int(_params.get("enc", 0)), int((_stage.get("enemies", []) as Array).size()))
	_build_adventure_navi()

var _boss_bar_fill: Sprite2D
var _boss_count: Label

func _build_adventure_navi() -> void:
	var total := int((_stage.get("enemies", []) as Array).size())
	if total <= 0:
		return
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var lab := _man("laboratory_ui")
	var sf := _man("skeleton_fortress")
	var navi := Node2D.new()
	navi.z_index = 50
	add_child(navi)
	var bar_w := 275.0
	var right := vis.x - 20.0
	var y := 58.0
	var track := _spr("laboratory_ui", "scene_laboratory_upgrade_gauge_bg", lab, S)
	if track:
		var tw := float((lab.get("scene_laboratory_upgrade_gauge_bg", {}) as Dictionary).get("w", 200)) * S
		if tw > 0.0:
			track.scale = Vector2(bar_w / tw * S, S)
		track.position = Vector2(right - bar_w * 0.5, y)
		navi.add_child(track)
	_boss_bar_fill = _spr("laboratory_ui", "scene_laboratory_upgrade_gauge_bar", lab, S)
	if _boss_bar_fill:
		_boss_bar_fill.centered = false
		_boss_bar_fill.position = Vector2(right - bar_w, y - 7.0)
		navi.add_child(_boss_bar_fill)
	var enc := int(_params.get("enc", 0))
	var at_boss := (enc + 1) >= total
	var ikey := "scene_adventure_skeleton_fortress_icon_boss%s_on" % ("2" if at_boss else "")
	var icon := _spr("skeleton_fortress", ikey, sf, 0.55 * S)
	if icon:
		icon.position = Vector2(right, y)
		navi.add_child(icon)
		var base := 0.55 * S
		var pt := icon.create_tween().set_loops()
		pt.tween_property(icon, "scale", Vector2(base - 0.03, base - 0.03), 0.1)
		pt.tween_property(icon, "scale", Vector2(base + 0.03, base + 0.03), 0.1)
		pt.tween_property(icon, "scale", Vector2(base, base), 0.1)
		pt.tween_interval(0.5)
	var box := NinePatchRect.new()
	var boxp := "res://assets/converted/ninepatch_ui/9patch_box1.tres"
	if ResourceLoader.exists(boxp):
		box.texture = load(boxp)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 10; box.patch_margin_bottom = 10
	box.size = Vector2(52, 26)
	box.position = Vector2(right - bar_w, y - 40.0)
	add_child(box)
	var bl := Label.new()
	bl.text = "보스"
	bl.add_theme_font_size_override("font_size", 16)
	bl.add_theme_color_override("font_color", Color(1, 1, 1))
	bl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	bl.add_theme_constant_override("outline_size", 4)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.size = box.size
	box.add_child(bl)
	_boss_count = Label.new()
	_boss_count.add_theme_font_size_override("font_size", 15)
	_boss_count.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_boss_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_boss_count.add_theme_constant_override("outline_size", 4)
	_boss_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_boss_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_count.size = Vector2(80, 26)
	_boss_count.position = Vector2(box.position.x + box.size.x + 8.0, box.position.y)
	add_child(_boss_count)
	_update_adventure_navi()
	navi.position = Vector2(0, -120.0)
	navi.create_tween().tween_property(navi, "position", Vector2.ZERO, 0.7) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _update_adventure_navi() -> void:
	var total := int((_stage.get("enemies", []) as Array).size())
	if total <= 0:
		return
	var done := clampi(int(_params.get("enc", 0)) + 1, 0, total)
	if _boss_count:
		_boss_count.text = "%d/%d" % [done, total]
	if is_instance_valid(_boss_bar_fill):
		var lab := _man("laboratory_ui")
		var fw := float((lab.get("scene_laboratory_upgrade_gauge_bar", {}) as Dictionary).get("w", 200))
		if fw > 0.0:
			var ratio := float(done) / float(total)
			_boss_bar_fill.scale = Vector2(275.0 / fw * ratio, Design.ASSET_SCALE)

var _party_cards: Array = []

func _show_party_cards() -> void:
	_hide_party_cards()
	var uids: Array = _run_party if not _run_party.is_empty() else _leader_party()
	if uids.is_empty():
		return
	var hp_state: Dictionary = {} if _healed else _params.get("hp_state", {})
	var party := PartyStats.summary(uids, _is_kades(), _field_element_key(), hp_state)
	PartyStats.apply_passives(party, _next_enemy_ref(), {
		"field_element": _field_element_key(), "enemy_boss": _next_is_boss(),
		"team_buffs": PartyStats.team_buff_names(uids),
		"explore_gold_pct": int(_awaken_explore().get("gold_pct", 0))})
	_party_cards = PartyCardView.build_row(self, self, party, _vis(), _pma)
	for i in mini(_party_cards.size(), party.size()):
		_attach_cure_button(_party_cards[i], party[i])

func _attach_cure_button(card: Control, pd: Dictionary) -> void:
	if card == null:
		return
	var lv := int(pd.get("level", 1))
	var key := ""
	for t in (Data.item_effects.get("heal_potion", {}).get("tiers", []) as Array):
		var k := String((t as Dictionary).get("key", ""))
		if ItemEffect.heal_usable(Data.item_effects, k, lv):
			key = k
			break
	if key == "":
		return
	var dead := int(pd.get("hp", 1)) <= 0
	PartyCardView.build_cure_button(card, key, UserDB.item_count(key), dead, _pma,
		_use_heal_potion.bind(int(pd.get("uid", 0)), key))

func _use_heal_potion(uid: int, key: String) -> void:
	var hp_state: Dictionary = (_params.get("hp_state", {}) as Dictionary).duplicate()
	var uids: Array = _run_party if not _run_party.is_empty() else _leader_party()
	var party := PartyStats.summary(uids, _is_kades(), _field_element_key(), hp_state)
	var healed := 0
	for pd: Dictionary in party:
		if int(pd.get("uid", 0)) != uid:
			continue
		var hp := int(pd.get("hp", 0))
		var hp_max := int(pd.get("hp_max", 1))
		healed = ItemEffect.heal_amount(Data.item_effects, hp, hp_max)
		if healed > 0:
			hp_state[str(uid)] = clampi(hp + healed, 0, hp_max)
		break
	if healed <= 0 or not UserDB.use_item(key, 1):
		return
	_params["hp_state"] = hp_state
	for i in mini(_party_cards.size(), uids.size()):
		if int(uids[i]) != uid:
			continue
		var c: Control = _party_cards[i]
		if is_instance_valid(c):
			CocosParticle.spawn(self, "skill_29", c.position + c.size * 0.5, 132, 0.9)
		break
	Bgm.sfx("effect_skill_29")
	_show_party_cards()

func _hide_party_cards() -> void:
	for c in _party_cards:
		if is_instance_valid(c):
			c.queue_free()
	_party_cards.clear()

func _next_enemy_ref() -> Dictionary:
	var enemies: Array = _stage.get("enemies", [])
	var ei := _rboss_enc if _rboss_enc >= 0 else int(_params.get("enc", 0))
	if ei < 0 or ei >= enemies.size():
		return {"element": "", "hp": 1}
	var e: Dictionary = enemies[ei]
	return {"element": Drops.normalize_element(e.get("element", "")),
		"hp": maxi(1, int(e.get("hp", 1)))}

func _is_boss_at(idx: int) -> bool:
	var enemies: Array = _stage.get("enemies", [])
	if idx >= 0 and idx < enemies.size() and (enemies[idx] as Dictionary).has("boss"):
		return bool((enemies[idx] as Dictionary)["boss"])
	var total := enemies.size()
	return total > 0 and int(_params.get("enc", 0)) + 1 >= total

func _enc_index() -> int:
	return _rboss_enc if _rboss_enc >= 0 else int(_params.get("enc", 0))

func _next_is_boss() -> bool:
	return _is_boss_at(_enc_index())

func _field_element_key() -> String:
	var authored := Drops.normalize_element(_stage.get("field_element", ""))
	if authored == "":
		authored = Drops.normalize_element(_stage.get("element", ""))
	if authored != "" and authored != "none":
		return authored
	var tally: Dictionary = {}
	for e in _stage.get("enemies", []):
		var el := Drops.normalize_element((e as Dictionary).get("element", ""))
		if el == "" or el == "none":
			continue
		tally[el] = int(tally.get(el, 0)) + 1
	var best := ""
	var best_n := 0
	for k in tally:
		if int(tally[k]) > best_n:
			best_n = int(tally[k]); best = String(k)
	return best

func _build_objective(enc: int, total: int) -> void:
	if total <= 0: return
	var done := (enc + 1) >= total
	const H := 48.0
	var bw := 250.0
	var panel := NinePatchRect.new()
	panel.texture = load("res://assets/converted/adventure_ui/scene_adventure_quest_shadow.tres")
	panel.patch_margin_left = 12; panel.patch_margin_top = 12; panel.patch_margin_right = 12; panel.patch_margin_bottom = 12
	panel.size = Vector2(bw, H); panel.position = Vector2(16, 50)
	add_child(panel)
	var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), 0.5)
	if pbg: pbg.position = Vector2(28, H * 0.5); panel.add_child(pbg)
	var qic := _spr("adventure_ui", "scene_adventure_icon_quest1", _man("adventure_ui"), 0.5)
	if qic: qic.position = Vector2(28, H * 0.5); panel.add_child(qic)
	if done:
		var chk := _spr("common_ui", "common_checked", _man("common_ui"), 0.6)
		if chk: chk.position = Vector2(28, H * 0.5); panel.add_child(chk)
	var lbl := Label.new()
	var goal_nm := Data.stage_display_name(_stage)
	lbl.text = goal_nm if not done else (goal_nm + " 완료")
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7)); lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(56, 4); lbl.size = Vector2(bw - 110, H - 8)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(lbl)
	var cnt := Label.new(); cnt.text = "%d/%d" % [mini(enc + 1, total), total]
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7)); cnt.add_theme_constant_override("outline_size", 3)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(bw - 60, 4); cnt.size = Vector2(48, H - 8)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(cnt)
	_build_story_objective(H)

func _build_story_objective(h: float) -> void:
	var no := StoryProgress.pending_episode()
	var sp := StoryProgress.spec(no)
	if no <= 0 or sp.is_empty():
		return
	var field := DungeonBG.base_field(DungeonBG.field_id(_stage))
	if sp.has("field"):
		if int(sp["field"]) != field:
			return
	elif sp.has("region"):
		if String(sp["region"]) != String(_stage.get("region", "")):
			return
	else:
		return
	var cur := StoryProgress.count(no)
	var need := int(sp.get("count", 0))
	var bw := 250.0
	var panel := NinePatchRect.new()
	panel.texture = load("res://assets/converted/adventure_ui/scene_adventure_quest_shadow.tres")
	panel.patch_margin_left = 12; panel.patch_margin_top = 12
	panel.patch_margin_right = 12; panel.patch_margin_bottom = 12
	panel.size = Vector2(bw, h); panel.position = Vector2(16, 50 + h + 6)
	add_child(panel)
	var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), 0.5)
	if pbg: pbg.position = Vector2(28, h * 0.5); panel.add_child(pbg)
	var qic := _spr("adventure_ui", "scene_adventure_icon_quest2", _man("adventure_ui"), 0.5)
	if qic == null:
		qic = _spr("adventure_ui", "scene_adventure_icon_quest1", _man("adventure_ui"), 0.5)
	if qic: qic.position = Vector2(28, h * 0.5); panel.add_child(qic)
	if cur >= need:
		var chk := _spr("common_ui", "common_checked", _man("common_ui"), 0.6)
		if chk: chk.position = Vector2(28, h * 0.5); panel.add_child(chk)
	var lbl := Label.new()
	lbl.text = StoryQuest.cond_line(sp, StoryProgress.place_name(sp), StoryProgress.target_name(sp))
	if lbl.text == "":
		lbl.text = "%d화 서브미션" % no
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(56, 4); lbl.size = Vector2(bw - 110, h - 8)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(lbl)
	var cnt := Label.new(); cnt.text = "%d/%d" % [mini(cur, need), need]
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	cnt.add_theme_constant_override("outline_size", 3)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(bw - 70, 4); cnt.size = Vector2(58, h - 8)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(cnt)

func _cycle_speed() -> void:
	_speed = 2.0 if _speed == 1.0 else (3.0 if _speed == 2.0 else 1.0)
	_speed_btn.text = "▶ x%d" % int(_speed)
	if is_instance_valid(_walk_tw):
		_walk_tw.set_speed_scale(_speed)

func _process(delta: float) -> void:
	if _done or not _walking:
		return
	if _event_open:
		if is_instance_valid(_walk_tw) and _walk_tw.is_running():
			_walk_tw.pause()
		if is_instance_valid(_walk_sfx) and _walk_sfx.playing:
			_walk_sfx.stop()
		return
	if is_instance_valid(_walk_tw) and not _walk_tw.is_running():
		_walk_tw.play()
	if is_instance_valid(_walk_sfx) and not _walk_sfx.playing:
		_walk_sfx.play()
	_t += delta * _speed

func _monster_meet() -> void:
	var vis := _vis()
	var mid := _enemy_id_for_enc()
	var enc := int(_params.get("enc", 0))
	var is_boss := _is_boss_at(_enc_index())
	_walking = false
	_stop_walk_sfx()
	if is_instance_valid(_walk_tw): _walk_tw.kill()
	if is_instance_valid(_walk_layer):
		var wl := _walk_layer
		var wt := wl.create_tween()
		wt.tween_property(wl, "modulate:a", 0.0, 0.2)
		wt.tween_callback(wl.queue_free)
		_walk_layer = null
	var enemies: Array = _stage.get("enemies", [])
	var ei := _rboss_enc if _rboss_enc >= 0 else enc
	var mn := "몬스터"
	if ei >= 0 and ei < enemies.size():
		mn = String((enemies[ei] as Dictionary).get("name", "몬스터"))
	_narrate("길을 잃고 헤매던 중 %s의 으슥한 곳에서\n%s%s 만났다."
		% [Data.stage_display_name(_stage), mn, _josa(mn, "을", "를")])
	_income_monster(is_boss)
	var delay := 0.0
	if is_boss:
		_alert_monster(mid)
		delay = 3.0 / maxf(_speed, 1.0)
	get_tree().create_timer(delay).timeout.connect(
		_show_monster.bind(mid, is_boss, vis))

func _income_monster(alert: bool) -> void:
	var vis := _vis()
	var flash := ColorRect.new()
	flash.color = Color8(204, 61, 61, 0) if alert else Color8(234, 234, 234, 100)
	flash.size = vis
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 200
	add_child(flash)
	var t := flash.create_tween()
	if alert:
		t.tween_interval(0.3)
		t.tween_property(flash, "color:a", 1.0, 0.2)
	else:
		t.tween_property(flash, "color:a", 200.0 / 255.0, 0.2)
	t.tween_property(flash, "color:a", 0.0, 0.7)
	t.tween_callback(flash.queue_free)
	CocosParticle.spawn(self, "pt_monster_income_1", Vector2(vis.x * 0.5, 0.0), 199, 0.6)
	Bgm.play("bg_battle_boss" if alert else "bg_colosseum_battle_2")

func _show_monster(mid: int, is_boss: bool, vis: Vector2) -> void:
	if not is_inside_tree():
		return
	var meet := Node2D.new(); add_child(meet)
	var cx := vis.x * 0.5
	var cy := FLOOR * 0.56
	var full := Vector2(0.75, 0.75) * (1.3 if is_boss else 1.0)
	var mscn := "res://scenes/monsters/monster_%d.tscn" % mid
	var mnode: Node2D = null
	if ResourceLoader.exists(mscn):
		mnode = (load(mscn) as PackedScene).instantiate()
		var ap := mnode.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("wait"): ap.play("wait")
	else:
		mnode = _spr("adventure_ui", "scene_adventure_shadow", _adv, 2.0)
	if mnode == null:
		_show_battle_ready(is_boss); return
	if is_boss:
		_boss_show_effect()
	var sbase := 1.5 * (1.3 if is_boss else 1.0)
	var sh := _spr("adventure_ui", "scene_adventure_shadow", _adv, sbase)
	if sh:
		sh.position = Vector2(cx, cy + 96.0)
		meet.add_child(sh)
		var st := sh.create_tween().set_loops()
		st.tween_property(sh, "scale", Vector2(sbase - 0.1, sbase - 0.1), 1.0)
		st.tween_property(sh, "scale", Vector2(sbase, sbase), 1.0)
	meet.add_child(mnode)
	var p0 := Vector2(cx, cy + 30.0)
	mnode.position = p0
	mnode.scale = full
	if is_boss:
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_inside_tree():
				Bgm.sfx("effect_monster_in"))
	else:
		Bgm.sfx("effect_monster_in")
	var t := meet.create_tween()
	t.tween_property(mnode, "scale", full * 1.2, 0.3)
	t.parallel().tween_property(mnode, "position", p0 + Vector2(0, -130.0), 0.3)
	t.tween_property(mnode, "scale", Vector2(full.x * 0.9, full.y * 0.8), 0.15)
	t.parallel().tween_property(mnode, "position", p0 + Vector2(0, -10.0), 0.15)
	t.tween_callback(func():
		_arrive_impact(cx, cy, is_boss))
	t.tween_property(mnode, "scale", full, 0.2)
	t.parallel().tween_property(mnode, "position", p0 + Vector2(0, -30.0), 0.2)
	t.tween_interval(2.05 if is_boss else 0.55)
	t.tween_callback(_show_battle_ready.bind(is_boss))

const _BOSS_GLYPH_DELAY: Array[float] = [0.6, 0.9, 1.2, 1.5]
const _BOSS_GLYPH_DX: Array[float] = [-260.0, -110.0, 110.0, 260.0]
func _boss_show_effect() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var cx := vis.x * 0.5
	var y := Design.flip_y(vis.y * 0.75, vis.y)
	var layer := Node2D.new()
	layer.z_index = 130
	add_child(layer)
	Bgm.sfx("effect_cut_in")
	var starts := [
		Vector2(-300.0 - vis.x, y),
		Vector2(vis.x * 0.35, y - 300.0),
		Vector2(vis.x * 0.7, y - 300.0),
		Vector2(vis.x + 300.0, y),
	]
	for i in 4:
		var g := _spr("adventure_ui", "scene_adventure_txt_boss%d_kr" % (i + 1), _adv, 2.0 * S)
		if g == null:
			continue
		g.position = starts[i]
		layer.add_child(g)
		var t := g.create_tween()
		t.tween_interval(_BOSS_GLYPH_DELAY[i])
		t.tween_property(g, "scale", Vector2.ONE * S, 0.75)
		t.parallel().tween_property(g, "position", Vector2(cx + _BOSS_GLYPH_DX[i], y), 0.8) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var tl := layer.create_tween()
	tl.tween_interval(2.7)
	tl.tween_callback(layer.queue_free)

const _READY_BTN := Vector2(262.0, 94.0)
var _ready_layer: CanvasLayer

func _show_battle_ready(is_boss: bool) -> void:
	if _done_battle_ready:
		return
	_done_battle_ready = true
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _READY_BTN.x * S
	var y := vis.y * 0.5 - 20.0
	_ready_layer = CanvasLayer.new(); _ready_layer.layer = 60
	add_child(_ready_layer)
	_ready_button("scene_adventure_btn1", AdventureRun.escape_frame(_is_fortress()),
		Vector2(vis.x * 0.5 - (w * 0.5 + 50.0), y), Vector2(-w - 60.0, y),
		_on_choice_run.bind(is_boss))
	if AdvAuto.enabled():
		_counter_ready_button("scene_adventure_choice_fight_KR",
			Vector2(vis.x * 0.5 + (w * 0.5 + 50.0), y), Vector2(vis.x + w + 60.0, y),
			_on_choice_fight)
	else:
		_ready_button("scene_adventure_btn2", "scene_adventure_choice_fight_KR",
			Vector2(vis.x * 0.5 + (w * 0.5 + 50.0), y), Vector2(vis.x + w + 60.0, y), _on_choice_fight)
	_narrate("어떻게 하시겠습니까?\n몬스터의 능력치를 잘 보고 결정하세요.")
	_show_party_cards()

var _done_battle_ready := false

func _ready_button(bg_key: String, label_key: String, to: Vector2, from: Vector2,
		cb: Callable) -> void:
	var S := Design.ASSET_SCALE
	var holder := Node2D.new()
	holder.position = from
	holder.set_meta("target_x", to.x)
	_ready_layer.add_child(holder)
	var bg := _spr("adventure_ui", bg_key, _adv, S)
	if bg:
		holder.add_child(bg)
	var lb := _spr("adventure_ui", label_key, _adv, S)
	if lb:
		holder.add_child(lb)
	var hit := Button.new()
	hit.flat = true
	hit.size = _READY_BTN * S
	hit.position = -_READY_BTN * S * 0.5
	hit.pressed.connect(cb)
	holder.add_child(hit)
	var tw := holder.create_tween()
	tw.tween_property(holder, "position", to, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

func _counter_ready_button(label_key: String, to: Vector2, from: Vector2, cb: Callable) -> void:
	var b := CounterButton.make(label_key, true)
	b.position = from
	b.set_meta("target_x", to.x)
	b.name = "AutoFightButton"
	b.fired.connect(cb)
	b.cancelled.connect(AdvAuto.off)
	_ready_layer.add_child(b)
	var tw := b.create_tween()
	tw.tween_property(b, "position", to, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

func _clear_battle_ready() -> void:
	if is_instance_valid(_ready_layer):
		_ready_layer.queue_free()
	_ready_layer = null

func _on_choice_fight() -> void:
	_clear_battle_ready()
	_go_battle()

func _on_choice_run(_is_boss: bool) -> void:
	_clear_battle_ready()
	_narrate("무사히 도망쳤다.")
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(self):
			Scenes.goto("worldmap", {"region": _params.get("region", "yutakan")}))

func _arrive_impact(x: float, y: float, is_boss: bool) -> void:
	_map_shake(9.0 if is_boss else 5.0)
	var burst := CPUParticles2D.new()
	burst.position = Vector2(x, y)
	burst.one_shot = true; burst.explosiveness = 1.0
	burst.amount = 20 if is_boss else 12
	burst.lifetime = 0.5
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 14.0
	burst.direction = Vector2(0, -1); burst.spread = 180.0
	burst.initial_velocity_min = 90.0; burst.initial_velocity_max = 210.0
	burst.gravity = Vector2(0, 320.0)
	burst.scale_amount_min = 2.0; burst.scale_amount_max = 4.5
	var g := Gradient.new()
	var c: Color = Color(1.0, 0.45, 0.25) if is_boss else Color(1.0, 0.92, 0.6)
	g.set_color(0, Color(c.r, c.g, c.b, 0.9)); g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	burst.color_ramp = g
	burst.z_index = 30
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(burst): burst.queue_free())

var _shake_tw: Tween
func _map_shake(intensity: float) -> void:
	if not is_instance_valid(_cam):
		_cam = Camera2D.new()
		_cam.position = _vis() * 0.5
		add_child(_cam); _cam.make_current()
	if is_instance_valid(_shake_tw): _shake_tw.kill()
	_shake_tw = _cam.create_tween()
	var amt := intensity
	for i in 6:
		_shake_tw.tween_property(_cam, "offset", Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), 0.03)
		amt *= 0.68
	_shake_tw.tween_property(_cam, "offset", Vector2.ZERO, 0.05)

func _alert_monster(mid: int) -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var lay := CanvasLayer.new(); lay.layer = 30; add_child(lay)
	var root := Node2D.new(); lay.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.position = Vector2(-100, -100)
	dim.size = vis + Vector2(200, 200)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(dim)
	lay.move_child(dim, 0)
	var dt := dim.create_tween()
	dt.tween_property(dim, "color:a", 150.0 / 255.0, 0.5)
	var dl := dim.create_tween().set_loops()
	dl.tween_interval(0.5)
	dl.tween_property(dim, "color:a", 50.0 / 255.0, 0.5)
	dl.tween_property(dim, "color:a", 150.0 / 255.0, 0.5)
	var narr_par: Node = _narr_label.get_parent() if is_instance_valid(_narr_label) else null
	var narr_home := Vector2.ZERO
	if narr_par is Control:
		narr_home = (narr_par as Control).position
		(narr_par as Control).create_tween().tween_property(narr_par, "position:y", vis.y + 40.0, 0.5)
	var cp := "res://assets/converted/monster_%d/monster_%d_%d_image_cutin.tres" % [mid, mid, mid]
	var cut_h := 74.0 * S * 2.0
	if ResourceLoader.exists(cp):
		var cut := Sprite2D.new()
		cut.texture = load(cp)
		cut.material = _pma
		cut.scale = Vector2(S * 2.0, S * 2.0)
		cut.z_index = 10
		cut.position = Vector2(vis.x * 1.5, vis.y * 0.5)
		root.add_child(cut)
		var ch := cut.texture.get_size().y
		if ch > 1.0:
			cut_h = ch * S * 2.0
		cut.create_tween().tween_property(cut, "position:x", vis.x * 0.5, 0.5)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var bar_h := float(_adv.get("scene_adventure_bar", {}).get("h", 23)) * S
	for i in 2:
		var bar := _spr("adventure_ui", "scene_adventure_bar", _adv, S)
		if bar == null: continue
		bar.flip_h = (i == 0)
		bar.position = Vector2(vis.x * 0.5,
			vis.y * 0.5 + (-cut_h * 0.5 if i == 0 else cut_h * 0.5))
		bar.z_index = 15
		root.add_child(bar)
		var dir := 1.0 if i == 0 else -1.0
		_alert_scroll(bar, "scene_adventure_bar_deco_%s_move" % ("right" if i == 0 else "left"),
			S, 0.0, dir * vis.x, 9.0, vis.x)
		_alert_scroll(bar, "scene_adventure_txt_danger",
			S * 0.5, (-bar_h * 0.5 - 26.0) if i == 0 else (bar_h * 0.5 + 26.0),
			dir * vis.x * 2.0, 4.5, vis.x)
	var life := 3.0 / maxf(_speed, 1.0)
	get_tree().create_timer(life).timeout.connect(func() -> void:
		if is_instance_valid(narr_par) and narr_par is Control:
			(narr_par as Control).create_tween().tween_property(narr_par, "position", narr_home, 0.3)
		if is_instance_valid(lay):
			var ft := dim.create_tween()
			ft.tween_property(root, "modulate:a", 0.0, 0.25)
			ft.parallel().tween_property(dim, "color:a", 0.0, 0.25)
			ft.tween_callback(lay.queue_free))

func _alert_scroll(bar: Sprite2D, key: String, scale: float, y: float,
		travel: float, dur: float, screen_w: float) -> void:
	var e: Dictionary = _adv.get(key, {})
	var w := float(e.get("w", 0)) * scale
	if w <= 1.0:
		return
	var n := int(ceil((screen_w * 2.0 + absf(travel)) / w)) + 1
	var strip := Node2D.new()
	strip.position = Vector2(0, y)
	bar.add_child(strip)
	var x0 := -screen_w - (w if travel > 0.0 else 0.0)
	for i in n:
		var s := _spr("adventure_ui", key, _adv, scale)
		if s == null:
			strip.queue_free(); return
		s.scale /= bar.scale.x
		s.position = Vector2((x0 + w * i) / bar.scale.x, 0)
		strip.add_child(s)
	var tw := strip.create_tween().set_loops()
	tw.tween_property(strip, "position:x", travel / bar.scale.x, dur).from(0.0)

func _go_battle() -> void:
	var hp_state: Dictionary = {} if _healed else _params.get("hp_state", {})
	var enc := int(_params.get("enc", 0))
	var ei := _enc_index()
	var is_boss := _is_boss_at(ei)
	var elite := false
	if not is_boss:
		var er := RandomNumberGenerator.new()
		er.seed = hash("elite_%s_%d_%d" % [String(_params.get("stage", "")), enc,
			int(_params.get("run_seed", 0))])
		elite = er.randf() < 0.10
	Scenes.goto("battle", {"stage": String(_params.get("stage", "")),
		"region": _params.get("region", "yutakan"), "enc": enc, "enemy_index": ei,
		"elite": elite,
		"boss": is_boss,
		"hp_state": hp_state,
		"kades": _is_kades(), "field": _base_field(),
		"night": bool(_params.get("night", false)),
		"run_seed": int(_params.get("run_seed", 0)),
		"party_uids": _run_party.duplicate(), "hero": bool(_params.get("hero", false))})

func _pick_weighted(rows: Array, rr: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in rows:
		total += maxf(0.0, float((r as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return rr.randi() % rows.size()
	var t := rr.randf() * total
	for i in rows.size():
		t -= maxf(0.0, float((rows[i] as Dictionary).get("weight", 1)))
		if t <= 0.0:
			return i
	return rows.size() - 1

func _enemy_id_for_enc() -> int:
	var enemies: Array = _stage.get("enemies", [])
	if enemies.is_empty(): return 1
	var enc := _rboss_enc if _rboss_enc >= 0 else clampi(int(_params.get("enc", 0)), 0, enemies.size() - 1)
	var e: Dictionary = enemies[enc]
	var eid: Variant = e.get("asset_id", e.get("id", 1))
	return int(eid) if eid != null else 1

func _open_dialogue(text: String, on_done := Callable()) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 80; add_child(layer)
	const BH := 120.0
	var bw: float = vis.x - 20.0
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 16; box.patch_margin_top = 16; box.patch_margin_right = 16; box.patch_margin_bottom = 16
	box.size = Vector2(bw, BH); box.position = Vector2(10, vis.y - BH - 12)
	layer.add_child(box)
	var lbl := Label.new(); lbl.text = text
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.15, 0.1, 0.03))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(14, 12); lbl.size = Vector2(bw - 28, BH - 24)
	lbl.visible_characters = 0
	box.add_child(lbl)
	var arrow := _spr("common_ui", "common_btn_arrow2", _man("common_ui"), 0.8)
	if arrow:
		arrow.position = Vector2(bw - 26, BH - 22); arrow.visible = false; box.add_child(arrow)
	var total := text.length()
	var done := {"v": false}
	var timer := Timer.new(); timer.wait_time = 1.0 / 40.0; timer.one_shot = false
	layer.add_child(timer)
	var reveal_all := func() -> void:
		lbl.visible_characters = -1; done["v"] = true
		if timer and is_instance_valid(timer): timer.stop()
		if arrow:
			arrow.visible = true
			var tw := arrow.create_tween().set_loops()
			tw.tween_property(arrow, "position:y", BH - 16, 0.4).as_relative()
			tw.tween_property(arrow, "position:y", BH - 22, 0.4)
	timer.timeout.connect(func() -> void:
		lbl.visible_characters += 1
		if lbl.visible_characters >= total: reveal_all.call())
	timer.start()
	var catcher := Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if not done["v"]:
				reveal_all.call()
			else:
				if is_instance_valid(layer): layer.queue_free()
				if on_done.is_valid(): on_done.call())
	layer.add_child(catcher)

func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

func _spr(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _portrait(id: int, stage: String, scale := 1.0) -> Sprite2D:
	var dir := "portrait_%d" % id
	return _spr(dir, "dragon_dragon_%d_box_%s" % [id, stage], _man(dir), scale)

var _npc_lines_cache: Dictionary = {}
var _npc_lines_loaded := false
func _npc_line(npc: String, situation: String, fallback: String) -> String:
	if not _npc_lines_loaded:
		_npc_lines_loaded = true
		var f := FileAccess.open(Data.data_path("npc_lines.json"), FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _npc_lines_cache = d
	var byn: Dictionary = _npc_lines_cache.get(npc, {})
	var v = byn.get(situation, "")
	return String(v) if typeof(v) == TYPE_STRING and String(v) != "" else fallback
