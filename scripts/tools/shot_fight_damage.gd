extends Node
## 콜로세움 전투 화면에서 **피해 수치 두 층 + 노란 별**을 실제 배선으로 캡처한다.
##
## 각성기 한 판을 기다리는 대신, 살아 있는 `fight.gd` 의 뷰에 대고
## `_hit_number` / `_total_number` / `_damaged_particle` 을 원작 `mixingDamage` 와 같은 순서로
## 직접 부른다(잔타 N회 → 마지막 타). 레퍼런스 = 각성기 영상의 불 속성 구간 +4.2~+6.0초.
##
## 임시 오토로드로 등록해 부팅 경로에서 돈다(`--script` 모드엔 오토로드가 없다) —
## 러너 `scripts/tools/run_shot_fight_damage.py` 가 등록/해제를 책임진다.
## 산출 = `scratch_shots/fight_damage_<n>.png`

const OUT := "res://scratch_shots/fight_damage_%d.png"

var _fight: Node = null
var _shot := 0


func _ready() -> void:
	await get_tree().process_frame
	# `Scenes.goto` 는 상태 전이 규칙(`_allowed`)을 타므로 오토로드에서 곧장 부르면 막힌다.
	# 캡처용이니 씬만 그대로 얹는다.
	_fight = (load("res://scenes/fight.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_fight)
	await get_tree().process_frame
	if not _fight.has_method("_hit_number"):
		push_error("[shot] fight 씬을 못 찾았다")
		get_tree().quit(1)
		return
	# 상대는 `colosseum.gd` 와 같은 경로로 뽑는다(빈 opponent 면 적 뷰가 아예 안 생긴다).
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	var party: Array = Colosseum.eligible_uids()
	if party.is_empty():
		party = UserDB.party()
	_fight.call("enter", {"mode": "team", "opponent": Colosseum.roll_match("team", rng),
		"party": party, "stage_element": "fire"})
	await get_tree().create_timer(0.5).timeout
	# 등장 연출이 끝나기를 기다린다(드래곤이 슬롯에 앉아야 좌표가 의미 있다).
	await get_tree().create_timer(4.0).timeout
	await _burst()
	get_tree().quit()


func _find_fight(n: Node) -> Node:
	if n.has_method("_hit_number") and n.has_method("_total_number"):
		return n
	for c in n.get_children():
		var r := _find_fight(c)
		if r != null:
			return r
	return null


## 원작 `mixingDamage` 순서 그대로 — 잔타마다 (낱타 수치 + 누계 갱신 + 별), 마지막에 마무리 타.
func _burst() -> void:
	var views: Dictionary = _fight.get("_views")
	var targets: Array = []
	for k: String in views.keys():
		var v: Dictionary = views[k]
		if not bool(v.get("mine", false)) and not bool(v.get("dead", false)):
			targets.append(v)
	if targets.is_empty():
		push_error("[shot] 상대 뷰가 없다")
		return
	for i in 9:
		for v: Dictionary in targets:
			_fight.call("_hit_number", v, str(20 + i * 7))
			_fight.call("_total_number", v, 20 + i * 7, false)
			_fight.call("_damaged_particle", v)
		if i == 1 or i == 6:
			await _capture()            # 별이 살아 있는 동안(수명 0.15s) 바로 찍는다
		await get_tree().create_timer(0.18).timeout
	for v: Dictionary in targets:
		_fight.call("_hit_number", v, "374")
		_fight.call("_total_number", v, 374, true)
		_fight.call("_damaged_particle", v)
	await get_tree().create_timer(0.06).timeout
	await _capture()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://scratch_shots")
	var img := get_viewport().get_texture().get_image()
	_shot += 1
	img.save_png(ProjectSettings.globalize_path(OUT % _shot))
	print("[write] ", OUT % _shot)
