class_name Toast
extends RefCounted
## 짧은 안내 문구 — 원작 `GameManager::showToast(const char*)` @014c193c 이식.
##
## 원작은 문구를 큐(`GameManager+0x60`)에 `{category:"TOAST", text:…}` 로 넣기만 하고,
## 소비 루틴(`docs/ref/orig_code/decomp/GameManager.c:8707~8975`)이 이렇게 그린다:
##
##     label = CCLabelBMFont::create(text, "font/font_common.fnt")
##     w = VisibleRect::right().x * 0.6
##     if (w <= label.contentSize.width): w = label.contentSize.width + 20
##     box = CCScale9Sprite::createWithSpriteFrameName("9patch/box1.png", CCRect(20,20,10,10))
##     box.setContentSize(CCSize((int)w, 60))
##     box.setPosition(VisibleRect::center())
##     box.setColor(0,0,0)                       ← 검정 틴트
##     box.setOpacity(0)
##     CCDirector::setNotificationNode(box)      ← 항상 최상단
##     label.setPosition(box.w*0.5, box.h*0.5 + 5)
##     box.addChild(label)
##     runAction(Sequence(FadeTo(0.2, 150), Delay(0.7), FadeTo(0.2, 0), CallFunc))
##
## ⇒ **반투명 검정 상자(알파 150/255, 높이 60) + `font_common` BMFont 흰 글씨, 화면 중앙.**
##
## 🔴 2026-07-29 통일. 종전에는 화면마다 자작이었다 — `worldmap.gd::_notice` 는
##    `9patch/popup4`(양피지)+갈색 TTF, `cave.gd`/`town.gd::_toast` 는 배경 없는 노란 라벨.
##    원작은 **전역 함수 하나**가 소유하는 물건이라 여기로 모았다(CLAUDE.md §3).
##
## 색/투명 분리: 원작 `setColor` 는 자식(라벨)까지 물들이지 않고 `setOpacity` 만 함께 흐려진다
## → Godot 에선 상자에 `self_modulate`(자기만), 페이드는 부모 `modulate.a`(자식까지).
##
## `showLongToast` 는 지속시간만 다른 별도 표를 쓴다(원작 `isLong` 키) → `hold` 인자로 연다.

const BOX := "res://assets/converted/ninepatch_ui/9patch_box1.tres"
const FONT := "res://assets/converted/font_ui/font_common.fnt"
const BOX_FRAME := 38.0            # 9patch/box1 프레임 크기(캡 인셋 계산용)
const H := 60.0                    # 원작 setContentSize(w, 60)
const ALPHA := 150.0 / 255.0       # 원작 FadeTo(0.2, 0x96)
const FADE_IN := 0.2
const HOLD := 0.7                  # 원작 기본값(showToast)
const FADE_OUT := 0.2
const WIDTH_RATIO := 0.6           # 원작 VisibleRect::right().x * 0.6
const TEXT_PAD := 20.0             # 원작 label.w + 20
const LAYER := 40                  # 원작 setNotificationNode = 항상 최상단

## `host` 위에 토스트를 띄운다. 같은 host 의 이전 토스트는 지운다(원작도 같은 문구는 큐에서 걸러낸다).
static func show(host: Node, text: String, hold := HOLD) -> void:
	if host == null or not is_instance_valid(host) or text == "":
		return
	for c in host.get_children():
		if c is CanvasLayer and c.name == "ToastLayer" and not c.is_queued_for_deletion():
			c.queue_free()
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	var lay := CanvasLayer.new()
	lay.name = "ToastLayer"
	lay.layer = LAYER
	host.add_child(lay)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(root)

	var l := Label.new()
	l.text = text
	var f: Font = load(FONT) if ResourceLoader.exists(FONT) else null
	if f:
		# 비트맵 폰트는 fixed_size_scale_mode 를 켜야 font_size 가 먹는다(CLAUDE.md §10).
		if f is FontFile:
			(f as FontFile).fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 원작 폭 규칙: 화면폭 60%, 글자가 더 길면 글자폭+20.
	var tw := 0.0
	var lf := l.get_theme_font("font")
	if lf:
		tw = lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			l.get_theme_font_size("font_size")).x
	var w := maxf(vis.x * WIDTH_RATIO, tw + TEXT_PAD)

	var np := NinePatchRect.new()
	np.texture = load(BOX)
	# 원작 capInsets CCRect(20,20,10,10) — 38×38 프레임의 (20,20)에서 10×10 이 중앙.
	np.patch_margin_left = 20
	np.patch_margin_top = 20
	np.patch_margin_right = int(BOX_FRAME) - 30
	np.patch_margin_bottom = int(BOX_FRAME) - 30
	np.size = Vector2(w, H)
	np.position = Vector2(round((vis.x - w) * 0.5), round((vis.y - H) * 0.5))
	np.self_modulate = Color(0, 0, 0, ALPHA)      # 검정 틴트(자식엔 안 물림)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(np)

	l.size = Vector2(w, H)
	l.position = Vector2(0, -5.0)                 # 원작 label.y = box.h*0.5 + 5 (y-up) → 위로 5
	np.add_child(l)

	root.modulate.a = 0.0
	var t := root.create_tween()
	t.tween_property(root, "modulate:a", 1.0, FADE_IN)
	t.tween_interval(hold)
	t.tween_property(root, "modulate:a", 0.0, FADE_OUT)
	t.tween_callback(lay.queue_free)
