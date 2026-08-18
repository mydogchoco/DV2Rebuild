class_name ItemDetailView
extends Control

const WIN := Vector2(590.0, 520.0)
const WIN_CAP := Rect2(130, 190, 40, 58)
const BTN_SIZE := Vector2(220.0, 56.0)
const DIM_ALPHA := 127.0 / 255.0

const ICON_POS := Vector2(160.0, 370.0)
const BACKLIGHT_SCALE := 0.35

const GEM_CAP := Rect2(20, 20, 2, 2)
const GEM_BOX := Vector2(70.0, 70.0)
const GEM_FRAME := {"ATT": "9patch_gem_red_bg", "DEF": "9patch_gem_blue_bg",
	"HP": "9patch_gem_yellow_bg", "ALL": "9patch_gem_white_bg"}
const SKILL_FRAME := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
	"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}

const DRAGON_BG := "common_dragon_bg2"
const DRAGON_COVER := "common_dragon_cover2"
const DRAGON_POS := Vector2(160.0, 210.0)
const RATING_SCALE := 0.8

const S_TITLE := "아이템 사용"
const S_GEM := "현재의 잼 슬롯이 랜덤으로 변경 됩니다.\n사용하시겠습니까?"
const S_SKILL := "현재의 스킬 슬롯이 랜덤으로 변경 됩니다.\n사용하시겠습니까?"
const S_GEM_WARN := "* 착용 중인 잼은 모두 파괴됩니다."
const S_ASCENSION := "#352a1fa9"
const S_BIND_WARN := "* %d개의 귀속된 아이템이 모두 판매됩니다."
const S_LEVEL := "레벨 %d"
const WARN_COLOR := Color8(0x00, 0x29, 0x40)
const BODY_COLOR := Color8(0x2a, 0x18, 0x00)

static func open_slot_reset(host: Node, kind: String, d: Dictionary, item_key: String,
		on_confirm: Callable) -> ItemDetailView:
	var lay := CanvasLayer.new()
	lay.layer = 70
	host.add_child(lay)
	var p := ItemDetailView.new()
	p._kind = kind
	p._dragon = d
	p._item_key = item_key
	p._on_confirm = on_confirm
	p._layer = lay
	lay.add_child(p)
	return p

static func open_ascension(host: Node, d: Dictionary, item_key: String, bind_count: int,
		on_confirm: Callable) -> ItemDetailView:
	var lay := CanvasLayer.new()
	lay.layer = 70
	host.add_child(lay)
	var p := ItemDetailView.new()
	p._kind = "ascension"
	p._dragon = d
	p._item_key = item_key
	p._bind_count = bind_count
	p._on_confirm = on_confirm
	p._layer = lay
	lay.add_child(p)
	return p

var _kind := "gem"
var _dragon: Dictionary = {}
var _item_key := ""
var _bind_count := 0
var _on_confirm := Callable()
var _win: Control
var _dim: ColorRect
var _layer: CanvasLayer

func _ready() -> void:
	_build()

func _p(cocos: Vector2) -> Vector2:
	return Vector2(cocos.x, WIN.y - cocos.y)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_dim.create_tween().tween_property(_dim, "color:a", DIM_ALPHA, 0.2)

	var vis := get_viewport_rect().size
	_win = Control.new()
	_win.size = WIN
	_win.position = ((vis - WIN) * 0.5).round()
	_win.pivot_offset = WIN * 0.5
	add_child(_win)
	var frame := AtlasUI.nine("ninepatch_ui", "9patch_popup4", WIN, WIN_CAP)
	if frame != null:
		_win.add_child(frame)
	var tw := _win.create_tween()
	tw.tween_property(_win, "scale", Vector2(1.2, 1.2), 0.1)
	tw.tween_property(_win, "scale", Vector2.ONE, 0.1)

	_build_title_bar()
	_build_close()
	_build_item_row()
	_build_divider()
	_build_slot_preview()
	_build_body()
	_build_buttons()

func _build_title_bar() -> void:
	var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
	if th <= 0.0: th = 44.0
	var tw_pt := WIN.x * 0.9
	var bar := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(tw_pt, th))
	var c := _p(Vector2(WIN.x * 0.5, WIN.y - 50.0))
	if bar != null:
		bar.position = c - Vector2(tw_pt, th) * 0.5
		_win.add_child(bar)
	var l := Label.new()
	l.text = Data.ui(S_TITLE)
	_bm_style(l, 31, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(tw_pt, th)
	l.position = c - l.size * 0.5
	_win.add_child(l)

func _build_close() -> void:
	var b := TextureButton.new()
	var t := AtlasUI.tex("common_ui", "common_close_btn")
	var sz := Vector2(60.0, 60.0)
	if t != null:
		b.texture_normal = t
		b.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
		sz = AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	b.position = _p(Vector2(WIN.x - 50.0, WIN.y - 50.0)) - sz * 0.5
	b.pressed.connect(_close)
	_win.add_child(b)

func _build_item_row() -> void:
	var pos := _p(ICON_POS)
	var bl := AtlasUI.spr("common_ui", "common_backlight3", Design.ASSET_SCALE * BACKLIGHT_SCALE)
	var blw := AtlasUI.size_pt("common_ui", "common_backlight3").x * BACKLIGHT_SCALE
	if bl != null:
		bl.position = pos
		_win.add_child(bl)
	var icon := _item_icon(96.0)
	if icon != null:
		icon.position = pos
		_win.add_child(icon)
	var l := Label.new()
	l.text = _item_name()
	_bm_style(l, 26, Color.WHITE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(WIN.x - (ICON_POS.x + blw * 0.5 + 20.0) - 20.0, 44.0)
	l.position = Vector2(ICON_POS.x + blw * 0.5 + 20.0, pos.y - 22.0)
	_win.add_child(l)

func _build_divider() -> void:
	var s := AtlasUI.spr("worldmap_ui", "scene_worldmap_certificate_popup_line", Design.ASSET_SCALE)
	if s == null:
		return
	s.position = _p(Vector2(WIN.x * 0.5, WIN.y * 0.5 + 30.0))
	_win.add_child(s)

func _build_slot_preview() -> void:
	if _kind == "ascension":
		_build_dragon_row()
		return
	if _kind == "gem":
		var types := Gem.types(_dragon.get("gems", {}))
		for i in Gem.SLOTS:
			var c := _p(Vector2(WIN.x * 0.5 + i * 76.0 - 76.0, WIN.y * 0.5 - 20.0))
			var np := AtlasUI.nine("ninepatch_ui",
				String(GEM_FRAME.get(String(types[i]), "9patch_gem_white_bg")), GEM_BOX, GEM_CAP)
			if np != null:
				np.position = c - GEM_BOX * 0.5
				_win.add_child(np)
	else:
		var stypes := Loadout.slot_types(_dragon)
		for i in Loadout.SKILL_SLOTS:
			var c := _p(Vector2(WIN.x * 0.5 - 42.0 + i * 84.0, WIN.y * 0.5 - 30.0))
			var s := AtlasUI.spr("common_ui",
				String(SKILL_FRAME.get(String(stypes[i]), "common_skill_star_bg")),
				Design.ASSET_SCALE)
			if s != null:
				s.position = c
				_win.add_child(s)

func _build_dragon_row() -> void:
	var S := Design.ASSET_SCALE
	var c := _p(DRAGON_POS)
	for key in [DRAGON_BG, "", DRAGON_COVER]:
		var s: Sprite2D = null
		if key == "":
			s = _dragon_portrait(S)
		else:
			s = AtlasUI.spr("common_ui", key, S)
		if s != null:
			s.position = c
			_win.add_child(s)
	var bw := AtlasUI.size_pt("common_ui", DRAGON_BG).x
	if bw <= 0.0:
		bw = 108.0
	var lx := DRAGON_POS.x + bw * 0.5

	var lv := Label.new()
	lv.text = S_LEVEL % int(_dragon.get("level", 1))
	_bm_style(lv, 22, Color.WHITE)
	lv.size = Vector2(lv.get_minimum_size().x, 28.0)
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.position = _p(Vector2(lx + 20.0, DRAGON_POS.y + 15.0)) - Vector2(0.0, lv.size.y)
	_win.add_child(lv)

	var nm := Label.new()
	nm.text = Icons.name_of(_dragon)
	nm.add_theme_font_size_override("font_size", 28)
	nm.add_theme_color_override("font_color", BODY_COLOR)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.size = Vector2(nm.get_minimum_size().x, 34.0)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.position = _p(Vector2(lx + 23.0, DRAGON_POS.y - 3.0))
	_win.add_child(nm)

	var rt := Label.new()
	rt.text = "%.1f" % _grade()
	_bm_style(rt, int(round(30.0 * RATING_SCALE)), Color(1.0, 0.84, 0.35), "font_title")
	rt.size = Vector2(90.0, 32.0)
	rt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var rx := lx + 23.0 + nm.size.x + 15.0
	if nm.size.x < lv.size.x:
		rx = lx + 20.0 + lv.size.x + 15.0
	rt.position = _p(Vector2(rx, DRAGON_POS.y + 2.0)) - Vector2(0.0, rt.size.y * 0.5)
	_win.add_child(rt)

func _dragon_portrait(scale: float) -> Sprite2D:
	var art := Icons.art_id_of(_dragon)
	var frame := "dragon_dragon_%d_box_%s" % [art, Growth.portrait_stage(_dragon)]
	return AtlasUI.spr("portrait_%d" % art, frame, scale)

func _grade() -> float:
	return Growth.compute_grade(Data.get_dragon(int(_dragon.get("id", 0))), Data.stat_table,
		_dragon.get("stat_bonus", {}), _dragon.get("gain_log", []),
		Data.level_curve.get("grade", {}))

func _build_body() -> void:
	var cy := 130.0 if _kind == "ascension" else 140.0
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = Vector2(WIN.x - 60.0, 88.0)
	box.position = _p(Vector2(WIN.x * 0.5, cy)) - box.size * 0.5
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	_win.add_child(box)
	var main := Label.new()
	match _kind:
		"gem": main.text = S_GEM
		"ascension": main.text = Data.ui(S_ASCENSION)
		_: main.text = S_SKILL
	_bm_style(main, 20, BODY_COLOR, "font_common")
	main.add_theme_constant_override("line_spacing", -3)
	main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(main)
	if _kind == "gem":
		var warn := Label.new()
		warn.text = S_GEM_WARN
		_bm_style(warn, 20, WARN_COLOR, "font_common")
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(warn)
	elif _kind == "ascension" and _bind_count > 0:
		var bw := Label.new()
		bw.text = S_BIND_WARN % _bind_count
		_bm_style(bw, 20, WARN_COLOR, "font_common")
		bw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(bw)

func _build_buttons() -> void:
	var c := _p(Vector2(WIN.x * 0.5, 68.0))
	AtlasUI.frame_button(_win, "확인", c + Vector2(-120.0, 0) - BTN_SIZE * 0.5, BTN_SIZE,
		_confirm, 0, false, 24)
	AtlasUI.frame_button(_win, "취소", c + Vector2(120.0, 0) - BTN_SIZE * 0.5, BTN_SIZE,
		_close, 0, false, 24)

func _confirm() -> void:
	var cb := _on_confirm
	Bgm.sfx("effect_button")
	_close()
	if cb.is_valid():
		cb.call()

func _close() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

func _item_def() -> Dictionary:
	return Data.get_item(_item_key)

func _item_name() -> String:
	return String(_item_def().get("name", _item_key))

func _item_icon(target: float) -> Sprite2D:
	var path := String(_item_def().get("icon", ""))
	var slash := path.find("/")
	if slash < 0:
		return null
	var dir := path.substr(0, slash)
	var frame := path.substr(slash + 1)
	var man := AtlasUI.manifest(dir)
	var w: float = maxf(1.0, float((man.get(frame, {}) as Dictionary).get("w", target)))
	return AtlasUI.spr(dir, frame, target / w)

static var _bmfonts: Dictionary = {}
func _bmfont(name: String) -> FontFile:
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

func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
