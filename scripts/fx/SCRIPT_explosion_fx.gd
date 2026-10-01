class_name ExplosionFx
extends Node3D

# A DEATH: Mac-Pan going up. Drawn with mewd-engine's baked art (ExplosionAtlas)
# the way mewd draws a bang — "one call is one ball; a bang is a dozen of them" —
# in four layers of camera-facing sprites:
#
#   flash     one big fireball frame that pops and is gone in a blink
#   fireballs a dozen-odd balls thrown out and up, growing as they go, white
#             through the fire ramp to nothing (mewd's c0 -> c1), additive
#   sparks    the spark texel, flung hard and falling under gravity, additive
#   smoke     the eight-frame puff, rising slowly after the fire, grey, fading
#
# Every sprite is moved, grown, faded and frame-stepped here, by hand, rather than
# by a particle node: a few dozen quads, the same on desktop and in the browser.
# `size` is the bang's width in metres. Frees itself when the last sprite is out.

@export var size := 3.2

var _sprites: Array = []   # of Dictionary
var _rng := RandomNumberGenerator.new()


## Play one at `at` (world space) under `parent`.
static func spawn(parent: Node, at: Vector3, size := 3.2) -> ExplosionFx:
	var fx := ExplosionFx.new()
	fx.size = size
	parent.add_child(fx)
	fx.global_position = at
	return fx


func _ready() -> void:
	_rng.randomize()
	var at := ExplosionAtlas.atlases()
	var s := size / 3.2
	var fire := _gradient([Color(1, 1, 1, 1), Color(1, 0.78, 0.35, 0.95), Color(1, 0.45, 0.12, 0.0)])
	var flash := _gradient([Color(1, 1, 0.9, 1), Color(1, 0.7, 0.3, 0.0)])
	var spark := _gradient([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 1), Color(0.5, 0.12, 0.02, 0)])
	var smoke := _gradient([Color(0.2, 0.18, 0.16, 0.0), Color(0.24, 0.22, 0.2, 0.8), Color(0.42, 0.41, 0.4, 0.0)])
	var centre := Vector3(0, 0.7 * s, 0)

	_add(at.fireball, ExplosionAtlas.FIREBALLS, true, flash, centre, Vector3.ZERO,
			0.0, 0.2, 3.2 * s, 4.6 * s, 0.0, 0.0)
	for i in 16:
		var d := _dir(0.25)
		_add(at.fireball, ExplosionAtlas.FIREBALLS, true, fire, centre + d * 0.3 * s,
				d * _rng.randf_range(2.0, 5.0) * s, _rng.randf_range(0.0, 0.08),
				_rng.randf_range(0.6, 1.0), 0.8 * s, _rng.randf_range(1.8, 2.6) * s,
				4.0, 1.5)
	for i in 50:
		var d := _dir(-0.1)
		_add(at.spark, 1, true, spark, centre, d * _rng.randf_range(5.0, 11.0) * s,
				0.0, _rng.randf_range(0.6, 1.1), 0.14 * s, 0.07 * s, 0.6, -14.0)
	for i in 12:
		var d := _dir(0.6)
		_add(at.smoke, ExplosionAtlas.SMOKE_PUFFS, false, smoke, centre + d * 0.5 * s,
				d * _rng.randf_range(0.6, 1.6) * s, _rng.randf_range(0.15, 0.5),
				_rng.randf_range(1.6, 2.4), 1.2 * s, _rng.randf_range(2.6, 3.6) * s,
				1.2, 0.5)


# A random direction, weighted upward by `lift` (0 = any way, 1 = straight up).
func _dir(lift: float) -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1), _rng.randf_range(-1, 1))
	v.y += lift
	return v.normalized()


func _add(tex: Texture2D, frames: int, additive: bool, ramp: Gradient, pos: Vector3,
		vel: Vector3, delay: float, life: float, size0: float, size1: float,
		drag: float, gravity: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(1.0 / frames, 1.0, 1.0)
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = pos
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_sprites.append({
		"mi": mi, "mat": mat, "ramp": ramp, "vel": vel, "age": -delay, "life": life,
		"s0": size0, "s1": size1, "drag": drag, "g": gravity, "frames": frames,
		"frame0": _rng.randi() % frames, "fps": 12.0,
	})


func _process(delta: float) -> void:
	var alive := 0
	for p in _sprites:
		var mi: MeshInstance3D = p.mi
		p.age += delta
		if p.age < 0.0:
			alive += 1
			continue
		var t: float = p.age / p.life
		if t >= 1.0:
			mi.visible = false
			continue
		alive += 1
		mi.visible = true
		var vel: Vector3 = p.vel
		vel *= exp(-p.drag * delta)
		vel.y += p.g * delta
		p.vel = vel
		mi.position += vel * delta
		mi.scale = Vector3.ONE * lerpf(p.s0, p.s1, t)
		var mat: StandardMaterial3D = p.mat
		mat.albedo_color = (p.ramp as Gradient).sample(t)
		var f: int = (p.frame0 + int(p.age * p.fps)) % p.frames
		mat.uv1_offset = Vector3(float(f) / p.frames, 0.0, 0.0)
	if alive == 0:
		queue_free()


func _gradient(colors: Array) -> Gradient:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / float(colors.size() - 1))
		cols.append(colors[i])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	return g
