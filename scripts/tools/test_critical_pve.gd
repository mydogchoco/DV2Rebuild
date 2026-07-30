extends SceneTree
# PvE 크리티컬 아트 + 연타 설정 검증.
#   (1) critical_<id> 아틀라스에 critical/e_critical 프레임이 있고 .tres 로 로드되는지
#   (2) `vis.x / w` 배율이 실제로 화면을 채우는지(384x260 · 768x519 두 변형 모두)
#   (3) combat.json judge.crit_hits 가 읽히는지
# Run: godot --headless --script res://scripts/tools/test_critical_pve.gd
func _initialize() -> void:
	var vis := Vector2(1024, 692)        # 디자인 기준 화면
	var da := DirAccess.open("res://assets/converted")
	var checked := 0
	var no_frame := 0
	var bad_fit := []
	var sizes := {}
	for sub in da.get_directories():
		if not sub.begins_with("critical_"):
			continue
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % sub, FileAccess.READ)
		if f == null:
			continue
		var man = JSON.parse_string(f.get_as_text())
		if not (man is Dictionary):
			continue
		var id := sub.trim_prefix("critical_")
		var key := "dragon_dragon_%s_critical_critical" % id
		if not man.has(key):
			no_frame += 1
			continue
		checked += 1
		# 배율 기준은 트림 프레임이 아니라 원본 캔버스(src)다 — battle.gd::_critical_art 와 동일.
		var src: Array = man[key].get("src", [man[key].get("w", 0), man[key].get("h", 0)])
		var w := float(src[0])
		var h := float(src[1])
		sizes["%dx%d" % [int(w), int(h)]] = int(sizes.get("%dx%d" % [int(w), int(h)], 0)) + 1
		# 가로를 화면 폭에 맞췄을 때 세로가 화면 높이에 근사하는가(±8%)
		var s := vis.x / w
		var fit_h := h * s
		if absf(fit_h - vis.y) / vis.y > 0.08:
			bad_fit.append("%s %dx%d -> h=%d" % [sub, int(w), int(h), int(fit_h)])
		# 실제 리소스 로드 확인(첫 5개만)
		if checked <= 5:
			var p := "res://assets/converted/%s/%s.tres" % [sub, key]
			if not ResourceLoader.exists(p) or load(p) == null:
				bad_fit.append("%s 로드 실패" % sub)
	print("critical 프레임 보유 드래곤: %d (프레임 없음 %d)" % [checked, no_frame])
	print("크기 분포: %s" % [sizes])
	print("화면 꽉 채우기 실패(±8%% 초과): %d %s" % [bad_fit.size(), bad_fit.slice(0, 5)])

	# `--script` 모드에는 오토로드(Data)가 없으므로 파일을 직접 읽는다.
	var hits := 0
	var cf := FileAccess.open("res://data/combat.json", FileAccess.READ)
	if cf:
		var cd = JSON.parse_string(cf.get_as_text())
		if cd is Dictionary:
			hits = int((cd.get("judge", {}) as Dictionary).get("crit_hits", 0))
	print("combat.json judge.crit_hits = %d" % hits)
	var bad := bad_fit.size() + (0 if hits >= 1 else 1)
	print("결과: %s" % ("PASS" if bad == 0 else "FAIL(%d)" % bad))
	quit(0 if bad == 0 else 1)
