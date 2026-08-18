class_name ColosseumSelect
extends CanvasLayer

const CO := "colosseum_ui"
const CM := "common_ui"
const NP := "ninepatch_ui"
const ST := "stand_ui"

const PANEL_INSET := 20.0
const POPUP5_CAP := Rect2(100, 105, 75, 135)
const TITLE_UP := 305.0
const TITLE_SCALE := 0.75
const CLOSE_SCALE := 1.5
const CLOSE_RIGHT := 55.0
const CLOSE_TOP := 30.0
const CONFIRM_SIZE := Vector2(200.0, 120.0)
const CONFIRM_DX := -27.0
const CONFIRM_DY := -240.0
const STAGE_W := 465.0
const STAGE_DX := STAGE_W * 0.5 + 42.0 - 15.0
const STAGE_DY_3 := 100.0
const STAGE_DY_1 := 55.0
const SLOTS_3 := [Vector2(110.0, -40.0), Vector2(-90.0, 75.0), Vector2(-125.0, -115.0)]
const SLOT_1 := Vector2(0.0, 40.0)
const STAND_DOWN_3 := 35.0
const STAND_DOWN_1 := 20.0
const STAND_SCALE_3 := 0.6
const STAND_SCALE_1 := 1.0
const GLOW_UP_3 := 21.0
const GLOW_UP_1 := 20.0
const GLOW_SCALE := 0.75
const SHADOW_DOWN := 32.5
const SHADOW_SCALE := 1.75
const SPIN3_DEG := 90.0
const SPIN4_DEG := 10.0
const SPIN_SEC := 2.0
const FADE_SEC := 0.25
const DRAGON_SCALE := 0.6
const LIST_INSET := 268.5
const LIST_H := 135.0
const LIST_LEFT := 22.0
const LIST_DY := -240.0
const SEL_MARGIN := 11
const SCROLL_PAD := Vector2(4.1, 0.0)
const SCROLL_TRIM := 7.1
const CELL_GAP := 10.0
const CELL_MARGIN := 10.0
const CELL_SCALE := 1.05
const PORTRAIT_SCALE := 0.9
const PORTRAIT_UP := 7.5
const LV_SCALE := 0.8
const DIM_OPACITY := 0x66 / 255.0
const INFO_RIGHT := 199.5 + 42.5
const INFO_UP := 55.0
const INFO_SLIDE := 0.1
const HIT_BOX := 120.0

var _mode := "team"
var _need := 3
var _picked: Array = []
var _on_confirm := Callable()
var _pma: CanvasItemMaterial
var _vis: Vector2
var _slots: Array = []
var _cells: Dictionary = {}
var _dragon_layer: Node2D = null
var _panel: StatusPanel = null
var _panel_uid := -1
var _confirm: Control = null

static func open(host: Node, mode: String, seed_party: Array,
		on_confirm: Callable) -> ColosseumSelect:
	var l := ColosseumSelect.new()
	l.layer = 30
	l._mode = mode
	l._on_confirm = on_confirm
	l._need = Colosseum.party_size(mode)
	for u in seed_party:
		if l._picked.size() < l._need and Colosseum.eligible(int(u)) \
				and not UserDB.is_down(int(u)):
			l._picked.append(int(u))
	host.add_child(l)
	return l

func _ready() -> void:
	_pma = AtlasUI.pma()
	_vis = get_viewport().get_visible_rect().size
	_build()

func _build() -> void:
	var catcher := Control.new()
	catcher.size = _vis
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(catcher)

	var bg := AtlasUI.nine(NP, "9patch_popup5",
		Vector2(_vis.x - PANEL_INSET * 2.0, _vis.y - PANEL_INSET), POPUP5_CAP)
	if bg != null:
		bg.position = Vector2(PANEL_INSET, PANEL_INSET * 0.5)
		add_child(bg)

	_build_deco()
	_build_title()
	_build_close()
	_build_stage()
	_build_list()
	_build_confirm()
	_refresh_slots()
	if not _picked.is_empty():
		_open_panel(int(_picked[_picked.size() - 1]))

func _build_deco() -> void:
	var deco := AtlasUI.spr_cocos(CO, "scene_colosseum_dragon_select_deco", 1.0,
		Vector2(0.5, 1.0))
	if deco == null:
		return
	var w := AtlasUI.size_pt(CO, "scene_colosseum_dragon_select_deco").x
	if w > 1.0:
		deco.scale = Vector2((_vis.x + 5.0) / w, 1.0)
	deco.position = Vector2(_vis.x * 0.5, 0.0)
	add_child(deco)

func _build_title() -> void:
	var l := _bm_label(_string("ColosseumSelectTitle", "드래곤 선택"), 39, "font_title")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(_vis.x, 48.0)
	l.position = Vector2(0.0, _vis.y * 0.5 - TITLE_UP - 24.0)
	add_child(l)

func _build_close() -> void:
	var t := AtlasUI.tex(CM, "common_close_btn")
	if t == null:
		return
	var b := TextureButton.new()
	b.texture_normal = t
	b.scale = Vector2.ONE * (CLOSE_SCALE * Design.ASSET_SCALE)
	var sz := t.get_size() * b.scale
	b.position = Vector2(_vis.x - CLOSE_RIGHT, CLOSE_TOP) - sz * 0.5
	b.pressed.connect(func() -> void:
		Bgm.sfx("effect_button")
		_dismiss())
	add_child(b)

const STAGE_SHIFT_X := 80.0
const STAGE_NUDGE_1 := Vector2(55.0, 75.0)
const STAGE_NUDGE_3 := Vector2(60.0, 50.0)

const Cave := preload("res://scripts/ui/cave.gd")
const CAVE_DSCALE_PER_W := Cave.PED_DRAGON_SCALE / Cave.PED_WIDTH
const CAVE_LIFT_PER_W := (Cave.PED_BOTTOM - Cave.PED_DRAGON_Y) / Cave.PED_WIDTH

func _build_stage() -> void:
	var S := Design.ASSET_SCALE
	var three := _need >= 3
	var stage := Vector2(STAGE_DX + STAGE_SHIFT_X,
		_vis.y * 0.5 - (STAGE_DY_3 if three else STAGE_DY_1)) \
		+ (STAGE_NUDGE_3 if three else STAGE_NUDGE_1)
	var offs: Array = SLOTS_3 if three else [SLOT_1]
	var st_scale := (STAND_SCALE_3 if three else STAND_SCALE_1) * S
	var glow_up := GLOW_UP_3 if three else GLOW_UP_1
	var st_key := "stand_stand%d" % ((UserDB.get_skin("stand_skin") % _stand_count()) + 1)

	_dragon_layer = Node2D.new()
	add_child(_dragon_layer)

	for i in mini(_need, offs.size()):
		var o: Vector2 = offs[i]
		var slot := stage + Vector2(o.x, -o.y)
		var stand_pos := slot + Vector2(0.0, STAND_DOWN_3) if three \
			else stage + Vector2(0.0, STAND_DOWN_1)

		var stand := AtlasUI.spr(ST, st_key, st_scale)
		if stand == null:
			continue
		stand.position = stand_pos
		add_child(stand)

		var glow3 := AtlasUI.spr(CM, "common_backlight3", GLOW_SCALE)
		var glow4 := AtlasUI.spr(CM, "common_backlight4", GLOW_SCALE)
		var sh := AtlasUI.spr(CM, "common_shadow", SHADOW_SCALE)
		if glow3 == null or glow4 == null or sh == null:
			continue
		glow3.position = Vector2(0.0, -glow_up)
		glow3.modulate.a = 0.0
		glow3.z_index = -1
		stand.add_child(glow3)
		_spin(glow3, SPIN3_DEG)

		glow4.position = Vector2(0.0, -glow_up)
		glow4.z_index = -1
		stand.add_child(glow4)
		_spin(glow4, SPIN4_DEG)

		sh.position = Vector2(0.0, SHADOW_DOWN)
		sh.modulate.a = 0.0
		stand.add_child(sh)

		var st_px := AtlasUI.size_pt(ST, st_key) / S
		var draw_w := st_px.x * st_scale
		var st_bottom := stand_pos.y + st_px.y * st_scale * 0.5
		_slots.append({"stand": stand, "glow3": glow3, "glow4": glow4, "shadow": sh,
			"pos": slot,
			"foot": Vector2(stand_pos.x, st_bottom - draw_w * CAVE_LIFT_PER_W),
			"dscale": draw_w * CAVE_DSCALE_PER_W})

func _spin(n: Node2D, deg: float) -> void:
	var t := n.create_tween().set_loops()
	t.tween_property(n, "rotation", deg_to_rad(deg), SPIN_SEC).as_relative() \
		.set_trans(Tween.TRANS_LINEAR)

func _stand_count() -> int:
	var m := AtlasUI.manifest(ST)
	var n := 0
	while m.has("stand_stand%d" % (n + 1)):
		n += 1
	return maxi(1, n)

func _refresh_slots() -> void:
	if not is_instance_valid(_dragon_layer):
		return
	for c in _dragon_layer.get_children():
		c.queue_free()
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var filled := i < _picked.size()
		_fade(s["glow3"], 1.0 if filled else 0.0)
		_fade(s["shadow"], 1.0 if filled else 0.0)
		_fade(s["glow4"], 0.0 if filled else 1.0)
		if not filled:
			continue
		var uid := int(_picked[i])
		var d := UserDB.get_dragon(uid)
		if d.is_empty():
			continue
		var node := _dragon_spine(d, float(s.get("dscale", DRAGON_SCALE * Design.ASSET_SCALE)))
		if node == null:
			continue
		node.position = s.get("foot", s["pos"])
		_dragon_layer.add_child(node)
		var hit := Button.new()
		hit.flat = true
		hit.size = Vector2(HIT_BOX, HIT_BOX)
		hit.position = node.position - hit.size * 0.5
		hit.pressed.connect(func() -> void: _toggle(uid))
		_dragon_layer.add_child(hit)

func _fade(n: CanvasItem, a: float) -> void:
	var t := n.create_tween()
	t.tween_property(n, "modulate:a", a, FADE_SEC)

func _dragon_spine(d: Dictionary, dscale := -1.0) -> Node2D:
	var id := Icons.art_id_of(d)
	var S := Design.ASSET_SCALE
	var ds := dscale if dscale > 0.0 else DRAGON_SCALE * S
	for st in [Growth.spine_stage(d), "adult", "child", "baby"]:
		var p := Icons.spine_scene(id, st)
		if p == "":
			continue
		var holder := Node2D.new()
		holder.scale = Vector2(-ds, ds)
		var inst := (load(p) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null:
			for cand in ["wait", "animation", "idle"]:
				if ap.has_animation(cand):
					ap.get_animation(cand).loop_mode = Animation.LOOP_LINEAR
					ap.play(cand)
					break
		return holder
	return null

func _build_list() -> void:
	var S := Design.ASSET_SCALE
	var box_w: float = _vis.x - LIST_INSET
	var top: float = _vis.y * 0.5 - LIST_DY - LIST_H * 0.5

	var box := NinePatchRect.new()
	box.texture = AtlasUI.tex(NP, "9patch_selection_box")
	box.patch_margin_left = SEL_MARGIN
	box.patch_margin_right = SEL_MARGIN
	box.patch_margin_top = SEL_MARGIN
	box.patch_margin_bottom = SEL_MARGIN
	box.size = Vector2(box_w, LIST_H)
	box.position = Vector2(LIST_LEFT, top)
	add_child(box)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(SCROLL_PAD.x, SCROLL_PAD.y)
	scroll.size = Vector2(box_w - SCROLL_TRIM, LIST_H)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)

	var strip := Control.new()
	scroll.add_child(strip)

	var src: Array = AtlasUI.manifest(CM).get("common_dragon_bg2", {}).get("src", [83, 85])
	var cw := float(src[0]) * S
	var ch := float(src[1]) * S
	var pitch := cw + CELL_GAP

	var list := UserDB.dragons()
	for i in list.size():
		var d: Dictionary = list[i]
		var cx := pitch * float(i) + cw * 0.5 + CELL_MARGIN
		var cy := LIST_H - (ch * 0.5 + CELL_MARGIN)
		strip.add_child(_cell(d, Vector2(cx, cy), Vector2(cw, ch)))
	strip.custom_minimum_size = Vector2(pitch * float(list.size()) + 11.2, LIST_H)

func _cell(d: Dictionary, center: Vector2, sz: Vector2) -> Control:
	var S := Design.ASSET_SCALE
	var uid := int(d.get("uid", 0))
	var id := int(d.get("id", 0))
	var lv := int(d.get("level", 1))
	var pickable := Colosseum.eligible(uid) and not UserDB.is_down(uid)

	var root := Control.new()
	root.size = sz * CELL_SCALE
	root.position = center - root.size * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mid := root.size * 0.5

	var bg := AtlasUI.spr(CM, "common_dragon_bg2", S * CELL_SCALE)
	if bg != null:
		bg.position = mid
		root.add_child(bg)

	if UserDB.is_egg(d):
		var egg := AtlasUI.spr(CM, "common_breed_egg_small", S * CELL_SCALE)
		if egg != null:
			egg.position = mid + Vector2(0.0, -5.0)
			root.add_child(egg)
	else:
		var por := _portrait(Icons.art_id_of(d), Growth.portrait_stage(d),
			PORTRAIT_SCALE * S * CELL_SCALE, int(d.get("skin", 0)))
		if por != null:
			por.position = mid + Vector2(0.0, -PORTRAIT_UP)
			root.add_child(por)

	var cover := AtlasUI.spr(CM, "common_dragon_cover2", S * CELL_SCALE)
	if cover != null:
		cover.position = mid
		root.add_child(cover)

	var dim := AtlasUI.spr(CM, "common_dragon_cover4", S * CELL_SCALE)
	if dim != null:
		dim.position = mid
		dim.modulate = Color(0, 0, 0, DIM_OPACITY)
		dim.visible = not pickable
		root.add_child(dim)

	var lvl := _bm_label(_string("level", "레벨 %d") % lv, 17)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.size = Vector2(root.size.x + 20.0, 22.0)
	lvl.position = Vector2(-10.0, root.size.y - 26.0)
	root.add_child(lvl)

	var btn := Button.new()
	btn.flat = true
	btn.size = root.size
	btn.pressed.connect(func() -> void: _toggle(uid))
	root.add_child(btn)

	_cells[uid] = {"root": root, "dim": dim, "pickable": pickable}
	_paint_cell(uid)
	return root

func _paint_cell(uid: int) -> void:
	var c: Dictionary = _cells.get(uid, {})
	if c.is_empty():
		return
	var root: Control = c["root"]
	root.modulate = Color(0.6, 0.6, 0.6) if _picked.has(uid) else Color.WHITE

func _toggle(uid: int) -> void:
	var c: Dictionary = _cells.get(uid, {})
	if not c.is_empty() and not bool(c.get("pickable", false)):
		if UserDB.is_down(uid):
			Toast.show(self, "행동불능 상태입니다.")
		else:
			Toast.show(self, "레벨 %d 이상만 출전할 수 있습니다." % Colosseum.min_level())
		return
	Bgm.sfx("effect_tab", 0.5)
	var at := _picked.find(uid)
	if at >= 0:
		_picked.remove_at(at)
		_close_panel()
	elif _picked.size() < _need:
		_picked.append(uid)
		_open_panel(uid)
	else:
		_picked[_need - 1] = uid
		_open_panel(uid)
	for k in _cells.keys():
		_paint_cell(int(k))
	_refresh_slots()
	_update_confirm()

func _open_panel(uid: int) -> void:
	if _panel_uid == uid and is_instance_valid(_panel):
		return
	_close_panel()
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		return
	var pw: float = StatusPanel.PANEL.x * StatusPanel.PANEL_SCALE
	var ph: float = StatusPanel.PANEL.y * StatusPanel.PANEL_SCALE
	var pos := Vector2(_vis.x - INFO_RIGHT - pw * 0.5,
		_vis.y * 0.5 - INFO_UP - ph * 0.5)
	_panel = StatusPanel.open_panel(self, d, false, pos, false, true)
	_panel.action_requested.connect(func(a: String, arg: int) -> void:
		UserDB.set_active(uid)
		Scenes.goto("cave", {"open": a, "arg": arg}))
	_panel.layer = layer + 1
	_panel_uid = uid
	_panel.offset = Vector2(_vis.x - pos.x, 0.0)
	var t := _panel.create_tween()
	t.tween_property(_panel, "offset", Vector2(10.0, 0.0), INFO_SLIDE)
	t.tween_property(_panel, "offset", Vector2.ZERO, INFO_SLIDE)

func _close_panel() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_panel_uid = -1

func _build_confirm() -> void:
	var w := CONFIRM_SIZE.x
	var pos := Vector2(_vis.x + CONFIRM_DX - w * 0.5,
		_vis.y * 0.5 - CONFIRM_DY) - CONFIRM_SIZE * 0.5
	_confirm = AtlasUI.frame_button(self, _string("ColosseumSelectButton", "선택 완료"),
		pos, CONFIRM_SIZE, func() -> void: _commit(), 0, false, 24)
	_update_confirm()

func _update_confirm() -> void:
	if not is_instance_valid(_confirm):
		return
	var ok := _picked.size() >= _need
	_confirm.modulate = Color.WHITE if ok else Color(0.62, 0.62, 0.62)
	for c in _confirm.get_children():
		if c is Button:
			(c as Button).disabled = not ok

func _commit() -> void:
	if _picked.size() < _need:
		return
	Bgm.sfx("effect_button")
	var picked := _picked.duplicate()
	UserDB.clear_party()
	for u in picked:
		UserDB.toggle_party(int(u))
	var cb := _on_confirm
	queue_free()
	if cb.is_valid():
		cb.call(picked)

func _dismiss() -> void:
	_close_panel()
	queue_free()

static var _bmfonts: Dictionary = {}

func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	var f: FontFile = load(p) if ResourceLoader.exists(p) else null
	if f != null:
		f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	_bmfonts[name] = f
	return f

func _bm_label(text: String, size: int, font := "font_subtitle") -> Label:
	var l := Label.new()
	l.text = text
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

const STR := {
	"ColosseumSelectTitle": "드래곤 선택",
	"ColosseumSelectButton": "선택 완료",
	"level": "레벨 %d",
}

func _string(key: String, fallback: String) -> String:
	return String(STR.get(key, fallback))

func _portrait(id: int, stage: String, scale: float, skin: int) -> Sprite2D:
	var dir := "portrait_%d" % id
	var man := AtlasUI.manifest(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if not man.has(frame) and stage == "evolution":
		frame = "dragon_dragon_%d_box_adult" % id
	if skin > 0 and man.has("%s_skin%d" % [frame, skin]):
		frame = "%s_skin%d" % [frame, skin]
	return AtlasUI.spr(dir, frame, scale)
