# NpcTalkLayer — 원작 `cocos2d::NpcTalkLayer` 이식. render 계층(§8.1).
#
# 원작 구성(`NpcTalkLayer::initWidget` @011e389c):
#   ① `common.img_plist` + `9patch.img_plist` 로드
#   ② 전체화면 `CCLayerColor`(**opacity 0**) — 보이는 딤이 아니라 **터치 차단 + NPC 컨테이너**다.
#      자식 tag 100/0x65/0x66 = 좌/중/우 화자 슬롯.
#   ③ `ScenarioTextBox::create(left, center, right, bool)` — 하단 대사창(우리 `story.gd` 와 같은 것)
#
# 화자 슬롯은 `NpcTalkLayer::setTalker` 의 `param_10`(= `NpcPosition`)로 갈린다.
# 🔴 2026-08-06 정정 — 종전 주석의 "2 = CENTER · 3 = RIGHT" 는 **틀렸다**. 슬롯 필드는 맞지만
#   화면 어디에 놓이는지는 그 슬롯이 `NpcManager::setTarget` 에 넘기는 배치 코드가 정하고,
#   그 코드의 실제 좌표식(`setTarget` @014d5e04~, `getDefaultNpcPos` @014d89bc)은 이렇다:
#     1 → x = bodyW*0.5 + margin                (**LEFT**)   · 슬롯 +0x198(tag 100)
#     2 → x = visW − bodyW*0.5 − margin         (**RIGHT**)  · 슬롯 +0x1a0(tag 0x65)
#     3 → x = visW*0.5                          (**CENTER**) · 슬롯 +0x1a8(tag 0x66)
#   등장 방향도 이와 일치한다(1=왼쪽에서, 2=오른쪽에서, 3=아래에서 솟음).
#   ⇒ 라온은 3(가운데) 혼자, 콜로세움 누리 이벤트는 즈믄 1(왼쪽) + 누리 2(오른쪽)다.
#
# 배치 상수(`NpcManager::setTarget`):
#   · 좌우 여백 `this+0xb0` 기본 **20.0**
#   · NPC 별 y 보정: `jimon` **+100** · `amanta`/`hybrid`/`regiana_dragon` **−60**
#   · NPC 별 x 가산 `this+0xb4`: `annie` +20 · `regiana_dragon` +480
#   · **1(LEFT) 슬롯은 좌우 반전**한다(`setFlippedX(1)` + `setScaleX(-1)`).
#
# 화자 강조 — 말하는 쪽은 크게, 나머지는 작게(`setTalker` 의 `CCScaleTo` 3종).
#   `this+0x180` = 1.07(작게) · `+0x184` = 1.12(평소) · `+0x188` = 1.17(튀어오름).
#   말할 때: Delay(1/6) → ScaleTo(1/6, 1.17) → ScaleTo(0.25, 1.12), 나머지 슬롯은 ScaleTo(1/6, 1.07).
#   ⚠️ 이 1.12 는 **아틀라스 4/3 위에 곱해지는 값**이라, 종전 우리 초상(1.0배)은 원작보다 12% 작았다.
#
# 등장(`setIncomeAction` @011e64ac): 화자·대사창 모두 `CCDelayTime(0.45)` → `CCMoveBy(0.45)`.
#   대사창은 `ScenarioTextBox::setPreventTouch` 로 입력을 막는다.
# 화자 개별 등장(`setTalker` 의 `isFirstShow`): 좌/우는 `CCMoveBy(0.5)` + `CCEaseBackOut`,
#   가운데는 `CCMoveBy(1.25)` + `CCEaseExponentialInOut`(몸통 높이만큼 아래에서 솟는다).
#
# 얼굴 파츠는 원작 `NpcManager`(`getNpcBodySprite`/`setNpcEye`/`setNpcMouse`/양팔)이고
# 우리는 공용 컴포넌트 `NpcPortrait` 가 이미 그것이다 — 눈 깜빡임 파라미터도 일치한다:
#   `TalkNpc::create(…, float 0.1, float 3.0, float 0.03, float 0.03)`
#   ↔ `NpcPortrait.EYE_FAST 0.1 · EYE_HOLD 3.0 · MOUTH_STEP 0.03`
#
# `TalkNpc::create` 인자 = (npc 폴더명, 대사, **몸통**, **표정**, 위치, isFirstShow, isStartSmall, …).
# 화자 이름표는 원작이 `NpcTalkLayer::setTalk` 에서 `StringManager::getString("NPC_" + 폴더명)`
#   으로 만든다(`<NPC_nuri>누리`·`<NPC_jimon>즈믄`·`<NPC_raon>라온`) — 우리는 데이터에 실어 둔다.
#
# ⚠️ ASSUMPTION — 대사창 `CCMoveBy` 의 이동량은 `VisibleRect` 계산이라 상수로 안 나온다(`BOX_DY`).
extends CanvasLayer
class_name NpcTalkLayer

const BOX_H := 150.0                                    # 원작 contentSize(visW-20, 150)
## 대사창의 z — 원작 `initWidget` 의 `addChild(ScenarioTextBox, 1000)` 그대로.
## 화자(초상)는 기본 z 0 이라 항상 대사창 **뒤**에 깔린다.
const BOX_Z := 1000
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const ARROW := "res://assets/converted/common_ui/common_btn_arrow2.tres"
## 원작 setIncomeAction — 지연 0.45 후 0.45초 이동.
const IN_DELAY := 0.45
const IN_TIME := 0.45
const BOX_DY := 170.0       # ASSUMPTION: 대사창이 화면 밖에서 올라오는 거리
## 타자기 속도 — `story.gd` 와 같은 값(원작 `setTextSpeed` 는 코스메틱 설정, 정확값 미확정).
const CPS := 40.0

## 화자 슬롯(원작 `NpcPosition`) — 위 주석의 좌표식에서 확정.
const POS_LEFT := 1
const POS_RIGHT := 2
const POS_CENTER := 3

## 화자 크기 — 원작 NpcTalkLayer +0x180 / +0x184 / +0x188.
const SCALE_SMALL := 1.07
const SCALE_NORMAL := 1.12
const SCALE_POP := 1.17
const SCALE_UP_TIME := 0.16666667
const SCALE_SETTLE_TIME := 0.25
## 원작 `NpcManager::setTarget` — 좌우 여백 기본값(this+0xb0)과 NPC 별 보정(this+0xb4 / y).
const SIDE_MARGIN := 20.0
const NPC_Y_OFFSET := {"jimon": 100.0, "amanta": -60.0, "hybrid": -60.0, "regiana_dragon": -60.0}
const NPC_X_EXTRA := {"annie": 20.0, "regiana_dragon": 480.0}
## 화자 개별 등장 시간(setTalker isFirstShow 분기).
const SIDE_IN_TIME := 0.5
const CENTER_IN_TIME := 1.25

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
var _portrait: Node2D                  # 마지막으로 말한 화자(단일 화자 화면의 호환용 별칭)
var _slots: Dictionary = {}            # pos(int) → {"npc": String, "body": int, "node": NpcPortrait}
var _opened := false                   # 첫 화자에만 레이어 등장 지연(IN_DELAY)을 준다
var _choice_row: Control
var _full := ""
var _shown := 0.0
var _typing := false

## host 위에 대화 레이어를 띄운다. `npc_id` 는 `data/npc_face.json` 의 NPC 키.
## `pos` 는 원작 `NpcPosition`(1 왼쪽 / 2 오른쪽 / 3 가운데) — 혼자 나오는 화면은 가운데다.
static func open(host: Node, npc_id: String, who: String, text: String,
		emotion := 1, body := 1, pos := POS_CENTER) -> NpcTalkLayer:
	var l := NpcTalkLayer.new()
	l.layer = 26
	host.add_child(l)
	l._build(npc_id, who, text, emotion, body, pos)
	return l

func _build(npc_id: String, who: String, text: String, emotion: int, body: int,
		pos := POS_CENTER) -> void:
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

	# ③ ScenarioTextBox — story.gd 와 같은 원작 레이아웃
	var box := NinePatchRect.new()
	box.texture = load(DIALOG_BOX)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 20.0, BOX_H)
	box.position = Vector2(10.0, vis.y - BOX_H + BOX_DY)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 🔴 대사창은 **화자보다 위**다 — 원작 `initWidget` 이 화자 컨테이너(this+0x1b0)는 기본 z 로,
	#    `ScenarioTextBox`(this+0x178)는 **`addChild(box, 1000)`** 로 넣는다(@011e389c :353/:361).
	#    노드 순서만 믿으면 나중에 붙는 화자가 글자를 덮는다(2026-08-06 라온 대사 가림).
	#    자식(이름표·본문·▶)은 z_as_relative 기본값이라 함께 올라간다.
	box.z_index = BOX_Z
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

	# 화자 — 초상이 없는 화자(오리지널 캐릭터 등)는 대사창만 띄운다.
	# 남의 얼굴로 대체하지 않는다(CLAUDE.md §3).
	set_talker(npc_id, who, pos, emotion, body, true, false)
	set_text(text)

## 원작 `NpcTalkLayer::setTalker` — **한 줄마다** 화자·표정·몸통·자리를 갈아 끼운다.
##
## · `pos` = `NpcPosition`(1 왼쪽 / 2 오른쪽 / 3 가운데). 슬롯마다 초상 하나가 남아 있고,
##   말하지 않는 슬롯은 `SCALE_SMALL` 로 줄어든다(원작의 화자 강조).
## · `first_show` = 이 슬롯에 이 NPC 가 처음 나오는 줄 → 화면 밖에서 등장.
## · `start_small` = 방금까지 줄어 있던 화자가 다시 말하는 줄 → 작은 크기에서 튀어오른다.
## · `npc_id` 가 빈 문자열이면 초상 없이 이름표만 바꾼다.
func set_talker(npc_id: String, who: String, pos := POS_CENTER, emotion := 1, body := 1,
		first_show := true, start_small := false) -> void:
	set_speaker(who)
	if npc_id == "":
		return
	var vis := _vis()
	var slot: Dictionary = _slots.get(pos, {})
	var p: NpcPortrait = slot.get("node", null)
	var fresh := false
	# 몸통이 바뀌면 원작 `setTarget` 도 몸통 스프라이트를 다시 만든다(표정만 바뀔 땐 파츠만 교체).
	if p == null or not is_instance_valid(p) or String(slot.get("npc", "")) != npc_id \
			or int(slot.get("body", 0)) != body:
		if p != null and is_instance_valid(p):
			p.queue_free()
		p = NpcPortrait.create(npc_id, maxi(emotion, 1), maxi(body, 1))
		if p == null:
			return
		add_child(p)
		fresh = true
	else:
		p.set_emotion(maxi(emotion, 1))
	# 화자가 바뀌면 이전 화자의 입을 다물린다(원작 setStopMouse — 말하는 쪽만 입이 돈다).
	if _portrait != null and is_instance_valid(_portrait) and _portrait != p:
		_portrait.set_talking(false)
	_slots[pos] = {"npc": npc_id, "body": body, "node": p}
	_portrait = p

	# 🔴 발밑은 **화면 바닥**이다(상점·점술집의 NpcPortrait 배치와 같다). 대사창 위
	#    (vis.y − BOX_H)에 올리면 초상이 그만큼 밀려 **머리가 화면 밖으로 잘린다**
	#    (2026-07-31 스크린샷 검수). 원작도 ScenarioTextBox 가 전폭이라 하반신을 덮는 구성이다.
	var home := _slot_home(p, npc_id, pos, vis)
	var flip := -1.0 if pos == POS_LEFT else 1.0     # 원작 setTarget: 1번 자리만 좌우 반전
	if fresh:
		p.position = home
		p.scale = Vector2(flip * (SCALE_SMALL if start_small else SCALE_NORMAL),
			SCALE_SMALL if start_small else SCALE_NORMAL)
	# 말하지 않는 슬롯은 작게(원작: Delay(1/6) → ScaleTo(1/6, 1.07))
	for other_pos: int in _slots:
		if other_pos == pos:
			continue
		var o: NpcPortrait = (_slots[other_pos] as Dictionary).get("node", null)
		if o == null or not is_instance_valid(o):
			continue
		var of := signf(o.scale.x)
		var ot := o.create_tween()
		ot.tween_interval(SCALE_UP_TIME)
		ot.tween_property(o, "scale", Vector2(of * SCALE_SMALL, SCALE_SMALL), SCALE_UP_TIME)

	var t := p.create_tween()
	if fresh and first_show:
		# 등장 — 원작 좌/우는 화면 폭 절반만큼 바깥에서 BackOut, 가운데는 몸통 높이만큼 아래에서.
		var from := home
		var dur := SIDE_IN_TIME
		var trans := Tween.TRANS_BACK
		var ease := Tween.EASE_OUT
		match pos:
			POS_LEFT:
				from.x -= vis.x * 0.5
			POS_RIGHT:
				from.x += vis.x * 0.5
			_:
				from.y += p.body_height()          # 원작도 contentSize(= 배율 곱하기 전) 높이다
				dur = CENTER_IN_TIME
				trans = Tween.TRANS_EXPO
				ease = Tween.EASE_IN_OUT
		p.position = from
		if not _opened:
			t.tween_interval(IN_DELAY)
		t.tween_property(p, "position", home, dur).set_trans(trans).set_ease(ease)
	else:
		t.tween_interval(SCALE_UP_TIME)
	# 말하는 쪽 강조 — ScaleTo(1/6, 1.17) → ScaleTo(0.25, 1.12)
	t.tween_property(p, "scale", Vector2(flip * SCALE_POP, SCALE_POP), SCALE_UP_TIME)
	t.tween_property(p, "scale", Vector2(flip * SCALE_NORMAL, SCALE_NORMAL), SCALE_SETTLE_TIME)
	_opened = true

## 그 슬롯에서 초상의 발밑 좌표 — 원작 `NpcManager::setTarget` 의 좌표식 그대로.
func _slot_home(p: NpcPortrait, npc_id: String, pos: int, vis: Vector2) -> Vector2:
	var half_w: float = p.body_width() * 0.5
	var extra: float = float(NPC_X_EXTRA.get(npc_id, 0.0))
	var y: float = vis.y - float(NPC_Y_OFFSET.get(npc_id, 0.0))
	match pos:
		POS_LEFT:
			return Vector2(half_w + SIDE_MARGIN + extra, y)
		POS_RIGHT:
			return Vector2(vis.x - half_w - SIDE_MARGIN + extra, y)
	return Vector2(vis.x * 0.5, y)

## 대사 교체(원작 `setTalk`). 타자기를 처음부터 다시 돌린다.
## 타자 동안 화자의 입이 움직인다(원작 setMouseAction/setStopMouse — 상점 `shop.gd::_say` 와
## 같은 배선. 입 프레임이 없는 NPC 는 `NpcPortrait.set_talking` 이 알아서 무시한다).
func set_text(text: String) -> void:
	_full = text
	_shown = 0.0
	_typing = true
	_label.text = ""
	if _portrait != null and is_instance_valid(_portrait):
		_portrait.set_talking(true)
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
	_choice_row.z_index = BOX_Z          # 대사창과 같은 층 — 화자가 버튼을 덮으면 안 된다
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
		if _portrait != null and is_instance_valid(_portrait):
			_portrait.set_talking(false)
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
		if _portrait != null and is_instance_valid(_portrait):
			_portrait.set_talking(false)
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
