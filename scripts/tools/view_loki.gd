extends Node2D
## 로키(800) 스파인 **뷰어 창** — 변환·저작 결과를 눈으로 돌려 보는 용도.
##
## `shot_loki.gd` 는 PNG 를 굽고 바로 종료하므로 창으로는 못 본다. 이쪽은 창을 띄운 채
## 단계·애니를 바꿔 가며 재생한다. 검증(회귀)은 `test_loki800.gd` 가 하고, 이건 **육안 확인**용.
##
## Run: godot --path . res://scenes/view_loki.tscn
##      godot --path . res://scenes/view_loki.tscn -- id=1      (대조군: 다른 드래곤)
##
## 조작: ← → 단계 · ↑ ↓ 애니 · Space 다시재생 · 1~9 배속 · Esc 종료
const STAGES := ["baby", "child", "adult", "aura", "e", "advent"]
const ANIMS := ["wait", "love", "attack"]
## 원본 스켈레톤 높이(포팅 카드 §1) — 단계마다 4배 넘게 차이 나서 그대로 두면 비교가 안 된다.
const SKEL_H := {"baby": 122.0, "child": 210.0, "adult": 289.0, "aura": 390.0, "e": 798.0,
	"advent": 491.0}
const FIT_PX := 560.0

var _id := 800
var _si := 2                # 성체부터 — 가장 대표적인 단계
var _ai := 0
var _speed := 1.0
var _holder: Node2D = null
var _ap: AnimationPlayer = null
var _label: Label = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("id="):
			_id = int(a.substr(3))
	get_window().title = "로키 뷰어 — 드빌1 이식 확인"

	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.17, 0.20)
	bg.size = get_viewport_rect().size
	bg.z_index = -100
	add_child(bg)

	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	add_child(_label)

	var help := Label.new()
	help.position = Vector2(16, get_viewport_rect().size.y - 34)
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color(1, 1, 1, 0.55)
	help.text = "← → 단계   ↑ ↓ 애니   Space 다시재생   1~9 배속   Esc 종료"
	add_child(help)

	_spawn()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match (e as InputEventKey).keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_RIGHT:
			_si = (_si + 1) % STAGES.size(); _spawn()
		KEY_LEFT:
			_si = (_si - 1 + STAGES.size()) % STAGES.size(); _spawn()
		KEY_DOWN:
			_ai = (_ai + 1) % ANIMS.size(); _play()
		KEY_UP:
			_ai = (_ai - 1 + ANIMS.size()) % ANIMS.size(); _play()
		KEY_SPACE:
			_play()
		_:
			var k: int = (e as InputEventKey).keycode
			if k >= KEY_1 and k <= KEY_9:
				_speed = float(k - KEY_0) / 2.0   # 1=0.5배 … 9=4.5배
				if _ap != null:
					_ap.speed_scale = _speed
				_status()


## 단계 교체 — 씬을 새로 인스턴스하고 스켈레톤 높이로 배율을 맞춘다.
func _spawn() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null
		_ap = null
	var stage: String = STAGES[_si]
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [_id, stage]
	if not ResourceLoader.exists(path):
		_status("씬 없음: " + path)
		return
	_holder = Node2D.new()
	# 이 스켈레톤들의 root 는 발밑이 아니라 몸통 부근이다(포팅 카드) → 화면 중앙 기준.
	_holder.position = get_viewport_rect().size * 0.5
	var s: float = FIT_PX / float(SKEL_H.get(stage, 400.0))
	_holder.scale = Vector2(s, s)
	add_child(_holder)
	_holder.add_child((load(path) as PackedScene).instantiate())
	_ap = _holder.get_child(0).get_node_or_null("AnimationPlayer")
	_play()


func _play() -> void:
	if _ap == null:
		_status("AnimationPlayer 없음")
		return
	var an: String = ANIMS[_ai]
	if not _ap.has_animation(an):
		_status("애니 없음: " + an)
		return
	_ap.speed_scale = _speed
	_ap.play(an)
	_status()


func _status(extra := "") -> void:
	var an: String = ANIMS[_ai]
	var ln := 0.0
	if _ap != null and _ap.has_animation(an):
		ln = _ap.get_animation(an).length
	_label.text = "%d  %s   [%s %.2fs]   x%.1f   %s" % [
		_id, STAGES[_si], an, ln, _speed, extra]
