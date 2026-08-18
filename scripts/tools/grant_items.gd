extends Node

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
