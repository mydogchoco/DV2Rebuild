extends Node

var _uid := 0
var _feed_key := ""

func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.size = get_viewport().get_visible_rect().size
	add_child(root)
	Scenes.bind_root(root)
	await get_tree().process_frame

	var el := ""
	if UserDB.dragons().is_empty():
		for did in Data.dragons:
			var e := String((Data.dragons[did] as Dictionary).get("element", ""))
			if _find_feed_for(e) != "":
				UserDB.add_dragon(int(did), 10)
				el = e
				break
	_uid = int(UserDB.dragons()[0]["uid"]) if not UserDB.dragons().is_empty() else 0
	if _uid > 0:
		UserDB.set_active(_uid)
		el = String(Data.get_dragon(int(UserDB.get_dragon(_uid).get("id", 0))).get("element", ""))
	_feed_key = _find_feed_for(el)
	if _uid <= 0 or _feed_key == "":
		print("[test_adventure_auto_feed] 준비 실패 — uid=%d 속성=%s 먹이키=%s"
			% [_uid, el, _feed_key])
		get_tree().quit(1)
		return

	var fails := 0
	fails += await _case("오토·먹이 있음", true, true, false, true)
	fails += await _case("오토·먹이 없음", true, false, true, false)
	fails += await _case("오토 꺼짐", false, true, true, false)

	print("[test_adventure_auto_feed] %s" % ("ALL PASS" if fails == 0 else "FAIL(%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)

func _case(label: String, auto_on: bool, give_food: bool,
		want_popup: bool, want_fed: bool) -> int:
	AdvAuto.set_enabled(auto_on)
	UserDB.set_dragon_field(_uid, "food", 0)
	_clear_feeds()
	if give_food:
		UserDB.add_item(_feed_key, 3)
	var have_before := int(UserDB.inventory().get(_feed_key, 0))

	Scenes.goto("worldmap", {})
	await get_tree().process_frame
	Scenes.goto("adventure", {"stage": "1", "region": "yutakan", "hero": false})
	await get_tree().process_frame
	var sc := Scenes.current_scene()
	if sc == null:
		print("%-16s 씬 로드 실패" % label)
		return 1

	var popup := false
	for c in sc.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer == 70:
			popup = true
	var food := int(UserDB.get_dragon(_uid).get("food", 0))
	var used := have_before - int(UserDB.inventory().get(_feed_key, 0))
	var ok := popup == want_popup and (food > 0) == want_fed \
		and used == (1 if want_fed else 0)
	print("%-16s 확인창=%s(기대 %s) 허기=%d 소모=%d  %s"
		% [label, popup, want_popup, food, used, ("OK" if ok else "FAIL")])
	return 0 if ok else 1

func _find_feed_for(element: String) -> String:
	for k in Data.items:
		var idef: Dictionary = Data.items[k]
		if ItemEffect.is_feed(idef) and ItemEffect.feed_matches(idef, element):
			return String(k)
	return ""

func _clear_feeds() -> void:
	for k in UserDB.inventory().keys():
		if ItemEffect.is_feed(Data.get_item(String(k))):
			UserDB.add_item(String(k), -int(UserDB.inventory().get(k, 0)))
