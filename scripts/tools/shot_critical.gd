extends Node2D
## 크리티컬 자산 렌더 캡처 — 스파인(PvP)과 아트(PvE)를 각각 PNG로 저장해 눈으로 대조한다.
## Run: godot --path . res://scenes/shot_critical.tscn -- <out_dir> <id> [id...]
var _ids: Array = []
var _out := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	for i in range(1, args.size()):
		_ids.append(args[i])
	if _ids.is_empty():
		_ids = ["104"]
	_run()

func _run() -> void:
	var vis := get_viewport_rect().size
	for id in _ids:
		# --- 스파인(PvP) ---
		var sp := "res://scenes/dragons/dragon_%s_critical.tscn" % id
		if ResourceLoader.exists(sp):
			var holder := Node2D.new()
			holder.position = vis * 0.5
			add_child(holder)
			var inst = (load(sp) as PackedScene).instantiate()
			holder.add_child(inst)
			var ap: AnimationPlayer = null
			for ch in holder.get_children():
				ap = ch.get_node_or_null("AnimationPlayer")
				if ap: break
			if ap:
				for cand in ["animation", "critical"]:
					if ap.has_animation(cand):
						ap.play(cand)
						ap.advance(ap.get_animation(cand).length * 0.4)
						break
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/spine_%s.png" % [_out, id])
			holder.queue_free()
			await get_tree().process_frame
	print("saved to ", _out)
	get_tree().quit()
