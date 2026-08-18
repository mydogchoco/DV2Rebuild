extends Node
func _ready() -> void:
	await get_tree().process_frame
	var f := 0
	UserDB.reset()
	f += _eq("초기화 직후 드래곤", UserDB.dragon_count(), 0)
	f += _eq("초기화 직후 골드", UserDB.currency("gold"), 0)

	var first := NewGame.ensure(UserDB, Data.new_game_def())
	f += _true("1회차 = 신규 지급", first)
	f += _eq("지급 후 드래곤 (시작 드래곤 없음)", UserDB.dragon_count(), 0)
	f += _eq("지급 후 골드", UserDB.currency("gold"), 100000)
	f += _eq("지급 후 다이아", UserDB.currency("diamond"), 1000)
	var egg_key := "mall_question_egg2"
	if UserDB.is_admin():
		f += _eq("관리자: 미트라의 알", UserDB.item_count("egg:4155"), 1)
		f += _eq("관리자: 고대신룡 II의 알", UserDB.item_count("egg:4210"), 1)
		f += _eq("관리자: 빛문알은 안 준다", UserDB.item_count(egg_key), 0)
	else:
		f += _eq("빛나는 의문의 알", UserDB.item_count(egg_key), 10)

	var second := NewGame.ensure(UserDB, Data.new_game_def())
	f += _true("2회차 = 재지급 안 함", not second)
	f += _eq("2회차 후 골드 그대로", UserDB.currency("gold"), 100000)
	if UserDB.is_admin():
		f += _eq("2회차 후 미트라 알 그대로", UserDB.item_count("egg:4155"), 1)
	else:
		f += _eq("2회차 후 알 그대로", UserDB.item_count(egg_key), 10)
	var third := NewGame.ensure(UserDB, Data.new_game_def())
	f += _true("3회차도 재지급 안 함", not third)
	f += _eq("3회차 후 다이아 그대로", UserDB.currency("diamond"), 1000)

	print("[test_new_game_seed] 관리자=%s" % str(UserDB.is_admin()))
	for k in ["egg:4155", "egg:4210", "mall_question_egg2"]:
		var n := UserDB.item_count(k)
		if n > 0:
			var did := EggGacha.dragon_of(k)
			var nm := ("%s의 알" % String(Data.get_dragon(did).get("name", "?"))) \
				if did > 0 else Data.item_name(k)
			print("[test_new_game_seed]   %s x%d = '%s'" % [k, n, nm])
	print("[test_new_game_seed] %s" % ("실패 %d건" % f if f > 0 else "통과"))
	get_tree().quit(1 if f > 0 else 0)

func _eq(name: String, got, want) -> int:
	if got == want: return 0
	print("  ✗ %s: %s (기대 %s)" % [name, got, want]); return 1

func _true(name: String, ok: bool) -> int:
	if ok: return 0
	print("  ✗ %s" % name); return 1
