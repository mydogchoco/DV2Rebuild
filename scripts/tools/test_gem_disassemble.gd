extends SceneTree
## 헤드리스 젬 분해/강화 공식 스모크 (§8 — 오토로드 없이 데이터 + Gem 로직만 본다).
## 실행: godot --headless --path . --script res://scripts/tools/test_gem_disassemble.gd --quit-after 3
##
## 전부 **원작 디컴프에서 복원한 값**을 고정한다(2026-07-31). 회귀하면 여기서 잡힌다.
##   ① 분해 골드 = 500 × 개수 — `UpgradeGemLayer::onClickDisassembleCntMenu` 의
##      `confirmBtIconTextSort(this, cnt * 500)`. 참조 영상 `docs/ref/gem/젬분해4.png` 의
##      1,454,000 = 500 × (12+11+642+597+439+1207) 로 교차검증된다.
##   ② 가루/개 = max(1, floor(1.55^(티어) / 10)) — 같은 함수의 pow/÷10/최소1.
##      (우리 `tier` 는 0-base 라 원작 `typeLevel-1` 과 같은 지수다.)
##   ③ 연금술 포인트 배율 0.5 %/point — 참조 영상 실측(2pt→60%, 6pt→62%).
##   ④ 소울젬 승급 대상 = 최대티어 혼성젬(샌즈 포함) — `UpgradeSoulGemPopup::ableGemCheck`.

const Gem := preload("res://scripts/systems/gem.gd")

func _init() -> void:
	var t: Dictionary = JSON.parse_string(FileAccess.open(
		"res://data/gems.json", FileAccess.READ).get_as_text())
	var fails := 0

	# ① 골드 = 500/개 + 참조 영상 실측 재현
	var video_counts := [12, 11, 642, 597, 439, 1207]
	var total := 0
	for c in video_counts:
		total += int(c)
	fails += _eq("젬분해4 총 개수", total, 2908)
	fails += _eq("젬분해4 골드", Gem.disassemble_gold(total, t), 1454000)
	fails += _eq("골드 1개", Gem.disassemble_gold(1, t), 500)

	# ② 가루/개 = max(1, (int)pow(1.55, tier) / 10)
	for pair in [[0, 1], [1, 1], [5, 1], [9, 5], [12, 19], [16, 110], [18, 266]]:
		var tier := int((pair as Array)[0])
		fails += _eq("가루 tier=%d" % tier, Gem.disassemble_dust(tier, t), int((pair as Array)[1]))

	# ③ 포인트 배율 — 0.5 %/point (100pt → +50%)
	fails += _eq("point_bonus(0)", Gem.point_bonus(0, t), 0)
	fails += _eq("point_bonus(2)", Gem.point_bonus(2, t), 1)
	fails += _eq("point_bonus(6)", Gem.point_bonus(6, t), 3)
	fails += _eq("point_bonus(100)", Gem.point_bonus(100, t), 50)

	# ④ 승급 대상 — 혼성 6종 + 샌즈(ATTDEFHP)가 첫 능력치 축의 소울젬으로 간다.
	var want := {"ATTDEF": "SOULATT", "ATTHP": "SOULATT", "DEFATT": "SOULDEF",
		"DEFHP": "SOULDEF", "HPATT": "SOULHP", "HPDEF": "SOULHP", "ATTDEFHP": "SOULALL"}
	for nm: String in (t["gems"] as Dictionary):
		var gd: Dictionary = (t["gems"] as Dictionary)[nm]
		var code := String(gd.get("code", ""))
		if want.has(code):
			fails += _eq("%s promote_to" % code, String(gd.get("promote_to", "")), String(want[code]))
		elif String(gd.get("category", "")) != "soul":
			fails += _eq("%s 는 승급 대상 아님" % code, String(gd.get("promote_to", "")), "")

	print("[test_gem_disassemble] %s" % ("OK" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)


func _eq(what: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  ✗ %s: got %s, want %s" % [what, str(got), str(want)])
	return 1
