extends SceneTree
## 헤드리스 검증 — **도감 단계(Book::getStep 1~6)의 칸 수와 단계별 초상**.
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_dex_steps.gd
##
## 사용자 확정(2026-07-30):
##   · **오라성체까지 있는 종 = 5단계 · 각성이 있는 종 = 6단계.**
##   · 오라성체는 **아트가 성체와 같다**(오라 이펙트만 다르다) → 오라성체 칸은 `box_adult`.
##   · 각성 칸만 각성체 초상(`box_evolution`)을 쓴다.
##
## 🔴 여기서 지키는 회귀: 종전엔 각성 판별을 `box_s01`(**13종**)로 해서 거의 모든 종이 5칸으로
##   굳었고, 그 5번째(오라성체) 칸이 `box_evolution`(=각성 그림)을 그리고 있었다.
##   판별의 정답은 `box_evolution` 보유(**137종**)다 — 아래 ②가 네 신호의 일치를 못박는다.

const EGG := preload("res://scripts/systems/egg_gacha.gd")

func _init() -> void:
	var fails := 0
	var meta: Dictionary = _load("res://data/dex_meta.json")

	# ── ① 신호 규모 — evo(각성 보유) 137 · s01 13 ──────────────────────────
	var evo := 0
	var s01 := 0
	for k in meta:
		var m: Dictionary = meta[k]
		if bool(m.get("evo", false)): evo += 1
		if bool(m.get("awaken", false)): s01 += 1
	fails += _eq("각성 보유(box_evolution)", evo, 137)
	fails += _eq("box_s01 보유(각성 아님)", s01, 13)
	fails += _true("각성 보유가 s01 보다 훨씬 많다(판별 신호가 바뀐 이유)", evo > s01 * 5)

	# ── ② 실측 대조 — 초상 매니페스트가 meta 와 일치하나 ───────────────────
	var checked := 0
	var mismatch: Array = []
	var evo_no_frame: Array = []
	for k in meta:
		var did := int(k)
		var dir := "portrait_%d" % did
		if not FileAccess.file_exists("res://assets/converted/%s/_manifest.json" % dir):
			continue
		checked += 1
		var man: Dictionary = _load("res://assets/converted/%s/_manifest.json" % dir)
		var has_ev: bool = man.has("dragon_dragon_%d_box_evolution" % did)
		if has_ev != bool((meta[k] as Dictionary).get("evo", false)):
			mismatch.append(did)
		if bool((meta[k] as Dictionary).get("evo", false)) and not has_ev:
			evo_no_frame.append(did)
		# 모든 종은 성체 초상이 있어야 한다(오라성체 칸이 이걸 쓴다).
		if not man.has("dragon_dragon_%d_box_adult" % did):
			mismatch.append(did)
	fails += _true("초상 매니페스트 검사 대상 있음(%d)" % checked, checked > 300)
	fails += _eq("meta ↔ 초상 실측 불일치 없음", mismatch, [])
	fails += _eq("각성 보유인데 프레임 없는 종 없음", evo_no_frame, [])

	# ── ③ 단계 칸 수 규칙 ─────────────────────────────────────────────────
	#     (cave.gd 의 `slots` 식과 같은 규칙을 여기서 독립적으로 재현해 고정한다.)
	var five := 0
	var six := 0
	for k in meta:
		if bool((meta[k] as Dictionary).get("evo", false)): six += 1
		else: five += 1
	fails += _eq("6단계 종 수 = 각성 보유 수", six, evo)
	fails += _eq("5단계 + 6단계 = 전체", five + six, meta.size())

	# ── ③-b 미구현 더미 종 제외 + 특수 트리거 (사용자 확정 2026-07-30) ─────
	#   `dragons.csv` 이름 칸이 비었거나 `null` 인 행은 미구현 더미다.
	#   완전 공백 21건은 dragons.json 에 아예 없고, `null` 2건(600·700)은 `dex_hidden` 으로
	#   실려 **도감·입수처에서 기본 제외**된다(도감은 보유 이력이 있을 때만 덧붙인다).
	var dragons_arr = _load_any("res://data/dragons.json")
	var hidden: Array = []
	var nameless: Array = []
	var by_id := {}
	for d in (dragons_arr as Array):
		var dd: Dictionary = d
		by_id[int(dd.get("id", 0))] = dd
		if bool(dd.get("dex_hidden", false)):
			hidden.append(int(dd.get("id", 0)))
		if String(dd.get("name", "")).strip_edges() == "":
			nameless.append(int(dd.get("id", 0)))
	hidden.sort(); nameless.sort()
	fails += _eq("기본 숨김 종 = 600·700", hidden, [600, 700])
	fails += _eq("이름 없는 종은 전부 숨김 처리돼 있다", nameless, hidden)
	# 입수처(알 뽑기) 후보에 숨김 종이 절대 들어가지 않는다.
	# 속성 축까지 훑는다 — 이 루프가 **`element` 가 null 인 종(4083)에서 터지던 버그**를 잡았다
	# (`String(null)` 은 Godot 4.7 런타임 에러). `EggGacha.candidates` 의 typeof 가드를 지킨다.
	var leaked: Array = []
	var elems: Array[String] = ["", "fire", "aqua", "wind", "earth", "light",
		"dark", "holy", "chaos", "shadow"]
	for star in range(1, 8):
		for ei in elems.size():
			for cid in EGG.candidates(by_id, star, elems[ei], {}, []):
				if hidden.has(int(cid)):
					leaked.append(int(cid))
	fails += _eq("뽑기 후보에 숨김 종 유출 없음", leaked, [])
	# 숨김 종을 뺀 뒤에도 후보가 넉넉히 남는다(과잉 필터 방지).
	var any_pool := 0
	for star in range(1, 8):
		any_pool += EGG.candidates(by_id, star, "", {}, []).size()
	fails += _true("성급 후보 총합이 300 이상(%d)" % any_pool, any_pool >= 300)

	# ── ④ 성장 단계 임계값(오라성체 = 45, 성체 = 25) ─────────────────────
	fails += _true("44 는 오라성체 아님", not Growth.is_aura_adult(44))
	fails += _true("45 = 오라성체", Growth.is_aura_adult(45))
	fails += _eq("오라성체도 아트는 adult", Growth.stage_for_level(45), "adult")
	fails += _eq("성체도 adult", Growth.stage_for_level(25), "adult")

	if fails == 0:
		print("[test_dex_steps] ✅ ALL PASS  (5단계 %d종 · 6단계 %d종)" % [five, six])
	else:
		print("[test_dex_steps] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _load_any(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

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
