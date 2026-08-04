extends Control
## 게임 진입점(render/app 최상위). 부팅 시 새 게임을 보장하고 초기 씬으로 전환한다.
## render→logic(NewGame)→data(Data) 단방향만 사용. (CLAUDE.md §10.2)

const FOREGROUND_FPS := 60
const BACKGROUND_FPS := 15

func _ready() -> void:
	_apply_focus_fps(DisplayServer.window_is_focused())
	Scenes.bind_root($SceneRoot)
	# 부팅 첫 화면 = **타이틀**(원작 `IntroScene` — 타이틀 스파인 + `music/bg_intro.mp3`).
	# 화면을 누르면 인트로가 `begin_new_game()` 을 부른다(원작 ccTouchBegan → LoadingLayer 자리).
	Scenes.goto("intro")

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_apply_focus_fps(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_apply_focus_fps(false)

func _apply_focus_fps(focused: bool) -> void:
	Engine.max_fps = FOREGROUND_FPS if focused else BACKGROUND_FPS

## 게임 시작 절차 = 초기 로드아웃 → **닉네임(최초 1회)** → (새 세이브면 프롤로그) → 메인 화면.
##
## 타이틀의 "화면을 터치해주세요"(`intro.gd`)와 **세이브 데이터 초기화 직후**
## (`SettingLayer::_do_reset` → `Scenes.goto("intro")` → 터치)가 이 하나를 같이 쓴다.
## 🔴 2026-07-31 수정 — 종전엔 이 단계들이 `_ready` 안에만 있어서, 게임을 켠 채로 세이브를
##    초기화하면 `UserDB.reset()` 이 빈 세이브를 만들어 놓고 아무도 다시 태우지 않았다.
## 🟦 2026-08-01 사용자 확정 — **닉네임을 먼저 확정하고 그 다음에 튜토리얼**이 시작된다.
##    종전엔 프롤로그를 먼저 띄우고 그 위에 닉네임 팝업을 얹어, 이름을 정하는 동안 이야기가
##    뒤에서 이미 시작돼 있었다.
func begin_new_game() -> void:
	# 반환값 true = 진행 중 세이브가 없어 초기 로드아웃을 방금 넣었다(= 갓 시작한 유저).
	var fresh: bool = NewGame.ensure(UserDB, Data.new_game_def())
	# 원작 User::getNickName 이 비어 있으면(=최초 실행) 이름부터 받는다.
	# NickNameLayer::create(true) 상당 — 취소 없이 확정해야 진행된다.
	# SceneRoot 가 아니라 최상위(self)에 붙여 씬 전환과 무관하게 떠 있게 한다.
	if not UserDB.has_user_nickname():
		NickNamePopup.open(self, true, func(_nick): _start_after_nickname(fresh))
		return
	_start_after_nickname(fresh)

## 닉네임이 확정된 뒤의 첫 화면.
func _start_after_nickname(fresh: bool) -> void:
	# 원작 메인 화면은 **WorldMapScene 의 유타칸 지역뷰(낮)** 다 — 양피지 전체지도
	# (`WorldMapFullLayer`)는 하단 메뉴 '월드맵'(tag 0x12)으로 따로 들어가는 화면이고,
	# 동굴도 하단 메뉴의 한 항목이다(`WorldMapScene::moveCave`, `menu_cave`).
	# 근거: 레퍼런스 `docs/ref/orig_image/old_screenshots/Yutakan_main.png` = 부팅 직후 화면 = 유타칸 섬.
	# 🔴 종전엔 `goto("worldmap")`(=overview 양피지)로 띄워 첫 화면이 원작과 달랐다(2026-07-28 수정).
	var main_params := {"region": "yutakan"}
	if fresh:
		# 갓 시작한 유저는 프롤로그부터(사용자 확정 2026-07-31). 원작 `<PrologueTalk0~33>` 이식본은
		# 이미 있었는데 아무도 부르지 않아 한 번도 보이지 않았다.
		# 프롤로그가 끝나면 **튜토리얼**(원작 시나리오 0 의 `SN_0_*` 상태기계)이 이어받는다.
		UserDB.set_pmeta(TutorialGuide.STEP_KEY, "")     # 처음부터
		UserDB.set_pmeta(TutorialGuide.DONE_KEY, false)
		Scenes.goto("prologue", {"back": "worldmap", "back_params": main_params,
			"then": "tutorial"})
	else:
		Scenes.goto("worldmap", main_params)
		_resume_tutorial()


# ── 튜토리얼(원작 시나리오 0 의 `SN_0_*` 상태기계) ────────────────────────────
# `Main` 이 소유해야 씬을 갈아타도 살아 있다 — `Scenes` 는 `$SceneRoot` 만 교체한다.
# 원작도 같은 구조다: `TutorialLayer`/`ScenarioLayer` 는 러닝 씬 위에 얹히는 레이어다.
var _tutorial: TutorialGuide = null

## 프롤로그가 끝나면 부른다(`prologue.gd` 가 `then: "tutorial"` 을 받았을 때).
func start_tutorial() -> void:
	if is_instance_valid(_tutorial):
		return
	_tutorial = TutorialGuide.start(self)

## 진행 중이던 튜토리얼을 다시 붙인다(껐다 켜도 이어진다).
func _resume_tutorial() -> void:
	if is_instance_valid(_tutorial):
		return
	_tutorial = TutorialGuide.resume(self)
