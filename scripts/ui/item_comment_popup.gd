class_name ItemCommentPopup
extends Control
## 원작 `ItemCommentPopup` — 가방에서 아이템을 쓰기 전에 뜨는 **아이템 사용 확인창**. render 층(§8.1).
##
## 원작은 이 한 클래스가 여러 아이템 분기를 갖는다(`setItem` 의 번호 switch):
##   0x192 레벨다운 · 0x193 승천 · **0x1b1 젬 슬롯 변경** · **0x1b2 스킬 슬롯 변경** ·
##   0x1b8 드래곤볼 스카우터 · 0x1bd 장신구 옵션 초기화.
## 여기서는 **슬롯 재추첨 두 종(0x1b1/0x1b2)만** 이식한다 — 나머지 아이템은 종전 경로를 그대로 쓴다.
##
## 근거·좌표는 `docs/ref/porting/SlotResetScreens.md` §1 표 그대로.
## 좌표 규약: 원작 리터럴은 창 로컬 cocos(y-up, 창 좌하단 원점) **포인트**다(§9 — ASSET_SCALE 을
## 다시 곱하지 않는다). `_p()` 가 y 만 뒤집는다.

## `init`: `9patch/popup4` capInsets `CCRect(130,190,40,58)` + `setContentSpriteSize(590,520)`.
const WIN := Vector2(590.0, 520.0)
const WIN_CAP := Rect2(130, 190, 40, 58)
const BTN_SIZE := Vector2(220.0, 56.0)
## `PopupLayer::show(..., 127.0)`.
const DIM_ALPHA := 127.0 / 255.0

## 후광 `common/backlight3` setScale(0.35) + 아이템 아이콘이 함께 놓이는 자리.
const ICON_POS := Vector2(160.0, 370.0)
const BACKLIGHT_SCALE := 0.35

const GEM_CAP := Rect2(20, 20, 2, 2)
const GEM_BOX := Vector2(70.0, 70.0)
const GEM_FRAME := {"ATT": "9patch_gem_red_bg", "DEF": "9patch_gem_blue_bg",
	"HP": "9patch_gem_yellow_bg", "ALL": "9patch_gem_white_bg"}
const SKILL_FRAME := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
	"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}

## 원작 문자열(`DV2/string/stringsData_KR.xml`).
const S_TITLE := "아이템 사용"                                          # <CaveBagItem>
const S_GEM := "현재의 잼 슬롯이 랜덤으로 변경 됩니다.\n사용하시겠습니까?"    # <CaveBagMsg19>
const S_SKILL := "현재의 스킬 슬롯이 랜덤으로 변경 됩니다.\n사용하시겠습니까?" # <CaveBagMsg20>
const S_GEM_WARN := "* 착용 중인 잼은 모두 파괴됩니다."                    # <CaveBagMsg21> {#002940:…}
const WARN_COLOR := Color8(0x00, 0x29, 0x40)
## 본문 색 — 원작 `setColor(ccColor3B{0x2a,0x18,0x00})`.
const BODY_COLOR := Color8(0x2a, 0x18, 0x00)

## `kind` = "gem"(0x1b1) | "skill"(0x1b2). `d` = 대상 드래곤 레코드(원작 `getDragonSelected`).
static func open_slot_reset(host: Node, kind: String, d: Dictionary, item_key: String,
		on_confirm: Callable) -> ItemCommentPopup:
	# 동굴의 가방 오버레이가 CanvasLayer(10)·대상선택 모달이 (20)이라 z_index 로는 못 이긴다 →
	# 자기 CanvasLayer 를 갖는다(PopupType 과 같은 방식).
	var lay := CanvasLayer.new()
	lay.layer = 70
	host.add_child(lay)
	var p := ItemCommentPopup.new()
	p._kind = kind
	p._dragon = d
	p._item_key = item_key
	p._on_confirm = on_confirm
	p._layer = lay
	lay.add_child(p)
	return p

var _kind := "gem"
var _dragon: Dictionary = {}
var _item_key := ""
var _on_confirm := Callable()
var _win: Control
var _dim: ColorRect
var _layer: CanvasLayer

func _ready() -> void:
	_build()

## 창 로컬 cocos → 창 로컬 Godot.
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
	# PopupLayer::show 의 팝 연출 — CCScaleTo(0.1,1.2) → CCScaleTo(0.1,1.0)
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

## 제목바 `9patch/pop_title_bg` size (창폭×0.9, 프레임높이), pos (창폭/2, 창높이−50).
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
	l.text = S_TITLE
	_bm_style(l, 31, Color.WHITE)                 # font_subtitle scale 1.2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(tw_pt, th)
	l.position = c - l.size * 0.5
	_win.add_child(l)

## 닫기 `common/close_btn` scale 1.5 at (창폭−50, 창높이−50).
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

## 후광 + 아이템 아이콘 + 이름(원작 `initWidget` 후광 · `setItem` 아이콘/이름).
func _build_item_row() -> void:
	var pos := _p(ICON_POS)
	var bl := AtlasUI.spr("common_ui", "common_backlight3", Design.ASSET_SCALE * BACKLIGHT_SCALE)
	var blw := AtlasUI.size_pt("common_ui", "common_backlight3").x * BACKLIGHT_SCALE
	if bl != null:
		bl.position = pos
		_win.add_child(bl)
		# 원작 후광은 회전하지 않는다(ItemCommentPopup 에는 runAction 이 없다).
	var icon := _item_icon(96.0)
	if icon != null:
		icon.position = pos
		_win.add_child(icon)
	var l := Label.new()
	l.text = _item_name()
	_bm_style(l, 26, Color.WHITE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(WIN.x - (ICON_POS.x + blw * 0.5 + 20.0) - 20.0, 44.0)
	# anchor(0, 0.5) → 왼쪽 정렬, 세로 중앙.
	l.position = Vector2(ICON_POS.x + blw * 0.5 + 20.0, pos.y - 22.0)
	_win.add_child(l)

## 구분선 `scene/worldmap/certificate_popup_line` at (창폭/2, 창높이/2 + 30).
func _build_divider() -> void:
	var s := AtlasUI.spr("worldmap_ui", "scene_worldmap_certificate_popup_line", Design.ASSET_SCALE)
	if s == null:
		return
	s.position = _p(Vector2(WIN.x * 0.5, WIN.y * 0.5 + 30.0))
	_win.add_child(s)

## `setGemReset` / `setSkillReset` — **현재** 슬롯 미리보기.
func _build_slot_preview() -> void:
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

## 본문(`setDetailString`) — font_common, 가운데 정렬, (창폭/2, 140).
## 젬은 `CaveBagMsg19 + "\n" + CaveBagMsg21`, 스킬은 `CaveBagMsg20` 한 줄
## (원작 `BagPopup.c:16539` 의 `iVar6 == 0x1b1` 분기).
func _build_body() -> void:
	# 원작은 라벨 **중심**이 (창폭/2, 140) 이다. 우리 한글 보강 비트맵은 원작보다 행이 높아
	# 그대로 두면 마지막 줄이 버튼(중심 y=68, 높이 56 → 위쪽 96)을 침범한다 → 참조 영상의
	# 행 간격(≈26pt)에 맞춰 크기·행간을 줄인다.
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = Vector2(WIN.x - 60.0, 88.0)
	box.position = _p(Vector2(WIN.x * 0.5, 140.0)) - box.size * 0.5
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	_win.add_child(box)
	var main := Label.new()
	main.text = S_GEM if _kind == "gem" else S_SKILL
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

## 확인(tag 0) / 취소(tag 1) — `RoundedButton(220×56)` 을 메뉴 (창폭/2, 68) 안에서 ∓120.
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

# ---------- 소품 ----------

func _item_def() -> Dictionary:
	return Data.get_item(_item_key)

func _item_name() -> String:
	return String(_item_def().get("name", _item_key))

## 원작 `Item::getImagePath()` — 큰 아이콘(`item/etc/<key>.png`).
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
