extends Node
## 검수용 임시 오토로드 — 스킬 습득 흐름(에자녹 스크롤 + 레벨 10·25·45 자동 습득)을
## 바로 만져볼 수 있는 상태로 게임을 띄운다.
##
## 켜는 법: project.godot [autoload] 에 아래 한 줄을 넣고 실행, 확인 뒤 다시 지운다.
##   SkillTestMode="*res://scripts/tools/skill_test_mode.gd"
##
## ⚠️ `UserDB.begin_batch()` 로 **디스크에 쓰지 않는다** — 여기서 준 아이템·드래곤은
##    창을 닫으면 사라지고 사용자 세이브는 그대로다.

func _ready() -> void:
	await get_tree().process_frame
	UserDB.begin_batch()
	if not UserDB.has_user_nickname():
		UserDB.set_user_nickname("계란")

	# ① 에자녹 스크롤 — 무작위 3종 + 선택 2종
	for k in ["scroll_silver", "scroll_gold", "scroll_n5"]:
		UserDB.add_item(k, 5)
	for k in ["s_skillbook1", "s_skillbook3", "s_skillbook5"]:
		UserDB.add_item(k, 5)
	# ② 이미 만들어진 스킬 아이템(가방 '스킬' 탭에서 바로 사용 가능)
	UserDB.add_item(Loadout.item_key(11, 3), 3)
	UserDB.add_item(Loadout.item_key(12, 5), 2)
	# ③ 레벨 자동 습득을 보려면 레벨을 올려야 한다 — Lv+1 과 축복을 넉넉히
	UserDB.add_item("level_up", 60)
	UserDB.add_item("bless_of_dragon", 10)

	# ④ Lv9 신규 드래곤 — 한 번만 레벨을 올리면 Lv10 자동 습득이 보인다(스킬 0개 상태 확인 겸용)
	var d := UserDB.add_dragon(54, 9)
	UserDB.set_active(int(d["uid"]))
	print("[SkillTestMode] Lv9 테스트 드래곤 uid=%d 생성 · 스킬 %d개(0이어야 정상)"
		% [int(d["uid"]), (UserDB.dragon_skills(int(d["uid"])) as Array).size()])
	print("[SkillTestMode] 스크롤/스킬아이템/Lv+1 지급 완료 — 디스크 미기록(begin_batch)")

	Scenes.goto("cave")
