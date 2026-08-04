extends Node
## BGM 매니저(오토로드 "Bgm"). 원작 배경음(setWorldMapSound 등)을 res://DV2/music/*.mp3로 재생.
## play(track): 같은 트랙이면 무시, 다르면 짧은 크로스페이드. 루프 재생. sfx(track): 1회성 효과음.
## 오프라인 재구현 — 원작 음악은 로컬 소장용(푸시 금지, [[dv2-git-remote-policy]]).

const DIR := "res://assets/music/%s.mp3"
const LEGACY_DIR := "res://DV2/music/%s.mp3"
const FADE := 0.6

# ── 사용자 볼륨 (원작 SettingLayer 의 슬라이더 2개) ─────────────────────────
# 원작은 `CocosDenshion::SimpleAudioEngine` 의 **배경음/효과음 두 계통**을 따로 조절한다
# (`SettingLayer::setVolume` — tag 1 → setBackgroundMusicVolume, tag 2 → setEffectsVolume).
# 우리는 그 두 계통을 AudioServer 버스로 만든다: BGM 은 Music, 효과음·구역앰비언트는 Sfx.
# 값은 0.0~1.0 선형이고 원작 기본은 **0.5** (`IntroScene.c:12633 getFloatForKey(…, 0.5)`).
# `_base_vol` 은 그와 별개인 **믹스 레벨**(곡이 원래 큰 것을 깎아 둔 값)이라 그대로 둔다.
const MUSIC_BUS := "Music"
const SFX_BUS := "Sfx"
const PREF_MUSIC := "MUSICVOLUME"      # 원작 CCUserDefault 키 그대로
const PREF_EFFECT := "EFFECTVOLUME"
const VOL_DEFAULT := 0.5

var _a: AudioStreamPlayer   # 현재 재생
var _b: AudioStreamPlayer   # 크로스페이드 대상
var _cur := ""
var _fade: Tween             # 진행 중인 크로스페이드(새 play가 오면 죽인다)
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
	# 원작 effect_button: 전역 버튼 클릭음(모든 BaseButton pressed → SFX).
	get_tree().node_added.connect(_on_node_added)

## 이름으로 조회해 중복 생성을 막는다(AudioServer 버스는 세션 전역).
func _ensure_bus(name: String) -> int:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")
	return idx

## 0.0 은 `linear_to_db` 가 -inf 라 버스 mute 로 처리한다.
func _apply_bus(name: String, v: float) -> void:
	var idx := _ensure_bus(name)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0005)))

func music_volume() -> float:
	return _music_vol

func effects_volume() -> float:
	return _effect_vol

## 원작 `SettingLayer::setVolume` tag 1. 소리는 즉시 반영된다.
## `persist=false` = 드래그 중(파일 쓰기 없음). 원작도 값 저장은 창을 닫을 때 한 번이다
## (`~SettingLayer` 가 setFloatForKey → flush).
func set_music_volume(v: float, persist := true) -> void:
	_music_vol = clampf(v, 0.0, 1.0)
	_apply_bus(MUSIC_BUS, _music_vol)
	if persist:
		_store_pref(PREF_MUSIC, _music_vol)

## 원작 `SettingLayer::setVolume` tag 2.
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
		# 일부 원작 음원은 아직 DV2 원본 폴더에만 있다. 대표적으로
		# InterFace::setCallHitSound가 번갈아 쓰는 effect_dragon_damaged_2.
		path = LEGACY_DIR % track
		if not FileAccess.file_exists(path):
			return null
		# 원본 폴더의 오래된 .import가 현재 .godot 캐시를 가리키지 않을 수 있으므로
		# MP3 본문을 직접 읽는다. 음원 내용은 원작 파일 그대로이며 변환하지 않는다.
		st = AudioStreamMP3.load_from_buffer(FileAccess.get_file_as_bytes(path))
	else:
		st = load(path)
	if st == null:
		return null
	if st is AudioStreamMP3:
		st.loop = true
	return st as AudioStream

## 배경음 재생(루프). 같은 트랙 재생 중이면 무시. 다르면 _a→_b 크로스페이드.
func play(track: String) -> void:
	if _muted or track == "":
		return
	if track == _cur and _a.playing:
		return
	var st := _make_stream(track)
	# ⚠️ _cur 는 **로드 성공 후에만** 갱신한다. 실패한 트랙을 현재값으로 박아 두면 다음에 같은
	#    트랙을 다시 요청해도 위 조기반환에 걸려 영영 안 걸린다.
	if st == null:
		return
	_cur = track
	# 이전 크로스페이드가 아직 돌고 있으면 죽인다 — 씬 전환이 연속으로 일어나면(월드맵→탐험→전투)
	# 페이드가 겹쳐 _a/_b 스왑 콜백이 뒤늦게 실행되며 방금 켠 곡을 멈춰 버린다.
	if _fade != null and _fade.is_valid():
		_fade.kill()
	# 현재 재생 중이면 크로스페이드, 아니면 즉시 페이드인.
	if _a.playing:
		_b.stream = st; _b.volume_db = -40.0; _b.play()
		_fade = create_tween().set_parallel(true)
		_fade.tween_property(_a, "volume_db", -40.0, FADE)
		_fade.tween_property(_b, "volume_db", _base_vol, FADE)
		_fade.chain().tween_callback(func():
			_a.stop()
			var tmp := _a; _a = _b; _b = tmp)   # 스왑: _a가 항상 현재
	else:
		_a.stream = st; _a.volume_db = -40.0; _a.play()
		_fade = create_tween()
		_fade.tween_property(_a, "volume_db", _base_vol, FADE)

## 1회성 효과음(승리 팡파레 등). 별도 임시 플레이어.
## `vol` = 원작 `SoundManager::playEffect(..., volume, ...)` 의 볼륨 인자(0~1, 1=원음).
## 원작이 음원마다 다른 볼륨을 넘기는 자리가 있다 —
##   피격 `runSpineWithAnimationName` @0104f468: `(rand()%6)*0.05 + 0.25`
##   사망 `deadEffect` @0109a654: 0.5
## 기본값 1.0 이라 기존 호출부는 그대로다.
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

## 루프 효과음. 원작 `SoundManager::playEffect(..., loop=1)` 대응(알 대기 중 심장박동 등).
## **호출자가 소유한다** — 반환된 플레이어를 자기 노드에 붙여 두면 그 노드가 사라질 때 같이 죽는다.
## (원작은 `stopEffectAll()` 로 껐지만, 우리 쪽 효과음은 전부 임시 플레이어라 트리 수명이 곧 소유권이다.)
func loop_sfx(track: String) -> AudioStreamPlayer:
	if _muted: return null
	var st := _make_stream(track)
	if st == null: return null
	if st is AudioStreamMP3: st.loop = true
	var p := AudioStreamPlayer.new(); p.bus = SFX_BUS; p.stream = st; p.volume_db = _base_vol
	p.autoplay = true      # 트리에 들어가는 순간 시작한다(아직 트리 밖이라 play() 는 못 부른다)
	return p

# ═══════════════════════════════════════════════════════════════════════════
# 구역 앰비언트 — 원작 `WorldMapLayer::setWorldMapSound` (WorldMapLayer.c:4108~)
#
# 원작은 지역마다 `WorldMapSound::create(파일, CCRect)` 를 3개씩 등록하고
# (`WorldMap{Yutakan,Elf,Dwarf}Layer::initSound`), 매 스크롤마다:
#   · 화면 중앙을 컨테이너 좌표로 변환 → 각 rect 의 `containsPoint` 검사
#   · **밖이면 `SoundManager::stopEffect`** (id 를 -1 로 되돌린다)
#   · 안이면 `playEffect(pitch=1.0, pan, gain, …, loop=1)` — 이미 재생 중이면 `modifyEffect`
#       gain = |1.0 − d|,  d = min(1, |중앙 − rect중심| / (rect.w × 0.5))
#       pan  = −(중앙.x − rect중심.x) / (rect.w × 0.5)
#   (근거: WorldMapLayer.c:4166-4249 — `fVar12 = 1.0/|rect중심 − rect좌중앙|` = 1/(w/2))
#
# ⇒ 즉 **위치 기반**이고, 구역을 벗어나면 멈춘다. 종전 우리 구현(`ambient(track)`)은
#   위치와 무관하게 한 트랙을 무한 재생했고 씬을 나가도 안 껐다(2026-07-28 사용자 검수:
#   "폭포 효과음이 장소 관계없이 게임 내내 재생"). `Scenes.goto` 가 매 전환마다
#   `area_clear()` 를 부르므로 월드맵 밖으로 나가면 반드시 멈춘다.
#
# 좌표계: `rect`·`center` 는 **씬의 콘텐츠 좌표**(스크롤 적용 전 design px). 호출자가 맞춘다.

const AREA_VOL_DB := -14.0   # gain=1.0 일 때의 볼륨(BGM _base_vol 아래로 깔린다)
const AREA_BUS := "AreaSfx%d"

var _areas: Array = []          # [{track, rect: Rect2, player, bus_idx}]

## 이 씬의 구역 목록을 등록한다. areas = [{"track": String, "rect": Rect2}].
## 이전 등록분은 모두 정지·해제된다.
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

## 화면 중앙(콘텐츠 좌표)을 넘겨 재생/정지·볼륨·팬을 갱신한다.
func area_update(center: Vector2) -> void:
	for a in _areas:
		var r: Rect2 = a["rect"]
		var p: AudioStreamPlayer = a["player"]
		if not r.has_point(center):
			if p.playing:
				p.stop()
			continue
		# 원작: 정규화 반경 = rect.w * 0.5 (세로도 같은 값으로 나눈다 — 축자 이식)
		var half: float = maxf(1.0, r.size.x * 0.5)
		var c := r.get_center()
		var d: float = minf(1.0, (center - c).length() / half)
		var gain: float = absf(1.0 - d)
		var pan: float = clampf(-(center.x - c.x) / half, -1.0, 1.0)
		_area_panner(a["bus"]).pan = pan
		p.volume_db = AREA_VOL_DB + linear_to_db(maxf(gain, 0.0005))
		if not p.playing:
			p.play()

## 씬을 떠날 때(=`Scenes.goto`) 호출. 남아 있던 구역 사운드를 전부 끊는다.
func area_clear() -> void:
	for a in _areas:
		var p: AudioStreamPlayer = a["player"]
		if is_instance_valid(p):
			p.stop(); p.queue_free()
	_areas.clear()

## 구역 슬롯 i 전용 버스(팬 이펙트 포함). 없으면 만들고, 있으면 재사용한다.
## ⚠️ AudioServer 버스는 세션 전역이다 — 이름으로 조회해 중복 생성을 막는다.
## 원작 구역 앰비언트는 `SoundManager::playEffect` = **효과음 계통**이라 Sfx 버스로 보낸다
## (`WorldMapLayer::setWorldMapSound`). 그래서 효과음 슬라이더가 이것까지 함께 줄인다.
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
