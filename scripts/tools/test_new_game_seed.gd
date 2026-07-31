extends Node
## 초기 로드아웃 회귀 테스트 — 세이브 초기화 후 **한 번만** 지급되는지.
## 🔴 2026-08-01: 시작 드래곤(디버그 지급분)을 빼자 `dragon_count()>0` 판정이 영영 참이 되어
##    타이틀을 터치할 때마다 재화·알이 재지급되던 것을 잡는다(NewGame.SEEDED_KEY).
## ⚠️ 세이브를 **실제로 초기화**한다 — 돌리기 전에 `user://save_0.json` 을 백업할 것.
##   (Windows: %APPDATA%\Godot\app_userdata\DragonVillage2 Offline\save_0.json)
## 실행: project.godot `[autoload]` 에 아래 한 줄을 임시로 넣고 헤드리스 부팅 → 끝나면 지운다.
##   TestNewGameSeed="*res://scripts/tools/test_new_game_seed.gd"
##   godot --headless --path . --quit-after 60
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
	f += _eq("빛나는 의문의 알", UserDB.item_count("mall_question_egg2"), 10)

	var second := NewGame.ensure(UserDB, Data.new_game_def())
	f += _true("2회차 = 재지급 안 함", not second)
	f += _eq("2회차 후 골드 그대로", UserDB.currency("gold"), 100000)
	f += _eq("2회차 후 알 그대로", UserDB.item_count("mall_question_egg2"), 10)
	var third := NewGame.ensure(UserDB, Data.new_game_def())
	f += _true("3회차도 재지급 안 함", not third)
	f += _eq("3회차 후 다이아 그대로", UserDB.currency("diamond"), 1000)

	print("[test_new_game_seed] %s" % ("실패 %d건" % f if f > 0 else "통과"))
	get_tree().quit(1 if f > 0 else 0)

func _eq(name: String, got, want) -> int:
	if got == want: return 0
	print("  ✗ %s: %s (기대 %s)" % [name, got, want]); return 1

func _true(name: String, ok: bool) -> int:
	if ok: return 0
	print("  ✗ %s" % name); return 1
