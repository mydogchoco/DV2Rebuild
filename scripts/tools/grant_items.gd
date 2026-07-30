extends Node
## 검증용 아이템 지급 — 세이브 JSON 을 직접 고치지 않고 **UserDB 를 거쳐** 스키마를 지킨다.
##
## ⚠️ `--script` 단독 모드에는 오토로드(UserDB/Data)가 없다 → **임시 오토로드**로 붙여 돌린다:
##   1) project.godot [autoload] 에 `GrantItems="*res://scripts/tools/grant_items.gd"` 한 줄 추가
##   2) Godot --path . --headless --quit-after 120 -- --item=bless_of_amor=100 --item=...
##   3) 그 줄을 지운다  (커밋하지 말 것 — [[dv2-shothelper-autoload-gotcha]] 와 같은 함정)
##
## `--item` 생략 시 아모르/데르사/마이아의 축복 100개씩.
## ⚠️ 게임이 실행 중이면 그쪽 인스턴스가 나중에 세이브를 덮어쓴다 — **게임을 닫고** 돌릴 것.

func _ready() -> void:
	var grants: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--item="):
			var kv := a.substr(7).split("=")
			if kv.size() == 2:
				grants[String(kv[0])] = int(kv[1])
	if grants.is_empty():
		grants = {"bless_of_amor": 100, "bless_of_dersa": 100, "bless_of_maia": 100}

	await get_tree().process_frame
	for key in grants.keys():
		var before := UserDB.item_count(key)
		UserDB.add_item(key, int(grants[key]))
		print("[grant] %-18s %d -> %d  (%s)" % [key, before, UserDB.item_count(key),
			Data.item_name(key)])
	UserDB.save()
	print("[grant] 저장 완료")
	get_tree().quit()
