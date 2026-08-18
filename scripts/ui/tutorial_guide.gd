class_name TutorialGuide
extends CanvasLayer

const ARROW_TEX := "res://assets/converted/common_ui/common_btn_arrow2.tres"
const BOX_H := 132.0
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const STEP_KEY := "tutorial_step"
const DONE_KEY := "tutorial_done"

signal finished

var _steps: Dictionary = {}
var _order: Array = []
var _i := 0
var _box: Control
var _box_btn: Button
var _label: Label
var _arrows: Array[Node] = []
var _blocked := false
var _box_wanted := false
var _wait_target: Node = null

static var _live: TutorialGuide = null

static func is_running() -> bool:
	if _live != null and is_instance_valid(_live):
		return true
	return _pending()

static func _pending() -> bool:
	var v = UserDB.get_pmeta(DONE_KEY, null)
	return v is bool and not bool(v)

static func resume(host: Node) -> TutorialGuide:
	if not _pending():
		return null
	return start(host)

static func start(host: Node) -> TutorialGuide:
	var g := TutorialGuide.new()
	g.layer = 60
	_live = g
	host.add_child(g)
	return g

func _ready() -> void:
	var doc: Dictionary = Data.tutorial_flow
	_steps = doc.get("steps", {})
	_order = doc.get("order", [])
	if _order.is_empty():
		push_warning("[tutorial] data/tutorial_flow.json 이 비었다 — extract_tutorial_flow.py 실행 필요")
		queue_free()
		return
	var saved := String(UserDB.get_pmeta(STEP_KEY, ""))
	_i = maxi(0, _order.find(saved)) if saved != "" else 0
	_build_box()
	_run()

func _build_box() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	_box = Control.new()
	_box.size = Vector2(vis.x, BOX_H)
	_box.position = Vector2(0.0, vis.y - BOX_H)
	_place_box()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)
	var np := NinePatchRect.new()
	np.texture = load(DIALOG_BOX)
	np.patch_margin_left = 20; np.patch_margin_top = 20
	np.patch_margin_right = 11; np.patch_margin_bottom = 11
	np.size = _box.size
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(np)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(34.0, 16.0)
	_label.size = Vector2(vis.x - 68.0, BOX_H - 32.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_label)
	_box_btn = Button.new()
	_box_btn.flat = true
	_box_btn.size = _box.size
	_box_btn.pressed.connect(func(): if _wait_target == null: _advance())
	_box.add_child(_box_btn)

func _apply_box_input() -> void:
	if not is_instance_valid(_box):
		return
	var eat := _wait_target == null
	_box.mouse_filter = Control.MOUSE_FILTER_STOP if eat else Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_box_btn):
		_box_btn.mouse_filter = Control.MOUSE_FILTER_STOP if eat else Control.MOUSE_FILTER_IGNORE

const FALLBACK_LAYER_MIN := 20

var _popup_check := 0

func _process(_dt: float) -> void:
	if not is_instance_valid(_box):
		return
	_popup_check -= 1
	if _popup_check > 0:
		return
	_popup_check = 6
	var hidden := _modal_open()
	_box.visible = _box_wanted and not hidden
	for a in _arrows:
		if is_instance_valid(a) and a is CanvasItem:
			(a as CanvasItem).visible = not hidden
	if is_instance_valid(_npc) and _npc is CanvasItem:
		(_npc as CanvasItem).visible = not hidden

func _modal_open() -> bool:
	var sc := Scenes.current_scene()
	if sc != null and sc.has_method("has_modal"):
		return bool(sc.call("has_modal"))
	return _fallback_modal(get_tree().root)

func _fallback_modal(n: Node) -> bool:
	if n == self:
		return false
	if n is CanvasLayer:
		var cl := n as CanvasLayer
		if cl.layer >= FALLBACK_LAYER_MIN and cl.visible and cl.name != "ToastLayer":
			return true
	for c in n.get_children():
		if _fallback_modal(c):
			return true
	return false

func _place_box() -> void:
	if not is_instance_valid(_box) or not is_instance_valid(_label):
		return
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var lines := maxi(1, _label.get_line_count() if _label.get_line_count() > 0 else 1)
	var h := maxf(BOX_H, float(lines) * (_label.get_line_height() + 2) + 32.0)
	_box.size.y = h
	for c in _box.get_children():
		if c is NinePatchRect or c is Button:
			(c as Control).size.y = h
	_label.size.y = h - 32.0
	var y := vis.y - h
	var bar := _find_guide_target(get_tree().root, "bottom_bar")
	if bar != null:
		y = minf(y, bar.get_global_rect().position.y - h)
	_box.position = Vector2(0.0, maxf(0.0, y))

func _arrow(target: Control, spec: Dictionary) -> void:
	var tex := load(ARROW_TEX) if ResourceLoader.exists(ARROW_TEX) else null
	if tex == null or not is_instance_valid(target):
		return
	var a := Sprite2D.new()
	a.texture = tex
	a.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	a.modulate.a = 0.0
	if bool(spec.get("flip_x", false)):
		a.flip_h = true
	else:
		a.rotation_degrees = float(spec.get("rot", 0))
	var r := target.get_global_rect()
	a.position = r.position + r.size * 0.5
	add_child(a)
	_arrows.append(a)
	var t := a.create_tween()
	t.tween_interval(float(spec.get("delay", 0.0)))
	t.tween_property(a, "modulate:a", 1.0, 0.3)
	t.tween_callback(func():
		var p := a.create_tween().set_loops()
		p.tween_property(a, "scale", Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5, 0.5)
		p.tween_property(a, "scale", Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE), 0.5))

const HILITE_COLOR := Color8(0xf1, 0x5f, 0x5f)
const HILITE_PAD := 6.0

func _highlight(target: Control) -> void:
	if not is_instance_valid(target) or not ResourceLoader.exists(DIALOG_BOX):
		return
	var r := target.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var np := NinePatchRect.new()
	np.texture = load(DIALOG_BOX)
	np.patch_margin_left = 20; np.patch_margin_top = 20
	np.patch_margin_right = 11; np.patch_margin_bottom = 11
	np.modulate = HILITE_COLOR
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.position = r.position - Vector2(HILITE_PAD, HILITE_PAD)
	np.size = r.size + Vector2(HILITE_PAD, HILITE_PAD) * 2.0
	add_child(np)
	_arrows.append(np)

func _clear_speaker() -> void:
	if is_instance_valid(_npc):
		_npc.queue_free()
	_npc = null

func _clear_arrows() -> void:
	for a in _arrows:
		if is_instance_valid(a):
			a.queue_free()
	_arrows.clear()

const NO_PORTRAIT := ["hero", "prologuemonster"]
var _npc: Node = null

func _show_speaker(st: Dictionary) -> void:
	if is_instance_valid(_npc):
		_npc.queue_free()
	_npc = null
	if not st.has("talk_index"):
		return
	var sp: Dictionary = Data.tutorial_flow.get("speakers", {}).get(str(int(st["talk_index"])), {})
	var npc := String(sp.get("npc", ""))
	if npc == "" or npc in NO_PORTRAIT:
		return
	var p := NpcPortrait.create(npc, 1, 1)
	if p == null:
		return
	_npc = p
	p.z_index = 4
	add_child(p)
	p.modulate.a = 0.0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.2)
	_place_speaker()

const SPEAKER_H_RATIO := 0.62

func _scale_speaker() -> void:
	if not is_instance_valid(_npc) or not is_instance_valid(_box):
		return
	var h: float = (_npc as NpcPortrait).body_height()
	if h <= 0.0:
		return
	var room := maxf(1.0, _box.position.y)
	var k := minf(1.0, room * SPEAKER_H_RATIO / h)
	(_npc as Node2D).scale = Vector2(k, k)

func _place_speaker() -> void:
	if not is_instance_valid(_npc) or not is_instance_valid(_box):
		return
	_scale_speaker()
	var vis: Vector2 = get_viewport().get_visible_rect().size
	(_npc as Node2D).position = Vector2(vis.x * 0.5, _box.position.y)

func _cur() -> Dictionary:
	return _steps.get(String(_order[_i]), {}) if _i < _order.size() else {}

func _run() -> void:
	_clear_arrows()
	_stop_gate()
	if _i >= _order.size():
		_finish()
		return
	var key := String(_order[_i])
	var st: Dictionary = _steps.get(key, {})
	if String(st.get("cut", "")) != "":
		_i += 1
		_run()
		return
	UserDB.set_pmeta(STEP_KEY, key)
	var text := String(st.get("text", ""))
	_label.text = text
	_box_wanted = text != ""
	_show_speaker(st)
	await get_tree().process_frame
	_place_box()
	_place_speaker()
	var target := _target_for(st)
	_wait_target = null
	if target != null:
		for spec in st.get("arrows", []):
			_arrow(target, spec)
		if bool(st.get("highlight", false)):
			_highlight(target)
		if bool(st.get("press_target", false)) and target is BaseButton:
			_wait_target = target
			if not (target as BaseButton).pressed.is_connected(_advance):
				(target as BaseButton).pressed.connect(_advance, CONNECT_ONE_SHOT)
	var gate := String(st.get("gate", ""))
	if gate != "" and not _gate_ok(gate):
		var wt := String(st.get("gate_wait_text", ""))
		if wt != "":
			_label.text = wt
			_box_wanted = true
			await get_tree().process_frame
			_place_box()
			_place_speaker()
		if target is BaseButton and (target as BaseButton).pressed.is_connected(_advance):
			(target as BaseButton).pressed.disconnect(_advance)
		_wait_target = _box
		_apply_box_input()
		_start_gate(gate)
		return
	_apply_box_input()
	_dispatch(st)

func _target_for(st: Dictionary) -> Control:
	var id := String(st.get("target", ""))
	if id == "":
		return null
	return _find_guide_target(get_tree().root, id)

func _find_guide_target(n: Node, id: String) -> Control:
	if n.has_method("guide_target"):
		var r = n.call("guide_target", id)
		if r is Control and is_instance_valid(r):
			return r
	for c in n.get_children():
		var r2 := _find_guide_target(c, id)
		if r2 != null:
			return r2
	return null

var _gate_timer: Timer = null

func _gate_ok(gate: String) -> bool:
	match gate:
		"hatched_dragon":
			return UserDB.has_hatched_dragon()
		_:
			push_warning("[tutorial] 모르는 게이트 '%s' — 통과 처리한다" % gate)
			return true

func _start_gate(gate: String) -> void:
	_gate_timer = Timer.new()
	_gate_timer.wait_time = 1.0
	_gate_timer.autostart = true
	_gate_timer.timeout.connect(func():
		if _gate_ok(gate):
			_pass_gate())
	add_child(_gate_timer)

func _stop_gate() -> void:
	if is_instance_valid(_gate_timer):
		_gate_timer.queue_free()
	_gate_timer = null

func _pass_gate() -> void:
	_stop_gate()
	_wait_target = null
	_run()

func _dispatch(st: Dictionary) -> void:
	var action := String(st.get("action", ""))
	match action:
		"":
			pass
		"enter_cave":
			if Scenes.current_state() != "cave":
				_blocked = true
				_box_wanted = false
				Scenes.goto("cave", {})
				await get_tree().process_frame
				_blocked = false
			_advance()
		"name_dragon":
			var cave := Scenes.current_scene()
			if cave != null and cave.has_method("_open_rename"):
				cave.call("_open_rename")
			else:
				push_warning("[tutorial] 이름짓기(`_open_rename`)를 못 찾았다 — 건너뛴다")
		"cutscene":
			_start_cutscene(st)
		"adventure":
			_start_tutorial_battle()
		"finish":
			_finish()
		_:
			push_warning("[tutorial] 미이식 스텝 동작 '%s' (%s) — 건너뛴다"
				% [action, String(_order[_i])])

func _start_cutscene(st: Dictionary) -> void:
	_blocked = true
	_box_wanted = false
	_clear_arrows()
	_clear_speaker()
	if not Scenes.state_changed.is_connected(_on_cutscene_done):
		Scenes.state_changed.connect(_on_cutscene_done)
	Scenes.goto("prologue", {
		"from": int(st.get("from", 0)), "to": int(st.get("to", 0)),
		"back": "worldmap", "back_params": Scenes.MAIN_PARAMS})

func _on_cutscene_done(from_s: String, _to_s: String) -> void:
	if from_s != "prologue":
		return
	Scenes.state_changed.disconnect(_on_cutscene_done)
	_blocked = false
	_advance()

func _start_tutorial_battle() -> void:
	var spec: Dictionary = Data.tutorial_flow.get("battle", {})
	var mid := int(spec.get("monster_id", 0))
	if mid <= 0:
		print("[tutorial] 튜토리얼 전투 ⚫보류(사용자 확정) — 상대가 정해지면 "
			+ "data/tutorial_flow.json `battle.monster_id` 에 넣으면 그대로 붙는다")
		_advance()
		return
	var enemy := Data.story_enemy_of(mid, int(spec.get("level", 1)))
	if enemy.is_empty():
		push_warning("[tutorial] 몬스터 %d 정의를 못 찾았다 — 전투를 건너뛴다" % mid)
		_advance()
		return
	_blocked = true
	_box_wanted = false
	_clear_arrows()
	if not Scenes.state_changed.is_connected(_on_scene_changed):
		Scenes.state_changed.connect(_on_scene_changed)
	Scenes.goto("battle", {"enemy": enemy, "back": "worldmap",
		"back_params": {"region": "yutakan"}})

func _on_scene_changed(from_s: String, _to_s: String) -> void:
	if from_s != "battle":
		return
	Scenes.state_changed.disconnect(_on_scene_changed)
	_blocked = false
	_advance()

func _advance() -> void:
	if _blocked:
		return
	_i += 1
	_run()

func _finish() -> void:
	_clear_arrows()
	_clear_speaker()
	if _live == self:
		_live = null
	UserDB.set_pmeta(DONE_KEY, true)
	UserDB.set_pmeta(STEP_KEY, "")
	finished.emit()
	queue_free()
