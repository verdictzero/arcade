class_name ArcadeGame
extends Node

# THE RULES, as close to the arcade's as the board allows (the numbers are from
# Jamey Pittman's "The Pac-Man Dossier"; Ghost has the targeting).
#
#   Pellets 10, power pellets 50. Clear the board and the level goes up.
#   An extra life at 10,000 points, once.
#
#   SCATTER / CHASE. The ghosts alternate on a per-level timetable (SCHEDULES) —
#   level 1 is scatter 7 s, chase 20, scatter 7, chase 20, scatter 5, chase 20,
#   scatter 5, then chase for good — and every ghost turns round at each switch.
#   The timetable stands still while the ghosts are frightened.
#
#   FRIGHT. A power pellet turns every ghost not already eaten blue and turns it
#   round, for FRIGHT[level] seconds, flashing white for the last few. Blue ghosts
#   are slower and wander; Mac-Pan eats them for 200, 400, 800, 1600 (doubling per
#   ghost, per pellet), the game holds a beat with the score where the ghost was,
#   and the ghost goes home as a wisp to revive. From level 17 the pellet only
#   turns them round.
#
#   THE HOUSE. Pinky leaves at once; Inky and Clyde wait on dot counters (level 1:
#   30 and 60, level 2: 0 and 50, then 0). After a death the house goes on one
#   shared counter instead (Pinky 7, Inky 17, Clyde 32). And if Mac-Pan goes 4 s
#   (3 s from level 5) without eating, the next ghost is let out anyway.
#
#   SPEEDS (SPEEDS, as fractions of the arcade's 100%): Mac-Pan normal and while
#   ghosts are blue; ghosts normal, in the tunnel and blue. Blinky turns "Cruise
#   Elroy" when few dots are left (ELROY): faster, and he chases through scatter.
#   After a death that waits until Clyde is out of the house.
#
#   LOADING everyone frozen until the world's loading screen has gone
#   PLAY    the above
#   EATING  the beat after a ghost is eaten: all frozen, its score where it was
#   DYING   a ghost caught Mac-Pan: he explodes (ExplosionFx), a life comes off
#   CLEARED the last pellet is eaten: a pause, the level goes up

@export var maze_path: NodePath = ^"../HedgeMaze"
@export var macpan_path: NodePath = ^"../MacPan"
@export var ghost_paths: Array[NodePath] = [^"../Blinky", ^"../Pinky", ^"../Inky", ^"../Clyde"]
@export var pellets_path: NodePath = ^"../Pellets"
@export var hud_path: NodePath = ^"../Hud"
## Play is held, everyone frozen, until this goes away (the world's loading screen).
@export var loading_path: NodePath = ^"../LoadingScreen"
@export var start_lives := 3
@export var extra_life_at := 10000
@export var catch_distance := 0.6
@export var death_time := 2.6
@export var clear_time := 1.6
@export var eat_pause := 0.8
## The arcade's 100% speed: 75.75 px/s over 8 px tiles.
@export var base_speed := 9.47

enum State { LOADING, PLAY, EATING, DYING, CLEARED }

const INF := 1.0e9
## Scatter/chase phase lengths in seconds, scatter first; the last runs forever.
const SCHEDULES := [
	[7.0, 20.0, 7.0, 20.0, 5.0, 20.0, 5.0, INF],           # level 1
	[7.0, 20.0, 7.0, 20.0, 5.0, 1033.0, 1.0 / 60.0, INF],  # levels 2-4
	[5.0, 20.0, 5.0, 20.0, 5.0, 1037.0, 1.0 / 60.0, INF],  # level 5+
]
## [seconds blue, flashes] for levels 1..19; level 19 on is 0.
const FRIGHT := [
	[6, 5], [5, 5], [4, 5], [3, 5], [2, 5], [5, 5], [2, 5], [2, 5], [1, 3], [5, 5],
	[2, 5], [1, 3], [1, 3], [3, 5], [1, 3], [1, 3], [0, 0], [1, 3], [0, 0],
]
## One flash: white then blue, 14 frames each at 60 Hz.
const FLASH_PERIOD := 28.0 / 60.0
## [mac, mac blue, ghost, ghost tunnel, ghost blue] by level band.
const SPEEDS := [
	[0.80, 0.90, 0.75, 0.40, 0.50],  # level 1
	[0.90, 0.95, 0.85, 0.45, 0.55],  # levels 2-4
	[1.00, 1.00, 0.95, 0.50, 0.60],  # levels 5-20
	[0.90, 0.90, 0.95, 0.50, 0.60],  # level 21+
]
const EYES_SPEED := 1.6
const HOUSE_SPEED := 0.45
## [dots left for Elroy 1, speed, dots left for Elroy 2, speed] by level.
const ELROY := [
	[20, 0.80, 10, 0.85], [30, 0.90, 15, 0.95], [40, 0.90, 20, 0.95], [40, 0.90, 20, 0.95],
	[40, 1.00, 20, 1.05], [50, 1.00, 25, 1.05], [50, 1.00, 25, 1.05], [50, 1.00, 25, 1.05],
	[60, 1.00, 30, 1.05], [60, 1.00, 30, 1.05], [60, 1.00, 30, 1.05], [80, 1.00, 40, 1.05],
	[80, 1.00, 40, 1.05], [80, 1.00, 40, 1.05], [100, 1.00, 50, 1.05], [100, 1.00, 50, 1.05],
	[100, 1.00, 50, 1.05], [100, 1.00, 50, 1.05], [120, 1.00, 60, 1.05],
]
const GLOBAL_RELEASE := {Ghost.Personality.PINKY: 7, Ghost.Personality.INKY: 17, Ghost.Personality.CLYDE: 32}

var state := State.LOADING
var score := 0
var level := 1
var lives := 3

var _mac: MacPan
var _ghosts: Array[Ghost] = []
var _blinky: Ghost
var _pellets: Pellets
var _hud: ArcadeHud
var _loading: Node

var _mode_index := 0
var _mode_time := 0.0
var _fright_left := 0.0
var _fright_clock := 0.0
var _fright_flash_at := INF
var _chain := 0
var _personal := {}           # Personality -> dots counted in the house
var _global_mode := false
var _global_count := 0
var _idle := 0.0              # seconds since the last dot
var _elroy_suspended := false
var _extra_given := false


func _ready() -> void:
	_mac = get_node(macpan_path) as MacPan
	for p in ghost_paths:
		var g := get_node_or_null(p) as Ghost
		if g != null:
			_ghosts.append(g)
			g.game = self
			if g.personality == Ghost.Personality.BLINKY:
				_blinky = g
	_pellets = get_node(pellets_path) as Pellets
	_hud = get_node_or_null(hud_path) as ArcadeHud
	_loading = get_node_or_null(loading_path)
	_mac.reached_tile.connect(_on_mac_tile)
	lives = start_lives
	_reset_house_counters()
	_refresh()


# ---------------------------------------------------------------- queries

func macpan() -> MazeActor:
	return _mac


func blinky() -> MazeActor:
	return _blinky


func is_scatter() -> bool:
	return _mode_index % 2 == 0


## 0, or Blinky's Cruise Elroy stage (1 or 2).
func elroy() -> int:
	if _elroy_suspended:
		return 0
	var e: Array = ELROY[mini(level, ELROY.size()) - 1]
	var left := _pellets.remaining()
	if left <= int(e[2]):
		return 2
	if left <= int(e[0]):
		return 1
	return 0


## Are frightened ghosts showing white right now (the end-of-fright flash)?
func fright_flash_on() -> bool:
	if _fright_left <= 0.0 or _fright_clock < _fright_flash_at:
		return false
	return fmod(_fright_clock - _fright_flash_at, FLASH_PERIOD) < FLASH_PERIOD * 0.5


func ghost_speed(g: Ghost) -> float:
	var s: Array = _speeds()
	if g.is_eyes():
		return base_speed * EYES_SPEED
	if g.state == Ghost.State.HOUSE or g.state == Ghost.State.LEAVING:
		return base_speed * HOUSE_SPEED
	if _in_tunnel(g.tile()):
		return base_speed * float(s[3])
	if g.frightened:
		return base_speed * float(s[4])
	if g == _blinky:
		var e := elroy()
		if e > 0:
			var row: Array = ELROY[mini(level, ELROY.size()) - 1]
			return base_speed * float(row[1] if e == 1 else row[3])
	return base_speed * float(s[2])


func _speeds() -> Array:
	if level <= 1:
		return SPEEDS[0]
	if level <= 4:
		return SPEEDS[1]
	if level <= 20:
		return SPEEDS[2]
	return SPEEDS[3]


# The side tunnel: the tunnel row, out past the side blocks (and off the board).
func _in_tunnel(t: Vector2i) -> bool:
	return t.y == 14 and (t.x <= 5 or t.x >= 22)


# ---------------------------------------------------------------- the loop

func _physics_process(delta: float) -> void:
	match state:
		State.LOADING:
			# Re-asserted every tick rather than once in `_ready`: the actors are
			# later siblings, and a node switches its own processing on when it readies.
			var loading: bool = _loading != null and bool(_loading.get("visible"))
			_freeze_all(loading)
			if not loading:
				_begin_round()
				state = State.PLAY
			return
		State.PLAY:
			pass
		_:
			return

	var s: Array = _speeds()
	_mac.speed = base_speed * float(s[1] if _fright_left > 0.0 else s[0])

	if _fright_left > 0.0:
		_fright_left -= delta
		_fright_clock += delta
		if _fright_left <= 0.0:
			_end_fright()
	else:
		var sched: Array = _schedule()
		_mode_time += delta
		while _mode_index < sched.size() - 1 and _mode_time >= float(sched[_mode_index]):
			_mode_time -= float(sched[_mode_index])
			_mode_index += 1
			for g in _ghosts:
				g.request_reverse()

	_idle += delta
	if _idle >= (4.0 if level < 5 else 3.0):
		_idle = 0.0
		var g := _next_in_house()
		if g != null:
			g.release()
	_check_personal_release()
	if _elroy_suspended and not _clyde_in_house():
		_elroy_suspended = false

	_collide()


func _collide() -> void:
	if _mac.is_teleporting():
		return
	for g in _ghosts:
		if g.is_teleporting() or not g.is_solid():
			continue
		if g.grid_pos().distance_to(_mac.grid_pos()) >= catch_distance:
			continue
		if g.frightened:
			_eat_ghost(g)
		else:
			_die()
		return


func _on_mac_tile(tile: Vector2i) -> void:
	if state != State.PLAY:
		return
	var pts := _pellets.eat(tile)
	if pts <= 0:
		return
	_add_score(pts)
	_count_dot()
	if pts >= _pellets.power_points:
		_power_pellet()
	if _pellets.remaining() == 0:
		_clear()


func _add_score(pts: int) -> void:
	var before := score
	score += pts
	if not _extra_given and before < extra_life_at and score >= extra_life_at:
		_extra_given = true
		lives += 1
	_refresh()


# ---------------------------------------------------------------- fright

func _power_pellet() -> void:
	var f: Array = FRIGHT[mini(level, FRIGHT.size()) - 1]
	var secs := float(f[0])
	_chain = 0
	if secs <= 0.0:
		for g in _ghosts:
			g.request_reverse()
		return
	_fright_left = secs
	_fright_clock = 0.0
	_fright_flash_at = maxf(secs - float(f[1]) * FLASH_PERIOD, 0.0)
	for g in _ghosts:
		g.frighten()


func _end_fright() -> void:
	_fright_left = 0.0
	for g in _ghosts:
		g.unfrighten()


func _eat_ghost(g: Ghost) -> void:
	var pts := 200 * (1 << mini(_chain, 3))
	_chain += 1
	_add_score(pts)
	state = State.EATING
	_freeze_all(true)
	g.set_model_visible(false)
	_mac.set_model_visible(false)
	_score_popup(g.global_position, pts)
	await get_tree().create_timer(eat_pause).timeout
	g.eat()
	g.set_model_visible(true)
	_mac.set_model_visible(true)
	_freeze_all(false)
	state = State.PLAY


func _score_popup(at: Vector3, pts: int) -> void:
	var l := Label3D.new()
	l.text = str(pts)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font = Fonts.technical()
	l.font_size = 120
	l.pixel_size = 0.024
	l.outline_size = 24
	l.modulate = Color(0.45, 0.95, 1.0)
	l.outline_modulate = Color(0, 0, 0, 0.9)
	_mac.get_parent().add_child(l)
	l.global_position = at + Vector3(0, 1.4, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.2, eat_pause + 0.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(eat_pause)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------- the house

func _reset_house_counters() -> void:
	_personal = {
		Ghost.Personality.PINKY: 0, Ghost.Personality.INKY: 0, Ghost.Personality.CLYDE: 0,
	}
	_global_mode = false
	_global_count = 0


func _personal_limit(p: int) -> int:
	if level == 1:
		return {Ghost.Personality.PINKY: 0, Ghost.Personality.INKY: 30, Ghost.Personality.CLYDE: 60}.get(p, 0)
	if level == 2:
		return {Ghost.Personality.CLYDE: 50}.get(p, 0)
	return 0


# The ghost the house lets out next: Pinky, then Inky, then Clyde.
func _next_in_house() -> Ghost:
	var best: Ghost = null
	for g in _ghosts:
		if g.in_house() and (best == null or g.personality < best.personality):
			best = g
	return best


func _clyde_in_house() -> bool:
	for g in _ghosts:
		if g.personality == Ghost.Personality.CLYDE:
			return g.in_house()
	return false


func _count_dot() -> void:
	_idle = 0.0
	if _global_mode:
		_global_count += 1
		for g in _ghosts:
			if g.in_house() and GLOBAL_RELEASE.get(g.personality, -1) == _global_count:
				g.release()
				if g.personality == Ghost.Personality.CLYDE:
					_global_mode = false
		return
	var g := _next_in_house()
	if g != null:
		_personal[g.personality] = int(_personal.get(g.personality, 0)) + 1


func _check_personal_release() -> void:
	if _global_mode:
		return
	var g := _next_in_house()
	if g != null and int(_personal.get(g.personality, 0)) >= _personal_limit(g.personality):
		g.release()


# ---------------------------------------------------------------- rounds

func _schedule() -> Array:
	return SCHEDULES[0] if level <= 1 else (SCHEDULES[1] if level <= 4 else SCHEDULES[2])


# A fresh round on the current board: after the load, a death or a level-up.
func _begin_round() -> void:
	_mode_index = 0
	_mode_time = 0.0
	_fright_left = 0.0
	_chain = 0
	_idle = 0.0
	_mac.respawn()
	for g in _ghosts:
		g.start_round()
	_freeze_all(false)


func _die() -> void:
	state = State.DYING
	_freeze_all(true)
	_mac.set_model_visible(false)
	ExplosionFx.spawn(_mac.get_parent(), _mac.global_position)
	await get_tree().create_timer(0.5).timeout
	for g in _ghosts:
		g.set_model_visible(false)
	await get_tree().create_timer(death_time - 0.5).timeout
	lives -= 1
	if lives < 0:
		score = 0
		level = 1
		lives = start_lives
		_extra_given = false
		_pellets.reset()
		_reset_house_counters()
		_elroy_suspended = false
	else:
		_global_mode = true
		_global_count = 0
		_elroy_suspended = true
	_begin_round()
	_refresh()
	state = State.PLAY


func _clear() -> void:
	state = State.CLEARED
	_freeze_all(true)
	await get_tree().create_timer(clear_time).timeout
	level += 1
	_pellets.reset()
	_reset_house_counters()
	_elroy_suspended = false
	_begin_round()
	_refresh()
	state = State.PLAY


func _freeze_all(frozen: bool) -> void:
	_mac.set_frozen(frozen)
	for g in _ghosts:
		g.set_frozen(frozen)


func _refresh() -> void:
	if _hud == null:
		return
	_hud.set_score(score)
	_hud.set_level(level)
	_hud.set_lives(lives)
