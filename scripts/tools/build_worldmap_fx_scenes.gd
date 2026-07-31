extends SceneTree
# assets/converted/scenespine_ani_*/ 의 중간 JSON → scenes/worldmap_fx/<name>.tscn 빌드.
# Run: godot --headless --script res://scripts/tools/build_worldmap_fx_scenes.gd
# 대상 = 월드맵 소속 스파인(`scene/worldmap/ani_*_spine.spine_json`).
#   바다 거품 `ani_sea_spine`(원작 WorldMapLayer::initWidget, anim nest/dustwave)
#   지역 앰비언트 `ani_fire_new_spine` · `ani_cave_spine` · `ani_veti_spine` 등(initAnimation)
# 중간 JSON 은 `scripts/tools/build_worldmap_sea.py` 등이 만든다(spine_export.export_scene).
const Builder = preload("res://scripts/tools/build_spine_scene.gd")

func _initialize() -> void:
	var built := 0
	var root_dir := "res://assets/converted"
	var da := DirAccess.open(root_dir)
	if da == null:
		push_error("no " + root_dir); quit(1); return
	DirAccess.make_dir_recursive_absolute("res://scenes/worldmap_fx")
	for sub in da.get_directories():
		# ⚠️ 종전엔 `scenespine_ani_` 만 받았다. 월드맵 스파인 중에는 스켈레톤 이름이 `ani_` 로
		#   시작하지 않는 것이 있다 — 임프상인은 스켈레톤 `worldmap_imp_spine` + 아틀라스
		#   `ani_imp_spine` 로 **이름이 서로 다르다**(2026-07-31).
		if not sub.begins_with("scenespine_"):
			continue
		var d2 := DirAccess.open("%s/%s" % [root_dir, sub])
		if d2 == null:
			continue
		for fn in d2.get_files():
			if fn.ends_with(".json") and not fn.begins_with("_"):
				var in_path := "%s/%s/%s" % [root_dir, sub, fn]
				var nm := sub.substr("scenespine_".length())
				var out_path := "res://scenes/worldmap_fx/%s.tscn" % nm
				if Builder.build_one(in_path, out_path) == OK:
					built += 1
					print("  + ", out_path)
	print("built %d worldmap fx scenes" % built)
	quit(0)
