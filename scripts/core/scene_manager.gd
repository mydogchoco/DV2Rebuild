extends Node

signal state_changed(from_state: String, to_state: String)

const MAIN_PARAMS := {"region": "yutakan"}

const REGISTRY := {
	"intro": "res://scenes/intro.tscn",
	"cave": "res://scenes/cave.tscn",
	"town": "res://scenes/town.tscn",
	"worldmap": "res://scenes/worldmap.tscn",
	"adventure": "res://scenes/adventure.tscn",
	"battle": "res://scenes/battle.tscn",
	"breeding": "res://scenes/breeding.tscn",
	"shop": "res://scenes/shop.tscn",
	"magicshop": "res://scenes/magicshop.tscn",
	"imp_shop": "res://scenes/imp_shop.tscn",
	"laboratory": "res://scenes/laboratory.tscn",
	"mamorudiclab": "res://scenes/mamorudiclab.tscn",
	"colosseum": "res://scenes/colosseum.tscn",
	"fight": "res://scenes/fight.tscn",
	"promote": "res://scenes/promote.tscn",
	"story": "res://scenes/story.tscn",
	"prologue": "res://scenes/prologue.tscn",
}

const TRANSITIONS := {
	"intro": ["worldmap", "prologue", "cave"],
	"cave": ["town", "worldmap", "breeding", "promote", "story", "prologue"],
	"town": ["cave", "worldmap", "shop", "magicshop", "laboratory", "promote", "story"],
	"breeding": ["cave", "worldmap"],
	"shop": ["town", "worldmap"],
	"magicshop": ["town", "worldmap"],
	"imp_shop": ["worldmap"],
	"laboratory": ["town", "worldmap"],
	"mamorudiclab": ["worldmap"],
	"colosseum": ["worldmap", "fight"],
	"fight": ["colosseum"],
	"promote": ["worldmap", "town", "cave"],
	"worldmap": ["worldmap", "town", "cave", "battle", "adventure", "mamorudiclab", "story",
		"prologue", "shop", "magicshop", "laboratory", "breeding", "promote", "imp_shop",
		"colosseum"],
	"prologue": ["worldmap", "cave"],
	"adventure": ["battle", "worldmap", "story", "shop"],
	"battle": ["worldmap", "cave", "adventure", "story"],
	"story": ["worldmap", "cave", "town", "adventure", "battle"],
}

var _root: Node = null
var _current_scene: Node = null
var _state: String = ""

var story_backdrop: Texture2D = null

const _SNAP_STATES := ["story", "prologue"]

func bind_root(root: Node) -> void:
	_root = root

func current_state() -> String:
	return _state

func current_scene() -> Node:
	return _current_scene

func goto_main(extra: Dictionary = {}) -> bool:
	var p := MAIN_PARAMS.duplicate()
	for k in extra:
		p[k] = extra[k]
	return goto("worldmap", p)

func goto(state: String, params: Dictionary = {}) -> bool:
	if _root == null:
		push_error("[Scenes] root 미바인딩 — 최상위 씬에서 bind_root() 필요"); return false
	if not REGISTRY.has(state):
		push_error("[Scenes] 미등록 상태: " + state); return false
	if _state != "" and not _allowed(_state, state):
		push_error("[Scenes] 허용되지 않은 전환: %s → %s" % [_state, state]); return false
	var packed = load(REGISTRY[state])
	if packed == null:
		push_error("[Scenes] 씬 로드 실패: " + REGISTRY[state]); return false
	var inst = packed.instantiate()
	Bgm.area_clear()
	if state in _SNAP_STATES and _state != "" and _state not in _SNAP_STATES:
		story_backdrop = _grab_frame()
	if is_instance_valid(_current_scene):
		_current_scene.queue_free()
	var prev := _state
	_current_scene = inst
	_state = state
	if inst.has_method("enter"):
		inst.enter(params)
	_root.add_child(inst)
	state_changed.emit(prev, state)
	return true

func _grab_frame() -> Texture2D:
	if _root == null or not _root.is_inside_tree():
		return null
	var vp := _root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

func _allowed(from_s: String, to_s: String) -> bool:
	if to_s == "intro":
		return true
	if not TRANSITIONS.has(from_s):
		return true
	return to_s in TRANSITIONS[from_s]
