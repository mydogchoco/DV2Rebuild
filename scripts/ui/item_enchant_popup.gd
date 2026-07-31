class_name ItemEnchantPopup
extends Control
## 아이템(장비) 강화 창 — 원작 `cocos2d::ItemEnchantPopup` 이식. render 층(CLAUDE.md §8.1).
##
## 참조 프레임 = `docs/ref/equip/장비강화1.png`(사용자 제공).
## 디컴프 = `docs/ref/orig_code/decomp/ItemEnchantPopup.c`(`initWidget` 리터럴, skip 0건).
##
## 원작 톱니 기계(전부 이 이식으로 갭 해소):
##   `scene/cave/gear` + `gear_shadow`(+2.5,−2.5) + `gear_inside` + `enchant_line`
##   + `gear_shadow_large`(100, −127.5) + `gear_shadow_small`(182.5, −75)
##   + `itembox_add` ×3 @ 중심 기준 **(0,199) / −(157.5,125) / +(159.5,−125)**
##     (아티팩트 합성 기계와 **같은 삼각 배치**다 — `ArtifactMix::drawMachine` 과 리터럴 일치)
##   + `itembox_add_sign`("+") + `pipe1~4`(왼쪽 배관) + `common/coin_big` 비용
##   + `9patch/scroll_box` 재료 격자 + `9patch/text_box` 설명
##   효과음 `effect_enchant` / 성공 `effect_equip_success` / 실패 `effect_equip_failed`.
##
## ## 재료 = **다른 장비**다 (2026-08-01 재채굴)
##
## 종전 주석의 "강화 보조 재료(강화석) 데이터 유실"은 **오진**이었다. 원작 `initData` 를
## 읽어 보면 재료 후보는 별도 아이템이 아니라 **보유 장비 목록**이다:
##   · `AccountManager::getEquip()` 전량에서 `getTag != 대상` 이고 `getDragonTag() == 0`
##     (= 아무 드래곤에게도 안 낀 것)만 추린다
##   · 정렬 = **미귀속(belong == -1) 먼저**, 그 다음 귀속분
## 그리고 확률·비용도 전부 클라 계산이다(`Equipment.enchant_*`, 공식은 그쪽 주석):
##   기준% = 50 − 1.5·W(대상) · 골드 = 500·W(대상) · 가산% = ΣW(재료)×100 / (W(대상)×5)
## 참조 프레임의 "23% / x 9000" 이 W=18 하나로 동시에 맞아 교차검증됐다.
##
## 원작 조작(디컴프 그대로):
##   · 목록 칸 클릭 = **하이라이트**(효과음 `effect_element_match`) + 오른쪽 설명 갱신.
##     이미 재료로 넣은 칸이면 하단 버튼이 `취소`, 아니면 `선택`으로 바뀐다
##     (`onClickItem` → `setSelect`/`setCancel` 가 같은 버튼의 콜백을 갈아 끼운다).
##   · `선택` = 빈 재료 칸 중 첫 칸에 넣는다(3칸 다 차면 토스트) → `calculate()` 재계산.
##   · `강화` = 골드 확인 → 한도 확인 → **재료 1칸 이상** 확인(원작 `onClickEnchant` 는
##     세 칸이 전부 비면 아무 일도 하지 않는다) → 성공/실패 판정.

signal closed

const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN := Vector2(860.0, 520.0)
const DIM_ALPHA := 127.0 / 255.0

## `initWidget` 리터럴 — 기계 중심 기준 오프셋(cocos y-up).
const SHADOW_OFF := Vector2(2.5, -2.5)
const SHADOW_LARGE := Vector2(100.0, -127.5)
const SHADOW_SMALL := Vector2(182.5, -75.0)
const ADD_SLOTS := [Vector2(0.0, 199.0), Vector2(-157.5, -125.0), Vector2(159.5, -125.0)]
## 왼쪽 배관 — (창폭×0.5 기준 오프셋, cocos y).
## (오프셋만 상수로 — 프레임 키는 아래에서 리터럴로 부른다. `asset_index.py` 가
##  `AtlasUI.spr("<폴더>", "<키>")` 쌍으로 사용처를 세기 때문이다.)
const PIPE_AT := [Vector2(-20.0, 80.0), Vector2(-55.0, -10.0), Vector2(-100.0, 5.0),
	Vector2(-45.0, -25.0)]
const BTN := Vector2(150.0, 48.0)

## 목록 격자 — 원작 `initWidget` @00e8f27x 리터럴.
##   안쪽 폭 = scroll_box.w − 10 · 칸 폭 = 안쪽/3 − 5 · 칸 높이 = 폭 × 130/115
const GRID_COLS := 3
const CELL_RATIO := 130.0 / 115.0
const CELL_GAP := 5.0
const LIST_BOX := Vector2(340.0, 200.0)
## 칸 배경 = 원작 `RoundedLayer::create(w, h, 0x66000000, 1, 1)` (에셋이 아니라 그려지는 도형).
const CELL_BG := Color(0, 0, 0, 0x66 / 255.0)

var _uid := 0
var _slot := ""
var _on_done: Callable = Callable()
var _win_root: Control
var _rng := RandomNumberGenerator.new()

## 재료 후보(인벤 키 배열, 개수만큼 펼친 것). 원작 `this+0x290` CCArray 대응.
var _pool: PackedStringArray = []
## 재료 3칸이 가리키는 `_pool` 인덱스(-1=빈 칸). 원작 `this+0x264/0x268/0x26c`.
var _mats: Array[int] = [-1, -1, -1]
## 지금 하이라이트된 목록 칸(-1=없음). 원작 `this+0x260`.
var _sel := -1
## 직전 강화로 **새로 붙은 옵션** 인덱스(-1=없음). 원작 `scene/cave/txt_new` 뱃지 자리.
var _new_opt := -1


static func open(parent: Node, uid: int, slot_id: String, on_done := Callable()) -> ItemEnchantPopup:
	var p := ItemEnchantPopup.new()
	p._uid = uid
	p._slot = slot_id
	p._on_done = on_done
	parent.add_child(p)
	p._build()
	return p


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 65
	_rng.randomize()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.2)
	_reload_pool()
	_rebuild()


## 재료 후보 목록. 원작 `initData` 규칙 그대로 —
## 대상 자신 제외 + 드래곤에게 안 낀 것만 + **미귀속 먼저** 정렬.
## (우리 가방은 장착 중인 장비를 담지 않으므로 `getDragonTag()==0` 조건은 자동 충족된다)
func _reload_pool() -> void:
	var free_first: PackedStringArray = []
	var bound: PackedStringArray = []
	var inv: Dictionary = UserDB.inventory()
	var keys: Array = inv.keys()
	keys.sort()
	for k in keys:
		var key := String(k)
		if Equipment.parse_item_key(key) == "":
			continue
		if not Equipment.catalog(Data.equipment).has(Equipment.parse_item_key(key)):
			continue
		for _n in int(inv[key]):
			if Equipment.item_key_belong(key) > 0:
				bound.append(key)
			else:
				free_first.append(key)
	_pool = free_first + bound
	_mats = [-1, -1, -1]
	_sel = -1


func _rebuild() -> void:
	if is_instance_valid(_win_root):
		_win_root.queue_free()
	var vis := get_viewport_rect().size
	_win_root = Control.new()
	_win_root.size = WIN
	_win_root.position = ((vis - WIN) * 0.5).round()
	add_child(_win_root)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", WIN, WIN_CAP)
	if fr:
		_win_root.add_child(fr)

	var t := _label("아이템 강화", 26, Color.WHITE)      # <CaveEnchantTitle>
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 26.0)
	t.size = Vector2(WIN.x, 40.0)
	_win_root.add_child(t)

	var cb := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct:
		cb.texture_normal = ct
		cb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.3
	cb.position = Vector2(WIN.x - 74.0, 24.0)
	cb.pressed.connect(close)
	_win_root.add_child(cb)

	_build_machine()
	_build_side()


## 톱니 기계 — 원작 initWidget 순서(그림자 → 톱니 → 안쪽 → 라인) 그대로.
func _build_machine() -> void:
	var S := Design.ASSET_SCALE
	var c := Vector2(WIN.x * 0.30, WIN.y * 0.5 + 8.0)
	var root := Node2D.new()
	root.name = "machine"
	root.position = c
	_win_root.add_child(root)

	for spec in [["scene_cave_gear_shadow_large", SHADOW_LARGE], ["scene_cave_gear_shadow_small", SHADOW_SMALL]]:
		var s := AtlasUI.spr("cave_ui", String(spec[0]), S * 0.62)
		if s:
			var o: Vector2 = spec[1]
			s.position = Vector2(o.x, -o.y) * 0.62
			root.add_child(s)
	var gsh := AtlasUI.spr("cave_ui", "scene_cave_gear_shadow", S * 0.62)
	if gsh:
		gsh.position = Vector2(SHADOW_OFF.x, -SHADOW_OFF.y)
		root.add_child(gsh)
	var gear := AtlasUI.spr("cave_ui", "scene_cave_gear", S * 0.62)
	if gear:
		root.add_child(gear)
		# 원작 `makeGearActionNormal` — 톱니가 천천히 돈다.
		gear.create_tween().set_loops().tween_property(gear, "rotation", TAU, 12.0).as_relative()
	var inside := AtlasUI.spr("cave_ui", "scene_cave_gear_inside", S * 0.62)
	if inside:
		root.add_child(inside)
	var line := AtlasUI.spr("cave_ui", "scene_cave_enchant_line", S * 0.62)
	if line:
		root.add_child(line)
		line.create_tween().set_loops().tween_property(line, "rotation", -TAU, 20.0).as_relative()

	# 강화 대상 장비 — 톱니 한가운데.
	var art := _item_sprite(1.1)
	if art:
		art.name = "target"
		root.add_child(art)

	# 보조 재료 3칸(`itembox_add` + `itembox_add_sign`). 채워지면 sign 대신 장비 아이콘.
	for i in ADD_SLOTS.size():
		var off: Vector2 = ADD_SLOTS[i]
		var at := Vector2(off.x, -off.y) * 0.62
		var box := AtlasUI.spr("cave_ui", "scene_cave_itembox_add", S * 0.62)
		if box:
			box.position = at
			root.add_child(box)
		var mi := _mats[i]
		if mi < 0:
			var sign := AtlasUI.spr("cave_ui", "scene_cave_itembox_add_sign", S * 0.62)
			if sign:
				sign.position = at
				root.add_child(sign)
		else:
			var cell := _cell_visual(String(_pool[mi]), 52.0)
			cell.position = c + at - Vector2(26.0, 26.0)
			_win_root.add_child(cell)
		var hit := Button.new()
		hit.flat = true
		hit.size = Vector2(56.0, 56.0)
		hit.position = c + at - hit.size * 0.5
		hit.pressed.connect(_on_slot_click.bind(i))
		_win_root.add_child(hit)

	# 왼쪽 배관(원작 `initPipePos` — 창 중앙 왼쪽으로 이어지는 관 4개).
	var pipes: Array[Sprite2D] = [
		AtlasUI.spr("cave_ui", "scene_cave_pipe1", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe2", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe3", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe4", S * 0.62)]
	for pi in pipes.size():
		var p: Sprite2D = pipes[pi]
		if p == null:
			continue
		var o: Vector2 = PIPE_AT[pi]
		p.position = c + Vector2(o.x, -o.y) * 0.62 + Vector2(-WIN.x * 0.18, 0)
		_win_root.add_child(p)

	# 비용 — `common/coin_big` @ (w/3+15, 57.5)c.
	var cost := _cost()
	var coin := AtlasUI.spr("common_ui", "common_coin_big", S * 0.8)
	if coin:
		coin.position = Vector2(WIN.x / 3.0 + 15.0, WIN.y - 57.5)
		_win_root.add_child(coin)
	var short := UserDB.gold() < cost
	var cl := _label("x %s" % AtlasUI.comma(cost), 20,
		Color(1, 0.45, 0.38) if short else Color(1, 0.95, 0.72))
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.position = Vector2(WIN.x / 3.0 + 45.0, WIN.y - 78.0)
	cl.size = Vector2(240.0, 40.0)
	_win_root.add_child(cl)

	# 성공 확률(참조의 좌하단 "성공 확률 23%"). 원작은 라벨 두 개(문구 + 수치)다.
	var pl := _label("성공 확률 %d%%" % _success_pct(), 19, Color(0.55, 1.0, 0.62))
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.position = Vector2(40.0, WIN.y - 78.0)
	pl.size = Vector2(220.0, 40.0)
	_win_root.add_child(pl)


## 오른쪽 — `9patch/scroll_box` 재료 격자 + `9patch/text_box` 설명 + 강화/선택 버튼.
func _build_side() -> void:
	var bx := WIN.x * 0.56
	var bw := WIN.x - bx - 44.0
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(bw, LIST_BOX.y),
		Rect2(65, 65, 6, 6))
	if box:
		box.position = Vector2(bx, 84.0)
		_win_root.add_child(box)
	_build_grid(Vector2(bx, 84.0), Vector2(bw, LIST_BOX.y))

	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(bw, 165.0),
		Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(bx, 292.0)
		_win_root.add_child(tb)
	# 원작 텍스트 박스는 라벨 8줄이 정해진 자리에 놓인다 — 넘치면 잘리게 클립한다.
	var clip := Control.new()
	clip.position = Vector2(bx + 16.0, 302.0)
	clip.size = Vector2(bw - 32.0, 145.0)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_root.add_child(clip)
	var col := VBoxContainer.new()
	col.size = clip.size
	col.add_theme_constant_override("separation", 3)
	clip.add_child(col)
	# 설명 = 하이라이트한 목록 칸이 있으면 그 장비, 없으면 강화 대상.
	var desc_key := String(_pool[_sel]) if _sel >= 0 and _sel < _pool.size() else ""
	if desc_key == "":
		var sd := _slot_data()
		col.add_child(_label(_item_name(), 19, Color(0.72, 0.20, 0.10)))
		col.add_child(_label("강화 %d / %d" % [int(sd.get("enhance", 0)), _limit()], 16,
			Color(0.30, 0.17, 0.04)))
		var oi := 0
		for o in (sd.get("options", []) as Array):
			var ol := _opt_label(o as Dictionary)
			col.add_child(ol)
			# 직전 강화로 붙은 옵션에는 원작 `scene/cave/txt_new` 뱃지를 단다
			# (원작 `responseResult` 가 <CaveItemEquipSucces2> 와 함께 띄운다).
			if oi == _new_opt:
				var nb := AtlasUI.spr("cave_ui", "scene_cave_txt_new", Design.ASSET_SCALE * 0.7)
				if nb:
					nb.position = Vector2(bw - 60.0, 10.0)
					ol.add_child(nb)
			oi += 1
	else:
		var m := Equipment.item_key_meta(desc_key)
		var it: Dictionary = Equipment.catalog(Data.equipment).get(
			Equipment.parse_item_key(desc_key), {})
		# 이름 글자 색 = 원작 `Equip::getRarityColor` 표(실루엣 표와 다르다).
		col.add_child(_label(_key_name(desc_key), 19,
			Icons.rarity_text_color(int(m.get("rarity", 0)))))
		col.add_child(_label("무게 %d  ·  확률 가산 +%d%%" % [
			Equipment.enchant_weight_of_key(desc_key, Data.equipment),
			_bonus_of(desc_key)], 16, Color(0.30, 0.17, 0.04)))
		for o in (m.get("options", []) as Array):
			col.add_child(_opt_label(o as Dictionary))
		if String(it.get("bonus", "")) != "":
			var bl := _label(String(it["bonus"]), 13, Color(0.36, 0.28, 0.14))
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size = Vector2(bw - 32.0, 0)
			col.add_child(bl)

	# 오른쪽 아래 두 버튼. 원작은 두 번째 버튼의 **콜백과 라벨이 바뀐다**
	# (`setSelect`/`setCancel`) — 넣을 수 있으면 `선택`, 이미 넣었으면 `취소`.
	var pick_txt := "선택"
	if _sel >= 0 and _mats.has(_sel):
		pick_txt = "취소"
	_button("강화", Vector2(bx + bw * 0.5 - BTN.x - 8.0, WIN.y - 76.0), _on_enchant)
	_button(pick_txt, Vector2(bx + bw * 0.5 + 8.0, WIN.y - 76.0), _on_pick)


## 재료 후보 격자 — 원작 리터럴대로 3열, 칸 높이 = 폭 × 130/115.
func _build_grid(at: Vector2, box: Vector2) -> void:
	var inner := box.x - 10.0
	var cw := inner / float(GRID_COLS) - CELL_GAP
	var ch := cw * CELL_RATIO
	var sc := ScrollContainer.new()
	sc.position = at + Vector2(5.0, 7.5)
	sc.size = Vector2(inner, box.y - 15.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_win_root.add_child(sc)
	var page := Control.new()
	var rows := int(ceil(float(_pool.size()) / float(GRID_COLS)))
	page.custom_minimum_size = Vector2(inner, (ch + CELL_GAP) * float(rows) + 2.5)
	sc.add_child(page)

	if _pool.is_empty():
		var none := _label("재료로 쓸 장비가 없습니다", 15, Color(0.45, 0.33, 0.20))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.position = Vector2(0, 16.0)
		none.size = Vector2(inner, 30.0)
		page.add_child(none)
		return

	for i in _pool.size():
		var cell := Control.new()
		cell.size = Vector2(cw, ch)
		cell.position = Vector2(inner * float(i % GRID_COLS) / float(GRID_COLS) + CELL_GAP * 0.5,
			(ch + CELL_GAP) * float(i / GRID_COLS))
		page.add_child(cell)
		var bg := ColorRect.new()
		bg.color = CELL_BG
		bg.size = cell.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bg)
		# 원작은 아이콘/실루엣을 0.7 배로 그린다(setScale 0x3f333333).
		var vis := _cell_visual(String(_pool[i]), cw * 0.7)
		vis.position = (cell.size - vis.size) * 0.5
		cell.add_child(vis)
		# 재료로 넣은 칸은 한 겹 더 덮는다(원작: 같은 크기 RoundedLayer 0x66000000 을 보이게).
		if _mats.has(i):
			var used := ColorRect.new()
			used.color = CELL_BG
			used.size = cell.size
			used.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(used)
		if i == _sel:
			var mark := ReferenceRect.new()
			mark.border_color = Color(1.0, 0.86, 0.35)
			mark.border_width = 3.0
			mark.editor_only = false
			mark.size = cell.size
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(mark)
		var b := Button.new()
		b.flat = true
		b.size = cell.size
		b.pressed.connect(_on_cell_click.bind(i))
		cell.add_child(b)


## 장비 한 칸의 그림 — 희귀도 실루엣 + 아이콘 + 귀속 뱃지 + `+N`(원작 셀 구성 그대로).
func _cell_visual(key: String, box: float) -> Control:
	var m := Equipment.item_key_meta(key)
	var item: Dictionary = Equipment.catalog(Data.equipment).get(
		Equipment.parse_item_key(key), {})
	var holder: Control = Icons.equip_rect(item, box, int(m.get("rarity", 0)),
		int(m.get("belong", 0)), _uid)
	if holder == null:
		holder = Control.new()
		holder.custom_minimum_size = Vector2(box, box)
		holder.size = Vector2(box, box)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var up := int(m.get("enhance", 0))
	if up > 0:
		# 원작: 앵커 (1,0) · 위치 (칸폭, 0) + (−10, 12.5) → 오른쪽 아래.
		var l := _label("+%d" % up, 14, Color(1, 0.95, 0.72))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.size = Vector2(box, box)
		l.position = Vector2(-2.0, 0.0)
		holder.add_child(l)
	return holder


# ------------------------------------------------------------ 동작

## 목록 칸 클릭 = 하이라이트 + 설명 갱신(원작 `onClickItem`).
func _on_cell_click(i: int) -> void:
	Bgm.sfx("effect_element_match")
	_sel = i
	_rebuild()


## `선택`/`취소` 버튼(원작 `onClickSelect` / `onClickCancel`).
func _on_pick() -> void:
	if _sel < 0:
		_notice("재료로 쓸 장비를 먼저 고르세요")     # 원작도 여기서 토스트를 낸다
		return
	var at := _mats.find(_sel)
	if at >= 0:
		_mats[at] = -1
		_rebuild()
		return
	var free := _mats.find(-1)
	if free < 0:
		_notice("재료는 3개까지 넣을 수 있습니다")
		return
	_mats[free] = _sel
	Bgm.sfx("effect_element_match")
	_rebuild()


## 재료 칸을 직접 눌러 빼기(원작은 목록 쪽 `취소` 버튼만 있지만 칸 클릭이 더 직관적이다).
## ASSUMPTION: 원작에 없는 조작 — 결과는 `onClickCancel` 과 같다.
func _on_slot_click(i: int) -> void:
	if _mats[i] < 0:
		_notice("오른쪽 목록에서 재료로 쓸 장비를 고른 뒤 `선택`을 누르세요")
		return
	_mats[i] = -1
	_rebuild()


func _on_enchant() -> void:
	var sd := _slot_data()
	var why := Equipment.enchant_blocked(sd, Data.equipment)
	if why != "":
		# 원작 문구 그대로(<CaveItemEquipMsg11/7/8>).
		_notice({
			"no_equip": "착용 중인 장비가 없습니다.",
			"grade_max": "가장 낮은 등급의 아이템은 강화가 불가능합니다.",
			"option_max": "더 이상 강화할 수 없습니다.",
		}.get(why, why))
		return
	# 원작 `onClickEnchant`: 세 칸이 전부 비면 아무 일도 일어나지 않는다.
	if bool(Equipment.enchant_cfg(Data.equipment).get("require_material", true)) \
			and _filled().is_empty():
		_notice("보조 재료를 1개 이상 넣어야 합니다")
		return
	var cost := _cost()
	if not UserDB.spend("gold", cost):
		_notice("골드가 부족합니다")
		return

	# 재료 소모 — 넣은 순서와 무관하게 인벤에서 같은 키를 하나씩 뺀다.
	for k in _filled():
		UserDB.add_item(k, -1)

	Bgm.sfx("effect_enchant")
	var was := _item_name()
	var before := (sd.get("options", []) as Array).size()
	var after := before
	var ok := _rng.randi() % 100 < _success_pct()
	if ok:
		var next: Dictionary = Equipment.enhance(
			UserDB.get_dragon(_uid).get("equip", {}), _slot, _rng, Data.equipment)
		if not next.is_empty():
			UserDB.set_dragon_field(_uid, "equip", next)
			after = (_slot_data().get("options", []) as Array).size()
	Bgm.sfx("effect_equip_success" if ok else "effect_equip_failed")
	# NEW 뱃지는 **다시 그리기 전에** 정해야 설명 패널에 붙는다.
	_new_opt = (after - 1) if (ok and after > before) else -1
	if _on_done.is_valid():
		_on_done.call()
	_reload_pool()
	_rebuild()
	# 원작 문구 — <CaveItemEquipSucces1/2>(성공, 추가 옵션이 붙으면 2번) / <CaveItemEquipFail>.
	if not ok:
		_notice("아쉽게 실패했네요. 다음을 기약하죠.")
	elif after > before:
		_notice("축하드려요! 강화에 성공했습니다!
%s -> %s
새로운 옵션 %s" % [
			was, _item_name(), _opt_text(_slot_data(), after - 1)])
	else:
		_notice("축하드려요! 강화에 성공했습니다!
%s -> %s" % [was, _item_name()])


## 채워진 재료 칸의 인벤 키들.
func _filled() -> PackedStringArray:
	var out: PackedStringArray = []
	for i in _mats:
		if i >= 0 and i < _pool.size():
			out.append(String(_pool[i]))
	return out


func _slot_data() -> Dictionary:
	for s in (UserDB.get_dragon(_uid).get("equip", {}).get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == _slot:
			return s
	return {}


func _weight() -> int:
	return Equipment.enchant_weight_of_slot(_slot_data(), Data.equipment)


func _limit() -> int:
	var per := int(Data.equipment.get("option", {}).get("enhance_per_option", 5))
	return (_slot_data().get("options", []) as Array).size() * per


## 강화 비용 — 원작 `initWidget`: W(대상) × 500.
func _cost() -> int:
	return Equipment.enchant_gold(_weight(), Data.equipment)


## 표시 확률 — 기준(대상 무게) + 재료 가산. 원작 `calculate` 그대로.
func _success_pct() -> int:
	var ws: Array = []
	for k in _filled():
		ws.append(Equipment.enchant_weight_of_key(k, Data.equipment))
	return Equipment.enchant_pct(_weight(), ws, Data.equipment)


## 그 장비 하나를 재료로 넣었을 때의 가산 확률(설명 패널용).
func _bonus_of(key: String) -> int:
	var w := _weight()
	if w <= 0:
		return 0
	return int(Equipment.enchant_weight_of_key(key, Data.equipment) * 100
		/ (w * int(Equipment.enchant_cfg(Data.equipment).get("material_denom", 5))))


func _item_name() -> String:
	var sd := _slot_data()
	var item: Dictionary = Equipment.catalog(Data.equipment).get(String(sd.get("key", "")), {})
	var nm := String(item.get("name", "장비"))
	var e := int(sd.get("enhance", 0))
	return "%s +%d" % [nm, e] if e > 0 else nm


func _key_name(key: String) -> String:
	var item: Dictionary = Equipment.catalog(Data.equipment).get(
		Equipment.parse_item_key(key), {})
	var nm := String(item.get("name", "장비"))
	var e := int(Equipment.item_key_meta(key).get("enhance", 0))
	return "%s +%d" % [nm, e] if e > 0 else nm


## 옵션 i번의 "이름 +값" 문자열(원작 <CaveItemEquipSucces4> 의 %s 자리).
func _opt_text(sd: Dictionary, i: int) -> String:
	var opts: Array = sd.get("options", [])
	if i < 0 or i >= opts.size():
		return ""
	var od := opts[i] as Dictionary
	return "%s +%s" % [String(EquipOptionLayer.STAT_KR.get(
		String(od.get("stat", "")), String(od.get("stat", "")))), str(od.get("value", 0))]


func _opt_label(od: Dictionary) -> Label:
	return _label("%s +%s" % [String(EquipOptionLayer.STAT_KR.get(
		String(od.get("stat", "")), String(od.get("stat", "")))),
		str(od.get("value", 0))], 16, Color(0.30, 0.17, 0.04))


func _item_sprite(mult: float) -> Sprite2D:
	var sd := _slot_data()
	var item: Dictionary = Equipment.catalog(Data.equipment).get(String(sd.get("key", "")), {})
	var t := Icons.equip_texture(item)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = AtlasUI.pma()
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * mult
	return s


func close() -> void:
	closed.emit()
	queue_free()


# ---------- 공용 ----------

func _button(text: String, at: Vector2, cb: Callable) -> void:
	var root := Control.new()
	root.size = BTN
	root.position = at
	_win_root.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_btn", BTN, Rect2(20, 20, 4, 4))
	if np:
		root.add_child(np)
	var l := _label(text, 20, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = BTN
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = BTN
	b.pressed.connect(cb)
	root.add_child(b)


func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if col == Color.WHITE or col.v > 0.8:
		l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
		l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _notice(msg: String) -> void:
	PopupType.open(self, "아이템 강화", msg, Callable(), "확인", "")
