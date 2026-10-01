extends Node

# Floating origin: keeps the action near the world origin so float precision doesn't
# degrade as the fleet drives forward indefinitely. When the reference (the player)
# drifts past `threshold` from origin, the whole world is rebased by -reference so it
# snaps back to the origin.
#
# Systems that own world-space state (the swarms via their managers/movers, the
# player) join group "origin_shiftable" and implement apply_origin_shift(shift).
# Transient FX (bolts, explosions, debris, beams) are direct Node3D children of the
# scene and are shifted directly. A few distant/static nodes (sun, sky, light) are
# excluded by name so they don't get dragged around.
#
# HORIZONTAL_ONLY exists because a rebase is only free when nothing in the scene
# treats a world coordinate as an absolute. The space/fleet game satisfies that:
# it is open in all three axes and every consumer of position is relative, so it
# rebases the full vector and always has. The island world does not. That scene
# pins several things to ABSOLUTE world Y and has no way to be told they moved:
#
#   * the void-fog band in `SHADER_terrain_splat.gdshader` (`fog_top` / `fog_bottom`)
#     are shader uniforms in world space, and `SCRIPT_island_world.gd` places chunk
#     holders at `pivot - _origin_offset`
#   * the Environment's height fog (`fog_height`) — WorldEnvironment is in
#     `exclude_names`, so nothing would move it even in principle
#   * the two cloud-deck quads, which hang at fixed altitudes
#
# A full-vector rebase fired while cruising at y = +240 slides every island up
# 240 m in render space while all of that stays put, which un-fogs the top
# quarter of every cliff and drops the islands through the cloud sea. The world
# has no vertical extent worth rebasing anyway — it is bounded by the cloud
# ceiling above and `cliff_cutoff_y` below — so throwing the Y term away costs
# that scene nothing and removes the whole class of bug.
#
# Defaults to false: this script is shared, and changing what a rebase means for
# an existing scene is exactly the kind of silent behaviour change that would
# show up as an unexplained fleet-game regression months later. The island scene
# opts in.
@export var reference_path: NodePath
@export var threshold := 10000.0
## Rebase on XZ only, leaving world Y untouched (and ignoring altitude when
## deciding whether the threshold has been crossed). Set this in any scene that
## has world-Y-anchored visuals; see the note above.
@export var horizontal_only := false
@export var exclude_names: Array[String] = ["SpaceSun", "DirectionalLight3D", "WorldEnvironment"]

var _ref: Node3D = null


func _ready() -> void:
	_ref = get_node_or_null(reference_path) as Node3D


func _physics_process(_delta: float) -> void:
	if _ref == null or not is_instance_valid(_ref):
		return
	var p := _ref.global_position
	# The trigger has to match the shift. Measuring the full distance while only
	# correcting XZ would let a high-flying reference fire a rebase that barely
	# moves it, then fire again next frame, and again.
	var drift: float = Vector2(p.x, p.z).length() if horizontal_only else p.length()
	if drift < threshold:
		return
	var shift: Vector3 = Vector3(-p.x, 0.0, -p.z) if horizontal_only else -p
	# Owners of world-space state rebase themselves.
	for n in get_tree().get_nodes_in_group("origin_shiftable"):
		if n.has_method("apply_origin_shift"):
			n.apply_origin_shift(shift)
	# Transient FX (scene-root Node3Ds) shift directly.
	var scene := get_tree().current_scene
	if scene == null:
		return
	for child in scene.get_children():
		if child == self or child.is_in_group("origin_shiftable"):
			continue
		if child is Node3D and not exclude_names.has(String(child.name)):
			(child as Node3D).global_position += shift
