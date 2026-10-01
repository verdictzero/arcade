class_name ArcadeGame
extends Node

# THE RULES: Mac-Pan eats the pellets for points, a ghost that catches him blows
# him up (ExplosionFx) and costs a life, clearing the board raises the level, and
# losing the last life starts the game over. Everything it shows goes to the HUD.
#
#   LOADING everyone frozen until the world's loading screen has gone
#   PLAY    -> a ghost within `catch_distance` tiles of Mac-Pan -> DYING
#   DYING   everyone freezes, Mac-Pan explodes, the ghosts vanish a beat later;
#           then a life comes off and everyone respawns (or, out of lives, the
#           score, level, lives and pellets all reset)
#   CLEARED the last pellet is eaten: a pause, the level goes up, the pellets
#           come back and everyone respawns
#
# Power pellets score but do not yet turn the ghosts blue; that comes with the
# ghosts' real AI.

@export var maze_path: NodePath = ^"../HedgeMaze"
@export var macpan_path: NodePath = ^"../MacPan"
@export var ghost_paths: Array[NodePath] = [^"../Blinky", ^"../Pinky", ^"../Inky", ^"../Clyde"]
@export var pellets_path: NodePath = ^"../Pellets"
@export var hud_path: NodePath = ^"../Hud"
## Play is held, everyone frozen, until this goes away (the world's loading screen).
@export var loading_path: NodePath = ^"../LoadingScreen"
@export var start_lives := 3
@export var catch_distance := 0.6
@export var death_time := 2.6
@export var clear_time := 1.6

enum State { LOADING, PLAY, DYING, CLEARED }

var state := State.LOADING
var score := 0
var level := 1
var lives := 3

var _mac: MacPan
var _ghosts: Array[Ghost] = []
var _pellets: Pellets
var _hud: ArcadeHud
var _loading: Node


func _ready() -> void:
	_mac = get_node(macpan_path) as MacPan
	for p in ghost_paths:
		var g := get_node_or_null(p) as Ghost
		if g != null:
			_ghosts.append(g)
	_pellets = get_node(pellets_path) as Pellets
	_hud = get_node_or_null(hud_path) as ArcadeHud
	_loading = get_node_or_null(loading_path)
	_mac.reached_tile.connect(_on_mac_tile)
	lives = start_lives
	_refresh()


func _physics_process(_delta: float) -> void:
	if state == State.LOADING:
		# Re-asserted every tick rather than once in `_ready`: the actors are later
		# siblings, and a node switches its own physics processing on when it readies.
		var loading: bool = _loading != null and bool(_loading.get("visible"))
		_freeze_all(loading)
		if not loading:
			state = State.PLAY
		return
	if state != State.PLAY or _mac.is_teleporting():
		return
	for g in _ghosts:
		if g.is_teleporting():
			continue
		if g.grid_pos().distance_to(_mac.grid_pos()) < catch_distance:
			_die()
			return


func _on_mac_tile(tile: Vector2i) -> void:
	if state != State.PLAY:
		return
	var pts := _pellets.eat(tile)
	if pts > 0:
		score += pts
		_refresh()
		if _pellets.remaining() == 0:
			_clear()


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
		_pellets.reset()
	_respawn_all()
	_refresh()
	state = State.PLAY


func _clear() -> void:
	state = State.CLEARED
	_freeze_all(true)
	await get_tree().create_timer(clear_time).timeout
	level += 1
	_pellets.reset()
	_respawn_all()
	_refresh()
	state = State.PLAY


func _freeze_all(frozen: bool) -> void:
	_mac.set_frozen(frozen)
	for g in _ghosts:
		g.set_frozen(frozen)


func _respawn_all() -> void:
	_mac.respawn()
	for g in _ghosts:
		g.respawn()
	_freeze_all(false)


func _refresh() -> void:
	if _hud == null:
		return
	_hud.set_score(score)
	_hud.set_level(level)
	_hud.set_lives(lives)
