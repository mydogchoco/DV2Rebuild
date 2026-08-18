extends Node

const DIR := "res://assets/music/%s.mp3"
const LEGACY_DIR := "res://DV2/music/%s.mp3"
const FADE := 0.6

const MUSIC_BUS := "Music"
const SFX_BUS := "Sfx"
const PREF_MUSIC := "MUSICVOLUME"
const PREF_EFFECT := "EFFECTVOLUME"
const VOL_DEFAULT := 0.5

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _cur := ""
var _fade: Tween
var _base_vol := -9.0
var _muted := false
var _music_vol := VOL_DEFAULT
var _effect_vol := VOL_DEFAULT

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	var prefs := SaveSystem.load_prefs()
	_music_vol = clampf(float(prefs.get(PREF_MUSIC, VOL_DEFAULT)), 0.0, 1.0)
	_effect_vol = clampf(float(prefs.get(PREF_EFFECT, VOL_DEFAULT)), 0.0, 1.0)
	_apply_bus(MUSIC_BUS, _music_vol)
	_apply_bus(SFX_BUS, _effect_vol)
	_a = AudioStreamPlayer.new(); _a.bus = MUSIC_BUS; add_child(_a)
	_b = AudioStreamPlayer.new(); _b.bus = MUSIC_BUS; add_child(_b)
	get_tree().node_added.connect(_on_node_added)

func _ensure_bus(name: String) -> int:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")
	return idx

func _apply_bus(name: String, v: float) -> void:
	var idx := _ensure_bus(name)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0005)))

func music_volume() -> float:
	return _music_vol

func effects_volume() -> float:
	return _effect_vol

func set_music_volume(v: float, persist := true) -> void:
	_music_vol = clampf(v, 0.0, 1.0)
	_apply_bus(MUSIC_BUS, _music_vol)
	if persist:
		_store_pref(PREF_MUSIC, _music_vol)

func set_effects_volume(v: float, persist := true) -> void:
	_effect_vol = clampf(v, 0.0, 1.0)
	_apply_bus(SFX_BUS, _effect_vol)
	if persist:
		_store_pref(PREF_EFFECT, _effect_vol)

func _store_pref(key: String, v: float) -> void:
	var prefs := SaveSystem.load_prefs()
	prefs[key] = v
	SaveSystem.save_prefs(prefs)

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(_click_sfx):
		(n as BaseButton).pressed.connect(_click_sfx)

func _click_sfx() -> void:
	sfx("effect_button")

func _make_stream(track: String) -> AudioStream:
	var path := DIR % track
	var st: AudioStream
	if not ResourceLoader.exists(path):
		path = LEGACY_DIR % track
		if not FileAccess.file_exists(path):
			return null
		push_warning("[Bgm] '%s' 가 assets/music 에 없다 — build_music.py 를 돌리지 않으면 exe 에서 무음이다" % track)
		st = AudioStreamMP3.load_from_buffer(FileAccess.get_file_as_bytes(path))
	else:
		st = load(path)
	if st == null:
		return null
	if st is AudioStreamMP3:
		st.loop = true
	return st as AudioStream

func play(track: String) -> void:
	if _muted or track == "":
		return
	if track == _cur and _a.playing:
		return
	var st := _make_stream(track)
	if st == null:
		return
	_cur = track
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if _a.playing:
		_b.stream = st; _b.volume_db = -40.0; _b.play()
		_fade = create_tween().set_parallel(true)
		_fade.tween_property(_a, "volume_db", -40.0, FADE)
		_fade.tween_property(_b, "volume_db", _base_vol, FADE)
		_fade.chain().tween_callback(func():
			_a.stop()
			var tmp := _a; _a = _b; _b = tmp)
	else:
		_a.stream = st; _a.volume_db = -40.0; _a.play()
		_fade = create_tween()
		_fade.tween_property(_a, "volume_db", _base_vol, FADE)

func sfx(track: String, vol := 1.0) -> void:
	if _muted: return
	var st := _make_stream(track)
	if st == null: return
	if st is AudioStreamMP3: st.loop = false
	var p := AudioStreamPlayer.new(); p.bus = SFX_BUS; p.stream = st
	p.volume_db = _base_vol + (0.0 if is_equal_approx(vol, 1.0)
		else linear_to_db(clampf(vol, 0.0001, 1.0)))
	add_child(p); p.play()
	p.finished.connect(func(): if is_instance_valid(p): p.queue_free())

func loop_sfx(track: String) -> AudioStreamPlayer:
	if _muted: return null
	var st := _make_stream(track)
	if st == null: return null
	if st is AudioStreamMP3: st.loop = true
	var p := AudioStreamPlayer.new(); p.bus = SFX_BUS; p.stream = st; p.volume_db = _base_vol
	p.autoplay = true
	return p

const AREA_VOL_DB := -14.0
const AREA_BUS := "AreaSfx%d"

var _areas: Array = []

func area_setup(areas: Array) -> void:
	area_clear()
	if _muted:
		return
	var i := 0
	for a in areas:
		var track := String(a.get("track", ""))
		var st := _make_stream(track)
		if st == null:
			push_warning("[Bgm] 구역 사운드 없음: %s" % track)
			continue
		if st is AudioStreamMP3:
			st.loop = true
		var bus := _area_bus(i)
		var p := AudioStreamPlayer.new()
		p.bus = AudioServer.get_bus_name(bus)
		p.stream = st
		p.volume_db = -60.0
		add_child(p)
		_areas.append({"track": track, "rect": a.get("rect", Rect2()), "player": p, "bus": bus})
		i += 1

func area_update(center: Vector2) -> void:
	for a in _areas:
		var r: Rect2 = a["rect"]
		var p: AudioStreamPlayer = a["player"]
		if not r.has_point(center):
			if p.playing:
				p.stop()
			continue
		var half: float = maxf(1.0, r.size.x * 0.5)
		var c := r.get_center()
		var d: float = minf(1.0, (center - c).length() / half)
		var gain: float = absf(1.0 - d)
		var pan: float = clampf(-(center.x - c.x) / half, -1.0, 1.0)
		_area_panner(a["bus"]).pan = pan
		p.volume_db = AREA_VOL_DB + linear_to_db(maxf(gain, 0.0005))
		if not p.playing:
			p.play()

func area_clear() -> void:
	for a in _areas:
		var p: AudioStreamPlayer = a["player"]
		if is_instance_valid(p):
			p.stop(); p.queue_free()
	_areas.clear()

func _area_bus(i: int) -> int:
	var name := AREA_BUS % i
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, SFX_BUS)
	AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
	return idx

func _area_panner(bus: int) -> AudioEffectPanner:
	return AudioServer.get_bus_effect(bus, 0) as AudioEffectPanner

func stop() -> void:
	_cur = ""
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if _a: _a.stop()
	if _b: _b.stop()
	area_clear()

func set_muted(m: bool) -> void:
	_muted = m
	if m: stop()
