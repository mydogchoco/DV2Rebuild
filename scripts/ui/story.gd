extends Control

const BOX_H := 150.0
const ARROW := "res://assets/converted/common_ui/common_btn_arrow2.tres"
const SKIP := "res://assets/converted/common_ui/common_btn_skip.tres"
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const ART_DIR := "res://assets/converted/scenario"
const TITLE_FONT := "res://assets/converted/font_ui/font_subtitle.fnt"
const CPS := 40.0
const TALK_OPS := ["npc_talk", "user_talk", "talker_in", "talk"]

var _params: Dictionary = {}
var _lines: Array = []
var _idx := 0
var _no := 0
var _part := 0
var _pma: CanvasItemMaterial

var _flow: Array = []
var _flow_i := 0
var _bg_layer: TextureRect
var _host_view: TextureRect
var _illust: TextureRect
var _cut: TextureRect

var _label: Label
var _name_label: Label
var _arrow: Sprite2D
var _typing := false
var _timer: Timer
var _arrow_tween: Tween
var _npc_slots: Dictionary = {}
var _active_npc: Node2D
var _talker: Node2D
var _step_stage: Dictionary = {}
var _line_keys: PackedStringArray = []

var _box: NinePatchRect
var _box_home := Vector2.ZERO
var _fx_layer: CanvasLayer
var _sc_item: Sprite2D
var _monster: Sprite2D
var _skip_btn: Button

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_no = int(_params.get("no", 1))
	_part = int(_params.get("part", 0))
	_idx = 0
	if not StoryProgress.implemented(_no):
		_build_unavailable()
		return
	var sc: Dictionary = Data.scenario_def(str(_no))
	var parts: Array = sc.get("parts", [])
	_flow = Data.scenario_flow_of(_no)
	_flow_i = 0
	_npc_slots.clear()
	_active_npc = null
	_talker = null
	_lines = []
	_line_keys = []
	if _flow.is_empty():
		if _part >= 0 and _part < parts.size():
			_lines = (parts[_part] as Dictionary).get("lines", [])
			for l in _lines:
				_line_keys.append("%d_%d" % [_part, int((l as Dictionary).get("k", 0))])
	elif not _build_lines_from_flow(parts):
		for pi in parts.size():
			var pls: Array = (parts[pi] as Dictionary).get("lines", [])
			_lines.append_array(pls)
			for l in pls:
				_line_keys.append("%d_%d" % [pi, int((l as Dictionary).get("k", 0))])
	_build_backdrop(sc)
	_build_textbox()
	_build_skip()
	var resume := int(_params.get("resume_flow", 0))
	if resume <= 0 and StoryProgress.gate_cleared(_no):
		resume = StoryProgress.mission_resume(_no)
	if resume > 0 and resume <= _flow.size():
		_flow_i = resume
		_idx = 0
		for i in resume:
			if String((_flow[i] as Dictionary).get("op", "")) in TALK_OPS:
				_idx += 1
		_idx = mini(_idx, _lines.size())
	if _no == 20 and not Data.scenario_def(str(_no)).get("cuts", []).is_empty():
		_show_cutin()
	if not _flow.is_empty():
		_play_flow()
	elif _lines.is_empty():
		_show_line_text("(이 시나리오의 대사가 없습니다 — data/scenario.json 확인)")
	else:
		_show_line(0)

func _build_lines_from_flow(parts: Array) -> bool:
	if _flow.is_empty():
		return false
	var by_part: Dictionary = {}
	for pi in parts.size():
		var p: Dictionary = parts[pi]
		var lut: Dictionary = {}
		for l in (p.get("lines", []) as Array):
			lut[int((l as Dictionary).get("k", 0))] = l
		by_part[p.get("m")] = {"pi": pi, "lines": lut}
	var kept: Array = []
	var found := false
	for o in _flow:
		var d: Dictionary = o
		if not (String(d.get("op", "")) in TALK_OPS):
			kept.append(o)
			continue
		var ref = d.get("line")
		if ref == null:
			continue
		found = true
		var pd: Dictionary = by_part.get((ref as Dictionary).get("m"), {})
		var line = (pd.get("lines", {}) as Dictionary).get(int((ref as Dictionary).get("k", 0)))
		if line == null:
			continue
		kept.append(o)
		_lines.append(line)
		_line_keys.append("%d_%d" % [int(pd.get("pi", 0)), int((line as Dictionary).get("k", 0))])
	if not found:
		return false
	_flow = kept
	return true

func _build_unavailable() -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.03, 0.06)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var msg := Label.new()
	msg.text = "%d화는 현재 구현되지 않아 열람할 수 없습니다." % _no
	msg.add_theme_font_size_override("font_size", 26)
	msg.add_theme_color_override("font_color", Color.WHITE)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(msg)
	var leave := Button.new()
	leave.text = "돌아가기"
	leave.size = Vector2(180.0, 56.0)
	leave.position = Vector2((_vis().x - leave.size.x) * 0.5, _vis().y * 0.65)
	leave.pressed.connect(_leave)
	back.add_child(leave)

func _build_backdrop(sc: Dictionary) -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.03, 0.06)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var host: Texture2D = Scenes.story_backdrop
	if host != null:
		var hv := TextureRect.new()
		hv.texture = host
		hv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hv.set_anchors_preset(Control.PRESET_FULL_RECT)
		hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hv)
		_host_view = hv
	var ib := Data.scenario_initial_bg(_no)
	if ib != "":
		var res := _bg_res(ib)
		if res != "":
			_put_bg(res, _field_of(ib))
		else:
			push_warning("[story] 초기 배경 변환본 없음: %s" % ib)
	if not _flow.is_empty() and _flow_has_art():
		return
	var illust: Array = sc.get("illust", [])
	if illust.is_empty():
		return
	var pick := String(illust[mini(_part, illust.size() - 1)])
	var p := "%s/%s" % [ART_DIR, pick]
	if not ResourceLoader.exists(p):
		return
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

func _flow_has_art() -> bool:
	const ART := ["illust", "cut", "illust_3", "illust_8", "illust_9"]
	for o in _flow:
		if String((o as Dictionary).get("op", "")) in ART:
			return true
	return false

func _build_textbox() -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 8; add_child(lay)
	var box := NinePatchRect.new()
	box.texture = load(DIALOG_BOX)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 20.0, BOX_H)
	box.position = Vector2(10.0, vis.y - BOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(box)
	_box = box
	_box_home = box.position
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_name_label.position = Vector2(20.0, 8.0)
	_name_label.size = Vector2(box.size.x - 90.0, 28.0)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(20.0, 38.0)
	_label.size = Vector2(box.size.x - 75.0, BOX_H - 46.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)
	if ResourceLoader.exists(ARROW):
		_arrow = Sprite2D.new()
		_arrow.texture = load(ARROW)
		_arrow.material = _pma
		_arrow.position = Vector2(box.size.x - 35.0, BOX_H * 0.5)
		_arrow.visible = false
		box.add_child(_arrow)
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_advance())
	lay.add_child(catcher)
	lay.move_child(catcher, 0)

func _build_skip() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var lay := CanvasLayer.new(); lay.layer = 9; add_child(lay)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(117.0 * S, 39.0 * S)
	b.position = Vector2(vis.x - b.size.x - 18.0, 16.0)
	_skip_btn = b
	if ResourceLoader.exists(SKIP):
		var s := Sprite2D.new()
		s.texture = load(SKIP)
		s.material = _pma
		s.scale = Vector2(S, S)
		s.position = b.size * 0.5
		b.add_child(s)
	var l := Label.new()
	l.text = "건너뛰기"
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88))
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = b.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(_confirm_skip)
	lay.add_child(b)

func _confirm_skip() -> void:
	var p := _popup_above_all(Data.ui("#9e64f3d7"), Vector2(620.0, 330.0))
	p.add_body_label(Data.ui("#bb1e4a29"))
	p.add_action_button("확인", func() -> void:
		p.close()
		_finish(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 - 110.0, p.win_size.y - 60.0))
	p.add_action_button("취소", func() -> void: p.close(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 + 110.0, p.win_size.y - 60.0))

func _play_flow() -> void:
	if _should_pause_for_mission():
		_pause_for_mission()
		return
	while _flow_i < _flow.size():
		var o: Dictionary = _flow[_flow_i]
		_flow_i += 1
		match String(o.get("op", "")):
			"npc_talk":
				var folder := Data.scenario_npc_folder(int(o.get("npc", 0)))
				_name_label.text = Data.npc_name(folder) if folder != "" else ""
				_step_stage = _stage_args(o, o.get("b3"))
				if folder != "":
					_stage_from_step(folder, _step_stage)
				_talker = _active_npc if folder != "" else null
				_next_line()
				return
			"talker_in":
				var f2 := _str(o, "npc_name")
				_name_label.text = Data.npc_name(f2) if f2 != "" else ""
				_step_stage = _stage_args(o, o.get("enter"))
				if f2 != "":
					_stage_from_step(f2, _step_stage)
				_talker = _active_npc if f2 != "" else null
				_next_line()
				return
			"talk":
				var f3 := _str(o, "npc_name")
				_name_label.text = ""
				_step_stage = _stage_args(o, o.get("enter"))
				if f3 != "":
					_name_label.text = Data.npc_name(f3)
					if _step_stage.is_empty():
						_keep_or_show_npc(f3)
					else:
						_stage_from_step(f3, _step_stage)
				_talker = _active_npc if f3 != "" else null
				_line_by_key(_str(o, "key"))
				return
			"user_talk":
				_name_label.text = ""
				_step_stage = {}
				_talker = null
				_next_line()
				return
			"bgm":
				var trk := _str(o, "track")
				if trk != "":
					Bgm.play(trk)
			"sfx":
				var sfx := _str(o, "track")
				if sfx != "":
					Bgm.sfx(sfx)
			"cut":
				_show_cut(_str(o, "frame"))
			"bg", "bg_pass":
				_apply_bg(int(o.get("bg", 0)))
			"illust":
				_apply_illust(int(o.get("illust", _no)), int(o.get("kind", 1)))
			"removeIllust":
				if is_instance_valid(_illust):
					_illust.visible = false
			"talker_out":
				_hide_npc(int(o.get("talker", 0)), int(o.get("n", 0)))
			"field_bgm":
				Bgm.play(Data.scenario_bgm(int(o.get("field", 0))))
			"title":
				_show_title_card(int(o.get("title", _no)))
			"blackout":
				_color_flash(Color(0, 0, 0, 0), [[0.5, 1.0], [1.0, 0.0], [0.5, 50.0 / 255.0], [1.0, 0.0]])
			"shine":
				_color_flash(Color(1, 1, 1, 0), [[0.25, 1.0], [0.25, 0.0]])
			"color_on":
				var col := _cc4b(int(o.get("color", 0xff0000ff)))
				var op_a: float = float(int(o.get("opacity", 125))) / 255.0
				var seq: Array = [[0.2, op_a], [0.2, op_a]]
				if bool(o.get("fade_out", false)):
					seq.append([0.2, 0.0])
				_color_flash(col, seq, 300, true)
			"color_off":
				_clear_color_layer(300)
			"smoke":
				_color_flash(Color(0.5, 0.5, 0.5, 0),
					[[0.2, 125.0 / 255.0], [0.5, 125.0 / 255.0], [0.2, 0.0]], 100, true)
			"shake":
				_shake(0.3, 5.0)
			"monster_cry":
				Bgm.sfx("voice1")
			"battle":
				if _start_battle(int(o.get("battle", 0))):
					return
			"walk":
				var fld := int(o.get("field", 0))
				_push_box_away()
				if fld > 0:
					_apply_field_bg(fld)
				_restore_box()
			"walk_delay":
				_walk_beats(int(o.get("n", 1)))
			"illust_3", "illust_8", "illust_9":
				_show_cutin()
			"monster_show":
				_show_monster(int(o.get("monsters", 0)))
			"monster_hide":
				if is_instance_valid(_monster):
					_monster.queue_free()
			"hide_skip":
				if is_instance_valid(_skip_btn):
					_skip_btn.visible = false
			"minigame_text":
				_line_by_key("%d_M" % _no)
				return
			"minigame_pass":
				pass
			"item_show":
				_show_sc_item(int(o.get("item", -1)))
			"removeScenarioItem":
				if is_instance_valid(_sc_item):
					_sc_item.queue_free()
			_:
				pass
	_finish()

func _start_battle(battle_no: int) -> bool:
	var spec: Dictionary = Data.story_battle(battle_no)
	if spec.is_empty():
		push_warning("[story] 전투번호 %d 의 편성을 못 찾았다 — 건너뛴다" % battle_no)
		return false
	var p := {
		"enemy": spec["enemy"],
		"story_return": {
			"no": _no, "part": _part, "resume_flow": _flow_i,
			"back": _params.get("back", "worldmap"),
			"back_params": _params.get("back_params", {}),
		},
	}
	var fld := int(spec.get("field", 0))
	if fld > 0:
		p["bg_stage"] = fld
	Scenes.goto("battle", p)
	return true

func _apply_field_bg(field: int) -> void:
	var p := "res://assets/converted/adventure_bg/bg_%d.jpg" % field
	if not ResourceLoader.exists(p):
		return
	_put_bg(p, field)

func _put_bg(res: String, fid: int) -> void:
	_ensure_bg_layer()
	for c in _bg_layer.get_children():
		c.queue_free()
	_bg_layer.texture = load(res)
	_bg_layer.visible = true
	if fid > 0:
		DungeonBG.add_overlay(_bg_layer, {"bg": fid})

func _walk_beats(n: int) -> void:
	_push_box_away()
	var t := create_tween()
	t.tween_interval(0.5 * float(maxi(n, 1)))
	t.tween_callback(_restore_box)

func _show_cutin() -> void:
	var cuts: Array = Data.scenario_def(str(_no)).get("cuts", [])
	if cuts.is_empty():
		return
	var lay := CanvasLayer.new()
	lay.layer = 5
	add_child(lay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(root)
	var back: TextureRect = null
	var panels: Array[TextureRect] = []
	for c in cuts:
		var name := String(c)
		var tex: Texture2D = null
		var is_back := name.ends_with(".jpg")
		if is_back:
			var p1 := "%s/%s" % [ART_DIR, name]
			if ResourceLoader.exists(p1):
				tex = load(p1)
		else:
			var p2 := "res://assets/converted/scenario_cut/%s.tres" % name
			if ResourceLoader.exists(p2):
				tex = load(p2)
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if is_back 			else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
		if is_back:
			back = tr
		else:
			tr.modulate.a = 0.0
			panels.append(tr)
	if panels.is_empty():
		return
	var t := create_tween()
	for i in panels.size():
		var cur: TextureRect = panels[i]
		t.tween_property(cur, "modulate:a", 1.0, 0.25)
		t.tween_interval(0.9)
		if i < panels.size() - 1:
			t.tween_property(cur, "modulate:a", 0.0, 0.2)
	var flash := ColorRect.new()
	flash.color = Color(0, 0, 0, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	t.tween_property(flash, "color:a", 150.0 / 255.0, 0.1)
	t.tween_interval(0.4)
	t.tween_property(flash, "color:a", 0.0, 0.1)

func _show_monster(no: int) -> void:
	var orig := Data.scenario_monster_path(no)
	if orig == "":
		return
	var key := orig.trim_suffix(".png").replace("/", "_")
	var p := "res://assets/converted/scenario_monster/%s.tres" % key
	if not ResourceLoader.exists(p):
		return
	if is_instance_valid(_monster):
		_monster.queue_free()
	var vis := _vis()
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	s.position = Vector2(vis.x * 0.5, vis.y * 0.5)
	_monster = s
	_fx().add_child(s)
	s.modulate.a = 0.0
	s.create_tween().tween_property(s, "modulate:a", 1.0, 0.3)

func _show_sc_item(no: int) -> void:
	var orig := Data.scenario_item_path(no)
	if orig == "":
		return
	var key := orig.trim_suffix(".png").replace("/", "_")
	var cands := ["res://assets/converted/scenario_item/%s.tres" % key,
		"res://assets/converted/item_small_ui/%s.tres" % key]
	var tex: Texture2D = null
	for c in cands:
		if ResourceLoader.exists(c):
			tex = load(c)
			break
	if tex == null:
		return
	if is_instance_valid(_sc_item):
		_sc_item.queue_free()
	var vis := _vis()
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	s.position = Vector2(vis.x * 0.5, vis.y * 0.38)
	_sc_item = s
	_fx().add_child(s)
	s.modulate.a = 0.0
	var t := s.create_tween()
	t.tween_property(s, "modulate:a", 1.0, 0.3)

func _fx() -> CanvasLayer:
	if not is_instance_valid(_fx_layer):
		_fx_layer = CanvasLayer.new()
		_fx_layer.layer = 10
		add_child(_fx_layer)
	return _fx_layer

func _push_box_away() -> void:
	if not is_instance_valid(_box):
		return
	var t := _box.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(_box, "position", _box_home + Vector2(0.0, 250.0), 0.5)

func _cc4b(v: int) -> Color:
	return Color((v & 0xFF) / 255.0, ((v >> 8) & 0xFF) / 255.0, ((v >> 16) & 0xFF) / 255.0, 0.0)

func _color_flash(base: Color, steps: Array, tag := 100, below := false) -> void:
	if not below:
		_push_box_away()
	_clear_color_layer(tag)
	var r := ColorRect.new()
	r.name = "fx_%d" % tag
	r.color = base
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if below:
		_ensure_bg_layer()
		add_child(r)
		move_child(r, _bg_layer.get_index() + 1)
	else:
		_fx().add_child(r)
	var t := r.create_tween()
	for s in steps:
		var arr: Array = s
		t.tween_property(r, "color:a", float(arr[1]), float(arr[0]))
	if not steps.is_empty() and is_zero_approx(float((steps[-1] as Array)[1])):
		t.tween_callback(func() -> void:
			if is_instance_valid(r):
				r.queue_free())
	if not below:
		t.tween_callback(_restore_box)

func _restore_box() -> void:
	if not is_instance_valid(_box):
		return
	var t := _box.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(_box, "position", _box_home, 0.5)

func _clear_color_layer(tag := 100) -> void:
	for parent in [_fx_layer, self]:
		if not is_instance_valid(parent):
			continue
		var n: Node = (parent as Node).get_node_or_null("fx_%d" % tag)
		if n != null:
			n.queue_free()

func _shake(dur: float, amp: float) -> void:
	var home := position
	var t := create_tween()
	var n := int(dur * 60.0)
	for i in n:
		t.tween_property(self, "position",
			home + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)), dur / float(n))
	t.tween_property(self, "position", home, 0.0)

func _show_title_card(no: int) -> void:
	Bgm.sfx("effect_jingle")
	var vis := _vis()
	var lay := _fx()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var num := _title_label("스토리 %d." % no, 30)
	num.position = Vector2(vis.x * 0.2, vis.y * 0.2)
	num.modulate.a = 0.0
	root.add_child(num)
	var ttl := _title_label(Data.scenario_title(no), 42)
	ttl.position = Vector2(vis.x * 0.5 - ttl.size.x * 0.5, vis.y * 0.45)
	ttl.modulate.a = 0.0
	root.add_child(ttl)
	for pair in [[dim, "color:a"], [num, "modulate:a"]]:
		var n: CanvasItem = pair[0]
		var t0 := n.create_tween()
		t0.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_EXPO)
		t0.tween_property(n, String(pair[1]), 1.0, 0.9)
		t0.tween_interval(2.7)
		t0.tween_property(n, String(pair[1]), 0.0, 0.36)
	var t := ttl.create_tween()
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_interval(1.1)
	t.tween_property(ttl, "modulate:a", 1.0, 0.9)
	t.tween_interval(1.6)
	t.tween_property(ttl, "modulate:a", 0.0, 0.36)
	t.tween_callback(func() -> void:
		if is_instance_valid(root):
			root.queue_free())

func _title_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := load(TITLE_FONT) if ResourceLoader.exists(TITLE_FONT) else null
	if f != null:
		if f is FontFile:
			(f as FontFile).fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.size = l.get_minimum_size()
	return l

func _str(o: Dictionary, key: String) -> String:
	var v = o.get(key, null)
	return String(v) if typeof(v) == TYPE_STRING else ""

func _line_by_key(key: String) -> void:
	var m := RegEx.create_from_string(r"^\d+(?:_\d+)?_(\d+)$").search(key)
	if m == null:
		_next_line()
		return
	var want := int(m.get_string(1))
	for i in _lines.size():
		var d: Dictionary = _lines[i]
		if int(d.get("k", -1)) == want:
			_restored_speaker(i)
			_show_line_text(_admin_line(i, String(d.get("text", ""))))
			_idx = i + 1
			return
	_next_line()

func _next_line() -> void:
	if _idx >= _lines.size():
		_show_line_text("")
		return
	_restored_speaker(_idx)
	_show_line_text(_admin_line(_idx, String((_lines[_idx] as Dictionary).get("text", ""))))
	_idx += 1

func _fill_count(text: String) -> String:
	if not text.contains("%"):
		return text
	var sp := StoryProgress.spec(_no)
	var n := int(sp.get("count", 0)) if not sp.is_empty() else 0
	if n > 0:
		return RegEx.create_from_string("%\\d*\\$?[sd]").sub(text, str(n), true)
	var out := RegEx.create_from_string("%\\d*\\$?[sd](?=\\S)").sub(text, "몇 ", true)
	return RegEx.create_from_string("%\\d*\\$?[sd]").sub(out, "몇", true)

func _restored_speaker(i: int) -> void:
	if i < 0 or i >= _line_keys.size() or _name_label == null:
		return
	var s: Dictionary = Data.story_speaker(_no, _line_keys[i])
	if s.is_empty():
		return
	var folder := String(s.get("npc", ""))
	if folder != "":
		_stage_from_step(folder, _step_stage)
		_talker = _active_npc
	_name_label.text = String(s.get("name", Data.npc_name(folder)))

func _admin_line(i: int, text: String) -> String:
	if i < 0 or i >= _line_keys.size() or not UserDB.is_admin():
		return text
	var ov: Dictionary = Data.admin_story_line(_no, _line_keys[i])
	if ov.is_empty():
		return text
	var npc := String(ov.get("npc", ""))
	if npc != "":
		var pos := int(ov.get("pos", Data.admin_story_default("pos", 2)))
		_show_npc(npc, 1, int(ov.get("expr", 1)), pos)
		_talker = _active_npc
		if _talker != null and _talker.has_method("set_rest_mouth"):
			_talker.call("set_rest_mouth", int(ov.get("mouth", 0)))
		_name_label.text = String(ov.get("name", Data.admin_story_default("name", "")))
	elif ov.has("name"):
		_name_label.text = String(ov["name"])
	return String(ov.get("text", text))

func _apply_bg(bg_no: int) -> void:
	var paths: Array = Data.scenario_bg_paths(bg_no)
	if paths.is_empty():
		if is_instance_valid(_bg_layer):
			_bg_layer.visible = false
		return
	var res := _bg_res(String(paths[0]))
	if res == "":
		return
	_put_bg(res, _field_of(String(paths[0])))

func _ensure_bg_layer() -> void:
	if is_instance_valid(_bg_layer):
		return
	_bg_layer = TextureRect.new()
	_bg_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_layer)
	move_child(_bg_layer, (_host_view.get_index() + 1) if is_instance_valid(_host_view) else 1)

func _field_of(orig: String) -> int:
	var r := RegEx.create_from_string(r"scene/adventure/bg/(\d+)/").search(orig)
	return int(r.get_string(1)) if r else 0

func _bg_res(orig: String) -> String:
	var cands: Array[String] = []
	var m := RegEx.create_from_string(r"scene/adventure/bg/(\d+)/")
	var r := m.search(orig)
	if r:
		cands.append("res://assets/converted/adventure_bg/bg_%s.jpg" % r.get_string(1))
	elif orig.begins_with("scenario/main_story/bg/"):
		cands.append("%s/bg/%s" % [ART_DIR, orig.get_file()])
	elif orig.begins_with("scene/magicshop/"):
		cands.append("res://assets/converted/magicshop_bg/%s" % orig.get_file())
	elif orig.begins_with("scene/shop/"):
		cands.append("res://assets/converted/shop_bg/%s" % orig.get_file())
	elif orig.begins_with("scene/laboratory/"):
		cands.append("res://assets/converted/laboratory_bg/%s" % orig.get_file())
	elif orig.begins_with("scenario/prologue/"):
		cands.append("res://assets/converted/prologue_ui/%s" % orig.get_file())
	elif orig.begins_with("scenario/main_story/"):
		cands.append("%s/%s" % [ART_DIR, orig.get_file()])
	for c in cands:
		if ResourceLoader.exists(c):
			return c
	return ""

func _apply_illust(no: int, kind: int) -> void:
	var p := "%s/sn_%d_%d_illust.jpg" % [ART_DIR, no, maxi(kind, 1)]
	if not ResourceLoader.exists(p):
		var arr: Array = Data.scenario_def(str(no)).get("illust", [])
		if arr.is_empty():
			return
		p = "%s/%s" % [ART_DIR, String(arr[clampi(kind - 1, 0, arr.size() - 1)])]
		if not ResourceLoader.exists(p):
			return
	if not is_instance_valid(_illust):
		_illust = TextureRect.new()
		_illust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_illust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_illust.set_anchors_preset(Control.PRESET_FULL_RECT)
		_illust.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_illust.z_index = 3
		add_child(_illust)
	_illust.texture = load(p)
	_illust.visible = true
	_illust.modulate.a = 0.0
	var t := _illust.create_tween()
	t.tween_interval(0.5)
	t.tween_property(_illust, "modulate:a", 1.0, 0.5)

func _show_cut(frame: String) -> void:
	var p := "res://assets/converted/scenario_cut/%s.tres" % frame
	if not ResourceLoader.exists(p):
		return
	if not is_instance_valid(_cut):
		_cut = TextureRect.new()
		_cut.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_cut.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_cut.set_anchors_preset(Control.PRESET_FULL_RECT)
		_cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cut.z_index = 3
		add_child(_cut)
	_cut.texture = load(p)
	_cut.visible = true
	_cut.modulate.a = 0.0
	_cut.create_tween().tween_property(_cut, "modulate:a", 1.0, 0.25)

func _hide_npc(pos := 0, mode := 0) -> void:
	var which: Array = _npc_slots.keys() if pos <= 0 else [clampi(pos, 1, 3)]
	for k in which:
		var p: Node2D = _npc_slots.get(int(k))
		_npc_slots.erase(int(k))
		if is_instance_valid(p):
			_exit_npc(p, int(k), mode)
	if not is_instance_valid(_active_npc) or pos <= 0 or int(_active_npc.get_meta("story_pos", 0)) == pos:
		_active_npc = null

func _show_line(i: int) -> void:
	_idx = i
	var e: Dictionary = _lines[i]
	var cast_npc := _cast_npc(_no, _part, int(e.get("k", 0)))
	_name_label.text = Data.npc_name(cast_npc) if cast_npc != "" else ""
	if cast_npc != "":
		_show_npc(cast_npc)
	_talker = _active_npc if cast_npc != "" else null
	_show_line_text(_admin_line(i, String(e.get("text", ""))))

func _show_line_text(text: String) -> void:
	_label.text = _fill_count(text)
	_label.visible_characters = 0
	_typing = true
	_set_talking(true)
	_stop_arrow_tween()
	if _arrow: _arrow.visible = false
	if is_instance_valid(_timer): _timer.queue_free()
	_timer = Timer.new()
	_timer.wait_time = 1.0 / CPS
	add_child(_timer)
	var total := text.length()
	_timer.timeout.connect(func() -> void:
		_label.visible_characters += 1
		if _label.visible_characters >= total:
			_reveal_all())
	_timer.start()

func _reveal_all() -> void:
	_label.visible_characters = -1
	_typing = false
	_set_talking(false)
	if is_instance_valid(_timer): _timer.stop()
	if _arrow:
		_arrow.visible = true
		_stop_arrow_tween()
		_arrow_tween = _arrow.create_tween().set_loops()
		_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5 + 6.0, 0.4)
		_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5, 0.4)

func _set_talking(on: bool) -> void:
	if not on:
		for p in _npc_slots.values():
			if is_instance_valid(p) and p.has_method("set_talking"):
				p.call("set_talking", false)
		return
	if is_instance_valid(_talker) and _talker.has_method("set_talking"):
		_talker.call("set_talking", true)

func _stop_arrow_tween() -> void:
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = null
	if is_instance_valid(_arrow):
		_arrow.position.y = BOX_H * 0.5

func _advance() -> void:
	if _typing:
		_reveal_all()
		return
	if not _flow.is_empty():
		_play_flow()
		return
	if _lines.is_empty() or _idx + 1 >= _lines.size():
		_finish()
		return
	_show_line(_idx + 1)

func _popup_above_all(title: String, sz: Vector2) -> FramedWindow:
	var host := CanvasLayer.new()
	host.layer = 20
	add_child(host)
	var p := FramedWindow.open(host, title, sz)
	p.closed.connect(func() -> void:
		if is_instance_valid(host):
			host.queue_free())
	return p

func _should_pause_for_mission() -> bool:
	if not _mission_open():
		return false
	return _idx > int(StoryProgress.spec(_no)["break_after"])

func _mission_open() -> bool:
	var sp := StoryProgress.spec(_no)
	if sp.is_empty() or not sp.has("break_after"):
		return false
	return not StoryProgress.gate_cleared(_no)

func _pause_for_mission() -> void:
	var sp := StoryProgress.spec(_no)
	StoryProgress.issue_mission(_no, _flow_i)
	var cond := StoryQuest.cond_line(sp, StoryProgress.place_name(sp), StoryProgress.target_name(sp))
	var p := _popup_above_all("서브미션", Vector2(620.0, 330.0))
	p.closed.connect(_leave)
	p.add_body_label("%s\n%s\n\n완료하면 이야기가 이어집니다." % [String(sp.get("name", "")), cond])
	p.add_action_button("확인", func() -> void: p.close())

func _show_complete_notice() -> void:
	var ep := Data.story_episode(_no)
	var title := String(ep.get("title", "%d화" % _no))
	var p := _popup_above_all(Data.ui("#1044a559"), Vector2(620.0, 330.0))
	p.closed.connect(_leave)
	p.add_body_label("%s\n스토리를 완료하였습니다." % title)
	p.add_action_button("확인", func() -> void: p.close())

func _finish() -> void:
	if _mission_open():
		_pause_for_mission()
		return
	var first: bool = not bool(UserDB.get_progress("scenario_%d_%d" % [_no, _part], false))
	UserDB.set_progress("scenario_%d_%d" % [_no, _part], true)
	var rw := StoryProgress.grant_special_reward(_no)
	if not rw.is_empty():
		_show_special_reward(rw)
		return
	if first:
		_show_complete_notice()
		return
	_leave()

func _leave() -> void:
	var back := String(_params.get("back", ""))
	if back == "":
		Scenes.goto_main()
		return
	var bp: Dictionary = _params.get("back_params", {})
	if back == "worldmap" and not bp.has("region"):
		Scenes.goto_main(bp)
		return
	Scenes.goto(back, bp)

func _show_special_reward(rw: Dictionary) -> void:
	var p := _popup_above_all(Data.ui("#861bb11a"), Vector2(700.0, 470.0))
	p.closed.connect(_leave)
	var y := 110.0
	var name_l := Label.new()
	name_l.text = "Lv.%d %s" % [int(rw.get("level", 1)), String(rw.get("name", ""))]
	name_l.add_theme_font_size_override("font_size", 30)
	name_l.add_theme_color_override("font_color", Color(0.24, 0.15, 0.05))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.position = Vector2(0, y); name_l.size = Vector2(p.win_size.x, 40)
	p.content.add_child(name_l)
	y += 56.0
	var dno := int(rw.get("dragon_no", 0))
	var tp := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_adult.tres" % [dno, dno]
	if ResourceLoader.exists(tp):
		var tr := TextureRect.new()
		tr.texture = load(tp)
		tr.material = _pma
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(150, 150)
		tr.position = Vector2(p.win_size.x * 0.5 - 75.0, y)
		p.content.add_child(tr)
		y += 162.0
	var det := Label.new()
	var miss: Array = rw.get("skills_missing", [])
	det.text = "보유 스킬 %d개 습득" % int(rw.get("skills_granted", 0))
	if not miss.is_empty():
		det.text += "  (미구현 스킬 %s 제외)" % str(miss)
	det.add_theme_font_size_override("font_size", 17)
	det.add_theme_color_override("font_color", Color(0.36, 0.26, 0.1))
	det.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.position = Vector2(20, y); det.size = Vector2(p.win_size.x - 40, 44)
	p.content.add_child(det)
	var noti := Label.new()
	noti.text = "해당 시나리오 클리어시 지급되며, 해당 드래곤은\n둥지의 드래곤 목록에서 확인할 수 있습니다."
	noti.add_theme_font_size_override("font_size", 15)
	noti.add_theme_color_override("font_color", Color(0.5, 0.36, 0.14))
	noti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	noti.position = Vector2(20, y + 48.0); noti.size = Vector2(p.win_size.x - 40, 50)
	p.content.add_child(noti)

var _cast: Dictionary = {}
var _cast_loaded := false
func _cast_npc(no: int, part: int, k: int) -> String:
	if not _cast_loaded:
		_cast_loaded = true
		var f := FileAccess.open("res://data/scenario_cast.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _cast = d
	var byno: Dictionary = _cast.get(str(no), {})
	var bypart: Dictionary = byno.get(str(part), {})
	return String(bypart.get(str(k), ""))

func _keep_or_show_npc(npc: String) -> void:
	for p in _npc_slots.values():
		if is_instance_valid(p) and String(p.get_meta("npc", "")).begins_with(npc + "|"):
			_active_npc = p
			p.z_index = 5
			for other in _npc_slots.values():
				if is_instance_valid(other) and other != p:
					other.z_index = 4
			return
	_show_npc(npc, 1, 1, _flow_pos_for_npc(npc), false)

func _stage_args(o: Dictionary, enter: Variant) -> Dictionary:
	if o.get("state") == null and o.get("pos") == null:
		return {}
	return {
		"body": maxi(int(o.get("body", 1)), 1),
		"state": maxi(int(o.get("state", 1)), 1),
		"pos": clampi(int(o.get("pos", 3)), 1, 3),
		"enter": enter,
		"emoticon": int(o.get("emoticon", 0)),
		"via": String(o.get("via", "")),
	}

func _stage_from_step(npc: String, a: Dictionary) -> void:
	if a.is_empty():
		_keep_or_show_npc(npc)
		return
	var state := int(a.get("state", 1))
	var body := int(a.get("body", 1))
	if String(a.get("via", "")) == "play" and npc == "yulia" and state == 5:
		body = 5
	_show_npc(npc, body, state, int(a.get("pos", 3)), a.get("enter"))
	var emo := int(a.get("emoticon", 0))
	if emo > 0 and _active_npc is NpcPortrait:
		NpcEmoticon.show_on(_active_npc as NpcPortrait, emo)

func _show_npc(npc: String, body := 1, state := 1, pos := 3, enter: Variant = null) -> void:
	pos = clampi(pos, 1, 3)
	var want := "%s|%d" % [npc, body]
	var old: Node2D = _npc_slots.get(pos)
	var same: bool = is_instance_valid(old) and String(old.get_meta("npc", "")) == want
	var do_enter: bool = (not same) if enter == null else bool(enter)
	if same:
		_active_npc = old
		old.call("set_emotion", maxi(state, 1))
		_raise_npc(old)
		if do_enter:
			_enter_npc(old, pos, _npc_home(old, pos))
		return
	var manifest := "res://assets/converted/npc_%s/_manifest.json" % npc
	if not FileAccess.file_exists(manifest):
		if is_instance_valid(old):
			old.queue_free()
		_npc_slots.erase(pos)
		if _active_npc == old:
			_active_npc = null
		return
	if is_instance_valid(old):
		old.queue_free()
	var p := NpcPortrait.create(npc, maxi(state, 1), body)
	if p == null:
		_npc_slots.erase(pos)
		return
	_npc_slots[pos] = p
	_active_npc = p
	p.set_meta("npc", want)
	p.set_meta("story_pos", pos)
	var home := _npc_home(p, pos)
	p.position = home
	add_child(p)
	_raise_npc(p)
	if do_enter:
		_enter_npc(p, pos, home)

func _raise_npc(p: Node2D) -> void:
	for other in _npc_slots.values():
		if is_instance_valid(other) and other != p:
			other.z_index = 4
	p.z_index = 5

func _npc_home(p: Node2D, pos: int) -> Vector2:
	var vis := _vis()
	var w: float = float(p.call("body_width")) if p.has_method("body_width") else 0.0
	match pos:
		1: return Vector2(w * 0.5, vis.y)
		2: return Vector2(vis.x - w * 0.5, vis.y)
		_: return Vector2(vis.x * 0.5, vis.y)

func _enter_npc(p: Node2D, pos: int, home: Vector2) -> void:
	var vis := _vis()
	var t := p.create_tween()
	if pos == 1:
		p.position = home - Vector2(vis.x * 0.5, 0.0)
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "position", home, 0.5)
	elif pos == 2:
		p.position = home + Vector2(vis.x * 0.5, 0.0)
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "position", home, 0.5)
	else:
		p.position = home + Vector2(0.0, vis.y)
		t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(p, "position", home, 1.25)

func _exit_npc(p: Node2D, pos: int, mode: int) -> void:
	if mode <= 0:
		p.queue_free()
		return
	var vis := _vis()
	var t := p.create_tween()
	if mode == 1:
		t.tween_property(p, "modulate:a", 0.0, 0.5)
	else:
		var dst := p.position
		if pos == 1: dst -= Vector2(vis.x * 0.5, 0.0)
		elif pos == 2: dst += Vector2(vis.x * 0.5, 0.0)
		else: dst += Vector2(0.0, vis.y)
		t.set_trans(Tween.TRANS_EXPO if pos == 3 else Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(p, "position", dst, 0.5)
	t.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

func _flow_pos_for_npc(npc: String) -> int:
	for i in range(mini(_flow_i, _flow.size()) - 1, -1, -1):
		var o: Dictionary = _flow[i]
		if not o.has("pos"):
			continue
		if _str(o, "npc_name") == npc:
			return clampi(int(o.get("pos", 3)), 1, 3)
		if _str(o, "op") == "npc_talk" \
				and Data.scenario_npc_folder(int(o.get("npc", 0))) == npc:
			return clampi(int(o.get("pos", 3)), 1, 3)
	return 3

func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

func _spr(dir: String, name: String, scale := 1.0) -> Sprite2D:
	return AtlasUI.spr(dir, name, scale)
