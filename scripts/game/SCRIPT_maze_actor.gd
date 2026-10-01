class_name MazeActor
extends Node3D

# ANYTHING THAT RUNS THE MAZE: Mac-Pan and the ghosts. Moves on HedgeMaze's tile
# grid the arcade way — always heading for the centre of the next tile, deciding
# what to do only on arriving at one — and wraps through the side tunnel with a
# teleport: it beams out at one end and in at the other, with TeleportFx at both.
#
# GRID: tile (x, y) is column x, row y of the layout; row 0 is the far (-Z) edge,
# so "up" on the board is Vector2i.UP (row - 1), toward -Z, away from the camera.
# Positions are in tile units with tile centres on integers.
#
# SUBCLASSES decide the turns, in `_choose_dir(at)`: called on arriving at a tile
# centre (and while stopped), returns the direction to take from there, or ZERO to
# stop. Whatever it returns is only taken if `can_enter` allows it; otherwise the
# actor carries straight on, or stops if that is blocked too.
#
# THE MODEL is the actor's GLB, scaled to `model_scale`, lifted `model_lift` so it
# stands on the dirt, and turned so its front (+Z turned by `model_front_yaw`)
# faces the way it is going. Its materials are swapped for MAT_actor (the arena's
# self-lit prop shader — the scene has no light) carrying the model's own colour
# texture, so it sits in the same light as the hedges.

## Emitted when the actor arrives at a tile centre.
signal reached_tile(tile: Vector2i)

@export var maze_path: NodePath = ^"../HedgeMaze"
## Tiles per second.
@export var speed := 7.0
@export var start_tile := Vector2i(13, 23)
@export var start_dir := Vector2i.LEFT

@export_group("Model")
@export var model_scene: PackedScene
## Child nodes of the model to keep, comma-separated; empty keeps all.
## (MODEL_ghost.glb carries a copy of Mac-Pan as well as the ghost.) A String and
## not a PackedStringArray because the export's scene conversion dropped the
## array, and the exported ghosts came out wearing Mac-Pan.
@export var keep_only := ""
@export var model_scale := 0.1
@export var model_lift := 0.7
## Which way the model's face points at rest, as a yaw from +Z (radians).
@export var model_front_yaw := 0.0
## How fast the model turns to a new heading, in radians per second.
@export var turn_rate := 18.0
@export var base_material: ShaderMaterial = preload("res://materials/MAT_actor.tres")

@export_group("Teleport")
## Seconds to beam out, and again to beam in.
@export var beam_time := 0.22

var maze: HedgeMaze
var _pos := Vector2.ZERO
var _dir := Vector2i.ZERO
var _target := Vector2i.ZERO
var _moving := false
var _yaw := 0.0
var _model: Node3D
var _materials: Array[ShaderMaterial] = []
var _beam := 0.0          # 0 solid .. 1 gone
var _teleport_phase := 0  # 0 none, 1 beaming out, 2 beaming in
var _teleport_to := Vector2i.ZERO


func _ready() -> void:
	maze = get_node_or_null(maze_path) as HedgeMaze
	_model = _build_model()
	reset_to(start_tile, start_dir)


## Put the actor on a tile centre, heading `dir`.
func reset_to(tile: Vector2i, dir: Vector2i) -> void:
	_pos = Vector2(tile)
	_dir = dir
	_target = tile
	_moving = false
	_yaw = _yaw_for(dir)
	_teleport_phase = 0
	_set_beam(0.0)
	_place()


## Back to `start_tile` / `start_dir`, visible and solid.
func respawn() -> void:
	reset_to(start_tile, start_dir)
	set_model_visible(true)


## Stop (or restart) moving and animating, wherever the actor is.
func set_frozen(frozen: bool) -> void:
	set_physics_process(not frozen)


func set_model_visible(v: bool) -> void:
	if _model != null:
		_model.visible = v


## Where the actor is, in tile units (tile centres on integers).
func grid_pos() -> Vector2:
	return _pos


func tile() -> Vector2i:
	return Vector2i(roundi(_pos.x), roundi(_pos.y))


func direction() -> Vector2i:
	return _dir


func is_moving() -> bool:
	return _moving


func is_teleporting() -> bool:
	return _teleport_phase != 0


## Can this actor step from `from` into `to`? Hedge never; the ghost-house door
## ('-') only for actors that override this.
func can_enter(from: Vector2i, to: Vector2i) -> bool:
	if maze == null or maze.is_wall(to):
		return false
	return maze.tile_char(to) != "-"


## Turn round on the spot, mid-tile. Classic: both Mac-Pan and the ghosts may.
func reverse() -> void:
	if _dir == Vector2i.ZERO:
		return
	_dir = -_dir
	_target = _target + _dir if _moving else _target
	if not _moving and can_enter(_target, _target + _dir):
		_target += _dir
		_moving = true


func _choose_dir(_at: Vector2i) -> Vector2i:
	return _dir


func _physics_process(delta: float) -> void:
	if maze == null:
		return
	if _teleport_phase != 0:
		_teleport_step(delta)
		_place()
		return
	_before_move(delta)
	var step := speed * delta
	var travelled := 0.0
	while step > 1e-5:
		if not _moving:
			var nd := _choose_dir(_target)
			if nd != Vector2i.ZERO and can_enter(_target, _target + nd):
				_dir = nd
				_target += nd
				_moving = true
			else:
				break
		var tv := Vector2(_target)
		var d := _pos.distance_to(tv)
		if d > step:
			_pos += (tv - _pos) / d * step
			travelled += step
			step = 0.0
		else:
			_pos = tv
			step -= d
			travelled += d
			reached_tile.emit(_target)
			if _tunnel_exit(_target):
				break
			var nd := _choose_dir(_target)
			if nd != Vector2i.ZERO and can_enter(_target, _target + nd):
				_dir = nd
			if can_enter(_target, _target + _dir):
				_target += _dir
			else:
				_moving = false
				break
	_after_move(delta, travelled)
	_place()


func _before_move(_delta: float) -> void:
	pass


func _after_move(_delta: float, _travelled: float) -> void:
	pass


# THE SIDE TUNNEL. An actor that walks off the board's left or right edge (the
# tunnel row is the only open way off it) beams out one tile past the edge and
# beams in one tile past the other, still heading the same way.
func _tunnel_exit(at: Vector2i) -> bool:
	var w := maze.grid_size().x
	if at.x >= 0 and at.x < w:
		return false
	_teleport_to = Vector2i(w if at.x < 0 else -1, at.y)
	_teleport_phase = 1
	_moving = false
	var from_world := maze.to_global(maze.tile_to_local(at))
	var to_world := maze.to_global(maze.tile_to_local(_teleport_to))
	TeleportFx.spawn(get_parent(), from_world)
	TeleportFx.spawn(get_parent(), to_world, beam_time)
	return true


func _teleport_step(delta: float) -> void:
	var rate := delta / maxf(beam_time, 0.001)
	if _teleport_phase == 1:
		_set_beam(minf(_beam + rate, 1.0))
		if _beam >= 1.0:
			_pos = Vector2(_teleport_to)
			_target = _teleport_to
			_teleport_phase = 2
	else:
		_set_beam(maxf(_beam - rate, 0.0))
		if _beam <= 0.0:
			_teleport_phase = 0
			if can_enter(_target, _target + _dir):
				_target += _dir
				_moving = true


func _set_beam(v: float) -> void:
	_beam = v
	for m in _materials:
		m.set_shader_parameter("dissolve", v)
		m.set_shader_parameter("energy", sin(v * PI) * 0.8)
	if _model != null:
		# A squeeze up the beam's axis as it goes: narrower, a touch taller.
		var s := 1.0 - 0.45 * v
		_model.scale = Vector3(s, 1.0 + 0.6 * v, s) * model_scale


func _yaw_for(dir: Vector2i) -> float:
	if dir == Vector2i.ZERO:
		return _yaw
	return atan2(float(dir.x), float(dir.y)) - model_front_yaw


func _place() -> void:
	if maze == null:
		return
	var local := maze.tile_to_local(Vector2i.ZERO) + Vector3(_pos.x, 0.0, _pos.y) * maze.tile_size()
	global_position = maze.to_global(local)
	var want := _yaw_for(_dir)
	_yaw = rotate_toward(_yaw, want, turn_rate * get_physics_process_delta_time())
	rotation.y = _yaw


func _build_model() -> Node3D:
	if model_scene == null:
		return null
	var m := model_scene.instantiate() as Node3D
	m.name = "Model"
	var keep := PackedStringArray()
	for n in keep_only.split(",", false):
		keep.append(n.strip_edges())
	if not keep.is_empty():
		for c in m.get_children():
			if not keep.has(String(c.name)):
				m.remove_child(c)
				c.queue_free()
	m.scale = Vector3.ONE * model_scale
	m.position.y = model_lift
	add_child(m)
	var stack: Array[Node] = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as BaseMaterial3D
			var mat := base_material.duplicate() as ShaderMaterial
			if src != null and src.albedo_texture != null:
				mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			mi.set_surface_override_material(s, mat)
			_materials.append(mat)
	return m


## Set the colour every surface of the model is multiplied by.
func set_tint(c: Color) -> void:
	for m in _materials:
		m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
