extends SceneTree
## 빛의 탑 터치 연출 스파인 점검.
##
## 원작(`DV2/480/scene/worldmap/ani_lighttower_spine.spine_json`)의 `touch_*` 애니는
## 탑 본체(`worldmap_top_top`)와 배경판(`worldmap_top_book`/`bookwhite`/`under`)을
## `attachment: null` 로 **숨긴다**. 그 탑 본체가 솟아오르는 것은 `appear` 애니뿐이다
## (본 `worldmap_top_top` translate y −319 → 5).
## 또 원소별 변형 슬롯(`top010101` / `top020202020202` / `worldmap_toptop`)은 9종 중
## **1개만** 보여야 한다.
##
##   godot --headless --path . --script res://scripts/tools/test_lighttower_spine.gd --quit-after 30

const SCENE := "res://scenes/worldmap_fx/ani_lighttower_spine.tscn"
const BODY := ["worldmap_top_top_slot", "worldmap_top_book",
	"worldmap_top_bookwhite_slot", "worldmap_top_under_slot"]
const VARIANT_GROUPS := ["top010101__", "top020202020202__", "worldmap_toptop__"]

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	if not ResourceLoader.exists(SCENE):
		print("FAIL: 씬 없음 ", SCENE)
		quit(1)
		return
	var inst := (load(SCENE) as PackedScene).instantiate() as Node2D
	get_root().add_child(inst)
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		print("FAIL: AnimationPlayer 없음")
		quit(1)
		return
	print("애니 목록: ", ap.get_animation_list())
	var fail := 0

	print("── 탑 본체·배경판 (touch_* 에서는 숨어야 한다) ──")
	for an in ["appear", "touch_wind", "touch_water"]:
		if not ap.has_animation(an):
			continue
		ap.play(an)
		ap.seek(0.05, true)
		var line := "  %-12s " % an
		for w in BODY:
			var n := _find(inst, w)
			var vis: bool = n != null and (n as CanvasItem).visible
			line += "%s=%s " % [w.replace("worldmap_top_", "").replace("_slot", ""),
				("?" if n == null else ("보임" if vis else "숨김"))]
			if an.begins_with("touch_") and vis:
				fail += 1
		print(line)

	print("── 원소 변형 슬롯 (항상 1개만 보여야 한다) ──")
	for an2 in ["touch_wind", "touch_water"]:
		if not ap.has_animation(an2):
			continue
		ap.play(an2)
		for t in [0.05, 0.3, 0.6]:
			ap.seek(t, true)
			for grp in VARIANT_GROUPS:
				var on: Array = []
				_collect_visible(inst, grp, on)
				if on.size() != 1:
					fail += 1
				print("  %-12s t=%.2f %-22s %d개 %s" % [an2, t, grp, on.size(), str(on)])
	# 🔴 원작 저작 오타: touch_wind 의 `top020202020202` 만 `worldmap_top_wind`(184×302 = 탑 건물
	#    통짜 그림)를 가리킨다 — 나머지 7원소는 전부 `*_02`(34×106 빛줄기)다. 그 본이 0.6초에
	#    y 10→220 으로 솟아 **탑이 빛기둥과 함께 솟구쳐 오르는** 것으로 보였다.
	#    `build_worldmap_lighttower.py` 가 변환 시 `worldmap_top_wind02` 로 고친다.
	if ap.has_animation("touch_wind"):
		ap.play("touch_wind")
		ap.seek(0.3, true)
		var on2: Array = []
		_collect_visible(inst, "top020202020202__", on2)
		var bad := on2.has("worldmap_top_wind")
		print("  touch_wind 의 빛줄기 슬롯 → %s%s" % [str(on2), "  🔴 탑 그림!" if bad else "  ok"])
		if bad:
			fail += 1

	print("\n%s (실패 %d)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(0 if fail == 0 else 1)

## 보이는 **스프라이트**만 모은다. `*_frame` 은 변환기가 만든 트랜스폼 홀더라 항상 보인다
## (그림이 없다) — 세면 원소 변형이 9개로 잡혀 오판한다.
func _collect_visible(n: Node, prefix: String, out: Array) -> void:
	var nm := String(n.name)
	if n is Sprite2D and nm.begins_with(prefix) and not nm.ends_with("_frame") 			and (n as CanvasItem).visible:
		out.append(nm.substr(prefix.length()))
	for c in n.get_children():
		_collect_visible(c, prefix, out)

func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r != null:
			return r
	return null
