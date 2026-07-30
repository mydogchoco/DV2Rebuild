class_name EggResultPopup
extends CanvasLayer
## 드래곤 **알 획득** 공개 팝업 — render 층(CLAUDE.md §8).
##
## 원래 `cave.gd::_show_egg_result` 안에만 있던 연출을 그대로 떼어낸 것이다(2026-07-30).
## 뽑기 알(의문의 알·빛나는 의문의 알·속성알) 개봉이 쓰던 것을 **카드 코드 보상**과
## **드래곤 소환**도 같이 쓰게 하려고 공용화했다 — 배치·프레임·수치는 전부 종전 그대로다.
##
## ⚠️ 다건 획득 공개는 `GetItemPopup`(원작 `ShowGetItemDetailLayer`)이다. 이 팝업은 **알 1개**를
##    크게 보여 주는 전용 연출이고 원작 문구도 `CaveEggBronMsg7/9/13` 계열이라 별개다.
##
## 쓰는 프레임: `9patch/recall_del`(창) · `common/backlight3`(뒤 후광) · `common/eggclass`(성급) ·
##   `item/item_small/ele_*`(속성) · `common/check_btn`(확인) · `portrait_<id>/dragon_dragon_<id>_egg`.

signal closed

const PW := 520.0
const PH := 440.0
const LAYER_Z := 70

## 알 뒤 후광이 한 바퀴 도는 데 걸리는 초(원작 backlight 연출).
const BACKLIGHT_TURN := 14.0


## 알 획득 공개. `host` 아래에 붙고, 확인을 누르면 `closed` 를 쏜 뒤 스스로 사라진다.
##   did  = 드래곤 id
##   used = "무엇을 써서" 얻었는가(아이템 키). 비면 `msg` 가 없을 때 "알"로 떨어진다.
##   msg  = 하단 문구를 통째로 갈아끼운다(소환·코드처럼 "사용"이 아닌 경로용).
##   opts = 마스터에 값이 없는 종을 위한 덮어쓰기. `name`(이름표) · `art_id`(알 그림) ·
##          `element`(속성 아이콘). 커스텀 종 600/700 은 이름·속성·초상이 모두 없고
##          **재료에게서 물려받으므로**(`Summon.plan` 의 inherit) 소환이 이 셋을 넘긴다.
static func open(host: Node, did: int, used := "", msg := "", opts := {}) -> EggResultPopup:
	var p := EggResultPopup.new()
	p.layer = LAYER_Z
	host.add_child(p)
	p._build(did, used, msg, opts)
	return p


func _build(did: int, used_key: String, msg: String, opts: Dictionary = {}) -> void:
	var d: Dictionary = Data.get_dragon(did)
	var vis := get_viewport().get_visible_rect().size

	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_recall_del.tres")
	win.patch_margin_left = 40; win.patch_margin_right = 40
	win.patch_margin_top = 40; win.patch_margin_bottom = 40
	win.size = Vector2(PW, PH)
	win.position = Vector2((vis.x - PW) * 0.5, (vis.y - PH) * 0.5)
	add_child(win)

	# 후광 — 원작은 알 뒤 (w*0.5, h*0.5+110). 회전시켜 둔다(원작 backlight 연출).
	# ⚠️ `set_loops()` 만으로는 **한 바퀴 돌고 멈춘다** — rotation 을 절대값 TAU 로 트윈하면
	#    2회차는 TAU→TAU 라 움직이지 않는다(사용자 보고 2026-07-30). `.from(0.0)` 로 매 회차
	#    0 에서 시작시킨다(0 과 TAU 는 같은 각이라 이음매가 보이지 않는다).
	#    같은 관용구를 쓰는 곳: cave.gd:3006 · get_item_popup.gd:143 · levelup_result.gd:134.
	var back := AtlasUI.spr("common_ui", "common_backlight3", 1.0)
	if back:
		back.position = Vector2(PW * 0.5, 170.0)
		back.modulate = Color(1, 1, 1, 0.85)
		win.add_child(back)
		back.create_tween().set_loops().tween_property(
			back, "rotation", TAU, BACKLIGHT_TURN).from(0.0)

	# 알 — 도감과 같은 규약 `dragon_dragon_<id>_egg`. 초상이 없는 종은 물려받은 art_id 로.
	var art := int(opts.get("art_id", did))
	var eggspr := AtlasUI.spr("portrait_%d" % art, "dragon_dragon_%d_egg" % art, 1.5)
	if eggspr == null and art != did:
		eggspr = AtlasUI.spr("portrait_%d" % did, "dragon_dragon_%d_egg" % did, 1.5)
	if eggspr:
		eggspr.position = Vector2(PW * 0.5, 170.0)
		win.add_child(eggspr)

	var name_l := Label.new()
	name_l.text = _str(opts.get("name"), _str(d.get("name"), "드래곤 %d" % did))
	name_l.add_theme_font_size_override("font_size", 30)
	name_l.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	name_l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	name_l.add_theme_constant_override("outline_size", 5)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.size = Vector2(PW, 38); name_l.position = Vector2(0, 262)
	win.add_child(name_l)

	# 성급(원작 common/eggclass 를 별 개수만큼) + 속성 아이콘.
	var star := int(d.get("star", 0))
	var sw := 26.0
	var x0 := PW * 0.5 - (float(star) * sw) * 0.5
	for i in star:
		var st := AtlasUI.spr("common_ui", "common_eggclass", 0.9)
		if st:
			st.position = Vector2(x0 + float(i) * sw + sw * 0.5, 316.0)
			win.add_child(st)
	var ele := _ele_frame(_str(opts.get("element"), _str(d.get("element"), "")))
	var es := AtlasUI.spr("item_small_ui", "item_item_small_ele_%s" % ele, 1.0) if ele != "" else null
	if es:
		es.position = Vector2(x0 - 34.0, 316.0)
		win.add_child(es)

	var sub := Label.new()
	# 원작 문구 — CaveEggBronMsg7(의문의 알) / Msg9(정기=속성알) / Msg13(일반형).
	#   "%1$s을 사용하여 %2$s의 알을 획득하였습니다."
	if msg != "":
		sub.text = msg
	else:
		var used := Data.item_name(used_key) if used_key != "" else "알"
		sub.text = "%s을 사용하여 %s의 알을 획득하였습니다." % [used, _str(d.get("name"), "드래곤")]
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(PW, 24); sub.position = Vector2(0, 344)
	win.add_child(sub)

	# 확인 — 원작 common/check_btn.
	var ok := AtlasUI.spr("common_ui", "common_check_btn", 1.0)
	if ok:
		ok.position = Vector2(PW * 0.5, PH - 52.0)
		win.add_child(ok)
	var okb := Button.new(); okb.flat = true
	okb.size = Vector2(150, 60); okb.position = Vector2((PW - 150) * 0.5, PH - 82.0)
	okb.pressed.connect(func():
		closed.emit()
		queue_free())
	win.add_child(okb)


## 마스터 데이터의 문자열 필드를 안전하게 읽는다.
## ⚠️ 커스텀 종(600 수비형 / 700 공격형)은 `name` · `element` 가 **null** 이다(플레이어가 정하는
##   드래곤이라 마스터에 값이 없다). Godot 4.7 에서 `String(null)` 은 런타임 에러
##   (`Invalid call. Nonexistent 'String' constructor`)라 `.get(k, "")` 기본값으로는 못 막는다
##   — 키가 **있고 값이 null** 이면 기본값이 안 쓰이기 때문이다. [[dv2-godot-runtime-and-validation]]
##   실제로 소환(=커스텀 종)을 이 창에 물리자마자 터졌다(2026-07-30).
static func _str(v, fallback: String) -> String:
	return String(v) if typeof(v) == TYPE_STRING and String(v) != "" else fallback


## 우리 속성 코드 → 원작 `item/item_small/ele_*` 프레임 접미사.
## 원작 프레임은 ground/water 인데 우리 data 는 earth/aqua 를 쓴다.
static func _ele_frame(element: String) -> String:
	match element:
		"earth": return "ground"
		"aqua": return "water"
		_: return element
