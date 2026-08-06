extends Node
## 피해 수치 + 노란 별 확인 창 — **대전에서 실제로 뜨는 것**을 손으로 눌러 본다.
##
## `dev_ultimate_fx.gd` 와 같은 원칙: 여기서 보는 그림이 곧 대전 화면이다.
## 이 창은 `scenes/fight.tscn` 을 **그대로 띄우고** 그 안의
## `_hit_number` / `_total_number` / `_damaged_particle` 을 직접 부른다 ⇒ 별도 사본이 없다.
##
## 실행: godot --path . res://scenes/dev_damage_number.tscn
##   1 = 단타(낱타만)  · 2 = 크리티컬(낱타 + 누계 1회)  · 3/SPACE = 각성기 연타(누계 누적)
##   4 = 회복(+N)      · R = 전투 다시 시작              · ESC = 종료
##
## ## 무엇을 봐야 하나 (원작 `MakeInterface::showDamage` @010910ac)
##   · 작은 **흰** 숫자 = `font/font_normal.fnt`(size 56) — 대상 둘레 ±100×±30 산포,
##     2.0→1.0 팝 → 0.25초 정지 → 위로 75 떠오르며 사라짐
##   · 큰 **금색** 숫자 = `font/font_total.fnt`(size 93) — 슬롯 + (0, 배율×235),
##     타격마다 누적되며 1.75→1.0 재팝. **단타에는 안 뜬다**(1번과 2번을 비교할 것)
##   · **노란 오각별** = `damagedEffect` @0108f4cc 의
##     `particle/scene/colosseum/effect_damaged.plist`(수명 0.15s · 속도 1000 · 배율 0.75)
##   상세 = `docs/ref/porting/ColosseumDamageNumber.md`

const HELP := "1 단타   2 크리티컬   3/SPACE 각성기 연타   4 회복   R 재시작   ESC 종료"

var _busy := false


func _ready() -> void:
	# ⚠️ 씬을 직접 instantiate 하면 안 된다 — 전투가 끝난 뒤 결과창의 '로비로' 버튼이
	#   `Scenes.goto("colosseum")` 을 부르는데, root 가 안 묶여 있으면 그때 조용히 실패한다
	#   (실제로 그렇게 한 번 만들었다가 로그가 `[Scenes] root 미바인딩` 으로 도배됐다).
	#   컨테이너를 묶어 두면 전투 → 로비 → 전투 왕복이 대전과 똑같이 돈다.
	var holder := Node.new()
	holder.name = "SceneHolder"
	add_child(holder)
	Scenes.bind_root(holder)
	await get_tree().process_frame
	_enter_fight()
	_build_help()


func _enter_fight() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var party: Array = Colosseum.eligible_uids()
	if party.is_empty():
		party = UserDB.party()
	# 무대는 불로 고정 — 레퍼런스 영상(각성기 mp4)의 첫 구간과 같은 배경이라 대조하기 쉽다.
	Scenes.goto("fight", {"mode": "team", "opponent": Colosseum.roll_match("team", rng),
		"party": party, "stage_element": "fire"})


## R — 다시 한 판. `fight → fight` 는 전이표에 없으므로 로비를 한 번 거친다(원작 경로와 같다).
func _restart() -> void:
	if Scenes.current_state() == "fight":
		Scenes.goto("colosseum")
	_enter_fight()


func _build_help() -> void:
	var l := Label.new()
	l.text = HELP
	l.position = Vector2(12, 4)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.z_index = 4096
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := CanvasLayer.new()
	cl.layer = 128
	add_child(cl)
	cl.add_child(l)


## 지금 화면의 전투 씬(로비에 있으면 null).
func _fight_scene() -> Node:
	var s := Scenes.current_scene()
	return s if s != null and is_instance_valid(s) and s.has_method("_hit_number") else null


## 살아 있는 상대 뷰들. 없으면 빈 배열.
func _targets() -> Array:
	var f := _fight_scene()
	if f == null:
		return []
	var views: Dictionary = f.get("_views")
	var out: Array = []
	for k: String in views.keys():
		var v: Dictionary = views[k]
		if not bool(v.get("mine", false)) and not bool(v.get("dead", false)):
			out.append(v)
	return out


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not (e as InputEventKey).pressed or e.is_echo():
		return
	match (e as InputEventKey).keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_R:
			_restart()
		KEY_1:
			_single(false)
		KEY_2:
			_single(true)
		KEY_3, KEY_SPACE:
			_ultimate()
		KEY_4:
			_heal()


## 단타 — 원작에서 낱타 수치만 뜬다. `crit` 이면 누계 라벨이 **한 번 떴다 사라진다**
## (`ActionType` 0x29~0x2b + `Dragon::getCriticalHit()==1` 분기).
func _single(crit: bool) -> void:
	var f := _fight_scene()
	for v: Dictionary in _targets():
		var dmg := randi_range(40, 180)
		f.call("_hit_number", v, str(dmg))
		f.call("_total_number", v, dmg, true, crit)
		f.call("_damaged_particle", v)


## 각성기 — 원작 `mixingDamage` 순서 그대로 잔타마다 (낱타 + 누계 + 별), 마지막에 마무리 타.
func _ultimate() -> void:
	if _busy:
		return
	_busy = true
	for i in 12:
		var f := _fight_scene()
		if f == null:
			break
		for v: Dictionary in _targets():
			var a := randi_range(15, 70)
			f.call("_hit_number", v, str(a))
			f.call("_total_number", v, a, false)
			f.call("_damaged_particle", v)
		await get_tree().create_timer(0.16).timeout
	var fin := _fight_scene()
	if fin != null:
		for v: Dictionary in _targets():
			var last := randi_range(300, 500)
			fin.call("_hit_number", v, str(last))
			fin.call("_total_number", v, last, true)
			fin.call("_damaged_particle", v)
	_busy = false


func _heal() -> void:
	var f := _fight_scene()
	for v: Dictionary in _targets():
		f.call("_hit_number", v, "+%d" % randi_range(30, 250), true)
