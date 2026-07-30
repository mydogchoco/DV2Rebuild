extends SceneTree
# 크리티컬 스파인 산출물 검증 — scenes/dragons/*_critical.tscn 전수 로드 후
#   (1) AnimationPlayer 존재 (2) "animation" 애니 존재 (3) 스프라이트 텍스처가 실제로 물렸는지
# 를 확인한다. (3)이 핵심 — 아틀라스 링크가 빠진 채 빌드된 사고(worldmap_fx 12종)를 잡기 위해서다.
# Run: godot --headless --script res://scripts/tools/test_critical_spines.gd
func _initialize() -> void:
	var da := DirAccess.open("res://scenes/dragons")
	if da == null:
		print("FAIL: scenes/dragons 없음"); quit(1); return
	var total := 0
	var no_ap := []
	var no_anim := []
	var no_tex := []
	var zero_len := []
	for fn in da.get_files():
		if not (fn.ends_with("_critical.tscn")):
			continue
		total += 1
		var ps := load("res://scenes/dragons/%s" % fn) as PackedScene
		if ps == null:
			no_tex.append(fn); continue
		var inst = ps.instantiate()
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap == null:
			no_ap.append(fn)
		# battle.gd::_critical_spine 과 같은 후보 순서로 본다(원작은 "animation" 만 쓰지만
		# dragon_4007 은 "critical" 이다). dragon_9999 는 크리티컬 애니가 아예 없는 플레이스홀더.
		elif not (ap.has_animation("animation") or ap.has_animation("critical")):
			if not fn.begins_with("dragon_9999"):
				no_anim.append(fn)
		else:
			var an := "animation" if ap.has_animation("animation") else "critical"
			if ap.get_animation(an).length <= 0.0:
				zero_len.append(fn)
		# 텍스처가 실제로 물렸는지: Sprite2D 를 하나라도 찾아 AtlasTexture.atlas 확인
		var ok_tex := false
		var stack: Array = [inst]
		while not stack.is_empty():
			var n = stack.pop_back()
			if n is Sprite2D and n.texture is AtlasTexture and (n.texture as AtlasTexture).atlas != null:
				ok_tex = true
				break
			for c in n.get_children():
				stack.append(c)
		if not ok_tex:
			no_tex.append(fn)
		inst.free()
	print("검사 %d개" % total)
	print("  AnimationPlayer 없음 : %d %s" % [no_ap.size(), no_ap.slice(0, 3)])
	print("  'animation' 없음     : %d %s" % [no_anim.size(), no_anim.slice(0, 3)])
	print("  길이 0               : %d %s" % [zero_len.size(), zero_len.slice(0, 3)])
	print("  텍스처 미연결        : %d %s" % [no_tex.size(), no_tex.slice(0, 3)])
	var bad := no_ap.size() + no_anim.size() + no_tex.size() + zero_len.size()
	print("결과: %s" % ("PASS" if bad == 0 else "FAIL(%d)" % bad))
	quit(0 if bad == 0 else 1)
