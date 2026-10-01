extends Camera3D

# Free-fly camera for the island scene. Ported from golf's SCRIPT_fly_camera.gd
# with the on-foot handover (T, PREFAB_player.tscn) removed: that prefab brings
# golf's whole player — golf, build and vehicle controllers — and arcade has none
# of it. What is left is the flying, the variable speed and the collision toggle.
#
# KEYBOARD/MOUSE: WASD to move in the look plane, Q/E down/up, Shift to boost and
# Alt to creep. Mouse looks while captured; click to (re)capture, Esc to release.
# Mouse wheel (or [ and ]) scales the base speed. C toggles collision.
#
# CONTROLLER: left stick to move, right stick to look, LT/RT down and up, LB/RB
# down and up the speed ladder.
#
# Drives IslandWorld's streaming just by being the active camera.

@export var speed := 600.0
@export var boost_mult := 5.0
@export var precision_mult := 0.15
@export var look_sensitivity := 0.0025
@export var stick_look_speed := 900.0

@export_group("Variable speed")
@export var speed_step := 1.25
@export var speed_scale_min := 1.0 / 128.0
@export var speed_scale_max := 8.0

@export_group("Collision")
## Off by default. On, the camera sweeps a sphere against world geometry and slides
## along it. A SWEEP, not a body: a probe that starts embedded moves unimpeded.
@export var collide := false
@export var probe_radius := 0.6
@export var probe_skin := 0.03

const STICK_LOOK_CURVE := 2.0

var _yaw := 0.0
var _pitch := 0.0
var _speed_scale := 1.0
var _probe: SphereShape3D = null

const HUD_LAYER := 205
const HUD_HOLD := 2.2
const HUD_FADE := 0.5
var _hud: CanvasLayer = null
var _hud_label: Label = null
var _hud_tween: Tween = null


func _ready() -> void:
	var e := global_transform.basis.get_euler()
	_yaw = e.y
	_pitch = e.x
	_probe = SphereShape3D.new()
	_probe.radius = probe_radius
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_yaw -= event.relative.x * look_sensitivity
			_pitch = clampf(_pitch - event.relative.y * look_sensitivity, -1.4, 1.4)
		return
	if event is InputEventMouseButton and event.pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			nudge_speed(1)
			return
		if button == MOUSE_BUTTON_WHEEL_DOWN:
			nudge_speed(-1)
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("fly_speed_up"):
		nudge_speed(1)
		return
	if event.is_action_pressed("fly_speed_down"):
		nudge_speed(-1)
		return
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_C:
			collide = not collide
			_say("COLLISION  %s" % ("ON" if collide else "OFF"))


func nudge_speed(notches: int) -> void:
	_speed_scale = clampf(_speed_scale * pow(speed_step, float(notches)),
			speed_scale_min, speed_scale_max)
	_say("SPEED  %s m/s" % _fmt(current_speed()))


func current_speed() -> float:
	return speed * _speed_scale


func _process(delta: float) -> void:
	_stick_look(delta)
	_fly_step(delta)


func _stick_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.is_zero_approx():
		return
	var mag := minf(look.length(), 1.0)
	look = look.normalized() * pow(mag, STICK_LOOK_CURVE) * stick_look_speed * delta
	_yaw -= look.x * look_sensitivity
	_pitch = clampf(_pitch - look.y * look_sensitivity, -1.4, 1.4)


# Movement takes the stick's MAGNITUDE rather than normalising it, so half a stick
# is half speed; the keyboard's digital 1.0 lands on the same full rate.
func _fly_step(delta: float) -> void:
	var b := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	global_transform.basis = b
	var plane := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := b.x * plane.x + b.z * plane.y
	dir += Vector3.UP * (Input.get_action_strength("fly_up")
			- Input.get_action_strength("fly_down"))
	var mag := minf(dir.length(), 1.0)
	if mag <= 0.001:
		return
	var sp := current_speed() * mag
	if Input.is_physical_key_pressed(KEY_SHIFT):
		sp *= boost_mult
	elif Input.is_physical_key_pressed(KEY_ALT):
		sp *= precision_mult
	var motion := dir.normalized() * sp * delta
	global_position = _sweep(global_position, motion) if collide \
			else global_position + motion


# Per-axis sphere sweep so the camera slides along a slope instead of sticking.
func _sweep(from: Vector3, motion: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return from + motion
	if _embedded(space, from):
		return from + motion
	var pos := from
	for axis in 3:
		if absf(motion[axis]) <= 0.0:
			continue
		var step := Vector3.ZERO
		step[axis] = motion[axis]
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _probe
		q.transform = Transform3D(Basis(), pos)
		q.motion = step
		q.collide_with_areas = false
		var result := space.cast_motion(q)
		var safe: float = result[0] if result.size() > 0 else 1.0
		if safe < 1.0:
			safe = clampf(safe - (probe_skin / maxf(step.length(), 0.0001)), 0.0, 1.0)
		pos += step * safe
	return pos


func _embedded(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis(), at)
	q.collide_with_areas = false
	return not space.intersect_shape(q, 1).is_empty()


func _fmt(v: float) -> String:
	return "%.1f" % v if absf(v) < 10.0 else "%d" % roundi(v)


func _say(text: String) -> void:
	if _hud == null:
		_build_hud()
	_hud_label.text = text
	if _hud_tween != null and _hud_tween.is_valid():
		_hud_tween.kill()
	_hud_label.modulate.a = 1.0
	_hud.visible = true
	_hud_tween = create_tween()
	_hud_tween.tween_interval(HUD_HOLD)
	_hud_tween.tween_property(_hud_label, "modulate:a", 0.0, HUD_FADE)
	_hud_tween.tween_callback(func() -> void: _hud.visible = false)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "FlyCameraReadout"
	_hud.layer = HUD_LAYER
	_hud.visible = false
	add_child(_hud)
	_hud_label = Label.new()
	_hud_label.add_theme_font_override("font", Fonts.technical())
	_hud_label.add_theme_font_size_override("font_size", 18)
	_hud_label.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0))
	_hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_hud_label.add_theme_constant_override("outline_size", 5)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud_label.position = Vector2(0.0, -96.0)
	_hud.add_child(_hud_label)
