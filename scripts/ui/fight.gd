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

# 원작 3v3 배치 — 좌(내 팀) / 우(상대). 카드가 아니라 스파인이라 바닥선을 맞춘다.
# 뒤(위)→앞(아래)으로 갈수록 바깥쪽에 놓아 서로 가리지 않게 한다.
# ⚠️ 3번째 슬롯을 0.82 에 두면 하단 로그 박스(원작 ColosseumTextBox)와 겹친다 — 0.74 까지만.
const SLOT_Y := [0.44, 0.59, 0.74]      # 화면 높이 비율
const MY_X := [0.30, 0.19, 0.08]
const FOE_X := [0.70, 0.81, 0.92]
# ⚠️ 드래곤 스파인의 **기본 방향은 왼쪽**이다(실측 2026-08-04 — 처음엔 반대로 알고
#   상대만 뒤집었더니 우리 팀이 등을 보였다). 그래서 **왼쪽에 서는 내 팀**을 뒤집는다.
# `PartySelect._spine_node` 는 **holder 원점 = 스프라이트 바닥 중앙**으로 맞춘다
# (party_select.gd:115 `inst.position -= …`). 그래서 바는 원점 바로 아래에 둔다.
const BAR_DY := 12.0
const BAR_W := 168.0
const BAR_H := 16.0

var _pma: CanvasItemMaterial
var _params: Dictionary = {}
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
		var xs: Array = MY_X if mine else FOE_X
		var x := vis.x * float(xs[i % xs.size()])
		var y := vis.y * float(SLOT_Y[i % SLOT_Y.size()])

		var holder := Node2D.new()
		holder.position = Vector2(x, y)
		add_child(holder)

		var sp := PartySelect._spine_node(int(p.get("id", 0)),
			"adult" if int(p.get("level", 1)) >= 30 else "child", 170.0)
		if sp != null:
			# 스파인 기본 방향이 왼쪽이므로 **왼쪽 진영(내 팀)** 을 뒤집어 마주 보게 한다.
			if mine:
				sp.scale = Vector2(-absf(sp.scale.x), sp.scale.y)
			holder.add_child(sp)

		# 이름 + HP 바 — 원작 9patch/bar_bg2 + bar1(둘 다 보유). 발밑에 놓는다.
		var barh := Control.new()
		barh.position = Vector2(x - BAR_W * 0.5, y + BAR_DY)
		add_child(barh)
		var bar_bg := _nine("9patch_bar_bg2", Vector2(BAR_W, BAR_H), Rect2(12, 6, 4, 4))
		if bar_bg != null:
			barh.add_child(bar_bg)
		var fill := _nine("9patch_bar1" if mine else "9patch_bar3",
			Vector2(BAR_W, BAR_H), Rect2(12, 6, 4, 4))
		if fill != null:
			barh.add_child(fill)

		var nm := Label.new()
		nm.text = "%s  Lv.%d" % [String(p.get("name", "")), int(p.get("level", 1))]
		nm.size = Vector2(BAR_W, 20.0)
		nm.position = Vector2(x - BAR_W * 0.5, y + BAR_DY + BAR_H + 2.0)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 15)
		add_child(nm)

		_views[tag] = {
			"node": holder, "bar": fill, "barh": barh, "name": nm,
			"hp": int(p.get("hp_max", 1)), "hp_max": maxi(1, int(p.get("hp_max", 1))),
			"dead": false, "pos": Vector2(x, y),
		}


# ---------- 상단 정보(원작 ColosseumFightInitWidget) ----------

func _build_top(vis: Vector2) -> void:
	var rating := Colosseum.rating_of(_mode)
	_side_plate(UserDB.user_nickname(), rating, 20.0, vis)
	_side_plate(String(_foe.get("nick", "")), int(_foe.get("rating", 0)),
		vis.x - 20.0 - 330.0, vis)

	# 가운데 VS — 원작 fight_spine 미변환이라 보유 프레임 vs/vs_bg 로 낸다.
	var vb := _spr(CO, "scene_colosseum_vs_bg", Design.ASSET_SCALE)
	if vb != null:
		vb.position = Vector2(vis.x * 0.5, 56.0)
		add_child(vb)
	var v := _spr(CO, "scene_colosseum_vs", Design.ASSET_SCALE)
	if v != null:
		v.position = Vector2(vis.x * 0.5, 56.0)
		add_child(v)


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
	_say("%s 와(과)의 대전!" % String(_foe.get("nick", "")))
	await _wait(1.0)
	if gen != _gen: return
	for ev in _events:
		_apply(ev)
		await _wait(0.45)
		if gen != _gen: return
	await _wait(0.5)
	if gen != _gen: return
	_finish()


## 이벤트 1건을 화면에 반영 — HP 감소 · 데미지 숫자 · 사망 처리.
func _apply(ev: Dictionary) -> void:
	var t := String(ev.get("type", ""))
	var dfn := String(ev.get("defender", ev.get("target", "")))
	var dmg := int(ev.get("damage", 0))
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]
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
		_float_text(v["pos"], "+%d" % heal, Color(0.5, 1.0, 0.5))
	if bool(ev.get("dead", false)) and not bool(v["dead"]):
		v["dead"] = true
		# 스파인만 지우면 **빈 HP 바와 이름표가 허공에 남는다**(2026-08-04 스크린샷에서 확인).
		# 셋을 함께 없앤다.
		for k in ["node", "barh", "name"]:
			var n = v.get(k)
			if n != null and is_instance_valid(n):
				create_tween().tween_property(n, "modulate:a", 0.0, 0.45)
	if t == "skill":
		_say("%s 발동!" % String(ev.get("skill_name", "스킬")))


func _set_bar(v: Dictionary) -> void:
	var b = v.get("bar")
	if b is NinePatchRect and is_instance_valid(b):
		var r := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
		(b as NinePatchRect).size = Vector2(BAR_W * r, BAR_H)


func _float_text(pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos + Vector2(-16.0, -60.0)
	l.add_theme_font_size_override("font_size", 26)
	l.modulate = col
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 44.0, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
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

	if bool(r.get("tier_up", false)):
		# 원작 ColosseumTierupPopup 자리 — 아직 이식 전이라 문구로 알린다.
		var up := Label.new()
		up.text = "티어 승급!  %s" % String((r.get("tier_after", {}) as Dictionary).get("name", ""))
		up.size = Vector2(vis.x, 40.0)
		up.position = Vector2(0.0, vis.y * 0.42 + 150.0)
		up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		up.add_theme_font_size_override("font_size", 26)
		up.modulate = Color(1.0, 0.9, 0.4)
		add_child(up)

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
