extends Node

func _ready() -> void:
	await get_tree().process_frame
	UserDB.begin_batch()
	if not UserDB.has_user_nickname():
		UserDB.set_user_nickname("계란")

	for k in ["scroll_silver", "scroll_gold", "scroll_n5"]:
		UserDB.add_item(k, 5)
	for k in ["s_skillbook1", "s_skillbook3", "s_skillbook5"]:
		UserDB.add_item(k, 5)
	for lv in [1, 2, 3]:
		UserDB.add_item(Loadout.item_key(11, lv), 2)
	UserDB.add_item(Loadout.item_key(12, 5), 2)
	UserDB.add_item("level_up", 60)
	UserDB.add_item("bless_of_dragon", 10)

	var d := UserDB.add_dragon(54, 9)
	UserDB.set_active(int(d["uid"]))
	print("[SkillTestMode] Lv9 테스트 드래곤 uid=%d 생성 · 스킬 %d개(0이어야 정상)"
		% [int(d["uid"]), (UserDB.dragon_skills(int(d["uid"])) as Array).size()])
	print("[SkillTestMode] 스크롤/스킬아이템/Lv+1 지급 완료 — 디스크 미기록(begin_batch)")

	Scenes.goto("cave")
