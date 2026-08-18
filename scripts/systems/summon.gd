class_name Summon
extends RefCounted

const FLAG_UNLOCK := "68c55dc64051b3eeca117e5cf77d59fe"

const EGG_ENHANCE_STEP := 1

const SPECIES_DEF := 600
const SPECIES_ATK := 700
const SPECIES := [SPECIES_DEF, SPECIES_ATK]

static func unlocked(meta_flag: bool) -> bool:
	return meta_flag

static func species_available(species: int, owned_step: int) -> bool:
	return SPECIES.has(species) and owned_step <= 0

static func available_species(steps: Dictionary) -> Array:
	var out := []
	for s in SPECIES:
		if species_available(int(s), int(steps.get(s, 0))):
			out.append(s)
	return out

const MATERIAL_MIN_LEVEL := 45
const MATERIAL_MIN_GRADE := 10.0

static func can_be_material(inst: Dictionary, grade := -1.0) -> bool:
	if inst.is_empty():
		return false
	if bool(inst.get("egg", false)) or bool(inst.get("locked", false)):
		return false
	if SPECIES.has(int(inst.get("id", 0))):
		return false
	if int(inst.get("level", 0)) < MATERIAL_MIN_LEVEL:
		return false
	return grade >= MATERIAL_MIN_GRADE

static func plan(species: int, material: Dictionary, material_master: Dictionary,
		flag: bool, owned_step: int, material_grade := -1.0) -> Dictionary:
	if not unlocked(flag):
		return {}
	if not species_available(species, owned_step):
		return {}
	if not can_be_material(material, material_grade):
		return {}
	var grade := Hatchery.GRADE_MAX
	var nick := String(material.get("nickname", ""))
	return {
		"species": species,
		"grade": grade,
		"seconds": Hatchery.hatch_seconds(grade),
		"inherit": {
			"art_id": int(material_master.get("art_id", material.get("id", 0))),
			"element": material_master.get("element", null),
			"nickname": nick,
			"name": nick if nick != "" else String(material_master.get("name", "")),
		},
	}
