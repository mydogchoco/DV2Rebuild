class_name PopupType
extends RefCounted
## 원작 `PopupTypeLayer` 1:1 — 범용 확인/메시지 다이얼로그. render 층(§8.1).
##
## 근거: `docs/ref/orig_code/decomp/PopupTypeLayer.c`
##   · 창 `9patch/popup4` + 제목바 `9patch/pop_title_bg` + `common/close_btn`
##   · `onClickLeft`(취소) / `onClickRight`(확인) / `onClickClose`
##   · `setConfirmListener` / `setCancelListener` / `getStringLine`(메시지)
##   · `setCash(type, n, bool)` @011ff8e0 — 확인 쪽에 재화 아이콘 + `"X %d"` 라벨.
##       type 0 = `common/diamond_small1.png` · 1 = `common/coin_small1.png` ·
##       2 = 아이템 아이콘 · 600 = `scene/season/icon_shop_strategy.png` (:3444 switch)
##     마지막 bool(`this+0x3c2`)은 재화 노드를 -80 옮기고 짝 노드를 켜는 **배치 변형**이라
##     의미가 없다 → 미반영(원작 호출부도 전부 `false`).
##
## `cancel_text == ""` = **안내 전용 1버튼** 모드. 원작도 `setCancelListener` 를 부르지 않으면
## 취소 버튼(`this+0x390`)과 짝(`0x388`)을 `setVisible(false)` 하고 확인을 창 중앙으로 옮긴다
## (`showCostItem` @01200200 분기).
##
## 🔴 2026-07-30: `cave.gd::_open_popup_type` 에만 있던 것을 여기로 올렸다 —
##    월드맵의 행동불능/허기 팝업이 같은 물건을 필요로 했다(원작도 한 클래스다).

const BW := 460.0
const BH := 300.0

## 팝업을 띄운다. 반환 = 만들어진 CanvasLayer(호출부가 미리 닫을 수 있게).
## cash_type < 0 이면 재화 표시 없음. cash_n = 소모량.
##
## `on_cancel` = **확인을 고르지 않고 닫힌** 모든 경로에서 1회 호출된다(취소 버튼 · X 버튼).
## 원작에도 `setCancelListener`(onClickLeft)가 있다. 닫기(X)까지 묶은 것은 "안 고르고 나가면"
## 이라는 호출부 요구 때문이다 — 젬 복구창이 그렇다(고르지 않고 나가면 젬이 소멸한다).
static func open(parent: Node, title: String, msg: String, on_confirm: Callable,
		confirm_text := "확인", cancel_text := "취소",
		cash_type := -1, cash_n := 0, on_cancel := Callable()) -> CanvasLayer:
	var vis: Vector2 = parent.get_viewport_rect().size
	var layer := CanvasLayer.new(); layer.layer = 70
	parent.add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12)
	win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 26)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	# 확인 외의 경로로 닫힐 때 딱 한 번만 부른다(취소·X 가 겹쳐 두 번 불리면 안 된다).
	var done := [false]
	var bail := func():
		if done[0]:
			return
		done[0] = true
		layer.queue_free()
		if on_cancel.is_valid():
			on_cancel.call()
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14)
	xb.pressed.connect(bail)
	win.add_child(xb)
	var ml := Label.new(); ml.text = msg
	ml.add_theme_font_size_override("font_size", 21)
	ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.position = Vector2(40, 84); ml.size = Vector2(BW - 80, 104)
	win.add_child(ml)
	# 재화 줄(setCash) — 원작은 확인 버튼 옆 컨테이너(`this+0x3a0`)에 아이콘 anchor(0,0.5) +
	# `"X %d"` 라벨을 넣는다. 컨테이너의 최종 좌표는 디컴프(@01201400~)에서 버튼 크기로
	# 계산돼 복원이 어려워, **버튼 줄 바로 위 중앙**에 같은 구성으로 놓는다.
	if cash_type >= 0:
		_add_cash_row(win, cash_type, cash_n)
	# 좌(취소, onClickLeft) / 우(확인, onClickRight). cancel_text 가 비면 확인 하나를 중앙에.
	var rb := Button.new(); rb.text = confirm_text; rb.size = Vector2(160, 46)
	if cancel_text == "":
		rb.position = Vector2(BW * 0.5 - 80, BH - 66)
	else:
		rb.position = Vector2(BW * 0.5 + 14, BH - 66)
		var lb := Button.new(); lb.text = cancel_text; lb.size = Vector2(160, 46)
		lb.position = Vector2(BW * 0.5 - 174, BH - 66)
		lb.pressed.connect(bail)
		win.add_child(lb)
	rb.pressed.connect(func():
		if done[0]:
			return
		done[0] = true            # 확인을 골랐으니 취소 콜백은 돌지 않는다
		layer.queue_free()
		on_confirm.call())
	win.add_child(rb)
	return layer

## `setCash` 의 아이콘 + "X %d". type→프레임은 원작 switch(PopupTypeLayer.c:3444) 그대로.
static func _add_cash_row(win: NinePatchRect, cash_type: int, n: int) -> void:
	var key := ""
	match cash_type:
		0: key = "common_diamond_small1"
		1: key = "common_coin_small1"
		_: key = "common_diamond_small1"   # 아이템(2)·시즌(600)은 우리 호출부에 없다
	var row := Control.new()
	row.size = Vector2(BW, 30.0)
	row.position = Vector2(0, BH - 104)
	win.add_child(row)
	var icon := AtlasUI.spr("common_ui", key, 1.0)
	var iw := 0.0
	if icon:
		iw = AtlasUI.size_pt("common_ui", key).x
	var lbl := Label.new()
	lbl.text = "X %d" % n
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(70.0, 30.0)
	# 아이콘 anchor(0,0.5) + 그 오른쪽에 라벨 — 둘을 합쳐 가운데 정렬.
	var total := iw + 6.0 + 46.0
	var x0 := BW * 0.5 - total * 0.5
	if icon:
		icon.position = Vector2(x0 + iw * 0.5, 15.0)
		row.add_child(icon)
	lbl.position = Vector2(x0 + iw + 6.0, 0)
	row.add_child(lbl)
