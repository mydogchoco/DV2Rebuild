extends SceneTree

func _init() -> void:
	var fails := 0
	var cfg := _json(_data_file("card_game.json"))
	fails += _true("데이터 로드", not cfg.is_empty())
	var rng := RandomNumberGenerator.new()

	var g: Dictionary = cfg["games"]
	fails += _eq("match 카드수", int(g["match"]["cards"]), 8)
	fails += _eq("match 기회", int(g["match"]["chances"]), 4)
	fails += _eq("avoid 카드수", int(g["avoid"]["cards"]), 3)

	rng.seed = 11
	for t in 40:
		var deck := CardGame.make_deck("match", cfg, rng)
		var cards: Array = deck["cards"]
		if cards.size() != 8:
			fails += _true("match 덱 8장", false); break
		var counts := {}
		for c in cards:
			var k := _sig(c)
			counts[k] = int(counts.get(k, 0)) + 1
		for k in counts:
			if int(counts[k]) % 2 != 0:
				fails += _true("match 덱이 짝을 이룬다 (%s ×%d)" % [k, int(counts[k])], false)
				break
	fails += _true("match 덱 4쌍 구성", true)

	rng.seed = 99
	var worst := 0
	for t in 60:
		var deck3 := CardGame.make_deck("match", cfg, rng)
		var cnt := {}
		for c in (deck3["cards"] as Array):
			var k2 := _sig(c)
			cnt[k2] = int(cnt.get(k2, 0)) + 1
		for k2 in cnt:
			worst = maxi(worst, int(cnt[k2]))
	fails += _eq("같은 보상 최대 장수(=2 여야 한다)", worst, 2)

	rng.seed = 22
	var blank_seen := {}
	for t in 60:
		var deck2 := CardGame.make_deck("avoid", cfg, rng)
		var cards2: Array = deck2["cards"]
		if cards2.size() != 3:
			fails += _true("avoid 덱 3장", false); break
		var nb := 0
		for c in cards2:
			if String(c.get("kind", "")) == "none":
				nb += 1
		blank_seen[nb] = true
		if nb < 1 or nb > 2:
			fails += _true("avoid 꽝 1~2장 (실제 %d)" % nb, false); break
	fails += _true("avoid 꽝 개수 %s ⊆ {1,2}" % str(blank_seen.keys()), true)

	var allowed := ["heal", "buff_att", "buff_def", "gold", "diamond", "egg", "none"]
	rng.seed = 33
	var kinds := {}
	for t in 400:
		var r := CardGame.roll_reward(cfg, rng)
		kinds[String(r.get("kind", ""))] = true
	for k in kinds:
		if not allowed.has(k):
			fails += _true("허용 밖 보상 종류 %s" % k, false)
	fails += _true("보상 종류 %s ⊆ 위키 목록" % str(kinds.keys()), true)

	rng.seed = 44
	var bad_gold := 0
	for t in 500:
		var r2 := CardGame.roll_reward(cfg, rng)
		if String(r2.get("kind", "")) == "gold":
			var a := int(r2.get("amount", 0))
			if a < 100 or a > 200:
				bad_gold += 1
	fails += _eq("골드 100~200 이탈", bad_gold, 0)

	var egg_pool := [100, 102, 83, 101]
	rng.seed = 55
	var bad_egg := 0
	for t in 2000:
		var r3 := CardGame.roll_reward(cfg, rng)
		if String(r3.get("kind", "")) == "egg" and not egg_pool.has(int(r3.get("dragon_id", -1))):
			bad_egg += 1
	fails += _eq("알 풀 이탈", bad_egg, 0)

	var blank := {"kind": "none"}
	fails += _true("꽝끼리는 짝 아님", not CardGame.is_match(blank, blank))
	fails += _true("같은 골드액은 짝", CardGame.is_match(
		{"kind": "gold", "amount": 150}, {"kind": "gold", "amount": 150}))
	fails += _true("다른 골드액은 짝 아님", not CardGame.is_match(
		{"kind": "gold", "amount": 150}, {"kind": "gold", "amount": 120}))

	fails += _eq("시드 재현성", _sig_deck(cfg, 777), _sig_deck(cfg, 777))

	print("CardGame 테스트 — %s (실패 %d)" % ["ALL PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)

func _sig(c: Dictionary) -> String:
	return "%s:%d:%d:%d" % [String(c.get("kind", "")), int(c.get("amount", -1)),
		int(c.get("dragon_id", -1)), int(c.get("tier", -1))]

func _sig_deck(cfg: Dictionary, s: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var out: PackedStringArray = []
	for c in (CardGame.make_deck("match", cfg, rng)["cards"] as Array):
		out.append(_sig(c))
	return " ".join(out)

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

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

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
