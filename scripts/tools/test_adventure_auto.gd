extends SceneTree

var _fails := 0

const FRAMES := [
	"scene_adventure_btn2", "scene_adventure_btn3", "scene_adventure_btn4",
	"scene_adventure_glow_automode", "scene_adventure_glow_lefttop",
	"scene_adventure_glow_righttop", "scene_adventure_glow_leftdown",
	"scene_adventure_glow_rightdown", "scene_adventure_glow_length",
	"scene_adventure_glow_width",
]

var _btn: CounterButton

func _initialize() -> void:
	_test_frames()
	_test_timing()
	_test_geometry()
	_btn = CounterButton.make("scene_adventure_choice_continue_KR", true)
	root.call_deferred("add_child", _btn)

func _process(_delta: float) -> bool:
	_test_build()
	if _fails == 0:
		print("=== ALL PASS ===")
	else:
		print("=== %d FAIL ===" % _fails)
	quit(1 if _fails > 0 else 0)
	return true

func _test_frames() -> void:
	var man := AtlasUI.manifest(CounterButton.DIR)
	for k in FRAMES:
		_check(man.has(k), "매니페스트에 %s" % k)
		_check(AtlasUI.tex(CounterButton.DIR, k) != null, "텍스처 로드 %s" % k)

func _test_timing() -> void:
	_check(is_equal_approx(CounterButton.T_LONG, 0.3), "긴 변 0.3s")
	_check(is_equal_approx(CounterButton.T_SHORT, 0.12), "짧은 변 0.12s")
	var sum := 0.0
	for row in CounterButton._SEGS:
		sum += float((row as Array)[2])
	_check(abs(sum - CounterButton.LAP) < 0.0005, "조각 합 = LAP (%.4f)" % sum)
	_check(abs(CounterButton.LAP - 1.98) < 0.0005, "한 바퀴 1.98초")

func _test_geometry() -> void:
	var keys: Array = []
	var anchors: Array = []
	for row in CounterButton._SEGS:
		keys.append(String((row as Array)[0]))
		anchors.append((row as Array)[1])
	_check(keys == ["glow_width", "glow_lefttop", "glow_length", "glow_leftdown",
		"glow_width", "glow_width", "glow_rightdown", "glow_length",
		"glow_righttop", "glow_width"], "조각 순서 = 원작 addObject 순서")
	_check(anchors == [Vector2(1, 1), Vector2(1, 1), Vector2(0, 1), Vector2(0, 1),
		Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0),
		Vector2(1, 0), Vector2(1, 1)], "앵커 = 원작 setAnchorPoint(자라는 방향)")
	_check(CounterButton.BTN_PX == Vector2(262, 94), "btn2 실측 262×94")

func _test_build() -> void:
	var b := _btn
	_check(is_instance_valid(b) and b.is_inside_tree(), "CounterButton 이 트리에 들어갔다")
	if not is_instance_valid(b):
		return
	var segs := 0
	for i in 10:
		if b.get_node_or_null("Glow%d" % i) != null:
			segs += 1
	_check(segs == 10, "글로우 조각 10개 (%d)" % segs)
	_check(b.get_node_or_null("GlowDot") != null, "러너 점 glow_automode")
	_check(b.get_child_count() >= 14,
		"바탕3 + 라벨 + 조각10 + 점 + 히트 (%d)" % b.get_child_count())

	var S := Design.ASSET_SCALE
	var W := CounterButton.BTN_PX.x * S
	var H := CounterButton.BTN_PX.y * S
	var man := AtlasUI.manifest(CounterButton.DIR)
	var wid := float((man.get("scene_adventure_glow_width", {}) as Dictionary).get("w", 0)) * S
	var rt := float((man.get("scene_adventure_glow_righttop", {}) as Dictionary).get("w", 0)) * S
	_pos_is(b, "Glow0", Vector2(0.0, -H * 0.5 - 5.0), "0번(상단 중앙)")
	_pos_is(b, "Glow1", Vector2(-wid, -H * 0.5 - 5.0), "1번(좌상 모서리)")
	_pos_is(b, "Glow9", Vector2(W - rt + 7.5 - W * 0.5, -H * 0.5 - 5.0), "9번(우상 윗변)")
	_pos_is(b, "Glow4", Vector2(-W * 0.5 + wid * 0.0 + _ld_x(man, S) - 7.0, H * 0.5 + 1.0),
		"4번(아랫변 좌)")

func _ld_x(man: Dictionary, s: float) -> float:
	return float((man.get("scene_adventure_glow_leftdown", {}) as Dictionary).get("w", 0)) * s

func _pos_is(b: Node, path: String, want: Vector2, what: String) -> void:
	var n := b.get_node_or_null(path) as Node2D
	if n == null:
		_check(false, "%s 노드 없음" % what)
		return
	_check(n.position.distance_to(want) < 0.01,
		"%s 좌표 %s (기대 %s)" % [what, n.position, want])

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)
