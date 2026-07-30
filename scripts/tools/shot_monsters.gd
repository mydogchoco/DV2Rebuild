extends SceneTree
## 몬스터 스파인 씬을 격자로 조립해 한 장에 담는다 — **에셋 식별용**.
##
## 왜: 위키에서 이름·스탯은 복원했지만 **어느 몬스터 스프라이트인지**는 못 정한 것들이 있다
## (우노 5보스 등). `extract_wiki.py` 는 순번으로 자동 배정만 하고,
## `data/_monster_mapping_notes.json` 과 어긋나는 구간이 있다.
## 아틀라스 페이지(`<id>_spine.png`)는 **부품 더미**라 눈으로 못 고른다 ⇒ 조립본이 필요하다.
##
## 실행:
##   godot --path . --script res://scripts/tools/shot_monsters.gd -- --from=118 --to=135 \
##         --out=user://monsters.png [--cols=6] [--cell=260]
##
## 결과는 사용자에게 보여 주고 이름을 매칭받는다(CLAUDE.md §1 역할분담 — 에셋 식별은 사용자 몫).

func _initialize() -> void:
	var lo := 118
	var hi := 135
	var cols := 6
	var cell := 260
	var sc := 0.62
	var out := "user://monsters.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="): lo = int(a.substr(7))
		elif a.begins_with("--to="): hi = int(a.substr(5))
		elif a.begins_with("--cols="): cols = int(a.substr(7))
		elif a.begins_with("--cell="): cell = int(a.substr(7))
		elif a.begins_with("--scale="): sc = float(a.substr(8))
		elif a.begins_with("--out="): out = a.substr(6)
	_run(lo, hi, cols, cell, sc, out)

func _run(lo: int, hi: int, cols: int, cell: int, sc: float, out: String) -> void:
	var ids: Array = []
	for i in range(lo, hi + 1):
		if ResourceLoader.exists("res://scenes/monsters/monster_%d.tscn" % i):
			ids.append(i)
	if ids.is_empty():
		print("SHOT: 씬 없음"); quit(1); return
	var rows := int(ceil(float(ids.size()) / float(cols)))

	var vp := SubViewport.new()
	vp.size = Vector2i(cols * cell, rows * cell)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.92, 0.92, 0.94)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)

	for k in ids.size():
		var id: int = ids[k]
		var cx := float(k % cols) * cell + cell * 0.5
		var cy := float(k / cols) * cell + cell * 0.62
		var inst := (load("res://scenes/monsters/monster_%d.tscn" % id) as PackedScene).instantiate() as Node2D
		if inst == null:
			continue
		# 씬마다 크기가 제각각이라 셀에 맞춰 줄인다(대략치 — 식별용이라 정밀할 필요 없다).
		inst.position = Vector2(cx, cy)
		inst.scale = Vector2(sc, sc)
		vp.add_child(inst)
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap and ap.has_animation("wait"):
			ap.play("wait")
		var l := Label.new()
		l.text = "#%d" % id
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		l.position = Vector2(float(k % cols) * cell + 6, float(k / cols) * cell + 4)
		vp.add_child(l)

	await process_frame
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(out)
	print("SHOT monsters saved: ", out, "  (", ids.size(), "종)")
	quit(0)
