class_name PartySelect
extends RefCounted
## 출전 편성 — 원작 `AdventureScene::setAddDragonPopupLayer`(@00c5e148) + `AddDragonCell`
## (initWithSize @00d1286c · updateDragonBtn @00d14a8c, 2026-08-01 `--max 20000` 재디컴파일).
##
## 🟠 2026-08-01 전면 재작성(사용자 지적 — 종전 세로 리스트 창은 자작 형태였다).
## 레퍼런스 `docs/ref/adventure/2_파티편성.png`·`파티편성_용병.png` = **전체 화면 + 큰 카드
## 가로 스크롤**이고, 디컴파일이 그 구성을 그대로 말한다:
##   · 팝업이 아니라 화면 전체 레이어. 카드 목록 = CCTableView @ (10, −15)
##   · 카드(AddDragonCell): `common/bg/info_bg(2/3/4)` 패널(→미보유, 9patch 대체)
##     + `scene/adventure/dragon_bg`+`dragon_frame`(초상 상자, **보유**) + 스파인 드래곤
##     + `common/shadow` + 이름 Thonburi 22 + LV(subtitle BMFont 0.75)
##     + 스탯 2열(라벨 x=77 우정렬, y = h−225/−252/−279 — subtitle 라벨 + font_common 값)
##     + 스킬 슬롯(`common/skill_*_bg` + 스킬 아이콘 + `common/lock`) — updateDragonBtn
##   · 상단 `전투 시작` 버튼(9patch bar1 — 얇아서 9patch/box1 로 대체) + 우상단 X
##   · 하단 전폭 텍스트박스 `<AdventureAddDragonHardDungeon>`
##     "추가로 전투에 참가할 드래곤을 최대 3마리 선택할 수 있습니다."
##
## ⚫ CUT(§2-1 온라인): 좌상단 `S용병 💎x1`(AdventureSpecialMercenary) · `용병 🪙x1200` —
##   친구/서버 용병 소환이라 만들지 않는다.
## ⚫ 전투력 숫자(레퍼런스 좌상단 주황 "8.3", `font_rating` + `Dragon::getRating`):
##   **값이 서버 소유다** — 클라에는 `setRating(float)` 세터뿐, 계산식이 없다(레코드로 내려옴).
##   수치를 지어내지 않는다(HARD RULE 6) → 표기 생략. 공식이 확보되면 `_card` 의 rating 자리부터.
##
## 미보유 자산 대체(CLAUDE.md §10 `common/bg/` 행): 카드 패널 `info_bg*` → `9patch/list_bg2`.
##
## 사용:
##   `PartySelect.open_run(host, current_uids, func(picked: Array): ...)`  — 던전 편성(확정 필수)
##   `PartySelect.open(host)` — 편성만(둥지 등). 닫기 전용.

const LIST_BG := "res://assets/converted/ninepatch_ui/9patch_list_bg2.tres"
const BOX1 := "res://assets/converted/ninepatch_ui/9patch_box1.tres"
const DIALOG := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const CLOSE_BTN := "res://assets/converted/common_ui/common_close_btn.tres"
const FONT_SUB := "res://assets/converted/font_ui/font_subtitle.fnt"

const MAX_PARTY := 3
const CARD_W := 250.0
const CARD_H := 400.0

## 던전 편성 — 확정해야 닫힌다(원작도 출전 인원을 정해야 진행된다).
## show_msg=false 면 하단 안내 박스를 그리지 않는다 — 탐험처럼 호스트가 자기
## 텍스트박스(BattleTextBox)를 이미 갖고 있으면 거기로 내야 겹치지 않는다(2026-08-01 실측).
static func open_run(host: Node, current: Array, on_confirm: Callable, show_msg := true) -> void:
	_build(host, current, on_confirm, true, show_msg)

## 편성만(확정 없음).
static func open(host: Node, _unused := Callable(), _unused2 := Callable()) -> void:
	_build(host, UserDB.party(), Callable(), false, true)


static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _tex(dir: String, key: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	return load(p) if ResourceLoader.exists(p) else null

static func _spr(dir: String, key: String, scale: float, pma: CanvasItemMaterial) -> Sprite2D:
	var t := _tex(dir, key)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = pma
	s.scale = Vector2(scale, scale)
	return s

## subtitle BMFont 라벨(비트맵 — fixed_size_scale_mode 규약, CLAUDE.md §10).
static func _bmf(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	if ResourceLoader.exists(FONT_SUB):
		l.add_theme_font_override("font", load(FONT_SUB))
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _ttf(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 드래곤 스파인 노드 — 원작이 초상이 아니라 `CCSkeletonAnimation`(getImagePathSpineJson)을 쓴다.
## ⚠️ 빌드된 스파인 씬은 단계·종마다 내부 원점 오프셋이 달라(2026-08-01 실측 — baby 씬이
##   ~+78px 아래로 떴다) **스프라이트 경계를 실측**해 상자 안에 맞춘다.
static func _spine_node(id: int, stage: String, box_h: float) -> Node2D:
	for st in [stage, "adult", "child", "baby"]:
		var p := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, st]
		if ResourceLoader.exists(p):
			var holder := Node2D.new()
			var inst = (load(p) as PackedScene).instantiate()
			holder.add_child(inst)
			var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
			if ap:
				for cand in ["wait", "animation", "idle"]:
					if ap.has_animation(cand):
						ap.get_animation(cand).loop_mode = Animation.LOOP_LINEAR
						ap.play(cand)
						break
			# 경계 실측 → 배율(상자 높이에 맞춤) + 바닥 중앙 정렬 보정.
			var r := _bounds(inst, Transform2D.IDENTITY)
			if r.size.y > 1.0:
				var k := minf(box_h / r.size.y, (box_h * 1.45) / maxf(r.size.x, 1.0))
				holder.scale = Vector2.ONE * k
				# holder 원점 = 상자 바닥 중앙이 되도록 내부를 밀어 둔다.
				inst.position -= Vector2(r.get_center().x, r.position.y + r.size.y)
			else:
				holder.scale = Vector2.ONE * (box_h / 260.0)
			return holder
	return null

## 스파인 씬(Sprite2D 트리)의 로컬 경계 상자.
static func _bounds(n: Node, xf: Transform2D) -> Rect2:
	var out := Rect2()
	var has := false
	var my := xf
	if n is Node2D:
		my = xf * (n as Node2D).transform
	if n is Sprite2D:
		var s := n as Sprite2D
		if s.texture != null and s.visible:
			var sz: Vector2 = s.texture.get_size()
			var org: Vector2 = (-sz * 0.5 + s.offset) if s.centered else s.offset
			for cx in [0.0, sz.x]:
				for cy in [0.0, sz.y]:
					var pt: Vector2 = my * (org + Vector2(cx, cy))
					if has:
						out = out.expand(pt)
					else:
						out = Rect2(pt, Vector2.ZERO)
						has = true
	for c in n.get_children():
		var r := _bounds(c, my)
		if r.size != Vector2.ZERO or r.position != Vector2.ZERO:
			out = out.merge(r) if has else r
			has = true
	return out

static func _stage_of(d: Dictionary) -> String:
	var lv := int(d.get("level", 1))
	return "adult" if lv >= 25 else ("child" if lv >= 10 else "baby")


static func _build(host: Node, current: Array, on_confirm: Callable, require_confirm: bool,
		show_msg := true) -> void:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var pma := CanvasItemMaterial.new()
	pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	# ⚠️ layer 30 유지 — test_party_flow 가 "layer 30 오버레이 존재"로 편성창을 검출한다.
	var overlay := CanvasLayer.new()
	overlay.layer = 30
	host.add_child(overlay)

	# 원작 CCLayerColor — 배경이 비치는 옅은 막(레퍼런스: 던전 배경이 그대로 보인다).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.size = vis
	overlay.add_child(dim)

	var picked: Array = []
	for u in current:
		if not UserDB.get_dragon(int(u)).is_empty() and picked.size() < MAX_PARTY:
			picked.append(int(u))

	# ── 카드 가로 스크롤(원작 CCTableView @ (10, −15)) ─────────────────────────
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(10.0, vis.y * 0.155)
	scroll.size = Vector2(vis.x - 20.0, CARD_H + 20.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	overlay.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 14)
	scroll.add_child(strip)

	var repaint_all := func():
		for c in strip.get_children():
			if c.has_meta("paint"):
				(c.get_meta("paint") as Callable).call()

	for d in UserDB.dragons():
		strip.add_child(_card(d, picked, pma, repaint_all))
	repaint_all.call()

	var dismiss := func(commit: bool):
		if commit:
			UserDB.clear_party()
			for u in picked:
				UserDB.toggle_party(int(u))
		if is_instance_valid(overlay):
			overlay.queue_free()
		if commit and on_confirm.is_valid():
			on_confirm.call(picked.duplicate())

	# ── 상단: 전투 시작(레퍼런스 우상단 어두운 판) + X ────────────────────────
	# ⚫ 좌상단 S용병/용병 버튼은 온라인 용병 소환이라 CUT(§2-1) — 헤더 주석 참조.
	var go := Button.new()
	go.flat = true
	var go_np := NinePatchRect.new()
	if ResourceLoader.exists(BOX1):
		go_np.texture = load(BOX1)
	go_np.patch_margin_left = 12; go_np.patch_margin_right = 12
	go_np.patch_margin_top = 12; go_np.patch_margin_bottom = 12
	go_np.size = Vector2(176.0, 56.0)
	go_np.position = Vector2(vis.x * 0.72, vis.y * 0.075)
	# 레퍼런스의 전투 시작 = **어두운 반투명 판** + 흰 글씨.
	go_np.modulate = Color(0.32, 0.28, 0.25, 0.95)
	overlay.add_child(go_np)
	var gl := _ttf("전투 시작", 28, Color.WHITE)
	gl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	gl.add_theme_constant_override("outline_size", 5)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gl.size = go_np.size
	go_np.add_child(gl)
	go.size = go_np.size
	go.pressed.connect(func(): dismiss.call(true))
	go_np.add_child(go)

	# 우상단 X — 원작 `newCommon/pss_btn_x`(미보유) → 보유 `common/close_btn`(붉은 X).
	# 던전 편성(run)에서도 원작처럼 X 를 둔다 — 현재 선택 그대로 시작(리더 혼자 포함).
	var close := TextureButton.new()
	if ResourceLoader.exists(CLOSE_BTN):
		close.texture_normal = load(CLOSE_BTN)
	close.position = Vector2(vis.x - 64.0, 12.0)
	close.pressed.connect(func(): dismiss.call(require_confirm))
	overlay.add_child(close)

	# ── 하단 전폭 텍스트박스(원작 BattleTextBox + <AdventureAddDragonHardDungeon>) ──
	if not show_msg:
		return
	var box := NinePatchRect.new()
	if ResourceLoader.exists(DIALOG):
		box.texture = load(DIALOG)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 20.0, 84.0)
	box.position = Vector2(10.0, vis.y - 94.0)
	overlay.add_child(box)
	var msg := _ttf("추가로 전투에 참가할 드래곤을 최대 %d마리 선택할 수 있습니다." % MAX_PARTY,
		26, Color(0.15, 0.1, 0.03))
	msg.position = Vector2(14.0, 0.0)
	msg.size = Vector2(box.size.x - 28.0, box.size.y)
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(msg)


## 카드 1장(원작 AddDragonCell). 좌표는 셀 로컬(카드 좌상단 원점).
static func _card(d: Dictionary, picked: Array, pma: CanvasItemMaterial,
		repaint_all: Callable) -> Control:
	var S := Design.ASSET_SCALE
	var uid := int(d["uid"])
	var id := int(d["id"])
	var ddef: Dictionary = Data.get_dragon(id)
	var lv := int(d.get("level", 1))
	var down := UserDB.is_down(uid)

	var cell := Button.new()
	cell.flat = true
	cell.custom_minimum_size = Vector2(CARD_W, CARD_H)
	# 패널 — 원작 `common/bg/info_bg*`(미보유) → 9patch/list_bg2.
	var bg := NinePatchRect.new()
	if ResourceLoader.exists(LIST_BG):
		bg.texture = load(LIST_BG)
	bg.patch_margin_left = 14; bg.patch_margin_right = 14
	bg.patch_margin_top = 14; bg.patch_margin_bottom = 14
	bg.size = Vector2(CARD_W, CARD_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(bg)

	# 이름 — 원작 Thonburi 22 @ (w*0.5, h−40) 중앙. (전투력 숫자는 서버 유실 → 생략, 헤더 참조)
	var nm := _ttf(Icons.name_of(d), 21, Color(0.2, 0.14, 0.05))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(10.0, 10.0)
	nm.size = Vector2(CARD_W - 20.0, 26.0)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.add_child(nm)

	# 초상 상자 — 원작 dragon_bg(179×117) + dragon_frame @ (w*0.5, h−130).
	var boxc := Vector2(CARD_W * 0.5, 130.0)
	var dbg := _spr("adventure_ui", "scene_adventure_dragon_bg", S, pma)
	if dbg: dbg.position = boxc; cell.add_child(dbg)
	var box_h := 117.0 * S
	# LV — 원작 subtitle BMFont 0.75, 상자 위 중앙.
	var lvl := _bmf("LV %d" % lv, 17)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.position = Vector2(10.0, boxc.y - box_h * 0.5 + 4.0)
	lvl.size = Vector2(CARD_W - 20.0, 20.0)
	cell.add_child(lvl)
	# 속성 뱃지 — 원작 item/item_small/ele_*(updateDragonBtn switch), 상자 우상단 안쪽.
	var elk := Icons.element_small_frame(String(ddef.get("element", "")))
	if elk != "":
		var eb := _spr("item_small_ui", elk, 0.62 * S, pma)
		if eb:
			eb.position = Vector2(CARD_W - 44.0, boxc.y - box_h * 0.5 + 12.0)
			cell.add_child(eb)
	# 그림자 + 스파인(원작 getImagePathSpineJson — 초상이 아니라 스파인이다).
	# `_spine_node` 는 원점 = 그림 **바닥 중앙**으로 정렬돼 돌아온다 → 상자 바닥에 세운다.
	var feet := boxc + Vector2(0.0, box_h * 0.5 - 10.0)
	var sh := _spr("common_ui", "common_shadow", S, pma)
	if sh:
		sh.position = feet + Vector2(0.0, -4.0)
		cell.add_child(sh)
	var sp := _spine_node(id, _stage_of(d), box_h * 0.86)
	if sp:
		sp.position = feet
		cell.add_child(sp)
	var dfr := _spr("adventure_ui", "scene_adventure_dragon_frame", S, pma)
	if dfr: dfr.position = boxc; cell.add_child(dfr)

	# ── 스탯 2열(원작 y = h−225/−252/−279 · 라벨 subtitle + 값 font_common) ──
	# 값 = 기본(성장 롤 합) + 초록 보너스(젬·장비·장신구 합산분). % 3종은 보너스만 표기
	# (레퍼런스 "치명타 :0%" — 기본 cri/evd/blk 는 판정 내부값이라 원작도 보너스만 냈다).
	var base := Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []),
		(d.get("stat_bonus", {}) as Dictionary).get("base", {}))
	var fin := PartyStats.resolve(d, ddef, {}, false, "")
	var rows := [
		["생명력", Color(0.32, 0.30, 0.78), "hp"],
		["공격력", Color(0.80, 0.22, 0.16), "att"],
		["방어력", Color(0.16, 0.38, 0.78), "def"]]
	var prows := [
		["치명타", "cri"], ["방어율", "blk"], ["회피율", "evd"]]
	for i in 3:
		var y := 222.0 + 27.0 * float(i)
		var lab := _ttf(String(rows[i][0]) + " :", 16, rows[i][1])
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.position = Vector2(0.0, y)
		lab.size = Vector2(72.0, 20.0)
		cell.add_child(lab)
		var k := String(rows[i][2])
		var b := int(base.get(k, 0))
		var extra := int(fin.get(k, b)) - b
		var val := _ttf("%d" % b, 16, Color(0.16, 0.16, 0.35))
		val.position = Vector2(76.0, y)
		val.size = Vector2(70.0, 20.0)
		cell.add_child(val)
		if extra != 0:
			var ex := _ttf("%+d" % extra, 15, Color(0.18, 0.62, 0.20))
			# 기본값 폭만큼 뒤에 — 원작처럼 "884+256" 붙여쓰기.
			ex.position = Vector2(76.0 + 9.6 * float(("%d" % b).length()), y)
			ex.size = Vector2(60.0, 20.0)
			cell.add_child(ex)
		# 우열(% 3종 — 보너스만).
		var pk := String(prows[i][1])
		var plab := _ttf(String(prows[i][0]) + " :", 16, Color(0.16, 0.38, 0.78))
		plab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		plab.position = Vector2(CARD_W * 0.55, y)
		plab.size = Vector2(58.0, 20.0)
		cell.add_child(plab)
		var pextra := int(fin.get(pk, 0)) - int(base.get(pk, 0))
		var pval := _ttf("%d%%" % pextra, 16, Color(0.16, 0.16, 0.35))
		pval.position = Vector2(CARD_W * 0.55 + 62.0, y)
		pval.size = Vector2(50.0, 20.0)
		cell.add_child(pval)

	# ── 스킬 슬롯(원작 updateDragonBtn — skill_*_bg + 아이콘 + lock) ──────────
	var slot_y := CARD_H - 62.0
	for si in Loadout.SKILL_SLOTS:
		var sx := CARD_W * 0.5 + (float(si) - float(Loadout.SKILL_SLOTS - 1) * 0.5) * 92.0
		var sbg := _spr("common_ui", "common_skill_circle_bg", 0.62 * S, pma)
		if sbg:
			sbg.position = Vector2(sx, slot_y)
			cell.add_child(sbg)
		if not Loadout.slot_unlocked(si, lv):
			var lk := _spr("common_ui", "common_lock", 0.7 * S, pma)
			if lk:
				lk.position = Vector2(sx, slot_y)
				cell.add_child(lk)
			continue
		var e := Loadout.equipped_entry(d, si)
		if e.is_empty():
			continue
		var sid := int(e.get("id", 0))
		var stex := _tex("skill", "skill_%d" % sid)
		if stex:
			var ic := Sprite2D.new()
			ic.texture = stex
			ic.material = pma
			ic.scale = Vector2.ONE * (0.5 * S)   # 원작 스킬 아이콘 scale 0.6 계열
			ic.position = Vector2(sx, slot_y)
			cell.add_child(ic)
		var slv := _ttf("%d" % int(e.get("level", 1)), 13, Color.WHITE)
		slv.add_theme_color_override("font_outline_color", Color(0.1, 0.35, 0.1, 0.95))
		slv.add_theme_constant_override("outline_size", 4)
		slv.position = Vector2(sx - 34.0, slot_y - 34.0)
		slv.size = Vector2(24.0, 18.0)
		cell.add_child(slv)

	# 출전 순번 뱃지(우상단) + 선택/비활성 칠.
	var mark := _ttf("", 20, Color(1.0, 0.62, 0.10))
	mark.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.0, 0.9))
	mark.add_theme_constant_override("outline_size", 5)
	mark.position = Vector2(10.0, 34.0)
	mark.size = Vector2(CARD_W - 20.0, 24.0)
	cell.add_child(mark)

	var paint := func():
		if down:
			mark.text = "행동불능 — %s" % Incapacitation.remain_text(
				UserDB.cure_time(uid), int(Time.get_unix_time_from_system()))
			cell.modulate = Color(0.55, 0.47, 0.47)
			return
		var at := picked.find(uid)
		mark.text = ("출전 %d" % (at + 1)) if at >= 0 else ""
		# 레퍼런스 파티편성_용병.png — 선택 카드는 테두리가 밝고, 비선택은 흰 판 그대로.
		cell.modulate = Color(1, 1, 1)
		bg.modulate = Color(1.0, 0.95, 0.72) if at >= 0 else Color(1, 1, 1)
	cell.set_meta("paint", paint)

	if down:
		# 행동불능 드래곤은 고를 수 없다(원작 AddDragonCell 도 `Dragon::isStun` 검사).
		picked.erase(uid)
		cell.disabled = true
		return cell

	cell.pressed.connect(func():
		var at := picked.find(uid)
		if at >= 0:
			picked.remove_at(at)
		elif picked.size() < MAX_PARTY:
			picked.append(uid)
		repaint_all.call())
	return cell
