extends Node

const TAG := "[test_promote]"

var _fails := 0
var _scene: Control

func _ready() -> void:
	await get_tree().process_frame
	await _run()

func _run() -> void:
	UserDB.begin_batch()
	var breed_backup = Data.promote.get("breed_enable", 0)
	var uids := _seed_roster()

	await _tab_structure(uids)
	await _training(uids)
	await _mate(uids)
	await _history(uids)
	_numbers()

	Data.promote["breed_enable"] = breed_backup
	if is_instance_valid(_scene):
		_scene.queue_free()
	UserDB.reload()
	print("%s %s" % [TAG, "ALL PASS" if _fails == 0 else "FAIL %d" % _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _seed_roster() -> Array:
	var d := UserDB.raw()
	d["dragons"] = []
	d["storage"] = []
	d["next_uid"] = 1
	d["currency"] = {"gold": 5_000_000, "diamond": 5000}
	if d.has("meta"):
		(d["meta"] as Dictionary).erase("training")
		(d["meta"] as Dictionary).erase("training_unlocked")
		(d["meta"] as Dictionary).erase("mate")
		(d["meta"] as Dictionary).erase("latea")
		(d["meta"] as Dictionary).erase("sky_nest")
	var out: Array = []
	for lv in [5, 20, 40, 45, 55]:
		var nd := UserDB.add_dragon(1, lv)
		out.append(int(nd.get("uid", 0)))
	d["active_uid"] = int(out[0])
	return out

func _open(tab: String) -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		await get_tree().process_frame
	_scene = (load("res://scenes/promote.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_scene)
	_scene.enter({"tab": tab, "from": "town"})
	for i in 4:
		await get_tree().process_frame

func _tab_structure(_uids: Array) -> void:
	Data.promote["breed_enable"] = 0
	await _open("train")
	_eq("탭(breed off)", _scene._tabs(), [0, 2, 3])
	Data.promote["breed_enable"] = 1
	await _open("train")
	_eq("탭(breed on)", _scene._tabs(), [0, 1, 2])
	await _open("latea")
	_eq("라테아 진입 폴백", _scene._tab, 0)
	Data.promote["breed_enable"] = 0

func _training(uids: Array) -> void:
	await _open("train")
	_ok("훈련 탭 레이어", _scene._layer != null and _scene._layer.get_child_count() > 0)
	_ok("캠프1 해금", _scene._camp_unlocked(1))
	_ok("캠프2 잠김", not _scene._camp_unlocked(2))

	var lv55: Dictionary = UserDB.get_dragon(int(uids[4]))
	_ok("Lv55 훈련 불가", _scene._train_disabled(lv55))
	_ok("Lv40 훈련 가능", not _scene._train_disabled(UserDB.get_dragon(int(uids[2]))))

	var uid := int(uids[2])
	var row: Dictionary = _scene._train_row(3)
	var gold0 := UserDB.gold()
	var exp0 := int(UserDB.get_dragon(uid).get("exp", 0))
	var lv0 := int(UserDB.get_dragon(uid).get("level", 1))
	_scene._do_train(1, uid, 3)
	for i in 3:
		await get_tree().process_frame
	_eq("훈련 비용(골드)", gold0 - UserDB.gold(), int(row["fee"]))
	var after: Dictionary = UserDB.get_dragon(uid)
	var gained := int(after.get("exp", 0)) - exp0 if int(after.get("level", 1)) == lv0 else -1
	_ok("경험치 즉시 지급", gained == int(row["exp"]) or int(after.get("level", 1)) > lv0)
	var left: int = _scene._camp_until(1) - int(Time.get_unix_time_from_system())
	_ok("둥지 청소 중(%ds ≈ %d)" % [left, int(row["need_time"])],
		absi(left - int(row["need_time"])) <= 2)

	var per := int(Data.promote["training"]["clean_reset_sec_per_dia"])
	_eq("초기화 초/다이아", per, 300)
	var dia0 := UserDB.diamond()
	_scene._reset_clean(1, left / per)
	_eq("초기화 다이아 차감", dia0 - UserDB.diamond(), left / per)
	_eq("초기화 후 대기 0", _scene._camp_until(1), 0)

	_eq("둥지 해금가", int(Data.promote["training"]["slot_open_dia"]), 99)
	var dia1 := UserDB.diamond()
	_scene._open_slot(2, 99)
	_eq("해금 차감", dia1 - UserDB.diamond(), 99)
	_ok("캠프2 해금됨", _scene._camp_unlocked(2))

	_scene._open_dragon_select(1)
	await get_tree().process_frame
	_ok("DragonPicker 열림", _canvas_layers(_scene, 40) > 0)

func _mate(uids: Array) -> void:
	Data.promote["breed_enable"] = 1
	await _open("mate")
	_ok("교배 탭 레이어", _scene._layer != null and _scene._layer.get_child_count() > 0)

	var a := int(uids[2])
	var b := int(uids[3])
	_scene._mate_pick = {0: a, 1: b}
	var ga := int(floor(_scene._grade_of(UserDB.get_dragon(a))))
	var gb := int(floor(_scene._grade_of(UserDB.get_dragon(b))))
	_eq("교배비 = (등급합)×500", _scene._mate_cost(), (ga + gb) * 500)
	_eq("최소 레벨", int(Data.promote["mate"]["min_level"]), 35)

	var gold0 := UserDB.gold()
	var cost: int = _scene._mate_cost()
	_scene._on_click_ok()
	for i in 3:
		await get_tree().process_frame
	_eq("교배비 차감", gold0 - UserDB.gold(), cost)
	_ok("교배 진행 중", not _scene._mate().is_empty())
	_ok("부모 교배중 표시", _scene._is_breeding(a) and _scene._is_breeding(b))

	var remain := int(_scene._mate()["end"]) - int(Time.get_unix_time_from_system())
	var want := int(ceil(float(remain) / 3600.0))
	_eq("즉시완료 다이아", want, int(ceil(float(Data.promote["mate"]["breed_sec"]) / 3600.0)))
	var dia0 := UserDB.diamond()
	_scene._instant_mate(want)
	for i in 2:
		await get_tree().process_frame
	_eq("즉시완료 차감", dia0 - UserDB.diamond(), want)

	var key := String(_scene._mate()["egg"])
	var n0 := UserDB.item_count(key)
	_scene._finish_mate()
	for i in 3:
		await get_tree().process_frame
	_eq("알 지급", UserDB.item_count(key) - n0, 1)
	_ok("교배 상태 비움", _scene._mate().is_empty())
	var hist = UserDB.get_pmeta("mate_history", [])
	_ok("교배 기록 1건", (hist is Array) and (hist as Array).size() == 1)
	Data.promote["breed_enable"] = 0

func _history(uids: Array) -> void:
	await _open("nest")
	_ok("하늘둥지 빈 목록", _scene._layer.get_child_count() > 0)
	UserDB.store_dragon(int(uids[1]))
	await _open("nest")
	_eq("보관 1마리", UserDB.storage_dragons().size(), 1)
	var dia0 := UserDB.diamond()
	var price: int = _scene._restore_price(20)
	_scene._do_restore(0, UserDB.storage_dragons()[0], false, price)
	await get_tree().process_frame
	_eq("회수 다이아 차감", dia0 - UserDB.diamond(), price)
	_eq("보관 비었다", UserDB.storage_dragons().size(), 0)

	var uid := int(uids[3])
	var before: Dictionary = UserDB.get_dragon(uid).duplicate(true)
	UserDB.release_dragon(uid)
	var recs := UserDB.latea_records()
	_eq("라테아 1건", recs.size(), 1)
	await _open("latea")
	_ok("라테아 목록", _scene._layer.get_child_count() > 0)
	var restored := UserDB.restore_from_latea(0)
	_eq("복원 레벨 보존", int(restored.get("level", 0)), int(before.get("level", 0)))
	_eq("복원 gain_log 보존", (restored.get("gain_log", []) as Array).size(),
		(before.get("gain_log", []) as Array).size())
	_eq("라테아 비었다", UserDB.latea_records().size(), 0)

	UserDB.set_pmeta("latea", [{"id": 1, "name": "x", "level": 10, "date": "",
		"t": int(Time.get_unix_time_from_system()) - 8 * 86400}])
	_eq("8일 지난 기록 소멸", UserDB.latea_records().size(), 0)

func _numbers() -> void:
	var t: Array = Data.promote["restore"]["price_dia"]
	_eq("부활가 Lv1", _scene._restore_price(1), int(t[0]))
	_eq("부활가 Lv24", _scene._restore_price(24), int(t[0]))
	_eq("부활가 Lv25", _scene._restore_price(25), int(t[1]))
	_eq("부활가 Lv44", _scene._restore_price(44), int(t[1]))
	_eq("부활가 Lv45", _scene._restore_price(45), int(t[2]))
	var rows: Array = Data.promote["training"]["info_train_v2"]
	_eq("훈련 5종", rows.size(), 5)
	for r: Dictionary in rows:
		for c in ["train_no", "name", "fee_type", "fee", "exp", "need_time", "icon", "icon2"]:
			_ok("info_train_v2.%s (%s)" % [c, r.get("name", "?")], r.has(c))
	for i in rows.size():
		var r: Dictionary = rows[i]
		_eq("행%d 아이콘 쌍" % (i + 1), [r.get("icon"), r.get("icon2")],
			["train%d" % (i * 2 + 1), "train%d" % (i * 2 + 2)])
	for r: Dictionary in rows:
		for k in ["icon", "icon2"]:
			var key := "scene_promote_%s" % String(r[k])
			_ok("프레임 %s" % key, AtlasUI.tex("promote_ui", key) != null)

func _canvas_layers(n: Node, want: int) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CanvasLayer and (ch as CanvasLayer).layer == want and not ch.is_queued_for_deletion():
			c += 1
	return c

func _ok(what: String, cond: bool) -> void:
	if not cond:
		_fails += 1
		print("  FAIL %s" % what)

func _eq(what: String, got, want) -> void:
	if got != want:
		_fails += 1
		print("  FAIL %s — got %s, want %s" % [what, got, want])
