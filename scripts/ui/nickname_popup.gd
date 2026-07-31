# NickNamePopup — 유저 닉네임 입력/변경 팝업 (render 계층, §8.1)
#
# 원작 1:1 이식. 포팅 카드 = `docs/ref/porting/NickNameLayer.md`.
#   · 클래스   `cocos2d::NickNameLayer` (`docs/ref/orig_code/decomp/NickNameLayer.c`)
#   · 진입     `NickNameLayer::create(bool)` — bool = **최초설정 여부**.
#              최초설정이면 취소 버튼이 숨겨져 닫을 수 없다(`initWidget` 이 취소를 setVisible(0) 로 만든다).
#   · 호출자   `BagPopup.c:7243` — '닉네임 변경' 아이템 사용 시 `create(false)`.
#   · 확정     `onClickOk` → Request/ResponseNickName → `User::setNickName`
#              (서버 왕복은 §2-1로 컷 — 로컬 즉시 반영)
#
# 레이아웃(initWidget @013b0968). 좌표는 **원작 소스의 디자인 포인트 리터럴**이라
# §9-2에 따라 ASSET_SCALE 을 다시 곱하지 않는다. 배경 650×420 로컬 좌표(cocos y-up):
#   제목바 `9patch/pop_title_bg` 폭 w*0.9 @(w*0.5, h-50)
#   안내   @(w*0.5, h*0.5-53)
#   입력   `9patch/text_box` insets(20,20,4,4) 400×53 @(w*0.5, h*0.5+13)
#   확인   RoundedButton(style=0 → `9patch/btn`)  220×56 @(w*0.5, 75)
#   취소   RoundedButton(style=1 → `9patch/btn2`) 220×56 @(w*0.5+120, 75)
extends RefCounted
class_name NickNamePopup

const PANEL := Vector2(650.0, 420.0)          # 원작 setContentSize(650, 420)
const BTN := Vector2(220.0, 56.0)             # 원작 RoundedButton size
const EDIT := Vector2(400.0, 53.0)            # 원작 CCEditBox size
const MAX_LEN := 12                           # ASSUMPTION: 원작 길이 제한은 서버 검증(유실). 12자로 둔다.

const _NP := "res://assets/converted/ninepatch_ui/%s.tres"

## 팝업을 parent 위에 띄운다. is_first=true 면 취소 없음(원작 create(true)).
## on_confirm(name: String) 은 확정 후 호출된다. 반환값 = 이 팝업의 CanvasLayer(수동 제거용).
static func open(parent: Node, is_first: bool, on_confirm := Callable()) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 40
	parent.add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 최초설정은 원작에서 닫을 수 없다 — 바깥 클릭도 막는다(dim 이 입력을 흡수).
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var vis: Vector2 = parent.get_viewport().get_visible_rect().size
	var win := _nine(_NP % "9patch_popup4", 130, 190, 55, 81)
	win.size = PANEL
	win.position = ((vis - PANEL) * 0.5).round()
	layer.add_child(win)

	# ── 제목 바: 폭 = 패널폭 × 0.9, cocos y = h-50 → godot y = 50 - 바높이/2
	var tw := PANEL.x * 0.9
	# 원작은 폭만 늘리고 **높이는 프레임 그대로** 쓴다(`CCSize(w*0.9, frame.height)`).
	# pop_title_bg 프레임 33px → 디자인 포인트 33 × ASSET_SCALE(4/3) = 44 (§9-1).
	var th := 33.0 * Design.ASSET_SCALE
	var tbar := _nine(_NP % "9patch_pop_title_bg", 20, 12, 20, 12)
	tbar.size = Vector2(tw, th)
	tbar.position = Vector2((PANEL.x - tw) * 0.5, 50.0 - th * 0.5)
	tbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(tbar)
	win.add_child(_label("닉네임 설정" if is_first else "닉네임 변경", 28, Color.WHITE,
		tbar.position, tbar.size))

	# ── 안내 라벨: cocos (w*0.5, h*0.5-53) → godot y = h*0.5+53
	var guide := "게임에서 사용할 닉네임을 입력하세요." if is_first else "새 닉네임을 입력하세요."
	win.add_child(_label(guide, 19, Color(0.36, 0.26, 0.12),
		Vector2(0.0, PANEL.y * 0.5 + 53.0 - 14.0), Vector2(PANEL.x, 28.0)))

	# ── 입력 박스: cocos (w*0.5, h*0.5+13) → godot y = h*0.5-13
	# capInsets CCRect(20,20,4,4) = **중앙 영역**(cocos2d-x 규약) → 프레임 40×40 기준
	# left=20 top=20 right=40-20-4=16 bottom=16.
	var box := _nine(_NP % "9patch_text_box", 20, 20, 16, 16)
	box.size = EDIT
	box.position = Vector2((PANEL.x - EDIT.x) * 0.5, PANEL.y * 0.5 - 13.0 - EDIT.y * 0.5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(box)

	var edit := LineEdit.new()
	edit.max_length = MAX_LEN
	edit.text = "" if is_first else UserDB.user_nickname()
	edit.placeholder_text = "%d자 이내" % MAX_LEN
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.flat = true
	edit.size = EDIT - Vector2(36.0, 14.0)
	edit.position = box.position + Vector2(18.0, 7.0)
	edit.add_theme_font_size_override("font_size", 24)
	edit.add_theme_color_override("font_color", Color(0.22, 0.16, 0.08))
	edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.48, 0.40))
	win.add_child(edit)

	# ── 버튼: 원작은 확인 @(w*0.5,75) / 취소 @(w*0.5+120,75). 취소가 보일 때만 확인을 -120 으로
	#    옮겨 좌우 대칭을 만든다(원작은 취소가 숨겨진 상태를 기준으로 좌표를 잡아 둔다).
	var by := PANEL.y - 75.0 - BTN.y * 0.5      # cocos y=75 → godot
	var ok_cx := PANEL.x * 0.5 + (-120.0 if not is_first else 0.0)
	var ok := _button("확인", "9patch_btn", Vector2(ok_cx - BTN.x * 0.5, by))
	win.add_child(ok)

	var cancel: Control = null
	if not is_first:
		# ⚠️ 두 버튼 다 RoundedButtonType 0 = `9patch/btn` 이다.
		#    Ghidra 의 `param_6` 번호에 속기 쉽다 — 실제 C++ 시그니처는
		#    `create(CCSize, CCObject*, void(CCObject::*)(CCObject*), RoundedButtonType, float)` 이고
		#    **멤버 함수 포인터가 2슬롯**(fn, adj)이라 인자가 한 칸 밀려 보인다.
		#    취소 호출의 `1` 은 type 이 아니라 adj(가상함수 표식)다. 2016 참조 스크린샷
		#    (docs/ref/orig_image/old_screenshots/Screenshot_2016-06-08-21-46-10.png)에서도 확인/취소가 같은 빨강이다.
		cancel = _button("취소", "9patch_btn",
			Vector2(PANEL.x * 0.5 + 120.0 - BTN.x * 0.5, by))
		win.add_child(cancel)

	# 원작 editBoxTextChanged: 타이핑마다 확정 가능 여부 갱신.
	# ⚠️ 버튼을 `disabled` 로 만들지는 **않는다** — IME 로 한 글자를 조합하는 동안 `text` 는
	#    아직 비어 있어서, 한 글자짜리 이름은 확인이 눌리지 않는 상태가 된다(위 IME 함정과 같은 뿌리).
	#    흐릿하게만 표시하고 판정은 누른 뒤 `TextField.value` 로 한다.
	var refresh := func() -> void:
		ok.modulate = Color(1, 1, 1, 1.0 if not edit.text.strip_edges().is_empty() else 0.55)
	edit.text_changed.connect(func(_t): refresh.call())
	refresh.call()

	# 🔴 한글 IME 조합 함정 — 확인을 누르는 순간 포커스가 버튼으로 넘어가며 **조합 중인
	#    마지막 글자가 취소**됐다("계란" → "계"). 처방은 `TextField` 주석 참조.
	TextField.no_steal(win)
	var confirm := func():
		var nick := TextField.value(edit)
		if nick.is_empty():
			return
		UserDB.set_user_nickname(nick)
		layer.queue_free()
		if on_confirm.is_valid():
			on_confirm.call(nick)
	(ok.get_child(0) as Button).pressed.connect(confirm)
	edit.text_submitted.connect(func(_s): confirm.call())      # 엔터로도 확정
	if cancel != null:
		(cancel.get_child(0) as Button).pressed.connect(func(): layer.queue_free())

	edit.grab_focus()
	return layer

# ---------- helpers ----------

static func _nine(path: String, l: int, t: int, r: int, b: int) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = load(path)
	n.patch_margin_left = l; n.patch_margin_top = t
	n.patch_margin_right = r; n.patch_margin_bottom = b
	return n

static func _label(text: String, size: int, color: Color, pos: Vector2, dim: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos; l.size = dim
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 원작 RoundedButton = 9-slice 배경 + BMFont 라벨. capInsets 는 전부 CCRect(20,20,4,4)
## = 중앙 4×4 → 프레임 41×42 기준 left=20 top=20 right=17 bottom=18.
## 반환 노드의 child(0) 이 실제 Button(투명) — 시그널은 거기에 연결한다.
static func _button(text: String, frame: String, pos: Vector2) -> Control:
	var bg := _nine(_NP % frame, 20, 20, 17, 18)
	bg.size = BTN
	bg.position = pos
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.flat = true
	b.text = text
	b.size = BTN
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.85, 0.85, 0.85, 0.6))
	bg.add_child(b)
	return bg
