extends Control
## Cave (메인 로비). 참고: docs/OldRef_image/Cave.png
## 기능: 드래곤 육성·관리, 인벤토리 확인/사용, 도감 열람, 배경 스킨 변경.

const UI := "res://assets/converted/cave_ui/%s.tres"
const STAND := "res://assets/converted/stand_ui/stand_stand%d.tres"
const BG := "res://assets/converted/cave_bg/cavebg%d.jpg"
const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const SEED_OWNED := [{"id": 1, "level": 5}, {"id": 5, "level": 12}, {"id": 10, "level": 25}]
const SKIN_COUNT := 15
const STAND_COUNT := 16

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _stand_manifest: Dictionary = {}
var _battle_manifest: Dictionary = {}
var _portrait_manifests: Dictionary = {}   # dir -> manifest (캐시)
var _elem_icon: Sprite2D
var _bg: TextureRect
var _stage: Node2D
var _list_box: VBoxContainer
var _stat_label: RichTextLabel
var _overlay: Control

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var mf := FileAccess.open("res://assets/converted/cave_ui/_manifest.json", FileAccess.READ)
	if mf: _manifest = JSON.parse_string(mf.get_as_text())
	var sf := FileAccess.open("res://assets/converted/stand_ui/_manifest.json", FileAccess.READ)
	if sf: _stand_manifest = JSON.parse_string(sf.get_as_text())
	var bf := FileAccess.open("res://assets/converted/battle_ui/_manifest.json", FileAccess.READ)
	if bf: _battle_manifest = JSON.parse_string(bf.get_as_text())

	if SaveSystem.state["owned_dragons"].is_empty():
		for o in SEED_OWNED:
			SaveSystem.add_dragon(o["id"], o["level"])
		SaveSystem.state["currency"] = {"gold": 125000, "diamond": 980}
		SaveSystem.state["inventory"] = {"에너지 드링크": 3, "레벨업 물약": 12, "각성의 마석": 2, "문장": 47}
		SaveSystem.save_game()

	_build_background()
	_build_walls()
	_build_stage()
	_build_dragon_list()
	_build_bottom_bar()
	_build_menu()
	_build_topbar()
	_refresh()

# ---------- helpers ----------
func _ui_tex(name: String) -> AtlasTexture:
	var p := UI % name
	return load(p) if ResourceLoader.exists(p) else null

func _ui_sprite(name: String, scale := 1.0) -> Sprite2D:
	return _atlas_sprite("cave_ui", name, _manifest, scale)

## 임의 변환 아틀라스의 스프라이트 생성(회전/PMA 보정). 없으면 텍스처 없는 스프라이트 반환.
func _atlas_sprite(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p):
		s.texture = load(p)
	s.material = _pma
	if man.get(name, {}).get("rotated", false):
		s.rotation = PI / 2.0
		s.flip_h = true   # 회전 cocos 프레임: +90°와 함께 수직 반전(월드 기준) 보정
	s.scale = Vector2(scale, scale)
	return s

func _panel(col := Color(0, 0, 0, 0.55)) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _active() -> Dictionary:
	var owned: Array = SaveSystem.state["owned_dragons"]
	if owned.is_empty(): return {}
	var i: int = clampi(int(SaveSystem.state.get("active_dragon", 0)), 0, owned.size() - 1)
	return owned[i]

# ---------- build ----------
func _build_background() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)

func _build_walls() -> void:
	# 동굴 벽 프레임 (480/scene/cave/wall, 기본 wall/1). 원작 768x519 기준 → 높이맞춤.
	var man := {}
	var f := FileAccess.open("res://assets/converted/wall_ui/_manifest.json", FileAccess.READ)
	if f: man = JSON.parse_string(f.get_as_text())
	const S := 1080.0 / 519.0   # 화면 높이에 맞춤
	var dir := "res://assets/converted/wall_ui/%s.tres"
	# left
	_wall(dir % "scene_cave_wall_1_wall_left", man.get("scene_cave_wall_1_wall_left", {}), S,
		func(dw, _dh): return Vector2(dw / 2.0, 540))
	# right
	_wall(dir % "scene_cave_wall_1_wall_right", man.get("scene_cave_wall_1_wall_right", {}), S,
		func(dw, _dh): return Vector2(1920 - dw / 2.0, 540))
	# bottom (rotated + 원본이 뒤집혀 있어 수직 반전)
	_wall(dir % "scene_cave_wall_1_wall_bottom", man.get("scene_cave_wall_1_wall_bottom", {}), S,
		func(_dw, dh): return Vector2(960, 1080 - dh / 2.0), true)

func _wall(path: String, info: Dictionary, s: float, place: Callable, flip_v := false) -> void:
	if not ResourceLoader.exists(path): return
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.material = _pma
	if info.get("rotated", false):
		spr.rotation = PI / 2.0
	spr.scale = Vector2(s, s)
	var dw: float = float(info.get("w", 0)) * s
	var dh: float = float(info.get("h", 0)) * s
	var pos: Vector2 = place.call(dw, dh)
	if flip_v:
		var holder := Node2D.new()  # x축 기준 수직 반전
		holder.position = pos
		holder.scale = Vector2(1, -1)
		add_child(holder)
		holder.add_child(spr)
	else:
		spr.position = pos
		add_child(spr)

func _build_stage() -> void:
	_stage = Node2D.new()
	_stage.position = Vector2(980, 510)   # 화면 중앙 쪽으로(받침대가 하단 벽 안 가리게). 드래곤-받침대 상대거리 유지.
	add_child(_stage)

func _build_dragon_list() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(24, 120)
	sc.custom_minimum_size = Vector2(150, 600)
	sc.size = Vector2(150, 600)
	add_child(sc)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 10)
	sc.add_child(_list_box)

var _name_label: RichTextLabel
var _grade_label: Label

func _build_bottom_bar() -> void:
	# 골드 하단 배너 (참고 Cave2.jpg — cave.png에 전용 에셋이 없어 직접 제작)
	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.66, 0.22, 0.96)
	sb.set_corner_radius_all(18)
	sb.border_width_top = 3; sb.border_width_left = 3; sb.border_width_right = 3; sb.border_width_bottom = 3
	sb.border_color = Color(1, 0.9, 0.55, 0.8)
	bar.add_theme_stylebox_override("panel", sb)
	bar.position = Vector2(28, 928)
	bar.size = Vector2(1864, 150)
	add_child(bar)

	# 등급 배지 (원형)
	var badge := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.97, 0.85, 0.32)
	bsb.set_corner_radius_all(42)
	bsb.set_border_width_all(3); bsb.border_color = Color(0.6, 0.4, 0.1)
	badge.add_theme_stylebox_override("panel", bsb)
	badge.position = Vector2(20, 40); badge.size = Vector2(84, 84)
	bar.add_child(badge)
	_grade_label = Label.new()
	_grade_label.size = Vector2(84, 84)
	_grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_grade_label.add_theme_font_size_override("font_size", 30)
	_grade_label.add_theme_color_override("font_color", Color(0.35, 0.2, 0))
	badge.add_child(_grade_label)

	# 속성 아이콘 (별 대신) + 이름/레벨
	_elem_icon = Sprite2D.new()
	_elem_icon.material = _pma
	_elem_icon.position = Vector2(146, 32)
	bar.add_child(_elem_icon)
	_name_label = RichTextLabel.new()
	_name_label.bbcode_enabled = true
	_name_label.fit_content = true
	_name_label.scroll_active = false
	_name_label.position = Vector2(184, 12)
	_name_label.size = Vector2(440, 44)
	_name_label.add_theme_font_size_override("normal_font_size", 30)
	bar.add_child(_name_label)
	_stat_label = RichTextLabel.new()
	_stat_label.bbcode_enabled = true
	_stat_label.fit_content = true
	_stat_label.scroll_active = false
	_stat_label.position = Vector2(124, 74)
	_stat_label.size = Vector2(620, 40)
	_stat_label.add_theme_font_size_override("normal_font_size", 22)
	bar.add_child(_stat_label)

	var lv := Button.new()
	lv.text = "Lv+"
	lv.position = Vector2(1786, 10); lv.size = Vector2(64, 36)
	lv.pressed.connect(_on_levelup)
	bar.add_child(lv)

	# 탭: 아이템(2x2) / 젬(3) / 각성스킬(1) / 스킬(2)
	_tab_group(bar, 760, "item", "아이템", 4, 2)
	_tab_group(bar, 1010, "gem", "젬", 3, 3)
	_tab_group(bar, 1280, "skill", "각성스킬", 1, 1)   # 각성스킬 전용 아이콘 없음 → skill 아이콘 대용
	_tab_group(bar, 1470, "skill", "스킬", 2, 2)

func _tab_group(bar: Panel, x: int, _icon: String, label: String, count: int, cols: int) -> void:
	var lb := Label.new()
	lb.text = label
	lb.position = Vector2(x + 4, 18)
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.3, 0.18, 0))
	bar.add_child(lb)
	for i in count:
		var slot := _ui_sprite("scene_cave_attribute_bg", 0.82)
		slot.position = Vector2(x + 30 + (i % cols) * 52, 78 + (i / cols) * 50)
		bar.add_child(slot)

func _build_menu() -> void:
	# 우측 메뉴: 맨 위 = 동굴 스킨 변경(scene_cave_skin), 이하 도감/인벤토리/카드 (참고 Cave.png)
	# 원본과 통일 — 아이콘(버튼)만, 텍스트 없음. 균일 간격으로 세로 분산.
	var items := [["skin", _open_skin], ["book", _open_dex],
				  ["bag", _open_inventory], ["card", _open_cards]]
	var first_cy := 180   # 첫 버튼 중심 y
	var step := 190       # 균일 간격
	for i in items.size():
		_menu_button(items[i][0], items[i][1], first_cy + i * step)

func _menu_button(icon: String, cb: Callable, cy: int) -> void:
	# 투명 Button(클릭) + Sprite2D 아이콘(회전/PMA 처리). cy = 버튼 중심 y.
	const SIZE := 140
	var cx := 1920 - 24 - SIZE / 2   # 우측 여백 24
	var b := Button.new()
	b.flat = true
	b.position = Vector2(cx - SIZE / 2, cy - SIZE / 2)
	b.size = Vector2(SIZE, SIZE)
	b.pressed.connect(cb)
	add_child(b)
	var spr := _ui_sprite("scene_cave_%s" % icon, 2.0)
	spr.position = Vector2(cx, cy)   # 버튼 중심
	add_child(spr)

func _build_topbar() -> void:
	var top := Label.new()
	top.name = "TopCurrency"
	top.position = Vector2(960, 24)
	top.add_theme_font_size_override("font_size", 28)
	add_child(top)
	var x := Button.new()
	x.text = "✕"
	x.position = Vector2(1850, 16)
	x.size = Vector2(54, 54)
	x.pressed.connect(func(): get_tree().quit())
	add_child(x)

# ---------- refresh ----------
func _refresh() -> void:
	var skin_idx: int = int(SaveSystem.state.get("cave_skin", 0)) % SKIN_COUNT
	_bg.texture = load(BG % (skin_idx + 1))
	_refresh_dragon()
	_refresh_list()
	_refresh_stats()
	var c: Dictionary = SaveSystem.state["currency"]
	get_node("TopCurrency").text = "골드 %d    다이아 %d" % [int(c.get("gold", 0)), int(c.get("diamond", 0))]

func _refresh_dragon() -> void:
	for ch in _stage.get_children():
		ch.queue_free()
	# 받침대: stand 스킨 스프라이트 (480/stand.png). 디스크가 드래곤보다 넓게(참고 Cave.png).
	var si: int = int(SaveSystem.state.get("stand_skin", 0)) % STAND_COUNT
	var info = _stand_manifest.get("stand_stand%d" % (si + 1), {})
	var w: float = maxf(1.0, float(info.get("w", 305)))
	var ped_holder := Node2D.new()
	ped_holder.position = Vector2(0, 235)
	ped_holder.scale = Vector2(1, -1)   # x축 기준 반전(수직) — stand 원본이 뒤집혀 있음
	_stage.add_child(ped_holder)
	var ped := Sprite2D.new()
	ped.texture = load(STAND % (si + 1))
	ped.material = _pma
	if info.get("rotated", false):
		ped.rotation = PI / 2.0
	ped.scale = Vector2(620.0 / w, 620.0 / w)
	ped_holder.add_child(ped)
	var a := _active()
	if a.is_empty(): return
	var stage_name := Data.stage_for_level(int(a["level"]))
	var path := DRAGON_SCENE % [int(a["id"]), stage_name]
	if ResourceLoader.exists(path):
		var holder := Node2D.new()
		holder.scale = Vector2(1.9, 1.9)
		holder.position = Vector2(0, 40)   # 발이 스탠드 중앙쯤 오도록 위로
		_stage.add_child(holder)
		var inst = load(path).instantiate()
		holder.add_child(inst)
		var ap = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.play("wait")

## 드래곤 단계 박스 썸네일(480/dragon/dragon_{N}.png의 box_<stage>). 도감에서도 재사용.
func _portrait_sprite(id: int, stage: String, scale := 1.0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_portrait_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	return _atlas_sprite(dir, "dragon_dragon_%d_box_%s" % [id, stage], _portrait_manifests[dir], scale)

func _refresh_list() -> void:
	for ch in _list_box.get_children():
		ch.queue_free()
	var owned: Array = SaveSystem.state["owned_dragons"]
	var active := int(SaveSystem.state.get("active_dragon", 0))
	for i in owned.size():
		_list_box.add_child(_dragon_slot(int(owned[i]["id"]), int(owned[i]["level"]), i, i == active))

func _dragon_slot(id: int, level: int, idx: int, is_active: bool) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(132, 124)
	slot.clip_contents = true
	# 프레임(배경/테두리)
	var frame := _ui_sprite("scene_cave_dragon_frame", 1.85)
	frame.position = Vector2(66, 58)
	if not is_active:
		frame.modulate = Color(0.7, 0.7, 0.75)
	slot.add_child(frame)
	# 단계 썸네일(프레임 위)
	var stage := Data.stage_for_level(level)
	var por := _portrait_sprite(id, stage, 1.25)
	por.position = Vector2(66, 54)
	if not is_active:
		por.modulate = Color(0.85, 0.85, 0.85)
	slot.add_child(por)
	# 레벨
	var lv := Label.new()
	lv.text = "Lv.%d" % level
	lv.size = Vector2(132, 22)
	lv.position = Vector2(0, 100)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_theme_font_size_override("font_size", 18)
	lv.add_theme_color_override("font_color", Color(1, 1, 1))
	slot.add_child(lv)
	# 클릭(투명)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(132, 124)
	b.pressed.connect(func():
		SaveSystem.state["active_dragon"] = idx
		SaveSystem.save_game()
		_refresh())
	slot.add_child(b)
	return slot

func _refresh_stats() -> void:
	var a := _active()
	if a.is_empty():
		_name_label.text = "보유 드래곤 없음"
		_stat_label.text = ""
		_grade_label.text = "-"
		return
	var d: Dictionary = Data.get_dragon(int(a["id"]))
	var lv := int(a["level"])
	var s := Data.compute_stats(int(a["id"]), lv)
	_grade_label.text = "%.1f" % float(a.get("grade", 8.0))
	_name_label.text = "레벨 %d  %s" % [lv, str(d.get("name", "?"))]
	_update_elem_icon(str(d.get("element", "")))
	# TODO: (+보너스)는 grade/문장/각인(§K-5) 구현 후. 현재 base만.
	_stat_label.text = "[color=#7d4a12]생명력[/color] %d (+0)    [color=#7d4a12]공격력[/color] %d (+0)    [color=#7d4a12]방어력[/color] %d (+0)" % [
		s["hp"], s["att"], s["def"]]

func _update_elem_icon(element: String) -> void:
	var name := "battle_element_%s_mark" % element
	var p := "res://assets/converted/battle_ui/%s.tres" % name
	if not ResourceLoader.exists(p):
		_elem_icon.visible = false
		return
	_elem_icon.visible = true
	_elem_icon.texture = load(p)
	var info: Dictionary = _battle_manifest.get(name, {})
	if info.get("rotated", false):
		_elem_icon.rotation = PI / 2.0
		_elem_icon.flip_h = true
	else:
		_elem_icon.rotation = 0.0
		_elem_icon.flip_h = false
	var hh: float = maxf(1.0, float(info.get("h", 70)))
	_elem_icon.scale = Vector2(46.0 / hh, 46.0 / hh)

# ---------- actions ----------
func _on_levelup() -> void:
	var owned: Array = SaveSystem.state["owned_dragons"]
	var i := int(SaveSystem.state.get("active_dragon", 0))
	if i < owned.size():
		owned[i]["level"] = mini(45, int(owned[i]["level"]) + 1)  # TODO: 경험치/아이템 소비(§E,§K)
		SaveSystem.save_game()
		_refresh()

func _open_skin() -> void:
	# 컴팩트 패널(암전X) — 변경을 실시간으로 보면서 선택
	_close_overlay()
	_overlay = _panel(Color(0, 0, 0, 0.72))
	_overlay.position = Vector2(540, 740)
	_overlay.size = Vector2(840, 300)
	add_child(_overlay)
	var v := VBoxContainer.new()
	v.position = Vector2(30, 22)
	v.custom_minimum_size = Vector2(780, 256)
	v.add_theme_constant_override("separation", 18)
	_overlay.add_child(v)
	var head := HBoxContainer.new()
	var t := Label.new(); t.text = "동굴 스킨 변경"; t.add_theme_font_size_override("font_size", 32)
	t.custom_minimum_size = Vector2(560, 0)
	head.add_child(t)
	var c := Button.new(); c.text = "  닫기 ✕  "; c.pressed.connect(_close_overlay)
	head.add_child(c)
	v.add_child(head)
	v.add_child(_skin_row("동굴 배경", "cave_skin", SKIN_COUNT))
	v.add_child(_skin_row("받침대(스탠드)", "stand_skin", STAND_COUNT))

func _skin_row(label: String, key: String, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(280, 0)
	lbl.add_theme_font_size_override("font_size", 30)
	row.add_child(lbl)
	var prev := Button.new(); prev.text = "  ◀  "
	var idx := Label.new(); idx.add_theme_font_size_override("font_size", 30)
	idx.custom_minimum_size = Vector2(140, 0)
	idx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nxt := Button.new(); nxt.text = "  ▶  "
	var upd := func():
		idx.text = "%d / %d" % [int(SaveSystem.state.get(key, 0)) + 1, count]
	upd.call()
	var step := func(d: int):
		SaveSystem.state[key] = (int(SaveSystem.state.get(key, 0)) + d + count) % count
		SaveSystem.save_game()
		upd.call()
		_refresh()
	prev.pressed.connect(func(): step.call(-1))
	nxt.pressed.connect(func(): step.call(1))
	row.add_child(prev); row.add_child(idx); row.add_child(nxt)
	return row

func _close_overlay() -> void:
	if _overlay: _overlay.queue_free(); _overlay = null

func _make_overlay(title: String) -> VBoxContainer:
	_close_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.78)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var box := VBoxContainer.new()
	box.position = Vector2(360, 80)
	box.custom_minimum_size = Vector2(1200, 920)
	_overlay.add_child(box)
	var head := HBoxContainer.new()
	var t := Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 40)
	head.add_child(t)
	var close := Button.new(); close.text = "  닫기 ✕  "
	close.pressed.connect(_close_overlay)
	head.add_child(close)
	box.add_child(head)
	return box

func _open_dex() -> void:
	var box := _make_overlay("도감")
	var owned_ids := {}
	for o in SaveSystem.state["owned_dragons"]:
		owned_ids[int(o["id"])] = true
	var il := ItemList.new()
	il.custom_minimum_size = Vector2(1180, 840)
	il.max_columns = 3
	il.fixed_column_width = 380
	for id in Data.dragon_ids():
		var d: Dictionary = Data.get_dragon(id)
		var mark := "★" if owned_ids.has(id) else "·"
		il.add_item("%s #%d %s [%s/%s]" % [mark, id, str(d.get("name", "?")), str(d.get("element", "")), str(d.get("type", ""))])
	box.add_child(il)

func _open_inventory() -> void:
	var box := _make_overlay("인벤토리")
	var inv: Dictionary = SaveSystem.state.get("inventory", {})
	if inv.is_empty():
		var e := Label.new(); e.text = "보유 아이템 없음"; box.add_child(e); return
	for item_name in inv.keys():
		var row := HBoxContainer.new()
		var l := Label.new(); l.text = "%s  ×%d" % [str(item_name), int(inv[item_name])]
		l.custom_minimum_size = Vector2(400, 0)
		l.add_theme_font_size_override("font_size", 28)
		row.add_child(l)
		var use := Button.new(); use.text = "사용"
		use.pressed.connect(func():
			inv[item_name] = maxi(0, int(inv[item_name]) - 1)  # TODO: 효과 적용(§E)
			if inv[item_name] == 0: inv.erase(item_name)
			SaveSystem.save_game(); _open_inventory())
		row.add_child(use)
		box.add_child(row)

func _open_cards() -> void:
	var box := _make_overlay("카드")
	var l := Label.new(); l.text = "카드 시스템 (추후 구현)"; l.add_theme_font_size_override("font_size", 28)
	box.add_child(l)
