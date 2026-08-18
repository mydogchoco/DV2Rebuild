extends SceneTree
const FX := [
	{"scene": "skill_1_bite_spine", "sfx": "effect_bite"},
	{"scene": "skill_1_scratch_spine", "sfx": "effect_scratch"},
]

func _initialize() -> void:
	var bad := 0
	for e in FX:
		var path := "res://scenes/fx/%s.tscn" % e["scene"]
		var line := "%-24s" % e["scene"]
		if not ResourceLoader.exists(path):
			line += " 씬없음"; bad += 1
		else:
			var inst = (load(path) as PackedScene).instantiate()
			var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
			if ap == null or not ap.has_animation("animation"):
				line += " 애니없음"; bad += 1
			else:
				line += " 애니 %.2fs" % ap.get_animation("animation").length
			var ok_tex := false
			var stack: Array = [inst]
			while not stack.is_empty():
				var n = stack.pop_back()
				if n is Sprite2D and n.texture is AtlasTexture and (n.texture as AtlasTexture).atlas != null:
					ok_tex = true; break
				for c in n.get_children():
					stack.append(c)
			line += (" 텍스처O" if ok_tex else " 텍스처✗")
			if not ok_tex: bad += 1
			inst.free()
		var sp := "res://assets/music/%s.mp3" % e["sfx"]
		var snd = load(sp) if ResourceLoader.exists(sp) else null
		line += (" 사운드O" if snd != null else " 사운드✗(%s)" % e["sfx"])
		if snd == null: bad += 1
		print(line)
	print("결과: %s" % ("PASS" if bad == 0 else "FAIL(%d)" % bad))
	quit(0 if bad == 0 else 1)
