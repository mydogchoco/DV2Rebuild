extends Node

func _ready() -> void:
	var fails := 0
	fails += _hatch_counts()
	fails += _mission_state_follows_counter()
	if fails == 0:
		print("[test_quest_count] ALL PASS")
	else:
		print("[test_quest_count] %d FAIL" % fails)
	get_tree().quit()

func _hatch_counts() -> int:
	var fails := 0
	var before := UserDB.quest_count("hatches")
	var egg := UserDB.add_egg(1, 7.0, 0)
	var uid := int(egg["uid"])
	if not UserDB.is_egg(UserDB.get_dragon(uid)):
		print("  FAIL 알이 알 상태로 안 들어갔다"); fails += 1
	if not UserDB.hatch_egg(uid, {}):
		print("  FAIL hatch_egg 가 실패했다(남은 시간 0인데)"); fails += 1
	if UserDB.is_egg(UserDB.get_dragon(uid)):
		print("  FAIL 부화 뒤에도 알 상태다"); fails += 1
	var after := UserDB.quest_count("hatches")
	if after != before + 1:
		print("  FAIL 부화했는데 'hatches' 가 %d → %d (기대 %d)" % [before, after, before + 1])
		fails += 1
	else:
		print("  ok  동굴 둥지 부화 → hatches %d → %d" % [before, after])
	_drop_dragon(uid)
	_set_count("hatches", before)
	return fails

func _mission_state_follows_counter() -> int:
	var fails := 0
	var key := "feeds"
	var goal := 3
	var before := UserDB.quest_count(key)
	var was_accepted := UserDB.quest_accepted(key)

	UserDB.accept_quest(key)
	if UserDB.quest_progress(key) != 0:
		print("  FAIL 수락 직후 진행도가 0이 아니다: ", UserDB.quest_progress(key)); fails += 1
	for i in goal:
		UserDB.bump_quest(key)
	var prog := UserDB.quest_progress(key)
	if prog < goal:
		print("  FAIL %d회 먹였는데 진행도 %d/%d" % [goal, prog, goal]); fails += 1
	else:
		print("  ok  먹이 %d회 → 진행도 %d/%d (보상 대기)" % [goal, prog, goal])

	_set_count(key, before)
	UserDB.giveup_quest(key)
	for i in goal:
		UserDB.bump_quest(key)
	UserDB.accept_quest(key)
	if UserDB.quest_progress(key) != 0:
		print("  FAIL 수락 전 증가분이 진행도에 섞였다: ", UserDB.quest_progress(key)); fails += 1

	_set_count(key, before)
	_clear_flags(key, was_accepted)
	return fails

func _drop_dragon(uid: int) -> void:
	var arr: Array = UserDB.raw().get("dragons", [])
	for i in range(arr.size() - 1, -1, -1):
		if int((arr[i] as Dictionary).get("uid", 0)) == uid:
			arr.remove_at(i)

func _set_count(key: String, n: int) -> void:
	var q: Dictionary = UserDB.raw().get("meta", {}).get("quests", {})
	if q.is_empty():
		return
	q[key] = n

func _clear_flags(key: String, was_accepted: bool) -> void:
	var q: Dictionary = UserDB.raw().get("meta", {}).get("quests", {})
	if q.is_empty():
		return
	q.erase("gaveup_" + key)
	if was_accepted:
		q["accepted_" + key] = true
	else:
		q.erase("accepted_" + key)
		q.erase("base_" + key)
