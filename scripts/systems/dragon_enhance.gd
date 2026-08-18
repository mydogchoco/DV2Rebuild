extends RefCounted

const TICKET_ITEM := "dragon_enhance_ticket"

static func material_satisfies(
		use_ticket: bool, ticket_count: int, material_grade: float, required_grade: float) -> bool:
	if use_ticket:
		return ticket_count > 0
	return material_grade >= required_grade
