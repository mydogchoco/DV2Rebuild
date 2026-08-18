class_name UiText
extends RefCounted

const PUBLISHED := "res://data/ui_text.json"
const SIDECAR := "res://data/text/ui_text.json"

static var _table: Dictionary = {}
static var _loaded := false

static func get_text(key: String) -> String:
	if not _loaded:
		_loaded = true
		var path := SIDECAR if FileAccess.file_exists(SIDECAR) else PUBLISHED
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_table = d
	var v := String(_table.get(key, ""))
	return v if v != "" else key

static func reload() -> void:
	_loaded = false
	_table = {}
