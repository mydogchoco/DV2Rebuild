extends Node
## Autoload "Scenes": 명시적 씬/상태 기계. (CLAUDE.md §10.4)
## 게임 모드(cave/worldmap/battle/menu 등) 전환을 한 곳에서 관리한다.
## ⚠️ 씬끼리 서로를 직접 load/instantiate 하지 않는다 — 전환은 반드시 Scenes.goto()로.
##
## 사용: 최상위 씬(main.tscn)이 _ready에서 bind_root($SceneRoot) 후 goto("cave").
## 새 씬에 enter(params: Dictionary) 메서드가 있으면 전환 시 호출해 인자를 전달한다.

signal state_changed(from_state: String, to_state: String)

# 상태(게임 모드) → 씬 경로. 화면을 추가하면 여기 등록.
const REGISTRY := {
	"cave": "res://scenes/cave.tscn",
	# "worldmap": "res://scenes/worldmap.tscn",
	# "battle": "res://scenes/battle.tscn",
}

# 허용 전환표(상태기계). from에 키가 없으면 모든 전환 허용(규칙 미정의).
# 화면이 늘면 여기에 모드별 진입 가능 경로를 채운다.
const TRANSITIONS := {
	# "cave": ["worldmap", "battle"],
	# "worldmap": ["cave", "battle"],
	# "battle": ["cave", "worldmap"],
}

var _root: Node = null            # 현재 씬이 들어갈 컨테이너(main.tscn이 등록)
var _current_scene: Node = null
var _state: String = ""

## 현재 씬이 부착될 컨테이너 등록(최상위 씬에서 1회 호출).
func bind_root(root: Node) -> void:
	_root = root

func current_state() -> String:
	return _state

func current_scene() -> Node:
	return _current_scene

## state로 전환. params는 새 씬의 enter(params)로 전달(메서드가 있으면).
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
	if is_instance_valid(_current_scene):
		_current_scene.queue_free()
	_root.add_child(inst)
	_current_scene = inst
	var prev := _state
	_state = state
	if inst.has_method("enter"):
		inst.enter(params)
	state_changed.emit(prev, state)
	return true

func _allowed(from_s: String, to_s: String) -> bool:
	if not TRANSITIONS.has(from_s):
		return true   # 규칙 미정의 → 허용
	return to_s in TRANSITIONS[from_s]
