class_name Design

const DESIGN_HEIGHT := 692.0
const REF_WIDTH := 1024.0
const REF_SIZE := Vector2(REF_WIDTH, DESIGN_HEIGHT)

static func flip_y(cocos_y: float, h := DESIGN_HEIGHT) -> float:
	return h - cocos_y

static func to_godot(cocos: Vector2, h := DESIGN_HEIGHT) -> Vector2:
	return Vector2(cocos.x, h - cocos.y)

static func in_cell(cocos: Vector2, cell_size: Vector2) -> Vector2:
	return Vector2(cocos.x, cell_size.y - cocos.y)

static func visible_point(visible: Vector2, ax: float, ay: float) -> Vector2:
	return Vector2(visible.x * ax, visible.y * (1.0 - ay))

static func center(visible: Vector2) -> Vector2: return visible_point(visible, 0.5, 0.5)
static func left(visible: Vector2) -> Vector2:   return visible_point(visible, 0.0, 0.5)
static func right(visible: Vector2) -> Vector2:  return visible_point(visible, 1.0, 0.5)
static func top(visible: Vector2) -> Vector2:    return visible_point(visible, 0.5, 1.0)
static func bottom(visible: Vector2) -> Vector2: return visible_point(visible, 0.5, 0.0)

static func content_scale(actual_height: float) -> float:
	return actual_height / DESIGN_HEIGHT

const RESOURCE_HEIGHT := 519.0
const ASSET_SCALE := DESIGN_HEIGHT / RESOURCE_HEIGHT

static func px(n: float) -> float:
	return n * ASSET_SCALE

static func px2(v: Vector2) -> Vector2:
	return v * ASSET_SCALE
