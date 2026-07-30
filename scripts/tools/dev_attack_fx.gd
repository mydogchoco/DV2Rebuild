extends Node2D
## 전투 연출 육안 확인용 개발 창.
##
## ┌ 일반공격 아트 2종 — 원작 `MakeInterface::firstAttackEffect`(MakeInterface.c:14990)
## │   1 물기(bite) / 2 발톱(scratch, X반전) = **일반공격**.
## │   case 3·4(hit, x2.5) = **크리티컬 타격**으로 재구성 — info_dragon_v2 가 attack_type 과
## │   critical_type 을 별개 컬럼으로 갖고, first/secondAttackEffect 가 태그가 달라 1·2타를 따로 띄운다.
## └ 크리티컬 아트 — `dragon/dragon_%d_critical/critical.png`(각성은 `e_critical.png`)
##     **화면 정중앙 · 화면 전체 크기.** 배율은 트림 프레임(w)이 아니라 원본 캔버스(src) 기준.
##     이게 탐험(PvE)에서 실제로 쓰는 연출이다 — `battle.gd::_critical_art` 와 같은 계산.
##
## PvP 크리티컬 스파인(`dragon_%d_critical_spine`)은 이 창에서 다루지 않는다.
##   `MakeInterface` 는 콜로세움 인터페이스이고, 그 스켈레톤은 단독 재생용이 아니라
##   공격 드래곤의 몸을 런타임에 끼워 넣는 조립 리그다(`bone*_slot`) — 정적 변환본은 파츠가 흩어진다
##   (dragon_104 캡처로 확인). 자산 자체는 남겨 두었다.
##
## ⚠️ `VIEW_ZOOM` 은 일반공격 아트 **보기용 확대일 뿐 원작 값이 아니다**(원작은 1.0).
##    크리티컬 아트에는 적용하지 않는다 — 원래 크기가 곧 화면 크기라 확대하면 넘친다.
##
## 실행: godot --path . res://scenes/dev_attack_fx.tscn
##   1/2 = 물기/발톱(일반) · 3 = 크리티컬 타격(hit x2.5) · **S = 크리티컬 전체 시퀀스**
##   V = 크리티컬 아트만 · E = 일반↔각성(e_critical) 전환
##   ←/→ = 드래곤 이동 · PgUp/PgDn = ±10 · A = 자동순환 · ESC = 종료

const VIEW_ZOOM := 2.0

const FX := [
	{"key": "1", "name": "물기 (bite)", "scene": "skill_1_bite_spine",
		"sfx": "effect_bite", "scale": 1.0, "flip": false, "note": "지속 1.0"},
	{"key": "2", "name": "발톱 (scratch)", "scene": "skill_1_scratch_spine",
		"sfx": "effect_scratch", "scale": 1.0, "flip": true, "note": "X반전 · 지속 1.5"},
]

var _slots: Array[Node2D] = []
var _auto := true
var _t := 0.0
var _idx := 0
var _art_layer: CanvasLayer
var _status: Label
var _info: Label

var _ids_normal: Array = []      # critical.png 보유 드래곤
var _ids_awaken: Array = []      # e_critical.png 보유 드래곤
var _awaken := false
var _i := 0


func _ready() -> void:
	var vis := get_viewport_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.13)
	bg.size = vis
	add_child(bg)

	var title := Label.new()
	title.text = "1·2 일반공격(확대 x%.1f)   |   S = 크리티컬 전체 시퀀스(음성+컷인 → 타격 연타 → 화면 전체 아트)" % VIEW_ZOOM
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	var n := FX.size()
	for i in n:
		var e: Dictionary = FX[i]
		var cx := vis.x * (float(i) + 0.5) / float(n)
		var cy := vis.y * 0.5

		var ring := Line2D.new()
		ring.width = 1.0
		ring.default_color = Color(1, 1, 1, 0.15)
		for a in 33:
			var th := TAU * float(a) / 32.0
			ring.add_point(Vector2(cos(th), sin(th)) * 60.0 + Vector2(cx, cy))
		add_child(ring)

		var slot := Node2D.new()
		slot.position = Vector2(cx, cy)
		add_child(slot)
		_slots.append(slot)

		var lb := Label.new()
		lb.text = "[%s] %s\n%s\n%s · 사운드 %s" % [e["key"], e["name"], e["scene"], e["note"], e["sfx"]]
		lb.position = Vector2(cx - 200, cy + 120)
		lb.size = Vector2(400, 110)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lb)

	_scan_ids()

	_info = Label.new()
	_info.position = Vector2(24, vis.y - 116)
	_info.add_theme_font_size_override("font_size", 16)
	_info.modulate = Color(0.75, 0.85, 1.0)
	add_child(_info)

	_status = Label.new()
	_status.position = Vector2(24, vis.y - 66)
	_status.add_theme_font_size_override("font_size", 16)
	add_child(_status)
	_update_status()


func _scan_ids() -> void:
	var da := DirAccess.open("res://assets/converted")
	if da == null:
		return
	for sub in da.get_directories():
		if not sub.begins_with("critical_"):
			continue
		var id := sub.trim_prefix("critical_")
		var man := _man(id)
		if man.has("dragon_dragon_%s_critical_critical" % id):
			_ids_normal.append(id)
		if man.has("dragon_dragon_%s_critical_e_critical" % id):
			_ids_awaken.append(id)
	_ids_normal.sort_custom(func(a, b): return int(a) < int(b))
	_ids_awaken.sort_custom(func(a, b): return int(a) < int(b))


func _man(id: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/critical_%s/_manifest.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _list() -> Array:
	return _ids_awaken if _awaken else _ids_normal


func _update_status() -> void:
	var l := _list()
	var cur: String = String(l[_i]) if not l.is_empty() else "(없음)"
	_status.text = "S 전체시퀀스 · 3 크리타격 · V 아트만 · E %s(%d마리) · ←/→ 드래곤 · PgUp/PgDn ±10 · A 자동순환 %s · ESC" % [
		("각성 e_critical" if _awaken else "일반 critical"), l.size(), ("ON" if _auto else "OFF")]
	_info.text = "현재: 드래곤 %s  (%d / %d)" % [cur, _i + 1, l.size()]


func _process(delta: float) -> void:
	if not _auto:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 1.4
		_play(_idx)
		_idx = (_idx + 1) % FX.size()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match (e as InputEventKey).keycode:
		KEY_1: _play(0)
		KEY_2: _play(1)
		KEY_3: _play_crit_hit()
		KEY_S: _play_sequence()
		KEY_V: _play_critical_art()
		KEY_E:
			_awaken = not _awaken
			_i = 0
			_update_status()
			_play_critical_art()
		KEY_A:
			_auto = not _auto
			_update_status()
		KEY_LEFT: _step(-1)
		KEY_RIGHT: _step(1)
		KEY_PAGEUP: _step(-10)
		KEY_PAGEDOWN: _step(10)
		KEY_ESCAPE: get_tree().quit()


func _step(d: int) -> void:
	var l := _list()
	if l.is_empty():
		return
	_i = posmod(_i + d, l.size())
	_update_status()
	_play_critical_art()


## battle.gd::_normal_attack_fx 와 같은 파라미터(보기 확대만 추가).
func _play(i: int) -> void:
	var e: Dictionary = FX[i]
	var slot := _slots[i]
	for c in slot.get_children():
		c.queue_free()
	var path := "res://scenes/fx/%s.tscn" % e["scene"]
	if not ResourceLoader.exists(path):
		return
	var s := float(e["scale"]) * VIEW_ZOOM
	var holder := Node2D.new()
	holder.scale = Vector2(-s if bool(e["flip"]) else s, s)
	slot.add_child(holder)
	holder.add_child((load(path) as PackedScene).instantiate())
	var ap: AnimationPlayer = null
	for ch in holder.get_children():
		ap = ch.get_node_or_null("AnimationPlayer")
		if ap: break
	if ap and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
		ap.play("animation")
	Bgm.sfx(String(e["sfx"]))


## PvE 크리티컬 아트 — battle.gd::_critical_art 와 **같은 계산**.
func _play_critical_art() -> void:
	var l := _list()
	if l.is_empty():
		return
	if _art_layer and is_instance_valid(_art_layer):
		_art_layer.queue_free()
	var id := String(l[_i])
	var man := _man(id)
	var key := "dragon_dragon_%s_critical_%s" % [id, ("e_critical" if _awaken else "critical")]
	if not man.has(key):
		return
	var ent: Dictionary = man[key]
	var src: Array = ent.get("src", [ent.get("w", 0), ent.get("h", 0)])
	if float(src[0]) <= 0.0:
		return
	var path := "res://assets/converted/critical_%s/%s.tres" % [id, key]
	if not ResourceLoader.exists(path):
		return
	var vis := get_viewport_rect().size
	var s := vis.x / float(src[0])
	var spr := Sprite2D.new()
	spr.texture = load(path)
	# 회전 보정 불필요 — 변환 단계가 흡수(scripts/tools/fix_rotated_frames.py)
	spr.scale = Vector2(s, s)
	# 트림 오프셋 보정 — cocos off = (트림중심 − 원본캔버스중심), y-up.
	var off: Array = ent.get("off", [0, 0])
	spr.position = vis * 0.5 + Vector2(float(off[0]), -float(off[1])) * s
	_art_layer = CanvasLayer.new()
	_art_layer.layer = 41
	add_child(_art_layer)
	_art_layer.add_child(spr)
	_info.text = "현재: 드래곤 %s  (%d / %d)   %s   캔버스 %dx%d · 프레임 %dx%d · 배율 %.2f" % [
		id, _i + 1, l.size(), ("e_critical(각성)" if _awaken else "critical(일반)"),
		int(src[0]), int(src[1]), int(ent.get("w", 0)), int(ent.get("h", 0)), s]
	var t := spr.create_tween()
	t.tween_interval(1.2)
	t.tween_property(spr, "modulate:a", 0.0, 0.3)
	t.tween_callback(func(): if is_instance_valid(_art_layer): _art_layer.queue_free())


# ── 크리티컬 시퀀스 (battle.gd::_critical_sequence 와 같은 순서·같은 자산) ──────────
const CRIT_FX := {"scene": "skill_1_hit_spine", "sfx": "effect_headbutt", "scale": 2.5}
const CUTIN_LETTER := {
	"earth": "e", "aqua": "a", "fire": "f", "wind": "w", "light": "l",
	"dark": "d", "holy": "h", "chaos": "c", "shadow": "s",
}
var _elem_by_id: Dictionary = {}
var _seq_layer: CanvasLayer


func _element_of(id: String) -> String:
	if _elem_by_id.is_empty():
		var f := FileAccess.open("res://data/dragons.json", FileAccess.READ)
		if f:
			var arr = JSON.parse_string(f.get_as_text())
			if arr is Array:
				for d in arr:
					_elem_by_id[str(d.get("id", 0))] = String(d.get("element", ""))
	return String(_elem_by_id.get(id, "fire"))


## 3번 = 크리티컬 타격 스파인(hit, x2.5) 단독 재생. 가운데 슬롯에 띄운다.
func _play_crit_hit() -> void:
	var slot := _slots[_slots.size() - 1]
	for c in slot.get_children():
		c.queue_free()
	var path := "res://scenes/fx/%s.tscn" % CRIT_FX["scene"]
	if not ResourceLoader.exists(path):
		return
	var holder := Node2D.new()
	holder.scale = Vector2.ONE * float(CRIT_FX["scale"]) * VIEW_ZOOM
	slot.add_child(holder)
	holder.add_child((load(path) as PackedScene).instantiate())
	var ap: AnimationPlayer = null
	for ch in holder.get_children():
		ap = ch.get_node_or_null("AnimationPlayer")
		if ap: break
	if ap and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
		ap.play("animation")
	Bgm.sfx(String(CRIT_FX["sfx"]))


## S = 전체 시퀀스: 드래곤 음성 + 컷인 → hit 타격 연타 → 화면 전체 아트.
func _play_sequence() -> void:
	var l := _list()
	if l.is_empty():
		return
	var id := String(l[_i])
	_auto = false
	_update_status()
	if _seq_layer and is_instance_valid(_seq_layer):
		_seq_layer.queue_free()
	_seq_layer = CanvasLayer.new()
	_seq_layer.layer = 40
	add_child(_seq_layer)

	# ① 음성 — voice_critical 매핑이 비어 있으므로 속성 크리티컬음으로 폴백(전투와 동일 규칙).
	Bgm.sfx("effect_critical")
	# ② 컷인 — 밴드(dragon/cut_in_<속성>) + 드래곤 얼굴(critical_<id>/cut_in)
	_cutin(id)
	# 컷인 오버레이(막 + 밴드)가 완전히 걷힌 뒤 때린다 — battle.gd `_CUTIN_TOTAL` 과 같은 값.
	# 🔴 2026-07-27: 0.5초였을 때 타격 스파인이 컷인 CanvasLayer(40) 아래에 깔려 안 보였다.
	await get_tree().create_timer(0.65).timeout
	if not is_inside_tree(): return
	# ③ 타격 연타 — hit 스파인 x2.5 + effect_headbutt (간격 0.1초 = 원작 critical_frame)
	var hits := 2
	var cf := FileAccess.open("res://data/combat.json", FileAccess.READ)
	if cf:
		var cd = JSON.parse_string(cf.get_as_text())
		if cd is Dictionary:
			hits = maxi(1, int((cd.get("judge", {}) as Dictionary).get("crit_hits", 2)))
	for i in hits:
		if i > 0:
			await get_tree().create_timer(0.1).timeout
			if not is_inside_tree(): return
		_play_crit_hit()
	# ④ 화면 전체 크리티컬 아트 — 마지막 타의 hit 스파인(0.2초)이 끝난 뒤. 겹치면 아트가 덮는다.
	await get_tree().create_timer(0.2).timeout
	if not is_inside_tree(): return
	_play_critical_art()


func _cutin(id: String) -> void:
	## 원작 `Cutin::show`(docs/ref/orig_code/decomp/Cutin.c:443-845) 그대로 — battle.gd::_critical_cutin 과 동일.
	##   t=0.1 · t2=0.05 · 막 alpha 150 유지 0.4 · 밴드 EaseOut ScaleTo(s, s*1.05) 후 0.5초 뒤 퇴장
	var vis := get_viewport_rect().size
	var center := vis * 0.5
	var letter: String = CUTIN_LETTER.get(_element_of(id), "f")
	var bdir := "cut_in_%s" % letter
	var s := vis.x / 576.0

	# ① 어두운 막
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = vis
	dim.z_index = -1
	_seq_layer.add_child(dim)
	var dt := dim.create_tween()
	dt.tween_property(dim, "color:a", 150.0 / 255.0, 0.1)
	dt.tween_interval(0.4)
	dt.tween_property(dim, "color:a", 0.0, 0.1)

	# ② 밴드 — 3프레임 루프 + EaseOut 확대 + 퇴장
	var bp := "res://assets/converted/%s/dragon_cut_in_%s_bg_cut1.tres" % [bdir, letter]
	if ResourceLoader.exists(bp):
		var band := Sprite2D.new()
		band.texture = load(bp)
		band.position = center
		band.scale = Vector2.ONE
		_seq_layer.add_child(band)
		var frame := 1
		var ticker := Timer.new(); ticker.wait_time = 0.07; ticker.autostart = true
		ticker.timeout.connect(func():
			frame = frame % 3 + 1
			var fp := "res://assets/converted/%s/dragon_cut_in_%s_bg_cut%d.tres" % [bdir, letter, frame]
			if is_instance_valid(band) and ResourceLoader.exists(fp): band.texture = load(fp))
		_seq_layer.add_child(ticker)
		var bs := band.create_tween()
		bs.tween_property(band, "scale", Vector2(s, s * 1.05), 0.1)			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var bf := band.create_tween()
		bf.tween_interval(0.5)
		bf.tween_property(band, "modulate:a", 100.0 / 255.0, 0.05)
		bf.tween_property(band, "modulate:a", 0.0, 0.1)
		bf.parallel().tween_property(band, "position:x", center.x - vis.x, 0.1)

	# ③ 얼굴 — 밖에서 밀고 들어오며 페이드인
	var man := _man(id)
	var key := "dragon_dragon_%s_critical_%s" % [id, ("e_cut_in" if _awaken else "cut_in")]
	var fp2 := "res://assets/converted/critical_%s/%s.tres" % [id, key]
	if man.has(key) and ResourceLoader.exists(fp2):
		var face := Sprite2D.new()
		face.texture = load(fp2)
		face.scale = Vector2(s, s)
		face.z_index = 5
		var fw: float = face.texture.get_width() * s
		face.position = Vector2(center.x + fw * 0.5, center.y)
		face.modulate.a = 0.0
		_seq_layer.add_child(face)
		var ft := face.create_tween().set_parallel(true)
		ft.tween_property(face, "modulate:a", 1.0, 0.1)
		ft.tween_property(face, "position", center, 0.1)
	Bgm.sfx("effect_cut_in")
	var t := _seq_layer.create_tween()
	t.tween_interval(0.75)
	t.tween_callback(func(): if is_instance_valid(_seq_layer): _seq_layer.queue_free())
