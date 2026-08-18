extends Node

const PREFIXES := ["scenario_", "story_sq_", "story_mission_at_", "story_reward_"]

func _ready() -> void:
	var apply := "--apply" in OS.get_cmdline_user_args()
	print("[story-reset] 모드=%s  세이브=%s" % [SaveSystem.mode, SaveSystem.save_dir])
	if apply and SaveSystem.mode != "normal":
		push_error("[story-reset] 실세이브가 아니다 — 러너가 DV2_REAL_SAVE=1 을 안 걸었다")
		print("[story-reset] ABORT")
		get_tree().quit(1)
		return

	var progress: Dictionary = UserDB.raw().get("progress", {})
	var hit: Array[String] = []
	for k in progress.keys():
		var key := String(k)
		for p in PREFIXES:
			if key.begins_with(p):
				hit.append(key)
				break
	hit.sort()

	print("[story-reset] progress 전체 %d키 중 스토리 키 %d개" % [progress.size(), hit.size()])
	for p in PREFIXES:
		var group := hit.filter(func(k: String) -> bool: return k.begins_with(p))
		print("[story-reset]   %-20s %d개%s"
			% [p + "*", group.size(),
				("  ex) " + ", ".join(group.slice(0, 8))) if not group.is_empty() else ""])
	var seen_eps := hit.filter(func(k: String) -> bool: return k.begins_with("scenario_"))
	if not seen_eps.is_empty():
		print("[story-reset]   열람 기록 회차: %s" % ", ".join(seen_eps))

	if not apply:
		print("[story-reset] 덤프만 했다(쓰기 없음). 지우려면 --apply.")
		print("[story-reset] OK")
		get_tree().quit()
		return

	if hit.is_empty():
		print("[story-reset] 지울 것이 없다 — 이미 미시작 상태다.")
		print("[story-reset] OK")
		get_tree().quit()
		return

	var src := String(SaveSystem.save_dir).path_join("save_0.json")
	var dst := String(SaveSystem.save_dir).path_join(
		"save_0.pre_story_reset.%d.json" % int(Time.get_unix_time_from_system()))
	var fin := FileAccess.open(src, FileAccess.READ)
	if fin == null:
		push_error("[story-reset] 세이브를 못 읽었다: %s" % src)
		print("[story-reset] ABORT")
		get_tree().quit(1)
		return
	var blob := fin.get_buffer(fin.get_length())
	fin.close()
	var fout := FileAccess.open(dst, FileAccess.WRITE)
	if fout == null:
		push_error("[story-reset] 백업을 못 썼다: %s" % dst)
		print("[story-reset] ABORT")
		get_tree().quit(1)
		return
	fout.store_buffer(blob)
	fout.close()
	print("[story-reset] 백업 → %s (%d바이트)" % [dst, blob.size()])

	for k in hit:
		progress.erase(k)
	UserDB.save()

	var left := 0
	for k in (UserDB.raw().get("progress", {}) as Dictionary).keys():
		for p in PREFIXES:
			if String(k).begins_with(p):
				left += 1
				break
	print("[story-reset] 지운 키 %d개 · 남은 스토리 키 %d개" % [hit.size(), left])
	print("[story-reset] 다음 회차=%d · 1화 잠김해제=%s · 2화 잠김해제=%s"
		% [StoryProgress.next_episode(), StoryProgress.unlocked(1), StoryProgress.unlocked(2)])
	print("[story-reset] OK")
	get_tree().quit()
