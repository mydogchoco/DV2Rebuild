extends Node
## 겹친 드래곤의 **앞뒤(깊이)** 를 실제 배선으로 A/B 캡처한다.
##
## 같은 판·같은 프레임에서 두 장을 찍는다:
##   `fight_depth_before.png` — 홀더 z 를 전부 0 으로 되돌린 **종전 상태**(부품 번호로 섞인다)
##   `fight_depth_after.png`  — `fight.gd::_apply_depth` 가 배분한 z 대역
## 로그로 각 드래곤의 발밑 y·대역 z·부품 z 범위도 같이 뱉는다(눈 말고 숫자로도 확인).
##
## 임시 오토로드로 등록해 부팅 경로에서 돈다 — 러너 `run_shot_fight_depth.py` 가 등록/해제한다.

const OUT := "res://scratch_shots/fight_depth_%s.png"

var _fight: Node = null


func _ready() -> void:
	await get_tree().process_frame
	# 부팅 씬(타이틀)을 숨긴다 — 드래곤 대역이 음수 z 라 그대로 두면 타이틀이 전부 덮는다.
	# (실제 게임에선 `Scenes.goto` 가 이전 씬을 `queue_free` 하므로 이 상황이 없다.)
	for c in get_tree().root.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
	_fight = (load("res://scenes/fight.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_fight)
	await get_tree().process_frame
	if not _fight.has_method("_apply_depth"):
		push_error("[shot] fight 씬을 못 찾았다")
		get_tree().quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	var party: Array = Colosseum.eligible_uids()
	if party.is_empty():
		party = UserDB.party()
	_fight.call("enter", {"mode": "team", "opponent": Colosseum.roll_match("team", rng),
		"party": party, "stage_element": "fire"})
	# 등장 연출 도중 — 단상(`STAND_Z`)·그림자가 배경 위, 드래곤 아래로 나오는지 확인용.
	await get_tree().create_timer(2.5).timeout
	await _capture("intro")
	# 등장 연출(단상 → 착지)이 끝나야 슬롯 좌표가 의미 있다.
	await get_tree().create_timer(3.5).timeout

	_dump()
	# ① 종전 상태 — 매 프레임 재배분을 끄고 홀더 z 를 0 으로 되돌린다.
	_fight.set_process(false)
	for v in _views():
		(v["node"] as Node2D).z_index = 0
		var barh = v.get("barh")
		if barh is CanvasItem:
			(barh as CanvasItem).z_index = 0
	await _capture("before")
	# ② 현재 구현
	_fight.set_process(true)
	_fight.call("_apply_depth")
	await _capture("after")
	get_tree().quit()


func _views() -> Array:
	var out: Array = []
	var views: Dictionary = _fight.get("_views")
	var tags: Array = views.keys()
	tags.sort()
	for k in tags:
		var v: Dictionary = views[k]
		var n = v.get("node")
		if n is Node2D and is_instance_valid(n):
			out.append(v)
	return out


## 드래곤별 발밑 y / 대역 z / 부품 z 범위.
func _dump() -> void:
	var views: Dictionary = _fight.get("_views")
	var tags: Array = views.keys()
	tags.sort()
	for k in tags:
		var v: Dictionary = views[k]
		var n = v.get("node")
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		var home: Vector2 = v.get("home", v.get("pos", Vector2.ZERO))
		var lo := [0]
		var hi := [0]
		_span(v.get("spine"), 0, lo, hi)
		print("[depth] %s  y=%.1f  z=%d  parts=[%d..%d]" %
			[k, home.y, (n as Node2D).z_index, lo[0], hi[0]])


func _span(n, base: int, lo: Array, hi: Array) -> void:
	if not (n is Node):
		return
	var z := base
	if n is CanvasItem:
		z = base + (n as CanvasItem).z_index if (n as CanvasItem).is_z_relative() \
			else (n as CanvasItem).z_index
		lo[0] = mini(lo[0], z)
		hi[0] = maxi(hi[0], z)
	for c in (n as Node).get_children():
		_span(c, z, lo, hi)


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://scratch_shots")
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT % tag))
	print("[write] ", OUT % tag)
