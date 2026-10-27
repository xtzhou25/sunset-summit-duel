extends RefCounted
## Match-level entropy is isolated from combat/AI and sampled only by begin_match.
const Characters = preload("res://scripts/characters.gd")
var rng := RandomNumberGenerator.new()
var requested := -1
var resolved := 1
var draws := 0

func _init() -> void:
	rng.randomize()

func begin_match(player: int, choice: int = -1) -> int:
	player = Characters.valid_kind(player)
	requested = choice if choice >= 0 and choice < Characters.COUNT and choice != player else -1
	if requested >= 0:
		resolved = requested
	else:
		# Uniform draw from four indices, mapped past the player's stable role ID.
		var pick := rng.randi_range(0, Characters.COUNT - 2)
		resolved = pick if pick < player else pick + 1
		draws += 1
	return resolved
