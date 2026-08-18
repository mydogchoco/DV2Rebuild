extends Node

const TAG := "[ccreset]"

func _ready() -> void:
	await get_tree().process_frame
	UserDB.begin_batch()

	var args := OS.get_cmdline_user_args()
	var apply := "--apply" in args
	var dump := "--dump" in args
	var code := "eigenvector"
	for a in args:
		if a.begins_with("--code="):
			code = a.substr(7)

	var table: Dictionary = Data.card_codes
	var used_any = UserDB.get_pmeta("used_card_codes", [])
	var used: Array = (used_any as Array) if used_any is Array else []

	if dump:
		_dump(used, table)
		get_tree().quit()
		return

	var mark := CardCode.used_key(code, table)
	if mark.is_empty():
		print("%s 코드가 비어 있거나 정규화 결과가 없다: %s" % [TAG, code])
		get_tree().quit()
		return

	var info := CardCode.lookup(code, table)
	if info.is_empty():
		print("%s 표에서 못 찾은 코드다 — 오타 의심. 아무것도 바꾸지 않았다: %s" % [TAG, code])
		get_tree().quit()
		return
	var limit := int(info.get("uses", 1 if bool(info.get("once", true)) else 0))

	var kept: Array = []
	var removed := 0
	for m in used:
		if String(m) == mark:
			removed += 1
		else:
			kept.append(m)

	print("%s 코드=%s (정규화=%s)" % [TAG, code, CardCode.normalize(code)])
	print("%s   해시=%s" % [TAG, mark])
	print("%s   사용제한=%s / 지금까지 사용=%d" % [
		TAG, "무제한" if limit <= 0 else str(limit) + "회", removed])
	print("%s   used_card_codes: %d칸 → %d칸 (제거 %d, 다른 코드 %d칸 유지)" % [
		TAG, used.size(), kept.size(), removed, kept.size()])

	if removed == 0:
		print("%s 지울 이력이 없다 — 이미 0회다. 저장하지 않는다." % TAG)
		get_tree().quit()
		return

	UserDB.set_pmeta("used_card_codes", kept)
	if apply:
		UserDB.save()
		print("%s 저장 완료 — 이 코드만 %d회 → 0회." % [TAG, removed])
	else:
		print("%s 미리보기(--apply 없음) — 저장하지 않았다." % TAG)
	get_tree().quit()

func _dump(used: Array, table: Dictionary) -> void:
	print("%s used_card_codes %d칸" % [TAG, used.size()])
	var counts := {}
	for m in used:
		var k := String(m)
		counts[k] = int(counts.get(k, 0)) + 1
	var ids: Array = []
	for e in table.get("entries", []):
		ids.append(String((e as Dictionary).get("id", "")))
	for k in counts.keys():
		var idx := ids.find(String(k))
		print("%s   %s… x%d  (표 항목 #%s)" % [
			TAG, String(k).substr(0, 16), int(counts[k]),
			str(idx) if idx >= 0 else "표에 없음"])
