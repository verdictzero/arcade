@tool
class_name HedgeMaze
extends Node3D

# THE PAC-MAN BOARD, GROWN IN HEDGE. Reads a tile layout (data/MAZE_*.txt) and
# stands a hedge wherever it says wall, out of one 0.8 m hedge block
# (models/MODEL_hedge_chunk.glb) repeated as a single MultiMesh.
#
# THE LAYOUT is the arcade's own tile map, one character per tile, row 0 at the
# far (-Z) edge and column 0 at the left (-X) edge, as seen from the game camera:
#
#   #  hedge            .  pellet           o  power pellet
#   -  ghost-house door (a gap in the hedge; the ghosts' rule, not ours)
#   space  open floor, or OUT OF BOUNDS if no corridor reaches it
#
# Out-of-bounds tiles — the solid blocks either side of the ghost house, which the
# arcade draws as hollow outlines — are FILLED with hedge, so the board reads as
# masses of hedge with corridors cut through them rather than as walls standing in
# empty ground. They are found by flood fill from `start_tile` across every
# non-wall tile; whatever that never reaches is filled. The tunnel row is reached,
# so it stays open and runs out through the board's edge.
#
# A TILE IS `blocks_per_tile` x `blocks_per_tile` hedge blocks. The block is
# 0.8 m square and 1.6 m tall, so at the default 2 a tile is 1.6 m and the classic
# 28 x 31 board is 44.8 x 49.6 m. Blocks are never scaled: the texture is authored
# for the block, and stretching it would show.
#
# Each block takes a quarter-turn yaw from a hash of its position, so a long hedge
# does not repeat the same face block after block. The kerb along the texture's
# foot stays at the foot whichever way it turns.
#
# Walls get box colliders, one per horizontal run of wall tiles, on `collision_layer`.
#
# The board is centred on this node. Rebuilds in the editor when an export changes.

@export_file("*.txt") var layout_path := "res://data/MAZE_classic.txt":
	set(v):
		layout_path = v
		_queue_build()
@export var block_mesh_scene: PackedScene = preload("res://models/MODEL_hedge_chunk.glb"):
	set(v):
		block_mesh_scene = v
		_queue_build()
@export var material: Material = preload("res://materials/MAT_hedge.tres"):
	set(v):
		material = v
		_queue_build()
## Hedge blocks along each side of one tile.
@export_range(1, 4) var blocks_per_tile := 2:
	set(v):
		blocks_per_tile = v
		_queue_build()
## The block's footprint in metres. MODEL_hedge_chunk.glb is 0.8.
@export var block_size := 0.8:
	set(v):
		block_size = v
		_queue_build()
## Where Pac-Man starts, as (column, row). Seeds the out-of-bounds flood fill.
@export var start_tile := Vector2i(13, 23):
	set(v):
		start_tile = v
		_queue_build()
@export var variation_seed := 1:
	set(v):
		variation_seed = v
		_queue_build()
@export_flags_3d_physics var collision_layer := 1

var _rows: PackedStringArray = []
var _wall: Array = []  # [row][col] -> bool, after the fill
var _build_queued := false


func _ready() -> void:
	build()


## Tile size in metres.
func tile_size() -> float:
	return block_size * blocks_per_tile


## Board size in tiles (columns, rows).
func grid_size() -> Vector2i:
	if _rows.is_empty():
		return Vector2i.ZERO
	return Vector2i(_rows[0].length(), _rows.size())


## Board size in metres (X, Z).
func board_size() -> Vector2:
	return Vector2(grid_size()) * tile_size()


## Centre of a tile, in this node's local space, on the floor.
func tile_to_local(tile: Vector2i) -> Vector3:
	var origin := -board_size() * 0.5
	var t := tile_size()
	return Vector3(origin.x + (tile.x + 0.5) * t, 0.0, origin.y + (tile.y + 0.5) * t)


## The tile under a point in this node's local space. May be off the board.
func local_to_tile(p: Vector3) -> Vector2i:
	var origin := -board_size() * 0.5
	var t := tile_size()
	return Vector2i(floori((p.x - origin.x) / t), floori((p.z - origin.y) / t))


## Is this tile hedge? Off the board is open (the tunnel runs out through it).
func is_wall(tile: Vector2i) -> bool:
	if tile.y < 0 or tile.y >= _wall.size():
		return false
	var row: Array = _wall[tile.y]
	if tile.x < 0 or tile.x >= row.size():
		return false
	return row[tile.x]


## The raw layout character at a tile (' ' off the board).
func tile_char(tile: Vector2i) -> String:
	if tile.y < 0 or tile.y >= _rows.size() or tile.x < 0 or tile.x >= _rows[tile.y].length():
		return " "
	return _rows[tile.y][tile.x]


func _queue_build() -> void:
	if not is_inside_tree() or _build_queued:
		return
	_build_queued = true
	build.call_deferred()


func build() -> void:
	_build_queued = false
	for c in get_children():
		if c.has_meta("hedge_maze_built"):
			remove_child(c)
			c.queue_free()
	if not _load_layout():
		return
	_fill_out_of_bounds()
	var mesh := _block_mesh()
	if mesh == null:
		push_warning("HedgeMaze: no mesh in %s" % block_mesh_scene)
		return
	_build_hedges(mesh)
	_build_colliders(mesh)


func _load_layout() -> bool:
	var f := FileAccess.open(layout_path, FileAccess.READ)
	if f == null:
		push_warning("HedgeMaze: cannot read %s" % layout_path)
		return false
	var lines := f.get_as_text().split("\n")
	_rows = PackedStringArray()
	var width := 0
	for l in lines:
		var s := l.trim_suffix("\r")
		if s.strip_edges() == "" and _rows.is_empty():
			continue
		_rows.append(s)
		width = maxi(width, s.length())
	while not _rows.is_empty() and _rows[_rows.size() - 1].strip_edges() == "":
		_rows.remove_at(_rows.size() - 1)
	for i in _rows.size():
		_rows[i] = _rows[i].rpad(width)
	return not _rows.is_empty()


# Wall where the layout says '#', and wherever no corridor reaches.
func _fill_out_of_bounds() -> void:
	var size := grid_size()
	var reached := {}
	var stack: Array[Vector2i] = [start_tile]
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		if t.x < 0 or t.y < 0 or t.x >= size.x or t.y >= size.y:
			continue
		if reached.has(t) or _rows[t.y][t.x] == "#":
			continue
		reached[t] = true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(t + d)
	if reached.is_empty():
		push_warning("HedgeMaze: start_tile %s is a wall; nothing filled" % start_tile)
	_wall = []
	for y in size.y:
		var row := []
		for x in size.x:
			var c := _rows[y][x]
			row.append(c == "#" or (not reached.is_empty() and not reached.has(Vector2i(x, y))))
		_wall.append(row)


func _block_mesh() -> Mesh:
	if block_mesh_scene == null:
		return null
	var inst := block_mesh_scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [inst]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found = (n as MeshInstance3D).mesh
		stack.append_array(n.get_children())
	inst.free()
	return found


func _build_hedges(mesh: Mesh) -> void:
	var size := grid_size()
	var xforms: Array[Transform3D] = []
	var t := tile_size()
	for y in size.y:
		for x in size.x:
			if not _wall[y][x]:
				continue
			var corner := tile_to_local(Vector2i(x, y)) - Vector3(t * 0.5, 0.0, t * 0.5)
			for by in blocks_per_tile:
				for bx in blocks_per_tile:
					var p := corner + Vector3((bx + 0.5) * block_size, 0.0,
							(by + 0.5) * block_size)
					var turn := _hash(x * blocks_per_tile + bx, y * blocks_per_tile + by) % 4
					xforms.append(Transform3D(Basis(Vector3.UP, turn * PI * 0.5), p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Hedges"
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.set_meta("hedge_maze_built", true)
	add_child(mmi)


# One box per horizontal run of wall tiles: a few hundred shapes for the classic
# board rather than one per tile.
func _build_colliders(mesh: Mesh) -> void:
	var size := grid_size()
	var t := tile_size()
	var body := StaticBody3D.new()
	body.name = "HedgeCollision"
	body.collision_layer = collision_layer
	body.collision_mask = 0
	body.set_meta("hedge_maze_built", true)
	var height := maxf(mesh.get_aabb().size.y, 0.1)
	for y in size.y:
		var x := 0
		while x < size.x:
			if not _wall[y][x]:
				x += 1
				continue
			var x0 := x
			while x < size.x and _wall[y][x]:
				x += 1
			var run := x - x0
			var shape := BoxShape3D.new()
			shape.size = Vector3(run * t, height, t)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			var a := tile_to_local(Vector2i(x0, y))
			var b := tile_to_local(Vector2i(x - 1, y))
			cs.position = (a + b) * 0.5 + Vector3(0.0, height * 0.5, 0.0)
			body.add_child(cs)
	add_child(body)


func _hash(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (variation_seed * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff
