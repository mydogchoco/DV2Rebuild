extends Node2D
## 로키(800) 단계별 스파인 렌더 캡처 — 변환·모션 저작 결과를 눈으로 대조한다.
## Run: godot --path . res://scenes/shot_loki.tscn -- <out_dir> [anim] [t_ratio] [stage...]
##   anim    재생할 애니(기본 wait). "setup" 이면 아무것도 재생하지 않는다.
##   t_ratio 애니 길이의 몇 지점을 찍을지 0~1 (기본 0.35)
const STAGES := ["baby", "child", "adult", "aura", "e"]
## 원본 스켈레톤 높이(drake 별로 10배 차이) 기준으로 화면 높이에 맞춘 배율.
## child1 122 · child2 210 · adult 289 · transcended 390 · 288 798 (포팅 카드 §1)
const SKEL_H := {"baby": 122.0, "child": 210.0, "adult": 289.0, "aura": 390.0, "e": 798.0}
const FIT_PX := 620.0

var _out := ""
var _anim := "wait"
var _ratio := 0.35
var _stages: Array = []
var _id := 800          # 대조군을 찍을 때 다른 드래곤 id 를 넘긴다(--id 1)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	if args.size() > 1: _anim = args[1]
	if args.size() > 2: _ratio = float(args[2])
	for i in range(3, args.size()):
		if args[i].begins_with("id="):
			_id = int(args[i].substr(3))
		else:
			_stages.append(args[i])
	if _stages.is_empty():
		_stages = STAGES
	_run()

func _run() -> void:
	var vis := get_viewport_rect().size
	for stage in _stages:
		var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [_id, stage]
		if not ResourceLoader.exists(path):
			print("[skip] no scene: ", path)
			continue
		var holder := Node2D.new()
		# 이 스켈레톤들의 root 는 발밑이 아니라 **몸통 부근**이다(실측: 화면 앵커를 중심으로
		# 위아래로 고르게 뻗는다) → 화면 정중앙에 두고 스켈레톤 높이로 배율을 맞춘다.
		holder.position = vis * 0.5
		var s: float = FIT_PX / float(SKEL_H.get(stage, 400.0))
		holder.scale = Vector2(s, s)
		add_child(holder)
		var inst = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		var played := "-"
		if ap != null and _anim != "setup" and ap.has_animation(_anim):
			ap.play(_anim)
			ap.advance(ap.get_animation(_anim).length * _ratio)
			played = _anim
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/loki%d_%s_%s.png" % [_out, _id, stage, _anim])
		var anims := ap.get_animation_list() if ap != null else PackedStringArray()
		print("%-6s anims=%s played=%s" % [stage, str(anims), played])
		holder.queue_free()
		await get_tree().process_frame
	print("saved to ", _out)
	get_tree().quit()
