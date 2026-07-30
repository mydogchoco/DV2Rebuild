class_name PartySelect
extends RefCounted
## 출전 편성 오버레이 — 원작 `AdventureScene::setAddDragonPopupLayer`(AdventureScene.c:32449-32975).
##
## ⚠️ 2026-07-27 전면 재작성. 이전 구현은 `Select3DragonsLayer` 를 근거로 삼았는데 **그 클래스는
##    던전 경로가 아니다** — 쓰는 곳은 `ExpeditionScene`·`ExpeditionRoomScene`·`DispatchLayer`·
##    `SelectAllDragons_4thRaidPopup`(원정/파견/레이드)뿐이다. 던전은 아래 구조를 쓴다.
##
## 원작 흐름(사용자 확정 2026-07-27):
##   월드맵 던전 클릭 → 난이도 선택 → **바로 입장**(`WorldMapPopupLayer::setAdventure`)
##   → `AdventureScene::initMainDragon` 이 `Dragon::isSelected` 로 **리더 1마리**를 세움
##   → 드래곤 추가는 입장 **후** `clickAddDragon` → `setAddDragonPopupLayer`
##   일반 탐험은 리더 혼자 나선다. 3마리는 레이드·영웅 단계·유타칸 밤·카데스의 공간·혼돈의 틈새뿐.
##
## 원작 `setAddDragonPopupLayer` 구성 요소(디컴파일에서 확인한 것만):
##   · `CCLayerColor`                      → 어두운 막
##   · `CCTableView` + `setVerticalFillOrder(0)` → 세로 스크롤 목록(위→아래)
##   · `Dragon::getImagePathSpineJson` + `getImagePathSpineText`
##     → `CCSkeletonAnimation::createWithFile(json, atlas, **1.0**)`  ← **초상이 아니라 스파인**
##   · `9patch/bar1`(×2) `9patch/bar2` `9patch/bar4` `9patch/bar_bg1` → Scale9 게이지
##   · `scene/adventure/stat_box3_bg` → 셀 배경
##   · 셀 내부 좌표(발췌): 게이지 capInsets `Rect(12,14,36,2)` / `Rect(25,14,10,2)`,
##     목록 크기 `(화면폭-20, 화면높이+20)`, 오프셋 `(10,-15)`, 셀 높이 60
##
## 미보유 자산(CLAUDE.md §10): `common/bg/info_bg.png` · `newCommon/pss_btn_x.png` 가 우리 덤프에
##   없다 → 보유한 `9patch/popup5` + `common/close_btn` 으로 대체한다.
##
## 사용:
##   `PartySelect.open_run(host, current_uids, func(picked: Array): ...)`  — 던전 편성(확정 필수)
##   `PartySelect.open(host)` — 편성만(둥지 등). 확정 콜백 없이 닫기 전용.

const POPUP5 := "res://assets/converted/ninepatch_ui/9patch_popup5.tres"
const TITLE_BG := "res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres"
const CLOSE_BTN := "res://assets/converted/common_ui/common_close_btn.tres"
const STAT_BOX_BG := "res://assets/converted/adventure_ui/scene_adventure_stat_box3_bg.tres"
const BAR_BG1 := "res://assets/converted/ninepatch_ui/9patch_bar_bg1.tres"
const BAR1 := "res://assets/converted/ninepatch_ui/9patch_bar1.tres"
const BAR4 := "res://assets/converted/ninepatch_ui/9patch_bar4.tres"

const BW := 820.0
const BH := 600.0
const CELL_H := 92.0            # 원작 셀 60pt × ASSET_SCALE(4/3) ≒ 80 + 여백
const MAX_PARTY := 3


## 던전 편성 — 확정해야 닫힌다(원작도 출전 인원을 정해야 진행된다).
static func open_run(host: Node, current: Array, on_confirm: Callable) -> void:
	_build(host, current, on_confirm, true)


## 편성만(확정 없음).
static func open(host: Node, _unused := Callable(), _unused2 := Callable()) -> void:
	_build(host, UserDB.party(), Callable(), false)


static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## 드래곤 스파인 노드 — 원작이 초상이 아니라 `CCSkeletonAnimation` 을 쓴다.
## 변환본은 `scenes/dragons/dragon_<id>_<stage>.tscn`. 배율 1.0(원작 createWithFile 세 번째 인자)에
## 셀 높이에 맞춘 축소만 얹는다.
static func _spine_node(id: int, stage: String, box: Vector2) -> Node2D:
	for st in [stage, "adult", "child", "baby"]:
		var p := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, st]
		if ResourceLoader.exists(p):
			var holder := Node2D.new()
			var inst = (load(p) as PackedScene).instantiate()
			holder.add_child(inst)
			# 스파인은 원점 기준이라 셀 안에 들어오도록 축소·정렬만 한다.
			holder.scale = Vector2.ONE * (box.y / 260.0)
			var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
			if ap:
				for cand in ["wait", "animation", "idle"]:
					if ap.has_animation(cand):
						ap.get_animation(cand).loop_mode = Animation.LOOP_LINEAR
						ap.play(cand)
						break
			return holder
	return null


static func _stage_of(d: Dictionary) -> String:
	var lv := int(d.get("level", 1))
	return "adult" if lv >= 25 else ("child" if lv >= 10 else "baby")


## Scale9 게이지 한 줄. `bar_bg1` 위에 `bar1`(HP) 또는 `bar4`(EXP) 를 비율만큼 덮는다.
static func _gauge(parent: Control, pos: Vector2, w: float, ratio: float, fill: String) -> void:
	var bg := NinePatchRect.new()
	if ResourceLoader.exists(BAR_BG1):
		bg.texture = load(BAR_BG1)
	bg.patch_margin_left = 6; bg.patch_margin_right = 6
	bg.position = pos; bg.size = Vector2(w, 14)
	parent.add_child(bg)
	var fg := NinePatchRect.new()
	if ResourceLoader.exists(fill):
		fg.texture = load(fill)
	fg.patch_margin_left = 6; fg.patch_margin_right = 6
	fg.position = pos + Vector2(2, 2)
	fg.size = Vector2(maxf(4.0, (w - 4) * clampf(ratio, 0.0, 1.0)), 10)
	parent.add_child(fg)


static func _build(host: Node, current: Array, on_confirm: Callable, require_confirm: bool) -> void:
	var vis: Vector2 = host.get_viewport_rect().size
	var overlay := CanvasLayer.new()
	overlay.layer = 30
	host.add_child(overlay)

	# 원작 CCLayerColor — 어두운 막.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = vis
	overlay.add_child(dim)

	var win := Control.new()
	win.size = Vector2(BW, BH)
	win.position = (vis - Vector2(BW, BH)) * 0.5
	overlay.add_child(win)

	var frame := NinePatchRect.new()
	if ResourceLoader.exists(POPUP5):
		frame.texture = load(POPUP5)
	frame.patch_margin_left = 100; frame.patch_margin_top = 105
	frame.patch_margin_right = 75; frame.patch_margin_bottom = 135
	frame.size = Vector2(BW, BH)
	win.add_child(frame)

	var title_bg := NinePatchRect.new()
	if ResourceLoader.exists(TITLE_BG):
		title_bg.texture = load(TITLE_BG)
	title_bg.patch_margin_left = 24; title_bg.patch_margin_right = 24
	title_bg.position = Vector2(BW * 0.5 - 170, 18)
	title_bg.size = Vector2(340, 52)
	win.add_child(title_bg)

	var title := Label.new()
	title.text = "출전 드래곤 선택"
	title.size = Vector2(340, 52)
	title.position = title_bg.position
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win.add_child(title)

	var picked: Array = []
	for u in current:
		if not UserDB.get_dragon(int(u)).is_empty() and picked.size() < MAX_PARTY:
			picked.append(int(u))

	var count := Label.new()
	count.position = Vector2(46, 78)
	count.size = Vector2(BW - 92, 26)
	win.add_child(count)

	# 원작 CCTableView(setVerticalFillOrder 0 = 위→아래) 대응 스크롤 목록.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 112)
	scroll.size = Vector2(BW - 60, BH - 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size.x = BW - 76
	scroll.add_child(list)

	var refresh := func():
		count.text = "선택 %d / %d   —   비우면 리더가 혼자 나섭니다" % [picked.size(), MAX_PARTY]

	for d in UserDB.dragons():
		var uid := int(d["uid"])
		var id := int(d["id"])
		var ddef: Dictionary = Data.get_dragon(id)
		var cell := Button.new()
		cell.flat = true
		cell.custom_minimum_size = Vector2(BW - 76, CELL_H)
		list.add_child(cell)

		var bgp := NinePatchRect.new()
		if ResourceLoader.exists(STAT_BOX_BG):
			bgp.texture = load(STAT_BOX_BG)
		bgp.patch_margin_left = 12; bgp.patch_margin_right = 12
		bgp.patch_margin_top = 12; bgp.patch_margin_bottom = 12
		bgp.size = Vector2(BW - 76, CELL_H)
		bgp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bgp)

		var sp := _spine_node(id, _stage_of(d), Vector2(CELL_H, CELL_H))
		if sp:
			sp.position = Vector2(64, CELL_H * 0.86)
			cell.add_child(sp)

		# 행동불능(원작 `Dragon::isStun`) — 던전 패배로 걸리며 회복 전까지 출전 불가.
		# 원작도 편성 목록에서 `Dragon::isStun` 을 검사한다(AddDragonCell.c:1310).
		var down := UserDB.is_down(uid)

		var nm := Label.new()
		nm.text = "%s   Lv.%d" % [String(ddef.get("name", "드래곤")), int(d.get("level", 1))]
		if down:
			nm.text += "   [행동불능 %s]" % Incapacitation.remain_text(
				UserDB.cure_time(uid), int(Time.get_unix_time_from_system()))
			nm.add_theme_color_override("font_color", Color(0.85, 0.45, 0.45))
		nm.position = Vector2(126, 12)
		nm.size = Vector2(420, 24)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(nm)

		# 원작 셀의 Scale9 게이지 2줄(bar1 = HP 계열, bar4 = EXP 계열).
		_gauge(cell, Vector2(126, 44), 300, 1.0, BAR1)
		_gauge(cell, Vector2(126, 64), 300, clampf(float(d.get("exp", 0)) / 1000.0, 0.05, 1.0), BAR4)

		var mark := Label.new()
		mark.position = Vector2(BW - 160, 30)
		mark.size = Vector2(80, 30)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(mark)

		var paint := func():
			var at := picked.find(uid)
			if down:
				mark.text = "회복 중"
				bgp.modulate = Color(0.5, 0.42, 0.42)
				return
			mark.text = "출전 %d" % (at + 1) if at >= 0 else ""
			bgp.modulate = Color(1, 1, 1) if at >= 0 else Color(0.72, 0.72, 0.76)
		paint.call()

		if down:
			# 행동불능 드래곤은 고를 수 없다(원작 CaveToastMsg18 "드래곤이 기절 상태 입니다.").
			picked.erase(uid)
			cell.disabled = true
			continue

		cell.pressed.connect(func():
			var at := picked.find(uid)
			if at >= 0:
				picked.remove_at(at)
			elif picked.size() < MAX_PARTY:
				picked.append(uid)
			# 표시 갱신 — 순번이 바뀔 수 있으니 전체를 다시 칠한다.
			for c in list.get_children():
				if c.has_meta("paint"):
					(c.get_meta("paint") as Callable).call()
			refresh.call())
		cell.set_meta("paint", paint)

	refresh.call()

	var dismiss := func(commit: bool):
		if commit:
			UserDB.clear_party()
			for u in picked:
				UserDB.toggle_party(int(u))
		if is_instance_valid(overlay):
			overlay.queue_free()
		if commit and on_confirm.is_valid():
			on_confirm.call(picked.duplicate())

	var go := Button.new()
	go.text = "출발"
	go.size = Vector2(160, 46)
	go.position = Vector2(BW - 210, BH - 62)
	go.pressed.connect(func(): dismiss.call(true))
	win.add_child(go)

	if not require_confirm:
		var close := TextureButton.new()
		if ResourceLoader.exists(CLOSE_BTN):
			close.texture_normal = load(CLOSE_BTN)
		close.position = Vector2(BW - 58, 14)
		close.pressed.connect(func(): dismiss.call(false))
		win.add_child(close)
		dim.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				dismiss.call(false))
