class_name ArenaField
extends IslandField

# THE PAC-MAN PLAYFIELD'S GROUND: a flat rectangle for the hedge maze, a wall of
# forest round three sides of it and on out past them, and the fourth side — the
# one the camera looks in from — a thick meadow: grass, and nothing taller, so no
# plant ever stands between the camera and the maze.
#
# It is the island engine with three things overridden, not a second engine. The
# mesher, the bake, the vegetation and the grass all still talk to an IslandField;
# this one answers differently in three places:
#
#   base_height  — the ground is pinned flat over the arena and the open side, and
#                  the island's own hills only rise again out in the forest.
#   forest_at    — zero on the arena and its margin and on the open side; a dense
#                  band hard against the margin on the other three (the treeline
#                  that frames the board); the island's own forest noise beyond.
#   sample       — carries three extra keys the scatters read, because forest
#                  density alone cannot keep a plant off the board: the scatters
#                  plant bushes and the odd tree on OPEN ground too
#                  (`tree_open_density`, `bush_open_density`).
#
#       "arena"      1 on the maze floor.       grass_scatter: no tufts.
#       "veg_clear"  1 on the arena, its margin
#                    and the open side.         veg_scatter: no trees, bushes, ferns.
#       "meadow"     1 on the open side.        grass_scatter: every cell, taller.
#
# AXES: the arena is centred on `arena_center` (x, z), long side on Z like the
# arcade board, and the camera sits on the +Z side looking toward -Z. That is the
# direction a Godot camera faces at identity, and where SCENE_arena puts it.
#
# Everything is a function of (x, z) and the exports, so two chunks sharing a
# vertex still agree bit for bit, which is what the mesher and the bake rely on.

## The arena's centre, in world XZ. Leave it on the hub's centre unless the hub
## moves too: the hub island is what puts land under it.
@export var arena_center := Vector2.ZERO
## The maze floor's full size in metres, X by Z. 112 x 124 is the arcade board's
## 28 x 31 tiles at 4 m a tile.
@export var arena_size := Vector2(112.0, 124.0)
## The height the floor is pinned to. Relative to the island's base altitude.
@export var arena_floor_y := 0.0

@export_group("Flat ground")
## How far past the arena's edge the ground stays dead flat before it is let go.
@export var flat_margin := 30.0
## Metres over which the flat ground hands back to the island's hills.
@export var flat_blend := 120.0

@export_group("Treeline")
## Bare ground between the arena's edge and the first tree, on the three wooded
## sides. Grass grows here; nothing taller does.
@export var tree_margin := 10.0
## Metres of solid forest past `tree_margin` — the treeline that frames the board.
## Past it the island's own forest noise (`forest_coverage`) takes over.
@export var tree_wall_depth := 45.0
## Metres over which the solid band fades out into the island's forest.
@export var tree_wall_fade := 60.0
## Metres over which the treeline gives way at the open side, so it does not end
## on a ruled line.
@export var open_side_blend := 25.0


## Distance outside the arena rectangle (0 anywhere on it), in metres.
func arena_distance(x: float, z: float) -> float:
	var half := arena_size * 0.5
	var dx := maxf(absf(x - arena_center.x) - half.x, 0.0)
	var dz := maxf(absf(z - arena_center.y) - half.y, 0.0)
	return sqrt(dx * dx + dz * dz)


## 1 on the maze floor, 0 off it, with a 1 m feather at the edge.
func arena_weight(x: float, z: float) -> float:
	return 1.0 - smoothstep(0.0, 1.0, arena_distance(x, z))


## 1 on the camera's side of the arena (+Z beyond its near edge), 0 behind it.
func open_side_weight(x: float, z: float) -> float:
	var edge := arena_center.y + arena_size.y * 0.5
	return smoothstep(edge - open_side_blend, edge, z)


## 1 on the arena and within `tree_margin` of it.
func clearing_weight(x: float, z: float) -> float:
	var d := arena_distance(x, z)
	return 1.0 - smoothstep(maxf(tree_margin - 2.0, 0.0), tree_margin, d)


func _flat_weight(x: float, z: float) -> float:
	var d := arena_distance(x, z)
	var w := 1.0 - smoothstep(flat_margin, flat_margin + flat_blend, d)
	# The open side stays flat all the way out: a hill rising between the camera
	# and the board would hide the bottom rows of the maze.
	return maxf(w, open_side_weight(x, z))


func base_height(x: float, z: float, mask: float, owner: Island,
		zone_flat := 0.0, zone_lift := 0.0) -> float:
	var h := super(x, z, mask, owner, zone_flat, zone_lift)
	if owner == null:
		return h
	var w := _flat_weight(x, z)
	if w <= 0.0:
		return h
	return lerpf(h, owner.base_y + arena_floor_y, w)


func forest_at(x: float, z: float, mask: float, slope: float,
		zone_flat := 0.0) -> float:
	var f := super(x, z, mask, slope, zone_flat)
	if not forest_enabled:
		return f
	var past := arena_distance(x, z) - tree_margin
	var wall := 1.0 - smoothstep(tree_wall_depth, tree_wall_depth + tree_wall_fade, past)
	wall *= smoothstep(0.0, maxf(forest_coast_margin, 0.001), mask)
	f = maxf(f, wall)
	return f * (1.0 - maxf(clearing_weight(x, z), open_side_weight(x, z)))


func sample(x: float, z: float) -> Dictionary:
	var s := super(x, z)
	if not s.get("on_land", false):
		return s
	var clear := clearing_weight(x, z)
	var open := open_side_weight(x, z)
	s["arena"] = arena_weight(x, z)
	s["veg_clear"] = maxf(clear, open)
	s["meadow"] = open * (1.0 - arena_weight(x, z))
	return s
