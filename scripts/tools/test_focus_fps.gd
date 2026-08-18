extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	assert(err == OK, "메인 씬을 열 수 있어야 함")
	await scene_changed
	var main := current_scene
	assert(main != null, "메인 씬이 생성되어야 함")
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(Engine.max_fps == 60, "비활성 창은 60 FPS여야 함")
	main._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(Engine.max_fps == 144, "활성 창은 144 FPS여야 함")
	print("[test_focus_fps] PASS — background=60, foreground=144")
	main.queue_free()
	await process_frame
	quit()
