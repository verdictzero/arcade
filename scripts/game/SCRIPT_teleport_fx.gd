class_name TeleportFx
extends Node3D

# THE SIDE TUNNEL'S TELEPORT: a column of energy bands racing up from the ground,
# a ring flashing out across it and sparks lifting off, all additive light
# (SHADER_teleport_energy.gdshader). One plays where an actor beams out and one
# where it beams in — see MazeActor._tunnel_exit. Frees itself when done.

const LIFE := 0.7
const SHADER := preload("res://shaders/SHADER_teleport_energy.gdshader")

var delay := 0.0
var _t := 0.0
var _column: ShaderMaterial
var _ring: ShaderMaterial
var _ring_mesh: MeshInstance3D
var _sparks: CPUParticles3D


## Play one at `at` (world space) under `parent`, `delay` seconds from now.
static func spawn(parent: Node, at: Vector3, delay := 0.0) -> TeleportFx:
	var fx := TeleportFx.new()
	fx.delay = delay
	parent.add_child(fx)
	fx.global_position = at
	return fx


func _ready() -> void:
	_column = _material(0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.75
	cyl.height = 3.2
	cyl.cap_top = false
	cyl.cap_bottom = false
	var col := MeshInstance3D.new()
	col.mesh = cyl
	col.material_override = _column
	col.position.y = 1.6
	add_child(col)

	_ring = _material(1)
	var quad := QuadMesh.new()
	quad.size = Vector2(3.6, 3.6)
	quad.orientation = PlaneMesh.FACE_Y
	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.mesh = quad
	_ring_mesh.material_override = _ring
	_ring_mesh.position.y = 0.05
	add_child(_ring_mesh)

	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 40
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 0.85
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_sparks.emission_ring_axis = Vector3.UP
	_sparks.emission_ring_radius = 0.7
	_sparks.emission_ring_inner_radius = 0.2
	_sparks.emission_ring_height = 0.1
	_sparks.direction = Vector3.UP
	_sparks.spread = 20.0
	_sparks.initial_velocity_min = 2.5
	_sparks.initial_velocity_max = 5.0
	_sparks.gravity = Vector3(0, -2.0, 0)
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.2
	var spark := QuadMesh.new()
	spark.size = Vector2(0.08, 0.22)
	var spark_mat := _material(0)
	spark_mat.set_shader_parameter("band_count", 0.0)
	spark_mat.set_shader_parameter("intensity", 1.5)
	spark.material = spark_mat
	_sparks.mesh = spark
	_sparks.particle_flag_align_y = true
	add_child(_sparks)
	visible = delay <= 0.0
	_apply(0.0)


func _material(shape: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("shape", shape)
	return m


func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		if delay > 0.0:
			return
		visible = true
	if _t == 0.0:
		_sparks.restart()
		_sparks.emitting = true
	_t += delta
	var k := clampf(_t / LIFE, 0.0, 1.0)
	_apply(k)
	if _t >= LIFE + 0.6:
		queue_free()


func _apply(k: float) -> void:
	# Envelope: a hard flash in, a slower fall away.
	var env := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.35, 1.0, k))
	_column.set_shader_parameter("intensity", env)
	_ring.set_shader_parameter("intensity", env * 1.3)
	_ring.set_shader_parameter("progress", k)
