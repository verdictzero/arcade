class_name Pellets
extends Node3D

# THE DOTS: a pellet on every '.' of the maze layout and a power pellet on every
# 'o' (HedgeMaze.tile_char), 240 and 4 on the classic board. The small ones are
# one MultiMesh, so the whole board of them is one draw call, and eating one
# zeroes its instance's scale; the four power pellets are their own meshes so
# each can pulse.
#
# Unshaded and self-coloured: they are lights in the dirt, not props in the sun.

@export var maze_path: NodePath = ^"../HedgeMaze"
@export var pellet_points := 10
@export var power_points := 50
@export var pellet_radius := 0.13
@export var power_radius := 0.34
@export var height := 0.55
@export var color := Color(1.0, 0.86, 0.62)

var _maze: HedgeMaze
var _small: MultiMesh
var _smalls := {}   # Vector2i -> instance index
var _powers := {}   # Vector2i -> MeshInstance3D
var _left := 0
var _t := 0.0


func _ready() -> void:
	_maze = get_node(maze_path) as HedgeMaze
	reset()


## Put every pellet back.
func reset() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_smalls.clear()
	_powers.clear()
	var small_tiles: Array[Vector2i] = []
	var g := _maze.grid_size()
	for y in g.y:
		for x in g.x:
			var t := Vector2i(x, y)
			var c := _maze.tile_char(t)
			if c == ".":
				small_tiles.append(t)
			elif c == "o":
				var mi := MeshInstance3D.new()
				mi.mesh = _sphere(power_radius)
				add_child(mi)
				mi.global_position = _spot(t)
				_powers[t] = mi
	_small = MultiMesh.new()
	_small.transform_format = MultiMesh.TRANSFORM_3D
	_small.mesh = _sphere(pellet_radius)
	_small.instance_count = small_tiles.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _small
	add_child(mmi)
	for i in small_tiles.size():
		_small.set_instance_transform(i, Transform3D(Basis(), to_local(_spot(small_tiles[i]))))
		_smalls[small_tiles[i]] = i
	_left = _smalls.size() + _powers.size()


func remaining() -> int:
	return _left


## Eat whatever is on `tile`; returns the points it was worth (0 if nothing).
func eat(tile: Vector2i) -> int:
	if _smalls.has(tile):
		var i: int = _smalls[tile]
		_smalls.erase(tile)
		_small.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO),
				_small.get_instance_transform(i).origin))
		_left -= 1
		return pellet_points
	if _powers.has(tile):
		(_powers[tile] as Node3D).queue_free()
		_powers.erase(tile)
		_left -= 1
		return power_points
	return 0


func _process(delta: float) -> void:
	_t += delta
	var k := 0.8 + 0.25 * sin(_t * TAU * 1.6)
	for p in _powers.values():
		(p as Node3D).scale = Vector3.ONE * k


func _spot(t: Vector2i) -> Vector3:
	return _maze.to_global(_maze.tile_to_local(t)) + Vector3(0, height, 0)


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	s.material = mat
	return s
