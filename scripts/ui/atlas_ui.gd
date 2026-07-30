class_name AtlasUI
## 원본 아틀라스 프레임을 Godot 노드로 만드는 공용 헬퍼. render 층(CLAUDE.md §8.1·§8.4).
##
## 화면마다 `_spr`/`_man`/9patch 코드를 다시 짜던 걸 한 곳으로 모은다
## (기존 중복: adventure.gd · battle.gd · cave.gd · story.gd · main_hud.gd …).
## 새 화면(상점·육성·연구소·점술집)은 여기를 쓴다.
##
## 두 가지 단위 규칙이 여기 갇혀 있다:
##   1. **에셋 스케일** — 480 아틀라스 프레임은 디자인 공간에서 ×4/3 로 그린다(§9).
##   2. **9patch capInsets** — Cocos 는 **포인트**, Godot patch_margin 은 **텍스처 픽셀**.
##      ×0.75 로 환산하지 않으면 우/하 여백이 음수가 되어 테두리가 뭉개진다.

static var _mans: Dictionary = {}

## 아틀라스 폴더의 `_manifest.json`(논리키 → w/h/rotated/off/src). 캐시된다.
static func manifest(dir: String) -> Dictionary:
	if _mans.has(dir):
		return _mans[dir]
	var p := "res://assets/converted/%s/_manifest.json" % dir
	var d := {}
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			d = j
	_mans[dir] = d
	return d

static func tex(dir: String, key: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	return load(p) if ResourceLoader.exists(p) else null

## 프레임 스프라이트. scale 은 **디자인 포인트 배율**(보통 Design.ASSET_SCALE 을 넘긴다).
static func spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var t := tex(dir, key)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = pma()
	s.scale = Vector2(scale, scale)
	return s

## 프레임의 디자인 공간 크기(포인트).
static func size_pt(dir: String, key: String) -> Vector2:
	var i: Dictionary = manifest(dir).get(key, {})
	return Vector2(float(i.get("w", 0)), float(i.get("h", 0))) * Design.ASSET_SCALE

static func pma() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return m

## 원작 `CCScale9Sprite::createWithSpriteFrameName(frame, capInsets)`.
## `cap` = 원작 소스의 `CCRect(left, top, centerW, centerH)` **그대로**. 크기가 0 이면
## capInsets 를 안 준 원작 호출 = Cocos 기본값(가로·세로 1/3 분할)로 처리한다.
## `sz_pt` 는 원하는 디자인 포인트 크기.
##
## ⚠️ 단위 정정(2026-07-28): capInsets 는 **텍스처 픽셀**이다(포인트 아님) — `.img_plist` 의
##    프레임 rect 와 같은 좌표계이기 때문. 실측 근거: `9patch/scroll_box` 는 102×102px 인데
##    원작 capInsets 가 `CCRect(65,65,6,6)` 이라 65+6+31=102 로 **픽셀에서만 정확히 맞는다**
##    (포인트로 보면 136pt 중 71pt 만 덮어 우/하 여백이 65pt 로 벌어진다).
##    `9patch/popup4`(225×329, cap 130/190/40/58 → 여백 130/190/55/81)도 같은 값이 나오고,
##    이는 cave.gd 가 이미 손으로 넣어 쓰던 수치와 일치한다.
##    이전 구현은 cap 을 포인트로 보고 ×0.75 했으나, 실제로 cap 을 넘기던 호출자가 없어
##    (전부 `Rect2()`) 회귀는 없다.
static func nine(dir: String, key: String, sz_pt: Vector2, cap := Rect2()) -> NinePatchRect:
	var t := tex(dir, key)
	if t == null:
		return null
	var inv := 1.0 / Design.ASSET_SCALE          # 포인트 → 텍스처 픽셀 (=0.75)
	var l := cap.position.x
	var tp := cap.position.y
	var cw := cap.size.x
	var ch := cap.size.y
	if cap.size == Vector2.ZERO:
		l = t.get_width() / 3.0
		tp = t.get_height() / 3.0
		cw = t.get_width() / 3.0
		ch = t.get_height() / 3.0
	var np := NinePatchRect.new()
	np.texture = t
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(tp))
	np.patch_margin_right = int(round(maxf(0.0, t.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, t.get_height() - tp - ch)))
	np.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	np.size = sz_pt * inv
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np

## 원작 `RoundedButton` — 이름과 달리 **도형을 그리지 않는다**. `9patch/btn{,2,3,4,6,8,10,11}`
## Scale9(capInsets 20,20,4,4)에 라벨을 얹은 메뉴 아이템이다(`docs/ref/orig_code/decomp/RoundedButton.c:102`).
## 기본 Godot `Button`(회색 사각)은 원작에 없는 모양이라 §3 위반이므로, 화면 안의 실행 버튼은
## 전부 이 헬퍼를 쓴다. `kind` = 원작 `RoundedButtonType`.
const BTN_CAP := Rect2(20, 20, 4, 4)
const BTN_FRAME := {0: "9patch_btn", 1: "9patch_btn2", 2: "9patch_btn3", 4: "9patch_btn6",
	5: "9patch_btn8", 7: "9patch_btn10", 8: "9patch_btn11"}

static func frame_button(parent: Node, text: String, pos: Vector2, sz: Vector2, cb: Callable,
		kind := 0, disabled := false, font_size := 18) -> Control:
	var root := Control.new()
	root.size = sz
	root.position = pos
	parent.add_child(root)
	var np := nine("ninepatch_ui", String(BTN_FRAME.get(kind, "9patch_btn4")), sz, BTN_CAP)
	if np != null:
		root.add_child(np)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.disabled = disabled
	b.pressed.connect(cb)
	root.add_child(b)
	if disabled:
		root.modulate = Color(0.62, 0.62, 0.62)
	return root

## 그 NPC가 **아틀라스에 실제로 가진** 표정 세트 번호들(`npc_<name>_eye_<e>_<f>` 스캔) 중
## **UI 씬(몸통 1번)에서 쓸 수 있는 것**만.
##
## ⚠️ `data/npc_face.json`(눈·입 좌표)에는 디컴프 제어흐름이 접혀 일부 표정만 들어 있다 —
##    애니는 좌표가 2·6 뿐이지만 프레임은 1·2·3·6 이 있다. 표정 고르기는 **프레임 기준**으로 해야
##    원작처럼 여러 얼굴이 나온다(좌표는 세트 간 차이가 몇 pt라 보유분을 재사용해도 무방).
##
## 🔴 2026-07-28 버그수정 — 사용자 보고 "가끔 유리아 얼굴 파츠가 어긋난다"(표정 5에서 재현):
##    `npc_<name>_body_<n>` 이 여럿인 NPC 가 있고(유리아 1·5, 아이드라 1·5, 바루세우 1·2·3 …)
##    그 번호와 같은 표정의 눈·입은 **그 몸통 전용으로 그려져 있다**(유리아 eye_5 는 src 69×26,
##    나머지는 60×30). 몸통 1 위에 얹으면 특히 입이 어긋난다.
##    원작 UI 씬은 몸통을 **1 고정**으로 쓰고(`MagicShopScene::setTalker` 호출부 전부 param 1)
##    표정도 좁게 쓴다(`onClickAlchemyItem` 은 1·2 만). 다른 몸통 포즈는 스토리 컷씬 쪽이다.
##    ⇒ **전용 몸통을 가진 표정 번호는 후보에서 뺀다.** 남은 표정은 전부 몸통 1에 맞는 그림이다
##      (유리아 1·2·3·4·6·7 실측 확인).
static func npc_emotions(npc: String) -> Array:
	var man := manifest("npc_%s" % npc)
	var out: Array = []
	var pre := "npc_%s_eye_" % npc
	var bpre := "npc_%s_body_" % npc
	var alt_bodies: Array = []          # 1 이 아닌 전용 몸통 번호 = 컷씬 전용 포즈
	for k in man.keys():
		var key := String(k)
		if key.begins_with(bpre):
			var b := key.substr(bpre.length())
			if b.is_valid_int() and int(b) != 1:
				alt_bodies.append(int(b))
	for k in man.keys():
		var key := String(k)
		if not key.begins_with(pre):
			continue
		var e := key.substr(pre.length()).split("_")[0]
		if not e.is_valid_int():
			continue
		var ei := int(e)
		if alt_bodies.has(ei) or out.has(ei):
			continue
		out.append(ei)
	out.sort()
	if out.is_empty():
		out.append(1)                   # 전부 걸러졌으면 기본 표정
	return out

## 원작이 그 씬에서 **실제로 쓰는 표정 번호**만 남긴다(`allowed` ∩ 아틀라스 보유분).
## `allowed` 가 비어 있으면 `npc_emotions()` 를 그대로 쓴다.
##
## 근거 = 각 씬의 `setTalker(…, name, 1, <표정>, 2, 0, 0, 1)` 호출부 실측(2026-07-28):
##   · `MagicShopScene` : 리터럴 1 + `iVar1`(rand 로 1 또는 2)          → {1, 2}
##   · `LaboratoryScene`: 리터럴 1 + `iVar20`(1 또는 3) + `(x&1)+1`(1 또는 2) → {1, 2, 3}
##   · `PromoteScene`   : 리터럴 1 뿐                                    → {1}
## 두 번째 인자(=1)가 몸통이고 세 번째가 표정이다(`NpcManager::setNpcEye` 가 받는 값).
static func npc_emotions_for(npc: String, allowed: Array) -> Array:
	var have := npc_emotions(npc)
	if allowed.is_empty():
		return have
	var out: Array = []
	for e in allowed:
		if have.has(int(e)):
			out.append(int(e))
	return out if not out.is_empty() else have

## 천 단위 콤마(원작 `Util::util_add_comma_to_num`).
static func comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
