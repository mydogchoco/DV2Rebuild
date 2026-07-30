class_name CocosParticle
extends RefCounted
## render 층 공용 — 원작 Cocos 파티클(assets/converted/particles/<name>.json, particle_export.py)
## → CPUParticles2D 1회 발사. 원래 battle.gd::_levelup_particle 에만 있었는데 레벨업 화면
## (cave.gd ExpLayer 이식)도 같은 파티클을 쓰므로 여기로 뽑아 둘이 공유한다.
## CLAUDE.md §3 "같은 일을 하는 헬퍼가 이미 있는지 grep" — 새로 짜지 말고 이걸 부를 것.

## 부드러운 원형 점 텍스처(파티클 공용) — 원작 user_particle.png 대체(절차 생성, 견고).
static var _dot_tex: GradientTexture2D

static func dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(0.5, 0.0)
		_dot_tex.width = 32; _dot_tex.height = 32
	return _dot_tex

## 1회 발사. 반환 = 생성한 노드(없으면 null). explosiveness 는 원작 duration<0(연속) 여부를
## 모사할 호출측 노브 — 배지/버스트류는 0.9, 흐름류는 0.5 가 관례(battle.gd 종전 값).
static func spawn(parent: Node, name: String, pos: Vector2, z := 131,
		explosiveness := 0.5, amount_cap := 160) -> CPUParticles2D:
	var path := "res://assets/converted/particles/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var c = JSON.parse_string(f.get_as_text())
	if typeof(c) != TYPE_DICTIONARY:
		return null
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = z
	p.texture = dot()
	p.one_shot = true
	p.explosiveness = explosiveness
	p.amount = clampi(int(c.get("amount", 80)), 8, amount_cap)
	p.lifetime = float(c.get("lifetime", 1.0))
	p.lifetime_randomness = clampf(float(c.get("lifetime_randomness", 0.0)), 0.0, 1.0)
	var dir: Array = c.get("direction", [0, -1])
	p.direction = Vector2(float(dir[0]), float(dir[1]))
	p.spread = float(c.get("spread", 0.0))
	p.initial_velocity_min = float(c.get("vmin", 0.0))
	p.initial_velocity_max = float(c.get("vmax", 0.0))
	var grav: Array = c.get("gravity", [0, 0])
	p.gravity = Vector2(float(grav[0]), float(grav[1]))
	p.radial_accel_min = float(c.get("radial_min", 0.0))
	p.radial_accel_max = float(c.get("radial_max", 0.0))
	p.tangential_accel_min = float(c.get("tangential_min", 0.0))
	p.tangential_accel_max = float(c.get("tangential_max", 0.0))
	p.scale_amount_min = float(c.get("scale_min", 1.0))
	p.scale_amount_max = float(c.get("scale_max", 1.0))
	var end_ratio := float(c.get("scale_end_ratio", 1.0))
	if not is_equal_approx(end_ratio, 1.0):
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, maxf(0.01, end_ratio)))
		p.scale_amount_curve = curve
	var em: Array = c.get("emit_rect", [0, 0])
	if float(em[0]) > 0.0 or float(em[1]) > 0.0:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(float(em[0]), float(em[1]))
	var cs: Array = c.get("color_start", [1, 1, 1, 1])
	var ce: Array = c.get("color_end", [1, 1, 1, 1])
	var grad := Gradient.new()
	grad.set_color(0, Color(cs[0], cs[1], cs[2], cs[3]))
	grad.set_color(1, Color(ce[0], ce[1], ce[2], ce[3]))
	p.color_ramp = grad
	if bool(c.get("additive", false)):
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat
	p.emitting = true
	parent.add_child(p)
	parent.get_tree().create_timer(float(c.get("lifetime", 1.0)) + 0.6).timeout.connect(p.queue_free)
	return p
