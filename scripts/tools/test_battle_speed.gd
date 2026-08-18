extends Node

const BATTLE := preload("res://scripts/ui/battle.gd")
const FIGHT := preload("res://scripts/ui/fight.gd")

var _fails := 0

func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.size = get_viewport().get_visible_rect().size
	add_child(root)
	Scenes.bind_root(root)
	await get_tree().process_frame

	if UserDB.dragons().is_empty():
		UserDB.add_dragon(int(Data.dragons.keys()[0]), 10)
	var uid := int(UserDB.dragons()[0]["uid"])
	UserDB.set_active(uid)

	await _test_adventure_battle(uid)
	_test_colosseum_fight()

	print("[test_battle_speed] %s" % ("ALL PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

func _test_adventure_battle(uid: int) -> void:
	UserDB.set_pmeta(BATTLE.SPEED_KEY, 4.0)
	var sc: Node = await _enter_battle(uid)
	if sc == null:
		return
	_check(float(sc.get("_speed")) == 4.0, "이월된 배속 x4 로 시작 (%s)" % sc.get("_speed"))

	sc.call("_cycle_speed")
	_check(float(sc.get("_speed")) == 1.0, "x4 다음은 x1 (%s)" % sc.get("_speed"))
	_check(float(UserDB.get_pmeta(BATTLE.SPEED_KEY, -1.0)) == 1.0, "세이브에 x1 기록")

	UserDB.set_pmeta(BATTLE.SPEED_KEY, 2.0)
	var sc2: Node = await _enter_battle(uid)
	if sc2 == null:
		return
	_check(float(sc2.get("_speed")) == 2.0, "다음 전투도 이월 x2 (%s)" % sc2.get("_speed"))

	UserDB.set_pmeta(BATTLE.SPEED_KEY, 7.0)
	var sc3: Node = await _enter_battle(uid)
	if sc3 != null:
		_check(float(sc3.get("_speed")) == 1.0, "모르는 값은 x1 (%s)" % sc3.get("_speed"))

func _enter_battle(uid: int) -> Node:
	Scenes.goto("worldmap", {})
	await get_tree().process_frame
	Scenes.goto("battle", {"stage": "1", "region": "yutakan", "enc": 0, "party_uids": [uid]})
	await get_tree().process_frame
	var sc: Node = Scenes.current_scene()
	if sc == null:
		_check(false, "전투 씬 로드")
	return sc

func _test_colosseum_fight() -> void:
	var f := FIGHT.new()
	UserDB.set_pmeta(FIGHT.SPEED_KEY, 3)
	_check(int(f.call("_saved_speed")) == 3, "PVP 이월 x3")
	UserDB.set_pmeta(FIGHT.SPEED_KEY, 9)
	_check(int(f.call("_saved_speed")) == 1, "PVP 모르는 값은 x1")

	UserDB.set_pmeta(FIGHT.SPEED_KEY, 1)
	f.set("_speed", 1)
	f.call("_cycle_speed")
	_check(int(f.get("_speed")) == 2 and int(UserDB.get_pmeta(FIGHT.SPEED_KEY, -1)) == 2,
		"PVP 버튼이 세이브에 x2 기록 (%s)" % UserDB.get_pmeta(FIGHT.SPEED_KEY, -1))
	f.free()

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)
