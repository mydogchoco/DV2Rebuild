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

		var sp := PartySelect._spine_node(int(p.get("id", 0)), "adult", DRAGON_H)
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

		var hud := _make_hud(p, Vector2(x, y), 1.0 if _mode != "team" else DRAGON_SCALE_TEAM)
		add_child(hud["root"])

		_views[tag] = {
			"node": holder, "bar": hud["fill"], "barh": hud["root"],
			"name": hud["name_label"], "hp_label": hud["hp_label"], "anim": ap,
			"hp": int(p.get("hp_max", 1)), "hp_max": maxi(1, int(p.get("hp_max", 1))),
			"dead": false, "pos": Vector2(x, y), "mine": mine,
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
const HUD_ELEM_POS := Vector2(17.5, 19.75)
const HUD_ELEM_W := 28.5

func _make_hud(p: Dictionary, at: Vector2, dragon_scale := 1.0) -> Dictionary:
	var S := Design.ASSET_SCALE
	var root := Node2D.new()
	# 원작 pos = 레이어중심 + (0, h*0.5 + 100) = **레이어 꼭대기에서 100pt 위**.
	# ⚠️ 그 100 은 원작 드래곤 레이어 크기 기준이라 우리 정규화 높이(170)에 그대로 쓰면
	#   HUD 가 위 슬롯까지 올라간다. 구조·프레임·내부 오프셋은 원작 그대로 두고
	#   **머리 위 여백만** 우리 배치에 맞춘다(= 레이어 꼭대기 + HUD_LIFT).
	# `PartySelect._spine_node` 규약상 holder 원점 = 스프라이트 **바닥 중앙**이다.
	root.position = at + Vector2(0.0, -(DRAGON_H * dragon_scale + HUD_LIFT))

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

	# 이름 — 원작 anchor(0,0), pos = cover + (-coverW*0.5, coverH*0.5) = **cover 좌상단**, scale 0.5.
	var nm := Label.new()
	nm.text = String(p.get("name", ""))
	nm.position = Vector2(-cover_w * 0.5, -cover_h * 0.5 - 21.0)
	_bm_style(nm, 16, Color.WHITE)
	root.add_child(nm)

	# 레벨 — 원작은 이름 오른쪽(anchor 0.65,0.85). 우리는 이름 폭을 런타임에 못 재므로
	#   cover 오른쪽 끝에 맞춘다(같은 줄·오른쪽이라는 성질은 같다).
	var lv := Label.new()
	lv.text = "Lv.%d" % int(p.get("level", 1))
	lv.size = Vector2(cover_w, 20.0)
	lv.position = Vector2(-cover_w * 0.5, -cover_h * 0.5 - 21.0)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bm_style(lv, 14, Color(1.0, 0.92, 0.6))
	root.add_child(lv)

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

	return {"root": root, "fill": fill, "hp_label": hp, "name_label": nm}


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


# ---------- 상단 정보(원작 ColosseumFightInitWidget) ----------

func _build_top(vis: Vector2) -> void:
	var rating := Colosseum.rating_of(_mode)
	_side_plate(UserDB.user_nickname(), rating, 20.0, vis)
	_side_plate(String(_foe.get("nick", "")), int(_foe.get("rating", 0)),
		vis.x - 20.0 - 330.0, vis)

	# 상단 가운데 VS 표식(상시). 개시 연출은 `_vs_intro()` 가 따로 낸다.
	var vb := _spr(CO, "scene_colosseum_vs_bg", Design.ASSET_SCALE)
	if vb != null:
		vb.position = Vector2(vis.x * 0.5, 56.0)
		add_child(vb)
	var v := _spr(CO, "scene_colosseum_mini_vs", Design.ASSET_SCALE)
	if v != null:
		v.position = Vector2(vis.x * 0.5, 56.0)
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


## 한쪽 진영의 프로필 판 — 원작 `profilebox` + `common/tier_icon_*`.
func _side_plate(nick: String, rating: int, x: float, _vis: Vector2) -> void:
	var h := Control.new()
	h.position = Vector2(x, 16.0)
	h.size = Vector2(330.0, 80.0)
	add_child(h)
	var bg := _nine9("scene_colosseum_profilebox", h.size, Rect2(40, 30, 4, 4), CO)
	if bg != null:
		h.add_child(bg)
	var tf := Colosseum.tier_frame(rating, "icon")
	if tf != "":
		var ts := _spr(CM, "common_" + tf.get_slice("/", 1).replace(".png", ""),
			Design.ASSET_SCALE * 0.7)
		if ts != null:
			ts.position = Vector2(44.0, 40.0)
			h.add_child(ts)
	var l := Label.new()
	l.text = "%s\n%d점" % [nick, rating]
	l.position = Vector2(84.0, 16.0)
	l.add_theme_font_size_override("font_size", 19)
	h.add_child(l)


# ---------- 하단 로그(원작 ColosseumTextBox) ----------

func _build_log(vis: Vector2) -> void:
	var box := _nine("9patch_dialogue_box", Vector2(vis.x - 40.0, 66.0), Rect2(10, 10, 4, 4))
	var host := Control.new()
	host.position = Vector2(20.0, vis.y - 82.0)
	host.size = Vector2(vis.x - 40.0, 66.0)
	add_child(host)
	if box != null:
		host.add_child(box)
	_log = Label.new()
	_log.position = Vector2(22.0, 18.0)
	_log.add_theme_font_size_override("font_size", 19)
	host.add_child(_log)


func _say(t: String) -> void:
	if _log != null:
		_log.text = t


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
			_say("%s: %s" % [String(_foe.get("nick", "")), String(ln).replace("\n", " ")])
			await _wait(1.9)
			if gen != _gen: return
	_say("%s 와(과)의 대전!" % String(_foe.get("nick", "")))
	_vs_intro()                 # 원작 fight_spine("FIGHT!") 개시 연출
	await _wait(1.8)
	if gen != _gen: return
	for ev in _events:
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
	var dfn := String(ev.get("defender", ev.get("target", "")))
	var dmg := int(ev.get("damage", 0))
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]
	_motion(ev, t, String(ev.get("attacker", "")), dfn)   # 스파인 공격/피격 모션
	if bool(ev.get("miss", false)):
		_float_text(v["pos"], "MISS", Color(0.85, 0.9, 1.0))
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
	var l = (_views[tag] as Dictionary).get("name")
	return (l as Label).text.split("  ")[0] if l is Label else tag


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
	var tw := node.create_tween()
	for d: float in HIT_SHAKE:
		tw.tween_property(node, "position:x",
			node.position.x + d * dir, HIT_SHAKE_SEC).as_relative()
	tw.tween_property(node, "position", v.get("pos", node.position), 0.0)


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


## 한 이벤트의 스파인 연출 — 공격자/피격자를 함께 움직인다.
func _motion(ev: Dictionary, t: String, atk_tag: String, dfn_tag: String) -> void:
	var atk: Dictionary = _views.get(atk_tag, {})
	var dfn: Dictionary = _views.get(dfn_tag, {})
	if not atk.is_empty() and not bool(atk.get("dead", false)):
		# 원작 `castSkill` 은 종류를 가리지 않고 **"attack" 하나만** 튼다
		# (크리티컬·각성기용 별도 애니를 콜로세움 경로에서 부르지 않는다).
		var dur := _play_anim(atk, "attack")
		# 각성기는 제자리에서 낸다(원작도 UltimateLayer 가 화면을 덮는다).
		if t != "awaken":
			_attack_pulse(atk, dfn, dur)
	# 피격 반응 — **애니는 없지만 반응은 있다**(2026-08-05 `action` 코드지도로 확정).
	#   code 0(기본 피격) → `damagedColor` = 깜빡임
	#   code -32(중독)    → `damagedColor` + `shakeLayerToHorizontal`
	# 종전엔 "모션이 없다"를 "아무것도 안 한다"로 잘못 옮겨 피격이 전혀 안 보였다.
	if not dfn.is_empty() and not bool(dfn.get("dead", false)) 			and not bool(ev.get("miss", false)) and int(ev.get("damage", 0)) > 0:
		_damaged_color(dfn)
		if t == "poison" or bool(ev.get("crit", false)):
			# 흔들림 방향 = 맞은 쪽이 밀리는 방향(공격자 반대편).
			_shake_horizontal(dfn, 1.0 if bool(dfn.get("mine", false)) else -1.0)

	# 이펙트 스파인은 **드래곤 모션과 별개**로 얹힌다(원작 castSkill 이 그렇게 만든다).
	var at: Vector2 = dfn.get("pos", _vis() * 0.5) if not dfn.is_empty() else _vis() * 0.5
	match t:
		"skill":
			_skill_spine(int(ev.get("skill_id", 0)), at)
		"awaken":
			_awaken_fx(atk, at)
		_:
			if atk.is_empty():
				pass
			elif bool(ev.get("crit", false)):
				# 원작 크리티컬 연출(공용 포신 스파인)은 그대로 두고, 드빌1에서 온 종만
				# **자기 크리티컬 이펙트**를 위에 얹는다(800 로키 = `col_action2`).
				_critical_spine(atk, dfn)
				_dragon_fx_seq(int(atk.get("id", 0)), "col_action2", at)
			else:
				# 평타 — 드빌1에서 온 종만 전용 평타 이펙트를 갖는다(`col_action1`).
				# 없으면 아무것도 안 뜬다(원작 콜로세움 평타에도 이펙트가 없다).
				_dragon_fx_seq(int(atk.get("id", 0)), "col_action1", at)


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


## 크리티컬 이펙트 — 원작은 **드래곤마다 전용 크리티컬 스켈레톤**을 갖는다
## (`scenes/dragons/dragon_<id>_critical.tscn` 422종 · 각성본 `_e_critical` 111종 변환 완료).
## 배치 규약은 battle.gd::_critical_spine 과 같다: 대상 위 z=8, 공격 방향으로 X 반전.
## 크리티컬 컷인 — 원작 `MakeInterface::action` @01062fd4 의 크리티컬 분기.
##
## 🔴 2026-08-05 정정 — 종전엔 **공격한 드래곤의 `critical` 애니**를 피격 지점에 띄웠는데,
##   원작은 그게 아니라 **공용 이펙트 스파인 3종**을 화면 중앙에 세우는 컷인이다.
##   근거(`probe/action_asm.c` 줄 865~1270, adrp+add 로 복원한 .rodata 문자열):
##     `dragon/dragon_9999_critical_spine.spine_json`        ← 본체(init·ready·set·shot·walking)
##     `dragon/dragon_9999_critical_ready_spine.spine_json`  ← ready 전용 레이어
##     `dragon/dragon_9999_critical_shot_spine.spine_json`   ← shot 전용 레이어
##   `CCSkeletonAnimation::createWithFile` ×3 → `VisibleRect::center` / `right` 에 배치.
##
## 원작 시퀀스(호출 순서 그대로):
##   Delay → Show → runSpine("init", ×2.0) → MoveTo(0.75)
##   → runSpine("ready", ×1.125) → Delay(길이) → shakeLayerToVertical
##   → Delay(0.5) → runSpine("ready", ×1.5) → Delay(0.25)
##   → Spawn(Delay(길이), Shake(1.5, 0.5)) → runSpine("shot", ×1.5) → Delay(0.5)
##
## ⚠️ `_ready`/`_shot` 전용 스파인 2종은 아직 미변환(🟠)이다. 다만 **본체 스파인이 같은
##   `init`/`ready`/`shot` 애니를 전부 갖고 있어**(실측: init·ready·set·shot·walking)
##   한 장으로 같은 안무를 낸다. 2종을 변환하면 레이어만 더 얹으면 된다.
const CRIT_SCENE := "res://scenes/dragons/dragon_9999_critical.tscn"
const CRIT_INIT_SPEED := 2.0        # 원작 runSpine(…, "init", 2.0)
const CRIT_READY_SPEED := 1.125     # 원작 runSpine(…, "ready", 1.125)
const CRIT_SHOT_SPEED := 1.5        # 원작 runSpine(…, "shot", 1.5)
const CRIT_GAP := 0.25              # 원작 Delay(0.25)
const CRIT_SHAKE_SEC := 1.5         # 원작 Shake::actionWithDuration(1.5, 0.5)
const CRIT_SHAKE_AMP := 0.5

func _critical_spine(atk: Dictionary, _dfn: Dictionary) -> void:
	if not ResourceLoader.exists(CRIT_SCENE):
		return
	var vis := _vis()
	var holder := Node2D.new()
	holder.z_index = 8                         # 원작 addChild(spine, 8, -2)
	holder.position = vis * 0.5                # 원작 VisibleRect::center
	# 원작 setScaleX(-…) — 공격 방향으로 뒤집는다.
	holder.scale = Vector2(-1.0 if bool(atk.get("mine", false)) else 1.0, 1.0)
	add_child(holder)
	var inst = (load(CRIT_SCENE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap == null:
		holder.queue_free()
		return

	var gen := _gen
	var step := func(name: String, speed: float) -> float:
		if not ap.has_animation(name) or gen != _gen or not is_instance_valid(ap):
			return 0.0
		ap.get_animation(name).loop_mode = Animation.LOOP_NONE
		ap.play(name, -1.0, speed)
		return ap.get_animation(name).length / speed

	var t_init: float = step.call("init", CRIT_INIT_SPEED)
	await _wait(maxf(0.05, t_init))
	var t_ready: float = step.call("ready", CRIT_READY_SPEED)
	_shake_screen(CRIT_SHAKE_SEC * 0.4, CRIT_SHAKE_AMP)   # 원작 shakeLayerToVertical
	await _wait(maxf(0.05, t_ready) + CRIT_GAP)
	var t_shot: float = step.call("shot", CRIT_SHOT_SPEED)
	_shake_screen(CRIT_SHAKE_SEC, CRIT_SHAKE_AMP)         # 원작 Shake(1.5, 0.5)
	await _wait(maxf(0.3, t_shot) + 0.5)                  # 원작 마지막 Delay(0.5)
	if is_instance_valid(holder):
		holder.queue_free()


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

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

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
