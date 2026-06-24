extends Node2D
## (C) integration demo: data (Data) -> computed stats -> converted spine scene.
## ←/→ cycle dragon, ↑/↓ change level (stage auto-switches), S add+save, R reset save.

var ids: Array = []
var idx := 0
var level := 1
var holder: Node2D
var info: Label
var help: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.15, 0.19)
	bg.size = Vector2(1920, 1080)
	add_child(bg)

	holder = Node2D.new()
	holder.position = Vector2(1360, 780)
	holder.scale = Vector2(2.4, 2.4)   # 480 baseline -> ~1080 display (scale at use, not baked)
	add_child(holder)

	info = _mk_label(60, 80, 34)
	help = _mk_label(60, 980, 22)
	help.text = "←/→ 드래곤   ↑/↓ 레벨(±5)   S 보유추가+저장   R 세이브리셋"

	_scan_ids()
	_show()

func _scan_ids() -> void:
	var seen := {}
	var da := DirAccess.open("res://scenes/dragons")
	if da:
		for f in da.get_files():
			if f.ends_with(".tscn") and f.begins_with("dragon_"):
				seen[int(f.trim_prefix("dragon_").split("_")[0])] = true
	ids = seen.keys()
	ids.sort()

func _mk_label(x: int, y: int, size: int) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.add_theme_font_size_override("font_size", size)
	add_child(l)
	return l

func _show() -> void:
	for c in holder.get_children():
		c.queue_free()
	if ids.is_empty():
		info.text = "변환된 드래곤 씬이 없습니다. spine_batch.py + build_all.gd 실행 필요."
		return
	var id: int = ids[idx]
	var d: Dictionary = Data.get_dragon(id)
	var stage := Data.stage_for_level(level)
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, stage]
	if ResourceLoader.exists(path):
		var inst = load(path).instantiate()
		holder.add_child(inst)
		var ap = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.play("wait")
	var s := Data.compute_stats(id, level)
	info.text = "#%d  %s\n속성: %s   유형: %s   %s성   %s세대\nLv.%d  [%s]\nHP %d   ATT %d   DEF %d\nCRI %d%%  EVD %d%%  BLK %d%%" % [
		id, str(d.get("name", "?")), str(d.get("element", "?")), str(d.get("type", "?")),
		str(d.get("star", "?")), str(d.get("generation", "?")), level, stage,
		s["hp"], s["att"], s["def"], s["cri"], s["evd"], s["blk"]]

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match (e as InputEventKey).keycode:
		KEY_RIGHT: idx = (idx + 1) % ids.size(); _show()
		KEY_LEFT: idx = (idx - 1 + ids.size()) % ids.size(); _show()
		KEY_UP: level = mini(45, level + 5); _show()
		KEY_DOWN: level = maxi(1, level - 5); _show()
		KEY_S:
			UserDB.add_dragon(ids[idx], level)
			help.text = "저장됨 — 보유 드래곤 %d마리 (user://save_0.json)" % UserDB.dragon_count()
		KEY_R:
			UserDB.reset()
			help.text = "세이브 리셋됨"
