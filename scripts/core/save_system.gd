extends Node
## Autoload "SaveSystem": 순수 저장 엔진 (CLAUDE.md §5).
## 게임 데이터의 "의미"는 모른다 — Dictionary를 받아 user://에 직렬화/역직렬화만 한다.
## 유저 상태의 스키마/접근 API는 UserDB(user_db.gd)가 담당한다. (관심사 분리)

const SAVE_NAME := "save_0.json"
const BACKUP_NAME := "save_0.bak.json"
const SAVE_PATH := "user://" + SAVE_NAME
const BACKUP_PATH := "user://" + BACKUP_NAME

## data를 디스크에 저장. 덮어쓰기 전에 기존 세이브를 백업으로 복사(쓰기 중단 대비).
func save(data: Dictionary) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[Save] cannot write " + SAVE_PATH); return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

## 세이브를 읽어 Dictionary로 반환. 없거나 손상되면 백업을 시도, 그래도 없으면 null.
func load_or_backup() -> Variant:
	var d = _read(SAVE_PATH)
	if d != null:
		return d
	var b = _read(BACKUP_PATH)
	if b != null:
		push_warning("[Save] 메인 세이브 손상/부재 → 백업에서 복구")
	return b

func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Save] corrupt JSON: " + path)
		return null
	return parsed

## 세이브 파일 삭제(새 게임 등). 백업은 남겨둔다.
func clear() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists(SAVE_NAME):
		dir.remove(SAVE_NAME)
