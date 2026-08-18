class_name EquipOptionView
extends Control

signal finished

const S_TITLE := "제련"
const S_RETRY := "재시도"
const S_BEFORE := "기존 옵션"
const S_AFTER := "제련 옵션"
const S_NON_SELECT := "#b8a551a9"
const S_MSG_BEFORE := "#4913cbf7"
const S_MSG_AFTER := "#6488fdd0"
const S_MSG_RETRY := "아이템은 기존 옵션으로 유지되고 제련 옵션은 변경 됩니다.\n제련 재시도 하시겠습니까?"

const CANVAS_LAYER := 68
const DIM_ALPHA := 200.0 / 255.0
const CIRCLE_SECS := 2.2
const SFX_ROLL := "effect_roulette"
const SFX_DONE := "effect_upgrade"

const WIN := Vector2(760.0, 460.0)
const CARD := Vector2(250.0, 300.0)
const CARD_L := Vector2(130.0, 92.0)
const CARD_R := Vector2(400.0, 92.0)
const BTN := Vector2(150.0, 48.0)

const STAT_KR := {"hp": "생명력", "att": "공격력", "def": "방어력", "blk": "방어율",
	"evd": "회피율", "cri": "치명타", "gold": "골드", "exp": "경험치",
	"pure": "관통", "depure": "관통 감소", "accuracy": "명중"}

static func opt_text(od: Dictionary, table: Dictionary, sep: String = " ") -> String:
	var st := String((od as Dictionary).get("stat", ""))
	return Equipment.option_text(String(STAT_KR.get(st, st)), st,
		(od as Dictionary).get("value", 0), table, sep)

var _uid := 0
var _slot := ""
var _bag_key := ""
var _coin_key := ""
var _grade := 0
var _on_done: Callable = Callable()
var _mode := 1
var _retry_cost: Dictionary = {}

var _before: Array = []
var _after: Array = []
var _enhance := 0
var _pick := -1
var _win_root: Control
var _canvas: CanvasLayer
var _rng := RandomNumberGenerator.new()

func _mount(parent: Node) -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = CANVAS_LAYER
	parent.add_child(_canvas)
	_canvas.add_child(self)
	_start()

func _dismiss() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	else:
		queue_free()

static func open(parent: Node, uid: int, slot_id: String, coin_key: String, grade: int,
		on_done := Callable()) -> EquipOptionView:
	var l := EquipOptionView.new()
	l._uid = uid
	l._slot = slot_id
	l._coin_key = coin_key
	l._grade = grade
	l._on_done = on_done
	l._retry_cost = {coin_key: 1}
	l._mount(parent)
	return l

static func open_bag(parent: Node, inv_key: String, coin_key: String, grade: int,
		on_done := Callable()) -> EquipOptionView:
	var l := EquipOptionView.new()
	l._bag_key = inv_key
	l._coin_key = coin_key
	l._grade = grade
	l._on_done = on_done
	l._retry_cost = {coin_key: 1}
	l._mount(parent)
	return l

static func open_artifact(parent: Node, inv_key: String, grade: int,
		on_done := Callable()) -> EquipOptionView:
	var l := EquipOptionView.new()
	l._bag_key = inv_key
	l._grade = grade
	l._mode = 2
	l._on_done = on_done
	l._retry_cost = (Equipment.artifact_smelt_cfg(Data.equipment).get("items", {}) as Dictionary)
	l._mount(parent)
	return l

func _roll_weights() -> Dictionary:
	return Equipment.artifact_smelt_weights(Data.equipment) if _mode == 2 else {}

func _can_pay_retry() -> bool:
	for k in _retry_cost:
		if UserDB.item_count(String(k)) < int(_retry_cost[k]):
			return false
	return not _retry_cost.is_empty()

func _pay_retry() -> bool:
	if not _can_pay_retry():
		return false
	for k in _retry_cost:
		if not UserDB.use_item(String(k), int(_retry_cost[k])):
			return false
	return true

func _retry_cost_text() -> String:
	var parts: PackedStringArray = []
	for k in _retry_cost:
		parts.append("%s X %d" % [Data.item_name(String(k)), int(_retry_cost[k])])
	return " · ".join(parts)

func _target_view() -> Dictionary:
	if _bag_key != "":
		var ck := Equipment.parse_item_key(_bag_key)
		if ck == "":
			return {}
		var m := Equipment.item_key_meta(_bag_key)
		return {"slot": "", "key": ck, "grade": int(m.get("rarity", 0)),
			"enhance": int(m.get("enhance", 0)), "options": m.get("options", []),
			"belong": int(m.get("belong", 0))}
	for s in (UserDB.get_dragon(_uid).get("equip", {}).get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == _slot:
			return s
	return {}

func current_key() -> String:
	return _bag_key

func _start() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()

	var tv := _target_view()
	_before = (tv.get("options", []) as Array).duplicate(true)
	_enhance = int(tv.get("enhance", 0))
	_after = Equipment.roll_options_at_enhance(_grade, _enhance, _rng, Data.equipment,
		_roll_weights())

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.5)
	_play_circle()

func _play_circle() -> void:
	var vis := get_viewport_rect().size
	var c := vis * 0.5
	var fx := Node2D.new()
	fx.position = c
	add_child(fx)
	Bgm.sfx(SFX_ROLL)

	for i in 2:
		var s := AtlasUI.spr("magicshop_ui", "scene_magicshop_recall_magic_circle_%d" % (i + 1),
			Design.ASSET_SCALE * 0.4)
		if s == null:
			continue
		s.modulate = Color(1, 1, 1, 0)
		fx.add_child(s)
		var t := s.create_tween().set_parallel(true)
		t.tween_property(s, "modulate:a", 1.0, 0.4)
		t.tween_property(s, "scale", Vector2.ONE * Design.ASSET_SCALE * 0.95, CIRCLE_SECS)
		t.tween_property(s, "rotation", TAU * (1.0 if i == 0 else -1.0), CIRCLE_SECS)

	var item := _item_sprite(1.4)
	if item != null:
		item.position = Vector2.ZERO
		fx.add_child(item)
		var it := item.create_tween()
		it.tween_property(item, "scale", item.scale * 1.25, CIRCLE_SECS * 0.5)
		it.tween_property(item, "scale", item.scale, CIRCLE_SECS * 0.5)

	var glow := ColorRect.new()
	glow.color = Color(1, 1, 1, 0)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	var gt := create_tween()
	gt.tween_interval(CIRCLE_SECS - 0.35)
	gt.tween_property(glow, "color:a", 1.0, 0.25)
	gt.tween_property(glow, "color:a", 0.0, 0.3)
	await gt.finished
	glow.queue_free()
	fx.queue_free()
	Bgm.sfx(SFX_DONE)
	_build_result()

func _build_result() -> void:
	var vis := get_viewport_rect().size
	_win_root = Control.new()
	_win_root.size = WIN
	_win_root.position = ((vis - WIN) * 0.5).round()
	add_child(_win_root)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", WIN, Rect2(130, 190, 40, 58))
	if fr:
		_win_root.add_child(fr)

	var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
	var tw := WIN.x * 0.42
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(tw, th))
	if tb:
		tb.position = Vector2(WIN.x * 0.5 - tw * 0.5, 44.0 - th * 0.5)
		_win_root.add_child(tb)
	var tl := _label(Data.ui(S_TITLE), 24, Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.position = Vector2(WIN.x * 0.5 - tw * 0.5, 44.0 - th * 0.5)
	tl.size = Vector2(tw, th)
	_win_root.add_child(tl)

	_build_card(0, CARD_L, "", _before)
	_build_card(1, CARD_R, S_AFTER, _after)

	var fold := AtlasUI.spr("common_ui", "common_btn_fold", Design.ASSET_SCALE * 0.7)
	if fold:
		fold.rotation = deg_to_rad(90.0)
		fold.position = Vector2((CARD_L.x + CARD.x + CARD_R.x) * 0.5, CARD_L.y + CARD.y * 0.5)
		_win_root.add_child(fold)

	_button("선택", Vector2(WIN.x * 0.5 - 160.0, WIN.y - 74.0), _on_select)
	_button(S_RETRY, Vector2(WIN.x * 0.5 + 10.0, WIN.y - 74.0), _on_retry)

func _build_card(idx: int, at: Vector2, caption: String, opts: Array) -> void:
	var card := Panel.new()
	card.size = CARD
	card.position = at
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.83, 0.70, 0.50, 0.55)
	sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10; sb.corner_radius_bottom_right = 10
	if _pick == idx:
		sb.border_width_left = 4; sb.border_width_right = 4
		sb.border_width_top = 4; sb.border_width_bottom = 4
		sb.border_color = Color(1.0, 0.86, 0.25)
	card.add_theme_stylebox_override("panel", sb)
	_win_root.add_child(card)

	var art := _item_sprite(1.0)
	if art != null:
		art.position = Vector2(CARD.x * 0.5, 76.0)
		card.add_child(art)
	if caption != "":
		var cl := _label(caption, 18, Color(0.30, 0.17, 0.04))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.position = Vector2(0, 132.0)
		cl.size = Vector2(CARD.x, 24.0)
		card.add_child(cl)

	var box := VBoxContainer.new()
	box.position = Vector2(16.0, 166.0)
	box.size = Vector2(CARD.x - 32.0, CARD.y - 180.0)
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	for o in opts:
		var od: Dictionary = o
		var l := _label(opt_text(od, Data.equipment), 16, Color(0.30, 0.17, 0.04))
		box.add_child(l)
	if opts.is_empty():
		box.add_child(_label("(옵션 없음)", 16, Color(0.45, 0.33, 0.20)))

	var b := Button.new()
	b.flat = true
	b.size = CARD
	var i := idx
	b.pressed.connect(func():
		_pick = i
		_rebuild_result())
	card.add_child(b)

func _rebuild_result() -> void:
	if is_instance_valid(_win_root):
		_win_root.queue_free()
	_build_result()

func _on_select() -> void:
	if _pick < 0:
		_notice(Data.ui(S_NON_SELECT))
		return
	_confirm(Data.ui(S_MSG_BEFORE) if _pick == 0 else Data.ui(S_MSG_AFTER), func(): _apply(_pick == 1))

func _on_retry() -> void:
	if not _can_pay_retry():
		_notice("%s이(가) 부족합니다" % _retry_cost_text())
		return
	_confirm("%s

%s" % [S_MSG_RETRY, _retry_cost_text()], func():
		if not _pay_retry():
			return
		_after = Equipment.roll_options_at_enhance(_grade, _enhance, _rng, Data.equipment,
			_roll_weights())
		_pick = -1
		_rebuild_result())

func _apply(use_new: bool) -> void:
	if use_new and _bag_key != "":
		var view := _target_view()
		if not view.is_empty() and UserDB.item_count(_bag_key) > 0:
			view["options"] = _after.duplicate(true)
			var new_key := Equipment.slot_to_item_key(view)
			UserDB.add_item(_bag_key, -1)
			UserDB.add_item(new_key, 1)
			_bag_key = new_key
	elif use_new:
		var next: Dictionary = Equipment.reroll(
			UserDB.get_dragon(_uid).get("equip", {}), _slot, _grade, _rng, Data.equipment, _uid)
		for s in (next.get("slots", []) as Array):
			if String((s as Dictionary).get("slot", "")) == _slot:
				(s as Dictionary)["options"] = _after.duplicate(true)
				break
		if not next.is_empty():
			UserDB.set_dragon_field(_uid, "equip", next)
	if _on_done.is_valid():
		_on_done.call(use_new)
	finished.emit()
	_dismiss()

func _item_sprite(mult: float) -> Sprite2D:
	var key := String(_target_view().get("key", ""))
	if key == "":
		return null
	var item: Dictionary = Equipment.catalog(Data.equipment).get(key, {})
	var t := Icons.equip_texture(item)
	if t == null:
		return null
	var s2 := Sprite2D.new()
	s2.texture = t
	s2.material = AtlasUI.pma()
	s2.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * mult
	return s2

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
	if col == Color.WHITE:
		l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
		l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _notice(msg: String) -> void:
	MessageWindow.open(self, "알림", msg, Callable(), "확인", "")

func _confirm(msg: String, on_ok: Callable) -> void:
	MessageWindow.open(self, "알림", msg, on_ok, "확인", "취소")
