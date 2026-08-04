# NpcTalkLayer — 원작 `cocos2d::NpcTalkLayer` 이식. render 계층(§8.1).
#
# 원작 구성(`NpcTalkLayer::initWidget` @011e389c):
#   ① `common.img_plist` + `9patch.img_plist` 로드
#   ② 전체화면 `CCLayerColor`(**opacity 0**) — 보이는 딤이 아니라 **터치 차단 + NPC 컨테이너**다.
#      자식 tag 100/0x65/0x66 = 좌/중/우 화자 슬롯.
#   ③ `ScenarioTextBox::create(left, center, right, bool)` — 하단 대사창(우리 `story.gd` 와 같은 것)
#
# 화자 슬롯은 `NpcTalkLayer::setTalker` 의 `param_10`(= `NpcPosition`)로 갈린다:
#   **1 = LEFT**(tag 100 → this+0x198) · **2 = CENTER**(0x65 → +0x1a0) · **3 = RIGHT**(0x66 → +0x1a8)
#   (`ScenarioTextBox::create(left, center, right, …)` 인자 순서와 일치)
#
# 등장(`setIncomeAction` @011e64ac): 화자·대사창 모두 `CCDelayTime(0.45)` → `CCMoveBy(0.45)`
#   + `CCEaseBackOut`. 대사창은 `ScenarioTextBox::setPreventTouch` 로 입력을 막는다.
#
# 얼굴 파츠는 원작 `NpcManager`(`getNpcBodySprite`/`setNpcEye`/`setNpcMouse`/양팔)이고
# 우리는 공용 컴포넌트 `NpcPortrait` 가 이미 그것이다 — 눈 깜빡임 파라미터도 일치한다:
#   `TalkNpc::create(…, float 0.1, float 3.0, float 0.03, float 0.03)`
#   ↔ `NpcPortrait.EYE_FAST 0.1 · EYE_HOLD 3.0 · MOUTH_STEP 0.03`
#
# ⚠️ ASSUMPTION — `CCMoveBy` 의 **이동량**은 `VisibleRect` 에서 계산돼 디컴프에 상수로 안 나온다.
#    아래 `IN_DY`(화자)·`BOX_DY`(대사창)는 화면 밖에서 올라오는 값으로 잡았다.
extends CanvasLayer
class_name NpcTalkLayer

const BOX_H := 150.0                                    # 원작 contentSize(visW-20, 150)
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const ARROW := "res://assets/converted/common_ui/common_btn_arrow2.tres"
## 원작 setIncomeAction — 지연 0.45 후 0.45초 이동.
const IN_DELAY := 0.45
const IN_TIME := 0.45
const IN_DY := 120.0        # ASSUMPTION: 화자가 아래에서 솟는 거리
const BOX_DY := 170.0       # ASSUMPTION: 대사창이 화면 밖에서 올라오는 거리
## 타자기 속도 — `story.gd` 와 같은 값(원작 `setTextSpeed` 는 코스메틱 설정, 정확값 미확정).
const CPS := 40.0

## 대사가 다 나오고 사용자가 한 번 더 눌렀을 때.
signal advanced()
## 선택지를 골랐을 때(0 = 첫 번째).
signal chosen(index: int)

var _pma: CanvasItemMaterial
var _box: NinePatchRect
var _name: Label
var _label: Label
var _arrow: Sprite2D
var _arrow_tween: Tween
var _portrait: Node2D
var _choice_row: Control
var _full := ""
var _shown := 0.0
var _typing := false

## host 위에 대화 레이어를 띄운다. `npc_id` 는 `data/npc_face.json` 의 NPC 키.
static func open(host: Node, npc_id: String, who: String, text: String,
		emotion := 1, body := 1) -> NpcTalkLayer:
	var l := NpcTalkLayer.new()
	l.layer = 26
	host.add_child(l)
	l._build(npc_id, who, text, emotion, body)
	return l

func _build(npc_id: String, who: String, text: String, emotion: int, body: int) -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var vis := _vis()

	# ② 전체화면 터치 차단(원작 CCLayerColor opacity 0 — 보이는 딤이 아니다)
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_tap())
	add_child(blocker)

	# 화자 — 원작 NpcPosition **2 = CENTER**.
	# 🔴 발밑은 **화면 바닥**이다(상점·점술집의 NpcPortrait 배치와 같다). 대사창 위
	#    (vis.y − BOX_H)에 올리면 초상이 그만큼 밀려 **머리가 화면 밖으로 잘린다**
	#    (2026-07-31 스크린샷 검수). 원작도 ScenarioTextBox 가 전폭이라 하반신을 덮는 구성이다.
	var p := NpcPortrait.create(npc_id, maxi(emotion, 1), body)
	if p != null:
		_portrait = p
		p.position = Vector2(vis.x * 0.5, vis.y + IN_DY)
		p.modulate.a = 0.0
		add_child(p)
		var pt := p.create_tween()
		pt.tween_interval(IN_DELAY)
		pt.tween_property(p, "modulate:a", 1.0, 0.15)
		pt.parallel().tween_property(p, "position:y", vis.y, IN_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ③ ScenarioTextBox — story.gd 와 같은 원작 레이아웃
	var box := NinePatchRect.new()
	box.texture = load(DIALOG_BOX)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 20.0, BOX_H)
	box.position = Vector2(10.0, vis.y - BOX_H + BOX_DY)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_box = box
	var bt := box.create_tween()
	bt.tween_interval(IN_DELAY)
	bt.tween_property(box, "position:y", vis.y - BOX_H, IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 화자 이름 — 원작 앵커(0,0.5) @ (20, 130) = 박스 위쪽
	_name = Label.new()
	_name.text = who
	_name.add_theme_font_size_override("font_size", 22)
	_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_name.position = Vector2(20.0, 8.0)
	_name.size = Vector2(box.size.x - 90.0, 28.0)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name)

	# 본문 — 원작 24pt, 앵커(0,0.5) @ (20, h*0.5−10), dimensions(w−75)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(20.0, 38.0)
	_label.size = Vector2(box.size.x - 75.0, BOX_H - 46.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)

	# 다음 화살표 — 원작 `common/btn_arrow2` @ (w−35, h*0.5)
	if ResourceLoader.exists(ARROW):
		_arrow = Sprite2D.new()
		_arrow.texture = load(ARROW)
		_arrow.material = _pma
		_arrow.position = Vector2(box.size.x - 35.0, BOX_H * 0.5)
		_arrow.visible = false
		box.add_child(_arrow)

	set_text(text)

## 대사 교체(원작 `setTalk`). 타자기를 처음부터 다시 돌린다.
func set_text(text: String) -> void:
	_full = text
	_shown = 0.0
	_typing = true
	_label.text = ""
	_stop_arrow_tween()
	if _arrow != null:
		_arrow.visible = false

func set_speaker(who: String) -> void:
	if _name != null:
		_name.text = who

## 선택지(원작 Yes/No 리스너 자리). 대사창 **위**에 얹는다.
## ⚠️ 원작이 이 버튼을 어떤 프레임으로 그렸는지는 못 찾았다(`NpcTalkLayer` 에 프레임 리터럴 0,
##    `TalkNpc` 는 디컴프 없음) — 코드로 그리는 둥근 버튼으로 낸다.
func set_choices(labels: Array) -> void:
	clear_choices()
	var vis := _vis()
	_choice_row = Control.new()
	_choice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_choice_row)
	var n := labels.size()
	var w := 200.0
	var gap := 28.0
	var total := n * w + (n - 1) * gap
	var y := vis.y - BOX_H - 40.0
	for i in n:
		var b := _button(String(labels[i]))
		b.size = Vector2(w, 52.0)
		b.position = Vector2(vis.x * 0.5 - total * 0.5 + i * (w + gap), y - 26.0)
		var idx := i
		b.pressed.connect(func(): chosen.emit(idx))
		_choice_row.add_child(b)

func clear_choices() -> void:
	if _choice_row != null and is_instance_valid(_choice_row):
		_choice_row.queue_free()
	_choice_row = null

func close() -> void:
	queue_free()

func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * CPS
	var n := mini(int(_shown), _full.length())
	_label.text = _full.substr(0, n)
	if n >= _full.length():
		_typing = false
		if _arrow != null:
			_stop_arrow_tween()
			_arrow.visible = true
			_arrow_tween = _arrow.create_tween().set_loops()
			_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5 + 6.0, 0.4).set_trans(Tween.TRANS_SINE)
			_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5, 0.4).set_trans(Tween.TRANS_SINE)

func _stop_arrow_tween() -> void:
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = null
	if is_instance_valid(_arrow):
		_arrow.position.y = BOX_H * 0.5

## 탭 — 원작 `ScenarioTextBox::ccTouchBegan`: 타이핑 중이면 전체 표시, 끝났으면 다음.
func _tap() -> void:
	if _typing:
		_typing = false
		_label.text = _full
		if _arrow != null:
			_stop_arrow_tween()
			_arrow.visible = true
		return
	if _choice_row != null and is_instance_valid(_choice_row):
		return          # 선택지가 떠 있으면 탭으로 넘기지 않는다
	advanced.emit()

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.36, 0.22, 0.09)
		if st == "hover":
			sb.bg_color = Color(0.46, 0.30, 0.13)
		elif st == "pressed":
			sb.bg_color = Color(0.28, 0.16, 0.06)
		sb.set_corner_radius_all(26)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.86, 0.72, 0.42, 0.9)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	return b

func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size
