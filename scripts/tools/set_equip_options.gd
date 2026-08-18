extends Node

func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var apply := "--apply" in args
	var dump := "--dump" in args
	var table: Dictionary = Data.equipment

	if dump:
		_dump(table)
		get_tree().quit()
		return

	var jobs: Array = []
	for a in args:
		if a.begins_with("--set="):
			var body := a.substr(6)
			var kv := body.split("=")
			if kv.size() != 2:
				continue
			var sc := String(kv[1]).split("x")
			jobs.append({"name": String(kv[0]), "stat": String(sc[0]),
				"count": int(sc[1]) if sc.size() > 1 else 4})
	if jobs.is_empty():
		print("[opt] 할 일이 없다. --dump 또는 --set=<이름>=<스탯>x<개수>")
		get_tree().quit()
		return

	var ranges: Dictionary = (table.get("option", {}) as Dictionary).get("value_ranges", {})
	var pool: Array = Equipment.option_stats(table)
	var ok := true
	for j in jobs:
		var stat := String(j["stat"])
		if not (stat in pool):
			print("[opt] 롤 풀에 없는 스탯: %s (가능: %s)" % [stat, str(pool)])
			ok = false
			continue
		var d := _find_dragon(String(j["name"]))
		if d.is_empty():
			print("[opt] 드래곤을 못 찾았다: %s" % j["name"])
			ok = false
			continue
		var slot := _exclusive_slot(d)
		if slot.is_empty():
			print("[opt] %s 에게 장착된 전용 장비가 없다." % j["name"])
			ok = false
			continue
		var rng: Array = ranges.get(stat, [1, 1])
		var vmax := int(rng[rng.size() - 1])
		var before := JSON.stringify(slot.get("options", []))
		var opts: Array = []
		for _i in int(j["count"]):
			opts.append({"stat": stat, "value": vmax})
		slot["options"] = opts
		print("[opt] uid=%d %s / %s\n      before %s\n      after  %s" % [
			int(d.get("uid", 0)), _label(d), String(slot.get("key", "")),
			before, JSON.stringify(opts)])
	if not ok:
		print("[opt] 실패한 항목이 있어 저장하지 않는다.")
		get_tree().quit()
		return
	if apply:
		UserDB.save()
		print("[opt] 저장 완료")
	else:
		print("[opt] 미리보기(--apply 없음) — 저장하지 않았다.")
	get_tree().quit()

func _label(d: Dictionary) -> String:
	var nick := String(d.get("nickname", ""))
	var sid := int(d.get("id", 0))
	var sname := UserDB.species_name(sid)
	var master := String((Data.dragons.get(str(sid), {}) as Dictionary).get("name", ""))
	return "%s | 종=%s%s (id=%d)" % [nick if nick != "" else "-",
		master if master != "" else "?", (" [%s]" % sname) if sname != "" else "", sid]

func _find_dragon(name: String) -> Dictionary:
	for d in UserDB.dragons():
		var dd := d as Dictionary
		if String(dd.get("nickname", "")) == name:
			return dd
	for d in UserDB.dragons():
		var dd := d as Dictionary
		if UserDB.species_name(int(dd.get("id", 0))) == name:
			return dd
	var cat := Equipment.catalog(Data.equipment)
	for d in UserDB.dragons():
		var dd := d as Dictionary
		var s := _exclusive_slot(dd)
		if s.is_empty():
			continue
		var it: Dictionary = cat.get(String(s.get("key", "")), {})
		if String(it.get("dragon", "")) == name:
			return dd
	return {}

func _exclusive_slot(d: Dictionary) -> Dictionary:
	for s in ((d.get("equip", {}) as Dictionary).get("slots", []) as Array):
		if String((s as Dictionary).get("key", "")).begins_with("exclusive:"):
			return s
	return {}

func _dump(table: Dictionary) -> void:
	var cat := Equipment.catalog(table)
	print("[opt] 세이브 드래곤 %d마리" % UserDB.dragons().size())
	for d in UserDB.dragons():
		var dd := d as Dictionary
		if bool(dd.get("egg", false)):
			continue
		var slots: Array = (dd.get("equip", {}) as Dictionary).get("slots", [])
		var line := "  uid=%-4d %s" % [int(dd.get("uid", 0)), _label(dd)]
		print(line)
		for s in slots:
			var sd := s as Dictionary
			var key := String(sd.get("key", ""))
			print("      [%s] %s (%s) grade=%d enhance=%d opts=%s" % [
				String(sd.get("slot", "?")),
				String((cat.get(key, {}) as Dictionary).get("name", key)), key,
				int(sd.get("grade", 0)), int(sd.get("enhance", 0)),
				JSON.stringify(sd.get("options", []))])
