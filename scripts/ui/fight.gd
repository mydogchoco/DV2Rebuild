extends Control
## 콜로세움 대전 씬 — 원작 `FightScene` + `MakeInterface::ColosseumFightInitWidget` 이식.
## render 층(§8). 🟦 사용자 확정 2026-08-04(솔로 재설계).
##
## ## 왜 battle.gd 가 아니라 새 파일인가
## 우리 `scripts/ui/battle.gd` 는 `AdventureScene` 계열 = **파티 카드 vs 중앙 몬스터 1마리**다.
## 콜로세움은 **양쪽 다 드래곤 스파인**이고 상단 UI(프로필·티어·연승)도 다르다.
## 원작도 `BattleScene`(탐험)과 `FightScene`(콜로세움)이 **별개 클래스**다 → 우리도 나눈다.
## 공유하는 것은 **로직층뿐**: `Battle.simulate(party_a, party_b, …)`.
##
## ## 원작이 서버에서 받던 것 → 우리가 채우는 것
## `FightScene::setActionParam` @00f8c93c(7,676B)은 `FightManager::getActor()` /
## `getActorAction()` / `getActorSkillNumber()` 를 읽어 **연출만 재생**하는 리플레이 플레이어다.
## 그 큐를 서버가 채웠다 → 우리는 `Battle.simulate()` 의 이벤트 배열로 채운다.
## 이게 이번 이식의 **유일한 배선 교체 지점**이다(docs/ref/porting/Colosseum.md §0·§2).
##
## ## 자산
## 보유: `scene/colosseum/{vs, vs_bg, mini_vs, profilebox, stage_0~7.jpg,
##   popup_win_kr, popup_win_bg_kr, popup_lose_kr, popup_lose_bg_kr, tag_win_kr, tag_lose_kr}`
##   · `common/tier_icon_*`(5티어) · `9patch/{bar1~4, bar_bg1~2, dialogue_box}`
## 미보유(§10 판본 불일치): `new9patch/du_*` `newCommon/{du_frame_dragon_02, tm_point}`
##   — 전부 **Dual(방어덱) 분기**라 우리가 컷한 모드의 프레임이다. 콜로세움 분기는 전부 보유.
## ⚪ 미변환: `scene/colosseum/fight_spine`(VS 연출 스파인) — spine_export 미실행.
##   지금은 보유 프레임 `vs` + `vs_bg` 로 낸다. 변환하면 `_vs_intro()` 한 곳만 교체.

const CO := "colosseum_ui"
const NP := "ninepatch_ui"
const CM := "common_ui"
const BG_DIR := "res://assets/converted/colosseum_bg"

# 원작 3v3 배치 — **화면 비율이 아니라 좌·우 바닥 모서리 기준 절대 오프셋**이다.
#
# 🔴 2026-08-04 정정(사용자 지적 "원작 로직을 그대로 계승하지 않았다") — 종전 비율 배치는 자작이었다.
# 근거: `FightScene::init` @00f88fac 이 슬롯 태그로 위치를 잡는다 —
#   내 팀 = 태그 11·13·15 (`iVar3 = 0xb`, +2), 상대 = 태그 10·12·14 (`iVar3 = 10`, +2).
#   위치는 `FUN_00f8ad70(layer, sceneType)` 가 태그로 분기해 준다(probe/fight_slot_probe.c):
#     tag 11 → `FUN_00f8f65c`  = leftBottom  + (335, 262.5)
#     tag 13 →                   leftBottom  + (200, 350)
#     tag 15 →                   leftBottom  + (135, 175)
#     tag 10 → `FUN_00f8f738`  = rightBottom + (-335, 262.5)
#     tag 12 →                   rightBottom + (-200, 350)
#     tag 14 →                   rightBottom + (-135, 175)
#   (probe/fight_slot0_probe.c — 콜로세움 씬 타입은 `0xbf2` 마스크에 드는 분기다.)
# Cocos y 는 바닥 기준이라 Godot 은 `visH - y` 로 뒤집는다(§Design).
#
# 스케일도 원작대로 — `makeDragonLayer` @0105072c 끝: **3v3 = 0.75, 1v1 = 1.0**.
# 뒤집기도 원작대로 — 같은 함수의 `1 << tag & 0xa800`(= 태그 11·13·15) 만 flipX 한다 = **내 팀**.
const SLOT_OFF := [Vector2(335.0, 262.5), Vector2(200.0, 350.0), Vector2(135.0, 175.0)]
const DRAGON_SCALE_TEAM := 0.75     # 원작 makeDragonLayer: type 3(3v3)
const DRAGON_SCALE_SOLO := 1.0      # 원작 makeDragonLayer: type 1(1v1)
# ⚠️ 드래곤 스파인의 **기본 방향은 왼쪽**이다(실측 2026-08-04 — 처음엔 반대로 알고
#   상대만 뒤집었더니 우리 팀이 등을 보였다). 그래서 **왼쪽에 서는 내 팀**을 뒤집는다.
# `PartySelect._spine_node` 는 **holder 원점 = 스프라이트 바닥 중앙**으로 맞춘다
# (party_select.gd:115 `inst.position -= …`). 그래서 바는 원점 바로 아래에 둔다.
const BAR_DY := 12.0
const BAR_W := 168.0
const BAR_H := 16.0

var _pma: CanvasItemMaterial
var _params: Dictionary = {}
var _mans: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _mode := "team"
var _foe: Dictionary = {}
var _my: Array = []          # PartyStats.summary_of 결과
var _fo: Array = []
var _views: Dictionary = {}  # 내부이름(A0/E0) → {node, bar, hp, hp_max, dead}
var _events: Array = []
var _winner := ""
var _gen := 0
var _log: Label


func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()


func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	Bgm.play("bg_colosseum_battle_2")   # 원작 콜로세움 전투 BGM(실재)
	_rebuild()


func _rebuild() -> void:
	_gen += 1
	for c in get_children():
		c.queue_free()
	_views.clear()
	_log_lines.clear()
	_skipped = false
	_folded = true
	_speed = 1

	_mode = String(_params.get("mode", "team"))
	_foe = _params.get("opponent", {})
	var uids: Array = _params.get("party", [])
	if uids.is_empty():
		uids = UserDB.party()
	var n := Colosseum.party_size(_mode)

	# 양 팀 스탯 — **같은 함수**로 만든다(봇 전용 계산 없음, §Colosseum 설계).
	_my = PartyStats.summary(uids.slice(0, n), false, "")
	_fo = PartyStats.summary_of((_foe.get("dragons", []) as Array).slice(0, n), false, "")

	var vis := _vis()
	_build_bg(vis)
	_build_team(_my, true, vis)
	_build_team(_fo, false, vis)
	_build_top(vis)
	_build_log(vis)
	_start()


# ---------- 배경 ----------

func _build_bg(vis: Vector2) -> void:
	# 원작은 대전마다 stage_N 을 고른다. 시드가 고정되면 같은 무대가 나온다.
	var n := _rng.randi() % 8
	var p := "%s/stage_%d.jpg" % [BG_DIR, n]
	if not ResourceLoader.exists(p):
		p = "%s/stage_3.jpg" % BG_DIR
	if not ResourceLoader.exists(p):
		return
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.size = vis
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(tr)


# ---------- 팀 배치 ----------

func _build_team(team: Array, mine: bool, vis: Vector2) -> void:
	for i in team.size():
		var p: Dictionary = team[i]
		var tag := ("A%d" if mine else "E%d") % i
		var off: Vector2 = SLOT_OFF[i % SLOT_OFF.size()]
		var x := off.x if mine else vis.x - off.x
		var y := vis.y - off.y                      # Cocos 바닥 기준 → Godot

		var holder := Node2D.new()
		holder.position = Vector2(x, y)
		add_child(holder)

		# ⚠️ **콜로세움은 항상 성체 스파인이다.**
		#   ① 원작 입장 조건이 레벨 25(=성체) 이상이라 애초에 유생이 못 들어온다
		#      (`ColosseumInError` "테이머 자격증 이벤트를 완수하셔야 입장할 수 있습니다. (레벨 25)").
		#   ② 실측(2026-08-04): 공격 모션은 **성체에만 있다** —
		#      adult 134/134 에 `attack` 존재, child 132/133 · baby 132/133 은 **없음**.
		#      종전엔 레벨 30 미만이면 child 를 띄워서, 저레벨 드래곤이 공격해도 아무 모션이
		#      없었다(사용자 지적).
		# 발밑 그림자 — 원작 `MakeInterface::setShadow` @01050b10 이
		#   `common/shadow.png` 를 드래곤 위치 −(0, s*95) 에 `setScale(s + 1.0)` 로 깐다
		#   (z=1, tag=-0x226). 우리 holder 원점 = 스프라이트 **바닥 중앙**이라 그 자리에 둔다.
		var sh := _spr(CM, "common_shadow", Design.ASSET_SCALE)
		if sh != null:
			sh.scale *= (DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO)
			sh.z_index = -1
			holder.add_child(sh)

		# 🔴 2026-08-05 — **정규화를 뺐다.** `PartySelect._spine_node(…, DRAGON_H)` 는 모든 종을
		#   같은 높이(170pt)로 눌러 담는 **우리 장치**다(편성 카드용). 원작 `makeDragonLayer` 는
		#   스파인을 **native 크기 그대로** 놓고 3v3=0.75 / 1v1=1.0 만 곱한다 ⇒ 종마다 크기가 다르다.
		#   실측(2026-08-05): 성체 native 높이 288~296pt → 3v3 이면 ~217pt.
		#   종전 값(170×0.75=127pt)은 레퍼런스(`docs/ref/pvp/`, 드래곤 210~250pt)의 절반이었다.
		var sp := _dragon_spine(int(p.get("id", 0)))
		var ap: AnimationPlayer = null
		if sp != null:
			# 원작 makeDragonLayer 의 최종 setScale — 3v3 은 0.75 로 줄인다.
			var ds := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
			sp.scale *= ds
			# 스파인 기본 방향이 왼쪽이므로 **왼쪽 진영(내 팀)** 을 뒤집어 마주 보게 한다
			# (원작도 태그 11·13·15 = 내 팀만 flipX 한다).
			if mine:
				sp.scale = Vector2(-absf(sp.scale.x), sp.scale.y)
			holder.add_child(sp)
			ap = _find_anim_player(sp)

		# HUD 는 드래곤 **머리 위**다 — 종마다 키가 다르므로 실측 높이를 넘긴다.
		var dh := DRAGON_H
		if sp != null:
			var rb := PartySelect._bounds(sp, Transform2D.IDENTITY)
			if rb.size.y > 1.0:
				dh = rb.size.y
		var hud := _make_hud(p, Vector2(x, y), dh)
		add_child(hud["root"])

		_views[tag] = {
			"node": holder, "bar": hud["fill"], "barh": hud["root"],
			# 🔴 HUD 의 라벨은 원작대로 낱말 "레벨" 이라 **이름 출처가 될 수 없다**
			#   (2026-08-05). 로그 문구용 표시 이름은 여기 따로 들고 있는다.
			"dname": String(p.get("name", "")), "icons": hud["icons"],
			"hp_label": hud["hp_label"], "anim": ap, "id": int(p.get("id", 0)),
			"element": String(p.get("element", "")),
			"hp": int(p.get("hp_max", 1)), "hp_max": maxi(1, int(p.get("hp_max", 1))),
			"dead": false, "pos": Vector2(x, y), "mine": mine, "slot": i,
		}


# ---------- 드래곤 HUD — 원작 `MakeInterface::setHUD` @01050ffc 이식 ----------
#
# 종전엔 다른 화면 프레임(`9patch/bar_bg2` + `bar1/bar3`)으로 자작 바를 그렸다.
# 콜로세움 전용 프레임이 **네 장 다 있다**(사용자 지적 2026-08-04로 재조회):
#   `scene/colosseum/bar_cover_bg`(118×19) · `bar_cover`(156×29) · `bar_bg`(119×17) · `bar`(119×17)
#
# 원작 조립 순서(그대로 옮긴다):
#   layer = 드래곤 노드. **HUD 는 그 위 100pt**(pos = 레이어중심 + (0, h*0.5 + 100)).
#   ① `bar_cover_bg`  addChild(z=7,  tag=5)
#   ② `bar_cover`     같은 위치, addChild(z=10, tag=6)
#        └ 속성 아이콘: pos(17.5, 19.75), setScale(28.5 / 아이콘폭), addChild(z=0)
#   ③ `bar_bg`        anchor(0, 0.5), pos = cover + (15 - w*0.5, 1), addChild(z=8, tag=4)
#   ④ `bar`(채움)     anchor(0, 0.5), pos = bar_bg.pos,             addChild(z=9, tag=3)
#   ⑤ 이름 BMFont(subtitle) anchor(0,0) scale 0.5, pos = cover + (-coverW*0.5, coverH*0.5)
#   ⑥ 레벨 BMFont(subtitle) anchor(0.65,0.85), pos = 이름.pos + (이름폭, coverH*0.5)
#   ⑦ "현재 / 최대" BMFont(subtitle) scale 0.75, pos = cover + (17.5, 1.5)
#   등장 = DelayTime(d) → Show → ScaleTo(0.05, 1.1) → ScaleTo(0.05, 1.0)
#   라벨만 DelayTime(d) → DelayTime(0.25) → FadeTo(0.5, 255)

const DRAGON_H := 170.0             # `_spine_node` 정규화 높이
const HUD_LIFT := 18.0              # 원작은 100(원작 레이어 크기 기준) — 위 주석 참조
const HUD_TOP_MIN := 155.0          # 상단 프로필 판 아래로만 — 아래 ⚠️
const HUD_ELEM_POS := Vector2(17.5, 19.75)
const HUD_ELEM_W := 28.5

func _make_hud(p: Dictionary, at: Vector2, dragon_h := DRAGON_H) -> Dictionary:
	var S := Design.ASSET_SCALE
	var root := Node2D.new()
	# 원작 pos = 레이어중심 + (0, h*0.5 + 100) = **레이어 꼭대기에서 100pt 위**.
	# ⚠️ 그 100 은 원작 드래곤 레이어 크기 기준이라 우리 정규화 높이(170)에 그대로 쓰면
	#   HUD 가 위 슬롯까지 올라간다. 구조·프레임·내부 오프셋은 원작 그대로 두고
	#   **머리 위 여백만** 우리 배치에 맞춘다(= 레이어 꼭대기 + HUD_LIFT).
	# `PartySelect._spine_node` 규약상 holder 원점 = 스프라이트 **바닥 중앙**이다.
	# ⚠️ 위 클램프는 원작에 없다 — 우리 사정이다. 원작 드래곤 레이어는 화면 위쪽 여백을 알고
	#   배치됐지만, 우리는 스파인을 native 크기로 놓기 시작하면서(2026-08-05) 앞줄 드래곤의
	#   HUD 가 상단 프로필 판(높이 ~103pt) 밑으로 파고들었다. 판 아래로만 밀어 준다.
	#   # ASSUMPTION: 원작이 이 충돌을 어떻게 피했는지(레이어 크기? 슬롯 y?)는 미확인.
	root.position = at + Vector2(0.0, -(dragon_h + HUD_LIFT))
	root.position.y = maxf(root.position.y, HUD_TOP_MIN)

	var cover_bg := _spr(CO, "scene_colosseum_bar_cover_bg", S)
	if cover_bg != null:
		root.add_child(cover_bg)                       # z=7
	var cover := _spr(CO, "scene_colosseum_bar_cover", S)
	if cover != null:
		root.add_child(cover)                          # z=10
	var cover_w := 156.0 * S
	var cover_h := 29.0 * S

	# 속성 아이콘 — 원작 `FightDragon::getElementSprite()`.
	#   `element->setPosition(17.5, 19.75)` · `setScale(28.5 / contentSize.width)`
	# ⚠️ §9 규칙 2 — 원작 좌표·크기 리터럴은 **이미 포인트**다. ASSET_SCALE 을 다시 곱하지 않는다.
	#   Cocos 자식 좌표 원점 = 부모의 **좌하단** → cover 중심 기준으로 환산해 넣는다.
	var es := _element_sprite(String(p.get("element", "")))
	if es != null and cover != null:
		es.position = Vector2(HUD_ELEM_POS.x - cover_w * 0.5,
			cover_h * 0.5 - HUD_ELEM_POS.y)
		var iw := float(es.texture.get_width())
		if iw > 0.0:
			es.scale = Vector2.ONE * (HUD_ELEM_W / iw)   # 화면에 28.5pt 폭으로
		cover.add_child(es)

	# 게이지 — 원작 `bar_bg` anchor(0, 0.5), pos = cover + (15 - w*0.5, 1). `bar` 는 같은 자리.
	var bar_w := 119.0 * S
	var bar_h := 17.0 * S
	var bar_left := Vector2(15.0 - bar_w * 0.5, -1.0 - bar_h * 0.5)
	var bg := _spr(CO, "scene_colosseum_bar_bg", S)
	if bg != null:
		bg.centered = false
		bg.position = bar_left
		root.add_child(bg)                             # 원작 z=8, tag=4
	var fill := _spr(CO, "scene_colosseum_bar", S)
	if fill != null:
		fill.centered = false
		fill.position = bar_left
		fill.region_enabled = true
		fill.region_rect = Rect2(0, 0, 119, 17)
		root.add_child(fill)                           # 원작 z=9, tag=3

	# ⑤ — 🔴 2026-08-05 정정: **여기 들어가는 건 드래곤 이름이 아니라 낱말 "레벨"** 이다.
	#   원작은 `StringManager::getString(...)` 결과를 BMFont 로 찍는데, 그 키가
	#   `<ColosseumLevel>레벨</ColosseumLevel>`(stringsData_KR.xml)이고 곧바로 ⑥ 에서
	#   `FightDragon::getLevel()` 을 "%d" 로 붙인다 — 레퍼런스 스크린샷(`docs/ref/pvp/`)의
	#   "레벨 35" 가 그것이다. 종전엔 드래곤 이름을 찍어 원작에 없는 정보를 내고 있었다.
	#   cover 좌상단, anchor(0,0).
	var nm := Label.new()
	nm.text = String(Data.colosseum.get("log", {}).get("level", "레벨"))
	nm.position = Vector2(-cover_w * 0.5, -cover_h * 0.5 - 21.0)
	_bm_style(nm, 16, Color.WHITE)
	root.add_child(nm)

	# ⑥ 레벨 숫자 — 원작 anchor(0.65,0.85), 이름 오른쪽. 폭을 런타임에 못 재므로 낱말 폭만큼
	#   띄운다(같은 줄·이름 바로 오른쪽이라는 성질은 같다).
	var lv := Label.new()
	lv.text = "%d" % int(p.get("level", 1))
	lv.size = Vector2(cover_w, 22.0)
	lv.position = Vector2(-cover_w * 0.5 + 42.0, -cover_h * 0.5 - 24.0)
	_bm_style(lv, 21, Color.WHITE)
	root.add_child(lv)

	# 상태이상 아이콘 줄 — 원작 `createIcon` 이 드래곤 레이어에 태그로 붙인다(아래 §상태이상).
	# 레퍼런스에서는 "레벨" 줄 **위** 왼쪽부터 오른쪽으로 늘어선다.
	# 아이콘 중심 기준이므로 반 칸(≈21pt) 만큼 안쪽으로 들여 "레벨" 줄 **위**에 얹는다.
	var icons := Node2D.new()
	icons.position = Vector2(-cover_w * 0.5 + 22.0, -cover_h * 0.5 - 48.0)
	root.add_child(icons)

	# "현재 / 최대" — 원작 pos = cover + (17.5, 1.5), scale 0.75, anchor 중앙.
	var hp := Label.new()
	var hpm := maxi(1, int(p.get("hp_max", 1)))
	hp.text = "%d / %d" % [hpm, hpm]
	hp.size = Vector2(bar_w, 18.0)
	hp.position = Vector2(17.5 - bar_w * 0.5, -1.5 - 9.0)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bm_style(hp, 13, Color.WHITE)
	root.add_child(hp)

	return {"root": root, "fill": fill, "hp_label": hp, "name_label": nm, "icons": icons}


## 속성 아이콘 — 원작 `FightDragon::getElementSprite()`.
## 프레임은 `battle/element_%s_mark.png`(cave.gd 가 이미 쓰는 원본 세트와 같은 것).
func _element_sprite(element: String) -> Sprite2D:
	if element == "":
		return null
	return _spr("battle_ui", "battle_element_%s_mark" % element, 1.0)


## 원작 BMFont(`GameManager::getFontName_subtitle`).
var _bmfonts := {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var path := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(path):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(path).duplicate()
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


# ---------- 상단 정보 — 원작 `MakeInterface::ColosseumFightInitWidget` @010519b0 ----------
#
# 🔴 2026-08-05 재이식(사용자 레퍼런스 `docs/ref/pvp/*.png` 대조). 종전엔 `profilebox` 를
#   9patch 로 **330×80 으로 늘려** 놓고 "닉네임\n점수" 를 한 줄 라벨로 찍었다 — 원작은
#   9patch 가 아니라 **스프라이트 원본 크기 그대로**이고, 안에 초상·티어·칭호·닉네임이 들어간다.
#
# 원작 조립(리터럴·좌표 그대로. §9 규칙 2 — 이 수치들은 이미 포인트다):
#   ① `scene/colosseum/profilebox.png`(338×77) 스프라이트, anchor(0,1)
#      pos = leftTop − (20, 0)  / 반대편은 rightTop 기준 대칭. z=15
#      등장 = MoveBy(0,+h) → Delay(3.85) → MoveBy(0.1,−h) → MoveBy(0.05,+10) → MoveBy(0.05,−10)
#   ② `common/box1.png`(50×50) = 초상 받침.
#      pos = (box1.w·0.5 + 35, plateH − box1.h·0.5 − 7.5)
#      └ 등급 테두리 `common/dragon_frame_<tier>.png`(FightManager::getScrambleBorderName) 를
#        받침 중앙에, 그 위에 초상(`getUserProfileImagePath`)을 받침에 맞춰 축소해 얹는다.
#   ③ 랭크 아이콘  pos = box1.pos + (box1.w + 5, 0), 폭이 60 을 넘으면 60/w 로 축소
#   ④ 닉네임 `CCLabelTTF(nick, "Thonburi", 20)` anchor(0,1) pos(195, 62)
#   ⑤ 칭호 이미지(`getUserTitleImagePath`) anchor(0,0) pos(195, 62), 폭 220 초과 시 축소
#   ⑥ 가운데 `scene/colosseum/vs_bg.png` + `vs.png`
#
# ⚠️ ③의 프레임은 원작에서 **서버가 준 경로**(`FightManager::getUserRankImagePath` 는 멤버
#   문자열을 그대로 돌려주는 게터다) — 레퍼런스의 ◇◇ / ★★ 이 그 자리다. 그 아트는 유실이라
#   같은 슬롯의 다른 분기(랭크시드전)가 쓰는 **`common/tier_icon_<tier>.png` 5종**을 쓴다.
#   우리 티어 사다리와 같은 축이라 의미도 맞는다(§Colosseum 티어 = 5단).
const PLATE_EDGE := 20.0            # 원작 leftTop − (20, 0)
const PLATE_AVATAR_X := 35.0
const PLATE_AVATAR_DY := 7.5
const PLATE_RANK_GAP := 5.0
const PLATE_RANK_MAX := 60.0
const PLATE_TEXT := Vector2(195.0, 62.0)
const PLATE_TITLE_MAX := 220.0
const PLATE_DROP_DELAY := 3.85      # 원작 CCDelayTime(0x40766666)

func _build_top(vis: Vector2) -> void:
	_side_plate(true, UserDB.user_nickname(), Colosseum.rating_of(_mode), vis)
	_side_plate(false, String(_foe.get("nick", "")), int(_foe.get("rating", 0)), vis)

	# 상단 가운데 VS 표식 — 원작이 부르는 건 `vs_bg`(101×90) + `vs`(79×68) 두 장이다.
	# 종전엔 `mini_vs`(30×18)를 얹어 좁쌀만 하게 나왔다(레퍼런스 대조).
	var cx := vis.x * 0.5
	var vb := _spr(CO, "scene_colosseum_vs_bg", Design.ASSET_SCALE)
	if vb != null:
		vb.position = Vector2(cx, 56.0)
		add_child(vb)
	var v := _spr(CO, "scene_colosseum_vs", Design.ASSET_SCALE)
	if v != null:
		v.position = Vector2(cx, 56.0)
		add_child(v)


## 대전 개시 연출 — 원작 `scene/colosseum/fight_spine`("FIGHT!").
##
## ⚠️ **2026-08-04 미해결**: `build_colosseum_fx.py` + `build_spine_scene.gd` 로 변환·씬 빌드는
##   끝났고(`scenes/fx/colosseum_fight.tscn`, 12본/8슬롯/anim=animation) 파일도 생기는데,
##   화면에 **아무것도 안 그려진다**(헤드리스 스크린샷 확인). 원인 미규명 —
##   슬롯 초기 가시성/스케일/앵커 중 하나로 보이나 근거 없이 만지지 않는다.
##   ⇒ 그때까지는 **보유 프레임 `vs`** 로 낸다(원작 아트다. 자작 도형이 아니다).
##   고치면 `USE_SPINE` 만 true 로 돌리면 된다.
##
## ✅ 2026-08-04 — "인트로가 중앙이 아니라 상단에 뜬다"던 종전 메모는 **내 오독이었다.**
##   실측: vis=(1230,692) · 스프라이트 pos=(615,346) = 정확히 중앙.
##   상단의 큰 흰 형체는 `_build_top` 이 상시로 까는 `vs_bg` 였다(무대 배경의 광선과도 겹쳤다).
const FIGHT_SPINE := "res://scenes/fx/colosseum_fight.tscn"
const USE_SPINE := false

func _vs_intro() -> void:
	var vis := _vis()
	if USE_SPINE and ResourceLoader.exists(FIGHT_SPINE):
		var holder := Node2D.new()
		holder.z_index = 100
		holder.position = vis * 0.5
		add_child(holder)
		var inst = (load(FIGHT_SPINE) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
			ap.play("animation")
		var tw := holder.create_tween()
		tw.tween_interval(1.4)
		tw.tween_property(holder, "modulate:a", 0.0, 0.3)
		tw.tween_callback(holder.queue_free)
		return
	var v := _spr(CO, "scene_colosseum_vs", Design.ASSET_SCALE * 1.6)
	if v != null:
		v.z_index = 100
		v.position = vis * 0.5
		add_child(v)
		var tw2 := create_tween()
		tw2.tween_interval(1.2)
		tw2.tween_property(v, "modulate:a", 0.0, 0.3)
		tw2.tween_callback(v.queue_free)


## 한쪽 진영의 프로필 판. `mine` = 왼쪽(내 쪽) / false = 오른쪽(상대) 대칭 배치.
##
## 판 안의 좌표는 **원작 그대로 cocos(좌하단 원점)** 로 적고 마지막에만 y 를 뒤집는다.
## 오른쪽 판은 x 를 판 폭 기준으로 되접는다(원작도 rightTop 기준 대칭이다).
func _side_plate(mine: bool, nick: String, rating: int, vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var pw := 338.0 * S
	var ph := 77.0 * S
	var plate := Node2D.new()
	plate.position = Vector2(-PLATE_EDGE if mine else vis.x + PLATE_EDGE - pw, 0.0)
	add_child(plate)

	# 오른쪽 판은 **좌우 반전**이다 — 원작도 rightTop 기준 대칭이고, 레퍼런스에서 상대 쪽은
	# 초상이 바깥(오른쪽)·글자 칸이 안쪽이다. 뒤집지 않으면 글자가 판 밖으로 밀린다.
	var bg := _spr(CO, "scene_colosseum_profilebox", S)
	if bg != null:
		bg.centered = false
		if not mine:
			bg.scale.x = -bg.scale.x
			bg.position.x = pw
		plate.add_child(bg)

	# 판 안의 한 점(cocos 좌하단 원점, 포인트) → plate 로컬 Godot 좌표.
	var P := func(x: float, y: float) -> Vector2:
		return Vector2(x if mine else pw - x, ph - y)

	# ② 초상 받침 + 등급 테두리 + 초상
	var bw := 50.0 * S
	var av: Vector2 = P.call(bw * 0.5 + PLATE_AVATAR_X, ph - bw * 0.5 - PLATE_AVATAR_DY)
	var box := _spr(CM, "common_box1", S)
	if box != null:
		box.position = av
		plate.add_child(box)
	var por := _plate_portrait(mine)
	if por != null:
		# 원작: 받침에 들어가도록 가로/세로 비 중 작은 쪽으로 축소한다.
		var tw := maxf(1.0, float(por.texture.get_width()))
		var th := maxf(1.0, float(por.texture.get_height()))
		por.scale = Vector2.ONE * minf(bw / tw, bw / th)
		por.position = av
		plate.add_child(por)
	# 등급 테두리 = 원작 `getScrambleBorderName` → `common/dragon_frame_<tier>.png`.
	var bf := Colosseum.tier_frame(rating, "dragon")
	if bf != "":
		var bs := _spr(CM, _frame_key(bf), S)
		if bs != null:
			bs.position = av
			plate.add_child(bs)

	# ③ 랭크 아이콘(우리는 티어 아이콘 — 위 ⚠️)
	var tf := Colosseum.tier_frame(rating, "icon")
	if tf != "":
		var ts := _spr(CM, _frame_key(tf), S)
		if ts != null:
			var iw := float(ts.texture.get_width()) * S
			if iw > PLATE_RANK_MAX:
				ts.scale *= PLATE_RANK_MAX / iw
			ts.position = av + Vector2((bw + PLATE_RANK_GAP + iw * 0.5) * (1.0 if mine else -1.0),
				0.0)
			plate.add_child(ts)

	# ⑤ 칭호 이미지 — 원작 `getUserTitleImagePath`. 우리 칭호 아트는 `title_<no>_kr`.
	var anchor: Vector2 = P.call(PLATE_TEXT.x, PLATE_TEXT.y)
	var tno := UserDB.user_title_no() if mine else 0
	var tpath := "res://assets/converted/%s/title_%d_kr.tres" % [
		String(Data.titles.get("atlas_dir", "title_ui")), tno]
	if tno > 0 and ResourceLoader.exists(tpath):
		var tt: Texture2D = load(tpath)
		var tr := Sprite2D.new()
		tr.texture = tt
		tr.centered = false
		tr.material = _pma
		var tws := float(tt.get_width()) * S
		var tsc := S * (PLATE_TITLE_MAX / tws if tws > PLATE_TITLE_MAX else 1.0)
		tr.scale = Vector2(tsc, tsc)
		var thh := float(tt.get_height()) * tsc
		tr.position = Vector2(anchor.x if mine else anchor.x - float(tt.get_width()) * tsc,
			anchor.y - thh)
		plate.add_child(tr)

	# ④ 닉네임 — 원작 CCLabelTTF("Thonburi", 20). 한글이라 우리 TTF 로 낸다.
	var l := Label.new()
	l.text = nick
	l.size = Vector2(pw - PLATE_TEXT.x - 24.0, 28.0)
	l.position = Vector2(anchor.x if mine else anchor.x - l.size.x, anchor.y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if mine else HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(l)

	# 등장 — 원작 MoveBy(0,+h) → Delay(3.85) → MoveBy(0.1,−h) → MoveBy(0.05,+10) → (0.05,−10).
	# Cocos +y 는 위, Godot 은 아래이므로 부호를 뒤집는다.
	var home := plate.position
	plate.position = home - Vector2(0.0, ph)
	var tw2 := plate.create_tween()
	tw2.tween_interval(PLATE_DROP_DELAY)
	tw2.tween_property(plate, "position", home, 0.1)
	tw2.tween_property(plate, "position", home - Vector2(0.0, 10.0), 0.05)
	tw2.tween_property(plate, "position", home, 0.05)


## `Colosseum.tier_frame` 는 원작 경로("common/tier_icon_gold.png")를 돌려준다 → 매니페스트 키로.
func _frame_key(path: String) -> String:
	return path.replace("/", "_").replace(".png", "")


## 프로필 초상 — 원작 `getUserProfileImagePath`(유저가 지정한 사진/드래곤).
## 우리는 메인 HUD 와 같은 규약을 쓴다: 내 쪽 = 활성 드래곤, 상대 = 선두 드래곤.
func _plate_portrait(mine: bool) -> Sprite2D:
	var did := 0
	if mine:
		var a := UserDB.active_dragon()
		did = int(a.get("id", 0))
	elif not _fo.is_empty():
		did = int((_fo[0] as Dictionary).get("id", 0))
	if did <= 0:
		return null
	var dir := "portrait_%d" % did
	var man := _man(dir)
	for stage in ["evolution", "adult"]:
		var k := "dragon_dragon_%d_box_%s" % [did, stage]
		if man.has(k):
			return _spr(dir, k, 1.0)
	return null


# ---------- 하단 로그 — 원작 `ColosseumTextBox::init` @010327c0 이식 ----------
#
# 🔴 2026-08-05 재이식(레퍼런스 `docs/ref/pvp/*.png` 대조). 종전엔 높이 66 짜리 상자에
#   한 줄 라벨만 있었고 **배속·SKIP·접기 버튼이 통째로 빠져 있었다**.
#
# 원작 조립(리터럴·좌표 그대로):
#   레이어 anchor(0.5,0), pos = VisibleRect::bottom + (0, 10)
#   ① `9patch/dialogue_box.png` 스케일9, contentSize = (visW − 20, 90)
#   ② `common/btn_up.png` 접기/펼치기 — pos = (boxW − 50, boxH·0.5)
#      (`foldTextBox`/`spreadTextBox` 가 짝. 우리는 줄 수만 바꾼다)
#   ③ SKIP `scene/adventure/bt_skip_%s.png` — pos = boxSize + (−skipW·0.5, 30) = 상자 위 오른쪽
#   ④ 배속 `scene/colosseum/btn_forward.png` — pos = (btnW·0.5, boxH + 30) = 상자 위 왼쪽
#      └ `CCString("x%d", getFightTimeScale())` BMFont(subtitle) at 버튼중심 + (−15, 12.5), scale 1.25
#   ⑤ 본문 CCScrollView size = (boxW − 125, boxH − 22.5) at (25, 20)
#   등장 = Delay(param) → Delay(0.6) → 메뉴 켜기
const LOG_H := 90.0
const LOG_MARGIN := 20.0
const LOG_BOTTOM := 10.0
const LOG_BTN_LIFT := 30.0
const LOG_FOLD_INSET := 50.0
const LOG_TEXT_PAD := Vector2(25.0, 20.0)
const LOG_TEXT_TRIM := Vector2(125.0, 22.5)
const SPEEDS := [1, 2, 3]           # 원작 FightManager::getFightTimeScale
const LOG_LINES := 2                # 접힌 상태(레퍼런스 2줄) ↔ 펼치면 더 보인다

var _log_host: Control
var _log_box: NinePatchRect
var _log_lines: Array[String] = []
var _speed_label: Label
var _speed := 1
var _folded := true
var _skipped := false

func _build_log(vis: Vector2) -> void:
	var bw := vis.x - LOG_MARGIN
	var host := Control.new()
	host.position = Vector2(LOG_MARGIN * 0.5, vis.y - LOG_BOTTOM - LOG_H)
	host.size = Vector2(bw, LOG_H)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	_log_host = host

	_log_box = _nine("9patch_dialogue_box", host.size, Rect2(10, 10, 4, 4))
	if _log_box != null:
		host.add_child(_log_box)

	_log = Label.new()
	_log.position = LOG_TEXT_PAD
	_log.size = host.size - LOG_TEXT_TRIM
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_theme_font_size_override("font_size", 19)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_log)

	# ② 접기/펼치기 ▲
	var up := _btn(CM, "common_btn_up", host,
		Vector2(bw - LOG_FOLD_INSET, LOG_H * 0.5), _toggle_fold)
	if up != null:
		up.rotation = 0.0

	# ③ SKIP — 남은 이벤트를 즉시 소화하고 결과로 간다(원작 onClickSkipBattle 과 같은 역할).
	var sk: Dictionary = _man("adventure_ui").get("scene_adventure_bt_skip_kr", {})
	var skw := float(sk.get("w", 71)) * Design.ASSET_SCALE
	_btn("adventure_ui", "scene_adventure_bt_skip_kr", host,
		Vector2(bw - skw * 0.5, -LOG_BTN_LIFT), _on_skip)

	# ④ 배속
	var fw := float((_man(CO).get("scene_colosseum_btn_forward", {}) as Dictionary).get("w", 81))
	var fwp := fw * Design.ASSET_SCALE
	var fb := _btn(CO, "scene_colosseum_btn_forward", host,
		Vector2(fwp * 0.5, -LOG_BTN_LIFT), _cycle_speed)
	_speed_label = Label.new()
	_speed_label.text = "x%d" % _speed
	_speed_label.size = Vector2(60.0, 24.0)
	# 원작 라벨 offset (−15, +12.5) — cocos y-up 이라 Godot 은 위로 12.5.
	_speed_label.position = Vector2(fwp * 0.5 - 15.0 - 30.0, -LOG_BTN_LIFT - 12.5 - 12.0)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(_speed_label, 17, Color(0.25, 0.2, 0.15))
	_speed_label.scale = Vector2.ONE * 1.25           # 원작 setScale(1.25)
	if fb != null:
		host.add_child(_speed_label)


## 상자 위/안의 원작 버튼 하나. 프레임 원본 크기 그대로 쓰고 클릭만 우리가 붙인다.
func _btn(dir: String, key: String, host: Control, at: Vector2, cb: Callable) -> TextureButton:
	var t := _tex(dir, key)
	if t == null:
		return null
	var b := TextureButton.new()
	b.texture_normal = t
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(t.get_width(), t.get_height()) * Design.ASSET_SCALE
	b.position = at - b.size * 0.5
	b.material = _pma
	b.pressed.connect(cb)
	host.add_child(b)
	return b


func _toggle_fold() -> void:
	# 원작 `foldTextBox`/`spreadTextBox` — 접힘(2줄) ↔ 펼침(상자를 키워 더 많이 보여 준다).
	_folded = not _folded
	var vis := _vis()
	var h := LOG_H if _folded else LOG_H * 2.2
	_log_host.position.y = vis.y - LOG_BOTTOM - h
	_log_host.size.y = h
	if _log_box != null:
		_log_box.size.y = h
	if _log != null:
		_log.size.y = h - LOG_TEXT_TRIM.y
	_render_log()


func _cycle_speed() -> void:
	_speed = SPEEDS[(SPEEDS.find(_speed) + 1) % SPEEDS.size()]
	if _speed_label != null:
		_speed_label.text = "x%d" % _speed


func _on_skip() -> void:
	_skipped = true


func _say(t: String) -> void:
	_log_lines.append(t)
	if _log_lines.size() > 12:
		_log_lines = _log_lines.slice(_log_lines.size() - 12)
	_render_log()


func _render_log() -> void:
	if _log == null:
		return
	var n := LOG_LINES if _folded else 6
	var take: Array = _log_lines.slice(maxi(0, _log_lines.size() - n))
	_log.text = "\n".join(PackedStringArray(take))


# ---------- 전투 재생 ----------
#
# 원작 `FightScene::setActionParam` 이 서버 액션 큐를 훑던 자리.
# 우리는 `Battle.simulate()` 이벤트 배열을 같은 방식으로 훑는다.

func _start() -> void:
	var cfg := _json("res://data/combat.json")
	var skills := _json("res://data/skills.json")
	var pa := _combatants(_my, "ally")
	var pb := _combatants(_fo, "enemy")
	var res: Dictionary = Battle.simulate(pa, pb, _rng, cfg, skills)
	_events = res.get("events", [])
	_winner = String(res.get("winner", ""))
	_play()


func _combatants(team: Array, side: String) -> Array:
	var out: Array = []
	for i in team.size():
		var p: Dictionary = team[i]
		var c := Battle.make_combatant(("A%d" if side == "ally" else "E%d") % i,
			side, String(p.get("element", "")), p.get("stats", {}))
		out.append(c)
	return out


func _play() -> void:
	var gen := _gen
	# 연승방지봇(라온/누리/선대군)은 붙기 전에 **대사를 한다**.
	# 라온·누리 대사는 원작 그대로(ColosseumRaonTalk*/ColosseumNuriTalk*), 단계는 연승 스케줄이
	# 정한다(25 누리A · 50 라온A · 75 누리B · 100 라온B · 150 라온C). 선대군은 사용자 CSV.
	var lines: Array = _foe.get("lines", [])
	if not lines.is_empty():
		for ln in lines:
			if _skipped:
				break
			_say("%s: %s" % [String(_foe.get("nick", "")), String(ln).replace("\n", " ")])
			await _wait(1.9)
			if gen != _gen: return
	_say("%s 와(과)의 대전!" % String(_foe.get("nick", "")))
	_vs_intro()                 # 원작 fight_spine("FIGHT!") 개시 연출
	await _wait(1.8)
	if gen != _gen: return
	for ev in _events:
		# SKIP — 원작 `MakeInterface::onClickSkipBattle`. 남은 이벤트는 **결과만** 반영하고
		# 연출을 건너뛴다(로직 결과는 이미 정해져 있으므로 승패는 바뀌지 않는다).
		if _skipped:
			_apply_silent(ev)
			continue
		_apply(ev)
		# 원작 간격 = 애니 길이 + 0.5(복귀) + 0.5(다음까지). 애니 길이를 모르는 이벤트는 짧게.
		await _wait(_evt_delay(ev))
		if gen != _gen: return
	await _wait(0.5)
	if gen != _gen: return
	_finish()


## 이벤트 사이 간격 — 원작은 `Delay(getDuration(anim) + 0.5)` + `Delay(0.5)` 로 벌린다.
## 실제 애니 길이는 `_motion` 이 재생하며 알게 되므로 여기선 종류별 대표값을 쓴다.
func _evt_delay(ev: Dictionary) -> float:
	match String(ev.get("type", "")):
		"awaken":
			return 2.0                       # 각성기는 길다(ultimate1)
		"normal", "double":
			return 1.5 if bool(ev.get("crit", false)) else 1.15
		"dot", "effect_tick":
			return 0.35
	return 0.7


## 이벤트 1건을 화면에 반영 — HP 감소 · 데미지 숫자 · 사망 처리.
func _apply(ev: Dictionary) -> void:
	var t := String(ev.get("type", ""))
	# 🔴 2026-08-05 — `confused`/`status_skip` 은 **피격자 칸이 없고 `actor` 만** 있다.
	#   종전엔 여기서 곧장 return 해 버려 혼란·기절이 화면에 전혀 안 나왔다.
	var dfn := String(ev.get("defender", ev.get("target", "")))
	if dfn == "" and t in ["confused", "status_skip"]:
		dfn = String(ev.get("actor", ""))
	var dmg := int(ev.get("damage", 0))
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]
	_motion(ev, t, String(ev.get("attacker", "")), dfn)   # 스파인 공격/피격 모션
	if bool(ev.get("miss", false)):
		# 회피 워드아트는 `_evade_effect`(원작 evadeEffect)가 낸다 — 여기서 또 찍지 않는다.
		_log_line(ev, t, dfn, 0, 0)
		return
	if dmg > 0:
		v["hp"] = maxi(0, int(v["hp"]) - dmg)
		_set_bar(v)
		var col := Color(1.0, 0.85, 0.3) if bool(ev.get("crit", false)) else Color(1, 1, 1)
		_float_text(v["pos"], str(dmg), col)
	var heal := int(ev.get("heal", 0))
	if heal > 0:
		v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + heal)
		_set_bar(v)
		_float_text(v["pos"], "+%d" % heal, Color(0.5, 1.0, 0.5), true)
	if bool(ev.get("dead", false)) and not bool(v["dead"]):
		# 원작 사망 = `deadTypeNormalDamage` / `deadTypeBigDamage` 가 **"damaged" → "down"**
		# 두 단계로 낸다. `damaged` 가 여기(사망 도입부)에만 쓰이는 게 원작 사양이다.
		var d0 := _play_anim(v, "damaged")
		var gen0 := _gen
		get_tree().create_timer(maxf(0.15, d0)).timeout.connect(func() -> void:
			if gen0 == _gen:
				_play_anim(v, "down"))
		v["dead"] = true
		# 스파인만 지우면 **빈 HP 바와 이름표가 허공에 남는다**(2026-08-04 스크린샷에서 확인).
		# 셋을 함께 없앤다. down 을 볼 수 있게 조금 늦춘다.
		for k in ["node", "barh"]:
			var n = v.get(k)
			if n != null and is_instance_valid(n):
				# damaged → down 두 단계를 다 보여 준 뒤에 사라진다.
				var tw := create_tween()
				tw.tween_interval(1.4)
				tw.tween_property(n, "modulate:a", 0.0, 0.45)
	_log_line(ev, t, dfn, dmg, heal)


## SKIP 중 — 연출 없이 **상태만** 굴린다(HP·사망·로그). 원작 `onClickSkipBattle` 과 같은 자리.
func _apply_silent(ev: Dictionary) -> void:
	var dfn := String(ev.get("defender", ev.get("target", "")))
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]
	if not bool(ev.get("miss", false)):
		var dmg := int(ev.get("damage", 0))
		if dmg > 0:
			v["hp"] = maxi(0, int(v["hp"]) - dmg)
		var heal := int(ev.get("heal", 0))
		if heal > 0:
			v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + heal)
		_set_bar(v)
	if bool(ev.get("dead", false)) and not bool(v["dead"]):
		v["dead"] = true
		for k in ["node", "barh"]:
			var n = v.get(k)
			if n != null and is_instance_valid(n):
				(n as CanvasItem).modulate.a = 0.0


## 하단 로그 문구 — **원작 `ColosseumTextBox` 가 쓰던 문장 그대로**.
## 출처 = `DV2/string/stringsData_KR.xml`(사용자 지적 2026-08-04로 채굴). 유실이 아니었다.
## 종전엔 "스킬 발동!" 같은 자작 문구를 냈다.
func _log_line(ev: Dictionary, t: String, dfn: String, dmg: int, heal: int) -> void:
	var L: Dictionary = Data.colosseum.get("log", {})
	if L.is_empty():
		return
	var an := _who(String(ev.get("attacker", "")))
	var dn := _who(dfn)
	match t:
		"normal", "double":
			var kind := String(L.get("atk_critical", "")) if bool(ev.get("crit", false)) \
				else String(L.get("atk_double" if t == "double" else "atk_normal", ""))
			if bool(ev.get("miss", false)):
				_say(String(L.get("evade", "")) % [dn, an, kind])
			elif bool(ev.get("block", false)):
				_say(String(L.get("defend", "")) % [dn, an, kind, dmg])
			else:
				_say(String(L.get("attack", "")) % [an, dn, kind, dmg])
		"awaken":
			_say(String(L.get("ultimate", "")) % an)
		"skill":
			var sn := String(ev.get("skill_name", ""))
			if sn != "":
				_say(String(L.get("skill", "")) % [an, dn, sn])
		"dot":
			_say(String(L.get("poison", "")) % [dn, dmg])
	if heal > 0:
		_say(String(L.get("recover", "")) % [dn, heal])
	if bool(ev.get("dead", false)):
		_say(String(L.get("stun", "")) % dn)


## 내부 전투원 이름(A0/E0) → 화면에 낼 드래곤 이름.
func _who(tag: String) -> String:
	if tag == "" or not _views.has(tag):
		return ""
	return String((_views[tag] as Dictionary).get("dname", tag))


## HP 게이지 갱신 — 원작 `MakeInterface::decreaseHP`/`increaseHP` 와 같은 자리.
## 채움은 `bar.png` 를 **왼쪽부터 잘라** 보여 준다(원작도 anchor(0,0.5) 스프라이트다).
func _set_bar(v: Dictionary) -> void:
	var r := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var b = v.get("bar")
	if b is Sprite2D and is_instance_valid(b):
		var s := b as Sprite2D
		var t := s.texture
		if t != null:
			s.region_rect = Rect2(0, 0, float(t.get_width()) * r, t.get_height())
	var hl = v.get("hp_label")
	if hl is Label and is_instance_valid(hl):
		(hl as Label).text = "%d / %d" % [maxi(0, int(v["hp"])), int(v["hp_max"])]


# ---------- 스파인 안무(원작 FightScene / MakeInterface) ----------
#
# 🔴 2026-08-04 정정 (사용자 지적: "일반 피격엔 모션이 없었다") — **맞았다.**
#   종전엔 `FightScene::onClickDebug` 의 시퀀스를 안무로 읽었는데, 그건 애니를 차례로
#   돌려보는 **디버그 뷰어**다. 근거: 거기서 쓰는 `MakeInterface::runSpineWithAnimationName`
#   의 호출자가 전 디컴프에서 **onClickDebug 뿐**이다(다른 호출자 0건).
#
# 진짜 어휘는 `MakeInterface` 에서 전투 중 애니를 바꾸는 **세 곳뿐**이다
# (`translateSpineAnimationName` 호출 지점 전수):
#     makeDragonLayer        @0105072c → "wait"    (루프, 상시)
#     castSkill              @0108a924 → "attack"  → 끝나면 "wait"
#     deadTypeBigDamage      @…        → "damaged" → "down"
#     deadTypeNormalDamage   @…        → "damaged" → "down"
#   (패킹 문자열 디코드: 0x0c+"attack" · 0x7469617708="wait" ·
#    0x646567616d61640e="damaged" · 0x6e776f6408="down")
#
# ⇒ **일반 피격에는 애니가 없다.** `damaged` 는 피격 반응이 아니라 **사망 도입부**다.
#   `critical`/`ultimate1`/`ultimate2` 는 콜로세움 경로에서 트리거되지 않는다
#   (변환본엔 있지만 원작 PvP 가 안 쓴다 — 안 쓰는 게 원작 정합이다).
#
# 🔴 2026-08-05 — 안무 마스터 `MakeInterface::action` @01062fd4 를 **드디어 읽었다**.
#
# 종전 주석의 "Delay → [ScaleTo(1.5) + MoveBy] → …" 는 **내가 지어낸 것**이었다.
# 그 함수는 28,968B 라 Ghidra 디컴파일이 타임아웃으로 죽었고(`process: timeout`),
# 나는 못 읽은 채 안무를 상상해 적었다. `scripts/tools/decomp_big.py --asm-only` +
# `asm_read.py` 로 **주석 붙은 디스어셈블리**를 뽑아 실제 시퀀스를 복원했다
# (근거 = `docs/ref/orig_code/probe/action_asm.c` 줄 176~465).
#
# ## 원작 기본 공격 시퀀스 (CCSequence 인자 순서 그대로)
#   ① `CCDelayTime(현재애니길이 + 0.05)`            ← 진행 중 모션이 끝나길 기다린다
#   ② `CCCallFuncN → runSpineWithAnimationName(dragon, "attack", 1.125)`  ← 재생속도 1.125배
#   ③ `CCDelayTime(getAttackFrame() / 30 / 1.125)` ← **타격 프레임**까지의 시간
#   ④ `CCScaleTo(0.05, base×1.25, 1.05)`           ┐
#   ⑤ `CCScaleTo(0.05, base×0.90, 0.95)`           ├ 타격 순간의 **스쿼시&스트레치**
#   ⑥ `CCScaleTo(0.05, base×1.00, 1.00)`           ┘
#   ⑦ `CCDelayTime(전체길이/1.125 − 타격시간 − 0.1)` ← 공격 애니 잔여분
#   ⑧ `CCCallFuncN → runSpineWithAnimationName(dragon, "wait", 1.0)`
#   ⑨ `CCScaleTo(0, base, 1.0)`
#
# 상수 출처(부동소수 리터럴 디코드): 0x3d088815=1/30 · 0x3f900000=1.125 · 0x3fa00000=1.25 ·
#   0x3f866666=1.05 · 0x3f666666=0.90 · 0x3f733333=0.95 · 0x3d4ccccd=0.05 · 0xbdcccccd=−0.1
#
# ⚠️ **이 분기에 이동(MoveBy/MoveTo)이 없다.** 공격자는 제자리에서 스케일 펄스만 한다.
#   `action` 안의 MoveBy 는 전부 뒤쪽 분기(줄 2029·2073·3036·4771~ / 지속시간 0.25)에 있고
#   그것들이 어느 액션 코드인지는 아직 특정하지 못했다 — 특정 전엔 붙이지 않는다(HARD RULE 6).
#   ⇒ 종전 `_approach`(APPROACH 120pt 전진)는 근거가 없어 **끄고**, 원작 스케일 펄스로 바꾼다.
#   되살릴 근거가 생기면 `ATK_APPROACH` 만 0 이 아닌 값으로 되돌리면 된다.
const ATK_ANIM_SPEED := 1.125       # 원작 runSpineWithAnimationName(…, 1.125)
const ATK_FPS := 30.0               # 원작 getAttackFrame() ÷ 30
const ATK_PULSE_SEC := 0.05         # 원작 ScaleTo 지속시간(3단 공통)
const ATK_PULSE := [Vector2(1.25, 1.05), Vector2(0.90, 0.95), Vector2(1.00, 1.00)]
const ATK_TAIL := 0.1               # 원작 마지막 Delay 의 −0.1
const ATK_LEAD := 0.05              # 원작 ①의 +0.05
const ATK_APPROACH := 0.0           # 원작 기본공격엔 이동이 없다(위 ⚠️)
const MOVE_SEC := 0.18

## 우리 변환본 드래곤 씬이 실제로 갖고 있는 애니(2026-08-04 실측):
##   wait · attack · critical · damaged · down · love · ultimate1 · ultimate2
## 즉 **연출에 필요한 건 전부 이미 변환돼 있었다** — 지금까지 wait 만 틀고 있었을 뿐이다.
const ANIM_IDLE := "wait"


## 콜로세움 드래곤 스파인 — **native 크기 그대로**, 원점 = 발밑 중앙(우리 배치 규약).
## 원작 `makeDragonLayer` 와 같다: 크기를 건드리지 않고 3v3/1v1 배율만 밖에서 곱한다.
## ⚠️ 콜로세움은 항상 성체다(입장 레벨 25 + 공격 모션이 성체에만 있다 — 위 `_build_team` 주석).
func _dragon_spine(id: int) -> Node2D:
	var path := "res://scenes/dragons/dragon_%d_adult.tscn" % id
	if id <= 0 or not ResourceLoader.exists(path):
		return null
	var holder := Node2D.new()
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null and ap.has_animation(ANIM_IDLE):
		ap.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
		ap.play(ANIM_IDLE)
	# 바닥 중앙 정렬만 한다(스케일은 건드리지 않는다).
	var r := PartySelect._bounds(inst, Transform2D.IDENTITY)
	if r.size.y > 1.0:
		inst.position -= Vector2(r.get_center().x, r.position.y + r.size.y)
	return holder


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


## 애니 1회 재생 후 대기 모션 복귀. 반환 = 그 애니 길이(초).
func _play_anim(v: Dictionary, name: String) -> float:
	var ap = v.get("anim")
	if not (ap is AnimationPlayer) or not is_instance_valid(ap):
		return 0.0
	var p := ap as AnimationPlayer
	if not p.has_animation(name):
		return 0.0
	var a := p.get_animation(name)
	a.loop_mode = Animation.LOOP_NONE
	# 원작 `runSpineWithAnimationName(dragon, name, 1.125)` — 공격은 1.125배로 돌린다.
	var speed := ATK_ANIM_SPEED if name == "attack" else 1.0
	p.play(name, -1.0, speed)
	var dur := a.length / speed
	# 원작 ⑦: 잔여 = 전체/1.125 − 타격시간 − 0.1. 여기서는 애니가 끝난 뒤 복귀시키면 되므로
	# 같은 값(= dur − 0.1)을 쓴다.
	var gen := _gen
	get_tree().create_timer(maxf(0.1, dur - ATK_TAIL)).timeout.connect(func() -> void:
		if gen != _gen or not is_instance_valid(p) or bool(v.get("dead", false)):
			return
		if p.has_animation(ANIM_IDLE):
			p.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
			p.play(ANIM_IDLE))
	return dur


## 피격 깜빡임 — 원작 `MakeInterface::damagedColor` @01089208 그대로.
##
##   FadeTo(0.0, 0)                              ← 즉시 투명
##   DelayTime(getDuration("damaged") − 0.1)     ← "damaged" 애니 **길이만 잰다**(재생 안 함)
##   FadeTo(0.1, 255)                            ← 0.1초에 걸쳐 복귀
##   (tag = −0xc0dc8, 이미 걸려 있으면 stopActionByTag 로 끊고 다시)
##
## ✅ 이게 "일반 피격에 모션이 없다"의 정확한 내막이다 —
##   `action` code 0(기본 피격)이 `getDuration(spine, "damaged", 0)` 를 부르지만
##   **재생이 아니라 측정**이고(실측: 반환값이 곧장 CCDelayTime 으로 간다),
##   눈에 보이는 반응은 이 **깜빡임**이다. 종전엔 이걸 통째로 빠뜨렸다.
const HIT_BLINK_BACK := 0.1         # 원작 FadeTo(0.1, 255)

func _damaged_color(v: Dictionary) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	# "damaged" 애니 길이 = 깜빡임 유지 시간(원작과 같은 출처).
	var hold := 0.3
	var ap = v.get("anim")
	if ap is AnimationPlayer and is_instance_valid(ap) and (ap as AnimationPlayer).has_animation("damaged"):
		hold = (ap as AnimationPlayer).get_animation("damaged").length
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 0.0, 0.0)
	tw.tween_interval(maxf(0.05, hold - HIT_BLINK_BACK))
	tw.tween_property(node, "modulate:a", 1.0, HIT_BLINK_BACK)


## 피격 좌우 흔들림 — 원작 `MakeInterface::shakeLayerToHorizontal` @010892c0.
##   MoveBy(0.05, dir×+20) → (0.05, dir×−35) → (0.05, dir×+25) → (0.05, dir×−10)
## 합이 0 이라 제자리로 돌아온다(총 0.2초).
const HIT_SHAKE := [20.0, -35.0, 25.0, -10.0]
const HIT_SHAKE_SEC := 0.05

func _shake_horizontal(v: Dictionary, dir: float) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	# ⚠️ 복귀 지점은 `v["pos"]`(슬롯 원위치)가 아니라 **지금 자리**다 —
	#   `_swap_position` 이 자리를 옮겨 둔 도중에 흔들리면 원위치로 튕겨 버린다(2026-08-05).
	var base := node.position
	var tw := node.create_tween()
	for d: float in HIT_SHAKE:
		tw.tween_property(node, "position:x",
			node.position.x + d * dir, HIT_SHAKE_SEC).as_relative()
	tw.tween_property(node, "position", base, 0.0)


## 타격 순간의 **스쿼시&스트레치** — 원작 `action` @01062fd4 의 ScaleTo 3단.
##   ScaleTo(0.05, base×1.25, 1.05) → (0.05, base×0.90, 0.95) → (0.05, base×1.00, 1.00)
## X 는 드래곤 자기 스케일에 **곱하고**(뒤집힘 부호가 살아 있어야 한다) Y 는 절대값이다.
## 시작 시점은 애니 시작 + `getAttackFrame()/30/1.125` = **타격 프레임**.
## 우리는 프레임 수를 못 읽으므로 애니 길이의 절반을 타격 시점으로 잡는다
## (# ASSUMPTION: getAttackFrame() 은 스파인 변환본에 남지 않는 원작 DB 값이다).
func _attack_pulse(v: Dictionary, target: Dictionary, anim_dur: float) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var base := _base_scale(v)
	var hit := clampf(anim_dur * 0.5, 0.05, 1.2)

	var tw := create_tween()
	tw.tween_interval(hit)
	for f: Vector2 in ATK_PULSE:
		# X 부호 유지(내 팀은 flipX 상태다), Y 는 원작대로 절대 배율.
		tw.tween_property(node, "scale",
			Vector2(base.x * f.x, absf(base.y) * f.y), ATK_PULSE_SEC)
	tw.tween_property(node, "scale", base, 0.0)

	# 이동은 원작 기본공격 분기에 없다 — 근거가 생기면 ATK_APPROACH 를 켠다.
	if ATK_APPROACH <= 0.0 or target.is_empty():
		return
	var home: Vector2 = v.get("pos", node.position)
	var tp: Vector2 = target.get("pos", home)
	var dx := signf(tp.x - home.x) * minf(ATK_APPROACH, absf(tp.x - home.x) - 90.0)
	var mv := create_tween()
	mv.tween_property(node, "position", home + Vector2(dx, 0.0), MOVE_SEC)
	mv.tween_interval(maxf(0.1, anim_dur - MOVE_SEC * 2.0))
	mv.tween_property(node, "position", home, MOVE_SEC)


func _base_scale(v: Dictionary) -> Vector2:
	if not v.has("base_scale"):
		var n = v.get("node")
		v["base_scale"] = (n as Node2D).scale if n is Node2D else Vector2.ONE
	return v["base_scale"]


# ---------- 액션 코드 배선 (2026-08-05) ----------
#
# `MakeInterface::action` @01062fd4 의 점프테이블 53핸들러를 전수 특정한 결과
# (`docs/ref/porting/Colosseum.md` §7.5)를 **우리 이벤트에 실제로 연결한다.**
# 종전엔 지도만 만들어 두고 `_motion` 은 여전히 우리 자체 타입 3가지로만 갈렸다.
#
# 원작은 서버가 액션 코드를 보내 줬다 → 우리는 `Battle.simulate()` 이벤트에서 **역으로 판정**한다.
# 이 판정은 render 층 일이다(§8): logic 은 "무슨 일이 있었나"만 말하고,
# "그 일을 원작이 어느 코드로 연출했나"는 화면의 어휘다.
const AC_HIT := 0          # 기본 피격
const AC_CONFUSE := 1      # 혼란 — 자기 자신을 때린다
const AC_DOUBLE := 2       # 연속 공격
const AC_EVADE := 3        # 회피
const AC_CUTIN := 4        # 각성기 컷인(`showCutIn`) — 아래 🔴 참조
const AC_CRIT_FX := 41     # 크리티컬 이펙트(`criticalEffectMake`)
const AC_CRIT_ANIM := 43   # 크리티컬 애니(`"critical"` → `"wait"`)
const AC_SWAP := 42        # 위치 교대
const AC_STUN := -15       # 기절(행동 불가)
const AC_POISON := -32     # 중독
const AC_BIGHIT := -54     # 대형 타격

## 이벤트 1건 → 원작 액션 코드. 양수 스킬 코드는 `skill_id` 가 그대로 코드다(§7.5 결론 ①).
func _action_code(ev: Dictionary, t: String) -> int:
	if bool(ev.get("miss", false)):
		return AC_EVADE
	match t:
		"confused":
			return AC_CONFUSE
		"double":
			return AC_DOUBLE
		"status_skip":
			return AC_STUN
		"dot":
			return AC_POISON
		"skill":
			return int(ev.get("skill_id", 0))
		"awaken":
			return AC_CUTIN
	if bool(ev.get("crit", false)):
		return AC_CRIT_FX
	return AC_HIT


## 한 이벤트의 스파인 연출 — 공격자/피격자를 함께 움직인다.
func _motion(ev: Dictionary, t: String, atk_tag: String, dfn_tag: String) -> void:
	var atk: Dictionary = _views.get(atk_tag, {})
	var dfn: Dictionary = _views.get(dfn_tag, {})
	var code := _action_code(ev, t)

	# code −15 기절 — 원작은 공격 자체가 없다(턴만 소모). 문자열 `ColosseumStuned`.
	if code == AC_STUN:
		var st: Dictionary = _views.get(String(ev.get("actor", "")), {})
		if not st.is_empty():
			_shake_horizontal(st, 1.0 if bool(st.get("mine", false)) else -1.0)
			_status_icon(st, int(ev.get("source", 0)), false, int(ev.get("turns", 0)))
		return

	# code 1 혼란 — 원작은 `swapPosition` 으로 자리를 바꾼 뒤 자기 스파인으로 자기를 친다.
	if code == AC_CONFUSE:
		var me: Dictionary = _views.get(String(ev.get("actor", "")), {})
		if not me.is_empty():
			_swap_position(me, 0.8)
			var d0 := _play_anim(me, "attack")
			_attack_pulse(me, me, d0)
			_damaged_color(me)
			_shake_horizontal(me, 1.0 if bool(me.get("mine", false)) else -1.0)
		return

	if not atk.is_empty() and not bool(atk.get("dead", false)):
		# 원작 `castSkill` 은 종류를 가리지 않고 **"attack" 하나만** 튼다
		# (크리티컬·각성기용 별도 애니를 콜로세움 경로에서 부르지 않는다).
		var dur := _play_anim(atk, "attack")
		# 각성기는 제자리에서 낸다(원작도 UltimateLayer 가 화면을 덮는다).
		if t != "awaken":
			_attack_pulse(atk, dfn, dur)
		# code 2 연속 공격 — 원작 `isDoubleAttack` 분기는 타격 시점을 **두 번** 잡는다
		# (`activeIcon` 이 `getAttackFrame()/30/1.5` 와 그 2배를 쓴다) ⇒ 펄스를 한 번 더.
		if code == AC_DOUBLE:
			var gen2 := _gen
			get_tree().create_timer(maxf(0.1, dur * 0.5)).timeout.connect(func() -> void:
				if gen2 == _gen and not bool(atk.get("dead", false)):
					_attack_pulse(atk, dfn, dur * 0.6))

	# code 3 회피 — 원작 `evadeEffect` + `setInvisibleSpine`/`setVisibleSpine`.
	if code == AC_EVADE:
		if not dfn.is_empty():
			_evade_effect(dfn)
		return

	# 피격 반응 — **애니는 없지만 반응은 있다**(2026-08-05 `action` 코드지도로 확정).
	#   code 0(기본 피격) → `damagedColor` = 깜빡임
	#   code −32(중독)    → `damagedColor` + `shakeLayerToHorizontal`
	#   code −54(대형 타격) → `shakeLayerAllDirection`(화면 전체 흔들림)
	# 종전엔 "모션이 없다"를 "아무것도 안 한다"로 잘못 옮겨 피격이 전혀 안 보였다.
	if not dfn.is_empty() and not bool(dfn.get("dead", false)) \
			and int(ev.get("damage", 0)) > 0:
		_damaged_color(dfn)
		if code == AC_POISON or code == AC_CRIT_FX:
			# 흔들림 방향 = 맞은 쪽이 밀리는 방향(공격자 반대편).
			_shake_horizontal(dfn, 1.0 if bool(dfn.get("mine", false)) else -1.0)
		if code == AC_BIGHIT:
			_shake_screen(0.4, 1.0)

	# 상태이상 부여 — 원작 code −14 가 `activeIcon`/`getSkillIndex` 로 아이콘을 세운다.
	var buff := String(ev.get("buff", ""))
	var debuff := String(ev.get("debuff", ""))
	if buff != "" and not atk.is_empty():
		_status_icon(atk, int(ev.get("skill_id", 0)), true, int(ev.get("turns", 0)))
	if debuff != "" and not dfn.is_empty():
		_status_icon(dfn, int(ev.get("skill_id", 0)), false, int(ev.get("turns", 0)))

	# 이펙트 스파인은 **드래곤 모션과 별개**로 얹힌다(원작 castSkill 이 그렇게 만든다).
	var at: Vector2 = dfn.get("pos", _vis() * 0.5) if not dfn.is_empty() else _vis() * 0.5
	match t:
		"skill":
			# 원작 `createIcon` 은 이펙트와 함께 **화면 상단 스킬 이름 배너**도 낸다.
			_skill_banner(String(ev.get("skill_name", "")), int(ev.get("skill_id", 0)))
			_skill_spine(int(ev.get("skill_id", 0)), at)
		"awaken":
			# 원작 `FightScene` @00f8cd6c: `showCutIn(actor, 0.5)` → `UltimateLayer`.
			# `showCutIn` 은 `getNo()` 가 **9013/9014**(이벤트 드래곤)일 때만 전면 컷인
			# (`getImagePathCutIn`/`CutBg`)을 내고, 나머지는 크리티컬 보이스만 낸다.
			# 우리 드래곤에 9013/9014 는 없다 ⇒ 보이스 + 각성기 레이어.
			_crit_voice(atk)
			_awaken_fx(atk, at)
		_:
			if atk.is_empty():
				pass
			elif code == AC_CRIT_FX:
				# 코드 41 은 `criticalEffectMake` 와 함께 **`swapPosition`** 도 부른다 —
				# 뒷줄이 크리티컬을 내면 앞줄과 자리를 바꾼다(3v3 한정).
				_swap_position(atk, 0.8)
				# 크리티컬 = **공격한 드래곤 자기 크리티컬 스파인**(원작 criticalEffectMake).
				_critical_effect(atk, dfn)
				_crit_voice(atk)
				# 드빌1에서 온 종만 자기 이펙트 시퀀스를 위에 더 얹는다(800 로키 = `col_action2`).
				_dragon_fx_seq(int(atk.get("id", 0)), "col_action2", at)
			else:
				# 평타 — 드빌1에서 온 종만 전용 평타 이펙트를 갖는다(`col_action1`).
				# 없으면 아무것도 안 뜬다(원작 콜로세움 평타에도 이펙트가 없다).
				_dragon_fx_seq(int(atk.get("id", 0)), "col_action1", at)


## 위치 교대 — 원작 `MakeInterface::swapPosition` @01087ea4 (액션 코드 **1**·**41**·**42**).
##
## 원작이 하는 일(디컴프 + 룩업표 실측):
##   행동한 드래곤의 태그 `t` 로 `DAT_021c4ae8`(태그 11~15 구간)을 찾아 **교대 상대 태그**를 얻는다.
##   실측값 = `[11, 10, 11, 10, 11]`, 구간 밖은 `10`
##   ⇒ 태그 11(내 앞줄)·10(상대 앞줄)은 **자기 자신** ⇒ 앞줄이 행동하면 교대가 없다.
##     태그 13·15(내 뒷줄) → 11, 12·14(상대 뒷줄) → 10 ⇒ **자기 진영 앞줄과 자리를 바꾼다.**
##   앞줄:  Delay(d1) → MoveBy(0.05, ±210) → Delay(d2 + 0.1) → MoveTo(0.05, 앞줄 제자리)
##   행동자: Delay(d1 + 0.05) → MoveTo(0.05, 앞줄 자리) → Delay(d2) → MoveTo(0.05, 제자리)
##   HUD(태그 × −50)도 같이 움직인다 — 앞줄 자리 + (0, scale × −95).
##
## # ASSUMPTION: 원작 `MoveBy` 의 x 부호가 `ABS(scaleX)/scaleY` 라 디컴프상 항상 양수로 읽히는데,
##   그러면 양 진영이 같은 방향으로 나간다. 물리적으로 "앞으로 비켜 준다"가 맞으므로
##   **진영 기준 전방**(내 팀 +x / 상대 −x)으로 뒀다. 크기 210·0.05 는 원작 그대로.
const SWAP_STEP := 210.0
const SWAP_SEC := 0.05

func _swap_position(actor: Dictionary, hold: float) -> void:
	if _mode != "team" or actor.is_empty():
		return
	if int(actor.get("slot", 0)) == 0:
		return                                   # 앞줄이 행동하면 교대 없음(룩업표 11→11 / 10→10)
	var mine := bool(actor.get("mine", false))
	var front: Dictionary = _views.get(("A0" if mine else "E0"), {})
	if front.is_empty() or bool(front.get("dead", false)):
		return
	var dir := 1.0 if mine else -1.0
	var fhome: Vector2 = front.get("pos", Vector2.ZERO)
	var ahome: Vector2 = actor.get("pos", Vector2.ZERO)

	# 앞줄 — 앞으로 비켜났다 제자리로.
	for k in ["node", "barh"]:
		var fn = front.get(k)
		if fn is Node2D and is_instance_valid(fn):
			var base: Vector2 = (fn as Node2D).position
			var t1 := (fn as Node2D).create_tween()
			t1.tween_property(fn, "position", base + Vector2(dir * SWAP_STEP, 0.0), SWAP_SEC)
			t1.tween_interval(hold + 0.1)
			t1.tween_property(fn, "position", base, SWAP_SEC)
	# 행동자 — 앞줄 자리로 갔다 제자리로.
	var shift := fhome - ahome
	for k2 in ["node", "barh"]:
		var an = actor.get(k2)
		if an is Node2D and is_instance_valid(an):
			var base2: Vector2 = (an as Node2D).position
			var t2 := (an as Node2D).create_tween()
			t2.tween_interval(SWAP_SEC)
			t2.tween_property(an, "position", base2 + shift, SWAP_SEC)
			t2.tween_interval(hold)
			t2.tween_property(an, "position", base2, SWAP_SEC)


## 회피 — 원작 `MakeInterface::evadeEffect` @0108f078.
##   `battle.img_plist` 의 `battle/miss_%s.png` 를 피격 지점에 놓고
##   Delay(0.25) → ScaleTo(0, 2.0) → ScaleTo(0.25, 1.0) → Delay(0.25)
##   → MoveBy(0.5, (0, 75)) → FadeTo(0.5, 0) → 제거.
## (프레임 이름은 SSO 바이트 복원: 길이 0x24>>1=18 · "battle" + "/m" + "iss_%s.p" + "ng")
const EVADE_LIFT := 75.0
const EVADE_POP := 2.0

func _evade_effect(dfn: Dictionary) -> void:
	var at: Vector2 = dfn.get("pos", _vis() * 0.5)
	var s := _spr("battle_ui", "battle_miss_kr", Design.ASSET_SCALE)
	if s == null:
		return
	s.position = at - Vector2(0.0, DMG_LIFT)
	s.z_index = 100
	s.scale *= EVADE_POP
	add_child(s)
	var base := Design.ASSET_SCALE
	var tw := s.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(s, "scale", Vector2(base, base), 0.25)
	tw.tween_interval(0.25)
	tw.tween_property(s, "position", s.position - Vector2(0.0, EVADE_LIFT), 0.5)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.5)
	tw.tween_callback(s.queue_free)


# ---------- 상태이상 아이콘 — 원작 `MakeInterface::createIcon` @0109272c ----------
#
# 원작 자산(리터럴 전수): `skill/%d.png`(스킬 아이콘 75×75) · `skill/buff.png` ·
#   `skill/debuff.png`(85×85 테두리) · `font/font_normal.fnt`(남은 턴) ·
#   `skill/skill_zzing_spine`(부여 순간의 반짝임) · `scene/colosseum/skill_txt_bg.png`(이름 배너)
# 지속 아이콘의 기본 크기는 `MakeInterface::activeIcon` @01092044 의 마지막
#   `ScaleTo(t, 0.375)` 에서 읽는다 — 발동할 때마다
#   `ScaleTo(t, 0.5, 0.3) → (0.3, 0.5) → (0.375)` 로 튄다.
const ICON_BASE := 0.375
const ICON_PULSE := 0.1
const ICON_STEP := 40.0
const ICON_MAX := 4

func _status_icon(v: Dictionary, skill_id: int, is_buff: bool, turns: int) -> void:
	var host = v.get("icons")
	if not (host is Node2D) or not is_instance_valid(host):
		return
	var box := host as Node2D
	# 같은 스킬이 이미 붙어 있으면 원작 `activeIcon` 처럼 **다시 튀게만** 한다.
	var name_key := "ic%d" % skill_id
	var old := box.get_node_or_null(NodePath(name_key))
	if old != null:
		_icon_pulse(old as Node2D)
		var lb := old.get_node_or_null("t")
		if lb is Label:
			(lb as Label).text = str(maxi(0, turns))
		return
	if box.get_child_count() >= ICON_MAX:
		return
	_zzing(v)                       # 새로 붙는 순간에만 — 재발동은 위 `activeIcon` 펄스다

	var holder := Node2D.new()
	holder.name = name_key
	holder.position = Vector2(box.get_child_count() * ICON_STEP, 0.0)
	holder.scale = Vector2.ONE * ICON_BASE
	box.add_child(holder)

	var ring := _spr("skill_ui", "skill_buff" if is_buff else "skill_debuff", Design.ASSET_SCALE)
	if ring != null:
		holder.add_child(ring)
	var ic := _spr("skill_ui", "skill_%d" % skill_id, Design.ASSET_SCALE)
	if ic != null:
		holder.add_child(ic)
	if turns > 0:
		var l := Label.new()
		l.name = "t"
		l.text = str(turns)
		l.size = Vector2(80.0, 40.0)
		l.position = Vector2(-4.0, -66.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bm_style(l, 36, Color.WHITE, "font_normal")
		holder.add_child(l)
	_icon_pulse(holder)


## 상태이상이 **새로 붙는 순간**의 반짝임 — 원작 `createIcon` 이 같은 시퀀스 안에서 낸다.
##   `skill/skill_zzing_spine.spine_json` + `.img_plist`, createWithFile(…, 1.0)
##   Delay(param_6 + **0.5**) → … → runSpineWithAnimationName("animation") → Delay(**1.0**) → 제거
const ZZING_SCENE := "res://scenes/fx/skill_zzing_spine.tscn"
const ZZING_DELAY := 0.5
const ZZING_HOLD := 1.0

func _zzing(v: Dictionary) -> void:
	if not ResourceLoader.exists(ZZING_SCENE):
		return
	var holder := Node2D.new()
	holder.z_index = 101
	holder.position = v.get("pos", _vis() * 0.5)
	holder.visible = false
	add_child(holder)
	var inst = (load(ZZING_SCENE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	var gen := _gen
	get_tree().create_timer(ZZING_DELAY).timeout.connect(func() -> void:
		if gen != _gen or not is_instance_valid(holder):
			return
		holder.visible = true
		if ap != null and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
			ap.play("animation"))
	var tw := holder.create_tween()
	tw.tween_interval(ZZING_DELAY + ZZING_HOLD)
	tw.tween_callback(holder.queue_free)


## 원작 `activeIcon` 의 발동 펄스. 기본 0.375 로 돌아온다.
func _icon_pulse(n: Node2D) -> void:
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(0.5, 0.3), ICON_PULSE)
	tw.tween_property(n, "scale", Vector2(0.3, 0.5), ICON_PULSE)
	tw.tween_property(n, "scale", Vector2.ONE * ICON_BASE, ICON_PULSE)


# ---------- 스킬 이름 배너 — 같은 `createIcon` 의 상단 표시 ----------
#
# 원작: `scene/colosseum/skill_txt_bg.png`(530×47) 를 `VisibleRect::top + (0, −150)` 에 두고
#   opacity 0 → Delay → FadeTo(0.15, 255) → Delay(1.15) → FadeTo(0.1, 0) → 제거.
#   그 위에 `getSkillName()` BMFont(subtitle), 아래 `Skill::getShort()` 짧은 설명이
#   `top + (0, −200)` 자리에서 배너로 올라온다(ScaleTo 1.65/1.35 + MoveTo 0.25).
# ⚠️ 우리는 **최종 배치**(레퍼런스 `docs/ref/pvp/화면 캡처 …202630.png` 의 "철갑 방패 / 적 피해 감소")
#   와 페이드 타이밍까지 옮기고, 설명 라벨이 이름 자리에서 배너로 **날아오르는 중간 안무**는
#   생략했다 — 원작 시퀀스의 인자 순서를 디컴프에서 확신할 수 없어서다(HARD RULE 6).
const BANNER_Y := 150.0
const BANNER_SUB_Y := 200.0
const BANNER_IN := 0.15
const BANNER_HOLD := 1.15
const BANNER_OUT := 0.1

func _skill_banner(sname: String, skill_id: int) -> void:
	if sname == "":
		return
	var vis := _vis()
	var root := Node2D.new()
	root.z_index = 120
	root.modulate.a = 0.0
	add_child(root)

	var bg := _spr(CO, "scene_colosseum_skill_txt_bg", Design.ASSET_SCALE)
	if bg != null:
		bg.position = Vector2(vis.x * 0.5, BANNER_Y)
		root.add_child(bg)

	var nm := Label.new()
	nm.text = sname
	nm.size = Vector2(vis.x, 40.0)
	nm.position = Vector2(0.0, BANNER_Y - 20.0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(nm, 30, Color.WHITE)
	root.add_child(nm)

	# 짧은 설명 — 원작 `Skill::getShort()` @01523868 은 `info_skill` 의 별도 열을 그대로 돌려주는
	# 게터인데(멤버 +0x130), **그 열은 서버 DB 와 함께 유실**됐다. 우리가 가진 가장 가까운 것이
	# `skills.json` 의 `effect_text` 라 그걸 쓴다(레퍼런스의 "적 피해 감소" 자리).
	var short := String((Data.skills.get(str(skill_id), {}) as Dictionary).get("effect_text", ""))
	if short != "":
		var sl := Label.new()
		sl.text = short
		sl.size = Vector2(vis.x, 32.0)
		sl.position = Vector2(0.0, BANNER_SUB_Y - 16.0)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bm_style(sl, 21, Color.WHITE)
		root.add_child(sl)

	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, BANNER_IN)
	tw.tween_interval(BANNER_HOLD)
	tw.tween_property(root, "modulate:a", 0.0, BANNER_OUT)
	tw.tween_callback(root.queue_free)


# ---------- 스킬/크리티컬 이펙트 스파인 ----------
#
# 원작 `MakeInterface::castSkill` @0108a924 이 쓰는 자산(리터럴 전수):
#     "skill/skill_%d_spine.spine_json" + "skill/skill_%d_spine.img_plist"
#     "particle/skill/skill_%d.plist"
#     애니명 "animation"
# ⇒ 스킬 연출은 **드래곤 모션이 아니라 별도 이펙트 스파인**이다(castSkill 은 드래곤 애니로는
#   "attack" 만 건드린다). 노출 시간은 원작이 애니 길이와 무관하게 0.7초 뒤 Hide 다.
#
# 우리 프로젝트엔 이 파이프라인이 **이미 있다** — `scenes/fx/skill_<id>_spine.tscn` 41종 +
# `battle.gd::_play_skill_spine` 이 같은 규약(z=100 · animation/work/destroy · 0.7초)으로
# 재생한다. 새로 짜지 않고 같은 규약을 따른다(§3 우리 코드 먼저).
const SKILL_SPINE_SEC := 0.7

## 스킬 이펙트 스파인 1회 재생. 없으면 false.
func _skill_spine(sid: int, at: Vector2) -> bool:
	var path := "res://scenes/fx/skill_%d_spine.tscn" % sid
	if sid <= 0 or not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 100                       # 원작 addChild(spine, 100)
	holder.position = at
	add_child(holder)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null:
		# 원작 스킬 스파인은 `animation`(본체) + `work`/`destroy`(뒤처리)를 갖는다.
		var pick := ""
		for cand in ["animation", "work", "destroy"]:
			if ap.has_animation(cand):
				pick = cand
				break
		if pick == "":
			holder.queue_free()
			return false
		ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
		ap.play(pick)
	var t := holder.create_tween()
	t.tween_interval(SKILL_SPINE_SEC)          # 원작 Delay(0.7) → Hide
	t.tween_callback(holder.queue_free)
	return true


## 드래곤 **전용 이펙트 프레임 시퀀스** 1회 재생. 없으면 false.
##
## DV2 원작에는 "드래곤별 이펙트"라는 축이 없다 — 이펙트는 스킬 단위(`skill_<id>_spine`)다.
## 이 경로는 **드빌1에서 이식한 종**이 자기 이펙트를 들고 오기 때문에 생겼다
## (800 로키: `col_action1` 12프레임 = 평타 · `col_action2` 16프레임 = 크리티컬).
## 🟦 사용자 확정 2026-08-04. 상세 = `docs/ref/porting/DragonLoki800.md` §5-C.
##
## 프레임마다 크기가 달라서 **원본 캔버스(src 800×480) 기준 트림 오프셋(off)** 으로 정렬한다.
## 안 그러면 재생 중 중심이 흔들린다(`dv2-atlas-trim-offset` 과 같은 축).
const FX_SEQ_FPS := 24.0

func _dragon_fx_seq(did: int, prefix: String, at: Vector2) -> bool:
	if did <= 0:
		return false
	var dir := "dragon_%d_fx" % did
	var man := _man(dir)
	if man.is_empty():
		return false
	var keys: Array = []
	for k in man:
		if String(k).begins_with("dragon_%d_%s_" % [did, prefix]):
			keys.append(String(k))
	if keys.is_empty():
		return false
	keys.sort()                                   # …_00, _01, … 프레임 순서
	var holder := Node2D.new()
	holder.z_index = 100                          # 스킬 이펙트와 같은 층
	holder.position = at
	add_child(holder)
	var shown: Array[Sprite2D] = []
	for k in keys:
		var ent: Dictionary = man.get(k, {})
		var spr := _spr(dir, k, Design.ASSET_SCALE)
		if spr == null:
			continue
		var off: Array = ent.get("off", [0, 0])
		# cocos off = (트림중심 − 원본캔버스중심), y-up → Godot 은 y 를 뒤집는다.
		spr.position = Vector2(float(off[0]), -float(off[1])) * Design.ASSET_SCALE
		spr.visible = false
		holder.add_child(spr)
		shown.append(spr)
	if shown.is_empty():
		holder.queue_free()
		return false
	var step := 1.0 / FX_SEQ_FPS        # 콜로세움엔 전투 배속 개념이 없다(탐험과 다른 점)
	var tw := holder.create_tween()
	for i in shown.size():
		var s: Sprite2D = shown[i]
		var prev: Sprite2D = shown[i - 1] if i > 0 else null
		tw.tween_callback(func() -> void:
			if prev != null and is_instance_valid(prev):
				prev.visible = false
			if is_instance_valid(s):
				s.visible = true)
		tw.tween_interval(step)
	tw.tween_callback(holder.queue_free)
	return true


## 크리티컬 이펙트 — 원작 `MakeInterface::criticalEffectMake` @01089a1c (액션 코드 **41**).
##
##   getAwaken()==0 ? "dragon/dragon_%d_critical_spine.spine_json"
##                  : "dragon/dragon_%d_e_critical_spine.spine_json"   (폴백 `dragon_9998_…`)
##   아틀라스 = `dragon/dragon_%d_spine.img_plist` · createWithFile(…, 1.0)
##   setScaleX(음수 = 공격 방향으로 X 반전) · addChild(spine, **8**, −2)
##   재생 = Show → runSpineWithAnimationName("animation") → DelayTime(getDuration("animation"))
##   ⚠️ 붙는 곳은 **공격자가 아니라 대상(target)의 레이어**다 — 스파인만 공격자 것을 쓴다.
##   (탐험 쪽 `battle.gd::_critical_spine` 이 같은 함수를 이미 이식해 뒀다 — 같은 규약을 따른다.)
##
## 🔴🔴 2026-08-05 **재정정** — 하루 전의 "원작 크리티컬은 공용 9999 컷인" 은 **틀렸다.**
##   사용자 지적("전투 중간에 금발 소녀 애니가 뜬다")으로 다시 팠더니:
##     · `dragon/dragon_9999_critical{,_ready,_shot}_spine` 을 만드는 블록은 `action` 안에서
##       **`01064694 cmp w19,#0x29a` / `01064698 b.eq 0x01069eac` 단 한 곳**으로만 들어온다.
##       `w19` = 액션 코드이므로 그 컷인은 **액션 코드 666 전용**이다(점프테이블 −54~170 밖의
##       특수 코드라 `default` 비교 사다리에서 걸린다). 우리 `Battle.simulate()` 는 666 을
##       만들지 않는다 ⇒ **어떤 대전에서도 뜨면 안 되는 연출**이었다.
##     · dragon 9999 는 드래곤이 아니다 — `dragons.json` 에 없고, 스켈레톤을 렌더해 보면
##       **거대한 새총을 든 금발 소녀**(누리)다. 이벤트 매치용 캐릭터로 보인다.
##     · 진짜 크리티컬은 **41 `criticalEffectMake`**(공격자 자기 크리티컬 스파인, 폴백 9998) 와
##       **43**(공격자 스파인의 `"critical"` → `"wait"` 애니) 다. 코드 0 의 배타 신호에도
##       `isCritical`/`getCriticalFrame` 이 있어 **타격 프레임만 크리티컬용으로 바뀐다**.
##     · **4 `showCutIn` 은 각성기 컷인**이다 — `FightScene` 이 `UltimateLayer` 를 만들기
##       **직전에** 부르고(@00f8cd6c), 내부는 `getNo()==0x2335(9013) || 0x2336(9014)` 일 때만
##       `Cutin::show(getImagePathCutIn, getImagePathCutBg)` 를 낸다. 그 밖의 드래곤은
##       `getDragonVoiceCriticalFilePath()` = **보이스만**.
##   ⇒ 9999 컷인 코드는 지웠다. 되살릴 근거(액션 코드 666 을 쓰는 이벤트 매치)가 생기면
##     복원 안무는 `docs/ref/porting/Colosseum.md` §8.7 에 적어 뒀다.
func _critical_effect(atk: Dictionary, dfn: Dictionary) -> bool:
	var cid := int(atk.get("id", 0))
	var path := "res://scenes/dragons/dragon_%d_e_critical.tscn" % cid
	if not ResourceLoader.exists(path):
		path = "res://scenes/dragons/dragon_%d_critical.tscn" % cid
	if cid <= 0 or not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 8                          # 원작 addChild(spine, 8, −2)
	# 원작은 **대상 레이어**에 붙인다.
	var node = dfn.get("node")
	if node is Node2D and is_instance_valid(node):
		(node as Node2D).add_child(holder)
	else:
		add_child(holder)
		holder.position = dfn.get("pos", _vis() * 0.5)
	# 원작 setScaleX(음수) — 공격 방향으로 뒤집는다.
	holder.scale = Vector2(-1.0 if bool(atk.get("mine", false)) else 1.0, 1.0)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	var pick := ""
	if ap != null:
		# 원작은 `"animation"` 하나만 쓴다. 일부 스켈레톤은 이름이 `critical` 이다(데이터 편차).
		for cand in ["animation", "critical"]:
			if ap.has_animation(cand):
				pick = cand
				break
	if pick == "":
		holder.queue_free()
		return false
	ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
	ap.play(pick)
	# 원작 CCDelayTime(getDuration("animation")) — 고정 초가 아니라 애니 길이만큼.
	var t := holder.create_tween()
	t.tween_interval(ap.get_animation(pick).length)
	t.tween_callback(holder.queue_free)
	return true


## 크리티컬 보이스 — 원작 `showCutIn` 의 비-이벤트 분기가 내는 유일한 것
## (`Dragon::getDragonVoiceCriticalFilePath()` → `music/voice<N>.mp3`).
## 매핑은 `data/dragon_voices.json` `voices.<id>.critical`(유실분을 사용자 검수로 채운 값).
func _crit_voice(atk: Dictionary) -> void:
	var id := int(atk.get("id", 0))
	var v := int((Data.dragon_voices.get("voices", {}).get(str(id), {}) as Dictionary).get("critical", 0))
	if v > 0:
		Bgm.sfx("voice%d" % v)


## 화면 흔들림 — 원작 `MakeInterface::shakeLayerToVertical` / `Shake::actionWithDuration`.
## 진폭은 원작 인자(0.5)를 픽셀로 환산한 값이 아니라 **비율**이므로 화면 크기에 맞춰 쓴다.
## # ASSUMPTION: Shake 클래스의 진폭 단위를 특정하지 못해 픽셀 환산은 우리가 정했다.
func _shake_screen(sec: float, amp: float) -> void:
	var base := position
	var tw := create_tween()
	var steps := maxi(2, int(sec / 0.05))
	for k in steps:
		var d := amp * 18.0 * (1.0 - float(k) / float(steps))
		tw.tween_property(self, "position",
			base + Vector2(0.0, d if k % 2 == 0 else -d), 0.05)
	tw.tween_property(self, "position", base, 0.05)


## 각성기(궁극기) 이펙트 — 원작 `UltimateLayer`(138메서드)가 **속성별 전용 아트**를 쓴다:
##     `skill/ultimate/<element>/<element>_*.png`  (aqua/chaos/dark/earth/fire/holy/light/
##     shadow/wind 9종 — 2026-08-04 cocos_export 로 전량 변환)
## 각 속성이 바닥 링 `<el>_circle1~3` + 번호가 붙은 시퀀스(fire=explosion1~6 ·
## wind=whirl1~4 · aqua=shark1~3 …)를 갖는다 ⇒ **링 + 프레임 시퀀스**가 기본 골격이다.
##
## ⚠️ 여기 구현한 건 그 골격까지다. `UltimateLayer` 전체 안무(속성별 개별 연출 · 카메라 ·
##   `battle/<combine>/combine_outline` 합체 외곽선 · `particle/scene/colosseum/effect_damaged`)
##   는 아직 이식 전이다 — 자산은 이제 다 있으니 이어서 붙이면 된다.
func _awaken_fx(atk: Dictionary, at: Vector2) -> void:
	var el := String(atk.get("element", ""))
	var dir := "ultimate_" + el
	var man := _man(dir)
	if man.is_empty():
		return
	var pfx := "skill_ultimate_%s_%s_" % [el, el]
	# 바닥 링
	var ring := _spr(dir, pfx + "circle1", Design.ASSET_SCALE)
	if ring != null:
		ring.position = at
		ring.z_index = 90
		add_child(ring)
		var rt := ring.create_tween()
		rt.tween_property(ring, "scale", Vector2(2.0, 2.0) * Design.ASSET_SCALE, 0.5)
		rt.parallel().tween_property(ring, "modulate:a", 0.0, 0.5)
		rt.tween_callback(ring.queue_free)
	# 번호 시퀀스 — 가장 긴 계열을 골라 프레임 애니로 돌린다.
	var fam := _longest_family(man, pfx)
	if fam.is_empty():
		return
	var spr := _spr(dir, fam[0], Design.ASSET_SCALE)
	if spr == null:
		return
	spr.position = at
	spr.z_index = 101
	add_child(spr)
	var i := 0
	var gen := _gen
	var step := func() -> void: pass
	var t := Timer.new()
	t.wait_time = 0.08                      # 원작 프레임 시퀀스 간격대
	t.autostart = true
	spr.add_child(t)
	t.timeout.connect(func() -> void:
		i += 1
		if gen != _gen or i >= fam.size():
			if is_instance_valid(spr):
				spr.queue_free()
			return
		var tex := _tex(dir, fam[i])
		if tex != null and is_instance_valid(spr):
			spr.texture = tex)


## `<prefix><name><N>` 꼴 중 원소가 가장 많은 계열을 프레임 순서대로 반환.
func _longest_family(man: Dictionary, pfx: String) -> Array:
	var groups := {}
	for k in man:
		var s := String(k)
		if not s.begins_with(pfx) or s.begins_with(pfx + "circle"):
			continue
		var tail := s.substr(pfx.length())
		var base := tail.rstrip("0123456789")
		if base == tail:
			continue                        # 번호 없는 단품은 시퀀스가 아니다
		if not groups.has(base):
			groups[base] = []
		(groups[base] as Array).append(s)
	var best: Array = []
	for b in groups:
		var arr: Array = groups[b]
		if arr.size() > best.size():
			arr.sort()
			best = arr
	return best


func _man(dir: String) -> Dictionary:
	if _mans.has(dir):
		return _mans[dir]
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
	_mans[dir] = d
	return d


## 피해/회복 수치 — 원작 `MakeInterface::showDamage` @010910ac 이식.
##   폰트: 피해 = `font/font_total.fnt` · 회복 = `font/font_heal.fnt`(둘 다 보유)
##   위치: 대상 기준 (0, 235) 위
##   연출: Delay → Show → **ScaleTo(0, 1.75) → ScaleTo(0.25, 1.0)** → Delay(0.5) → 사라짐
##   ⇒ 종전의 "위로 떠오르며 페이드"는 자작이었다. 원작은 **크게 떴다가 제 크기로 줄어드는** 팝이다.
const DMG_LIFT := 235.0 * 0.5       # 원작 (0,235) — 우리 드래곤 크기(170) 기준으로 절반만
const DMG_POP_BIG := 1.75           # 원작 ScaleTo(0, 1.75)
const DMG_POP_SEC := 0.25           # 원작 ScaleTo(0.25, 1.0)
const DMG_HOLD := 0.5               # 원작 DelayTime(0.5)

func _float_text(pos: Vector2, text: String, col: Color, heal := false) -> void:
	var l := Label.new()
	l.text = text
	l.size = Vector2(140.0, 40.0)
	l.pivot_offset = l.size * 0.5
	l.position = pos + Vector2(-70.0, -DMG_LIFT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(l, 30, col, "font_heal" if heal else "font_total")
	l.scale = Vector2.ONE * DMG_POP_BIG
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, DMG_POP_SEC)
	tw.tween_interval(DMG_HOLD)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)


# ---------- 결과 ----------

func _finish() -> void:
	var win := _winner == "ally"
	# 로직에 결과를 넘긴다 — 레이팅·연승·연승방지 갱신은 전부 Colosseum 이 한다.
	var r := Colosseum.apply_result(_mode, win, String(_foe.get("nick", "")))

	var vis := _vis()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = vis
	add_child(dim)

	# 원작 승패 아트 — popup_win_kr / popup_lose_kr (+ _bg). 전부 보유.
	var bgk := "scene_colosseum_popup_win_bg_kr" if win else "scene_colosseum_popup_lose_bg_kr"
	var fgk := "scene_colosseum_popup_win_kr" if win else "scene_colosseum_popup_lose_kr"
	var b := _spr(CO, bgk, Design.ASSET_SCALE)
	if b != null:
		b.position = Vector2(vis.x * 0.5, vis.y * 0.42)
		add_child(b)
	var f := _spr(CO, fgk, Design.ASSET_SCALE)
	if f != null:
		f.position = Vector2(vis.x * 0.5, vis.y * 0.42)
		add_child(f)

	var info := Label.new()
	var d := int(r.get("delta", 0))
	info.text = "%s%d점  →  %d점 (%s)\n%d연승" % [
		"+" if d >= 0 else "", d, int(r.get("rating_after", 0)),
		String((r.get("tier_after", {}) as Dictionary).get("name", "")), int(r.get("streak", 0))]
	info.size = Vector2(vis.x, 60.0)
	info.position = Vector2(0.0, vis.y * 0.42 + 90.0)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 24)
	add_child(info)

	# 원작 `ColosseumTierupPopup` — 승급/강등이 있으면 결과 위에 띄운다.
	if bool(r.get("tier_up", false)) or bool(r.get("tier_down", false)):
		ColosseumTierupPopup.open(self, r)

	AtlasUI.frame_button(self, "확인", Vector2(vis.x * 0.5 - 90.0, vis.y - 130.0),
		Vector2(180.0, 48.0), func() -> void:
			Scenes.goto("colosseum", {"from": "fight"}))


# ---------- 헬퍼 ----------

## 원작 `FightManager::getFightTimeScale()` — 배속 버튼이 정하는 재생 속도로 대기를 줄인다.
func _wait(sec: float) -> void:
	await get_tree().create_timer(maxf(0.01, sec / float(maxi(1, _speed)))).timeout

func _vis() -> Vector2:
	return get_viewport_rect().size

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}

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

func _nine9(key: String, sz_pt: Vector2, cap: Rect2, dir: String) -> NinePatchRect:
	var tex := _tex(dir, key)
	if tex == null:
		return null
	var inv := 1.0 / Design.ASSET_SCALE
	var l := cap.position.x * inv
	var t := cap.position.y * inv
	var cw := cap.size.x * inv
	var ch := cap.size.y * inv
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - ch)))
	np.size = sz_pt
	np.material = _pma
	return np
