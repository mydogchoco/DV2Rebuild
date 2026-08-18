class_name NpcPortrait
extends Node2D

const EYE_FAST := 0.1
const EYE_HOLD := 3.0
const MOUTH_STEP := 0.03
const FIRST_DELAY := 0.15

var npc_name: String = ""
var emotion: int = 1
var _body: Sprite2D
var _eye: Sprite2D
var _mouth: Sprite2D
var _man: Dictionary = {}
var _dir: String = ""
var _body_key: String = ""
var _art_emo: int = 1
var _eye_tl := Vector2.ZERO
var _mouth_tl := Vector2.ZERO
var _eye_fr: Array = []
var _mouth_fr: Array = []
var _eye_i := 0
var _mouth_i := 0
var _eye_next := FIRST_DELAY
var _mouth_next := FIRST_DELAY
var _t := 0.0
var _talking := false
var _rest_mouth := 0

static func create(npc: String, emotion_idx := 1, body_index := 1) -> NpcPortrait:
	var n := NpcPortrait.new()
	n.npc_name = npc
	n.emotion = emotion_idx
	n._build(body_index)
	return n

static func _nearest(nums: Array, want: int) -> int:
	nums.sort()
	var best: int = nums[0]
	for v in nums:
		if absi(int(v) - want) < absi(best - want):
			best = int(v)
	return best

func _build(body_index: int) -> void:
	_dir = "npc_%s" % npc_name
	_man = _manifest(_dir)
	if _man.is_empty():
		push_warning("[NpcPortrait] 매니페스트 없음: %s" % _dir)
		return
	var bkey := "npc_%s_body_%d" % [npc_name, body_index]
	if not _man.has(bkey):
		bkey = "npc_%s_body_1" % npc_name
	_body_key = bkey
	_body = _sprite(bkey, Design.ASSET_SCALE)
	if _body == null:
		return
	var bh: float = float(_man[bkey].get("h", 0)) * Design.ASSET_SCALE
	_body.position = Vector2(0, -bh * 0.5)
	add_child(_body)

	_art_emo = _resolve_art_emotion()
	_eye_fr = _frames("eye", _art_emo)
	_mouth_fr = _frames("mouth", _art_emo)
	_drop_duplicate_mouth()
	var pos := _face_pos()
	_eye = _attach_part("eye", pos.get("eye", null))
	_mouth = _attach_part("mouth", pos.get("mouth", null))

func _drop_duplicate_mouth() -> void:
	if _eye_fr.is_empty() or _mouth_fr.is_empty():
		return
	var er := _region_of("eye", _eye_fr[0])
	var mr := _region_of("mouth", _mouth_fr[0])
	if er != Rect2() and er == mr:
		_mouth_fr = []

func _region_of(slot: String, frame: int) -> Rect2:
	var key := "npc_%s_%s_%d_%d" % [npc_name, slot, _art_emo, frame]
	var path := "res://assets/converted/%s/%s.tres" % [_dir, key]
	if not ResourceLoader.exists(path):
		return Rect2()
	var t := load(path)
	return (t as AtlasTexture).region if t is AtlasTexture else Rect2()

func set_emotion(e: int) -> void:
	if e <= 0 or e == emotion or _body == null:
		return
	if _man.has("npc_%s_body_%d" % [npc_name, e]) and _body_key != "npc_%s_body_%d" % [npc_name, e]:
		return
	if _frames("eye", e).is_empty() and _frames("mouth", e).is_empty():
		return
	emotion = e
	for part in [_eye, _mouth]:
		if part != null:
			_body.remove_child(part)
			part.queue_free()
	_eye = null
	_mouth = null
	_art_emo = _resolve_art_emotion()
	_eye_fr = _frames("eye", _art_emo)
	_mouth_fr = _frames("mouth", _art_emo)
	_drop_duplicate_mouth()
	_eye_i = 0
	_mouth_i = 0
	_eye_next = _t + FIRST_DELAY
	_mouth_next = _t + FIRST_DELAY
	var pos := _face_pos()
	_eye = _attach_part("eye", pos.get("eye", null))
	_mouth = _attach_part("mouth", pos.get("mouth", null))

func _face_pos() -> Dictionary:
	var all: Dictionary = Data.npc_face.get("npc", {})
	var per: Dictionary = all.get(npc_name, {})
	if per.is_empty():
		return {}
	for key in [str(emotion), "?"]:
		if per.has(key):
			return per[key]
	var nums: Array = []
	for k in per.keys():
		if String(k).is_valid_int():
			nums.append(int(k))
	if nums.is_empty():
		return per.values()[0]
	return per[str(_nearest(nums, emotion))]

func _resolve_art_emotion() -> int:
	var have: Array = []
	for e in range(1, 10):
		if not _frames("eye", e).is_empty() or not _frames("mouth", e).is_empty():
			have.append(e)
	if have.is_empty() or emotion in have:
		return emotion
	return _nearest(have, emotion)

func _frames(slot: String, emo: int) -> Array:
	var out: Array = []
	for f in range(1, 4):
		if _man.has("npc_%s_%s_%d_%d" % [npc_name, slot, emo, f]):
			out.append(f)
	return out

func _attach_part(slot: String, slot_pos) -> Sprite2D:
	if _body == null or slot_pos == null or not (slot_pos is Array):
		return null
	var frames: Array = _eye_fr if slot == "eye" else _mouth_fr
	if frames.is_empty():
		return null
	if is_zero_approx(float(slot_pos[0])) and is_zero_approx(float(slot_pos[1])):
		push_warning("[NpcPortrait] %s/%s 좌표 미추출(0,0) — 미표시" % [npc_name, slot])
		return null
	var key := "npc_%s_%s_%d_%d" % [npc_name, slot, _art_emo, frames[0]]
	var s := _sprite(key, 1.0)
	if s == null:
		return null
	var bi: Dictionary = _man.get(_body_key, {})
	var S := Design.ASSET_SCALE
	var tl := Vector2(
		float(slot_pos[0]) / S - float(bi.get("w", 0)) * 0.5,
		float(slot_pos[1]) / S - float(bi.get("h", 0)) * 0.5)
	tl += _nudge(slot) / S
	if slot == "eye":
		_eye_tl = tl
	else:
		_mouth_tl = tl
	_body.add_child(s)
	_place(s, key, tl)
	return s

func _nudge(slot: String) -> Vector2:
	var nd = (Data.npc_face.get("nudge", {}) as Dictionary).get(npc_name, null)
	if nd is Array:
		return Vector2(float(nd[0]), float(nd[1])) if (nd as Array).size() >= 2 else Vector2.ZERO
	if not (nd is Dictionary):
		return Vector2.ZERO
	var bkey := _body_key.trim_prefix("npc_%s_" % npc_name)
	var total := Vector2.ZERO
	for bk in [bkey, "*"]:
		var per = (nd as Dictionary).get(bk, null)
		if not (per is Dictionary):
			continue
		for sk in [slot, "*"]:
			var v = (per as Dictionary).get(sk, null)
			if v is Array and (v as Array).size() >= 2:
				total += Vector2(float(v[0]), float(v[1]))
	return total

func _place(spr: Sprite2D, key: String, tl: Vector2) -> void:
	var info: Dictionary = _man.get(key, {})
	var src: Array = info.get("src", [info.get("w", 0), info.get("h", 0)])
	var off: Array = info.get("off", [0, 0])
	spr.position = tl + Vector2(
		float(src[0]) * 0.5 + float(off[0]),
		float(src[1]) * 0.5 - float(off[1]))

func set_talking(on: bool) -> void:
	_talking = on
	_mouth_next = _t + FIRST_DELAY
	if not on and not _mouth_fr.is_empty():
		var want: int = _rest_mouth if _mouth_fr.has(_rest_mouth) else int(_mouth_fr[0])
		_mouth_i = maxi(_mouth_fr.find(want), 0)
		_set_frame(_mouth, "mouth", want)

func set_rest_mouth(frame: int) -> void:
	_rest_mouth = frame
	if not _talking:
		set_talking(false)

func _process(delta: float) -> void:
	_t += delta
	if _eye != null and _eye_fr.size() > 1 and _t >= _eye_next:
		_eye_i = (_eye_i + 1) % _eye_fr.size()
		_set_frame(_eye, "eye", _eye_fr[_eye_i])
		_eye_next = _t + _eye_delay()
	if _mouth != null and _talking and _mouth_fr.size() > 1 and _t >= _mouth_next:
		_mouth_i = (_mouth_i + 1) % _mouth_fr.size()
		_set_frame(_mouth, "mouth", _mouth_fr[_mouth_i])
		_mouth_next = _t + _mouth_delay()

func _eye_delay() -> float:
	if _eye_i != 0:
		return randf() * EYE_FAST
	var r := randf() * EYE_HOLD
	return r + 0.2 if r < 0.3 else r

func _mouth_delay() -> float:
	var r := randf() * MOUTH_STEP
	return r + 0.05 if r < 0.1 else r

func _set_frame(spr: Sprite2D, slot: String, frame: int) -> void:
	if spr == null:
		return
	var key := "npc_%s_%s_%d_%d" % [npc_name, slot, _art_emo, frame]
	if not _man.has(key):
		return
	var p := "res://assets/converted/%s/%s.tres" % [_dir, key]
	if not ResourceLoader.exists(p):
		return
	spr.texture = load(p)
	_place(spr, key, _eye_tl if slot == "eye" else _mouth_tl)

static func has_art(npc: String) -> bool:
	return npc != "" and not _manifest("npc_%s" % npc).is_empty()

static func _manifest(dir: String) -> Dictionary:
	var p := "res://assets/converted/%s/_manifest.json" % dir
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _sprite(key: String, scale: float) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [_dir, key]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.scale = Vector2(scale, scale)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	s.material = m
	return s

func body_width() -> float:
	if _body == null:
		return 0.0
	return float(_body.texture.get_width()) * Design.ASSET_SCALE

func body_height() -> float:
	if _body == null:
		return 0.0
	return float(_body.texture.get_height()) * Design.ASSET_SCALE
