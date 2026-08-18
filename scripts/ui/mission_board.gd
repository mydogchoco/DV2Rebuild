class_name MissionBoard
extends CanvasLayer

const MISSION_UI := "res://assets/converted/mission_ui/%s.tres"
const STORY_COLS := 6
const STORY_CELL := Vector2(124.0, 104.0)

signal closed
signal changed

const _QUESTS := [
	{"key": "battles", "label": "전투 승리", "goal": 3},
	{"key": "hatches", "label": "부화하기", "goal": 1},
]

var _tab := 0
var _story_sel := 0
var _story_scroll := 0.0
var _story_list: ScrollContainer
var _back := "worldmap"
var _back_params: Dictionary = {}
var _win: Control

static func open(host: Node, tab := 0, back := "worldmap", back_params: Dictionary = {}) -> MissionBoard:
	var m := MissionBoard.new()
	m.layer = 30
	m._tab = tab
	m._back = back
	m._back_params = back_params
	host.add_child(m)
	m._build()
	return m

func close() -> void:
	closed.emit()
	queue_free()

func _build() -> void:
	if is_instance_valid(_story_list):
		_story_scroll = float(_story_list.scroll_vertical)
	_story_list = null
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	add_child(dim)
	var size := Vector2(880, 640) if _tab == 1 else Vector2(520, 340)
	_win = _popup(size, "미션")
	_mission_tabs(_win, _tab)
	if _tab == 1:
		_mission_story(_win)
	else:
		_mission_daily(_win)
	var closeb := Button.new()
	closeb.text = "닫기"
	closeb.size = Vector2(100, 40)
	closeb.position = Vector2(_win.size.x * 0.5 - 50, _win.size.y - 50)
	closeb.pressed.connect(close)
	_win.add_child(closeb)

func _rebuild(tab := -1) -> void:
	if tab >= 0:
		_tab = tab
	_build()

func _popup(size: Vector2, title_text: String) -> Control:
	var vis := get_viewport().get_visible_rect().size
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130
	win.patch_margin_top = 190
	win.patch_margin_right = 55
	win.patch_margin_bottom = 81
	win.size = size
	win.position = Vector2(round((vis.x - size.x) * 0.5), round((vis.y - size.y) * 0.5))
	add_child(win)
	if title_text != "":
		var tw := minf(size.x - 80.0, 300.0)
		var tbar := NinePatchRect.new()
		tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
		tbar.patch_margin_left = 20
		tbar.patch_margin_right = 20
		tbar.patch_margin_top = 12
		tbar.patch_margin_bottom = 12
		tbar.size = Vector2(tw, 52)
		tbar.position = Vector2((size.x - tw) * 0.5, 10)
		tbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(tbar)
		var tl := Label.new()
		tl.text = title_text
		tl.add_theme_font_size_override("font_size", 26)
		tl.add_theme_color_override("font_color", Color.WHITE)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.size = tbar.size
		tbar.add_child(tl)
	return win

func _mission_tabs(win: Control, tab: int) -> void:
	var defs := [["scene_worldmap_mission_tab_mission_kr", 0], ["scene_worldmap_mission_tab_story_kr", 1]]
	var x := 34.0
	for d in defs:
		var key := String(d[0])
		var idx := int(d[1])
		var p := MISSION_UI % key
		if not ResourceLoader.exists(p):
			continue
		var on := idx == tab
		var tr := TextureRect.new()
		tr.texture = load(p)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = Vector2(108, 46)
		tr.position = Vector2(x, 72.0 if on else 66.0)
		tr.modulate = Color.WHITE if on else Color(0.72, 0.68, 0.58)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(tr)
		var b := Button.new()
		b.flat = true
		b.size = tr.size
		b.position = tr.position
		b.pressed.connect(func(): _rebuild(idx))
		win.add_child(b)
		x += 116.0

func _mission_daily(win: Control) -> void:
	for i in _QUESTS.size():
		var qd: Dictionary = _QUESTS[i]
		var cnt := mini(UserDB.quest_count(String(qd["key"])), int(qd["goal"]))
		var done := cnt >= int(qd["goal"])
		var claimed := UserDB.quest_claimed(String(qd["key"]))
		var y := 134 + i * 70
		var nm := Label.new()
		nm.text = "%s  %d/%d" % [qd["label"], cnt, qd["goal"]]
		nm.add_theme_font_size_override("font_size", 20)
		nm.add_theme_color_override("font_color", Color(0.22, 0.15, 0.06))
		nm.position = Vector2(24, y)
		win.add_child(nm)
		var rw := Label.new()
		rw.text = "보상: 무작위 1종"
		rw.add_theme_font_size_override("font_size", 15)
		rw.add_theme_color_override("font_color", Color(0.45, 0.33, 0.14))
		rw.position = Vector2(24, y + 26)
		win.add_child(rw)
		var cb := Button.new()
		cb.size = Vector2(120, 42)
		cb.position = Vector2(win.size.x - 148, y + 2)
		cb.text = "수령 완료" if claimed else ("보상 받기" if done else "진행 중")
		cb.disabled = claimed or not done
		var qk: String = qd["key"]
		cb.pressed.connect(func():
			UserDB.claim_quest(qk)
			var pick := DailyQuest.roll_and_grant()
			var thost: Node = get_parent()
			Toast.show(thost if thost != null else self, "%s 획득!" % DailyQuest.describe(pick))
			changed.emit()
			_rebuild(0))
		win.add_child(cb)

func _mission_story(win: Control) -> void:
	var eps: Array = Data.story_episodes()
	if eps.is_empty():
		var warn := Label.new()
		warn.text = "(data/story.json 없음 — build_story_index.py 실행)"
		warn.add_theme_color_override("font_color", Color(0.3, 0.2, 0.08))
		warn.position = Vector2(40, 140)
		win.add_child(warn)
		return
	if _story_sel <= 0:
		_story_sel = StoryProgress.next_episode()
	_story_banner(win, _story_sel)
	var sc := ScrollContainer.new()
	sc.position = Vector2(30, 268)
	sc.size = Vector2(win.size.x - 60, win.size.y - 268 - 66)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = STORY_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	for no in eps:
		grid.add_child(_story_cell(int(no)))
	_story_list = sc
	_restore_story_scroll(sc)

func _restore_story_scroll(sc: ScrollContainer) -> void:
	if _story_scroll <= 0.0:
		return
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(_story_scroll)

func _story_seen(no: int) -> bool:
	return StoryProgress.seen(no)

func _story_unlocked(no: int) -> bool:
	return StoryProgress.unlocked(no)

func _story_thumb(no: int) -> Texture2D:
	for m in [1, 2, 3]:
		var p := "res://assets/converted/scenario/sn_%d_%d_illust.jpg" % [no, m]
		if ResourceLoader.exists(p):
			return load(p)
	return null

func _story_cell(no: int) -> Control:
	var ep := Data.story_episode(no)
	var unlocked := _story_unlocked(no)
	var cell := Control.new()
	cell.custom_minimum_size = STORY_CELL
	cell.size = STORY_CELL
	var tex := _story_thumb(no)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = STORY_CELL
		tr.clip_contents = true
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(tr)
	else:
		var plate := ColorRect.new()
		plate.color = Color(0.74, 0.66, 0.52)
		plate.size = STORY_CELL
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(plate)
	if not unlocked:
		var bp := MISSION_UI % "scene_worldmap_mission_story_black"
		if ResourceLoader.exists(bp):
			var bl := TextureRect.new()
			bl.texture = load(bp)
			bl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bl.size = STORY_CELL
			bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(bl)
		else:
			var d2 := ColorRect.new()
			d2.color = Color(0, 0, 0, 0.62)
			d2.size = STORY_CELL
			d2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(d2)
		var lp := "res://assets/converted/common_ui/common_lock.tres"
		if ResourceLoader.exists(lp):
			var lk := Sprite2D.new()
			lk.texture = load(lp)
			lk.position = STORY_CELL * 0.5
			cell.add_child(lk)
	var nl := Label.new()
	nl.text = "%d화" % no
	nl.add_theme_font_size_override("font_size", 19)
	nl.add_theme_color_override("font_color", Color(1, 1, 1))
	nl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	nl.add_theme_constant_override("outline_size", 5)
	nl.position = Vector2(6, 2)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(nl)
	var ti := Label.new()
	ti.text = String(ep.get("title", ""))
	ti.add_theme_font_size_override("font_size", 13)
	ti.add_theme_color_override("font_color", Color(1, 1, 1))
	ti.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	ti.add_theme_constant_override("outline_size", 4)
	ti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ti.position = Vector2(3, STORY_CELL.y - 38.0)
	ti.size = Vector2(STORY_CELL.x - 6.0, 36.0)
	ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(ti)
	var b := Button.new()
	b.flat = true
	b.size = STORY_CELL
	b.tooltip_text = String(ep.get("title", ""))
	var sel := no
	b.pressed.connect(func():
		_story_sel = sel
		_rebuild(1))
	cell.add_child(b)
	return cell

func _story_banner(win: Control, no: int) -> void:
	var ep := Data.story_episode(no)
	var unlocked := _story_unlocked(no)
	var bw := win.size.x - 60.0
	var bh := 135.0
	var top := Vector2(30.0, 122.0)
	var pan := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 102.0 / 255.0)
	sb.set_corner_radius_all(12)
	pan.add_theme_stylebox_override("panel", sb)
	pan.size = Vector2(bw, bh)
	pan.position = top
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(pan)
	var cov := NinePatchRect.new()
	cov.texture = load("res://assets/converted/ninepatch_ui/9patch_box_cover.tres")
	cov.patch_margin_left = 16
	cov.patch_margin_right = 16
	cov.patch_margin_top = 16
	cov.patch_margin_bottom = 16
	cov.size = pan.size
	cov.position = top
	cov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(cov)
	var nl := Label.new()
	nl.text = "%d화" % no
	nl.add_theme_font_size_override("font_size", 26)
	nl.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.position = top + Vector2(10, 0)
	nl.size = Vector2(84, bh)
	win.add_child(nl)
	var tex := _story_thumb(no)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = Vector2(148, 100)
		tr.position = top + Vector2(100, (bh - 100) * 0.5)
		tr.clip_contents = true
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(tr)
	var tl := Label.new()
	tl.text = String(ep.get("title", "(제목 없음)"))
	tl.add_theme_font_size_override("font_size", 28)
	tl.add_theme_color_override("font_color", Color(1, 1, 1))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.position = top + Vector2(264, 20)
	tl.size = Vector2(bw - 264 - 96, 34)
	win.add_child(tl)
	var sub := ""
	var need := int(ep.get("unlock_level", 0))
	if not StoryProgress.implemented(no):
		sub = "현재 미구현: 영구 잠금"
	else:
		var conds: Array[String] = []
		var prev := StoryProgress.previous_episode(no)
		if prev > 0:
			conds.append("%d화 관람" % prev)
		if need > 0:
			conds.append("드래곤 %d레벨" % need)
		if not conds.is_empty():
			sub = "개방조건: " + " · ".join(conds)
	var sl := Label.new()
	sl.text = sub
	sl.add_theme_font_size_override("font_size", 16)
	sl.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76) if unlocked else Color(1, 0.66, 0.5))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = top + Vector2(264, 60)
	sl.size = Vector2(bw - 264 - 96, 24)
	win.add_child(sl)
	var ql := Label.new()
	ql.text = StoryProgress.banner_line(no)
	ql.add_theme_font_size_override("font_size", 15)
	ql.add_theme_color_override("font_color",
		Color(0.72, 0.95, 0.72) if StoryProgress.gate_cleared(no) else Color(1, 0.86, 0.5))
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ql.position = top + Vector2(264, 86)
	ql.size = Vector2(bw - 264 - 96, 42)
	win.add_child(ql)
	var pp := MISSION_UI % "scene_worldmap_mission_btn_play"
	var pb := Button.new()
	pb.flat = true
	pb.size = Vector2(72, 72)
	pb.position = top + Vector2(bw - 88, (bh - 72) * 0.5)
	pb.disabled = not unlocked
	if ResourceLoader.exists(pp):
		var ps := Sprite2D.new()
		ps.texture = load(pp)
		ps.position = pb.size * 0.5
		if not unlocked:
			ps.modulate = Color(0.5, 0.5, 0.5)
		pb.add_child(ps)
	else:
		pb.text = "▶"
	var epn := no
	pb.pressed.connect(func():
		if not StoryProgress.implemented(epn):
			Toast.show(get_tree().current_scene, "현재 구현되지 않은 스토리입니다 (%d화)" % epn)
			return
		var play := func() -> void:
			var back := _back
			var bp := _back_params
			close()
			Scenes.goto("story", {"no": epn, "part": 0, "back": back, "back_params": bp})
		if StoryProgress.seen(epn):
			_confirm_review(epn, play)
		else:
			play.call())
	win.add_child(pb)

func _confirm_review(epn: int, play: Callable) -> void:
	var ep := Data.story_episode(epn)
	var p := FramedWindow.open(self, "다시보기", Vector2(640.0, 330.0))
	p.add_body_label("%d화. %s을 다시보시겠습니까?" % [epn, String(ep.get("title", ""))])
	p.add_action_button("확인", func() -> void:
		p.close()
		play.call(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 - 110.0, p.win_size.y - 60.0))
	p.add_action_button("취소", func() -> void: p.close(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 + 110.0, p.win_size.y - 60.0))
