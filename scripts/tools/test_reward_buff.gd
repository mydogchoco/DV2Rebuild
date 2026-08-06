extends SceneTree
## 헤드리스 단위 테스트 — 탐험 보상 배수권(경험치·골드 N배).
## 규칙 출처: 원작 아이템 설명문 + 위키 item.pdf §9.6("1시간 동안 탐험에서 얻는 경험치/골드 N배").
## 🟦 사용자 확정 2026-08-04: **게임을 꺼도 시간이 흐른다** = 실시간 unix 만료.
## 실행: godot --headless --path . --script res://scripts/tools/test_reward_buff.gd --quit-after 3

const IE := preload("res://scripts/systems/item_effect.gd")

func _init() -> void:
	var fails := 0
	var defs = _json("res://data/item_effects.json")
	var items = _json("res://data/items.json")
	var shop = _json("res://data/shop.json")

	# 0) 표 — 4종이 다 있고 지속시간은 1시간(위키 확정).
	fails += _true("item_effects 에 reward_buff", defs.has("reward_buff"))
	fails += _eq("지속시간 3600초(1시간)", int(defs["reward_buff"]["duration_sec"]), 3600)
	fails += _eq("배수권 4종", (defs["reward_buff"]["items"] as Dictionary).size(), 4)
	for k in ["expx2", "expx4", "goldx2", "goldx4"]:
		var eff := IE.reward_buff_of(defs, k)
		fails += _true("%s 해석됨" % k, not eff.is_empty())
		# 아이템 설명문의 배수와 표가 어긋나면 안 된다("… 경험치를 2배 증가시킨다").
		var want := 2 if k.ends_with("2") else 4
		fails += _eq("%s 배수" % k, int(eff.get("mult", 0)), want)
		fails += _true("%s 축" % k,
			String(eff.get("axis", "")) == ("exp" if k.begins_with("exp") else "gold"))
		# 가방에서 실제로 쓸 수 있어야 한다 — offline=impl 이 아니면 cave.gd 가 버튼을 안 만든다.
		fails += _true("%s offline=impl" % k, String((items[k] as Dictionary)["offline"]) == "impl")
	fails += _true("배수권이 아닌 키는 {}", IE.reward_buff_of(defs, "att_drink1").is_empty())

	# 1) 상점(ETC 탭)에서 4종을 다 판다 — 수급처가 있어야 의미가 있다.
	var sold := {}
	for t in (shop["tabs"] as Array):
		for s in ((t as Dictionary).get("stock", []) as Array):
			sold[String((s as Dictionary)["item"])] = String((t as Dictionary)["id"])
	for k2 in ["expx2", "expx4", "goldx2", "goldx4"]:
		fails += _true("%s 상점 진열" % k2, sold.has(k2))

	# 2) 무버프 = 배수 1.0 · 남은시간 0.
	var now := 1_800_000_000
	fails += _true("무버프 exp 1.0", IE.reward_buff_mult({}, "exp", now) == 1.0)
	fails += _eq("무버프 남은시간 0", IE.reward_buff_left({}, "exp", now), 0)

	# 3) 사용 → 1시간 동안 2배, 축은 서로 독립.
	var a: Dictionary = {}
	var r := IE.apply_reward_buff(a, IE.reward_buff_of(defs, "expx2"), now)
	fails += _true("expx2 사용 성공", bool(r["ok"]))
	a = r["active"]
	fails += _true("exp 2배 적용", IE.reward_buff_mult(a, "exp", now) == 2.0)
	fails += _eq("남은시간 3600", IE.reward_buff_left(a, "exp", now), 3600)
	fails += _true("골드는 무버프", IE.reward_buff_mult(a, "gold", now) == 1.0)

	# 4) 🔴 실시간 만료 — 1시간 1초 뒤에는 꺼져 있어야 한다(게임을 꺼도 흐른다는 규칙의 핵심).
	fails += _true("3599초 뒤 살아 있음", IE.reward_buff_mult(a, "exp", now + 3599) == 2.0)
	fails += _true("3601초 뒤 만료", IE.reward_buff_mult(a, "exp", now + 3601) == 1.0)
	fails += _eq("만료 후 남은시간 0", IE.reward_buff_left(a, "exp", now + 3601), 0)

	# 5) 중복 규칙(ASSUMPTION, 드링크 선례) — 같은 배수는 시간 누적.
	var r2 := IE.apply_reward_buff(a, IE.reward_buff_of(defs, "expx2"), now + 600)
	fails += _true("같은 배수 재사용 성공", bool(r2["ok"]))
	fails += _eq("남은 3000 + 3600 = 6600", IE.reward_buff_left(r2["active"], "exp", now + 600), 6600)

	# 6) 더 센 배수는 갱신하고 남은 시간을 잃지 않는다.
	var r3 := IE.apply_reward_buff(a, IE.reward_buff_of(defs, "expx4"), now + 600)
	fails += _true("4배로 갱신", IE.reward_buff_mult(r3["active"], "exp", now + 600) == 4.0)
	fails += _true("남은 시간 ≥ 3600", IE.reward_buff_left(r3["active"], "exp", now + 600) >= 3600)

	# 7) 더 약한 배수는 거부 — 호출측이 아이템을 소모하지 않는다.
	var r4 := IE.apply_reward_buff(r3["active"], IE.reward_buff_of(defs, "expx2"), now + 600)
	fails += _true("약한 배수 거부", not bool(r4["ok"]))
	fails += _true("거부 사유 문구 있음", String(r4["reason"]) != "")
	fails += _true("거부 시 상태 불변",
		IE.reward_buff_mult(r4["active"], "exp", now + 600) == 4.0)

	# 8) 만료분 정리 — 세이브에 죽은 항목이 쌓이지 않는다.
	var pruned := IE.prune_reward_buff(a, now + 4000)
	fails += _eq("만료분 제거", pruned.size(), 0)
	fails += _eq("살아있는 건 유지", IE.prune_reward_buff(a, now + 10).size(), 1)

	# 9) 🔴 세이브 왕복 — 게임을 껐다 켜도 유지돼야 한다. JSON 은 int 를 float 로 돌려주므로
	#    (Godot 4 의 고전 함정) 캐스팅이 빠지면 여기서 조용히 깨진다.
	var round_trip = JSON.parse_string(JSON.stringify(a))
	fails += _true("왕복 후 2배 유지", IE.reward_buff_mult(round_trip, "exp", now) == 2.0)
	fails += _eq("왕복 후 남은시간", IE.reward_buff_left(round_trip, "exp", now), 3600)
	fails += _true("왕복 후에도 1시간 뒤 만료",
		IE.reward_buff_mult(round_trip, "exp", now + 3601) == 1.0)

	# 10) 남은 시간 표기.
	fails += _true("59분", IE.reward_buff_left_text(3540) == "59분")
	fails += _true("1시간 10분", IE.reward_buff_left_text(4200) == "1시간 10분")
	fails += _true("만료는 빈 문자열", IE.reward_buff_left_text(0) == "")

	if fails == 0:
		print("[test_reward_buff] ALL PASS")
	else:
		printerr("[test_reward_buff] %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _json(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("  FAIL %s" % label)
	return 1
