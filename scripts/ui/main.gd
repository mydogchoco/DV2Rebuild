extends Control

const FOREGROUND_FPS := 144
const BACKGROUND_FPS := 60

func _ready() -> void:
	_init_focus_fps()
	Scenes.bind_root($SceneRoot)
	Scenes.goto("intro")

func _init_focus_fps() -> void:
	_apply_focus_fps(true)
	await get_tree().process_frame
	_apply_focus_fps(DisplayServer.window_is_focused())

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_apply_focus_fps(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_apply_focus_fps(false)

func _apply_focus_fps(focused: bool) -> void:
	Engine.max_fps = FOREGROUND_FPS if focused else BACKGROUND_FPS

func begin_new_game() -> void:
	var fresh: bool = NewGame.ensure(UserDB, Data.new_game_def())
	if not UserDB.has_user_nickname():
		RenameDialog.open(self, true, func(_nick): _start_after_nickname(fresh))
		return
	_start_after_nickname(fresh)

func _start_after_nickname(fresh: bool) -> void:
	var main_params := Scenes.MAIN_PARAMS.duplicate()
	if fresh:
		UserDB.set_pmeta(TutorialGuide.STEP_KEY, "")
		UserDB.set_pmeta(TutorialGuide.DONE_KEY, false)
		UserDB.set_pmeta("yutakan_night", false)
		UserDB.set_pmeta("kades_space", false)
		Scenes.goto("worldmap", main_params)
		start_tutorial()
	else:
		Scenes.goto_main()
		_resume_tutorial()

var _tutorial: TutorialGuide = null

func start_tutorial() -> void:
	if is_instance_valid(_tutorial):
		return
	_tutorial = TutorialGuide.start(self)

func _resume_tutorial() -> void:
	if is_instance_valid(_tutorial):
		return
	_tutorial = TutorialGuide.resume(self)
