class_name ItemEnchantPopup
extends Control
## 아이템(장비) 강화 창 — 원작 `cocos2d::ItemEnchantPopup` 이식. render 층(CLAUDE.md §8.1).
##
## 참조 프레임 = `docs/ref/equip/장비강화1.png`(사용자 제공).
## 디컴프 = `docs/ref/orig_code/decomp/ItemEnchantPopup.c`(`initWidget` 리터럴, skip 0건).
##
## 원작 톱니 기계(전부 이 이식으로 갭 해소):
##   `scene/cave/gear` + `gear_shadow`(+2.5,−2.5) + `gear_inside` + `enchant_line`
##   + `gear_shadow_large`(100, −127.5) + `gear_shadow_small`(182.5, −75)
##   + `itembox_add` ×3 @ 중심 기준 **(0,199) / −(157.5,125) / +(159.5,−125)**
##     (아티팩트 합성 기계와 **같은 삼각 배치**다 — `ArtifactMix::drawMachine` 과 리터럴 일치)
##   + `itembox_add_sign`("+") + `pipe1~4`(왼쪽 배관) + `common/coin_big` 비용
##   + `9patch/scroll_box` 재료 격자 + `9patch/text_box` 설명
##   효과음 `effect_enchant` / 성공 `effect_equip_success` / 실패 `effect_equip_failed`.
##
## ⚠️ **강화 보조 재료(강화석)는 데이터가 유실됐다** — `data/items.json` 257종에 해당 아이템이
##   없고(위키에도 표가 없다) 원작은 서버가 목록을 내려줬다. 그래서 3칸은 원작 프레임 그대로
##   그리되 **누르면 안내만** 한다. 우리 강화 규칙은 골드 1회 소모(`Equipment.enhance`,
##   한도 = 옵션 수 × 5, 위키 §2.6)로 유지한다. 재료 목록이 확보되면 이 칸만 배선하면 된다.

signal closed

const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN := Vector2(860.0, 520.0)
const DIM_ALPHA := 127.0 / 255.0

## `initWidget` 리터럴 — 기계 중심 기준 오프셋(cocos y-up).
const SHADOW_OFF := Vector2(2.5, -2.5)
const SHADOW_LARGE := Vector2(100.0, -127.5)
const SHADOW_SMALL := Vector2(182.5, -75.0)
const ADD_SLOTS := [Vector2(0.0, 199.0), Vector2(-157.5, -125.0), Vector2(159.5, -125.0)]
## 왼쪽 배관 — (창폭×0.5 기준 오프셋, cocos y).
## (오프셋만 상수로 — 프레임 키는 아래에서 리터럴로 부른다. `asset_index.py` 가
##  `AtlasUI.spr("<폴더>", "<키>")` 쌍으로 사용처를 세기 때문이다.)
const PIPE_AT := [Vector2(-20.0, 80.0), Vector2(-55.0, -10.0), Vector2(-100.0, 5.0),
	Vector2(-45.0, -25.0)]
const BTN := Vector2(150.0, 48.0)

var _uid := 0
var _slot := ""
var _on_done: Callable = Callable()
var _win_root: Control
var _rng := RandomNumberGenerator.new()


static func open(parent: Node, uid: int, slot_id: String, on_done := Callable()) -> ItemEnchantPopup:
	var p := ItemEnchantPopup.new()
	p._uid = uid
	p._slot = slot_id
	p._on_done = on_done
	parent.add_child(p)
	p._build()
	return p


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 65
	_rng.randomize()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.2)
	_rebuild()


func _rebuild() -> void:
	if is_instance_valid(_win_root):
		_win_root.queue_free()
	var vis := get_viewport_rect().size
	_win_root = Control.new()
	_win_root.size = WIN
	_win_root.position = ((vis - WIN) * 0.5).round()
	add_child(_win_root)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", WIN, WIN_CAP)
	if fr:
		_win_root.add_child(fr)

	var t := _label("아이템 강화", 26, Color.WHITE)      # <CaveEnchantTitle>
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 26.0)
	t.size = Vector2(WIN.x, 40.0)
	_win_root.add_child(t)

	var cb := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct:
		cb.texture_normal = ct
		cb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.3
	cb.position = Vector2(WIN.x - 74.0, 24.0)
	cb.pressed.connect(close)
	_win_root.add_child(cb)

	_build_machine()
	_build_side()


## 톱니 기계 — 원작 initWidget 순서(그림자 → 톱니 → 안쪽 → 라인) 그대로.
func _build_machine() -> void:
	var S := Design.ASSET_SCALE
	var c := Vector2(WIN.x * 0.30, WIN.y * 0.5 + 8.0)
	var root := Node2D.new()
	root.name = "machine"
	root.position = c
	_win_root.add_child(root)

	for spec in [["scene_cave_gear_shadow_large", SHADOW_LARGE], ["scene_cave_gear_shadow_small", SHADOW_SMALL]]:
		var s := AtlasUI.spr("cave_ui", String(spec[0]), S * 0.62)
		if s:
			var o: Vector2 = spec[1]
			s.position = Vector2(o.x, -o.y) * 0.62
			root.add_child(s)
	var gsh := AtlasUI.spr("cave_ui", "scene_cave_gear_shadow", S * 0.62)
	if gsh:
		gsh.position = Vector2(SHADOW_OFF.x, -SHADOW_OFF.y)
		root.add_child(gsh)
	var gear := AtlasUI.spr("cave_ui", "scene_cave_gear", S * 0.62)
	if gear:
		root.add_child(gear)
		# 원작 `makeGearActionNormal` — 톱니가 천천히 돈다.
		gear.create_tween().set_loops().tween_property(gear, "rotation", TAU, 12.0).as_relative()
	var inside := AtlasUI.spr("cave_ui", "scene_cave_gear_inside", S * 0.62)
	if inside:
		root.add_child(inside)
	var line := AtlasUI.spr("cave_ui", "scene_cave_enchant_line", S * 0.62)
	if line:
		root.add_child(line)
		line.create_tween().set_loops().tween_property(line, "rotation", -TAU, 20.0).as_relative()

	# 강화 대상 장비 — 톱니 한가운데.
	var art := _item_sprite(1.1)
	if art:
		art.name = "target"
		root.add_child(art)

	# 보조 재료 3칸(`itembox_add` + `itembox_add_sign`).
	for off in ADD_SLOTS:
		var box := AtlasUI.spr("cave_ui", "scene_cave_itembox_add", S * 0.62)
		var at := Vector2(off.x, -off.y) * 0.62
		if box:
			box.position = at
			root.add_child(box)
		var sign := AtlasUI.spr("cave_ui", "scene_cave_itembox_add_sign", S * 0.62)
		if sign:
			sign.position = at
			root.add_child(sign)
		var hit := Button.new()
		hit.flat = true
		hit.size = Vector2(56.0, 56.0)
		hit.position = c + at - hit.size * 0.5
		hit.pressed.connect(func(): _notice(
			"강화 보조 재료 목록은 원작 서버 데이터라 남아 있지 않습니다.\n(현재 강화는 골드만 소모합니다)"))
		_win_root.add_child(hit)

	# 왼쪽 배관(원작 `initPipePos` — 창 중앙 왼쪽으로 이어지는 관 4개).
	var pipes: Array[Sprite2D] = [
		AtlasUI.spr("cave_ui", "scene_cave_pipe1", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe2", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe3", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe4", S * 0.62)]
	for pi in pipes.size():
		var p: Sprite2D = pipes[pi]
		if p == null:
			continue
		var o: Vector2 = PIPE_AT[pi]
		p.position = c + Vector2(o.x, -o.y) * 0.62 + Vector2(-WIN.x * 0.18, 0)
		_win_root.add_child(p)

	# 비용 — `common/coin_big` @ (w/3+15, 57.5)c.
	var cost := _cost()
	var coin := AtlasUI.spr("common_ui", "common_coin_big", S * 0.8)
	if coin:
		coin.position = Vector2(WIN.x / 3.0 + 15.0, WIN.y - 57.5)
		_win_root.add_child(coin)
	var cl := _label("x %s" % AtlasUI.comma(cost), 20, Color(1, 0.95, 0.72))
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.position = Vector2(WIN.x / 3.0 + 45.0, WIN.y - 78.0)
	cl.size = Vector2(240.0, 40.0)
	_win_root.add_child(cl)

	# 성공 확률(참조의 좌하단 "성공 확률 23%").
	var pl := _label("성공 확률 %d%%" % _success_pct(), 19, Color(0.55, 1.0, 0.62))
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.position = Vector2(40.0, WIN.y - 78.0)
	pl.size = Vector2(220.0, 40.0)
	_win_root.add_child(pl)


## 오른쪽 — `9patch/scroll_box` 재료 격자 + `9patch/text_box` 설명 + 강화/선택 버튼.
func _build_side() -> void:
	var bx := WIN.x * 0.56
	var bw := WIN.x - bx - 44.0
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(bw, 190.0),
		Rect2(65, 65, 6, 6))
	if box:
		box.position = Vector2(bx, 84.0)
		_win_root.add_child(box)
	var note := _label("보조 재료 목록 없음 (서버 유실)", 16, Color(0.45, 0.33, 0.20))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.position = Vector2(bx, 84.0)
	note.size = Vector2(bw, 190.0)
	_win_root.add_child(note)

	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(bw, 175.0),
		Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(bx, 292.0)
		_win_root.add_child(tb)
	var col := VBoxContainer.new()
	col.position = Vector2(bx + 16.0, 306.0)
	col.size = Vector2(bw - 32.0, 150.0)
	col.add_theme_constant_override("separation", 5)
	_win_root.add_child(col)
	var sd := _slot_data()
	col.add_child(_label(_item_name(), 19, Color(0.72, 0.20, 0.10)))
	var done := int(sd.get("enhance", 0))
	col.add_child(_label("강화 %d / %d" % [done, _limit()], 17, Color(0.30, 0.17, 0.04)))
	for o in (sd.get("options", []) as Array):
		var od: Dictionary = o
		col.add_child(_label("%s +%s" % [String(EquipOptionLayer.STAT_KR.get(
			String(od.get("stat", "")), String(od.get("stat", "")))),
			str(od.get("value", 0))], 16, Color(0.30, 0.17, 0.04)))

	_button("강화", Vector2(bx + bw * 0.5 - BTN.x - 8.0, WIN.y - 76.0), _on_enchant)
	_button("선택", Vector2(bx + bw * 0.5 + 8.0, WIN.y - 76.0), close)


# ------------------------------------------------------------ 동작

func _on_enchant() -> void:
	var sd := _slot_data()
	if sd.is_empty():
		_notice("장비가 없는 칸입니다")
		return
	if int(sd.get("enhance", 0)) >= _limit():
		_notice("더 강화할 수 없습니다")
		return
	var cost := _cost()
	if not UserDB.spend("gold", cost):
		_notice("골드가 부족합니다")
		return
	Bgm.sfx("effect_enchant")
	var next: Dictionary = Equipment.enhance(
		UserDB.get_dragon(_uid).get("equip", {}), _slot, _rng, Data.equipment)
	var ok := not next.is_empty()
	if ok:
		UserDB.set_dragon_field(_uid, "equip", next)
	Bgm.sfx("effect_equip_success" if ok else "effect_equip_failed")
	if _on_done.is_valid():
		_on_done.call()
	_rebuild()


func _slot_data() -> Dictionary:
	for s in (UserDB.get_dragon(_uid).get("equip", {}).get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == _slot:
			return s
	return {}


func _limit() -> int:
	var sd := _slot_data()
	var per := int(Data.equipment.get("option", {}).get("enhance_per_option", 5))
	return (sd.get("options", []) as Array).size() * per


## 강화 비용 — 종전 cave.gd `ENHANCE_COST`(8,000). 원작 비용표는 서버 유실.
func _cost() -> int:
	return int(Data.equipment.get("option", {}).get("enhance_gold", 8000))


## 참조의 "성공 확률" 표시. 우리 `Equipment.enhance` 는 실패가 없다 —
## 한도(옵션 수 × 5)에 닿기 전이면 100%다. 원작 확률표는 서버 유실.
func _success_pct() -> int:
	var sd := _slot_data()
	return 100 if not sd.is_empty() and int(sd.get("enhance", 0)) < _limit() else 0


func _item_name() -> String:
	var sd := _slot_data()
	var item: Dictionary = Equipment.catalog(Data.equipment).get(String(sd.get("key", "")), {})
	var nm := String(item.get("name", "장비"))
	var e := int(sd.get("enhance", 0))
	return "%s +%d" % [nm, e] if e > 0 else nm


func _item_sprite(mult: float) -> Sprite2D:
	var sd := _slot_data()
	var item: Dictionary = Equipment.catalog(Data.equipment).get(String(sd.get("key", "")), {})
	var t := Icons.equip_texture(item)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = AtlasUI.pma()
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * mult
	return s


func close() -> void:
	closed.emit()
	queue_free()


# ---------- 공용 ----------

func _button(text: String, at: Vector2, cb: Callable) -> void:
	var root := Control.new()
	root.size = BTN
	root.position = at
	_win_root.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_btn", BTN, Rect2(20, 20, 4, 4))
	if np:
		root.add_child(np)
	var l := _label(text, 20, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = BTN
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = BTN
	b.pressed.connect(cb)
	root.add_child(b)


func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if col == Color.WHITE or col.v > 0.8:
		l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
		l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _notice(msg: String) -> void:
	PopupType.open(self, "아이템 강화", msg, Callable(), "확인", "")
