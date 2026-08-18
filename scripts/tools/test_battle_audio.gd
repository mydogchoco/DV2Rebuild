extends "res://scripts/ui/battle.gd"

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_audio_test")

func _run_audio_test() -> void:
	var before := _sfx_paths()
	_start_critical_audio({"id": 1, "element": "fire", "voice_critical": 12})
	var immediate := _new_paths(before)
	_expect(immediate.any(func(p: String): return p.ends_with("effect_cut_in.mp3")),
		"critical: effect_cut_in did not start immediately")
	_expect(not immediate.any(func(p: String): return p.ends_with("voice12.mp3")),
		"critical: voice started before cut-in voice delay")
	await get_tree().create_timer(CritCutin.VOICE_DELAY + 0.04).timeout
	var delayed := _new_paths(before)
	_expect(delayed.any(func(p: String): return p.ends_with("voice12.mp3")),
		"critical: mapped dragon voice did not start")

	var party_before := _sfx_player_ids()
	_hurt(_dummy_view("party"), 10, true)
	var party_audio := _new_sfx_player_ids(party_before)
	_expect(not party_audio.is_empty(),
		"hurt: party dragon did not use effect_dragon_damaged")

	var enemy_before := _sfx_player_ids()
	_queue_monster_hit_sfx()
	var enemy_immediate := _new_sfx_player_ids(enemy_before)
	_expect(enemy_immediate.is_empty(),
		"monster hit: damaged sound played before the impact delay")
	await get_tree().create_timer(_MONSTER_HIT_SFX_DELAY + 0.05).timeout
	var enemy_delayed := _new_sfx_player_ids(enemy_before)
	_expect(not enemy_delayed.is_empty(),
		"monster hit: delayed damaged sound did not play")

	_enemy = {"id": 162, "boss": true}
	_params = {"boss": true}
	var critical_before := _sfx_paths()
	_monster_critical_attack(_dummy_view("enemy"))
	var critical_audio := _new_paths(critical_before)
	_expect(critical_audio.any(func(p: String): return p.ends_with("effect_critical_ice_2.mp3")),
		"monster critical: break sound did not play")
	_expect(ResourceLoader.exists("res://assets/converted/monster_162/monster_162_162_image_att_cri.tres"),
		"monster critical: att_cri asset is unavailable")
	_expect(ResourceLoader.exists("res://assets/converted/monster_162/monster_162_162_image_att_effect_cri.tres"),
		"monster critical: att_effect_cri asset is unavailable")
	_expect(get_children().any(func(n: Node): return n is CanvasLayer and (n as CanvasLayer).layer == 35),
		"monster critical: screen break overlay was not created")

	var damaged_2 := Bgm._make_stream("effect_dragon_damaged_2")
	_expect(damaged_2 != null,
		"hurt: effect_dragon_damaged_2 legacy asset did not load")

	if _failures.is_empty():
		print("[PASS] battle audio: cut_in + delayed voice, delayed monster hit, boss critical break")
		get_tree().quit(0)
	else:
		for msg in _failures:
			push_error(msg)
		get_tree().quit(1)

func _dummy_view(kind: String) -> Dictionary:
	var node := Node2D.new()
	add_child(node)
	var fill := Control.new()
	fill.size = Vector2(100, 10)
	node.add_child(fill)
	var label := Label.new()
	node.add_child(label)
	return {
		"kind": kind, "node": node, "center": Vector2(100, 100), "base_pos": Vector2.ZERO,
		"alive": true, "hp": 100, "hp_max": 100, "hp_fill": fill,
		"hp_label": label, "bar_w": 100.0,
	}

func _sfx_paths() -> Array[String]:
	var out: Array[String] = []
	for child in Bgm.get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			if player.stream != null and player.bus == "Sfx":
				out.append(player.stream.resource_path)
	return out

func _new_paths(before: Array[String]) -> Array[String]:
	var remaining := before.duplicate()
	var out: Array[String] = []
	for path in _sfx_paths():
		var idx := remaining.find(path)
		if idx >= 0:
			remaining.remove_at(idx)
		else:
			out.append(path)
	return out

func _sfx_player_ids() -> Array[int]:
	var out: Array[int] = []
	for child in Bgm.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).bus == "Sfx":
			out.append(child.get_instance_id())
	return out

func _new_sfx_player_ids(before: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for id in _sfx_player_ids():
		if not before.has(id):
			out.append(id)
	return out

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
