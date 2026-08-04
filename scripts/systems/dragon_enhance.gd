extends RefCounted
## 드래곤 강화(장비 슬롯 확장)의 재료 대체 규칙.

const TICKET_ITEM := "dragon_enhance_ticket"

## 강화권은 회차별 요구 등급과 관계없이 재료 드래곤 한 마리를 대체한다.
## 강화권을 쓰지 않는 기존 경로는 재료 드래곤의 등급 하한을 그대로 검사한다.
static func material_satisfies(
		use_ticket: bool, ticket_count: int, material_grade: float, required_grade: float) -> bool:
	if use_ticket:
		return ticket_count > 0
	return material_grade >= required_grade
