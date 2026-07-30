class_name BottomTextBox
extends Control
## 원작 `BottomTextBox` 포팅 — 화면 하단 전폭 대사창. render 층(CLAUDE.md §8.1).
## 상점·육성·연구소·점술집이 공유한다(원작도 같은 클래스를 공유했다).
##
## 근거: docs/ref/orig_code/decomp/BottomTextBox.c :: init
##   · 배경 = `9patch/dialogue_box.png` Scale9, capInsets Rect(20,20,4,4), 앵커 (0,0)
##   · 박스 = 앵커 (0.5,0) @ (visW*0.5, bottom+10), contentSize (visW-20, 130)
##   · 이름 = **노랑** BMFont, 앵커 (0,0.5) @ (30, 110)   ← 박스 하단 기준 y-up
##   · 본문 = CCLabelBMFontEx, 폭 = boxW-60
##   · 대사는 `showString`(타이프라이터) → 클릭하면 `showStringAll`(전부 표시)
##
## 한글 BMFont 는 Godot 임포터 제약으로 못 쓴다(CLAUDE.md §10) → 서체만 TTF, 색·배치는 원작.

signal finished          ## 타이프라이터 출력이 끝났을 때
signal clicked           ## 박스를 눌렀을 때(원작 ccTouchBegan)

const BOX_H := 130.0
const BOX_MARGIN := 20.0
const BOX_BOTTOM := 10.0
const NAME_POS := Vector2(30.0, 110.0)      # 박스 로컬, Cocos y-up
const TEXT_INSET := 60.0
const CPS := 45.0                           # 타이프라이터 속도(글자/초)

## 0 이면 화면 전폭(원작 기본). 상점처럼 오른쪽에 NPC 열을 비워 두는 화면은 여기에 폭을 준다.
var max_width := 0.0

var _bg: NinePatchRect
var _name_lbl: Label
var _text_lbl: Label
var _full := ""
var _shown := 0.0
var _typing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	get_viewport().size_changed.connect(_layout)

func _build() -> void:
	_bg = NinePatchRect.new()
	_bg.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	# ⚠️ Cocos capInsets(20,20,4,4)는 **포인트**, Godot patch_margin 은 **텍스처 픽셀**.
	#    ×0.75(=1/ASSET_SCALE) 로 환산: 좌15 상15 중앙3×3 → 우 33-15-3=15, 하 15. (프레임 33×33)
	#    노드 자체는 ASSET_SCALE 로 키워 픽셀 1개가 4/3 포인트로 보이게 한다(§9).
	_bg.patch_margin_left = 15
	_bg.patch_margin_top = 15
	_bg.patch_margin_right = 15
	_bg.patch_margin_bottom = 15
	_bg.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 20)
	_name_lbl.add_theme_color_override("font_color", Color(1, 0.93, 0.25))   # 원작 ccYELLOW
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_lbl)

	_text_lbl = Label.new()
	_text_lbl.add_theme_font_size_override("font_size", 21)
	_text_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_lbl)
	_layout()

func _layout() -> void:
	var vis := get_viewport_rect().size
	var w: float = (max_width if max_width > 0.0 else vis.x) - BOX_MARGIN
	size = Vector2(w, BOX_H)
	# 폭을 제한하면 왼쪽 여백(BOX_MARGIN/2)을 유지한 채 왼쪽 정렬한다.
	var x: float = round((vis.x - w) * 0.5) if max_width <= 0.0 else BOX_MARGIN * 0.5
	position = Vector2(x, round(vis.y - BOX_H - BOX_BOTTOM))
	if _bg != null:
		_bg.size = Vector2(w, BOX_H) / Design.ASSET_SCALE
	if _name_lbl != null:
		# Cocos 앵커 (0,0.5) @ (30,110) → Godot: 박스 상단에서 (130-110)=20 아래, 세로 중앙정렬
		_name_lbl.position = Vector2(NAME_POS.x, BOX_H - NAME_POS.y - 14)
		_name_lbl.size = Vector2(w - TEXT_INSET, 28)
	if _text_lbl != null:
		_text_lbl.position = Vector2(NAME_POS.x, BOX_H - NAME_POS.y + 16)
		_text_lbl.size = Vector2(w - TEXT_INSET, BOX_H - 60)

## 원작 setString + showString — 이름(노랑)과 본문(타이프라이터).
func show_text(speaker: String, text: String, typewriter := true) -> void:
	_name_lbl.text = "[ %s ]" % speaker if speaker != "" else ""
	_full = text
	if typewriter:
		_shown = 0.0
		_typing = true
		_text_lbl.text = ""
	else:
		_typing = false
		_text_lbl.text = text
		finished.emit()

## 원작 showStringAll — 진행 중이면 즉시 전부 표시.
func show_all() -> void:
	if _typing:
		_typing = false
		_text_lbl.text = _full
		finished.emit()

func is_typing() -> bool:
	return _typing

func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * CPS
	var n := mini(int(_shown), _full.length())
	_text_lbl.text = _full.substr(0, n)
	if n >= _full.length():
		_typing = false
		finished.emit()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if _typing:
			show_all()
		else:
			clicked.emit()
		accept_event()
