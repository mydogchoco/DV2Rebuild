extends Node
## Autoload "RNG": single seedable RNG so gacha/breeding/battle rolls are reproducible.
## Set a fixed seed for debugging (§5 data model). All random gameplay should use this.

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0

func _ready() -> void:
	randomize()

func randomize() -> void:
	_rng.randomize()
	seed_value = _rng.seed

func set_seed(s: int) -> void:
	seed_value = s
	_rng.seed = s

func randf() -> float:
	return _rng.randf()

func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)

func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)

## True with probability p (0..1). Use for crit/dodge/block/gacha.
func chance(p: float) -> bool:
	return _rng.randf() < p

## Weighted pick: weights={key:weight} -> key.
func weighted(weights: Dictionary):
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var r := _rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys().back()
