class_name TutorialGuide
extends CanvasLayer
## 오프닝 튜토리얼 — 원작 `ScenarioLayer` 의 시나리오 0 상태기계 이식. render 층(§8).
##
## ## 원작 구조
##
## 튜토리얼은 **독립 씬이 아니라 씬 위에 얹힌 레이어**다. `ScenarioLayer::setNextSelecteMode`
## @016caaac 이 `SN_0_<대사번호>[_<하위>]` 키로 분기하며
##   · `setScNextArrow(delay, pos, rotation, parent)` 로 안내 화살표를 띄우고
##   · 대상 버튼의 **복제본**(`CCMenuItemImageEx` + `onClickBtnListener`)만 눌리게 하고
##   · `CaveScene::scene(0)` · `AdventureScene::scene(1,4)` · `onClickNicName` 같은 씬 훅을 건다.
## 스텝 표와 대사는 `data/tutorial_flow.json`(추출 = `extract_tutorial_flow.py`, 근거 주석은 그 파일).
##
## ## 우리 구조
##
## 씬을 갈아타도 살아 있어야 하므로 **`Main` 이 소유**한다(`Scenes` 는 `$SceneRoot` 만 바꾼다).
## 진행도는 `UserDB` 의 `meta.tutorial_step`(스텝 키) — 껐다 켜도 이어진다.
##
## ## 화살표 (원작 `setScNextArrow` + `setArrowForever` 축자 이식)
##
##   프레임 `common/btn_arrow2.png`, opacity 0 으로 놓고
##   `Delay(delay)` → `Spawn(FadeIn(0.3), 맥동)`,  맥동 = `RepeatForever(ScaleTo(0.5,1.5), ScaleTo(0.5,1.0))`
##   회전은 도 단위, **180 만 회전 대신 `setFlipX(true)`** 다.

const ARROW_TEX := "res://assets/converted/common_ui/common_btn_arrow2.tres"
const BOX_H := 132.0                    # 대사 상자 높이(프롤로그 텍스트박스와 같은 규격)
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const STEP_KEY := "tutorial_step"       # UserDB meta — 다음에 실행할 스텝 키
const DONE_KEY := "tutorial_done"

## 아직 이식하지 않은 스텝은 **조용히 건너뛰지 않고** 로그를 남긴다 — 빠뜨린 걸 표면화한다.
signal finished

var _steps: Dictionary = {}
var _order: Array = []
var _i := 0
var _box: Control
var _label: Label
var _arrows: Array[Node] = []
var _blocked := false      # 씬 훅 대기 중(입력을 우리가 먹지 않는다)
## 이 스텝은 **대상을 눌러야** 넘어간다(화살표가 가리키는 것). 대사 상자 탭으로는 안 넘어간다.
var _wait_target: Node = null


## 진행 중인 튜토리얼이 있으면 붙인다. 없으면 null.
static func resume(host: Node) -> TutorialGuide:
	if bool(UserDB.get_pmeta(DONE_KEY, false)):
		return null
	if String(UserDB.get_pmeta(STEP_KEY, "")) == "":
		return null
	return start(host)


## 처음부터 시작.
static func start(host: Node) -> TutorialGuide:
	var g := TutorialGuide.new()
	g.layer = 60
	host.add_child(g)
	return g


func _ready() -> void:
	var doc: Dictionary = Data.tutorial_flow
	_steps = doc.get("steps", {})
	_order = doc.get("order", [])
	if _order.is_empty():
		push_warning("[tutorial] data/tutorial_flow.json 이 비었다 — extract_tutorial_flow.py 실행 필요")
		queue_free()
		return
	var saved := String(UserDB.get_pmeta(STEP_KEY, ""))
	_i = maxi(0, _order.find(saved)) if saved != "" else 0
	_build_box()
	_run()


# ── 화면 ──────────────────────────────────────────────────────────────────────
func _build_box() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	_box = Control.new()
	_box.size = Vector2(vis.x, BOX_H)
	_box.position = Vector2(0.0, vis.y - BOX_H)
	_place_box()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP     # 상자를 누르면 다음 대사
	add_child(_box)
	var np := NinePatchRect.new()
	np.texture = load(DIALOG_BOX)
	np.patch_margin_left = 20; np.patch_margin_top = 20
	np.patch_margin_right = 11; np.patch_margin_bottom = 11
	np.size = _box.size
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(np)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(34.0, 16.0)
	_label.size = Vector2(vis.x - 68.0, BOX_H - 32.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_label)
	var btn := Button.new()
	btn.flat = true
	btn.size = _box.size
	# 화살표가 가리키는 대상이 있는 스텝은 **그것을 눌러야** 넘어간다(원작 조건) — 상자 탭 무시.
	btn.pressed.connect(func(): if _wait_target == null: _advance())
	_box.add_child(btn)


## 대사 상자를 **하단 메뉴바 위로** 올린다.
## 원작 시나리오 텍스트박스는 화면 맨 아래인데, 우리 메인 화면의 하단바는 레퍼런스에서 잘라낸
## **통짜 이미지**(`mainbar_ui/bottom_bar`, §10)라 상자가 그 위에 겹치면 메뉴 글자가 통째로
## 가려진다 — 그런데 튜토리얼이 "저 메뉴를 눌러라"라고 말하는 중이다. 그래서 바가 있는 화면에서만
## 그만큼 띄운다(바가 없는 화면은 원작대로 맨 아래).
func _place_box() -> void:
	if not is_instance_valid(_box):
		return
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var y := vis.y - BOX_H
	var bar := _find_guide_target(get_tree().root, "bottom_bar")
	if bar != null:
		y = minf(y, bar.get_global_rect().position.y - BOX_H)
	_box.position = Vector2(0.0, maxf(0.0, y))


## 원작 `setScNextArrow` — 대상 노드 위에 맥동하는 화살표.
func _arrow(target: Control, spec: Dictionary) -> void:
	var tex := load(ARROW_TEX) if ResourceLoader.exists(ARROW_TEX) else null
	if tex == null or not is_instance_valid(target):
		return
	var a := Sprite2D.new()
	a.texture = tex
	a.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	a.modulate.a = 0.0
	if bool(spec.get("flip_x", false)):
		a.flip_h = true                                   # 원작: 180°는 회전이 아니라 setFlipX
	else:
		a.rotation_degrees = float(spec.get("rot", 0))
	# 대상의 화면 중심에 놓는다(원작은 대상 노드의 position 을 그대로 쓴다).
	var r := target.get_global_rect()
	a.position = r.position + r.size * 0.5
	add_child(a)
	_arrows.append(a)
	var t := a.create_tween()
	t.tween_interval(float(spec.get("delay", 0.0)))
	t.tween_property(a, "modulate:a", 1.0, 0.3)
	t.tween_callback(func():
		var p := a.create_tween().set_loops()
		p.tween_property(a, "scale", Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5, 0.5)
		p.tween_property(a, "scale", Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE), 0.5))


func _clear_arrows() -> void:
	for a in _arrows:
		if is_instance_valid(a):
			a.queue_free()
	_arrows.clear()


# ── 진행 ──────────────────────────────────────────────────────────────────────
func _cur() -> Dictionary:
	return _steps.get(String(_order[_i]), {}) if _i < _order.size() else {}


func _run() -> void:
	_clear_arrows()
	if _i >= _order.size():
		_finish()
		return
	var key := String(_order[_i])
	var st: Dictionary = _steps.get(key, {})
	UserDB.set_pmeta(STEP_KEY, key)
	var text := String(st.get("text", ""))
	_label.text = text
	_box.visible = text != ""
	_place_box()          # 씬마다 하단바 유무가 달라 매 스텝 다시 잡는다
	# 안내 화살표 — 대상을 찾을 수 있을 때만(못 찾으면 대사만 보여 주고 넘어간다).
	var target := _target_for(st)
	_wait_target = null
	if target != null:
		for spec in st.get("arrows", []):
			_arrow(target, spec)
		# 원작은 대상 버튼의 **복제본**을 만들어 그것만 눌리게 한다(`onClickBtnListener`).
		# 우리는 진짜 버튼을 그대로 쓰되, 그 클릭이 다음 스텝으로 넘어가게 건다
		# ⇒ "화살표가 가리키는 것을 눌러야 진행" 이라는 원작의 조건이 그대로 성립한다.
		if target is BaseButton and not st.get("arrows", []).is_empty():
			_wait_target = target
			if not (target as BaseButton).pressed.is_connected(_advance):
				(target as BaseButton).pressed.connect(_advance, CONNECT_ONE_SHOT)
	_dispatch(String(st.get("action", "")))


## 스텝이 가리키는 화면 요소. 원작은 대상 **프레임의 복제 버튼**을 만들어 짚지만, 우리는
## 노드 구성이 달라 복제본을 만들면 원작에 없는 가짜 버튼이 하나 더 생긴다 → 씬이 등록해 둔
## 진짜 노드(`guide_target`)를 짚는다. id 와 그 근거는 `data/tutorial_flow.json` 의
## `target`/`target_basis`(추출 = extract_tutorial_flow.py).
func _target_for(st: Dictionary) -> Control:
	var id := String(st.get("target", ""))
	if id == "":
		return null
	return _find_guide_target(get_tree().root, id)


## 씬(또는 그 자식 HUD)이 노출한 `guide_target(id)` 를 찾는다.
func _find_guide_target(n: Node, id: String) -> Control:
	if n.has_method("guide_target"):
		var r = n.call("guide_target", id)
		if r is Control and is_instance_valid(r):
			return r
	for c in n.get_children():
		var r2 := _find_guide_target(c, id)
		if r2 != null:
			return r2
	return null


## 원작 씬 훅. 아직 이식 안 한 것은 **경고를 남기고** 다음 스텝으로 간다(조용한 누락 금지).
func _dispatch(action: String) -> void:
	match action:
		"":
			pass
		"enter_cave":
			# 원작 `SN_0_14_2` — `CCTransitionFade(0.51, CaveScene::scene(0))` 로 **푸시**.
			_blocked = true
			_box.visible = false
			Scenes.goto("cave", {})
			await get_tree().process_frame
			_blocked = false
			_advance()
		"adventure":
			_start_tutorial_battle()
		"finish":
			_finish()
		_:
			push_warning("[tutorial] 미이식 스텝 동작 '%s' (%s) — 건너뛴다"
				% [action, String(_order[_i])])


## 원작 `SN_0_26` = `AdventureScene::scene(1, 4)` — 시나리오 모드(FieldType 1)로 전투 4 진입.
##
## ⚠️ **상대는 복원 불가**다. `data/story_battles.json` 의 `monster_by_battle` 는 원작
## `AdventureScene` 의 `switch(battleNo)` 를 그대로 뽑은 것인데 **15번부터** 있고, 1~14 는
## default 분기라 런타임(서버) 값이다(그 파일 `_monster_basis`). 같은 파일의
## `monster_by_battle_event` 는 **이벤트 번호** 표라 battleNo 4 에 갖다 붙이면 근거 없는 교차매핑이다.
## ⇒ 상대는 `data/tutorial_flow.json` 의 `battle` 블록(사용자가 채우는 자리)에서 읽고,
##    비어 있으면 **전투를 건너뛴다**(지어내지 않는다 — HARD RULE 6).
func _start_tutorial_battle() -> void:
	var spec: Dictionary = Data.tutorial_flow.get("battle", {})
	var mid := int(spec.get("monster_id", 0))
	if mid <= 0:
		push_warning("[tutorial] 튜토리얼 전투 상대 미정 — data/tutorial_flow.json 의 `battle.monster_id` "
			+ "를 채우면 이 스텝에서 전투가 붙는다(원작 battleNo 4 는 서버 런타임 값이라 복원 불가)")
		return
	var enemy := Data.story_enemy_of(mid, int(spec.get("level", 1)))
	if enemy.is_empty():
		push_warning("[tutorial] 몬스터 %d 정의를 못 찾았다 — 전투를 건너뛴다" % mid)
		return
	_blocked = true
	_box.visible = false
	_clear_arrows()
	# 전투가 끝나면 우리가 다시 이어받는다. `Main` 소유라 씬이 바뀌어도 이 노드는 산다.
	if not Scenes.state_changed.is_connected(_on_scene_changed):
		Scenes.state_changed.connect(_on_scene_changed)
	Scenes.goto("battle", {"enemy": enemy, "back": "worldmap",
		"back_params": {"region": "yutakan"}})


## 전투 씬에서 나오면 다음 스텝으로. (원작도 전투가 끝나면 그 스텝 다음부터 잇는다.)
func _on_scene_changed(from_s: String, _to_s: String) -> void:
	if from_s != "battle":
		return
	Scenes.state_changed.disconnect(_on_scene_changed)
	_blocked = false
	_advance()


func _advance() -> void:
	if _blocked:
		return
	_i += 1
	_run()


func _finish() -> void:
	_clear_arrows()
	UserDB.set_pmeta(DONE_KEY, true)
	UserDB.set_pmeta(STEP_KEY, "")
	finished.emit()
	queue_free()
