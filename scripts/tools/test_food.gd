extends SceneTree
## 헤드리스 검증 — **허기(FOOD) 시스템**(§10: logic은 화면 없이 검증).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_food.gd
##
## 규칙(사용자 확정 2026-07-30 · docs/game_design.md):
##   · 눈금 = FOOD (상한=배부름 … 0=굶음). 원작 후기판은 피로도 삭제, 허기만 남았다.
##   · **속성이 맞는 먹이**만 먹는다. 속성당 2종 — 하나는 절반, 하나는 전량 회복.
##   · food 0 = 굶음 → 탐험 입장 불가 · 탐험 중이면 즉시 종료.

func _init() -> void:
	var fails := 0
	var defs: Dictionary = _load("res://data/item_effects.json")
	var items: Dictionary = _load("res://data/items.json")
	var fmax := ItemEffect.food_max(defs)

	# ── 1) 데이터: 먹이 18종 = 9속성 × 2단, half/full 로 정확히 갈린다 ────────
	var feeds: Array = []
	for k in items:
		var v = items[k]
		if v is Dictionary and ItemEffect.is_feed(v):
			feeds.append(k)
	fails += _eq("먹이 종수", feeds.size(), 18)
	fails += _eq("FOOD 상한", fmax, 100)
	var half: Array = defs.get("feed", {}).get("half", [])
	var full: Array = defs.get("feed", {}).get("full", [])
	fails += _eq("half 9종", half.size(), 9)
	fails += _eq("full 9종", full.size(), 9)
	var missing: Array = []
	for k in feeds:
		if not (half.has(k) or full.has(k)):
			missing.append(k)
	fails += _eq("모든 먹이가 half/full 중 하나", missing, [])
	# 속성마다 정확히 한 쌍(절반 1 · 전량 1)
	var by_el := {}
	for k in feeds:
		var el := String((items[k] as Dictionary).get("element", ""))
		var e: Dictionary = by_el.get(el, {"half": 0, "full": 0})
		if half.has(k): e["half"] = int(e["half"]) + 1
		else: e["full"] = int(e["full"]) + 1
		by_el[el] = e
	fails += _eq("9속성", by_el.size(), 9)
	for el in by_el:
		var e: Dictionary = by_el[el]
		fails += _eq("%s = 절반1·전량1" % el, [int(e["half"]), int(e["full"])], [1, 1])

	# ── 2) 회복량: 전량 = 상한까지 · 절반 = 상한의 50%만큼 ──────────────────
	var fire_full: Dictionary = items["food_fire_chicken"]
	var fire_half: Dictionary = items["food_fire_chickenleg"]
	fails += _eq("전량 먹이 pct", ItemEffect.feed_restore_pct(defs, "food_fire_chicken"), 100)
	fails += _eq("절반 먹이 pct", ItemEffect.feed_restore_pct(defs, "food_fire_chickenleg"), 50)
	fails += _eq("굶음 → 전량 = 만복",
		ItemEffect.food_after_feed(defs, fire_full, "food_fire_chicken", "fire", 0), fmax)
	fails += _eq("굶음 → 절반 = 50",
		ItemEffect.food_after_feed(defs, fire_half, "food_fire_chickenleg", "fire", 0), 50)
	fails += _eq("70 + 절반 = 상한에서 잘림",
		ItemEffect.food_after_feed(defs, fire_half, "food_fire_chickenleg", "fire", 70), fmax)

	# ── 3) 속성 불일치는 아무 효과 없다(소비도 하지 않는다 — 호출부 규칙) ────
	fails += _true("불 먹이를 물 드래곤은 못 먹는다", not ItemEffect.feed_matches(fire_full, "aqua"))
	fails += _eq("불일치 먹이는 FOOD 를 안 건드린다",
		ItemEffect.food_after_feed(defs, fire_full, "food_fire_chicken", "aqua", 30), 30)
	# 드링크·회복물약은 먹이가 아니다(허기와 무관).
	fails += _true("드링크는 먹이 아님", not ItemEffect.is_feed(items["att_drink1"]))
	fails += _true("회복물약은 먹이 아님", not ItemEffect.is_feed(items["heal_potion1"]))

	# ── 4) 굶음 판정 + 파티 스캔 ──────────────────────────────────────────
	fails += _true("0 = 굶음", ItemEffect.is_starving(defs, 0))
	fails += _true("1 = 안 굶음", not ItemEffect.is_starving(defs, 1))
	fails += _true("만복 = 안 굶음", not ItemEffect.is_starving(defs, fmax))
	var fake := {1: {"food": 0}, 2: {"food": 45}, 3: {}}   # 3 = 필드 없음 → 만복 취급
	var getter := func(uid: int): return fake.get(uid, {})
	fails += _eq("굶은 개체만 골라낸다",
		ItemEffect.starving_uids(defs, [1, 2, 3], getter), [1])

	# ── 5) 가방에 맞는 먹이가 있나(안내 문구 분기) ─────────────────────────
	fails += _true("불 먹이 보유 → 불 드래곤에게 먹일 수 있다",
		ItemEffect.has_matching_feed({"food_fire_chicken": 2}, items, "fire"))
	fails += _true("불 먹이만 있으면 물 드래곤에겐 없다",
		not ItemEffect.has_matching_feed({"food_fire_chicken": 2}, items, "aqua"))
	fails += _true("수량 0 은 보유가 아니다",
		not ItemEffect.has_matching_feed({"food_fire_chicken": 0}, items, "fire"))

	# ── 6) 오라성체 임계 = 45(만렙). 성체(25~44)는 오라 이펙트 없음 ─────────
	fails += _true("44 = 성체(오라 없음)", not Growth.is_aura_adult(44))
	fails += _true("45 = 오라성체", Growth.is_aura_adult(45))
	fails += _eq("성체 아트 임계는 그대로 25", Growth.stage_for_level(25), "adult")
	fails += _eq("24 = 해츨링", Growth.stage_for_level(24), "child")

	if fails == 0:
		print("[test_food] ✅ ALL PASS")
	else:
		print("[test_food] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1

func _true(label: String, ok: bool) -> int:
	if ok:
		return 0
	print("  FAIL %s" % label)
	return 1
