extends Control
## 프롤로그 — 원작 `<PrologueTalk0~33>` 34줄 + `scenario/prologue/` 삽화. render 층(§8).
##
## ## 원작 근거
##
## · 대사 = `DV2/string/stringsData_KR.xml` 의 `<PrologueTalk%d>` — **34줄 전량 실재**.
##   0="꿈이였나??" · 1~9 누리/즈믄 소개 · 10~13 알 고르기 · 14~19 동굴/부화 ·
##   20~33 마을 습격(포포 등장).
## · 배경 = `scenario/prologue/prologue_1.jpg` (`AdventureScene::setBackground` @00c38358 이
##   `CCSprite::create("scenario/prologue/prologue_1.jpg")` + 앵커(0.5, 0.0) 로 깐다).
## · 오버레이 = `scenario/prologue/prologue_img/{add_houses,add_human,add_line1,add_line2,
##   add_monster}.png` — 같은 함수가 배경 위에 얹는다.
## · 재잘거리는 재 파티클(`particle/scene/intro/ash.plist`) 4개도 같은 함수에 있으나
##   여기서는 생략한다(⚪ 미이식 — 파티클 변환 파이프라인 별건).
##
## ⚠️ **오버레이가 어느 대사에서 켜지는지는 원작 코드에 없다**(그 분기는 `ScenarioLayer` 의
##   프롤로그 경로에 있고 우리 덤프의 디컴프 범위 밖). 그래서 여기서는 **원작이 만드는 순서대로**
##   배경 위에 전부 깔되, 몬스터 습격 대사(20번)부터 `add_monster` 를 띄우는 것만
##   문면 근거로 켠다(ASSUMPTION — 문구 "마을 사람들이 공격받고 있어!" 와 프레임 이름 일치).
##
## 진입: `Scenes.goto("prologue", {"back": "<끝나고 갈 씬>"})`

const BOX_H := 150.0
const DIR := "res://assets/converted/prologue_ui"
const ARROW := "res://assets/converted/common_ui/common_btn_arrow2.tres"
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const CPS := 40.0
## 몬스터 오버레이를 켜는 대사 번호(ASSUMPTION — 위 주석).
const MONSTER_FROM := 20

var _params: Dictionary = {}
var _lines: Array[String] = []
var _idx := 0
var _label: Label
var _arrow: Sprite2D
var _typing := false
var _timer: Timer
var _monster: Sprite2D
var _pma: CanvasItemMaterial


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
	_idx = 0
	_lines = Data.prologue_lines()
	_build_scene()
	_build_textbox()
	if _lines.is_empty():
		_show_text("(프롤로그 대사가 없습니다 — build_scenario.py 실행)")
	else:
		_show_line(0)


## 배경 리소스 크기(원작 `prologue_1.jpg` 실측) / 오버레이 캔버스(plist sourceSize).
## 오버레이는 배경의 **절반 규격**으로 저작돼 있어 2배로 얹어야 겹친다.
const BG_SIZE := Vector2(768.0, 519.0)
const OVL_CANVAS := Vector2(384.0, 260.0)

var _stage: Node2D           # 배경 + 오버레이를 함께 담아 화면에 맞춰 확대하는 무대

## 원작 `AdventureScene::setBackground` @00c38358 의 프롤로그 분기 —
## `CCSprite::create("scenario/prologue/prologue_1.jpg")` 앵커(0.5, 0.0) 위에
## `prologue_img/*` 오버레이를 얹는다. 오버레이 좌표는 plist 의 offset/sourceSize 가 정한다.
func _build_scene() -> void:
	var vis := _vis()
	var back := ColorRect.new()
	back.color = Color(0.03, 0.02, 0.05)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_stage = Node2D.new()
	# 화면을 덮도록 확대(원작 배경도 화면을 채운다). 종횡비 유지.
	var k := maxf(vis.x / BG_SIZE.x, vis.y / BG_SIZE.y)
	_stage.scale = Vector2(k, k)
	_stage.position = (vis - BG_SIZE * k) * 0.5
	add_child(_stage)
	var bgp := "%s/prologue_1.jpg" % DIR
	if ResourceLoader.exists(bgp):
		var s := Sprite2D.new()
		s.texture = load(bgp)
		s.centered = false
		_stage.add_child(s)
	# 원작이 만드는 순서(houses → line1 → line2 → human → monster).
	for key in ["add_houses", "add_line1", "add_line2", "add_human"]:
		_overlay(key)
	_monster = _overlay("add_monster")
	if _monster != null:
		_monster.visible = false


## 오버레이 한 장. plist 의 `offset`/`sourceSize` 로 캔버스 안 위치를 되살린다
## (Cocos 는 트림된 프레임을 sourceSize 중앙에 놓고 offset 만큼 민다 — y 는 위가 +).
func _overlay(key: String) -> Sprite2D:
	var p := "%s/scenario_prologue_prologue_img_%s.tres" % [DIR, key]
	if not ResourceLoader.exists(p) or _stage == null:
		return null
	var man := _man()
	var mk := "scenario_prologue_prologue_img_%s" % key
	var info: Dictionary = man.get(mk, {})
	var tex := load(p)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.centered = false
	var scale := BG_SIZE.x / OVL_CANVAS.x        # 오버레이 캔버스 → 배경 좌표(=2배)
	s.scale = Vector2(scale, scale)
	var w := float(info.get("w", tex.get_size().x))
	var h := float(info.get("h", tex.get_size().y))
	var off: Array = info.get("off", [0, 0])
	var ox := (OVL_CANVAS.x - w) * 0.5 + float(off[0])
	var oy := (OVL_CANVAS.y - h) * 0.5 - float(off[1])
	s.position = Vector2(ox, oy) * scale
	s.z_index = 1
	_stage.add_child(s)
	return s


func _man() -> Dictionary:
	var f := FileAccess.open("%s/_manifest.json" % DIR, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


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
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(20.0, 20.0)
	_label.size = Vector2(box.size.x - 75.0, BOX_H - 34.0)
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


func _show_line(i: int) -> void:
	_idx = i
	if _monster != null:
		_monster.visible = i >= MONSTER_FROM
	_show_text(_lines[i])


func _show_text(text: String) -> void:
	_label.text = text
	_label.visible_characters = 0
	_typing = true
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
	if is_instance_valid(_timer): _timer.stop()
	if _arrow:
		_arrow.visible = true
		var t := _arrow.create_tween().set_loops()
		t.tween_property(_arrow, "position:y", BOX_H * 0.5 + 6.0, 0.4)
		t.tween_property(_arrow, "position:y", BOX_H * 0.5, 0.4)


func _advance() -> void:
	if _typing:
		_reveal_all()
		return
	if _lines.is_empty() or _idx + 1 >= _lines.size():
		UserDB.set_progress("prologue_seen", true)
		Scenes.goto(String(_params.get("back", "worldmap")), _params.get("back_params", {}))
		return
	_show_line(_idx + 1)


func _vis() -> Vector2:
	return get_viewport_rect().size
