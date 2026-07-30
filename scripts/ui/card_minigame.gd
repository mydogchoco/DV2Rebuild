extends Node
class_name CardMiniGame
## 탐험 카드 미니게임 — render 층(CLAUDE.md §8.1). 규칙은 `CardGame`(logic)이 갖고 있다.
##
## 원작 `CardMiniGameLayer` + `CardItem`. 포팅 카드 = `docs/ref/porting/CardMiniGame.md`.
##   · 딤 = `CCLayerColor(가시영역+200, 200)` @ (-100,-100) z=200 → 전체를 덮는다
##   · 카드 = `scene/adventure/card_game/card`(앞) / `card_back`(뒤), 152×214px
##   · 하트(남은 기회) = `heart_bg` + `heart_frame`
##   · 뒤집기 = `CardItem::setAnimationToFront/Back` + FinishTo*CallAction 콜백
##   · 오답 = `setShakeCard`, 짝 = `setLayerMatchAction`, 실패표시 = `fail`
##   · 효과음 `music/effect_card_in.mp3`
##
## 쓰는 곳: 어디서든 `CardMiniGame.open(parent, "match", on_done)`.
## `on_done.call(result)` — result = {"win": bool, "reward": Dictionary}
## 보상 **지급은 호출자 몫**이다(이 노드는 결과만 돌려준다).

const DIR := "card_game"
const SKEL := "skeleton_fortress"
const CARD_W := 152.0
const CARD_H := 214.0
const FLIP_SEC := 0.18          # 뒤집기 반바퀴
const HOLD_SEC := 0.55          # 두 장 보여 주는 시간
const SFX_FLIP := "effect_card_in"

var _cfg: Dictionary = {}
var _deck: Dictionary = {}
var _mode := "match"
var _on_done: Callable = Callable()
var _pma: CanvasItemMaterial
var _man: Dictionary = {}
var _layer: CanvasLayer
var _root: Control
var _cards: Array = []          # [{node, front, back, data, revealed, done}]
var _picked: Array = []         # 이번 기회에 뒤집은 카드 인덱스
var _chances := 0
var _busy := false
var _hearts: Array = []

## 부모에 붙여 바로 시작한다. mode = "match" | "avoid".
static func open(parent: Node, mode: String, on_done: Callable) -> CardMiniGame:
	var g := CardMiniGame.new()
	g._mode = mode
	g._on_done = on_done
	parent.add_child(g)
	return g

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_man = _manifest(DIR)
	_cfg = Data.card_game
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_deck = CardGame.make_deck(_mode, _cfg, rng)
	if _deck.is_empty():
		push_warning("[CardMiniGame] 덱 생성 실패 — data/card_game.json 확인")
		_finish(false, {})
		return
	_chances = int(_deck.get("chances", 1))
	_build()

# ── 화면 ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var vis := get_viewport().get_visible_rect().size
	_layer = CanvasLayer.new()
	_layer.layer = 80
	add_child(_layer)
	# 원작 딤(CCLayerColor). 전체를 덮고 아래 입력을 막는다.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	var title := _label("카드를 뒤집어 짝을 맞추세요" if _mode == "match" else "꽝을 피하세요",
		26, Color(1, 0.96, 0.86))
	title.size = Vector2(vis.x, 34)
	title.position = Vector2(0, vis.y * 0.12)
	_root.add_child(title)

	var cards: Array = _deck["cards"]
	# 격자 — 8장이면 4×2, 3장이면 3×1. 카드 원본 크기(152×214)에 화면에 맞는 배율.
	var cols: int = 4 if cards.size() > 4 else cards.size()
	var rows: int = int(ceil(float(cards.size()) / float(cols)))
	var s: float = minf(1.0, (vis.x * 0.78) / (cols * (CARD_W + 16.0)))
	var cw := CARD_W * s
	var ch := CARD_H * s
	var gap := 16.0 * s
	var gw := cols * cw + (cols - 1) * gap
	var gh := rows * ch + (rows - 1) * gap
	var x0 := (vis.x - gw) * 0.5 + cw * 0.5
	var y0 := vis.y * 0.52 - gh * 0.5 + ch * 0.5

	for i in cards.size():
		var cx := x0 + float(i % cols) * (cw + gap)
		var cy := y0 + float(i / cols) * (ch + gap)
		_cards.append(_make_card(i, cards[i], Vector2(cx, cy), s))

	_build_hearts(vis, s)

## 카드 1장 — 뒷면 스프라이트 + (숨겨 둔) 앞면. 뒤집기는 scale.x 로 한다.
func _make_card(idx: int, data: Dictionary, pos: Vector2, s: float) -> Dictionary:
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2(s, s)
	_root.add_child(holder)

	var back := _spr(DIR, "scene_adventure_card_game_card_back")
	if back: holder.add_child(back)
	var front := Node2D.new()
	front.visible = false
	holder.add_child(front)
	var face := _spr(DIR, "scene_adventure_card_game_card")
	if face: front.add_child(face)
	_decorate(front, data)

	var hit := Button.new()
	hit.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(st, empty)
	hit.size = Vector2(CARD_W, CARD_H) * s
	hit.position = pos - Vector2(CARD_W, CARD_H) * s * 0.5
	hit.pressed.connect(func(): _on_pick(idx))
	_root.add_child(hit)

	return {"holder": holder, "front": front, "back": back, "data": data,
		"hit": hit, "revealed": false, "done": false}

## 앞면 내용 — 보상 종류별 아이콘 + 라벨. 프레임은 원작 `CardItem` 이 부르는 것 그대로.
func _decorate(front: Node2D, data: Dictionary) -> void:
	var kind := String(data.get("kind", "none"))
	var icon: Sprite2D = null
	match kind:
		"none":
			icon = _spr(DIR, "scene_adventure_card_game_fail", 1.6)
		"heal":
			icon = _spr(DIR, "scene_adventure_card_game_heart_bg", 1.6)
		"buff_att":
			icon = _spr(SKEL, "scene_adventure_skeleton_fortress_buf_atk")
		"buff_def":
			icon = _spr(SKEL, "scene_adventure_skeleton_fortress_buf_def")
		"gold":
			icon = _spr("common_ui", "common_coin_small2", 1.2)
		"diamond":
			icon = _spr("common_ui", "common_diamond_big", 0.9)
		"egg":
			var t := Icons.dragon_egg_texture(int(data.get("dragon_id", 0)))
			if t != null:
				icon = Sprite2D.new(); icon.texture = t; icon.material = _pma
				icon.scale = Vector2(0.5, 0.5)
	if icon:
		icon.position = Vector2(0, -18)
		front.add_child(icon)
	var txt := String(data.get("label", ""))
	if kind == "gold" or kind == "diamond":
		txt = "%s %d" % [txt, int(data.get("amount", 0))]
	elif kind == "egg":
		txt = String(Data.get_dragon(int(data.get("dragon_id", 0))).get("name", txt))
	var l := _label(txt, 17, Color(0.24, 0.15, 0.05))
	l.size = Vector2(CARD_W, 22)
	l.position = Vector2(-CARD_W * 0.5, 62)
	front.add_child(l)

## 남은 기회 = 하트. 원작 heart_bg + heart_frame.
func _build_hearts(vis: Vector2, s: float) -> void:
	for h in _hearts:
		if is_instance_valid(h): h.queue_free()
	_hearts.clear()
	if _mode != "match":
		return
	var total := int((_cfg.get("games", {}) as Dictionary).get("match", {}).get("chances", 4))
	var pitch := 44.0
	var x0 := vis.x * 0.5 - (total - 1) * pitch * 0.5
	for i in total:
		var box := Node2D.new()
		box.position = Vector2(x0 + i * pitch, vis.y * 0.2)
		_root.add_child(box)
		var fr := _spr(DIR, "scene_adventure_card_game_heart_frame", 1.1)
		if fr: box.add_child(fr)
		var bg := _spr(DIR, "scene_adventure_card_game_heart_bg", 1.1)
		if bg:
			bg.modulate = Color(1, 1, 1, 1) if i < _chances else Color(0.25, 0.25, 0.25, 0.85)
			box.add_child(bg)
		_hearts.append(box)

# ── 진행 ────────────────────────────────────────────────────────────────────
func _on_pick(idx: int) -> void:
	if _busy or idx < 0 or idx >= _cards.size():
		return
	var c: Dictionary = _cards[idx]
	if bool(c["revealed"]) or bool(c["done"]):
		return
	_busy = true
	await _flip(c, true)
	_picked.append(idx)
	if _mode == "avoid":
		_resolve_avoid(idx)
		return
	if _picked.size() < 2:
		_busy = false
		return
	await get_tree().create_timer(HOLD_SEC).timeout
	_resolve_match()

func _resolve_avoid(idx: int) -> void:
	var d: Dictionary = (_cards[idx] as Dictionary)["data"]
	var win := String(d.get("kind", "none")) != "none"
	await get_tree().create_timer(HOLD_SEC).timeout
	_finish(win, d if win else {})

func _resolve_match() -> void:
	var a: Dictionary = _cards[_picked[0]]
	var b: Dictionary = _cards[_picked[1]]
	if CardGame.is_match(a["data"], b["data"]):
		a["done"] = true
		b["done"] = true
		# 원작 setLayerMatchAction — 맞은 카드를 강조하고 끝낸다(위키: 1번이라도 맞추면 성공).
		for n in [a, b]:
			var t := (n["holder"] as Node2D).create_tween()
			t.tween_property(n["holder"], "scale",
				(n["holder"] as Node2D).scale * 1.18, 0.18).set_trans(Tween.TRANS_BACK)
		await get_tree().create_timer(0.55).timeout
		_finish(true, a["data"])
		return
	# 안 맞으면 흔들고 되돌린다(setShakeCard → setAllCardRecoverIfNotMatch).
	for n in [a, b]:
		await _shake(n["holder"])
	for n in [a, b]:
		await _flip(n, false)
	_picked.clear()
	_chances -= 1
	_build_hearts(get_viewport().get_visible_rect().size, 1.0)
	if _chances <= 0:
		_finish(false, {})
		return
	_busy = false

func _flip(c: Dictionary, to_front: bool) -> void:
	Bgm.sfx(SFX_FLIP)
	var h: Node2D = c["holder"]
	var full: Vector2 = h.scale
	var t := h.create_tween()
	t.tween_property(h, "scale:x", 0.0, FLIP_SEC)
	await t.finished
	if not is_instance_valid(h):
		return
	c["revealed"] = to_front
	(c["front"] as Node2D).visible = to_front
	if c["back"] != null and is_instance_valid(c["back"]):
		(c["back"] as Sprite2D).visible = not to_front
	var t2 := h.create_tween()
	t2.tween_property(h, "scale:x", full.x, FLIP_SEC)
	await t2.finished

func _shake(h: Node2D) -> void:
	if not is_instance_valid(h):
		return
	var x := h.position.x
	var t := h.create_tween()
	for d in [-8.0, 8.0, -5.0, 5.0, 0.0]:
		t.tween_property(h, "position:x", x + d, 0.05)
	await t.finished

func _finish(win: bool, reward: Dictionary) -> void:
	_busy = true
	if is_instance_valid(_layer):
		_layer.queue_free()
	var cb := _on_done
	_on_done = Callable()
	if cb.is_valid():
		cb.call({"win": win, "reward": reward})
	queue_free()

# ── helpers ─────────────────────────────────────────────────────────────────
func _manifest(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
