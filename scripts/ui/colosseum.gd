extends Control
## 콜로세움 로비 — 원작 `ColosseumScene` 이식. render 층(§8).
##
## 🟦 사용자 확정 2026-08-04 — 상대를 봇으로만 채운 **솔로** 콜로세움.
## 판정·표·봇 생성은 전부 logic(`Colosseum` + `data/colosseum.json`). 여기서는 그리고 누르기만 한다.
## 설계 전문 = `docs/ref/porting/Colosseum.md`.
##
## ## 🔴 2026-08-04 재작성 — 구판 로비 클래스를 찾았다
## 종전 구현은 "후보 5명 목록에서 상대를 골라 싸운다"였는데 그건 **후기판(2020) 오독**이다.
## 원작 구판 로비는 별도 클래스 **`__ColosseumScene`** 으로 libgame.so 에 그대로 남아 있었다
## (2026-08-04 `batch_decompile.py --classes __ColosseumScene --max 20000`, 104함수).
## 그 `initWidget` @00f1fedc(15,980B)이 이 화면의 정답이고, 흐름은 이렇다:
##
##   `scene/colosseum/btn_menu.png` 버튼 **4개를 오른쪽에 세로로 쌓는다**
##     첫 버튼 pos = (visW - btnW*0.5 - 25, btnH*0.5 + 16), 위로 (btnH + 2) 간격
##     생성 순서 = 일일매치 · 3vs3 · 1vs1 · 토너먼트 인데 **좌표를 서로 바꿔 꽂아**
##     최종 위→아래 = **1VS1 · 3VS3 · 일일매치 · 토너먼트**
##     각 버튼: `icon_vs_bg.png` anchor(0.5,0) @ (btnW*0.5, 30)
##              그 위 왼쪽 끝에 `icon_1vs1`/`icon_3vs3`
##              BMFont(getFontName_subtitle) "1 VS 1" / "3 VS 3" @ (btnW*0.5, 80)
##   → 누르면 `onClickedColosseum1vs1` @00f257a4 / `onClickedColosseum3vs3` @00f25570
##       피로도 0 이면 토스트 → `checkDragon()` 실패면 토스트
##       → `LoadingLayer::show()` → `FightManager::setType(0|1)`
##       → `Select1vs1Layer/Select3vs3Layer::create(1)` → `show()`
##   즉 **시작 버튼 → 덱 선택 → 상대는 서버가 배정**. 로비에서 상대를 고르지 않는다.
##
## 왼쪽 큰 패널은 **랭킹 보드**다 — 구판 `responseList` 가 처리하는 JSON 키가
## `pvp_total_rank` / `pvp_week_rank` / `my_rank` / `my_week_rank` 이고
## 후보 목록 키(`match1_list`/`match3_list`)는 **후기판에만** 있다.
## 탭 프레임도 `txt_overall_%s` / `txt_weekly_%s` / `txt_friends_%s` / `txt_dual_%s` 4종이고
## 앞의 둘은 우리가 보유한다(뒤의 둘 = 친구전·방어덱 ⚫CUT).
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
## ## 원작 `__ColosseumScene::initWidget` 에서 그대로 가져온 수치
##   · 배경      `scene/colosseum/stage_3.jpg` 화면 중앙
##   · 제목바    `TitleLayer::create("scene/colosseum/titlebar.png", <제목>, this, onClickedX)` z=3
##   · 목록 패널  `CCScale9Sprite("9patch/popup5.png", capInsets)`
##       anchor(0,0) · pos(20, 0) · **contentSize(visW - btnW - 67, visH - 97)**
##   · 패널 장식  `scene/colosseum/window_deco.png`
##       contentSize(panelW+20, decoH) · anchor(0.5,1) · pos(panelW*0.5, panelH+26)
##   · 목록 판    `new9patch/du_bg_01`(미보유) contentSize(panelW-44, 481) anchor(0.5,1)
##   · 시작 버튼  `btn_menu.png` ×4, 첫 pos(visW - btnW*0.5 - 25, btnH*0.5 + 16), 위로 (btnH+2)
##       각 버튼 안: `icon_vs_bg` anchor(0.5,0) pos(btnW*0.5, 30) → 그 위 왼쪽에 모드 아이콘
##                   BMFont "1 VS 1"/"3 VS 3" pos(btnW*0.5, 80)
##   · 주간시간  `new9patch/du_box_02`(미보유) 300×40 @ (15, panelH-15)
##       그 안 `week_time.png` anchor(0,0.5) pos(10, h/2) + 오른쪽 3pt 에 BMFont
##   · 새로고침  같은 판 155×40 + `refresh.png` anchor(0,0.5) pos(13, h/2) + 남은 횟수 BMFont
##   · 보상안내  `common/ether_rank.png` 버튼 anchor(1,0.5) → `onClickedRankInfo`
##   · 피로도    `item/item_small/ticket.png` scale 0.5 + BMFont anchor(0,0.5)
##
## ⚫ 이 화면에서 **컷**: 방어덱(Dual)·복수전(revenge)·일일매치·토너먼트·친구전·리플레이
##   저장/재생·2020 시즌 보상·티켓 결제(`onClickRecharge`). 사유 = docs/ref/porting/Colosseum.md §1.

const BG_DIR := "res://assets/converted/colosseum_bg"
const CO := "colosseum_ui"          # 콜로세움 아틀라스
const NP := "ninepatch_ui"          # 9patch 아틀라스
const CM := "common_ui"             # common 아틀라스

# 원작 initWidget 리터럴 — 이 넷이 화면 골격이다.
# 오른쪽 열 폭은 원작이 `btnW + 67` 로 잡는다(`CCSize(visW - btnW - 67, visH - 97)`).
# btn_menu 196px × ASSET_SCALE = 261.33pt → 261.33 + 67 = 328.33.
const BTN_MENU_W := 196.0 * Design.ASSET_SCALE      # 261.33pt
const BTN_MENU_H := 104.0 * Design.ASSET_SCALE      # 138.67pt
const RIGHT_COL := BTN_MENU_W + 67.0                # 원작 contentSize(visW - btnW - 67, …)
const PANEL_LEFT := 20.0            # 원작 setPosition(20, 0)
const PANEL_TOP_GAP := 97.0         # 원작 contentSize(…, visH - 97)
const DECO_LIFT := 26.0             # 원작 pos(panelW*0.5, panelH + 26)
const POPUP5_CAP := Rect2(25, 25, 4, 4)

# 시작 버튼 배치 — 원작 그대로.
const BTN_RIGHT_PAD := 25.0         # 원작 pos.x = visW - btnW*0.5 - 25
const BTN_BOTTOM := 16.0            # 원작 pos.y = btnH*0.5 + 16
const BTN_GAP := 2.0                # 원작 다음 버튼 = 앞 버튼 + (0, btnH + 2)
const BTN_VS_BG_Y := 30.0           # 원작 icon_vs_bg pos(btnW*0.5, 30) anchor(0.5,0)
const BTN_LABEL_Y := 80.0           # 원작 "1 VS 1" BMFont pos(btnW*0.5, 80)

# 랭킹 행 = 원작 `ColosseumRankPvpCell::initWithSize` @00f0b2e4 가 쓰는 `9patch/replay_bg`(68×68).
# 점수칸은 구판 `scene/colosseum/pvp_point_bg`(230×41).
const CELL_FRAME := "9patch_replay_bg"
const CELL_CAP := Rect2(24, 24, 8, 8)
const POINT_FRAME := "scene_colosseum_pvp_point_bg"   # 230×41 — 레이팅 표시칸

var _pma: CanvasItemMaterial
var _mans: Dictionary = {}
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# 원작 탭 = 전체(pvp_total_rank) / 주간(pvp_week_rank). 친구·방어덱 탭은 ⚫CUT.
var _weekly := false
# 랭킹 보드는 모드별로 따로다(원작도 single/tournament 레이팅이 갈린다).
# 보드에서 보는 모드는 마지막에 누른 시작 버튼과 무관하게 유지한다.
var _board_mode := "team"


func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()


func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	# 원작 `ColosseumScene::onEnterTransitionDidFinish` @00f41e00 —
	# `playBackground("music/bg_colosseum.mp3", loop=1)`. 경로는 data 로 뺐다.
	Bgm.play(Colosseum.lobby_bgm())
	# 일일/주간 보상 — 원작은 우편함 지급(⚫온라인 CUT)이라 진입 시 즉시 준다.
	# 문구도 원작 그대로(Colosseum_Daily_Result_1 / Colosseum_Weekly_Result_1).
	for r: Dictionary in Colosseum.claim_rewards():
		var kind := "일일" if String(r.get("kind", "")) == "daily" else "이번 시즌"
		_notice("%s 보상 다이아 %d개와 콜로세움 주화 %d개를 지급했어!"
			% [kind, int(r.get("dia", 0)), int(r.get("coin", 0))])
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var vis := _vis()
	_build_bg(vis)
	var panel := _build_panel(vis)
	_build_tabs(panel)
	_build_rank_list(panel)
	_build_panel_footer(panel)
	# ⚠️ 우측 열을 **먼저** 짓는다. 이 Control 은 시작 버튼과 겹치는데(원작 열 폭이 btnW+67 이라
	#   버튼이 그 안에 든다) 나중에 붙이면 위에 깔려 버튼 클릭을 먹는다 — `mouse_filter` 도
	#   IGNORE 로 내려 둔다(Control 기본값은 STOP).
	_build_right_column(vis)
	_build_start_buttons(vis)


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


# ---------- 탭(전체 / 주간) ----------
#
# 원작 `TitleLayer::setTabImageMenus(this, onClickedTab, 0, weekly, overall, friends, dual)`
# + `TabMenu::setMenuPosX(…, 50)`. 탭 얼굴은 **원작 이미지 그대로** 쓴다 —
# `txt_overall_kr`(70×23) · `txt_weekly_kr` 을 `tab_normal`/`tab_selected`(101×35) 위에 얹는다.
# ⚫ `txt_friends`(친구전) · `txt_dual`(방어덱) 탭은 CUT — 프레임은 보유하지만 §2-1 대상이다.

const TAB_W := 101.0 * Design.ASSET_SCALE   # 134.67pt — 원작 tab_normal 실측폭
const TAB_H := 35.0 * Design.ASSET_SCALE    # 46.67pt
const TAB_X0 := 50.0                # 원작 TabMenu::setMenuPosX(…, 50)
const TAB_GAP := 6.0
const TAB_TOP := 10.0
const TAB_DROP := 8.0               # 비선택 탭은 내려앉는다(shop.gd::_build_tabs 와 동일)

func _build_tabs(host: Control) -> void:
	var tabs := [[false, "scene_colosseum_txt_overall_kr"],
				 [true, "scene_colosseum_txt_weekly_kr"]]
	for i in tabs.size():
		var weekly := bool(tabs[i][0])
		var on := weekly == _weekly
		var b := Button.new()
		b.flat = true
		b.size = Vector2(TAB_W, TAB_H)
		b.position = Vector2(TAB_X0 + float(i) * (TAB_W + TAB_GAP),
			TAB_TOP + (0.0 if on else TAB_DROP))
		var bg := _spr(CO, "scene_colosseum_tab_selected" if on else "scene_colosseum_tab_normal",
			Design.ASSET_SCALE)
		if bg != null:
			bg.position = Vector2(TAB_W * 0.5, TAB_H * 0.5)
			b.add_child(bg)
		var txt := _spr(CO, String(tabs[i][1]), Design.ASSET_SCALE)
		if txt != null:
			txt.position = Vector2(TAB_W * 0.5, TAB_H * 0.5)
			if not on:
				txt.modulate = Color(0.72, 0.68, 0.62)
			b.add_child(txt)
		var w := weekly
		b.pressed.connect(func() -> void:
			if _weekly == w:
				return
			_weekly = w
			_rebuild())
		host.add_child(b)

	# ── 보드 모드(1vs1 / 3vs3) ────────────────────────────────────────────────
	# ASSUMPTION: 원작 응답 키는 `pvp_total_rank` **하나**라 모드별 랭킹이 따로였는지 알 수 없다.
	#   우리는 레이팅을 모드별로 따로 갖고 있으므로(원작 `single` / `tournament`) 보드도 나눈다.
	#   ⚫컷된 친구전·방어덱 탭 자리를 그대로 쓰고, 얼굴은 원작 `icon_1vs1`/`icon_3vs3` 다.
	var mtabs := [["single", "scene_colosseum_icon_1vs1"],
				  ["team", "scene_colosseum_icon_3vs3"]]
	for i in mtabs.size():
		var key := String(mtabs[i][0])
		var on := key == _board_mode
		var b := Button.new()
		b.flat = true
		b.size = Vector2(TAB_W * 0.62, TAB_H)
		b.position = Vector2(TAB_X0 + 2.0 * (TAB_W + TAB_GAP) + 26.0
			+ float(i) * (TAB_W * 0.62 + TAB_GAP), TAB_TOP + (0.0 if on else TAB_DROP))
		var bg := _nine9("scene_colosseum_tab_selected" if on else "scene_colosseum_tab_normal",
			Vector2(TAB_W * 0.62, TAB_H), Rect2(30, 18, 6, 6), CO)
		if bg != null:
			b.add_child(bg)
		var ic := _spr(CO, String(mtabs[i][1]), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(TAB_W * 0.31, TAB_H * 0.5)
			if not on:
				ic.modulate = Color(0.7, 0.66, 0.6)
			b.add_child(ic)
		var m := key
		b.pressed.connect(func() -> void:
			if _board_mode == m:
				return
			_board_mode = m
			_rebuild())
		host.add_child(b)


# ---------- 랭킹 보드(원작 pvp_total_rank / pvp_week_rank) ----------

const CELL_H := 62.0
const CELL_GAP := 4.0
const LIST_TOP := TAB_TOP + TAB_H + 12.0
const LIST_PAD := 22.0
const LIST_BOTTOM := 62.0           # 아래 주간시간·새로고침 띠 자리

func _build_rank_list(host: Control) -> void:
	var w := host.size.x - LIST_PAD * 2.0
	var view_h := host.size.y - LIST_TOP - LIST_BOTTOM

	# 원작은 목록 뒤에 `new9patch/du_bg_01`(미보유) 판을 깐다 → 보유 `9patch/list_bg2` 로 대체.
	var back := _nine("9patch_list_bg2", Vector2(w, view_h), Rect2(24, 24, 8, 8))
	if back != null:
		back.position = Vector2(LIST_PAD, LIST_TOP)
		back.modulate = Color(1, 1, 1, 0.85)
		host.add_child(back)

	var sc := ScrollContainer.new()
	sc.position = Vector2(LIST_PAD + 6.0, LIST_TOP + 6.0)
	sc.size = Vector2(w - 12.0, view_h - 12.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(sc)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(sc.size.x, 0.0)
	sc.add_child(inner)

	var rows := Colosseum.ladder(_board_mode, _weekly, _rng).duplicate()
	# 내 자리를 점수대로 끼워 넣는다(원작 my_rank / my_week_rank 와 같은 규칙).
	var mine := Colosseum.rating_of(_board_mode)
	var me_nick := UserDB.user_nickname()
	if me_nick == "":
		me_nick = "나"
	rows.append({"nick": me_nick, "rating": mine, "me": true})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rating", 0)) > int(b.get("rating", 0)))

	var cw := sc.size.x
	for i in rows.size():
		var r: Dictionary = rows[i]
		var cell := Control.new()
		cell.position = Vector2(0.0, float(i) * (CELL_H + CELL_GAP))
		cell.size = Vector2(cw, CELL_H)
		inner.add_child(cell)

		# 배경은 셀의 **첫 자식**이어야 한다 — 나중에 붙이면 라벨을 덮는다.
		var bg := _nine(CELL_FRAME, Vector2(cw, CELL_H), CELL_CAP)
		if bg != null:
			if bool(r.get("me", false)):
				bg.modulate = Color(1.35, 1.22, 0.8)
			cell.add_child(bg)

		# 순위
		var rk := Label.new()
		rk.text = "%d" % (i + 1)
		rk.size = Vector2(52.0, CELL_H)
		rk.position = Vector2(4.0, 0.0)
		rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rk.add_theme_font_size_override("font_size", 22)
		rk.modulate = Color(1.0, 0.88, 0.5) if i < 3 else Color.WHITE
		cell.add_child(rk)

		# 티어 아이콘 — 원작 `ColosseumProfile::getRatingBorder` 가 고르는 그 프레임.
		var rating := int(r.get("rating", 0))
		var tf := Colosseum.tier_frame(rating, "icon")
		if tf != "":
			var tk := "common_" + tf.get_slice("/", 1).replace(".png", "")
			var ts := _spr(CM, tk, Design.ASSET_SCALE * 0.55)
			if ts != null:
				ts.position = Vector2(78.0, CELL_H * 0.5)
				cell.add_child(ts)

		var nick := Label.new()
		nick.text = String(r.get("nick", ""))
		nick.size = Vector2(cw * 0.5, CELL_H)
		nick.position = Vector2(106.0, 0.0)
		nick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nick.add_theme_font_size_override("font_size", 20)
		if bool(r.get("me", false)):
			nick.modulate = Color(1.0, 0.92, 0.55)
		cell.add_child(nick)

		# 점수칸 — 구판 pvp_point_bg(230×41).
		var pw := 230.0 * Design.ASSET_SCALE * 0.62
		var pb := _nine9(POINT_FRAME, Vector2(pw, 41.0 * Design.ASSET_SCALE * 0.72),
			Rect2(30, 18, 4, 4), CO)
		if pb != null:
			pb.position = Vector2(cw - pw - 12.0, CELL_H * 0.5 - 41.0 * Design.ASSET_SCALE * 0.36)
			cell.add_child(pb)
		var pt := Label.new()
		# 원작 `Colosseum_Word_3` = "%1$d점".
		pt.text = "%d점" % rating
		pt.size = Vector2(pw, CELL_H)
		pt.position = Vector2(cw - pw - 12.0, 0.0)
		pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pt.add_theme_font_size_override("font_size", 19)
		cell.add_child(pt)

	inner.custom_minimum_size = Vector2(cw,
		float(rows.size()) * (CELL_H + CELL_GAP))


## 패널 하단 띠 — 원작은 `new9patch/du_box_02`(미보유) 300×40 에 `week_time` 아이콘 + 남은 시간,
## 그 옆 155×40 버튼에 `refresh` 아이콘 + 남은 새로고침 횟수를 얹는다.
## 없는 판만 보유 `9patch/list_bg2` 로 대체하고 좌표·크기는 원작 그대로.
func _build_panel_footer(host: Control) -> void:
	var y := host.size.y - 52.0

	var wbox := _nine("9patch_list_bg2", Vector2(300.0, 40.0), Rect2(24, 24, 8, 8))
	if wbox != null:
		wbox.position = Vector2(15.0, y)
		host.add_child(wbox)
	var wt := _spr(CO, "scene_colosseum_week_time", Design.ASSET_SCALE)
	if wt != null:
		wt.position = Vector2(15.0 + 10.0 + 11.0, y + 20.0)
		host.add_child(wt)
	var wl := Label.new()
	wl.text = "이번 시즌 %s 남음" % _week_left()
	wl.position = Vector2(15.0 + 44.0, y + 8.0)
	wl.add_theme_font_size_override("font_size", 18)
	host.add_child(wl)

	# 새로고침 — 원작은 골드를 받는다(`Colosseum_Refresh_Msg`). 무료 횟수가 남으면 공짜.
	var rc := Colosseum.refresh_cost()
	var rb := Button.new()
	rb.flat = true
	rb.size = Vector2(155.0, 40.0)
	rb.position = Vector2(15.0 + 300.0 + 12.0, y)
	var rbg := _nine("9patch_list_bg2", Vector2(155.0, 40.0), Rect2(24, 24, 8, 8))
	if rbg != null:
		rb.add_child(rbg)
	var ri := _spr(CO, "scene_colosseum_refresh", Design.ASSET_SCALE * 0.8)
	if ri != null:
		ri.position = Vector2(13.0 + 18.0, 20.0)
		rb.add_child(ri)
	var rl := Label.new()
	rl.text = "새로고침" if rc <= 0 else "%s G" % AtlasUI.comma(rc)
	rl.size = Vector2(96.0, 40.0)
	rl.position = Vector2(56.0, 0.0)
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rl.add_theme_font_size_override("font_size", 18)
	rb.add_child(rl)
	rb.pressed.connect(func() -> void:
		if not Colosseum.pay_refresh():
			_notice("새로고침 비용이 부족합니다.")   # 원작 Colosseum_Refresh_Error
			return
		Colosseum.reroll_ladder(_board_mode, _rng)
		_rebuild())
	host.add_child(rb)

	# 보상 안내 — 원작 `common/ether_rank.png` 버튼(onClickedRankInfo → ColosseumRewardInfoLayer).
	var eb := Button.new()
	eb.flat = true
	eb.size = Vector2(60.0, 44.0)
	eb.position = Vector2(host.size.x - 76.0, y - 2.0)
	var es := _spr(CM, "common_ether_rank", Design.ASSET_SCALE)
	if es != null:
		es.position = Vector2(30.0, 22.0)
		eb.add_child(es)
	eb.pressed.connect(func() -> void:
		var c: Dictionary = Data.colosseum.get("coin", {})
		var d: Dictionary = c.get("daily", {})
		var wk: Dictionary = c.get("weekly", {})
		_notice("일일 보상 다이아 %d · 주화 %d / 시즌 보상 다이아 %d · 주화 %d"
			% [int(d.get("dia", 0)), int(d.get("coin", 0)),
			   int(wk.get("dia", 0)), int(wk.get("coin", 0))]))
	host.add_child(eb)


## 이번 시즌(주) 남은 시간 — 원작 `week_time` 라벨 자리. 주 단위 리셋은 `claim_rewards()` 규약과 같다.
func _week_left() -> String:
	var now := Time.get_unix_time_from_system()
	var week := 7 * 24 * 3600
	var left := int(week - (int(now) % week))
	return "%d일 %d시간" % [left / 86400, (left % 86400) / 3600]


# ---------- 시작 버튼(원작 btn_menu ×4 세로 스택) ----------
#
# 원작 좌표 그대로:
#   맨 아래 버튼 pos = (visW - btnW*0.5 - 25, btnH*0.5 + 16)   ← Cocos(아래 기준)
#   위로 (btnH + 2) 간격, 최종 위→아래 = 1VS1 · 3VS3 · [일일매치] · [토너먼트]
# ⚫ 일일매치(`onClickedDailyMatch`)·토너먼트(`onClickedTournament`)는 CUT(§2-1)이라
#   슬롯을 비워 두지 않고 남은 둘을 원작 앵커(우하단, 위로 쌓기)에 그대로 붙인다.

func _build_start_buttons(vis: Vector2) -> void:
	var stamina := Colosseum.refresh_ticket()
	var max_energy := int(Data.colosseum.get("ticket", {}).get("max", 10))
	var modes := [["team", "3 VS 3", "scene_colosseum_icon_3vs3"],
				  ["single", "1 VS 1", "scene_colosseum_icon_1vs1"]]
	for i in modes.size():
		var key := String(modes[i][0])
		# Cocos: 중심 y = btnH*0.5 + 16 + i*(btnH+2) (아래에서 위로) → Godot 상단 기준으로 뒤집는다.
		var cy_cocos := BTN_MENU_H * 0.5 + BTN_BOTTOM + float(i) * (BTN_MENU_H + BTN_GAP)
		var cx := vis.x - BTN_MENU_W * 0.5 - BTN_RIGHT_PAD
		var top_left := Vector2(cx - BTN_MENU_W * 0.5, vis.y - cy_cocos - BTN_MENU_H * 0.5)

		var b := Button.new()
		b.flat = true
		b.size = Vector2(BTN_MENU_W, BTN_MENU_H)
		b.position = top_left
		add_child(b)

		var face := _spr(CO, "scene_colosseum_btn_menu", Design.ASSET_SCALE)
		if face != null:
			face.position = Vector2(BTN_MENU_W * 0.5, BTN_MENU_H * 0.5)
			b.add_child(face)

		# `icon_vs_bg` anchor(0.5, 0) @ (btnW*0.5, 30) — Cocos 아래 기준이라 뒤집는다.
		# 이 띠에 올라가는 것 = **피로도 "n/10"**. 근거: `ColosseumBattleInfo::init` @01031808 이
		#   +0x18 을 subtitle BMFont 로 만들고 `updateStamina` @010319f0 가
		#   `CCString::createWithFormat("%d/%d", 남은, 10)` 을 넣는다. initWidget 은 그 라벨을
		#   ×0.8 로 vs_bg 한가운데(w*0.5, h*0.5)에 붙인다.
		var vw := 92.0 * Design.ASSET_SCALE
		var vh := 21.0 * Design.ASSET_SCALE
		var vy := BTN_MENU_H - BTN_VS_BG_Y - vh * 0.5
		var vbg := _spr(CO, "scene_colosseum_icon_vs_bg", Design.ASSET_SCALE)
		if vbg != null:
			vbg.position = Vector2(BTN_MENU_W * 0.5, vy)
			b.add_child(vbg)
		# 그 위 왼쪽 끝(원작 pos(0, h*0.5))에 모드 아이콘.
		var mi := _spr(CO, String(modes[i][2]), Design.ASSET_SCALE)
		if mi != null:
			mi.position = Vector2(BTN_MENU_W * 0.5 - vw * 0.5, vy)
			b.add_child(mi)
		var en := Label.new()
		en.text = "%d/%d" % [int(stamina.get("energy", 0)), max_energy]
		en.size = Vector2(vw, vh)
		en.position = Vector2(BTN_MENU_W * 0.5 - vw * 0.5 + 8.0, vy - vh * 0.5)
		en.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		en.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_bm_style(en, 18, Color.WHITE)
		b.add_child(en)

		# 원작 BMFont(`GameManager::getFontName_subtitle`) "1 VS 1" / "3 VS 3" @ (btnW*0.5, 80).
		var lb := Label.new()
		lb.text = String(modes[i][1])
		lb.size = Vector2(BTN_MENU_W, 40.0)
		lb.position = Vector2(0.0, BTN_MENU_H - BTN_LABEL_Y - 26.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bm_style(lb, 30, Color.WHITE)
		b.add_child(lb)

		# 연승 — 원작 버튼 **좌상단**에 주먹 아이콘 + 연승 수(title BMFont)를 붙인다.
		#   `icon_fist1`(1vs1) / `icon_fist2`(3vs3) @ (fistW*0.5 + 10, btnH - fistH*0.5 - 5)
		#   그 아래 anchor(0.5,1) 로 `ColosseumBattleInfo +0x28`(setVictory) 라벨.
		# (원작은 연승 0 이면 setVisible(false) 로 감춘다 — 같은 규칙.)
		var st := Colosseum.streak_of(key)
		if st > 0:
			var fw := 42.0 * Design.ASSET_SCALE
			var fx := fw * 0.5 + 10.0
			var fy := fw * 0.5 + 5.0
			var fi := _spr(CO, "scene_colosseum_icon_fist%d" % (1 if key == "single" else 2),
				Design.ASSET_SCALE * 0.7)
			if fi != null:
				fi.position = Vector2(fx, fy)
				b.add_child(fi)
			var sl := Label.new()
			sl.text = "%d" % st
			sl.size = Vector2(fw + 20.0, 24.0)
			sl.position = Vector2(fx - (fw + 20.0) * 0.5, fy + fw * 0.35)
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_bm_style(sl, 20, Color(1.0, 0.86, 0.5), "font_title")
			b.add_child(sl)

		var m := key
		b.pressed.connect(func() -> void: _start(m))


## 원작 `onClickedColosseum1vs1` / `onClickedColosseum3vs3` 의 검사 순서를 그대로 따른다.
##   ① 피로도 0 → 토스트  ② `checkDragon()` 실패 → 토스트  ③ 덱 선택창
## 서버가 하던 "상대 배정"은 `Colosseum.roll_match()` 가 대신한다.
func _start(mode: String) -> void:
	# ① 피로도 — 원작 문구 그대로(`ColosseumNoStamina`). 원작은 '입장권'이 아니라 **피로도**다.
	if not Colosseum.can_enter():
		_notice(String(Data.colosseum.get("log", {}).get("no_stamina",
			"피로도가 부족하여 전투에 참여가 불가능합니다.")))
		return
	# ② checkDragon — 원작 입장 조건은 레벨 25 이상(`ColosseumInError`).
	var n := Colosseum.party_size(mode)
	var ok := Colosseum.eligible_uids()
	if ok.size() < n:
		_notice("레벨 %d 이상 드래곤이 %d마리 필요합니다." % [Colosseum.min_level(), n])
		return
	# ③ 덱 선택.
	# 🟠 원작 전용 선택창은 `Select1vs1Layer`/`Select3vs3Layer`(CCMenuOnScrollView +
	#   `makeMagneticDummy` 드래그 재정렬 + `dragon_select_deco`)로 따로 있고 형태가 다르다.
	#   그쪽 이식은 별건 — 지금은 **같은 일을 하는 원작 유래 위젯**(`PartySelect`)을 쓴다.
	var seed_party: Array = []
	for u in UserDB.party():
		if Colosseum.eligible(int(u)):
			seed_party.append(int(u))
	for u in ok:
		if seed_party.size() >= n:
			break
		if not seed_party.has(int(u)):
			seed_party.append(int(u))
	PartySelect.open_run(self, seed_party.slice(0, n), func(picked: Array) -> void:
		if picked.is_empty():
			return
		if not Colosseum.spend_ticket():
			_notice(String(Data.colosseum.get("log", {}).get("no_stamina",
				"피로도가 부족하여 전투에 참여가 불가능합니다.")))
			return
		# 서버 랜덤 매칭 대체 — 여기서 상대가 정해진다.
		var foe := Colosseum.roll_match(mode, _rng)
		Colosseum.consume_guard()
		Scenes.goto("fight", {"mode": mode, "opponent": foe, "party": picked.slice(0, n)}))


# ---------- 우측 열(프로필 · 입장권 · 모드 진입) ----------

func _build_right_column(vis: Vector2) -> void:
	var x := vis.x - RIGHT_COL + PANEL_LEFT
	var col := Control.new()
	col.position = Vector2(x, 0.0)
	col.size = Vector2(RIGHT_COL - PANEL_LEFT, vis.y)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 시작 버튼 클릭을 가로채지 않게
	add_child(col)

	var s := Colosseum.refresh_ticket()
	var rating := Colosseum.rating_of(_board_mode)
	var streak := Colosseum.streak_of(_board_mode)

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

	col.add_child(_center_label("%d위  ·  %d연승 (최고 %d)" % [
		Colosseum.my_rank(_board_mode, _weekly), streak, int(s.get(
		"straight_single_best" if _board_mode == "single" else "straight_team_best", 0))],
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

	# 나가기 — 원작은 제목바의 `onClickedX`(`TitleLayer` 닫기 버튼).
	# 우리 제목바는 패널 장식이라 닫기 자리가 없어 우측 열 맨 아래(시작 버튼 위)에 둔다.
	var bw := cw - 40.0
	AtlasUI.frame_button(col, "나가기",
		Vector2(20.0, vis.y - BTN_MENU_H * 2.0 - BTN_BOTTOM - BTN_GAP - 54.0),
		Vector2(bw, 42.0),
		func() -> void: Scenes.goto("worldmap", {"from": "colosseum"}))


# ---------- BMFont(원작 getFontName_subtitle) ----------

var _bmfonts := {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f


func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
