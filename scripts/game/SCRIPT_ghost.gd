class_name Ghost
extends MazeActor

# A GHOST. MODEL_ghost.glb is white with black detail, so `color` multiplies the
# whole model: the body takes the colour and the eyes and markings stay black.
# The classic four are set in SCENE_arena: red, pink, cyan and orange.
#
# FOR NOW IT WANDERS: at each junction it takes a random way on, never straight
# back unless it has to. In the ghost house it heads for the door instead, and the
# door ('-') lets it out but never back in. The arcade's chase and scatter targets
# come later; they slot in here, in `_choose_dir`.

@export var color := Color.WHITE:
	set(v):
		color = v
		set_tint(v)
## Gentle hover, metres and cycles per second.
@export var bob_height := 0.08
@export var bob_rate := 1.6

const HOUSE_MIN := Vector2i(11, 13)
const HOUSE_MAX := Vector2i(16, 15)
const HOUSE_EXIT := Vector2i(13, 11)

var _rng := RandomNumberGenerator.new()
var _t := 0.0


func _init() -> void:
	# The ghost's own body; the rest of MODEL_ghost.glb is a stray Mac-Pan.
	keep_only = "Sphere_002"


func _ready() -> void:
	super()
	_rng.seed = hash(name)
	_t = _rng.randf() * TAU
	set_tint(color)


func can_enter(from: Vector2i, to: Vector2i) -> bool:
	if maze == null or maze.is_wall(to):
		return false
	if maze.tile_char(to) == "-":
		return to.y < from.y  # out through the door, upward only
	return true


func _in_house(t: Vector2i) -> bool:
	return t.x >= HOUSE_MIN.x and t.x <= HOUSE_MAX.x and t.y >= HOUSE_MIN.y and t.y <= HOUSE_MAX.y


func _choose_dir(at: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]:
		if d != -_dir and can_enter(at, at + d):
			options.append(d)
	if options.is_empty():
		return -_dir
	if _in_house(at) or maze.tile_char(at) == "-":
		var best := options[0]
		for d in options:
			if Vector2(at + d).distance_to(Vector2(HOUSE_EXIT)) \
					< Vector2(at + best).distance_to(Vector2(HOUSE_EXIT)):
				best = d
		return best
	return options[_rng.randi() % options.size()]


func _after_move(delta: float, _travelled: float) -> void:
	_t += delta * bob_rate * TAU
	if _model != null:
		_model.position.y = model_lift + sin(_t) * bob_height
