class_name MacPan
extends MazeActor

# THE PLAYER. Steered with the move_* actions (WASD, arrows, d-pad, left stick).
# A turn pressed early is BUFFERED and taken at the first tile centre that allows
# it, the way the arcade lets you pre-turn into a corner; pressing back the way
# you came reverses at once. With nothing open ahead he stops, mouth half open.
#
# THE CHOMP is the model's own clamshell: MODEL_macpan.glb is a top half
# (`Sphere_001`), a bottom half (`Sphere`) and the joint they hinge on
# (`Cylinder`), the hinge on the X axis through the model's origin. The halves
# swing open and shut about that axis, mirrored; the joint never moves. The jaw
# runs off DISTANCE, not time — `chomps_per_tile` bites per tile travelled — so a
# stopped Mac-Pan holds still and a fast one chomps fast.

@export var chomps_per_tile := 1.0
## Jaw half-angle, degrees, shut and fully open.
@export var jaw_closed_deg := 2.0
@export var jaw_open_deg := 38.0

var _want := Vector2i.ZERO
var _phase := 0.25
var _top: Node3D
var _bottom: Node3D


func _ready() -> void:
	super()
	if _model != null:
		_top = _model.get_node_or_null("Sphere_001") as Node3D
		_bottom = _model.get_node_or_null("Sphere") as Node3D
	_set_jaw()


func _before_move(_delta: float) -> void:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v.length() > 0.3:
		if absf(v.x) > absf(v.y):
			_want = Vector2i(signi(roundi(v.x)), 0)
		else:
			_want = Vector2i(0, signi(roundi(v.y)))
	if _want != Vector2i.ZERO and _want == -_dir and _moving:
		reverse()


func _choose_dir(at: Vector2i) -> Vector2i:
	if _want != Vector2i.ZERO and can_enter(at, at + _want):
		return _want
	return _dir


func _after_move(_delta: float, travelled: float) -> void:
	if travelled > 0.0:
		_phase = fposmod(_phase + travelled * chomps_per_tile, 1.0)
	_set_jaw()


func _set_jaw() -> void:
	if _top == null or _bottom == null:
		return
	# 0 -> shut, 0.5 -> open, 1 -> shut: a triangle wave reads snappier than a sine.
	var open := 1.0 - absf(_phase * 2.0 - 1.0)
	var a := deg_to_rad(lerpf(jaw_closed_deg, jaw_open_deg, open))
	_bottom.rotation.x = a
	_top.rotation.x = -a
