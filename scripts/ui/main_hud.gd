extends CanvasLayer
class_name MainHud

const COMMON := "res://assets/converted/common_ui/%s.tres"
const WMUI := "res://assets/converted/worldmap_ui/%s.tres"
const NP := "res://assets/converted/ninepatch_ui/%s.tres"

const ROUNDED := Vector2(200.0, 45.0)
const ROUNDED_ALPHA := 102.0 / 255.0

const BAR_MENU := [
	["미션", "quests"],
	["점술집", "magicshop"],
	["가방", "bag"],
	["상점", "shop"],
	["육성", "promote"],
	["연구소", "laboratory"],
	["콜로세움", "colosseum"],
	["월드맵", "overview"],
]

const INFO := Vector2(200.0, 54.0)

const BAR_TEX := "res://assets/converted/mainbar_ui/uibar_clean.png"
const BAR_META := "res://assets/converted/mainbar_ui/_uibar_meta.json"
const BAR_REF_W := 1000.0
const BAR_REF_H_FALLBACK := 123.0
const BAR_REF_TOP_FALLBACK := 0.0
const BAR_SLOT_CX := [43.0, 136.5, 249.0, 564.0, 658.5, 758.5, 853.5, 949.0]
const BAR_SLOT_W := 87.0
const BAR_SLOT_TOP := [57.0, 79.0, 79.0, 56.0, 73.0, 82.0, 79.0, 61.0]
const BAR_SLOT_TOP_ADJ := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0]
const BAR_LABEL_CY := 102.0
const BAR_LABEL_H := 16.0
const BAR_LABEL_SCALE := 0.92
const BAR_OFFSET_Y := 2.0
const BAR_CAVE := Vector3(409.5, 83.0, 58.0)

const BAR_FONT := "res://assets/converted/font_ui/font_common.fnt"

var _pma: CanvasItemMaterial
var _man_common: Dictionary = {}
var _man_wm: Dictionary = {}
var _portrait_man: Dictionary = {}
var _root: Control
var _mode := "worldmap"
var _show_variants := false
var _phase := ""

signal town_close()
signal town_quest()

static func attach(scene: Node, show_variants := false, phase := "", mode := "worldmap") -> MainHud:
	for c in scene.get_children():
		if c is MainHud and not c.is_queued_for_deletion():
			var h := c as MainHud
			h._show_variants = show_variants
			h._phase = phase
			h._mode = mode
			h.refresh()
			return h
	var hud := MainHud.new()
	hud.layer = 10
	hud._show_variants = show_variants
	hud._phase = phase
	hud._mode = mode
	scene.add_child(hud)
	return hud

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_man_common = _manifest("common_ui")
	_man_wm = _manifest("worldmap_ui")
	refresh()

func refresh() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var vis := _vis()
	_build_profile(vis)
	_build_currency(vis)
	if _mode == "town":
		_build_close_button(vis)
		_build_town_quest(vis)
		return
	_build_bottom_bar(vis)
	_build_setting_button(vis)
	if _show_variants:
		_build_variant_toggles(vis)

func _build_profile(_vis_size: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var bw := float(_man_common.get("common_dragon_bg1", {}).get("w", 81)) * S * 1.05
	var bh := float(_man_common.get("common_dragon_bg1", {}).get("h", 81)) * S * 1.05
	var cx := bw * 0.5 + 20.0
	var cy := bh * 0.5 + 25.0

	var ix := cx + bw * 0.5 - 14.0
	var iy := cy - INFO.y * 0.5
	var show_band := _mode != "town"
	if show_band:
		var band := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0, 0, 0, ROUNDED_ALPHA)
		bsb.set_corner_radius_all(int(INFO.y * 0.35))
		band.add_theme_stylebox_override("panel", bsb)
		band.size = INFO
		band.position = Vector2(ix, iy)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(band)

	var bg := _spr("common_ui", "common_dragon_bg1", _man_common, S * 1.05)
	if bg: bg.position = Vector2(cx, cy); _root.add_child(bg)

	var a := UserDB.active_dragon()
	if not a.is_empty():
		var did := Icons.art_id_of(a)
		var por := _portrait(did, profile_portrait_stage(a), int(a.get("skin", 0)))
		if por != null:
			var pw: float = maxf(1.0, float(por.texture.get_width()))
			var ps := 90.0 / pw
			por.scale = Vector2(ps, ps)
			por.position = Vector2(cx, cy - 7.5)
			_root.add_child(por)

	var cover := _spr("common_ui", "common_dragon_cover1", _man_common, S * 1.05)
	if cover: cover.position = Vector2(cx, cy); _root.add_child(cover)

	var tno := UserDB.user_title_no() if show_band else 0
	if tno > 0:
		var tp := "res://assets/converted/%s/title_%d_kr.tres" % [
			String(Data.titles.get("atlas_dir", "title_ui")), tno]
		if ResourceLoader.exists(tp):
			var tr := TextureRect.new()
			tr.texture = load(tp)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = Vector2(INFO.x - 44.0, 24.0)
			tr.position = Vector2(ix + 34.0, iy + 3.0)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(tr)

	var nick := UserDB.user_nickname() if show_band else ""
	if nick != "":
		_root.add_child(_label(nick, 19, Color(1, 0.96, 0.86),
			Vector2(ix + 36.0, iy + INFO.y * 0.5), Vector2(INFO.x - 46.0, 24.0),
			HORIZONTAL_ALIGNMENT_LEFT))
	if not a.is_empty():
		_root.add_child(_label("Lv %d" % int(a.get("level", 1)), 17, Color(1, 0.86, 0.42),
			Vector2(cx - bw * 0.5, cy + bh * 0.5 - 6.0), Vector2(bw, 22.0)))

	var hit := _hit(Rect2(cx - bw * 0.5, cy - bh * 0.5, bw, bh), "상태창")
	hit.pressed.connect(func(): _act("status"))
	_root.add_child(hit)

func _build_currency(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var dia_h := float(_man_common.get("common_diamond_big", {}).get("h", 33)) * S
	var y := dia_h * 0.5 + 25.0
	var dia_x := vis.x - 130.0
	var gold_x := dia_x - ROUNDED.x - 50.0
	_currency_row(gold_x, y, "common_coin_big", "common_charge_coin",
		_comma(UserDB.gold()), S)
	_currency_row(dia_x, y, "common_diamond_big", "common_charge",
		_comma(UserDB.diamond()), S)

func _currency_row(icon_x: float, y: float, icon_key: String, charge_key: String,
		text: String, S: float) -> void:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, ROUNDED_ALPHA)
	sb.set_corner_radius_all(int(ROUNDED.y * 0.5))
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = ROUNDED
	panel.position = Vector2(icon_x - ROUNDED.x, y - ROUNDED.y * 0.5)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	_root.add_child(_label(text, 21, Color.WHITE,
		Vector2(panel.position.x + 34.0, y - 14.0),
		Vector2(ROUNDED.x - 34.0 - 25.0, 28.0), HORIZONTAL_ALIGNMENT_RIGHT))

	var icon := _spr("common_ui", icon_key, _man_common, S)
	if icon: icon.position = Vector2(icon_x, y); _root.add_child(icon)

	var cb := _spr("common_ui", charge_key, _man_common, S * 1.05)
	var cx := icon_x - ROUNDED.x + 20.0
	if cb: cb.position = Vector2(cx, y); _root.add_child(cb)
	var cw := float(_man_common.get(charge_key, {}).get("w", 30)) * S * 1.05
	var hit := _hit(Rect2(cx - cw * 0.5, y - cw * 0.5, cw, cw), "다이아 상점")
	hit.pressed.connect(func(): _act("cashshop"))
	_root.add_child(hit)

func _build_close_button(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var c := Vector2(vis.x - 50.0, 50.0)
	var btn := _spr("common_ui", "common_close_btn", _man_common, S)
	if btn != null:
		btn.position = c
		btn.modulate.a = 0.0
		btn.scale = Vector2.ZERO
		_root.add_child(btn)
		var tw := btn.create_tween()
		tw.tween_interval(1.0)
		tw.tween_property(btn, "modulate:a", 1.0, 0.5)
		tw.parallel().tween_property(btn, "scale", Vector2(S, S) * 1.1, 0.5)
		tw.tween_property(btn, "scale", Vector2(S, S), 0.1)
	var w := float(_man_common.get("common_close_btn", {}).get("w", 44)) * S
	var h := float(_man_common.get("common_close_btn", {}).get("h", 44)) * S
	var hit := _hit(Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h), "월드맵으로")
	hit.pressed.connect(func(): town_close.emit())
	_root.add_child(hit)

func _build_town_quest(_vis_size: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var man := _manifest("town_elpis")
	var key := "scene_town_elpis_icon_townquest_scroll"
	var sc := S * 1.1
	var w := float(man.get(key, {}).get("w", 60)) * sc
	var h := float(man.get(key, {}).get("h", 60)) * sc
	var c := Vector2(180.0, 29.0 + h * 0.5)
	var icon := _spr("town_elpis", key, man, sc)
	if icon != null:
		icon.position = c
		_root.add_child(icon)

	var done := 0
	var total := 0
	var host := get_parent()
	if host != null and host.has_method("town_quest_progress"):
		var p: Vector2i = host.call("town_quest_progress")
		done = p.x
		total = p.y
	if total > 0:
		_root.add_child(_label("%d/%d" % [done, total], 17, Color.WHITE,
			Vector2(c.x - w * 0.5, c.y + h * 0.5 - 7.0 - 11.0), Vector2(w - 7.0, 22.0),
			HORIZONTAL_ALIGNMENT_RIGHT))

	if host != null and host.has_method("town_quest_alert") and bool(host.call("town_quest_alert")):
		var al := _spr("common_ui", "common_alert", _man_common, S * 0.55)
		if al != null:
			al.position = Vector2(c.x + w * 0.5 - 10.0, c.y - h * 0.5 + 10.0)
			al.z_index = 5
			_root.add_child(al)
			var pt := al.create_tween().set_loops()
			pt.tween_property(al, "scale", al.scale * 1.15, 0.5).set_trans(Tween.TRANS_SINE)
			pt.tween_property(al, "scale", al.scale, 0.5).set_trans(Tween.TRANS_SINE)

	var hit := _hit(Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h), "마을 퀘스트")
	hit.pressed.connect(func(): town_quest.emit())
	_root.add_child(hit)

const SET_BTN_RIGHT := 40.0
const SET_BTN_EDGE := 59.0
const SET_BTN_GAP := 6.0
const SET_BTN_SCALE := 0.7
const SET_BTN_PAD := 6.0
func _build_setting_button(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var m: Dictionary = _man_wm.get("scene_worldmap_menu_setting", {})
	var sz := Vector2(float(m.get("w", 56)), float(m.get("h", 61))) * S * SET_BTN_SCALE
	var edge := _bar_top(vis) + SET_BTN_EDGE * (vis.x / BAR_REF_W)
	var c := Vector2(vis.x - SET_BTN_RIGHT, edge - SET_BTN_GAP - sz.y * 0.5)
	var icon := _spr("worldmap_ui", "scene_worldmap_menu_setting", _man_wm, S * SET_BTN_SCALE)
	if icon:
		icon.position = c
		_root.add_child(icon)
	var pad := Vector2(SET_BTN_PAD, SET_BTN_PAD)
	var hit := _hit(Rect2(c - sz * 0.5 - pad, sz + pad * 2.0), "설정")
	hit.pressed.connect(func(): _act("setting"))
	_root.add_child(hit)

func _build_bottom_bar(vis: Vector2) -> void:
	var meta := _bar_meta()
	var bar_h := float((meta.get("crop", {}) as Dictionary).get("h", BAR_REF_H_FALLBACK))
	var bar_top_ref := float((meta.get("crop", {}) as Dictionary).get("y", BAR_REF_TOP_FALLBACK))
	var k := vis.x / BAR_REF_W
	var top := _bar_top(vis)
	var ry := func(y: float) -> float: return top + (y - bar_top_ref) * k

	var bar := TextureRect.new()
	if ResourceLoader.exists(BAR_TEX):
		bar.texture = load(BAR_TEX)
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.position = Vector2(0.0, top)
	bar.size = Vector2(vis.x, bar_h * k)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	var fs: int = maxi(10, int(round(BAR_LABEL_H * BAR_LABEL_SCALE * k)))
	var lw := BAR_SLOT_W * k
	var lh := BAR_LABEL_H * k * 1.6
	var bar_font := _orig_font()
	for i in mini(BAR_MENU.size(), BAR_SLOT_CX.size()):
		var e: Array = BAR_MENU[i]
		var mid: float = float(BAR_SLOT_CX[i]) * k
		var l := _label(String(e[0]), fs, Color(0.20, 0.20, 0.22),
			Vector2(mid - lw * 0.5, ry.call(BAR_LABEL_CY) - lh * 0.5), Vector2(lw, lh))
		l.add_theme_constant_override("outline_size", 0)
		if bar_font != null:
			l.add_theme_font_override("font", bar_font)
		_root.add_child(l)
		var st: float = float(BAR_SLOT_TOP[i]) if i < BAR_SLOT_TOP.size() else 0.0
		var adj: float = float(BAR_SLOT_TOP_ADJ[i]) if i < BAR_SLOT_TOP_ADJ.size() else 0.0
		var hy := top + st * k + adj
		var hit := _hit(Rect2(Vector2(mid - lw * 0.5, hy),
			Vector2(lw, top + bar_h * k - hy)), String(e[0]))
		hit.pressed.connect(func(): _act(String(e[1])))
		_root.add_child(hit)

	var cr := BAR_CAVE.z * k
	var cc := Vector2(BAR_CAVE.x * k, ry.call(BAR_CAVE.y))
	var chit := _hit(Rect2(cc - Vector2(cr, cr), Vector2(cr, cr) * 2.0), "동굴")
	chit.pressed.connect(func(): _act("cave"))
	_root.add_child(chit)
	_guide_targets["cave"] = chit
	var barhit := _hit(Rect2(Vector2(0.0, top), Vector2(vis.x, bar_h * k)), "bottom_bar")
	barhit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(barhit)
	_guide_targets["bottom_bar"] = barhit

var _guide_targets: Dictionary = {}
func guide_target(id: String) -> Control:
	var n = _guide_targets.get(id)
	return n if is_instance_valid(n) else null

func _build_variant_toggles(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var x := vis.x - 58.0
	var y := 160.0
	var night := bool(UserDB.get_pmeta("yutakan_night", false))
	var kades := bool(UserDB.get_pmeta("kades_space", false))
	if _phase != "":
		kades = _phase == "kades"
		night = _phase == "night"

	var kb := _spr("worldmap_ui", "scene_worldmap_menu_kades_mode_kr", _man_wm, S * 0.85)
	if kb:
		kb.position = Vector2(x, y)
		kb.modulate = Color(1, 1, 1, 1.0 if kades else 0.55)
		_root.add_child(kb)
	var kh := _hit(Rect2(x - 40.0, y - 40.0, 80.0, 80.0), "카데스의 공간")
	kh.pressed.connect(func():
		UserDB.set_pmeta("kades_space", not kades)
		_reload_worldmap())
	_root.add_child(kh)

	if kades:
		return
	var ny := y + 86.0
	var nb := NinePatchRect.new()
	nb.texture = load(NP % "9patch_btn")
	nb.patch_margin_left = 20; nb.patch_margin_top = 20
	nb.patch_margin_right = 17; nb.patch_margin_bottom = 18
	nb.size = Vector2(84.0, 40.0)
	nb.position = Vector2(x - 42.0, ny - 20.0)
	nb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(nb)
	_root.add_child(_label("낮으로" if night else "밤으로", 17, Color.WHITE,
		nb.position, nb.size))
	var nh := _hit(Rect2(nb.position, nb.size), "밤/낮 전환")
	nh.pressed.connect(func():
		UserDB.set_pmeta("yutakan_night", not night)
		_reload_worldmap())
	_root.add_child(nh)

func _reload_worldmap() -> void:
	var sc := Scenes.current_scene()
	if sc != null and sc.has_method("_rebuild"):
		sc.call("_rebuild")

func _act(action: String) -> void:
	match action:
		"cave":
			Scenes.goto("cave")
		"shop", "magicshop", "laboratory", "breeding", "promote", "colosseum":
			Scenes.goto(action, {"from": "worldmap"})
		"status":
			var sl := StatusPanel.open(get_parent() if get_parent() != null else self)
			sl.action_requested.connect(func(a: String, arg: int):
				Scenes.goto("cave", {"open": a, "arg": arg}))
			sl.closed.connect(refresh)
		"quests":
			var host := get_parent() if get_parent() != null else self
			var ml := MissionBoard.open(host, 0, "worldmap", {})
			ml.changed.connect(refresh)
		"dex", "bag", "titles":
			Scenes.goto("cave", {"open": action})
		"setting":
			var host := get_parent() if get_parent() != null else self
			var sl := SettingsView.open(host)
			sl.closed.connect(refresh)
		"cashshop":
			var p := {"tab": "cash", "from": _mode}
			if _mode == "town":
				p["area"] = _town_area()
			Scenes.goto("shop", p)
		"overview":
			var sc := Scenes.current_scene()
			if sc != null and sc.has_method("_rebuild") and "_mode" in sc:
				sc.set("_mode", "overview")
				sc.call("_rebuild")
			else:
				Scenes.goto("worldmap")

func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size

func _town_area() -> String:
	var host := get_parent()
	if host != null and host.has_method("town_area_id"):
		return String(host.call("town_area_id"))
	return "elpis"

var _bar_meta_cache: Dictionary = {}
func _bar_top(vis: Vector2) -> float:
	var meta := _bar_meta()
	var bar_h := float((meta.get("crop", {}) as Dictionary).get("h", BAR_REF_H_FALLBACK))
	return vis.y - bar_h * (vis.x / BAR_REF_W) + BAR_OFFSET_Y

func _bar_meta() -> Dictionary:
	if _bar_meta_cache.is_empty():
		var f := FileAccess.open(BAR_META, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _bar_meta_cache = d
	return _bar_meta_cache

var _orig_font_cache: Font = null
func _orig_font() -> Font:
	if _orig_font_cache != null:
		return _orig_font_cache
	if not ResourceLoader.exists(BAR_FONT):
		return null
	var f := (load(BAR_FONT) as FontFile)
	if f == null:
		return null
	f = f.duplicate() as FontFile
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	_orig_font_cache = f
	return f

func _manifest(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

static func profile_portrait_stage(dragon: Dictionary) -> String:
	return Growth.portrait_stage(dragon)

func _spr(dir: String, key: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		push_warning("[MainHud] 프레임 없음: %s/%s" % [dir, key])
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	if not man.has(key):
		push_warning("[MainHud] 매니페스트에 키 없음: %s" % key)
	return s

func _portrait(id: int, stage: String, skin: int) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_man.has(dir):
		_portrait_man[dir] = _manifest(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if skin > 0 and (_portrait_man[dir] as Dictionary).has("%s_skin%d" % [frame, skin]):
		frame = "%s_skin%d" % [frame, skin]
	if not (_portrait_man[dir] as Dictionary).has(frame):
		frame = "dragon_dragon_%d_box_adult" % id
	return _spr(dir, frame, _portrait_man[dir], 1.0)

func _label(text: String, size: int, color: Color, pos: Vector2, dim: Vector2,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos; l.size = dim
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _hit(rect: Rect2, tip: String) -> Button:
	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.position = rect.position
	b.size = rect.size
	b.tooltip_text = tip
	return b

func _comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
