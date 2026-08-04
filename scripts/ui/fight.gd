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
		var xs: Array = MY_X if mine else FOE_X
		var x := vis.x * float(xs[i % xs.size()])
		var y := vis.y * float(SLOT_Y[i % SLOT_Y.size()])

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
		var sp := PartySelect._spine_node(int(p.get("id", 0)), "adult", 170.0)
		var ap: AnimationPlayer = null
		if sp != null:
			# 스파인 기본 방향이 왼쪽이므로 **왼쪽 진영(내 팀)** 을 뒤집어 마주 보게 한다.
			if mine:
				sp.scale = Vector2(-absf(sp.scale.x), sp.scale.y)
			holder.add_child(sp)
			ap = _find_anim_player(sp)

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
			"node": holder, "bar": fill, "barh": barh, "name": nm, "anim": ap,
			"hp": int(p.get("hp_max", 1)), "hp_max": maxi(1, int(p.get("hp_max", 1))),
			"dead": false, "pos": Vector2(x, y), "mine": mine,
		}


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
		_float_text(v["pos"], "+%d" % heal, Color(0.5, 1.0, 0.5))
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
		for k in ["node", "barh", "name"]:
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


func _set_bar(v: Dictionary) -> void:
	var b = v.get("bar")
	if b is NinePatchRect and is_instance_valid(b):
		var r := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
		(b as NinePatchRect).size = Vector2(BAR_W * r, BAR_H)


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
# 규칙: 애니를 틀고 **그 길이 + 0.5초** 뒤 대기 모션으로 돌아온다.
#
# 접근 이동 = `MakeInterface::setAction`(action @01062fd4 머리) —
#     Delay → [ScaleTo(1.5) + MoveBy(offset)] → Delay(hold) → [ScaleTo(1.0) + MoveBy(-offset)]
# 공격자가 **앞으로 나가며 커졌다가 제자리로 돌아온다**. 배율·간격은 그대로 옮긴다.
const ATK_SCALE := 1.5              # 원작 ScaleTo(…, 1.5)
const ATK_LEAD := 0.5               # 원작이 애니 길이에 더하는 여유
const APPROACH := 120.0             # 상대 쪽으로 나가는 거리(우리 3v3 간격 기준)
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
	p.play(name)
	var dur := a.length
	# 원작: Delay(duration + 0.5) 뒤 "wait" 로 복귀.
	var gen := _gen
	get_tree().create_timer(dur + ATK_LEAD).timeout.connect(func() -> void:
		if gen != _gen or not is_instance_valid(p) or bool(v.get("dead", false)):
			return
		if p.has_animation(ANIM_IDLE):
			p.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
			p.play(ANIM_IDLE))
	return dur


## 공격자 접근 → 제자리 복귀.
##
## 원작 경로(디버그 아님): `BattleScene::basicAction` @00dcb1e8 이
##     setAction(delay, MakeInterface, actor, FightManager::getTarget(1),
##               getActorAction(), getHealthVariation(1), getHitAmount(), isSkillBlock, isMimic)
## 를 부르고, `MakeInterface::setAction` @01062fb4 은 `action` @01062fd4 의 얇은 래퍼다.
## `action` 머리의 안무 = Delay → [ScaleTo(1.5) + MoveBy(offset)] → Delay(hold)
##                        → [ScaleTo(1.0) + MoveBy(-offset)]  ⇒ **나갔다가 제자리로 돌아온다.**
## ⚠️ setAction 이 **target 을 인자로 받는다** — 고정 거리가 아니라 **대상 쪽으로** 간다.
func _approach(v: Dictionary, target: Dictionary, hold: float) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var home: Vector2 = v.get("pos", node.position)
	# 대상이 있으면 그쪽으로, 없으면 진영 방향으로 기본 거리만큼.
	var dx := APPROACH if bool(v.get("mine", false)) else -APPROACH
	if not target.is_empty():
		var tp: Vector2 = target.get("pos", home)
		var d := tp - home
		if absf(d.x) > 1.0:
			# 상대에게 완전히 겹치지 않도록 접근 거리에서 멈춘다(원작도 MoveBy 오프셋이다).
			dx = signf(d.x) * minf(APPROACH, absf(d.x) - 90.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "position", home + Vector2(dx, 0.0), MOVE_SEC)
	tw.tween_property(node, "scale", Vector2(ATK_SCALE, ATK_SCALE) * _base_scale(v), MOVE_SEC)
	tw.chain().tween_interval(maxf(0.1, hold))
	var tw2 := tw.chain()
	tw2.set_parallel(true)
	tw2.tween_property(node, "position", home, MOVE_SEC)
	tw2.tween_property(node, "scale", _base_scale(v), MOVE_SEC)


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
			_approach(atk, dfn, dur)
	# ⛔ 피격 모션 없음 — 원작에 트리거가 없다(위 주석). 피격은 데미지 숫자·HP 바로만 보인다.

	# 이펙트 스파인은 **드래곤 모션과 별개**로 얹힌다(원작 castSkill 이 그렇게 만든다).
	var at: Vector2 = dfn.get("pos", _vis() * 0.5) if not dfn.is_empty() else _vis() * 0.5
	match t:
		"skill":
			_skill_spine(int(ev.get("skill_id", 0)), at)
		"awaken":
			_awaken_fx(atk, at)
		_:
			if bool(ev.get("crit", false)) and not atk.is_empty():
				_critical_spine(atk, dfn)


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


## 크리티컬 이펙트 — 원작은 **드래곤마다 전용 크리티컬 스켈레톤**을 갖는다
## (`scenes/dragons/dragon_<id>_critical.tscn` 422종 · 각성본 `_e_critical` 111종 변환 완료).
## 배치 규약은 battle.gd::_critical_spine 과 같다: 대상 위 z=8, 공격 방향으로 X 반전.
func _critical_spine(atk: Dictionary, dfn: Dictionary) -> bool:
	var cid := int(atk.get("id", 0))
	var stage := "e_critical" if bool(atk.get("awakened", false)) else "critical"
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [cid, stage]
	if not ResourceLoader.exists(path):
		path = "res://scenes/dragons/dragon_%d_critical.tscn" % cid
		if not ResourceLoader.exists(path):
			return false
	var holder := Node2D.new()
	holder.z_index = 8                         # 원작 addChild(spine, 8, -2)
	holder.position = dfn.get("pos", _vis() * 0.5)
	# 원작 setScaleX(-…) — 부호가 핵심(공격 방향으로 뒤집는다).
	holder.scale = Vector2(-1.0 if bool(atk.get("mine", false)) else 1.0, 1.0)
	add_child(holder)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null:
		for cand in ["animation", "critical", "attack"]:
			if ap.has_animation(cand):
				ap.get_animation(cand).loop_mode = Animation.LOOP_NONE
				ap.play(cand)
				break
	var t := holder.create_tween()
	t.tween_interval(SKILL_SPINE_SEC)
	t.tween_callback(holder.queue_free)
	return true


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
