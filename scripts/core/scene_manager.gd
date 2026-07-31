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
	# 부팅 첫 화면 — 원작 IntroScene(타이틀 스파인 + bg_intro + "화면을 터치해주세요").
	"intro": "res://scenes/intro.tscn",
	"cave": "res://scenes/cave.tscn",
	"town": "res://scenes/town.tscn",
	"worldmap": "res://scenes/worldmap.tscn",
	"adventure": "res://scenes/adventure.tscn",
	"battle": "res://scenes/battle.tscn",
	"breeding": "res://scenes/breeding.tscn",
	"shop": "res://scenes/shop.tscn",
	# 엘피스 시설(원작 클래스명으로 등록)
	"magicshop": "res://scenes/magicshop.tscn",   # 점술집 — MagicShopScene
	# 임프상인 — ImpShopScene. **밤에만** 월드맵에서 진입(원작 <NightTutorial_talk12>
	# "낮에는 방랑상인이 가끔 서 있던 곳에 밤에는 임프상인이 항상 서 있어").
	"imp_shop": "res://scenes/imp_shop.tscn",
	"laboratory": "res://scenes/laboratory.tscn", # 연구소 — LaboratoryScene
	"mamorudiclab": "res://scenes/mamorudiclab.tscn", # 우노 마모루딕 연구소 — DragonAwaken
	"promote": "res://scenes/promote.tscn",       # 육성(훈련·교배·하늘둥지) — PromoteScene
	# 스토리(시나리오) 재생 — 원작 ScenarioLayer + ScenarioTextBox
	"story": "res://scenes/story.tscn",
	# 프롤로그 — 원작 <PrologueTalk0~33> + scenario/prologue 삽화
	"prologue": "res://scenes/prologue.tscn",
}

# 허용 전환표(상태기계). from에 키가 없으면 모든 전환 허용(규칙 미정의).
# 화면이 늘면 여기에 모드별 진입 가능 경로를 채운다.
const TRANSITIONS := {
	# 타이틀에서 나가는 길만 있다(원작도 `ccTouchBegan` → LoadingLayer → 게임 한 방향).
	# 새 세이브면 프롤로그를 거치고(사용자 확정 2026-07-31), 아니면 바로 메인 화면.
	"intro": ["worldmap", "prologue", "cave"],
	# 위계: **worldmap = 메인 허브**(원작 WorldMapScene) → town → cave.
	#   던전: worldmap → adventure(탐험) → battle(조우) → adventure → worldmap.
	# 원작 `WorldMapScene::onClickMenu` 는 메인 메뉴에서 상점/점술집/연구소로 **직접** 간다
	#   (tag 0x16=ShopScene · 0x15=MagicShopScene · 0x1d=PremiumShopScene, docs/ref/orig_code/decomp/WorldMapScene.c:10485~).
	#   마을을 거치던 종전 경로는 우리 임의 제약이었으므로 원작대로 푼다(마을 경로는 유지).
	"cave": ["town", "worldmap", "breeding", "promote", "story"],
	"town": ["cave", "worldmap", "shop", "magicshop", "laboratory", "promote", "story"],
	"breeding": ["cave", "worldmap"],
	"shop": ["town", "worldmap"],
	"magicshop": ["town", "worldmap"],
	"imp_shop": ["worldmap"],
	"laboratory": ["town", "worldmap"],
	"mamorudiclab": ["worldmap"],
	"promote": ["worldmap", "town", "cave"],
	# worldmap→worldmap = 지역 갈아타기(원작 `WorldMapScene::moveMap(int)`). 자기 자신도 허용.
	"worldmap": ["worldmap", "town", "cave", "battle", "adventure", "mamorudiclab", "story",
		"prologue", "shop", "magicshop", "laboratory", "breeding", "promote", "imp_shop"],
	# 프롤로그는 인트로라 끝나면 메인(월드맵)/동굴로만 나간다.
	"prologue": ["worldmap", "cave"],
	"adventure": ["battle", "worldmap", "story"],
	"battle": ["worldmap", "cave", "adventure", "story"],
	# 스토리는 어디서든 열리고(마을·동굴·던전 진입) 끝나면 부른 곳으로 돌아간다.
	"story": ["worldmap", "cave", "town", "adventure", "battle"],
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
	# 구역 앰비언트(원작 setWorldMapSound)는 **씬 소유**다 — 전환할 때 무조건 끊는다.
	# 새 씬이 필요하면 자기 _ready 에서 다시 `Bgm.area_setup()` 한다.
	# 🔴 2026-07-28: 이게 없어서 월드맵의 파도/폭포 소리가 상점·연구소·육성·스토리까지
	#    따라다니며 게임 내내 재생됐다(사용자 검수).
	Bgm.area_clear()
	if is_instance_valid(_current_scene):
		_current_scene.queue_free()
	# 🔴 2026-07-27 순서 수정: **enter(params)를 트리 편입 전에** 부른다.
	#   각 씬은 `enter`에서 `_params`만 받고 `if _pma != null: _rebuild()` 로 가드하며,
	#   실제 빌드는 `_ready`(=트리 안, `_vis()` 사용 가능)에서 한다.
	#   종전 순서(add_child → enter)는 `_ready` 가 **빈 params 로 1회** 빌드한 뒤
	#   `enter` 가 **다시** 빌드해 모든 씬이 두 번 지어졌다. 실제 사고 2건:
	#     · battle — 1차 빌드의 `_play_events()` 코루틴이 살아남아 2차 이벤트 배열을
	#       같이 재생 → 뷰 HP가 **두 배로 깎여** "몬스터 HP 0인데 안 죽음"
	#     · adventure — 1차 자식들이 `queue_free()` 대기(프레임 끝) 중에 2차가 지어져
	#       `move_child(walk, 1)` 이 걷기 배경 사본을 **정지 배경 아래**로 넣음 → 배회가 안 보임
	#   ⚠️ 그래서 `enter` 본문에서는 트리 의존 API(get_tree/get_viewport)를 쓰면 안 된다.
	var prev := _state
	_current_scene = inst      # enter/_ready 안에서 current_scene()·current_state() 가 새 씬을 보게
	_state = state
	if inst.has_method("enter"):
		inst.enter(params)
	_root.add_child(inst)
	state_changed.emit(prev, state)
	return true

func _allowed(from_s: String, to_s: String) -> bool:
	# 타이틀로 돌아가는 길은 **어디서나** 열려 있다 — 유일한 경로가 세이브 초기화
	# (`SettingLayer::_do_reset`)이고, 그건 곧 게임 재시작이라 위계를 따질 대상이 아니다.
	# (설정창은 메인 HUD 어디서든 열리므로 from 을 일일이 적으면 빠뜨린다.)
	if to_s == "intro":
		return true
	if not TRANSITIONS.has(from_s):
		return true   # 규칙 미정의 → 허용
	return to_s in TRANSITIONS[from_s]
