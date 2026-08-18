extends Node

func _ready() -> void:
	if not String(SaveSystem.save_dir).contains("test_save"):
		push_error("[seed] 실세이브로 돌고 있다 — 중단. 러너가 DV2_TEST_SAVE=1 을 걸어야 한다.")
		print("[seed] ABORT (실세이브)")
		get_tree().quit(1)
		return
	if UserDB.dragons().is_empty():
		UserDB.add_dragon(1, 20)
	UserDB.add_currency("gold", 200000)
	UserDB.add_currency("diamond", 500)
	UserDB.set_progress("scenario_1_0", true)
	UserDB.set_progress("story_mission_at_2", 0)
	UserDB.set_progress("story_sq_2", 0)
	UserDB.set_progress("scenario_2_0", false)
	UserDB.save()
	print("[seed] OK — 드래곤 %d마리 · 다음 회차 %d · 수행중 미션 %d"
		% [UserDB.dragons().size(), StoryProgress.next_episode(), StoryProgress.pending_episode()])
	get_tree().quit()
