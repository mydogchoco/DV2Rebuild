extends Control

const TAB_TRAIN := 0
const TAB_MATE := 1
const TAB_NEST := 2
const TAB_LATEA := 3

const S_TITLE := "육성"
const S_ANNONCE := "알림"
const S_TRAIN_CLEAN := "#d3b906bf"
const S_TRAIN_READY := "사용 가능"
const S_TRAIN_SELECT := "훈련 선택"
const S_TRAIN_DO := "훈련하기"
const S_TRAIN_RESET := "대기 시간 초기화까지 %s이 남았습니다.\n즉시 초기화하시겠습니까?"
const S_TRAIN_OPEN_MSG := "%s이(가) 되면 열리는 훈련 둥지입니다.\n다이아를 사용하여 즉시 여시겠습니까?"
const S_TRAIN_NO_MONEY := "#1b5b4a24"
const S_TRAIN_RESET_T := "#9d5e425c"
const S_TRAIN_OPEN_T := "#01958b21"
const S_BREED := "교배"
const S_BREED_DONE := "완료"
const S_BREED_INSTANT := "즉시 완료"
const S_BREED_INSTANT_MSG := "교배 완료까지 %s이 남았습니다.\n즉시 완료 하시겠습니까?"
const S_BREED_ERR2 := "#ac9e094d"
const S_BREED_ERR4 := "#eb2e996e"
const S_BREED_CERT_T := "교배 증명서"
const S_BREED_CERT_C := "#6922be63"
const S_BREED_HISTORY := "#3d36330b"
const S_NEST_EMPTY := "#691e8029"
const S_NEST_INFO := "하늘둥지에서 맡겨 놓은 드래곤을 찾아올 수 있습니다!\n드래곤을 찾아올 때는 소량의 보석이 소모되니 꼭! 기억해두세요!"
const S_NEST_OK := "축하드려요! 맡겼던 드래곤을 불러오는데 성공하셨습니다!\n지금 바로 동굴로 달려가서 되찾은 드래곤을 확인해보세요!"
const S_LATEA_EMPTY := "#6e84a759"
const S_LATEA_INFO := "라테아에서 드래곤을 찾아올 수 있습니다!\n드래곤을 찾아올 때는 소량의 보석이 소모되니 꼭! 기억해두세요!"
const S_LATEA_OK := "축하드려요! 라테아에서 드래곤을 불러오는데 성공하셨습니다!\n지금 바로 동굴로 달려가서 되찾은 드래곤을 확인해보세요!"
const S_NEST_ASK := "#baf5637e"
const S_LATEA_ASK := "#50356c65"

const FONT_SUB := "res://assets/converted/font_ui/font_subtitle.fnt"

var _params: Dictionary = {}
var _tab := TAB_TRAIN
var _npc: NpcPortrait
var _box: BottomTextBox
var _tick: Timer
var _layer: Control
var _countdowns: Array = []
var _mate_pick := {}

func enter(params: Dictionary = {}) -> void:
	Bgm.play("bg_promote")
	_params = params
	match String(params.get("tab", "")):
		"mate": _tab = TAB_MATE
		"nest": _tab = TAB_NEST
		"latea": _tab = TAB_LATEA
		"train": _tab = TAB_TRAIN
	if not _tabs().has(_tab):
		_tab = TAB_TRAIN
	if is_inside_tree():
		_rebuild()

func _ready() -> void:
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.autostart = true
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	if not _tabs().has(_tab):
		_tab = TAB_TRAIN
	_rebuild()

func _cfg() -> Dictionary:
	return Data.promote

func _breed_enabled() -> bool:
	return int(_cfg().get("breed_enable", 0)) == 1

func _tabs() -> Array:
	return [TAB_TRAIN, TAB_MATE, TAB_NEST] if _breed_enabled() \
		else [TAB_TRAIN, TAB_NEST, TAB_LATEA]

const TAB_FRAME := {
	TAB_TRAIN: "scene_promote_tab_train_kr",
	TAB_MATE: "scene_promote_tab_breed_kr",
	TAB_NEST: "scene_promote_tab_history_kr",
	TAB_LATEA: "scene_promote_tab_latea_kr",
}

func _rebuild() -> void:
	for c in get_children():
		if c != _tick:
			c.queue_free()
	_npc = null
	_box = null
	_layer = null
	_countdowns.clear()
	var vis := _vis()
	_build_bg()
	_build_layer(vis)
	_build_npc(vis)
	_build_wallet(vis)
	_build_title(vis)

func _build_bg() -> void:
	var p := "res://assets/converted/promote_bg/bg.jpg"
	if ResourceLoader.exists(p):
		var tr := TextureRect.new()
		tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.13, 0.16, 0.12)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

func _build_layer(vis: Vector2) -> void:
	_layer = Control.new()
	_layer.size = Vector2(vis.x - 280.0, vis.y - 315.0)
	_layer.position = Vector2(0.0, 180.0)
	_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_layer)
	match _tab:
		TAB_TRAIN: _build_training()
		TAB_MATE: _build_mate()
		TAB_LATEA: _build_history(true)
		_: _build_history(false)

func _build_title(vis: Vector2) -> void:
	var bar := AtlasUI.spr("promote_ui", "scene_promote_title_bar", Design.ASSET_SCALE)
	if bar != null:
		var sz := AtlasUI.size_pt("promote_ui", "scene_promote_title_bar")
		bar.scale.x = vis.x / maxf(1.0, sz.x / Design.ASSET_SCALE)
		bar.position = Vector2(vis.x * 0.5, sz.y * 0.5)
		bar.z_index = 9
		add_child(bar)
	var t := Label.new()
	t.text = Data.ui(S_TITLE)
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.35, 0.2, 0.06))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = Vector2(vis.x, 60)
	t.z_index = 10
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)

	var x := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE)
	if x != null:
		x.position = Vector2(vis.x - 42, 34)
		x.z_index = 11
		add_child(x)
	var xb := Button.new()
	xb.flat = true
	xb.size = Vector2(56, 56)
	xb.position = Vector2(vis.x - 70, 6)
	xb.z_index = 11
	xb.pressed.connect(_close)
	add_child(xb)

	var tw := AtlasUI.size_pt("common_ui", "common_tab_bg").x
	var th := AtlasUI.size_pt("common_ui", "common_tab_bg").y
	var tabs := _tabs()
	for i in tabs.size():
		var idx: int = tabs[i]
		var tx := 70.0 + (tw + 5.0) * i
		var drop := 0.0 if idx == _tab else 10.0
		var bg := AtlasUI.spr("common_ui", "common_tab_bg" if idx != _tab else "common_tab_bg4",
			Design.ASSET_SCALE)
		if bg != null:
			bg.position = Vector2(tx + tw * 0.5, th * 0.5 - drop)
			bg.z_index = 6
			add_child(bg)
		var lbl := AtlasUI.spr("promote_ui", String(TAB_FRAME[idx]), Design.ASSET_SCALE)
		if lbl != null:
			lbl.position = Vector2(tx + tw * 0.5, th - 50.0 - drop)
			lbl.z_index = 7
			add_child(lbl)
		var b := Button.new()
		b.flat = true
		b.size = Vector2(tw, th - 40.0)
		b.position = Vector2(tx, 20)
		b.z_index = 8
		b.pressed.connect(func(): _on_tab(idx))
		add_child(b)

func _on_tab(idx: int) -> void:
	if idx == _tab:
		return
	Bgm.sfx("effect_button")
	_tab = idx
	_mate_pick.clear()
	_rebuild()

func _build_wallet(vis: Vector2) -> void:
	var sz := AtlasUI.size_pt("promote_ui", "scene_promote_cash_box")
	var root := Control.new()
	root.size = sz
	root.position = Vector2(vis.x - sz.x - 8.0, 96.0)
	root.z_index = 8
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := AtlasUI.spr("promote_ui", "scene_promote_cash_box", Design.ASSET_SCALE)
	if bg != null:
		bg.position = sz * 0.5
		root.add_child(bg)
	var rows := [["common_coin_small1", AtlasUI.comma(UserDB.gold())],
		["common_diamond_small1", AtlasUI.comma(UserDB.diamond())]]
	for i in rows.size():
		var ic := AtlasUI.spr("common_ui", String(rows[i][0]), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(46.0, sz.y * 0.5 + (i - 0.5) * 48.0)
			root.add_child(ic)
		var l := Label.new()
		l.text = String(rows[i][1])
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.04))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(74.0, sz.y * 0.5 + (i - 0.5) * 48.0 - 14.0)
		l.size = Vector2(sz.x - 84.0, 28.0)
		root.add_child(l)

func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("dilis", _pick_emotion("dilis"))
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		_npc.position = Vector2(vis.x - 150.0, vis.y)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - 300.0
	_box.z_index = 12
	add_child(_box)
	_box.clicked.connect(func(): _say(_promote_talk()))
	_enter_talk()

func _pick_emotion(npc: String) -> int:
	var nums := AtlasUI.npc_emotions(npc)
	return int(nums[randi() % nums.size()]) if not nums.is_empty() else 1

func _enter_talk() -> void:
	match _tab:
		TAB_NEST:
			var empty := UserDB.storage_dragons().is_empty()
			_say(Data.ui(S_NEST_EMPTY) if empty else S_NEST_INFO, 4 if empty else 2)
		TAB_LATEA:
			var e2 := UserDB.latea_records().is_empty()
			_say(Data.ui(S_LATEA_EMPTY) if e2 else S_LATEA_INFO, 4 if e2 else 2)
		_:
			_say(_promote_talk())

func _promote_talk() -> String:
	var screen: Dictionary = Data.npc_talk.get("screen", {})
	var pool: Array = (screen.get("promote.breed_talk", {}) as Dictionary).get("lines", []) \
		if _tab == TAB_MATE else (screen.get("promote.talk", {}) as Dictionary).get("lines", [])
	if pool.is_empty():
		pool = Data.npc_talk.get("idle", {}).get("dilis", [])
	return String(pool[randi() % pool.size()]) if not pool.is_empty() else ""

func _npc_name() -> String:
	var per = Data.npc_lines_doc.get("dilis", null)
	if per is Dictionary and per.has("name"):
		return String(per["name"])
	return "딜리스"

const REACTION_EMOTIONS := [4, 7]

func _say(line: String, emo := 0) -> void:
	if not is_instance_valid(_box):
		return
	if is_instance_valid(_npc):
		if emo > 0:
			_npc.set_emotion(emo)
		elif REACTION_EMOTIONS.has(_npc.emotion):
			_npc.set_emotion(1)
	_box.show_text(_npc_name(), line)
	if is_instance_valid(_npc):
		_npc.set_talking(true)
		if not _box.finished.is_connected(_stop_talk):
			_box.finished.connect(_stop_talk)

func _stop_talk() -> void:
	if is_instance_valid(_npc):
		_npc.set_talking(false)

func _toast(msg: String, emo := 0) -> void:
	_say(msg, emo)

func _ly(y: float) -> float:
	return _layer.size.y - y

func _camp_state() -> Dictionary:
	var d = UserDB.get_pmeta("training", {})
	return d if d is Dictionary else {}

func _camp_until(camp: int) -> int:
	return int(_camp_state().get(str(camp), 0))

func _set_camp_until(camp: int, until: int) -> void:
	var st := _camp_state().duplicate()
	if until <= 0:
		st.erase(str(camp))
	else:
		st[str(camp)] = until
	UserDB.set_pmeta("training", st)

func _train_cfg() -> Dictionary:
	return _cfg().get("training", {})

func _unlock_rule(camp: int) -> Dictionary:
	var arr: Array = _train_cfg().get("camp_unlock", [])
	return arr[camp - 1] if camp - 1 < arr.size() else {}

func _camp_unlocked(camp: int) -> bool:
	var rule := _unlock_rule(camp)
	if String(rule.get("cond", "none")) == "none":
		return true
	var u = UserDB.get_pmeta("training_unlocked", [])
	if (u is Array) and (camp in u):
		return true
	if String(rule.get("cond", "")) == "colosseum_rating":
		return Colosseum.rating_of(String(rule.get("mode", "single"))) >= int(rule.get("value", 0))
	return false

func _build_training() -> void:
	var lw := _layer.size.x
	var lh := _layer.size.y
	var nest := AtlasUI.src_pt("promote_ui", "scene_promote_nest1")
	var gap := (lw - nest.x * 2.0) * 0.25
	var pos := [
		Vector2(lw * 0.5 - 150.0 - gap, lh * 0.5 - nest.y * 0.5),
		Vector2(lw * 0.5, lh - nest.y * 0.5),
		Vector2(lw * 0.5 + 150.0 + gap, lh * 0.5 - nest.y * 0.5),
	]
	for i in 3:
		_build_camp(i + 1, Vector2(pos[i].x, _ly(pos[i].y)), nest)

func _build_camp(camp: int, center: Vector2, nest: Vector2) -> void:
	var unlocked := _camp_unlocked(camp)
	var until := _camp_until(camp)
	var busy := unlocked and until > int(Time.get_unix_time_from_system())
	var frame := "scene_promote_nest3"
	var plate_key := "scene_promote_train_box2"
	var text := String(_unlock_rule(camp).get("label", ""))
	if unlocked:
		frame = "scene_promote_nest1" if busy else "scene_promote_nest2"
		plate_key = "scene_promote_train_box1"
		text = Data.ui(S_TRAIN_CLEAN) if busy else S_TRAIN_READY

	var s := AtlasUI.spr("promote_ui", frame, Design.ASSET_SCALE)
	if s != null:
		s.position = center
		s.z_index = 2
		_layer.add_child(s)
		_camp_entry_anim(s, center, camp - 1)

	var plate_y := center.y + nest.y * 0.5 + 10.0
	var plate := AtlasUI.spr("promote_ui", plate_key, Design.ASSET_SCALE)
	if plate != null:
		plate.position = Vector2(center.x, plate_y)
		plate.z_index = 3
		_layer.add_child(plate)
	var lb := _bmf(text, 16)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.size = Vector2(240.0, 40.0)
	lb.position = Vector2(center.x - 120.0, plate_y - 12.0)
	lb.z_index = 4
	_layer.add_child(lb)

	if not unlocked:
		var lock := AtlasUI.spr("common_ui", "common_lock", Design.ASSET_SCALE)
		if lock != null:
			lock.position = center
			lock.z_index = 4
			_layer.add_child(lock)
	elif busy:
		var cd := _bmf(_hms(until - int(Time.get_unix_time_from_system())), 18)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.size = Vector2(200.0, 26.0)
		cd.position = center - Vector2(100.0, 13.0)
		cd.z_index = 4
		_layer.add_child(cd)
		_countdowns.append({"node": cd, "end": until, "fmt": "%s"})

	var b := Button.new()
	b.flat = true
	b.size = Vector2(nest.x, nest.y)
	b.position = center - nest * 0.5
	b.z_index = 5
	b.pressed.connect(func(): _on_click_camp(camp))
	_layer.add_child(b)

func _camp_entry_anim(node: Sprite2D, pos: Vector2, i: int) -> void:
	var S := Design.ASSET_SCALE
	node.position = pos - Vector2(0, 10.0)
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_interval(0.3 * float(i))
	tw.set_parallel(true)
	tw.tween_property(node, "position:y", pos.y, 0.2)
	tw.tween_property(node, "modulate:a", 1.0, 0.2)
	tw.set_parallel(false)
	tw.tween_property(node, "scale", Vector2(S * 1.05, S * 0.95), 0.2)
	tw.tween_property(node, "scale", Vector2(S * 0.95, S * 1.05), 0.2)
	tw.tween_property(node, "scale", Vector2(S, S), 0.2)

func _on_click_camp(camp: int) -> void:
	Bgm.sfx("effect_button")
	if not _camp_unlocked(camp):
		var dia := int(_train_cfg().get("slot_open_dia", 99))
		MessageWindow.open(self, Data.ui(S_TRAIN_OPEN_T),
			S_TRAIN_OPEN_MSG % String(_unlock_rule(camp).get("label", "조건")),
			func(): _open_slot(camp, dia), "확인", "취소", 0, dia)
		return
	var until := _camp_until(camp)
	var now := int(Time.get_unix_time_from_system())
	if until > now:
		var per := maxi(1, int(_train_cfg().get("clean_reset_sec_per_dia", 300)))
		var cost := (until - now) / per
		MessageWindow.open(self, Data.ui(S_TRAIN_RESET_T), S_TRAIN_RESET % _hms(until - now),
			func(): _reset_clean(camp, cost), "확인", "취소", 0, cost)
		return
	_open_dragon_select(camp)

func _open_slot(camp: int, dia: int) -> void:
	if not UserDB.spend("diamond", dia):
		MessageWindow.open(self, S_ANNONCE, Data.ui(S_TRAIN_NO_MONEY), func(): pass, "확인", "")
		return
	var u = UserDB.get_pmeta("training_unlocked", [])
	var arr: Array = (u as Array).duplicate() if u is Array else []
	arr.append(camp)
	UserDB.set_pmeta("training_unlocked", arr)
	_rebuild()

func _reset_clean(camp: int, cost: int) -> void:
	if cost > 0 and not UserDB.spend("diamond", cost):
		MessageWindow.open(self, S_ANNONCE, Data.ui(S_TRAIN_NO_MONEY), func(): pass, "확인", "")
		return
	_set_camp_until(camp, 0)
	_rebuild()

func _open_dragon_select(camp: int) -> void:
	var uids: Array = []
	var off: Array = []
	for d in UserDB.dragons():
		var uid := int((d as Dictionary).get("uid", 0))
		uids.append(uid)
		if _train_disabled(d):
			off.append(uid)
	if uids.is_empty():
		_toast(Data.ui(S_BREED_ERR4))
		return
	DragonPicker.open(self, S_TRAIN_DO, uids, off, func(uid: int):
		TrainingPicker.open(self, S_TRAIN_SELECT, uid, func(no: int):
			_do_train(camp, uid, no)))

func _train_disabled(d: Dictionary) -> bool:
	if UserDB.is_egg(d):
		return true
	if int(d.get("level", 1)) > 49:
		return true
	if int(d.get("hp_state", 1)) == 0 or bool(d.get("incapacitated", false)):
		return true
	return _is_breeding(int(d.get("uid", 0)))

func _train_row(no: int) -> Dictionary:
	for r in _train_cfg().get("info_train_v2", []):
		if int((r as Dictionary).get("train_no", 0)) == no:
			return r
	return {}

func _do_train(camp: int, uid: int, no: int) -> void:
	var row := _train_row(no)
	if row.is_empty():
		return
	var dia := String(row.get("fee_type", "gold")) == "dia"
	if not UserDB.spend("diamond" if dia else "gold", int(row.get("fee", 0))):
		MessageWindow.open(self, S_ANNONCE, Data.ui(S_TRAIN_NO_MONEY), func(): pass, "확인", "")
		return
	_set_camp_until(camp, int(Time.get_unix_time_from_system()) + int(row.get("need_time", 0)))
	var ev := UserDB.grant_exp(uid, int(row.get("exp", 0)))
	_rebuild()
	if int(ev.get("levels_gained", 0)) > 0:
		LevelUpScreen.open(self, uid, {"on_close": func(): _rebuild()})
	else:
		_toast("%s 이(가) 훈련을 마쳤어요! EXP +%s"
			% [Icons.name_of(UserDB.get_dragon(uid)), AtlasUI.comma(int(row.get("exp", 0)))], 7)

func _mate() -> Dictionary:
	var d = UserDB.get_pmeta("mate", {})
	return d if d is Dictionary else {}

func _mate_cfg() -> Dictionary:
	return _cfg().get("mate", {})

func _is_breeding(uid: int) -> bool:
	var st := _mate()
	return not st.is_empty() and (int(st.get("a", 0)) == uid or int(st.get("b", 0)) == uid)

func _build_mate() -> void:
	var lw := _layer.size.x
	var lh := _layer.size.y
	var cx := lw * 0.5
	var gap := lw * 0.8 * 0.25 + 40.0
	var st := _mate()
	var running := not st.is_empty()
	var remain := int(st.get("end", 0)) - int(Time.get_unix_time_from_system()) if running else 0

	for i in 2:
		var bx := cx + (-1.0 if i == 0 else 1.0) * gap
		var bl := AtlasUI.spr("common_ui", "common_backlight4", Design.ASSET_SCALE * 0.8)
		if bl != null:
			bl.position = Vector2(bx, _ly(220.0))
			bl.z_index = 1
			_layer.add_child(bl)
			var tw := bl.create_tween().set_loops()
			tw.tween_property(bl, "rotation", deg_to_rad(60.0), 5.0).as_relative()

	var nest := AtlasUI.src_pt("promote_ui", "scene_promote_nest2")
	for i in 2:
		var sx := cx + (-1.0 if i == 0 else 1.0) * gap
		var sy := _ly(140.0)
		var sl := AtlasUI.spr("promote_ui", "scene_promote_nest2", Design.ASSET_SCALE)
		if sl != null:
			sl.position = Vector2(sx, sy)
			sl.z_index = 2
			_layer.add_child(sl)
		var uid := int(st.get("a" if i == 0 else "b", 0)) if running \
			else int(_mate_pick.get(i, 0))
		if uid > 0:
			var d: Dictionary = UserDB.get_dragon(uid)
			var sp := PartySelect._spine_node(Icons.art_id_of(d), Growth.spine_stage(d), 130.0)
			if sp != null:
				sp.position = Vector2(sx, _ly(250.0))
				sp.z_index = 3
				if i == 1:
					sp.scale.x *= -1.0
				_layer.add_child(sp)
				var t2 := sp.create_tween()
				t2.tween_property(sp, "position:y", sp.position.y + 30.0, 0.3)
				t2.tween_property(sp, "position:y", sp.position.y + 20.0, 0.2)
		if not running:
			var slot_i := i
			var b := Button.new()
			b.flat = true
			b.size = nest
			b.position = Vector2(sx, sy) - nest * 0.5
			b.z_index = 5
			b.pressed.connect(func(): _pick_parent(slot_i))
			_layer.add_child(b)

	var bar_w := lw * 0.8
	var bar := AtlasUI.nine("ninepatch_ui", "9patch_train_box3", Vector2(bar_w, 53.0),
		Rect2(20, 20, 4, 4))
	if bar != null:
		bar.position = Vector2(cx - bar_w * 0.5, _ly(50.0) - 26.5)
		bar.z_index = 2
		_layer.add_child(bar)
	var deco := AtlasUI.spr("promote_ui", "scene_promote_breed_box2", Design.ASSET_SCALE)
	if deco != null:
		deco.position = Vector2(cx, _ly(50.0) - 6.0)
		deco.z_index = 3
		_layer.add_child(deco)
	for i in 2:
		var uid := int(st.get("a" if i == 0 else "b", 0)) if running else int(_mate_pick.get(i, 0))
		var nm := Icons.name_of(UserDB.get_dragon(uid)) if uid > 0 else "-"
		var l := Label.new()
		l.text = nm
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(1, 0.97, 0.86))
		l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.04))
		l.add_theme_constant_override("outline_size", 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size = Vector2(bar_w * 0.45, 26.0)
		l.position = Vector2(cx + (-1.0 if i == 0 else 0.05) * bar_w * 0.47, _ly(50.0) - 17.0)
		l.z_index = 4
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(l)

	var hs := AtlasUI.spr("common_ui", "common_btn_history", Design.ASSET_SCALE)
	if hs != null:
		hs.position = Vector2(cx, _ly(65.0))
		hs.z_index = 6
		_layer.add_child(hs)
		var hb := Button.new()
		hb.flat = true
		hb.size = AtlasUI.src_pt("common_ui", "common_btn_history")
		hb.position = Vector2(cx, _ly(65.0)) - hb.size * 0.5
		hb.z_index = 7
		hb.pressed.connect(_open_mate_history)
		_layer.add_child(hb)

	var hy := _ly(lh * 0.5 + 100.0)
	var heart := AtlasUI.spr("promote_ui", "scene_promote_heart", Design.ASSET_SCALE)
	var hsz := AtlasUI.src_pt("promote_ui", "scene_promote_heart")
	if heart != null:
		heart.position = Vector2(cx, hy)
		heart.z_index = 6
		_layer.add_child(heart)
	var cost := _mate_cost()
	var top := _bmf("", 18)
	var bottom := _bmf("", 16)
	for l in [top, bottom]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(180.0, 24.0)
		l.z_index = 8
		_layer.add_child(l)
	top.position = Vector2(cx - 90.0, hy - 25.0 - 12.0)
	bottom.position = Vector2(cx - 90.0, hy + 5.0 - 12.0)
	if running and remain > 0:
		top.text = _hms(remain)
		bottom.text = S_BREED_INSTANT
		_countdowns.append({"node": top, "end": int(st.get("end", 0)), "fmt": "%s"})
		_mate_running_fx(Vector2(cx, hy), gap)
	elif running:
		top.text = S_BREED_DONE
	else:
		var ci := AtlasUI.spr("common_ui", "common_coin_small2", Design.ASSET_SCALE)
		if ci != null:
			ci.position = Vector2(cx - 45.0, hy - 25.0)
			ci.z_index = 8
			_layer.add_child(ci)
		top.text = AtlasUI.comma(cost)
		bottom.text = S_BREED
	var hb2 := Button.new()
	hb2.flat = true
	hb2.size = hsz
	hb2.position = Vector2(cx, hy) - hsz * 0.5
	hb2.z_index = 9
	hb2.pressed.connect(_on_click_ok)
	_layer.add_child(hb2)

func _mate_cost() -> int:
	var per := int(_mate_cfg().get("grade_cost_gold", 500))
	var g := 0
	for i in 2:
		var uid := int(_mate_pick.get(i, 0))
		if uid > 0:
			g += int(floor(_grade_of(UserDB.get_dragon(uid))))
	return g * per

func _grade_of(d: Dictionary) -> float:
	if d.is_empty():
		return 0.0
	var ddef: Dictionary = Data.get_dragon(int(d.get("id", 0)))
	return Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
		d.get("gain_log", []), Data.level_curve.get("grade", {}))

func _mate_running_fx(heart_pos: Vector2, gap: float) -> void:
	Bgm.sfx("effect_dragon_heart")
	for i in 2:
		var ghost := AtlasUI.spr("promote_ui", "scene_promote_heart",
			Design.ASSET_SCALE * (1.1 if i == 0 else 1.2))
		if ghost == null:
			continue
		ghost.position = heart_pos
		ghost.z_index = 8 + i
		ghost.modulate.a = 0.0
		_layer.add_child(ghost)
		var base := Design.ASSET_SCALE * (1.1 if i == 0 else 1.2)
		var tw := ghost.create_tween().set_loops()
		if i == 1:
			tw.tween_interval(1.4)
		tw.tween_property(ghost, "modulate:a", 100.0 / 255.0, 0.1)
		tw.set_parallel(true)
		tw.tween_property(ghost, "scale", Vector2.ONE * Design.ASSET_SCALE * 1.8, 0.9)
		tw.tween_property(ghost, "modulate:a", 0.0, 0.9)
		tw.set_parallel(false)
		tw.tween_property(ghost, "scale", Vector2.ONE * base, 0.6 if i == 0 else 0.1)
	var cx := _layer.size.x * 0.5
	for i in 2:
		CocosParticle.spawn(_layer, "promote_mate",
			Vector2(cx + (-1.0 if i == 0 else 1.0) * gap, _ly(250.0)), 5, 0.3)

func _pick_parent(slot: int) -> void:
	Bgm.sfx("effect_button")
	var minlv := int(_mate_cfg().get("min_level", 35))
	var uids: Array = []
	var off: Array = []
	var other := int(_mate_pick.get(1 - slot, 0))
	for d in UserDB.dragons():
		var uid := int((d as Dictionary).get("uid", 0))
		uids.append(uid)
		if UserDB.is_egg(d) or int((d as Dictionary).get("level", 1)) < minlv \
				or uid == other or uid == UserDB.active_uid() or _is_breeding(uid):
			off.append(uid)
	DragonPicker.open(self, S_BREED, uids, off, func(uid: int):
		_mate_pick[slot] = uid
		_rebuild())

func _on_click_ok() -> void:
	Bgm.sfx("effect_button")
	var st := _mate()
	if st.is_empty():
		if _mate_pick.size() < 2:
			_toast(Data.ui(S_BREED_ERR4), 4)
			return
		var cost := _mate_cost()
		if not UserDB.spend("gold", cost):
			MessageWindow.open(self, S_ANNONCE, Data.ui(S_TRAIN_NO_MONEY), func(): pass, "확인", "")
			return
		var a := int(_mate_pick[0])
		var b := int(_mate_pick[1])
		UserDB.set_pmeta("mate", {"a": a, "b": b,
			"end": int(Time.get_unix_time_from_system()) + int(_mate_cfg().get("breed_sec", 21600)),
			"egg": _mate_result(a, b)})
		_mate_pick.clear()
		_rebuild()
		return
	var remain := int(st.get("end", 0)) - int(Time.get_unix_time_from_system())
	if remain > 0:
		var per := maxi(1, int(_mate_cfg().get("instant_sec_per_dia", 3600)))
		var dia := int(ceil(float(remain) / float(per)))
		MessageWindow.open(self, S_BREED_INSTANT, S_BREED_INSTANT_MSG % _hms(remain),
			func(): _instant_mate(dia), "확인", "취소", 0, dia)
		return
	_finish_mate()

func _instant_mate(dia: int) -> void:
	if dia > 0 and not UserDB.spend("diamond", dia):
		MessageWindow.open(self, S_ANNONCE, Data.ui(S_TRAIN_NO_MONEY), func(): pass, "확인", "")
		return
	var st := _mate().duplicate()
	st["end"] = int(Time.get_unix_time_from_system())
	UserDB.set_pmeta("mate", st)
	_rebuild()

func _mate_result(a: int, b: int) -> String:
	var ea := _element_egg(a)
	var eb := _element_egg(b)
	for r in Data.combine_egg.get("recipes", []):
		var mats: Array = r.get("materials", [])
		if mats.size() == 2 and ((mats[0] == ea and mats[1] == eb) or (mats[0] == eb and mats[1] == ea)):
			return String(r.get("target", ea))
	return ea if randi() % 2 == 0 else eb

func _element_egg(uid: int) -> String:
	var d: Dictionary = UserDB.get_dragon(uid)
	var el := Icons.element_of(d)
	var key := "mall_%s_egg" % el
	return key if Data.items.has(key) else "mall_fire_egg"

func _finish_mate() -> void:
	var st := _mate()
	var key := String(st.get("egg", ""))
	var a := int(st.get("a", 0))
	var b := int(st.get("b", 0))
	if key != "":
		UserDB.add_item(key, 1)
	_push_mate_history(a, b, key)
	UserDB.set_pmeta("mate", {})

	var vis := _vis()
	var lay := CanvasLayer.new()
	lay.layer = 60
	add_child(lay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 150.0 / 255.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	lay.add_child(dim)
	var white := ColorRect.new()
	white.color = Color(1, 1, 1, 0)
	white.set_anchors_preset(Control.PRESET_FULL_RECT)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(white)

	var c := Vector2(vis.x * 0.5, vis.y * 0.5 + 35.0)
	var holder := Node2D.new()
	lay.add_child(holder)
	Bgm.sfx("effect_dragon_incubation")
	for k in ["common_nest2", "common_breed_egg", "common_nest1"]:
		var s := AtlasUI.spr("common_ui", k, Design.ASSET_SCALE * 1.5)
		if s != null:
			s.position = c
			holder.add_child(s)
	var egl := _egglight()
	if egl != null:
		egl.position = Vector2(vis.x * 0.5 - 7.0, vis.y * 0.5 + 100.0)
		egl.scale = Vector2.ONE * 0.93
		holder.add_child(egl)
		var t1 := egl.create_tween()
		t1.tween_interval(4.0)
		t1.tween_property(egl, "modulate:a", 0.0, 0.5)
	var tw := white.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(white, "color:a", 1.0, 0.5)
	tw.tween_interval(1.0)
	tw.tween_callback(func():
		lay.queue_free()
		_open_certificate(a, b, key))

func _egglight() -> Node2D:
	const P := "res://scenes/fx/egglight.tscn"
	if not ResourceLoader.exists(P):
		return null
	var n = (load(P) as PackedScene).instantiate()
	if not (n is Node2D):
		return null
	var ap: AnimationPlayer = n.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("egglight"):
		ap.get_animation("egglight").loop_mode = Animation.LOOP_NONE
		ap.play("egglight")
	return n

func _open_certificate(a: int, b: int, egg_key: String) -> void:
	var vis := _vis()
	var lay := CanvasLayer.new()
	lay.layer = 61
	add_child(lay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	lay.add_child(dim)
	var root := Node2D.new()
	root.position = Vector2(vis.x * 0.5, vis.y * 0.5)
	lay.add_child(root)

	var pop := AtlasUI.spr("worldmap_ui", "scene_worldmap_certificate_popup", Design.ASSET_SCALE)
	var psz := AtlasUI.src_pt("worldmap_ui", "scene_worldmap_certificate_popup")
	if pop != null:
		root.add_child(pop)
	var line := AtlasUI.spr("worldmap_ui", "scene_worldmap_certificate_popup_line",
		Design.ASSET_SCALE)
	if line != null:
		line.position = Vector2(0, -psz.y * 0.5 + 84.0)
		root.add_child(line)
	var mark := AtlasUI.spr("worldmap_ui", "scene_worldmap_mark", Design.ASSET_SCALE)
	if mark != null:
		mark.position = Vector2(psz.x * 0.5 - 70.0, psz.y * 0.5 - 70.0)
		mark.modulate.a = 0.85
		root.add_child(mark)

	var title := _bmf(S_BREED_CERT_T, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(psz.x, 32.0)
	title.position = Vector2(-psz.x * 0.5, -psz.y * 0.5 + 40.0)
	root.add_child(title)

	var ep := Data.item_icon_path(egg_key)
	var et: Texture2D = load(ep) if ep != "" and ResourceLoader.exists(ep) else null
	if et != null:
		var es := Sprite2D.new()
		es.texture = et
		es.material = AtlasUI.pma()
		es.scale = Vector2.ONE * Design.ASSET_SCALE
		es.position = Vector2(0, -20.0)
		root.add_child(es)
	var nm := _bmf(Data.item_name(egg_key), 22)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size = Vector2(psz.x, 28.0)
	nm.position = Vector2(-psz.x * 0.5, 40.0)
	root.add_child(nm)

	var par := _bmf("%s  ♥  %s" % [Icons.name_of(UserDB.get_dragon(a)),
		Icons.name_of(UserDB.get_dragon(b))], 18)
	par.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	par.size = Vector2(psz.x, 24.0)
	par.position = Vector2(-psz.x * 0.5, 76.0)
	root.add_child(par)

	var cm := Label.new()
	cm.text = Data.ui(S_BREED_CERT_C)
	cm.add_theme_font_size_override("font_size", 15)
	cm.add_theme_color_override("font_color", Color(0.3, 0.22, 0.1))
	cm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cm.size = Vector2(psz.x - 80.0, 44.0)
	cm.position = Vector2(-psz.x * 0.5 + 40.0, 106.0)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cm)

	var ok := AtlasUI.spr("worldmap_ui", "scene_worldmap_btn_ok_certificate", Design.ASSET_SCALE)
	var oksz := AtlasUI.src_pt("worldmap_ui", "scene_worldmap_btn_ok_certificate")
	if ok != null:
		ok.position = Vector2(0, psz.y * 0.5 - 46.0)
		root.add_child(ok)
	var okb := Button.new()
	okb.flat = true
	okb.size = oksz if oksz.x > 1.0 else Vector2(160, 52)
	okb.position = Vector2(vis.x * 0.5, vis.y * 0.5 + psz.y * 0.5 - 46.0) - okb.size * 0.5
	okb.pressed.connect(func():
		Bgm.sfx("effect_button")
		lay.queue_free()
		_rebuild()
		_toast("%s 을(를) 얻었어요!" % Data.item_name(egg_key), 7))
	lay.add_child(okb)

func _push_mate_history(a: int, b: int, egg_key: String) -> void:
	var recs = UserDB.get_pmeta("mate_history", [])
	var arr: Array = (recs as Array).duplicate() if recs is Array else []
	arr.push_front({
		"a": int(UserDB.get_dragon(a).get("id", 0)),
		"b": int(UserDB.get_dragon(b).get("id", 0)),
		"egg": egg_key,
		"date": Time.get_date_string_from_system(),
	})
	var cap := int(_mate_cfg().get("history_max", 30))
	while arr.size() > maxi(1, cap):
		arr.pop_back()
	UserDB.set_pmeta("mate_history", arr)

func _open_mate_history() -> void:
	Bgm.sfx("effect_button")
	var pop := FramedWindow.open(self, Data.ui(S_BREED_HISTORY))
	var recs = UserDB.get_pmeta("mate_history", [])
	var arr: Array = recs if recs is Array else []
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 90)
	scroll.size = Vector2(pop.win_size.x - 60.0, pop.win_size.y - 150.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	if arr.is_empty():
		col.add_child(_bmf("기록이 없어요.", 18))
		return
	for r in arr:
		col.add_child(_mate_history_row(r, scroll.size.x - 20.0))

func _mate_history_row(r: Dictionary, w: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(w, 84.0)
	var bar := AtlasUI.nine("promote_ui", "scene_promote_history_box", Vector2(w, 84.0), Rect2())
	if bar != null:
		row.add_child(bar)
	var slots := [
		[Icons.species_name(int(r.get("a", 0))), w * 0.22],
		["", w * 0.38],
		[Icons.species_name(int(r.get("b", 0))), w * 0.54],
		["", w * 0.70],
		[Data.item_name(String(r.get("egg", ""))), w * 0.86],
	]
	for i in slots.size():
		if i == 1 or i == 3:
			var s := AtlasUI.spr("common_ui", "common_heart2" if i == 1 else "common_equal",
				Design.ASSET_SCALE * 0.7)
			if s != null:
				s.position = Vector2(float(slots[i][1]), 42.0)
				row.add_child(s)
			continue
		var l := _bmf(String(slots[i][0]), 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = Vector2(w * 0.24, 44.0)
		l.position = Vector2(float(slots[i][1]) - w * 0.12, 22.0)
		row.add_child(l)
	return row

func _build_history(latea: bool) -> void:
	var rows: Array = UserDB.latea_records() if latea else UserDB.storage_dragons()
	if rows.is_empty():
		var l := _bmf(Data.ui(S_LATEA_EMPTY) if latea else Data.ui(S_NEST_EMPTY), 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(_layer.size.x, 30.0)
		l.position = Vector2(0.0, _layer.size.y * 0.5 - 15.0)
		_layer.add_child(l)
		return
	var scroll := ScrollContainer.new()
	scroll.position = Vector2.ZERO
	scroll.size = _layer.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_layer.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(_layer.size.x, 0)
	scroll.add_child(col)
	for i in rows.size():
		col.add_child(_history_cell(i, rows[i], latea, _layer.size.x - 20.0))

func _history_cell(index: int, rec: Dictionary, latea: bool, w: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(w, 100.0)
	var pad := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 100.0 / 255.0)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	pad.add_theme_stylebox_override("panel", sb)
	pad.size = Vector2(w, 100.0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

	var id := int(rec.get("id", 0))
	var lv := int(rec.get("level", 1))
	var bx := AtlasUI.spr("common_ui", "common_box", Design.ASSET_SCALE)
	if bx != null:
		bx.position = Vector2(60.0, 50.0)
		row.add_child(bx)
	var pt := _portrait_tex(id, lv)
	if pt != null:
		var ps := Sprite2D.new()
		ps.texture = pt
		ps.material = AtlasUI.pma()
		ps.scale = Vector2.ONE * 0.7
		ps.position = Vector2(60.0, 50.0)
		row.add_child(ps)
	var nm := _bmf("%s   Lv %d" % [Icons.species_name(id), lv], 20)
	nm.position = Vector2(100.0, 40.0)
	nm.size = Vector2(w - 120.0, 26.0)
	row.add_child(nm)
	if latea:
		var left := _days_left(rec)
		var sub := _bmf("%d일 남음" % left, 15)
		sub.add_theme_color_override("font_color", Color(1, 0.7, 0.5))
		sub.position = Vector2(100.0, 66.0)
		sub.size = Vector2(w - 120.0, 20.0)
		row.add_child(sub)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(w, 100.0)
	b.pressed.connect(func():
		Bgm.sfx("effect_button")
		_open_history_detail(index, rec, latea))
	row.add_child(b)
	return row

func _days_left(rec: Dictionary) -> int:
	var days := int(_cfg().get("latea", {}).get("expire_days", 7))
	if not rec.has("t"):
		return days
	var gone := (int(Time.get_unix_time_from_system()) - int(rec["t"])) / 86400
	return maxi(0, days - gone)

func _open_history_detail(index: int, rec: Dictionary, latea: bool) -> void:
	var id := int(rec.get("id", 0))
	var lv := int(rec.get("level", 1))
	var cost := _restore_price(lv)
	var pop := FramedWindow.open(self, Icons.species_name(id))
	var ws := pop.win_size
	var cx := ws.x * 0.5

	var bl := AtlasUI.spr("common_ui", "common_backlight3", Design.ASSET_SCALE)
	if bl != null:
		bl.position = Vector2(cx, ws.y * 0.5 - 20.0)
		bl.modulate = Color(1, 1, 1, 0.8)
		pop.content.add_child(bl)
	var st := AtlasUI.spr_cocos("stand_ui", "stand_stand1", 1.0, Vector2(0.5, 0))
	if st != null:
		st.position = Vector2(cx, ws.y - 130.0)
		pop.content.add_child(st)
	var sp := PartySelect._spine_node(Icons.species_art_id(id), _stage_for(lv), 170.0)
	if sp != null:
		sp.position = Vector2(cx, ws.y - 138.0)
		pop.content.add_child(sp)
	var nbg := AtlasUI.spr("common_ui", "common_name_bg", Design.ASSET_SCALE)
	if nbg != null:
		nbg.position = Vector2(cx, 108.0)
		pop.content.add_child(nbg)
	var nm := _bmf("%s   Lv %d" % [Icons.species_name(id), lv], 20)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size = Vector2(ws.x, 26.0)
	nm.position = Vector2(0.0, 96.0)
	pop.content.add_child(nm)

	var di := AtlasUI.spr("common_ui", "common_diamond_small1", Design.ASSET_SCALE)
	if di != null:
		di.position = Vector2(cx - 46.0, ws.y - 110.0)
		pop.content.add_child(di)
	var cl := _bmf(str(cost), 20)
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.size = Vector2(120.0, 26.0)
	cl.position = Vector2(cx - 28.0, ws.y - 123.0)
	pop.content.add_child(cl)
	pop.add_action_button("소환", func():
		pop.close()
		MessageWindow.open(self, S_ANNONCE, Data.ui(S_LATEA_ASK) if latea else Data.ui(S_NEST_ASK),
			func(): _do_restore(index, rec, latea, cost), "확인", "취소", 0, cost))

func _restore_price(level: int) -> int:
	var cfgr: Dictionary = _cfg().get("restore", {})
	var bounds: Array = cfgr.get("tier_max_level", [24, 44])
	var table: Array = cfgr.get("price_dia", [5, 15, 30])
	var tier := 0
	if level > int(bounds[0]):
		tier = 1
	if bounds.size() > 1 and level > int(bounds[1]):
		tier = 2
	return int(table[mini(tier, table.size() - 1)])

func _do_restore(index: int, rec: Dictionary, latea: bool, cost: int) -> void:
	if cost > 0 and not UserDB.spend("diamond", cost):
		MessageWindow.open(self, S_ANNONCE, Data.ui(S_TRAIN_NO_MONEY), func(): pass, "확인", "")
		return
	if latea:
		if UserDB.restore_from_latea(index).is_empty():
			UserDB.add_currency("diamond", cost)
			MessageWindow.open(self, S_ANNONCE, "불러올 수 없습니다.", func(): pass, "확인", "")
			return
	elif not UserDB.unstore_dragon(int(rec.get("uid", -1))):
		UserDB.add_currency("diamond", cost)
		MessageWindow.open(self, S_ANNONCE, "동굴에 자리가 없습니다.", func(): pass, "확인", "")
		return
	_rebuild()
	_say(S_LATEA_OK if latea else S_NEST_OK, 2)

func _register_countdown(node: Label, end_unix: int, fmt: String) -> void:
	_countdowns.append({"node": node, "end": end_unix, "fmt": fmt})

func _on_tick() -> void:
	var now := int(Time.get_unix_time_from_system())
	var done := false
	for c in _countdowns:
		var n: Label = c["node"]
		if not is_instance_valid(n):
			continue
		var remain := int(c["end"]) - now
		if remain <= 0:
			done = true
			continue
		n.text = String(c["fmt"]) % _hms(remain)
	if done:
		_countdowns.clear()
		_rebuild()

func _hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d : %02d : %02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]

func _bmf(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	if ResourceLoader.exists(FONT_SUB):
		l.add_theme_font_override("font", load(FONT_SUB))
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _stage_for(level: int) -> String:
	return "adult" if level >= 35 else ("child" if level >= 10 else "baby")

func _portrait_tex(id: int, level: int) -> Texture2D:
	var art := Icons.species_art_id(id)
	for stage in [_stage_for(level), "adult", "child", "baby"]:
		var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_%s.tres" % [art, art, stage]
		if ResourceLoader.exists(p):
			return load(p)
	return null

func _close() -> void:
	var from := String(_params.get("from", "worldmap"))
	if from == "cave":
		Scenes.goto("cave", {})
	elif from == "town":
		Scenes.goto("town", {"area": _params.get("area", "elpis")})
	else:
		Scenes.goto("worldmap", {"region": "yutakan"})

func _vis() -> Vector2:
	return get_viewport_rect().size
