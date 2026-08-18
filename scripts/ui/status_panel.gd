extends CanvasLayer
class_name StatusPanel

const DragonAwakenSkillInfoPopup := preload("res://scripts/ui/dragon_awaken_skill_info.gd")

signal action_requested(action: String, arg: int)
signal closed

const STAND_COUNT := 16

const PANEL := Vector2(362.0, 452.0)
const PANEL_SCALE := 0.95

const GROUP_ALPHA := 100.0 / 255.0
const STAMINA_ALPHA := 102.0 / 255.0

const GEM_BOX := {"ATT": "common_gem_box2", "DEF": "common_gem_box3",
	"HP": "common_gem_box1", "ALL": "common_gem_box4"}
const SKILL_BG := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
	"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}
const SKILL_MARK := {"tri": "common_skill_triangle", "sq": "common_skill_square",
	"cir": "common_skill_circle", "star": "common_skill_star"}
const SKILL_SLOT_MARK := {"tri": "△", "sq": "□", "cir": "○", "star": "☆"}

const SLOT_BOX := 1.05

const ELE_SMALL := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire",
	"aqua": "item_item_small_ele_water", "earth": "item_item_small_ele_ground",
	"wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy",
	"chaos": "item_item_small_ele_chaos", "shadow": "item_item_small_ele_shadow"}

var _pma: CanvasItemMaterial
var _man_common: Dictionary = {}
var _man_stand: Dictionary = {}
var _man_status: Dictionary = {}
var _man_item_small: Dictionary = {}
var _man_portrait: Dictionary = {}

var _root: Control
var _uid := -1
var _panel_only := false
var _panel_left := true
var _panel_pos := Vector2.INF
var _panel_dismiss := true
var _record: Dictionary = {}

var _edit := true
var _tip: Control = null
var _tip_tag := 0
var _pane: Control = null

const TAG_EQUIP := 3
const TAG_DRINK := 4
const TAG_SKILL := 5
const TAG_GEM := 7

static func open(host: Node) -> StatusPanel:
	var l := StatusPanel.new()
	l.layer = 24
	host.add_child(l)
	return l

static func open_panel(host: Node, record: Dictionary, left := true,
		pos := Vector2.INF, dismiss := true, edit := false) -> StatusPanel:
	var l := StatusPanel.new()
	l.layer = 24
	l._panel_only = true
	l._record = record
	l._panel_left = left
	l._panel_pos = pos
	l._panel_dismiss = dismiss
	l._edit = edit
	host.add_child(l)
	return l

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_man_common = _load_manifest("common_ui")
	_man_stand = _load_manifest("stand_ui")
	_man_status = _load_manifest("status_ui")
	_man_item_small = _load_manifest("item_small_ui")
	_uid = UserDB.active_uid()
	_build()

func _load_manifest(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if ResourceLoader.exists(p): s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _cspr(key: String, scale := 1.0) -> Sprite2D:
	return _spr("common_ui", key, scale)

func _cw(key: String, fallback := 1.0) -> float:
	return maxf(1.0, float(_man_common.get(key, {}).get("w", fallback)))

func _ch(key: String, fallback := 1.0) -> float:
	return maxf(1.0, float(_man_common.get(key, {}).get("h", fallback)))

func _tex(dir: String, key: String) -> Texture2D:
	return AtlasUI.tex(dir, key)

func _portrait(id: int, stage: String, scale := 1.0, skin := 0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _man_portrait.has(dir):
		_man_portrait[dir] = _load_manifest(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if not (_man_portrait[dir] as Dictionary).has(frame) and stage == "evolution":
		frame = "dragon_dragon_%d_box_adult" % id
	if skin > 0 and (_man_portrait[dir] as Dictionary).has("%s_skin%d" % [frame, skin]):
		frame = "%s_skin%d" % [frame, skin]
	return _spr(dir, frame, scale)

func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size

func _dragon() -> Dictionary:
	if not _record.is_empty():
		return _record
	var d := UserDB.get_dragon(_uid)
	return d if not d.is_empty() else UserDB.active_dragon()

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static var _bmfonts: Dictionary = {}
func _bmfont(name := "font_subtitle") -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f

func _bm_label(text: String, size: int, col: Color, name := "font_subtitle") -> Label:
	var l := _label(text, size, col)
	var f := _bmfont(name)
	if f != null:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 4)
	return l

func _rounded(size: Vector2, col: Color, radius := 12) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _close() -> void:
	closed.emit()
	queue_free()

func _act(action: String, arg := -1) -> void:
	action_requested.emit(action, arg)
	_close()

func _editable_uid() -> int:
	if not _edit:
		return -1
	var uid := int(_dragon().get("uid", _uid))
	return uid if uid > 0 and not UserDB.get_dragon(uid).is_empty() else -1

func _after_edit(uid: int) -> void:
	_redraw(uid)

func _click_equip() -> void:
	var uid := _editable_uid()
	if uid < 0:
		return
	var box: Array = [null]
	box[0] = EquipSlotsPanel.open(self, uid, "equip", func(sid: String, unlocked: bool) -> void:
		if not unlocked:
			Toast.show(self, "%s  (연구소 '드래곤 강화')" % EquipSlotsPanel.S_LOCK)
			return
		var refresh := func() -> void:
			if is_instance_valid(box[0]):
				(box[0] as EquipSlotsPanel).rebuild()
		var ip := ItemWindow.open(self, uid, sid, refresh)
		ip.closed.connect(refresh))
	(box[0] as EquipSlotsPanel).closed.connect(func() -> void: _after_edit(uid))

func _click_skill(slot: int, a: Dictionary) -> void:
	var uid := _editable_uid()
	if uid >= 0:
		var p := SkillLoadoutWindow.open(self, uid, slot)
		p.closed.connect(func() -> void: _after_edit(uid))
		return
	var sid := int(Loadout.equipped_ids(a)[slot])
	if sid <= 0:
		return
	var sdef: Dictionary = Data.skills.get(str(sid), {})
	var lv := int(Loadout.equipped_entry(a, slot).get("level", 1))
	_tip_show(TAG_SKILL + slot, "%s Lv.%d" % [String(sdef.get("name", "스킬")), lv],
		String(sdef.get("desc", sdef.get("comment", ""))))

func _click_gem(slot: int, a: Dictionary) -> void:
	var en := Gem.entries(a.get("gems", {}))
	if slot >= en.size() or en[slot] == null:
		return
	var gname := String(en[slot]["name"])
	var tier := int(en[slot]["tier"])
	var lines: Array = []
	var labels: Dictionary = Data.gems.get("stat_keys", {})
	var st := Gem.tier_stats(gname, tier, Data.gems)
	for k in st.keys():
		var kr := String(labels.get(String(k), String(k))).split("(")[0].strip_edges()
		var pct := "%" if String(k).ends_with("_pct") or String(k) in Gem.SUB_KEYS else ""
		lines.append("%s +%d%s" % [kr, int(st[k]), pct])
	_tip_show(TAG_GEM + slot, "%s +%d" % [gname, tier], "\n".join(PackedStringArray(lines)))

func _click_drink(a: Dictionary, tip_body: String) -> void:
	var uid := _editable_uid()
	if uid >= 0:
		DrinkMenu.open(self, uid, func() -> void: _after_edit(uid))
		return
	if (a.get("drink_buffs", {}) as Dictionary).is_empty():
		return
	_tip_show(TAG_DRINK, "버프 드링크", tip_body)

const TIP_H := 150.0
const TIP_INSET := 50.0
const TIP_BODY_DROP := 55.0
const TIP_SCALE := 0.8
const TIP_BG := Color(0x3c / 255.0, 0x3c / 255.0, 0x3c / 255.0, 0xc8 / 255.0)

func _tip_close() -> void:
	if is_instance_valid(_tip):
		_tip.queue_free()
	_tip = null

func _tip_show(tag: int, title: String, body: String) -> void:
	_tip_close()
	if _tip_tag == tag:
		_tip_tag = 0
		return
	_tip_tag = tag
	if not is_instance_valid(_pane):
		return
	Bgm.sfx("effect_button", 0.5)
	var PW: float = _pane.size.x
	var PH: float = _pane.size.y
	var w := PW - TIP_INSET
	var h := TIP_H

	var root := Control.new()
	root.size = Vector2(w, h)
	root.scale = Vector2(TIP_SCALE, TIP_SCALE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cx := PW * 0.5 + (6.0 if tag >= TAG_GEM else 0.0)
	var cy_cocos := (PH / 3.0 + h * TIP_SCALE * 0.5 + 50.0) if tag >= TAG_GEM \
		else (h * TIP_SCALE * 0.5 + 95.0)
	root.position = Vector2(cx - w * TIP_SCALE * 0.5, PH - cy_cocos - h * TIP_SCALE * 0.5)
	_pane.add_child(root)
	_tip = root

	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	win.patch_margin_left = 30; win.patch_margin_right = 30
	win.patch_margin_top = 30; win.patch_margin_bottom = 30
	win.size = Vector2(w, h)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(win)

	var bodybg := _rounded(Vector2(w - 24.0, h - TIP_BODY_DROP - 12.0), TIP_BG, 8)
	bodybg.position = Vector2(12.0, TIP_BODY_DROP)
	root.add_child(bodybg)

	var t := _bm_label(title, 16, Color(1.0, 0.95, 0.75))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = Vector2(w, TIP_BODY_DROP)
	root.add_child(t)
	var b := _bm_label(body, 13, Color.WHITE, "font_common")
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size = bodybg.size
	bodybg.add_child(b)

func _reopen(uid: int) -> void:
	UserDB.set_active(uid)
	_uid = uid
	if is_instance_valid(_root): _root.queue_free()
	_build()

func _build() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	if _panel_only:
		_build_panel_only(vis, S)
		return

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed: _close())
	add_child(dim)

	var W: float = vis.x - 40.0
	var H: float = vis.y - 40.0
	_root = NinePatchRect.new()
	(_root as NinePatchRect).texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	(_root as NinePatchRect).patch_margin_left = 130
	(_root as NinePatchRect).patch_margin_top = 190
	(_root as NinePatchRect).patch_margin_right = 55
	(_root as NinePatchRect).patch_margin_bottom = 81
	_root.size = Vector2(W, H)
	_root.position = Vector2(20, 20)
	add_child(_root)

	_build_title(W, S)

	var a := _dragon()
	if a.is_empty():
		var e := _label("보유 드래곤이 없습니다", 24, Color(0.9, 0.86, 0.76))
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.size = Vector2(W, 30); e.position = Vector2(0, H * 0.45)
		_root.add_child(e)
		return

	const TITLE_H := 56.0
	const STRIP_H := 135.0
	var strip_y: float = H - STRIP_H - 26.0
	var body_top := TITLE_H
	var body_h: float = strip_y - body_top - 10.0

	var stage_w: float = maxf(360.0, W - 380.0)
	_build_stage(a, stage_w, body_top, body_h, S)
	_build_panel(a, W, body_top, S)
	_build_strip(W, strip_y, STRIP_H)

func _build_panel_only(vis: Vector2, S: float) -> void:
	var a := _dragon()
	if a.is_empty():
		queue_free()
		return
	if _panel_dismiss:
		var catcher := Control.new()
		catcher.size = vis
		catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		catcher.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				_close())
		add_child(catcher)

	var pw := PANEL.x * PANEL_SCALE
	var margin := 16.0
	var inner := 40.0 + pw
	_root = Control.new()
	_root.size = Vector2(pw, PANEL.y * PANEL_SCALE)
	_root.position = _panel_pos if _panel_pos.is_finite() else \
		Vector2(margin if _panel_left else vis.x - pw - margin,
			maxf(10.0, vis.y * 0.5 - PANEL.y * PANEL_SCALE * 0.5))
	add_child(_root)
	_build_panel(a, inner, 0.0, S)

func _build_title(W: float, S: float) -> void:
	var tw := 300.0
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(tw, 33.0 * S)
	tbar.position = Vector2((W - tw) * 0.5, 2.0)
	tbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tbar)
	var t := _bm_label("상태창", 30, Color.WHITE, "font_title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = tbar.size
	tbar.add_child(t)
	var xb := TextureButton.new()
	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		xb.texture_normal = load(xt)
		xb.scale = Vector2(S, S)
		xb.position = Vector2(W - 24.0 - 48.0 * S, 6.0)
		xb.pressed.connect(_close)
		_root.add_child(xb)

func _build_stage(a: Dictionary, stage_w: float, top: float, h: float, S: float) -> void:
	var id := Icons.art_id_of(a)
	var lvl := int(a.get("level", 1))
	var cx := stage_w * 0.5

	var nb_w := _cw("common_name_bg", 302.0) * S
	var nb_h := _ch("common_name_bg", 41.0) * S
	var nb_cy := top + nb_h * 0.5
	var nb := _cspr("common_name_bg", S)
	nb.position = Vector2(cx, nb_cy)
	_root.add_child(nb)
	var nl := _label(Icons.name_of(a), 28, Color(0.36, 0.22, 0.08))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.size = Vector2(nb_w - 70.0, nb_h)
	nl.position = Vector2(cx - (nb_w - 70.0) * 0.5, nb_cy - nb_h * 0.5)
	_root.add_child(nl)
	var pen_w := _cw("common_namepen", 36.0) * S
	var pen_cx := cx + nb_w * 0.5 - pen_w * 0.5
	var pen := _cspr("common_namepen", S)
	pen.position = Vector2(pen_cx, nb_cy)
	_root.add_child(pen)
	var pen_hit := Button.new()
	pen_hit.flat = true
	pen_hit.tooltip_text = "이름 바꾸기"
	pen_hit.size = Vector2(pen_w + 16.0, nb_h)
	pen_hit.position = Vector2(pen_cx - pen_w * 0.5 - 8.0, nb_cy - nb_h * 0.5)
	pen_hit.pressed.connect(func(): _act("rename"))
	_root.add_child(pen_hit)

	var st_y: float = top + h - 52.0
	var sp := _rounded(Vector2(160.0, 45.0), Color(0, 0, 0, STAMINA_ALPHA), 22)
	sp.position = Vector2(cx - 80.0, st_y)
	_root.add_child(sp)
	var bolt := _cspr("common_bubble_food", 0.95)
	bolt.position = Vector2(30, 22)
	sp.add_child(bolt)
	var fmax := ItemEffect.food_max(Data.item_effects)
	var food := clampi(int(a.get("food", fmax)), 0, fmax)
	var sl := _bm_label("%d / %d" % [food, fmax], 20,
		Color(1, 0.45, 0.4) if food <= 0 else Color.WHITE)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sl.size = Vector2(100, 45); sl.position = Vector2(54, 0)
	sp.add_child(sl)

	var uid_cur := int(a.get("uid", 0))
	if uid_cur > 0 and UserDB.is_down(uid_cur):
		var now := int(Time.get_unix_time_from_system())
		var ct := UserDB.cure_time(uid_cur)
		var cost := Incapacitation.instant_cost(Data.incapacitation, ct, now)
		var db := _rounded(Vector2(300.0, 40.0), Color(0.35, 0.05, 0.05, 0.78), 18)
		db.position = Vector2(cx - 150.0, st_y - 46.0)
		_root.add_child(db)
		var dl := _bm_label("행동불능 — 남은 %s   (다이아 %d)" % [
			Incapacitation.remain_text(ct, now), cost], 18, Color(1, 0.86, 0.86))
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dl.size = Vector2(300, 40)
		db.add_child(dl)
		var cb := Button.new()
		cb.flat = true; cb.size = Vector2(300, 40)
		cb.pressed.connect(func():
			if cost > 0 and not UserDB.spend("diamond", cost):
				return
			UserDB.set_cure_time(uid_cur, 0)
			_reopen(uid_cur))
		db.add_child(cb)

	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var st_key := "stand_stand%d" % (si + 1)
	var raw_w: float = maxf(1.0, float(_man_stand.get(st_key, {}).get("w", 305)))
	var raw_h: float = maxf(1.0, float(_man_stand.get(st_key, {}).get("h", 120)))
	var stand_w: float = clampf(stage_w * 0.40, 220.0, 420.0)
	var st_sc := stand_w / raw_w
	var stand_bottom: float = st_y - 6.0
	var ped := _spr("stand_ui", st_key, st_sc)
	ped.position = Vector2(cx, stand_bottom - raw_h * st_sc * 0.5)
	_root.add_child(ped)

	var origin := Vector2(cx, stand_bottom - stand_w * 0.587)
	if UserDB.is_egg(a):
		var egg := Sprite2D.new()
		egg.texture = Icons.dragon_egg_texture(id)
		egg.material = _pma
		egg.scale = Vector2(S, S)
		egg.position = origin
		_root.add_child(egg)
		return

	var stage_name := Growth.spine_stage(a)
	var path := Icons.spine_scene(id, stage_name)
	if bool(a.get("awakened", false)) and path == "":
		stage_name = Growth.stage_for_level(lvl)
		path = Icons.spine_scene(id, stage_name)
	if path != "":
		var holder := Node2D.new()
		holder.scale = Vector2.ONE * (1.9 * stand_w / 620.0)
		holder.position = origin
		_root.add_child(holder)
		var inst := (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null and ap.has_animation("wait"):
			ap.play("wait")
	else:
		var por := _portrait(id, Growth.portrait_stage(a), stand_w / 220.0, int(a.get("skin", 0)))
		por.position = origin
		_root.add_child(por)
		push_warning("[status] dragon %d(%s) 스파인 씬 미빌드 → 초상 폴백" % [id, stage_name])

func _build_panel(a: Dictionary, W: float, top: float, S: float) -> float:
	var PW := PANEL.x
	var PH := PANEL.y
	var inset: float = clampf((W - 670.0) * 0.25, 40.0, 200.0)
	var pane := Control.new()
	pane.scale = Vector2(PANEL_SCALE, PANEL_SCALE)
	pane.size = Vector2(PW, PH)
	pane.position = Vector2(W - inset - PW * PANEL_SCALE, top)
	_root.add_child(pane)
	_pane = pane
	_tip = null
	_tip_tag = 0

	var bg := NinePatchRect.new()
	bg.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
	bg.patch_margin_left = 22; bg.patch_margin_right = 22
	bg.patch_margin_top = 16; bg.patch_margin_bottom = 16
	bg.size = Vector2(PW, PH)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(bg)

	var id := int(a.get("id", 1))
	var lvl := int(a.get("level", 1))
	var ddef: Dictionary = Data.get_dragon(id)
	var stage_name := Growth.portrait_stage(a)

	var box_w := _cw("common_item_box2", 58.0) * S
	var box := _cspr("common_item_box2", S)
	box.position = Vector2(55, 70)
	pane.add_child(box)
	var por := _portrait(Icons.art_id_of(a), stage_name, S * 0.62, int(a.get("skin", 0)))
	por.position = Vector2(55, 70)
	pane.add_child(por)
	var ekey := String(ELE_SMALL.get(Icons.element_of(a), ""))
	if ekey != "" and _man_item_small.has(ekey):
		var eh: float = maxf(1.0, float(_man_item_small[ekey].get("h", 70)))
		var es := _spr("item_small_ui", ekey, 30.0 / eh)
		es.position = Vector2(55 - box_w * 0.5 + 11.0, 70 - box_w * 0.5 + 11.0)
		pane.add_child(es)

	var lv := _bm_label("레벨 %d" % lvl, 18, Color.WHITE)
	lv.position = Vector2(100, 8); lv.size = Vector2(150, 24)
	pane.add_child(lv)
	var nm := _label(Icons.name_of(a), 20,
		Color(0.9, 0.87, 0.8))
	nm.position = Vector2(100, 32); nm.size = Vector2(160, 22)
	pane.add_child(nm)
	var grade: float = float(a["grade_override"]) if a.has("grade_override") else \
		Growth.compute_grade(ddef, Data.stat_table, a.get("stat_bonus", {}),
		a.get("gain_log", []), Data.level_curve.get("grade", {}))
	var gl := _bm_label("%.1f" % grade, 29, Color(1.0, 0.62, 0.12), "font_rating")
	gl.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0, 0.9))
	gl.add_theme_constant_override("outline_size", 4)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.position = Vector2(PW - 118.0, 6); gl.size = Vector2(100, 30)
	pane.add_child(gl)

	var need := LevelSystem.exp_to_next(Data.level_curve, lvl)
	var cur_exp := int(a.get("exp", 0))
	var ratio: float = clampf(float(cur_exp) / maxf(1.0, float(need)), 0.0, 1.0)
	_gauge(pane, Vector2(100, 77), "common_bar_exp", ratio, S)
	var eicon := _spr("adventure_ui", "scene_adventure_icon_exp", S * 0.85)
	if eicon.texture == null:
		eicon.queue_free()
	else:
		eicon.position = Vector2(100, 77)
		pane.add_child(eicon)
	var bw := _cw("common_bar_bg2", 162.0) * S
	var et := _bm_label("%d / %d" % [cur_exp, need], 15, Color.WHITE, "font_common")
	et.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	et.add_theme_constant_override("outline_size", 3)
	et.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	et.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	et.size = Vector2(bw - 30.0, 18); et.position = Vector2(125, 68)
	pane.add_child(et)

	_build_stats(pane, a, PW)

	var gw := box_w + 15.0
	var gh := box_w + 40.0
	var wide := 220.0
	_build_item_group(pane, a, Vector2(60.0 - gw * 0.5, 265.0 - gh * 0.5), Vector2(gw, gh), S)
	_build_gem_group(pane, a, Vector2(60.0 + gw * 0.5 + 5.0, 265.0 - gh * 0.5), Vector2(wide, gh), S)
	_build_drink_group(pane, a, Vector2(60.0 - gw * 0.5, 385.0 - gh * 0.5), Vector2(gw, gh), S)
	_build_skill_group(pane, a, Vector2(60.0 + gw * 0.5 + 5.0, 385.0 - gh * 0.5), Vector2(wide, gh), S)
	return pane.position.y + PH * PANEL_SCALE

func _gauge(pane: Control, at: Vector2, fill_key: String, ratio: float, S: float) -> void:
	var bh := _ch("common_bar_bg2", 11.0) * S
	for k in ["common_bar_bg2", fill_key, "common_bar_cover"]:
		var sp := _cspr(k, S)
		if sp.texture == null:
			sp.queue_free(); continue
		sp.centered = false
		if k == fill_key:
			if ratio <= 0.0:
				sp.queue_free(); continue
			sp.scale = Vector2(S * ratio, S)
		sp.position = Vector2(at.x, at.y - bh * 0.5)
		pane.add_child(sp)

static func display_stats(a: Dictionary) -> Dictionary:
	var ddef: Dictionary = Data.get_dragon(int(a.get("id", 1)))
	var base_bonus: Dictionary = (a.get("stat_bonus", {}) as Dictionary).get("base", {})
	var base: Dictionary = Growth.main_stats(ddef, Data.stat_table, a.get("gain_log", []), base_bonus)
	var total: Dictionary = Gem.apply(base.duplicate(), a.get("gems", {}), Data.gems)
	total = Equipment.apply(total, a.get("equip", {}), Data.equipment)
	total = EquipEffect.apply_static(total, a.get("equip", {}), Data.equip_effects)
	var ov: Dictionary = a.get("stat_override", {})
	for k in ov:
		total[k] = float(ov[k]) if PartyStats.PROB_STATS.has(String(k)) else int(round(float(ov[k])))
	total = PartyStats.with_awaken(a, total)
	return {"base": base, "total": total, "fixed": ov.keys()}

func _build_stats(pane: Control, a: Dictionary, PW: float) -> void:
	var shown := display_stats(a)
	var main: Dictionary = shown["base"]
	var total: Dictionary = shown["total"]
	var ov: Array = shown["fixed"]

	var rows_l := [["생명력", "hp"], ["공격력", "att"], ["방어력", "def"]]
	var rows_r := [["치명타", "cri"], ["방어율", "blk"], ["회피율", "evd"]]
	for i in 3:
		var y: float = [130.0, 157.0, 184.0][i]
		var kl: String = String(rows_l[i][1])
		var add: int = int(total.get(kl, 0)) - int(main.get(kl, 0))
		var txt := "%d" % int(main.get(kl, 0))
		if ov.has(kl):
			txt = "%d" % int(total.get(kl, 0))
		elif add != 0:
			txt += " + %d" % add
		var ll := _bm_label("%s : " % String(rows_l[i][0]), 19, Color(0.72, 0.68, 0.6))
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ll.size = Vector2(86, 22); ll.position = Vector2(4, y - 11)
		pane.add_child(ll)
		var lv := _bm_label(txt, 19, Color(0.98, 0.96, 0.9), "font_common")
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lv.size = Vector2(110, 22); lv.position = Vector2(94, y - 11)
		pane.add_child(lv)

		var kr: String = String(rows_r[i][1])
		var rl := _bm_label("%s : " % String(rows_r[i][0]), 19, Color(0.72, 0.68, 0.6))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.size = Vector2(86, 22); rl.position = Vector2(PW * 0.5 + 10.0, y - 11)
		pane.add_child(rl)
		var padd: int = int(total.get(kr, 0)) - int(main.get(kr, 0))
		var ptxt := "+%d%%" % padd
		if ov.has(kr):
			var pf := float(total.get(kr, 0.0))
			ptxt = ("%d%%" % int(roundf(pf))) if is_equal_approx(pf, roundf(pf)) else ("%.1f%%" % pf)
		var rv := _bm_label(ptxt, 19, Color(0.98, 0.96, 0.9), "font_common")
		rv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rv.size = Vector2(76, 22); rv.position = Vector2(PW * 0.5 + 102.0, y - 11)
		pane.add_child(rv)

func _group(pane: Control, at: Vector2, size: Vector2, title: String) -> Control:
	var g := Control.new()
	g.position = at
	g.size = size
	pane.add_child(g)
	var r := _rounded(size, Color(1, 1, 1, GROUP_ALPHA), 10)
	g.add_child(r)
	var t := _bm_label(title, 18, Color(0.24, 0.2, 0.14))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(size.x, 20); t.position = Vector2(0, 4)
	g.add_child(t)
	return g

func _hit(g: Control, center: Vector2, box: float, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.tooltip_text = tip
	b.size = Vector2(box, box)
	b.position = center - Vector2(box, box) * 0.5
	if cb.is_valid():
		b.pressed.connect(cb)
	g.add_child(b)
	return b

func _icon(g: Control, tex: Texture2D, center: Vector2, scale: float) -> Sprite2D:
	if tex == null: return null
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.scale = Vector2(scale, scale)
	s.position = center
	g.add_child(s)
	return s

func _build_item_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var g := _group(pane, at, size, "아이템")
	var box := _cw("common_item_box2", 58.0) * S
	var c := Vector2(size.x * 0.5, size.y - 10.0 - box * 0.5)
	_icon(g, _tex("common_ui", "common_item_box2"), c, S)
	var eqf: Dictionary = a.get("equip", {})
	var shown := 0
	var tip := "장비"
	for sid: String in Equipment.slot_ids(a.get("equip_slots", 1)):
		var sd: Dictionary = Equipment.equipped(eqf, sid, Data.equipment)
		if sd.is_empty(): continue
		if shown == 0:
			_icon(g, Icons.equip_texture(sd), c, S * 0.55)
			tip = String(sd.get("name", "장비"))
		shown += 1
	if shown > 1:
		var n := _bm_label("×%d" % shown, 25, Color(1, 0.95, 0.75), "font_title")
		n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		n.add_theme_constant_override("outline_size", 3)
		n.position = c + Vector2(box * 0.5 - 22.0, box * 0.5 - 20.0)
		n.size = Vector2(30, 18)
		g.add_child(n)
		tip += " 외 %d" % (shown - 1)
	elif shown == 0:
		_icon(g, _tex("common_ui", "common_item_box2_plus"), c, S * 0.8)
		tip = "비어 있음"
	_hit(g, c, box, "%s\n(클릭: 장비 관리)" % tip, func(): _click_equip())

func _build_gem_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var g := _group(pane, at, size, "젬")
	var gf: Dictionary = a.get("gems", {})
	var types := Gem.types(gf)
	var en := Gem.entries(gf)
	var kr: Dictionary = (Data.gems.get("slot_types", {}) as Dictionary).get("kr", {})
	var box := _cw("common_gem_box1", 44.0) * S
	var cy: float = size.y - (size.y * 0.5 - 10.0)
	var xs := [10.0 + box * 0.5, size.x * 0.5, size.x - 10.0 - box * 0.5]
	for i in Gem.SLOTS:
		var ty := String(types[i])
		var c := Vector2(float(xs[i]), cy)
		_icon(g, _tex("common_ui", String(GEM_BOX.get(ty, "common_gem_box4"))), c, S)
		var tip := "%d번 칸 (%s)" % [i + 1, String(kr.get(ty, ty))]
		if en[i] != null:
			var gname := String(en[i]["name"])
			var tier := int(en[i]["tier"])
			_icon(g, Icons.gem_texture(String(Gem.gem_def(gname, Data.gems).get("code", "")), tier),
				c, S * 0.6)
			tip += "\n%s +%d\n(클릭: 젬 정보)" % [gname, tier]
		else:
			tip += "\n비어 있음"
		var slot := i
		_hit(g, c, box, tip, func(): _click_gem(slot, a))

const DRINK_ICON := {"att": "att_drink1", "def": "def_drink1", "hp": "hp_drink1",
	"crit": "cri_drink1", "dodge": "miss_drink1", "block": "prodef_drink1"}
const DRINK_KR := {"att": "공격력", "def": "방어력", "hp": "생명력",
	"crit": "크리티컬", "dodge": "회피", "block": "방어확률"}

func _build_drink_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var g := _group(pane, at, size, "드링크")
	var box := _cw("common_item_box2", 58.0) * S
	var c := Vector2(size.x * 0.5, size.y - 10.0 - box * 0.5)
	_icon(g, _tex("common_ui", "common_item_box2"), c, S)

	var buffs: Dictionary = a.get("drink_buffs", {})
	var tip := "버프 드링크\n(클릭: 먹이기)"
	var body := "걸려 있는 버프가 없습니다."
	if buffs.is_empty():
		var plus := _icon(g, _tex("common_ui", "common_item_box2_plus"), c, S * 0.8)
		if plus != null:
			var base := plus.scale
			var tw := plus.create_tween().set_loops()
			for f in [[0.2, 1.15], [0.2, 1.1], [0.5, 1.2], [0.5, 1.0]]:
				tw.tween_property(plus, "scale", base * float(f[1]), float(f[0]))
	else:
		var top := ""
		for k in buffs.keys():
			if top == "" or int((buffs[k] as Dictionary).get("turns", 0)) \
					> int((buffs[top] as Dictionary).get("turns", 0)):
				top = String(k)
		var ip := Data.item_icon_path(String(DRINK_ICON.get(top, "")))
		if ip != "" and ResourceLoader.exists(ip):
			_icon(g, load(ip), c, S * 0.8)
		var lines: Array = []
		for k2 in buffs.keys():
			var e: Dictionary = buffs[k2]
			lines.append("%s +%d%%  (%d턴)" % [String(DRINK_KR.get(String(k2), String(k2))),
				int(e.get("pct", 0)), int(e.get("turns", 0))])
		lines.sort()
		body = "\n".join(PackedStringArray(lines))
		tip = body + "\n(클릭: 먹이기)"

	_hit(g, c, box, tip, func(): _click_drink(a, body))

func _redraw(uid: int) -> void:
	if not _record.is_empty():
		var fresh := UserDB.get_dragon(uid)
		if not fresh.is_empty():
			_record = fresh
		for ch in get_children():
			ch.queue_free()
		_root = null
		_build()
		return
	_reopen(uid)

func _build_skill_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var awakened := bool(a.get("awakened", false))
	var g := _group(pane, at, size, "스킬" if not awakened else "")
	var lvl := int(a.get("level", 1))
	var stypes := Loadout.slot_types(a)
	var equipped := Loadout.equipped_ids(a)
	var box := _cw("common_skill_circle_bg", 65.0) * S
	var cy: float = size.y - (size.y * 0.5 - 5.0)
	var sc := 0.9 if awakened else 1.0

	if awakened:
		var t := _bm_label("스킬", 18, Color(0.24, 0.2, 0.14))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.size = Vector2(90, 20); t.position = Vector2(size.x * 2.0 / 3.0 - 50.0, 4)
		g.add_child(t)
		var at2 := _bm_label("각성스킬", 16, Color(0.24, 0.2, 0.14))
		at2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		at2.size = Vector2(84, 20); at2.position = Vector2(size.x / 6.0 - 37.0, 4)
		g.add_child(at2)
		var ac := Vector2(size.x / 6.0 + 7.0, size.y - (size.y * 0.5 - 5.0 + 4.0))
		_icon(g, _tex("common_ui", "common_skill_evolution"), ac, S * 0.9)
		var aw := int(a.get("awaken_skill", 0))
		var aw_icon := Data.awaken_skill_icon(aw) if aw > 0 else 0
		if aw_icon > 0:
			_icon(g, _tex("skill_evolution", "skill_evolution_%d" % aw_icon), ac, S * 0.6)
		var aw_tip := "각성 스킬"
		var aw_row: Dictionary = Data.skill_awaken_for(aw) if aw > 0 else {}
		if not aw_row.is_empty():
			aw_tip = String(aw_row.get("name", aw_tip))
		var aw_hit := _hit(g, ac, box * 0.9, aw_tip, Callable())
		aw_hit.pressed.connect(func():
			if aw > 0:
				DragonAwakenSkillInfoPopup.open(self, aw_hit, aw))

	var xs := ([size.x * 0.5, size.x * 5.0 / 6.0 - 4.0] if awakened
		else [size.x * 0.5 - 5.0 - box * 0.5, size.x * 0.5 + 5.0 + box * 0.5])
	for i in Loadout.SKILL_SLOTS:
		var ty := String(stypes[i])
		var c := Vector2(float(xs[i]), cy)
		_icon(g, _tex("common_ui", String(SKILL_BG.get(ty, "common_skill_star_bg"))), c, S * sc)
		var tip := "%d번 칸 (%s)" % [i + 1, String(SKILL_SLOT_MARK.get(ty, "?"))]
		if not Loadout.slot_unlocked(i, lvl):
			_icon(g, _tex("common_ui", "common_lock"), c, S * 0.8)
			_hit(g, c, box * sc, tip + "\nLv.%d 에 해금" % int(Loadout.SLOT_UNLOCK_LEVEL[i]),
				func(): pass)
			continue
		if int(equipped[i]) > 0:
			var sid := int(equipped[i])
			var sdef: Dictionary = Data.skills.get(str(sid), {})
			if Loadout.slot_matches(ty, sdef):
				_icon(g, _tex("common_ui", String(SKILL_MARK.get(ty, "common_skill_circle"))),
					c, S * sc)
			_icon(g, _tex("skill", "skill_%d" % sid), c, S * 0.6)
			var lv_e := Loadout.equipped_entry(a, i)
			tip += "\n%s Lv.%d" % [String(sdef.get("name", "스킬")), int(lv_e.get("level", 1))]
			if Loadout.slot_matches(ty, sdef):
				tip += "  (타입 일치 · %s)" % Loadout.slot_match_label(sdef, Data.combat)
			tip += "\n(클릭: 스킬 교체)"
		else:
			tip += "\n비어 있음 (클릭: 장착)"
		var slot := i
		_hit(g, c, box * sc, tip, func(): _click_skill(slot, a))

func _build_strip(W: float, y: float, strip_h: float) -> void:
	var strip := NinePatchRect.new()
	strip.texture = load("res://assets/converted/ninepatch_ui/9patch_scroll_box.tres")
	strip.patch_margin_left = 65; strip.patch_margin_top = 65
	strip.patch_margin_right = 31; strip.patch_margin_bottom = 31
	strip.size = Vector2(W - 40.0, strip_h)
	strip.position = Vector2(20.0, y)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(strip)

	var owned: Array = UserDB.dragons()
	var S := Design.ASSET_SCALE
	var side := _cw("common_dragon_bg2", 81.0) * S
	var box := side * SLOT_BOX
	var row_h := strip_h - 12.0
	var cs: float = minf(1.0, (row_h - 6.0) / box)
	var step := (side + 15.0) * cs
	var scroll := ScrollContainer.new()
	scroll.position = strip.position + Vector2(25.0, 6.0)
	scroll.size = Vector2(strip.size.x - 50.0, row_h)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var row := Control.new()
	row.custom_minimum_size = Vector2(owned.size() * step + 70.0, row_h)
	scroll.add_child(row)

	for i in owned.size():
		var d: Dictionary = owned[i]
		var uid := int(d.get("uid", -1))
		var sel := uid == _uid
		var cell := Node2D.new()
		cell.position = Vector2((15.0 + box * 0.5) * cs + i * step,
			row_h - (10.0 + box * 0.5) * cs)
		cell.scale = Vector2(cs, cs)
		row.add_child(cell)
		cell.add_child(_cspr("common_dragon_bg1" if sel else "common_dragon_bg2", S))
		var por := _portrait(Icons.art_id_of(d),
			Growth.portrait_stage(d), 0.9 * S, int(d.get("skin", 0)))
		por.position = Vector2(0, -7.5)
		cell.add_child(por)
		cell.add_child(_cspr("common_dragon_cover1" if sel else "common_dragon_cover2", S))
		var lv := _bm_label("레벨 %d" % int(d.get("level", 1)),
			int(round(19.0 * S * 0.8)), Color.WHITE)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lv.size = Vector2(box, 26.0)
		lv.position = Vector2(-box * 0.5, box * 0.5 - 5.0 - 26.0)
		cell.add_child(lv)
		var b := Button.new(); b.flat = true
		b.size = Vector2(box * cs, box * cs)
		b.position = cell.position - Vector2(box * cs * 0.5, box * cs * 0.5)
		b.pressed.connect(func(): _reopen(uid))
		row.add_child(b)
