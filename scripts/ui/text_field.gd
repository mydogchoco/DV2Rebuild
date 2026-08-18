class_name TextField
static func value(edit: LineEdit) -> String:
	if edit == null:
		return ""
	if edit.has_method("apply_ime"):
		edit.apply_ime()
	return edit.text.strip_edges()

static func no_steal(root: Node) -> void:
	if root is BaseButton:
		(root as BaseButton).focus_mode = Control.FOCUS_NONE
	for c in root.get_children():
		no_steal(c)
