class_name Design
## render(scene) 층 좌표 규약 헬퍼 — 원작 Cocos2d-x 배치를 Godot로 이식할 때 쓴다.
## 근거: docs/ref/orig_code/probe/resolution_probe.c (AppDelegate::setDesignResolutionAndResourceDirectory).
##   원작 정책 = FIXED_HEIGHT: **높이 692 고정, 너비는 기기 비율로 가변**(line 494:
##   CCSize(w * (692/deviceH), 692)). 참조 landscape는 1024×692(line 79).
## 좌표계 변환: Cocos는 y-up(화면 아래가 0), Godot는 y-down(화면 위가 0). ⇒ godot_y = H - cocos_y.
##
## ⚠️ CLAUDE.md §10.2: 이 파일은 render 층 보조 유틸이다. logic/data 층(scripts/systems,
##    scripts/core의 규칙 코드, data/*.json)은 이 클래스를 참조하지 않는다. 순수 함수라 헤드리스 검증 가능.
##
## 원작 렌더 레시피(docs/ref/design/render_recipe_*.md)의 좌표를 옮길 때:
##   - 전체화면 리터럴 Cocos 좌표      → to_godot(cocos)
##   - 고정크기 셀(슬롯) 내부 좌표      → in_cell(cocos, cell_size)   (레시피 §2 규약)
##   - VisibleRect 앵커(중앙/좌/우/모서리) → visible_point(visible, ax, ay) + Godot 오프셋

const DESIGN_HEIGHT := 692.0                       # FIXED_HEIGHT base (docs/ref/orig_code/probe/resolution_probe.c:494)
const REF_WIDTH := 1024.0                          # 참조 landscape 너비 (docs/ref/orig_code/probe/resolution_probe.c:79)
const REF_SIZE := Vector2(REF_WIDTH, DESIGN_HEIGHT)

# ============================================================ y-flip (Cocos y-up → Godot y-down)

## Cocos y → Godot y. 전체화면은 h=DESIGN_HEIGHT, 셀 내부는 h=셀 높이.
static func flip_y(cocos_y: float, h := DESIGN_HEIGHT) -> float:
	return h - cocos_y

## 전체화면 Cocos 좌표(높이 692 기준) → Godot 좌표.
static func to_godot(cocos: Vector2, h := DESIGN_HEIGHT) -> Vector2:
	return Vector2(cocos.x, h - cocos.y)

## 고정크기 셀(슬롯) 내부 Cocos 좌표 → Godot 좌표 (레시피 §2: godot_y = cellH - cocos_y).
static func in_cell(cocos: Vector2, cell_size: Vector2) -> Vector2:
	return Vector2(cocos.x, cell_size.y - cocos.y)

# ============================================================ VisibleRect 앵커

## 원작 VisibleRect의 분수 앵커를 Godot 좌표점으로. visible = 현재 가시영역 픽셀크기(뷰포트 크기).
##   ax: 0=왼쪽, 0.5=가로중앙, 1=오른쪽.  ay: 0=아래(Cocos bottom), 0.5=중앙, 1=위(Cocos top).
## 반환점에 **Godot(y-down) 오프셋**을 더해 최종 배치한다.
##   예) 우상단 X버튼(rightTop, 안쪽 50): visible_point(vis, 1, 1) + Vector2(-50, 50)
##       배틀 팀 대칭(centerX ± spread): visible_point(vis, 0.5, 0.5) + Vector2(±spread, -35)
## 원작이 x를 중앙/좌/우 기준으로 잡으므로 16:9 넓은 폭에서도 가장자리 정렬·좌우 대칭이 그대로 유지된다.
static func visible_point(visible: Vector2, ax: float, ay: float) -> Vector2:
	return Vector2(visible.x * ax, visible.y * (1.0 - ay))

# 자주 쓰는 앵커 단축 (전부 Godot 좌표점 반환)
static func center(visible: Vector2) -> Vector2: return visible_point(visible, 0.5, 0.5)
static func left(visible: Vector2) -> Vector2:   return visible_point(visible, 0.0, 0.5)
static func right(visible: Vector2) -> Vector2:  return visible_point(visible, 1.0, 0.5)
static func top(visible: Vector2) -> Vector2:    return visible_point(visible, 0.5, 1.0)
static func bottom(visible: Vector2) -> Vector2: return visible_point(visible, 0.5, 0.0)

# ============================================================ 스케일

## setContentScaleFactor 대응(docs/ref/orig_code/probe/resolution_probe.c:490). 실제 뷰포트 높이 → 에셋 스케일 배수.
static func content_scale(actual_height: float) -> float:
	return actual_height / DESIGN_HEIGHT

# ------------------------------------------------------------ 에셋 → 디자인공간 배율
# 원작은 `DV2/480/` 아틀라스를 **리소스 기준 해상도 768×519**로 저작하고, 화면은 높이 692로 잡은 뒤
#   setContentScaleFactor(519/692 = 0.75)
# 를 걸었다. Cocos에서 contentScaleFactor는 "픽셀 → 포인트" 나눗셈이라, 프레임 N픽셀짜리 스프라이트는
# 디자인 공간에서 N/0.75 = **N × 4/3 포인트**로 그려진다.
#   근거: docs/ref/orig_code/probe/resolution_probe.c:60 `CCSize(768.0, 519.0)`(리소스 크기),
#         :79 `CCSize(1024.0, 692.0)`(참조 디자인), :494 `CCSize(w*(692/deviceH), 692)`,
#         :492 `setContentScaleFactor(DAT_029ee2b8 / DAT_029ee32c)` = 519/692.
#   실측 교차검증(docs/ref/orig_image/battle): 몬스터 네임플레이트 `monster_box`(476px) → 스크린샷 665px,
#         스크린샷 높이 735/692=1.062 보정 시 626 디자인px → 626/476 = **1.315**;
#         드래곤 카드 `stat_box_frame1`(227px) → 318px → 299 디자인px → 299/227 = **1.317**.
#   ⇒ 두 실측 모두 4/3(1.333)에 수렴. 아틀라스 프레임은 이 배율로 그려야 원작과 크기가 맞는다.
# ⚠️ `setContentSize()`로 크기를 **명시**한 Scale9/라벨은 이미 포인트 단위이므로 여기에 곱하지 않는다.
const RESOURCE_HEIGHT := 519.0                     # docs/ref/orig_code/probe/resolution_probe.c:60
const ASSET_SCALE := DESIGN_HEIGHT / RESOURCE_HEIGHT   # = 4/3

## 아틀라스 프레임 픽셀 크기 → 디자인 공간 포인트.
static func px(n: float) -> float:
	return n * ASSET_SCALE

static func px2(v: Vector2) -> Vector2:
	return v * ASSET_SCALE
