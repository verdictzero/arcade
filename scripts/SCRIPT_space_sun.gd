class_name SpaceSun
extends Control

# A fake distant sun + an intense, procedural lens flare. Drop the prefab into a
# space scene and it self-wires: it finds the scene's DirectionalLight3D and the
# active Camera3D, parks a bright unshaded disc far out along the light's
# INCOMING direction (so the sun sits where the light comes from), and tints
# everything to match the light's colour. The disc follows the camera at a fixed
# distance, so it reads as infinitely far (no parallax, can't be flown to).
#
# This Control lives on a CanvasLayer and draws the flare itself: a soft core
# glow + halo on the sun, an anamorphic streak, and a chain of ghost discs
# marching through screen centre — all additively blended and brightest when the
# sun is centred in view. No texture assets needed; the soft sprite is generated.
#
# IT IS ALSO USED WHERE THERE IS NO SUN. SCENE_test_zone_W2 has no light in it at
# all (everything there is `render_mode unshaded` — see that scene's SunPivot), and
# what it wants at the zenith is not a sun but a PUPIL: the eye panorama that fades
# in over the flip has a large eye centred exactly on the pole, with a solid bright
# core 4.3 degrees across, and a flare parked in the middle of it lights that core
# from inside. `direction_override` is what lets the same drawing code do that —
# point it straight up, hand it a colour, drive `flare_intensity` off the
# crossing, and every element below (halo, streak, ghost chain) still works,
# because none of them ever cared that the bright point was a star.

## The sun disc MeshInstance3D (sibling under the prefab root).
@export var disc_path: NodePath = ^"../../Disc"
## How far out the disc is parked (must be < the camera's far plane).
@export var distance := 8000.0
## Disc radius in world units at that distance (≈6° across at the defaults).
@export var disc_radius := 420.0
## Emission energy on the disc — crank it so the WorldEnvironment glow blooms it.
@export var disc_emission_energy := 18.0
## Overall flare brightness multiplier.
@export var flare_intensity := 1.5
## Per-second rate the flare fades in/out as objects (capital ships, islands)
## cross the line of sight to the sun. Higher = snappier. The player flight body
## is on no collision layer and the cockpit is visual-only, so neither occludes.
@export var occlusion_fade_rate := 12.0
## If alpha > 0, use this instead of the directional light's colour.
@export var override_color := Color(0, 0, 0, 0)
## How strongly the ghost elements take on their rainbow tint (0 = pure sun
## colour, 1 = full tint). Keep it low for a subtle chromatic shimmer.
@export_range(0.0, 1.0) var rainbow_amount := 0.35
## Tint of the anamorphic streaks (classic flares streak cool blue).
@export var anamorphic_color := Color(0.5, 0.72, 1.0)
## The chromatic split above and below the streak — a real lens aberration, and
## the reason the streak has an edge rather than just a width. The defaults are the
## classic warm/cool pair.
##
## THEY ARE EXPORTS BECAUSE A COOL FRINGE IS NOT ALWAYS RIGHT. In a scene where the
## entire palette is red — SCENE_test_zone_W2's nightmare — a blue line under the
## flare is the only cool pixel on screen, and it reads as a bug in the flare
## rather than as an artefact of a lens. Set both warm there and the split still
## does its job, because what sells it is that the two edges DIFFER, not that one
## of them is blue.
@export var fringe_warm := Color(1.0, 0.4, 0.4)
@export var fringe_cool := Color(0.4, 0.5, 1.0)
## Length of the main anamorphic streak as a multiple of screen width.
@export var anamorphic_length := 1.6

@export_group("No Light")
## World direction the source sits in, INSTEAD of hunting for a DirectionalLight3D.
## Zero (the default) keeps the self-wiring behaviour every space scene relies on.
##
## `Vector3.UP` parks it at the zenith, which is what SCENE_test_zone_W2 wants. The
## vector is normalised on use and does not have to be a unit.
##
## Setting this also stops the per-frame `_find_light` walk of the whole scene
## tree, which in a scene that genuinely has no light would otherwise recurse every
## node every frame forever and never find one.
@export var direction_override := Vector3.ZERO
## Multiplier on every element, on top of `flare_intensity`. Public so the flare
## can be faded by something outside it — the W2 director runs this off the
## nightmare crossing so the pupil lights as the eye opens.
@export_range(0.0, 1.0) var master_alpha := 1.0
## Scales every element's SIZE. `flare_intensity` scales brightness and saturates;
## this is the dial for "massive". 1.0 is the space-scene look.
@export_range(0.1, 6.0, 0.05, "or_greater") var flare_scale := 1.0
## How white the hot centre goes. 1.0 is the classic blown-out white pinpoint and
## is what the space scenes ship. Drop it toward 0 to keep the core the flare's own
## colour — a red flare with a white centre reads as a star, and W2 needs a pupil.
@export_range(0.0, 1.0) var core_whiteness := 1.0
## Whether the far disc mesh is drawn at all. A flare standing in for something the
## sky already draws (W2's apex eye) wants the flare and not a second bright ball
## in front of it.
@export var show_disc := true

var _light: DirectionalLight3D
var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _sprite: Texture2D
var _sun_screen := Vector2.ZERO
var _intensity := 0.0
var _color := Color(1, 1, 1)
var _occ := 1.0  # smoothed line-of-sight visibility, 1 = clear, 0 = blocked

# Ghost discs marching along the sun→centre→beyond axis. t = position (0 =
# centre, 1 = sun), s = size factor, a = base alpha, tint = rainbow hue mixed in
# (subtly, per rainbow_amount) for chromatic variety across the chain.
const GHOSTS := [
	{"t": -0.40, "s": 0.60, "a": 0.26, "tint": Color(1.0, 0.45, 0.35)},
	{"t": -0.15, "s": 0.22, "a": 0.40, "tint": Color(0.45, 1.0, 0.6)},
	{"t": 0.15, "s": 0.35, "a": 0.42, "tint": Color(0.5, 0.7, 1.0)},
	{"t": 0.32, "s": 0.18, "a": 0.55, "tint": Color(1.0, 0.9, 0.45)},
	{"t": 0.50, "s": 0.90, "a": 0.22, "tint": Color(0.6, 0.45, 1.0)},
	{"t": 0.66, "s": 0.28, "a": 0.45, "tint": Color(0.4, 1.0, 0.9)},
	{"t": 0.80, "s": 0.16, "a": 0.58, "tint": Color(1.0, 0.5, 0.4)},
	{"t": 1.00, "s": 0.50, "a": 0.38, "tint": Color(0.5, 0.8, 1.0)},
	{"t": 1.25, "s": 1.20, "a": 0.18, "tint": Color(1.0, 0.6, 0.9)},
	{"t": 1.50, "s": 0.24, "a": 0.50, "tint": Color(0.7, 1.0, 0.5)},
	{"t": 1.70, "s": 0.42, "a": 0.30, "tint": Color(0.5, 0.6, 1.0)},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var cim := CanvasItemMaterial.new()
	cim.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = cim
	_sprite = _make_radial(64, 2.2)
	_disc = get_node_or_null(disc_path) as MeshInstance3D
	if _disc != null and not show_disc:
		_disc.visible = false
		_disc = null
	if _disc != null:
		_disc_mat = StandardMaterial3D.new()
		_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_disc_mat.albedo_color = Color(0, 0, 0)
		_disc_mat.emission_enabled = true
		_disc.material_override = _disc_mat
		_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_disc.scale = Vector3.ONE * disc_radius


const SUN_RAY_STRIDE := 6
var _sun_ray_tick := 0
var _sun_target_occ := 1.0
var _last_intensity := -1.0
var _last_screen := Vector2.ZERO


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	# A fixed direction is a complete substitute for the light, so the tree walk is
	# skipped entirely rather than run and ignored — in a scene with no light it
	# never terminates early and would recurse every node, every frame, forever.
	var fixed := direction_override.length_squared() > 1e-6
	if _light == null and not fixed:
		_light = _find_light(get_tree().root)
	if cam == null or (_light == null and not fixed):
		if _intensity != 0.0:
			_intensity = 0.0
			queue_redraw()
		return
	if override_color.a > 0.0:
		_color = override_color
	elif _light != null:
		_color = _light.light_color
	else:
		_color = Color(1, 1, 1)
	# The light shines along its -Z; the sun is the source, so out along +Z.
	var sun_dir := direction_override.normalized() if fixed \
			else _light.global_transform.basis.z.normalized()
	var sun_pos := cam.global_position + sun_dir * distance
	if _disc != null:
		_disc.global_position = sun_pos
		# Emission is static unless the sun colour changes — skip the per-frame
		# material writes when it hasn't.
		if _disc_mat.emission != _color:
			_disc_mat.emission = _color
			_disc_mat.emission_energy_multiplier = disc_emission_energy

	if cam.is_position_behind(sun_pos):
		_intensity = 0.0
	else:
		_sun_screen = cam.unproject_position(sun_pos)
		var vp := get_viewport_rect().size
		var center := vp * 0.5
		var centered := clampf(1.0 - _sun_screen.distance_to(center) / center.length(), 0.0, 1.0)
		# Visible while the sun is on or near the screen; brightest when centred.
		var on := _sun_screen.x > -vp.x * 0.5 and _sun_screen.x < vp.x * 1.5 \
				and _sun_screen.y > -vp.y * 0.5 and _sun_screen.y < vp.y * 1.5
		# Occlusion: cast a ray from the camera to the (far) sun. A solid body in
		# the way (capital ship, island) blocks it; the player ship (no layer)
		# and the visual-only cockpit do not. Smoothed so it fades, not pops.
		# Occlusion ray is the per-frame cost here; cast it only every
		# SUN_RAY_STRIDE frames and reuse the cached result — the _occ lerp
		# below smooths over the gaps so it's visually identical.
		if _sun_ray_tick <= 0:
			_sun_ray_tick = SUN_RAY_STRIDE
			_sun_target_occ = 1.0
			var space := cam.get_world_3d().direct_space_state
			if space != null:
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, sun_pos)
				var hit := space.intersect_ray(q)
				# Ignore hits right at the camera — that's the player's own body
				# (e.g. the on-foot capsule the camera sits inside), not an occluder.
				if not hit.is_empty() and cam.global_position.distance_to(hit.position) > 3.0:
					_sun_target_occ = 0.0
		_sun_ray_tick -= 1
		_occ = lerpf(_occ, _sun_target_occ, clampf(occlusion_fade_rate * delta, 0.0, 1.0))
		_intensity = (0.35 + 0.65 * centered) * flare_intensity * _occ * master_alpha \
				if on else 0.0
	# Repaint only when the flare actually changed — the sun is far and slow,
	# so most frames are pixel-identical and the ~18 blits can be skipped.
	if absf(_intensity - _last_intensity) > 0.002 or _sun_screen != _last_screen:
		_last_intensity = _intensity
		_last_screen = _sun_screen
		queue_redraw()


func _draw() -> void:
	if _intensity <= 0.0:
		return
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var axis := _sun_screen - center
	# Every radius below is a fraction of screen HEIGHT times this, so "massive" is
	# one dial and it does not change any element's relationship to the others.
	var s := flare_scale
	# The hot centre, between white and the flare's own colour. A white pinpoint is
	# what makes a distant star read as a star; a pupil has to stay the colour of
	# the eye it is in, so this is a mix rather than a fixed white.
	var core := Color(1, 1, 1).lerp(_color, 1.0 - core_whiteness)
	# Core glow + halo right on the sun (largest, softest first).
	_blit(_sun_screen, vp.y * 0.55 * s, _color, 0.45 * _intensity)
	_blit(_sun_screen, vp.y * 0.22 * s, _color, 0.70 * _intensity)
	_blit(_sun_screen, vp.y * 0.08 * s, core, 0.95 * _intensity)

	# Anamorphic streak: a wide cool-blue bar with a subtle red/blue chromatic
	# split above/below, capped by a thin bright white core for the hot centre.
	var streak_w := vp.x * anamorphic_length
	var fringe := (vp.y * 0.012 + 3.0) * s
	_blit_rect(_sun_screen + Vector2(0.0, -fringe),
			Vector2(streak_w, (vp.y * 0.018 + 5.0) * s), fringe_warm, 0.10 * _intensity)
	_blit_rect(_sun_screen + Vector2(0.0, fringe),
			Vector2(streak_w, (vp.y * 0.018 + 5.0) * s), fringe_cool, 0.10 * _intensity)
	_blit_rect(_sun_screen, Vector2(streak_w, (vp.y * 0.022 + 6.0) * s),
			anamorphic_color, 0.22 * _intensity)
	_blit_rect(_sun_screen, Vector2(streak_w * 0.8, (vp.y * 0.006 + 2.0) * s),
			core, 0.30 * _intensity)

	# Ghost chain marching through screen centre, each with its rainbow tint
	# blended subtly over the sun colour.
	for g in GHOSTS:
		var p: Vector2 = center + axis * float(g["t"])
		var tint: Color = _color.lerp(g["tint"], rainbow_amount)
		_blit(p, vp.y * 0.16 * s * float(g["s"]), tint, float(g["a"]) * _intensity)


func _blit(pos: Vector2, size: float, col: Color, a: float) -> void:
	var s := Vector2(size, size)
	draw_texture_rect(_sprite, Rect2(pos - s * 0.5, s), false, Color(col.r, col.g, col.b, a))


func _blit_rect(pos: Vector2, size: Vector2, col: Color, a: float) -> void:
	draw_texture_rect(_sprite, Rect2(pos - size * 0.5, size), false, Color(col.r, col.g, col.b, a))


# A soft radial sprite (white core fading to transparent) used for every element.
func _make_radial(s: int, falloff: float) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := (s - 1) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x - c, y - c).length() / c
			var a := pow(clampf(1.0 - d, 0.0, 1.0), falloff)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _find_light(n: Node) -> DirectionalLight3D:
	if n is DirectionalLight3D:
		return n
	for c in n.get_children():
		var r := _find_light(c)
		if r != null:
			return r
	return null
