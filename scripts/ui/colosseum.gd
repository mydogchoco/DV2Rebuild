extends Control
## 콜로세움 로비 — 원작 `ColosseumScene` 이식. render 층(§8).
##
## 🟦 사용자 확정 2026-08-04 — 상대를 봇으로만 채운 **솔로** 콜로세움.
## 판정·표·봇 생성은 전부 logic(`Colosseum` + `data/colosseum.json`). 여기서는 그리고 누르기만 한다.
## 설계 전문 = `docs/ref/porting/Colosseum.md`.
##
## ## ⚠️ 판본 불일치 — 배치 코드는 후기판, 자산은 구판
## 디컴프한 `ColosseumScene::initWidget` @00f34bc0(13,024B)은 **후기판**이라
## `new9patch/colosseumbox1·2`, `top_info_box`, `classes_box`, `dragoninfo_box`,
## `sg_bottom_box_3`, `newCommon/ma_icon_notice`, `txt_1vs1/3vs3(_per)`, `plus_1_btn`,
## `plus_full_btn`, `simulation_mode_icon`, `revenge_toenail`, `colosseum_info_btn`,
## `btnicon_battle/ranking`, `dual_badge`, `randommatch_spine` 을 부르는데
## **`new9patch/`·`newCommon/` 폴더 자체가 우리 덤프에 없고**(missing_frames.py 의 `new*` 63% 군)
## 나머지도 `scene/colosseum.img_plist` 에 0건이다.
##
## 반면 **구판 로비 프레임은 거의 다 있다**(`assets/converted/colosseum_ui/` 116키):
##   `top_bg` `top_profile_bg` `titlebar` `colosseum_title` `window_deco`
##   `tab_normal` `tab_selected` `txt_overall_kr` `txt_weekly_kr`
##   `list_bg1~6` `list_box2` `profilebox` `pvp_point_bg`
##   `stamina_bar` `stamina_bar_bg` `week_time` `week_time_bg` `daily_time`
##   `icon_1vs1` `icon_3vs3` `icon_vs_bg` `mini_vs` `refresh` `btn_refresh`
##   `rank_reward` `rank_reward_bar` `tournament_box1/2` `tournament_box_frame`
##
## ⇒ `MultyEquipPop` 과 같은 방침: **배치·좌표는 원작 그대로 쓰고, 없는 패널만 보유 9patch 로
##   대체**한다. 자작 도형으로 흉내 내지 않는다. 교체 지점은 `SUB_*` 상수 몇 줄뿐이다.
##
## ## 원작 initWidget 에서 그대로 가져온 수치
##   · 목록 패널  `CCScale9Sprite("9patch/popup5.png", capInsets(25,25,4,4))`
##       anchor(0,0) · pos(20, 0) · contentSize(visW-340, visH-97)   ← 오른쪽 **320pt** 를 비운다
##   · 패널 장식  `scene/colosseum/window_deco.png` capInsets(0,0,719,115)
##       contentSize(panelW+20, decoH) · anchor(0.5,1) · pos(panelW*0.5, panelH+26)
##   · 모드 버튼  `icon_vs_bg.png` anchor(0.5,0) · pos(visW*0.5, visH-150)
##       그 위에 `icon_1vs1`/`icon_3vs3` 를 얹고, 버튼 2개를 (w+35, h/2)·(w+150, h/2) 에 둔다
##   · 주간시간  `week_time.png` anchor(0,0.5) · pos(10, h/2) + 그 오른쪽 3pt 에 BMFont
##   · 새로고침  `refresh.png` anchor(0,0.5) · pos(13, h/2) + 남은 횟수 BMFont
##   · 구분선    `scene/cave/info_line.png` 중앙
##   · 배경      `scene/colosseum/stage_3.jpg`
##
## ⚫ 이 화면에서 **컷**: 방어덱(Dual)·복수전(revenge)·일일매치·토너먼트·친구전·리플레이
##   저장/재생·2020 시즌 보상·티켓 결제(`onClickRecharge`). 사유 = docs/ref/porting/Colosseum.md §1.

const BG_DIR := "res://assets/converted/colosseum_bg"
const CO := "colosseum_ui"          # 콜로세움 아틀라스
const NP := "ninepatch_ui"          # 9patch 아틀라스
const CM := "common_ui"             # common 아틀라스

# 원작 initWidget 리터럴 — 이 4개가 화면 골격이다.
const RIGHT_COL := 340.0            # 원작 contentSize(visW - 340, …) — 오른쪽 열
const PANEL_LEFT := 20.0            # 원작 setPosition(20, 0)
const PANEL_TOP_GAP := 97.0         # 원작 contentSize(…, visH - 97)
const DECO_LIFT := 26.0             # 원작 pos(panelW*0.5, panelH + 26)
const POPUP5_CAP := Rect2(25, 25, 4, 4)

# 상대 목록 행 = 원작 `scene/colosseum/profilebox`(338×77). 후기판 `new9patch/colosseumbox1` 이
# 미보유라 처음엔 `9patch_ranking_info_box` 로 때웠는데, **구판 원본이 있었다** — 그걸 쓴다.
# 선택 표시는 같은 프레임에 `list_bg3`(449×59) 하이라이트를 겹치지 않고 modulate 로 준다.
const CELL_FRAME := "scene_colosseum_profilebox"
const CELL_CAP := Rect2(40, 30, 4, 4)          # 9-slice 안전 캡(좌우 테두리 보존)
const POINT_FRAME := "scene_colosseum_pvp_point_bg"   # 230×41 — 레이팅 표시칸

var _pma: CanvasItemMaterial
var _mans: Dictionary = {}
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _mode := "team"                 # "single"(1vs1) | "team"(3vs3) — 원작 탭
var _opponents: Array = []
var _selected := -1


func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_reroll()


func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	Bgm.play("bg_colosseum")        # 원작 콜로세움 BGM(music/bg_colosseum.mp3 실재)
	_reroll()


## 상대 목록을 새로 굴리고 다시 그린다(진입·탭 전환·새로고침 공용).
func _reroll() -> void:
	_opponents = Colosseum.roll_opponents(_mode, _rng)
	_selected = -1
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var vis := _vis()
	_build_bg(vis)
	var panel := _build_panel(vis)
	_build_tabs(panel)
	_build_list(panel)
	_build_right_column(vis)


# ---------- 배경 ----------

func _build_bg(vis: Vector2) -> void:
	# 원작 initWidget 이 부르는 배경 그대로.
	var p := "%s/stage_3.jpg" % BG_DIR
	if not ResourceLoader.exists(p):
		return
	var t: Texture2D = load(p)
	var tr := TextureRect.new()
	tr.texture = t
	tr.size = vis
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(tr)


# ---------- 목록 패널 ----------

## 원작: `9patch/popup5` capInsets(25,25,4,4) · anchor(0,0) · pos(20,0) · size(visW-340, visH-97).
## Cocos anchor(0,0)=좌하단이므로 Godot 좌표로 뒤집는다.
func _build_panel(vis: Vector2) -> Control:
	var sz := Vector2(vis.x - RIGHT_COL, vis.y - PANEL_TOP_GAP)
	var np := _nine("9patch_popup5", sz, POPUP5_CAP)
	var host := Control.new()
	host.position = Vector2(PANEL_LEFT, vis.y - sz.y)   # Cocos (20,0) → 하단 기준
	host.size = sz
	add_child(host)
	if np != null:
		host.add_child(np)
	# 패널 상단 장식 — 원작 window_deco(539×86), 폭 = 패널폭+20, 위로 걸치고 26pt 만 겹친다.
	# capInsets 는 원작이 (0,0,719,115) 로 주는데 그건 후기판 큰 프레임 기준이라
	# 우리 539×86 에 그대로 쓰면 캡이 프레임을 넘는다 → 가로만 늘어나게 좌우 캡을 잡는다.
	var dh := 86.0 * Design.ASSET_SCALE
	var deco := _nine9("scene_colosseum_window_deco", Vector2(sz.x + 20.0, dh),
		Rect2(60, 20, 4, 4), CO)
	if deco != null:
		deco.position = Vector2(-10.0, -dh + DECO_LIFT)
		host.add_child(deco)
	# 제목 — 장식 띠 한가운데.
	var title := _spr(CO, "scene_colosseum_colosseum_title", Design.ASSET_SCALE)
	if title != null:
		title.position = Vector2(sz.x * 0.5, -dh + DECO_LIFT + dh * 0.5)
		host.add_child(title)
	return host


# ---------- 탭(1vs1 / 3vs3) ----------
#
# 원작은 `TabMenu`(setMenuPosX 50) 로 모드를 가른다. 라벨 프레임 `txt_1vs1/3vs3` 은 미보유라
# 보유한 `icon_1vs1`/`icon_3vs3` 아이콘을 그대로 탭 얼굴로 쓴다.

const TAB_W := 168.0                # tab_normal 101px ×4/3 ≈ 135 → 라벨이 들어가게 조금 넓힌다
const TAB_H := 47.0                 # 35px ×4/3
const TAB_X0 := 50.0                # 원작 TabMenu::setMenuPosX(…, 50)
const TAB_TOP := 12.0               # 패널 안쪽 상단
const TAB_DROP := 8.0               # 비선택 탭은 내려앉는다(shop.gd::_build_tabs 와 동일)

func _build_tabs(host: Control) -> void:
	# 원작 `icon_1vs1`/`icon_3vs3` 은 25×27 짜리 **작은 아이콘**이라 그것만으론 탭을 못 읽는다
	# → 아이콘 + 한글 라벨을 함께 얹는다(라벨 프레임 `txt_1vs1/3vs3` 은 미보유, §판본 불일치).
	var modes := [["single", "scene_colosseum_icon_1vs1", "1 vs 1"],
				  ["team", "scene_colosseum_icon_3vs3", "3 vs 3"]]
	for i in modes.size():
		var key := String(modes[i][0])
		var on := key == _mode
		var b := Button.new()
		b.flat = true
		b.size = Vector2(TAB_W, TAB_H)
		b.position = Vector2(TAB_X0 + float(i) * (TAB_W + 8.0),
			TAB_TOP + (0.0 if on else TAB_DROP))
		var bg := _nine9("scene_colosseum_tab_selected" if on else "scene_colosseum_tab_normal",
			Vector2(TAB_W, TAB_H), Rect2(30, 20, 4, 4), CO)
		if bg != null:
			b.add_child(bg)
		var ic := _spr(CO, String(modes[i][1]), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(30.0, TAB_H * 0.5)
			b.add_child(ic)
		var lb := Label.new()
		lb.text = String(modes[i][2])
		lb.position = Vector2(52.0, TAB_H * 0.5 - 13.0)
		lb.add_theme_font_size_override("font_size", 20)
		if not on:
			lb.modulate = Color(0.75, 0.72, 0.66)
		b.add_child(lb)
		var m := key
		b.pressed.connect(func() -> void:
			if _mode == m:
				return
			_mode = m
			_reroll())
		host.add_child(b)


# ---------- 상대 목록 ----------

const CELL_H := 103.0               # profilebox 77px ×4/3
const CELL_GAP := 6.0
const LIST_TOP := TAB_TOP + TAB_H + 14.0
const LIST_PAD := 22.0

func _build_list(host: Control) -> void:
	var w := host.size.x - LIST_PAD * 2.0
	for i in _opponents.size():
		var o: Dictionary = _opponents[i]
		var cell := Control.new()
		cell.position = Vector2(LIST_PAD, LIST_TOP + float(i) * (CELL_H + CELL_GAP))
		cell.size = Vector2(w, CELL_H)
		host.add_child(cell)

		var bg := _nine9(CELL_FRAME, Vector2(w, CELL_H), CELL_CAP, CO)
		if bg != null:
			if i == _selected:
				bg.modulate = Color(1.25, 1.18, 0.85)   # 선택 강조(원작 선택 프레임 미보유)
			cell.add_child(bg)

		# 티어 테두리 — 원작 ColosseumProfile::getRatingBorder 가 고르는 그 프레임.
		var rating := int(o.get("rating", 0))
		var border := Colosseum.tier_frame(rating, "icon")   # common/tier_icon_%s.png
		var bkey := "common_" + border.get_slice("/", 1).replace(".png", "") if border != "" else ""
		if bkey != "":
			var bs := _spr(CM, bkey, Design.ASSET_SCALE)
			if bs != null:
				bs.position = Vector2(44.0, CELL_H * 0.5)
				cell.add_child(bs)

		# 닉네임 + 등급 라벨
		var nick := Label.new()
		nick.text = String(o.get("nick", ""))
		nick.position = Vector2(90.0, 22.0)
		nick.add_theme_font_size_override("font_size", 22)
		cell.add_child(nick)

		var sub := Label.new()
		var t: Dictionary = o.get("tier", {})
		sub.text = "%s  %d점" % [String(t.get("name", "")), rating]
		sub.position = Vector2(90.0, 54.0)
		sub.add_theme_font_size_override("font_size", 17)
		sub.modulate = Color(0.42, 0.34, 0.24)
		cell.add_child(sub)

		# 상대 드래곤 썸네일 — 원작도 셀에 상대 덱을 보여 준다.
		var dx := w - 24.0
		var drs: Array = o.get("dragons", [])
		for j in range(drs.size() - 1, -1, -1):
			var d: Dictionary = drs[j]
			var did := int(d.get("id", 0))
			# 썸네일 규약은 party_card.gd 와 같다 — portrait_<id>/dragon_dragon_<id>_box_<stage>.
			var stage := Growth.portrait_stage(d)
			var th := _spr("portrait_%d" % did, "dragon_dragon_%d_box_%s" % [did, stage], 0.5)
			if th == null:
				th = _spr("portrait_%d" % did, "dragon_dragon_%d_box_adult" % did, 0.5)
			if th != null:
				th.position = Vector2(dx - 30.0, CELL_H * 0.5)
				cell.add_child(th)
			dx -= 66.0

		# 연승방지봇 표식 — 원작 연승 배너와 같은 개념(FightScene::showWinningStreak).
		if String(o.get("grade", "")) == "ranker":
			var tag := Label.new()
			tag.text = "★"
			tag.position = Vector2(w - 30.0, 10.0)
			tag.modulate = Color(1.0, 0.85, 0.35)
			cell.add_child(tag)

		var idx := i
		var btn := Button.new()
		btn.flat = true
		btn.size = cell.size
		btn.pressed.connect(func() -> void: _on_pick(idx))
		cell.add_child(btn)


func _on_pick(i: int) -> void:
	if i < 0 or i >= _opponents.size():
		return
	_selected = i
	if not Colosseum.can_enter():
		# 원작 문구 그대로 — `ColosseumNoStamina`. 원작은 '입장권'이 아니라 **피로도**라 부른다.
		_notice(String(Data.colosseum.get("log", {}).get("no_stamina",
			"피로도가 부족하여 전투에 참여가 불가능합니다.")))
		_rebuild()
		return
	var foe: Dictionary = _opponents[i]
	var n := Colosseum.party_size(_mode)
	# 🟠 덱 선택 = 우리 `PartySelect`(원작 `AddDragonCell` 이식본) 재사용.
	#   원작 콜로세움 전용 선택창은 `Select3vs3Layer`/`Select1vs1Layer` 로 따로 있고
	#   (CCMenuOnScrollView + `makeMagneticDummy` 드래그 재정렬 + `dragon_select_deco`),
	#   형태가 다르다. 그쪽 이식은 별건으로 남긴다 — 지금은 **같은 일을 하는 원작 유래
	#   위젯**을 쓴다(자작 창을 새로 만드는 것보다 낫다). docs/ref/porting/Colosseum.md §1.
	PartySelect.open_run(self, UserDB.party().slice(0, n), func(picked: Array) -> void:
		if picked.is_empty():
			return
		if not Colosseum.spend_ticket():
			_notice("입장권이 부족합니다.")
			return
		Colosseum.consume_guard()
		Scenes.goto("fight", {"mode": _mode, "opponent": foe, "party": picked.slice(0, n)}))
	_rebuild()


# ---------- 우측 열(프로필 · 입장권 · 모드 진입) ----------

func _build_right_column(vis: Vector2) -> void:
	var x := vis.x - RIGHT_COL + PANEL_LEFT
	var col := Control.new()
	col.position = Vector2(x, 0.0)
	col.size = Vector2(RIGHT_COL - PANEL_LEFT, vis.y)
	add_child(col)

	var s := Colosseum.refresh_ticket()
	var rating := Colosseum.rating_of(_mode)
	var streak := Colosseum.streak_of(_mode)

	# 우측 열은 좁다(320pt) — 가로로 늘어놓으면 화면 밖으로 밀린다. **세로로 쌓는다.**
	const PAD := 18.0
	var cw := col.size.x - PAD * 2.0
	var mt := Colosseum.tier_of(rating)

	# ── 내 프로필: top_profile_bg(60×62) 안에 티어 아이콘 ──────────────────────
	var py := 76.0
	var pbg := _spr(CO, "scene_colosseum_top_profile_bg", Design.ASSET_SCALE)
	if pbg != null:
		pbg.position = Vector2(col.size.x * 0.5, py)
		col.add_child(pbg)
	var tf := Colosseum.tier_frame(rating, "icon")
	if tf != "":
		var tk := "common_" + tf.get_slice("/", 1).replace(".png", "")
		var ts := _spr(CM, tk, Design.ASSET_SCALE * 0.8)
		if ts != null:
			ts.position = Vector2(col.size.x * 0.5, py)
			col.add_child(ts)

	var tn := _center_label(String(mt.get("name", "")), col.size.x, py + 52.0, 24)
	col.add_child(tn)

	# 레이팅 — 원작 pvp_point_bg(230×41) 칸에 얹는다.
	var pb := _nine9(POINT_FRAME, Vector2(cw, 41.0 * Design.ASSET_SCALE),
		Rect2(30, 20, 4, 4), CO)
	if pb != null:
		pb.position = Vector2(PAD, py + 88.0)
		col.add_child(pb)
	col.add_child(_center_label("%d 점" % rating, col.size.x, py + 100.0, 21))

	col.add_child(_center_label("%d연승  (최고 %d)" % [streak, int(s.get(
		"straight_single_best" if _mode == "single" else "straight_team_best", 0))],
		col.size.x, py + 148.0, 17, Color(1.0, 0.92, 0.7)))

	# ── 입장권 게이지 — 원작 stamina_bar / stamina_bar_bg(125×11) ──────────────
	var have := int(s.get("energy", 0))
	var mx := int(Data.colosseum.get("ticket", {}).get("max", 10))
	var gy := py + 196.0
	var gw := 125.0 * Design.ASSET_SCALE
	var gx := col.size.x * 0.5 - gw * 0.5
	var gbg := _spr(CO, "scene_colosseum_stamina_bar_bg", Design.ASSET_SCALE)
	if gbg != null:
		gbg.position = Vector2(col.size.x * 0.5, gy)
		col.add_child(gbg)
	var gt := _tex(CO, "scene_colosseum_stamina_bar")
	if gt != null and have > 0:
		var ratio := clampf(float(have) / float(maxi(1, mx)), 0.0, 1.0)
		var fill := Sprite2D.new()
		fill.texture = gt
		fill.material = _pma
		fill.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		fill.region_enabled = true
		fill.region_rect = Rect2(0, 0, float(gt.get_width()) * ratio, gt.get_height())
		# region 을 왼쪽만 남기면 중심도 왼쪽으로 옮겨야 왼쪽 기준으로 찬다.
		fill.position = Vector2(gx + gw * ratio * 0.5, gy)
		col.add_child(fill)
	# 원작 명칭은 **피로도**다(ColosseumNoStamina · Colosseum_1vs1_Energy_Msg).
	# 표기도 원작 updateStamina 와 같은 "n/10" 꼴.
	col.add_child(_center_label("피로도 %d / %d" % [have, mx], col.size.x, gy + 14.0, 17))

	# ── 하단 버튼 ─────────────────────────────────────────────────────────────
	var bw := cw - 40.0
	AtlasUI.frame_button(col, "새로고침", Vector2(20.0, vis.y - 116.0),
		Vector2(bw, 44.0), func() -> void: _reroll())
	AtlasUI.frame_button(col, "나가기", Vector2(20.0, vis.y - 64.0),
		Vector2(bw, 44.0), func() -> void: Scenes.goto("worldmap", {"from": "colosseum"}))


func _notice(msg: String) -> void:
	Toast.show(self, msg)


## 좁은 우측 열용 — 폭 전체에 가운데 정렬한 라벨.
func _center_label(text: String, w: float, y: float, size: int,
		col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.size = Vector2(w, float(size) + 8.0)
	l.position = Vector2(0.0, y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	return l


# ---------- 헬퍼(다른 씬과 같은 규약) ----------

func _vis() -> Vector2:
	return get_viewport_rect().size

func _tex(dir: String, key: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	return load(p) if ResourceLoader.exists(p) else null

func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var t := _tex(dir, key)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _nine(key: String, sz_pt: Vector2, cap: Rect2) -> NinePatchRect:
	return _nine9(key, sz_pt, cap, NP)

## 원작 `CCScale9Sprite::createWithSpriteFrameName(frame, capInsets)`.
## capInsets 는 **포인트**, Godot patch_margin 은 **텍스처 픽셀** → ×0.75 환산(§9).
func _nine9(key: String, sz_pt: Vector2, cap: Rect2, dir: String) -> NinePatchRect:
	var tex := _tex(dir, key)
	if tex == null:
		return null
	var inv := 1.0 / Design.ASSET_SCALE
	var l := tex.get_width() / 3.0
	var t := tex.get_height() / 3.0
	var cw := l
	var ch := t
	if cap.size != Vector2.ZERO:
		l = cap.position.x * inv; t = cap.position.y * inv
		cw = cap.size.x * inv; ch = cap.size.y * inv
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - ch)))
	np.size = sz_pt if sz_pt.y > 0.0 else Vector2(sz_pt.x, float(tex.get_height()) * Design.ASSET_SCALE)
	np.material = _pma
	return np
