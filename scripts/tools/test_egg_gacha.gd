extends SceneTree
## 헤드리스 EggGacha 단위 테스트 (§10 — logic 은 화면 없이 검증 가능).
## 실행: godot --headless --script res://scripts/tools/test_egg_gacha.gd
## EggGacha 는 데이터를 인자로 받는 순수 로직이라 autoload 없이 실제 json 을 직접 읽어 돌린다.

func _init() -> void:
	var fails := 0
	var cfg: Dictionary = _json("res://data/gacha_eggs.json")
	var items: Dictionary = _json("res://data/items.json")
	var dragons: Dictionary = {}
	for d in _json_array("res://data/dragons.json"):
		dragons[int(d["id"])] = d
	fails += _true("데이터 로드", not cfg.is_empty() and not items.is_empty() and dragons.size() > 300)

	var rng := RandomNumberGenerator.new()

	# 1) 분류 — 뽑기 알만 '개봉' 대상이고 종이 정해진 알은 아니다.
	fails += _true("빛문알=개봉", EggGacha.is_gacha_egg(items["mall_question_egg2"]))
	fails += _true("속성알=개봉", EggGacha.is_gacha_egg(items["mall_water_egg"]))
	fails += _true("백룡의 알=부화", not EggGacha.is_gacha_egg(items["mall_back_egg"]))

	# 2) 🔴 회귀: 같은 알이 매번 같은 드래곤을 주면 안 된다(예전 hash(item_key) 시드 버그).
	var seen := {}
	rng.seed = 12345
	for i in 200:
		seen[EggGacha.roll("mall_question_egg2", items["mall_question_egg2"], cfg, dragons, rng)] = true
	fails += _true("빛문알 결과가 다양하다 (%d종)" % seen.size(), seen.size() > 20)

	# 3) 성급 범위 — 위키 item.pdf §5. 의문의 알 2~4성(+5성 5종), 빛문알 4~6성.
	fails += _stars("의문의 알", "mall_question_egg", items, cfg, dragons, rng, [2, 3, 4, 5])
	fails += _stars("빛나는 의문의 알", "mall_question_egg2", items, cfg, dragons, rng, [4, 5, 6])

	# 4) 의문의 알 5성은 위키가 특정한 5종뿐.
	var five: Array = EggGacha.candidates(dragons, 5, "",
		cfg["pools"]["mall_question_egg"]["star_pool_override"],
		cfg["pools"]["mall_question_egg"]["exclude"])
	fails += _eq("의문의 알 5성 풀 크기", five.size(), 5)
	fails += _true("수라 드래곤(4041) 포함", five.has(4041))

	# 5) 빛문알 전용 5종은 의문의 알·속성알에서 안 나온다(위키 '빛문알에서만 나오는 드래곤').
	var excl: Array = EggGacha.as_ints(cfg["pools"]["mall_question_egg"]["exclude"])
	fails += _true("태엽 드래곤(4029) 제외 — 4성이라 안 막으면 샌다", excl.has(4029))
	rng.seed = 777
	var leaked := 0
	for i in 400:
		if excl.has(EggGacha.roll("mall_question_egg", items["mall_question_egg"], cfg, dragons, rng)):
			leaked += 1
	fails += _eq("의문의 알에서 전용종 유출", leaked, 0)

	# 6) 속성 알은 그 속성만 나온다.
	rng.seed = 99
	var bad := 0
	for i in 200:
		var id := EggGacha.roll("mall_water_egg", items["mall_water_egg"], cfg, dragons, rng)
		if id <= 0 or String(dragons[id].get("element", "")) != "aqua":
			bad += 1
	fails += _eq("물속성 알이 물속성만 준다", bad, 0)

	# 7) 시드가 같으면 결과도 같다(§4 재현성).
	fails += _eq("시드 재현성", _seq(items, cfg, dragons, 4242), _seq(items, cfg, dragons, 4242))

	print("EggGacha 테스트 — %s (실패 %d)" % ["ALL PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _seq(items: Dictionary, cfg: Dictionary, dragons: Dictionary, s: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var out: Array = []
	for i in 12:
		out.append(EggGacha.roll("mall_question_egg2", items["mall_question_egg2"], cfg, dragons, rng))
	return out


func _stars(label: String, key: String, items: Dictionary, cfg: Dictionary,
		dragons: Dictionary, rng: RandomNumberGenerator, allowed: Array) -> int:
	rng.seed = 2026
	var got := {}
	for i in 600:
		var id := EggGacha.roll(key, items[key], cfg, dragons, rng)
		if id <= 0:
			return _true("%s: 뽑기 실패" % label, false)
		got[int(dragons[id].get("star", 0))] = true
	for s in got:
		if not allowed.has(s):
			return _true("%s: 허용 밖 성급 %d" % [label, s], false)
	return _true("%s 성급 %s ⊆ %s" % [label, str(got.keys()), str(allowed)], true)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _json_array(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


func _true(what: String, ok: bool) -> int:
	if not ok:
		print("  FAIL: ", what)
		return 1
	return 0


func _eq(what: String, got, want) -> int:
	if got != want:
		print("  FAIL: %s — got %s, want %s" % [what, str(got), str(want)])
		return 1
	return 0
