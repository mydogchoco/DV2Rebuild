class_name MissionLayer
extends CanvasLayer
## 미션 창 — 원작 `MissionLayer`(탭 껍데기) + `MissionStoryLayer`(스토리 탭) + `MissionStoryCell`.
## render 층(CLAUDE.md §8). 포팅 카드 = `docs/ref/porting/MissionStoryLayer.md`.
##
## ## 왜 여기 있나 (2026-07-30 이전: cave.gd 안)
##
## 원작에서 이 창은 **메인 화면(월드맵) 위에 뜨는 독립 레이어**다:
##   `WorldMapScene.c:13371` — `MissionLayer::create(4)` + `setStoryLayerScrollPos(-1.0, 1.5)`
##   후 월드맵 씬에 z=0xc / tag=0x37 로 얹는다. 수동 진입은 `onClickMenu` tag 0x11.
## 우리 구현은 `cave.gd` 안에 있어서 메인 화면의 '미션' 칸이 **동굴 씬으로 이동**한 뒤
## 팝업을 여는 형태였다(`Scenes.goto("cave", {"open": "quests"})`). 원작과 다르고,
## 창을 닫으면 월드맵이 아니라 동굴에 남는 문제가 있었다.
## ⇒ `StatusLayer` 와 같은 방식으로 떼어내 **어느 씬 위에서든 제자리에서** 뜬다.
##
## ## 탭
##
## 원작 탭 4개: 미션(`tab_mission_%s`) · 일일미션(`addimg/mission/tab_dailymission_%s`) ·
##   도감미션(`tab_bookmission_%s`) · 스토리(`tab_story_%s`) — `MissionLayer::initWidget`.
##   `addimg/` 는 우리 덤프에 없고(⚪), 도감미션(`MissionDragonLayer`)은 미구현이라
##   지금은 **[미션][스토리] 2탭**만 띄운다. 프레임은 원작 그대로.

const MISSION_UI := "res://assets/converted/mission_ui/%s.tres"
const STORY_COLS := 6
const STORY_CELL := Vector2(124.0, 104.0)

## 창을 닫았다(호스트가 필요하면 자기 갱신).
signal closed
## 보상 수령 등으로 재화·진행도가 바뀌었다 → 호스트 HUD 갱신용.
signal changed

## 일일 퀘스트(원작 일일미션 탭 대응). town.gd 와 동일 데이터/카운터(UserDB quest_count/claim_quest).
const _QUESTS := [
	{"key": "battles", "label": "전투 승리", "goal": 3, "gold": 300},
	{"key": "hatches", "label": "부화하기", "goal": 1, "gold": 200},
]

var _tab := 0          # 0=미션(일일 퀘스트) · 1=스토리
var _story_sel := 0    # 스토리 탭에서 배너에 띄운 회차(0=자동: 다음 볼 회차)
## ▶ 재생 후 스토리 화면에서 돌아올 곳. 원작은 메인 화면이므로 기본값이 worldmap 이다.
var _back := "worldmap"
var _back_params: Dictionary = {}
var _win: Control


## 원작 `MissionLayer::create(tab)` 대응. 호스트 씬 위에 바로 얹는다.
static func open(host: Node, tab := 0, back := "worldmap", back_params: Dictionary = {}) -> MissionLayer:
	var m := MissionLayer.new()
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


# ═══════════════════════════════════════════════════════════════════════════ 껍데기
func _build() -> void:
	# ⚠️ `queue_free()` 는 **프레임 끝**에 지운다 — 같은 프레임에 재빌드하면 옛 창이 트리에
	#    남아 새 창과 겹쳐 그려지고, 화면에는 옛 내용이 보인다(`--ep=` 지정이 무시되던 원인).
	#    제자리 재빌드는 즉시 제거가 맞다.
	for c in get_children():
		remove_child(c)
		c.free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	# 오프셋까지 함께 세우는 형태로 쓴다 — `orig_popup.gd` 가 기록한 함정(앵커만 바꾸면 rect 0×0
	# 으로 굳을 수 있다)을 피하는 쪽이다. ⚠️ 여기서는 `set_anchors_preset` 도 정상 동작했다
	# (실측: 팝업 밖 밝기 157 → 70, 알파 0.55 와 일치) — 동작 차이가 아니라 표기 통일이다.
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


## 탭 전환·보상 수령 후 제자리 재빌드(종전에는 CanvasLayer 를 free 하고 새로 만들었다).
func _rebuild(tab := -1) -> void:
	if tab >= 0:
		_tab = tab
	_build()


## 원작 `PopupLayer::setContentSprite("9patch/popup4.png", …)` 창 껍데기.
## ⚠️ `cave.gd::_orig_popup` 과 **같은 레시피의 복사본**이다(프레임·capInsets·제목바 폭 동일).
##    cave 쪽에는 이 창 외에도 3개 팝업이 물려 있어 공용화하면 그 3개의 픽셀이 흔들린다 —
##    사용자가 이 창들을 눈으로 검수해 온 이력이 있어 지금은 복제를 택했다(🟡).
##    한쪽을 고치면 반드시 다른 쪽도 고칠 것.
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


## 원작 `MissionLayer::initWidget` 의 탭 띠. 프레임 = `scene/worldmap/mission/tab_*_kr.png`.
## 원작은 언어 변형(%s = kr/en/jp)만 있고 on/off 프레임이 없다 → 선택 상태는
## **밝기 + 살짝 내린 위치**로 표시한다(원작 스크린샷도 선택 탭이 앞으로 나온다).
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


## 기존 일일 퀘스트(원작 일일미션 탭 대응).
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
		rw.text = "보상: %d G" % qd["gold"]
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
		var qg: int = int(qd["gold"])
		cb.pressed.connect(func():
			UserDB.claim_quest(qk)
			UserDB.add_currency("gold", qg)
			changed.emit()
			_rebuild(0))
		win.add_child(cb)


# ── 스토리 탭 ────────────────────────────────────────────────────────────────
## 원작 `MissionStoryLayer` 이식. 근거(디컴프 리터럴):
##   · 상단 배너 = `RoundedLayer::create(w-20, 135.0, 0x66000000, …)` + Scale9 `9patch/box_cover.png`
##     (`setTopList` @019eed88) — 회차 번호 / 썸네일 / 제목 / 개방조건 / ▶
##   · ▶ = `scene/worldmap/mission/btn_play.png` (`onClickStoryPlay` @019efdd0)
##   · 잠금 셀 = `scene/worldmap/mission/story_black.png` + `common/lock.png` (`tableCellAtIndex`)
##   · 문자열 = `MissionMsg1` "%d화" · `MissionMsg2` "개방조건: 드래곤 %d레벨" (stringsData_KR.xml)
## 목차(제목·챕터·해금레벨) = `data/story.json`.
## ⚠️ 종전 주석의 "서버 유실"은 오진이었다 — 원작은 **로컬 SQLite** `info_scenario_v2`
##    (`select db_no, min_lv, point, title, daynight … `, `ScenarioData::setInfo`)에서 읽었다.
##    그 `.db` 가 우리 덤프에 없어 값은 여전히 유실이지만 출처는 서버가 아니다.
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
	# 격자 — 회차가 146개라 스크롤한다.
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


## 관람 여부·해금 판정은 **규칙**이라 logic 층이 갖는다(§8) — `scripts/systems/story_quest.gd`.
##   레벨 게이트(`data/story.json` `_unlock`, ASSUMPTION) **AND** 서브퀘스트 완료(원작 하드코딩).
func _story_seen(no: int) -> bool:
	return StoryProgress.seen(no)


func _story_unlocked(no: int) -> bool:
	return StoryProgress.unlocked(no)


## 회차 썸네일 = 그 회차의 삽화(`scenario/sn_<no>_<m>_illust.jpg`). 삽화가 없는 회차가 더 많다
## (146화 중 40여 편) → 없으면 null 을 돌려주고 호출부가 번호판으로 대신한다.
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
	# 잠금 — 원작 story_black(어두운 막) + common/lock.
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
	# 회차 번호(원작 MissionMsg1 "%d화") — 좌상단.
	var nl := Label.new()
	nl.text = "%d화" % no
	nl.add_theme_font_size_override("font_size", 19)
	nl.add_theme_color_override("font_color", Color(1, 1, 1))
	nl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	nl.add_theme_constant_override("outline_size", 5)
	nl.position = Vector2(6, 2)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(nl)
	# 🟡 원작 이탈: 원작 셀은 **썸네일 + 회차번호**뿐이다. 우리 덤프의 삽화는 146화 중 40여 편에만
	# 있어(`scenario/sn_*_illust.jpg`) 대부분 빈 판이 되므로 제목을 작게 얹어 목록을 읽히게 한다.
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


## 상단 배너(원작 setTopList): 회차 / 썸네일 / 제목 / 개방조건 / ▶.
func _story_banner(win: Control, no: int) -> void:
	var ep := Data.story_episode(no)
	var unlocked := _story_unlocked(no)
	var bw := win.size.x - 60.0
	var bh := 135.0
	var top := Vector2(30.0, 122.0)
	# 원작 RoundedLayer(w-20, 135, 검정 40%) — 아틀라스 프레임이 아니라 코드로 그리는 레이어다.
	var pan := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 102.0 / 255.0)
	sb.set_corner_radius_all(12)
	pan.add_theme_stylebox_override("panel", sb)
	pan.size = Vector2(bw, bh)
	pan.position = top
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(pan)
	# 원작 테두리 = Scale9 `9patch/box_cover.png`.
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
	# 회차 번호(좌).
	var nl := Label.new()
	nl.text = "%d화" % no
	nl.add_theme_font_size_override("font_size", 26)
	nl.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.position = top + Vector2(10, 0)
	nl.size = Vector2(84, bh)
	win.add_child(nl)
	# 썸네일.
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
	# 제목.
	var tl := Label.new()
	tl.text = String(ep.get("title", "(제목 없음)"))
	tl.add_theme_font_size_override("font_size", 28)
	tl.add_theme_color_override("font_color", Color(1, 1, 1))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.position = top + Vector2(264, 20)
	tl.size = Vector2(bw - 264 - 96, 34)
	win.add_child(tl)
	# 개방조건(원작 MissionMsg2).
	var sub := ""
	var need := int(ep.get("unlock_level", 0))
	if need > 0:
		sub = "개방조건: 드래곤 %d레벨" % need
	elif no > 1:
		sub = "개방조건: %d화 관람" % (no - 1)
	var sl := Label.new()
	sl.text = sub
	sl.add_theme_font_size_override("font_size", 16)
	sl.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76) if unlocked else Color(1, 0.66, 0.5))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = top + Vector2(264, 60)
	sl.size = Vector2(bw - 264 - 96, 24)
	win.add_child(sl)
	# 서브미션(원작 `QuestTitleSub` = "서브미션 : %s") + 진행 카운터.
	# 원작은 이 조건을 **클라가** 판정했다 — `ScenarioSubQuestData` + `QuestData`(§ StoryQuest).
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
	# ▶ 재생(원작 btn_play + onClickStoryPlay).
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
	var no_lines := bool(ep.get("no_lines", false))
	pb.pressed.connect(func():
		if no_lines:
			Toast.show(get_tree().current_scene, "이 회차 대사가 추출본에 없습니다 (%d화)" % epn)
			return
		var play := func() -> void:
			var back := _back
			var bp := _back_params
			close()
			Scenes.goto("story", {"no": epn, "part": 0, "back": back, "back_params": bp})
		# 이미 본 회차는 **재관람 확인**을 먼저 띄운다 — 원작 `ScenarioManager::setIsReview`
		# + 문자열 `<ScenarioReViewContent>` "{N화. 제목}을 다시보시겠습니까?".
		if StoryProgress.seen(epn):
			_confirm_review(epn, play)
		else:
			play.call())
	win.add_child(pb)


## 재관람 확인 — 원작 `<ScenarioReViewContent>` = "{#002940:%1$d화. %2$s}을 다시보시겠습니까?".
## 원작은 `ScenarioManager::setIsReview(true)` 로 재관람 모드를 표시하는데, 우리는 관람 기록이
## 이미 남아 있어(`scenario_<no>_0`) 완료 알림만 건너뛰면 된다(story.gd `_finish`).
func _confirm_review(epn: int, play: Callable) -> void:
	var ep := Data.story_episode(epn)
	var p := OrigPopup.open(self, "다시보기", Vector2(640.0, 330.0))
	var l := Label.new()
	l.text = "%d화. %s을 다시보시겠습니까?" % [epn, String(ep.get("title", ""))]
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.16, 0.09, 0.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = Vector2(20.0, 62.0)
	l.size = Vector2(p.win_size.x - 40.0, 80.0)
	p.content.add_child(l)
	p.add_action_button("확인", func() -> void:
		p.close()
		play.call(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 - 110.0, p.win_size.y - 60.0))
	p.add_action_button("취소", func() -> void: p.close(), 0, Vector2(200.0, 56.0),
		Vector2(p.win_size.x * 0.5 + 110.0, p.win_size.y - 60.0))
