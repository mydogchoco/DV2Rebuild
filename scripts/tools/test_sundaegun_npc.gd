extends Node
## 선대군 NPC 입 프레임 스모크 — `build_sundaegun_npc.py` 산출물 + `NpcPortrait` 배선 검증.
## 확인: 매니페스트 입 3프레임 · npc_face 좌표 병합 · 입 파츠 부착 · set_talking 프레임 순환.
##
## ⚠️ `--script` 모드로는 못 돌린다 — `NpcPortrait` 가 `Data`/`Design` 오토로드를 참조한다.
## 전용 러너가 임시 오토로드로 등록·해제한다:
##     python scripts/tools/run_test_sundaegun.py

func _ready() -> void:
	var fails := 0

	# 1) 산출물 — 매니페스트에 몸통 + 입 1_1~1_3.
	var man_f := FileAccess.open("res://assets/converted/npc_sundaegun/_manifest.json", FileAccess.READ)
	fails += _true("매니페스트 존재", man_f != null)
	var man: Dictionary = JSON.parse_string(man_f.get_as_text()) if man_f != null else {}
	fails += _true("키 body_1", man.has("npc_sundaegun_body_1"))
	# 포포 이식 입 — 표정 1~6 × 프레임 1~3 (🟦 사용자 확정 2026-08-07)
	for e in range(1, 7):
		for f in range(1, 4):
			fails += _true("키 mouth_%d_%d" % [e, f], man.has("npc_sundaegun_mouth_%d_%d" % [e, f]))

	# 2) 좌표 — data/npc_face.json 에 사이드카가 병합돼 있다.
	var sd: Dictionary = (Data.npc_face.get("npc", {}) as Dictionary).get("sundaegun", {})
	fails += _true("npc_face sundaegun ? mouth", (sd.get("?", {}) as Dictionary).has("mouth"))

	# 3) 부착 — NpcPortrait 가 입 파츠를 실제로 단다(눈은 없음이 정상).
	var p := NpcPortrait.create("sundaegun")
	add_child(p)
	fails += _true("몸통", p._body != null)
	fails += _true("입 부착", p._mouth != null)
	fails += _true("눈 없음(정상)", p._eye == null)
	fails += _eq("입 프레임 수", (p._mouth_fr as Array).size(), 3)

	# 4) 말하기 — set_talking(true) 면 3프레임이 전부 돌고, 끄면 1(다뭄)로 복귀.
	p.set_talking(true)
	var seen := {}
	for i in 120:
		p._process(0.05)
		seen[p._mouth_i] = true
	fails += _eq("순환이 3프레임 전부 지남", seen.size(), 3)
	p.set_talking(false)
	fails += _eq("멈추면 다문 입(1)", p._mouth_i, 0)

	# 5) 표정 전환 — set_emotion(2~6) 이 그 표정의 입 프레임으로 갈아탄다.
	for e in range(2, 7):
		p.set_emotion(e)
		fails += _eq("표정 %d 전환" % e, p._art_emo, e)
		fails += _eq("표정 %d 프레임 수" % e, (p._mouth_fr as Array).size(), 3)

	print("[test_sundaegun] %s" % ("ALL PASS" if fails == 0 else "FAILS=%d" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _true(what: String, ok: bool) -> int:
	print(("  ok  " if ok else "  FAIL") + " " + what)
	return 0 if ok else 1

func _eq(what: String, got, want) -> int:
	var ok: bool = got == want
	print(("  ok  " if ok else "  FAIL") + " %s (got=%s want=%s)" % [what, got, want])
	return 0 if ok else 1
