class_name Ghost
extends MazeActor

# A GHOST, steered the arcade's way (after Jamey Pittman's "The Pac-Man Dossier").
#
# THE DECISION. Every time a ghost reaches a tile centre it picks its next way on
# from the exits it may take — never straight back the way it came, never up out
# of the four NO_UP tiles (the two above the ghost house and the two above
# Mac-Pan's start), never through hedge — choosing the one whose next tile is
# nearest, in a straight line, to its TARGET TILE. Ties go up, left, down, right.
# The target is all that differs between the four:
#
#   Blinky  Mac-Pan's own tile.
#   Pinky   four tiles ahead of Mac-Pan. Facing up, also four to the left: the
#           arcade's overflow bug, kept because it is how Pinky really plays.
#   Inky    take the point two ahead of Mac-Pan (same bug facing up), then double
#           the vector from Blinky to it. Inky needs Blinky to know where to go.
#   Clyde   Mac-Pan while eight or more tiles away; inside that, his corner.
#
# In SCATTER (ArcadeGame's timetable) each heads for its own corner instead, just
# past the board: Blinky top right, Pinky top left, Inky bottom right, Clyde bottom
# left — and goes round the hedge block there. Cruise Elroy (Blinky late in a
# board) keeps chasing through scatter. FRIGHTENED, a ghost picks among the same
# exits at random, and NO_UP does not apply.
#
# STATES: HOUSE (bobbing inside until ArcadeGame releases it), LEAVING (to the
# door and out), ACTIVE (the above), EATEN (a wisp racing back to the door) and
# ENTERING (down through the door to revive, then LEAVING again).
#
# A REVERSAL (mode change, power pellet) turns an active ghost round on the spot;
# one in the house takes it as "leave to the right instead of the left".
#
# MODEL_ghost.glb is white with black detail, so `color` multiplies the whole
# model: the body takes the colour and the eyes and markings stay black. That is
# also how it goes blue, and white when the fright is about to end.

enum Personality { BLINKY, PINKY, INKY, CLYDE }
enum State { HOUSE, LEAVING, ACTIVE, EATEN, ENTERING }

@export var color := Color.WHITE:
	set(v):
		color = v
		set_tint(v)
@export var frightened_color := Color(0.12, 0.2, 1.0)
@export var flash_color := Color(1.0, 1.0, 1.0)
@export var eaten_color := Color(0.8, 0.95, 1.0)
## How much of an eaten ghost is gone: what races home is a wisp of it.
@export_range(0.0, 1.0) var eaten_dissolve := 0.72
## Gentle hover, metres and cycles per second.
@export var bob_height := 0.08
@export var bob_rate := 1.6

const HOUSE_MIN := Vector2i(11, 13)
const HOUSE_MAX := Vector2i(16, 15)
## The tile above the door: where a ghost comes out, and where its eyes go home to.
const HOUSE_EXIT := Vector2i(13, 11)
## Inside, under the door: where an eaten ghost revives.
const HOUSE_HOME_ROW := 14
## No turning up out of these unless frightened (the arcade's "red zones").
const NO_UP: Array[Vector2i] = [Vector2i(12, 11), Vector2i(15, 11), Vector2i(12, 23), Vector2i(15, 23)]
## Scatter corners, just off the board (the arcade's, shifted to this layout).
const SCATTER := {
	Personality.BLINKY: Vector2i(25, -3),
	Personality.PINKY: Vector2i(2, -3),
	Personality.INKY: Vector2i(27, 32),
	Personality.CLYDE: Vector2i(0, 32),
}
const ORDER: Array[Vector2i] = [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]

var personality := Personality.BLINKY
var state := State.ACTIVE
var frightened := false
## Set by ArcadeGame: the rules, Mac-Pan and Blinky (for Inky) come from it.
var game: ArcadeGame

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _pending_reverse := false
var _exit_right := false


func _init() -> void:
	# The ghost's own body; the rest of MODEL_ghost.glb is a stray Mac-Pan.
	keep_only = "Sphere_002"


func _enter_tree() -> void:
	match String(name).to_lower():
		"pinky": personality = Personality.PINKY
		"inky": personality = Personality.INKY
		"clyde": personality = Personality.CLYDE
		_: personality = Personality.BLINKY
	state = State.ACTIVE if personality == Personality.BLINKY else State.HOUSE


func _ready() -> void:
	super()
	_rng.seed = hash(name)
	_t = _rng.randf() * TAU
	set_tint(color)


## Back to the start of a round: Blinky outside, the rest in the house.
func start_round() -> void:
	respawn()
	frightened = false
	_pending_reverse = false
	_exit_right = false
	state = State.ACTIVE if personality == Personality.BLINKY else State.HOUSE
	_update_look()


# ---------------------------------------------------------------- game API

func in_house() -> bool:
	return state == State.HOUSE


## Let a ghost out of the house.
func release() -> void:
	if state == State.HOUSE:
		state = State.LEAVING


## A power pellet: blue, and turn round. Eyes on their way home are not affected.
func frighten() -> void:
	if state == State.EATEN or state == State.ENTERING:
		return
	frightened = true
	request_reverse()
	_update_look()


func unfrighten() -> void:
	frightened = false
	_update_look()


## Turn round at the next chance (a scatter/chase switch, a power pellet).
func request_reverse() -> void:
	match state:
		State.ACTIVE:
			_pending_reverse = true
		State.HOUSE, State.LEAVING:
			_exit_right = true


## Mac-Pan caught it while blue: back to the house as a wisp.
func eat() -> void:
	frightened = false
	state = State.EATEN
	_pending_reverse = false
	_update_look()


## Can it kill Mac-Pan / be eaten by him, right now?
func is_solid() -> bool:
	return state == State.ACTIVE or (state == State.LEAVING and tile().y <= HOUSE_EXIT.y + 1)


func is_eyes() -> bool:
	return state == State.EATEN or state == State.ENTERING


# ---------------------------------------------------------------- movement

func can_enter(from: Vector2i, to: Vector2i) -> bool:
	if maze == null or maze.is_wall(to):
		return false
	if maze.tile_char(to) == "-":
		match state:
			State.LEAVING:
				return to.y < from.y
			State.EATEN, State.ENTERING:
				return to.y > from.y
			_:
				return false
	if state == State.HOUSE and not _in_house(to):
		return false
	return true


func _in_house(t: Vector2i) -> bool:
	return t.x >= HOUSE_MIN.x and t.x <= HOUSE_MAX.x and t.y >= HOUSE_MIN.y and t.y <= HOUSE_MAX.y


func _before_move(_delta: float) -> void:
	if game != null:
		speed = game.ghost_speed(self)
	if _pending_reverse and state == State.ACTIVE and not is_teleporting():
		_pending_reverse = false
		reverse()


func _choose_dir(at: Vector2i) -> Vector2i:
	match state:
		State.HOUSE:
			if at.y <= HOUSE_MIN.y:
				return Vector2i.DOWN
			if at.y >= HOUSE_MAX.y:
				return Vector2i.UP
			return _dir if _dir.x == 0 and _dir != Vector2i.ZERO else Vector2i.UP
		State.LEAVING:
			if at.y <= HOUSE_EXIT.y:
				state = State.ACTIVE
				var out := Vector2i.RIGHT if _exit_right else Vector2i.LEFT
				_exit_right = false
				_dir = out
				return out
			if at.x != HOUSE_EXIT.x and at.y > HOUSE_EXIT.y + 1:
				return Vector2i.LEFT if at.x > HOUSE_EXIT.x else Vector2i.RIGHT
			return Vector2i.UP
		State.EATEN:
			if at.y == HOUSE_EXIT.y and (at.x == HOUSE_EXIT.x or at.x == HOUSE_EXIT.x + 1):
				state = State.ENTERING
				return Vector2i.DOWN
			return _steer(at, HOUSE_EXIT, false)
		State.ENTERING:
			if at.y >= HOUSE_HOME_ROW:
				# Home: revive, and straight back out.
				state = State.LEAVING
				_update_look()
				return _choose_dir(at)
			return Vector2i.DOWN
	# ACTIVE
	if frightened:
		var opts := _options(at, true)
		return opts[_rng.randi() % opts.size()] if not opts.is_empty() else -_dir
	return _steer(at, target_tile(), true)


# The exits a ghost may take from `at`: not back, not into hedge, and not up out
# of a NO_UP tile when `restrict` is on.
func _options(at: Vector2i, restrict: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in ORDER:
		if d == -_dir:
			continue
		if not can_enter(at, at + d):
			continue
		if restrict and d == Vector2i.UP and not frightened and NO_UP.has(at):
			continue
		out.append(d)
	return out


# The exit whose next tile is nearest `target`; ties in ORDER (up, left, down, right).
func _steer(at: Vector2i, target: Vector2i, restrict: bool) -> Vector2i:
	var opts := _options(at, restrict)
	if opts.is_empty():
		return -_dir
	var best := opts[0]
	var best_d := Vector2(at + best).distance_squared_to(Vector2(target))
	for i in range(1, opts.size()):
		var d := Vector2(at + opts[i]).distance_squared_to(Vector2(target))
		if d < best_d:
			best_d = d
			best = opts[i]
	return best


## Where this ghost is heading right now.
func target_tile() -> Vector2i:
	if is_eyes():
		return HOUSE_EXIT
	if game == null:
		return tile()
	if game.is_scatter() and not (personality == Personality.BLINKY and game.elroy() > 0):
		return SCATTER[personality]
	return chase_target()


## The chase target (see the header), off Mac-Pan's tile and facing.
func chase_target() -> Vector2i:
	var mac: MazeActor = game.macpan()
	var pac := mac.tile()
	var face := mac.direction()
	match personality:
		Personality.PINKY:
			var t := pac + face * 4
			if face == Vector2i.UP:
				t += Vector2i(-4, 0)
			return t
		Personality.INKY:
			var pivot := pac + face * 2
			if face == Vector2i.UP:
				pivot += Vector2i(-2, 0)
			var b: MazeActor = game.blinky()
			var bt := b.tile() if b != null else pac
			return pivot * 2 - bt
		Personality.CLYDE:
			if Vector2(tile()).distance_squared_to(Vector2(pac)) >= 64.0:
				return pac
			return SCATTER[Personality.CLYDE]
	return pac


# ---------------------------------------------------------------- the look

func _after_move(delta: float, _travelled: float) -> void:
	_t += delta * bob_rate * TAU
	if _model != null:
		_model.position.y = model_lift + sin(_t) * bob_height
	_update_look()


func _update_look() -> void:
	var tint := color
	var floor_v := 0.0
	if is_eyes():
		tint = eaten_color
		floor_v = eaten_dissolve
	elif frightened:
		tint = frightened_color
		if game != null and game.fright_flash_on():
			tint = flash_color
	set_tint(tint)
	if floor_v != dissolve_floor:
		dissolve_floor = floor_v
		refresh_look()
