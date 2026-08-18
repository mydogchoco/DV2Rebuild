extends SceneTree

const LT := preload("res://scripts/ui/battle_log_text.gd")

const CASES := {
	"atk":       [["들판드래곤", "데스웜", 45], "들판드래곤의 공격"],
	"crit":      [["들판드래곤", "데스웜", 45], "크리티컬 공격!"],
	"double":    [["들판드래곤", "데스웜", 45], "더블 공격!"],
	"miss":      [["데스웜", "들판드래곤"], "공격을 피했다."],
	"block":     [["데스웜", "들판드래곤", 45], "공격을 방어하여"],
	"skill_atk": [["들판드래곤", "화염구", "데스웜", 45], "발동하고"],
	"reflect":   [["데스웜", "들판드래곤", "피해반사", 12], "데미지를 주었다."],
	"vamp":      [["들판드래곤", "데스웜", 12], "체력을 12 흡수하였다."],
	"skill_blk": [["들판드래곤", "데스웜", "화염구"], "무효화시켰다."],
	"dot_on":    [["들판드래곤", "데스웜", "중독"], "발동시켰다."],
	"dot":       [["데스웜", 12], "중독 현상 발동~!"],
	"pass":      [["데스웜", 12], "데스웜에게 12의 데미지를 주었다."],
	"confuse":   [["데스웜", "혼란", 12], "스스로를 공격하고"],
	"stop":      ["데스웜", "행동불능 상태에 빠져"],
	"bomb":      [["들판드래곤", "시한폭탄"], "7턴 후 폭발하는"],
}

const SHOT_LINE := "들판드래곤의 공격\n데스웜에게 45의 데미지를 주었다."

func _init() -> void:
	var fails := 0
	var L: Dictionary = LT.L
	if L.is_empty():
		push_error("battle_log_text.gd 의 L 이 비었다 — 로그 템플릿이 사라졌다")
		quit(1)
		return

	var want := CASES.keys(); want.sort()
	var have := L.keys(); have.sort()
	if want != have:
		push_error("템플릿 키 집합 불일치\n  기대: %s\n  실제: %s" % [want, have])
		fails += 1

	for key in CASES.keys():
		if not L.has(key):
			continue
		var tmpl := String(L[key])
		var args = CASES[key][0]
		var need := String(CASES[key][1])
		var out := tmpl % args
		if out == tmpl:
			push_error("[%s] 포맷이 적용되지 않았다(인자 개수 불일치 의심): %s" % [key, tmpl])
			fails += 1
			continue
		if out.find("%") >= 0:
			push_error("[%s] 치환되지 않은 자리표가 남았다: %s" % [key, out])
			fails += 1
		if out.find(need) < 0:
			push_error("[%s] 원작 문구 조각 '%s' 이(가) 없다: %s" % [key, need, out])
			fails += 1

	if L.has("atk"):
		var shot := String(L["atk"]) % ["들판드래곤", "데스웜", 45]
		if shot != SHOT_LINE:
			push_error("원작 스크린샷 줄과 다르다\n  기대: %s\n  실제: %s" % [SHOT_LINE, shot])
			fails += 1

	if fails == 0:
		print("전투 로그 문구 %d종 OK (원작 문자열 · 인자 수 · 스크린샷 줄 일치)" % CASES.size())
	else:
		print("실패 %d건" % fails)
	quit(1 if fails > 0 else 0)
