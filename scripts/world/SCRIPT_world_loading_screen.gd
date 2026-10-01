class_name WorldLoadingScreen
extends CanvasLayer

# Covers the screen while `SCRIPT_island_world.gd` pregenerates the world, then gets out
# of the way. Same terminal-green look as `SCRIPT_boot_sequence_hud.gd`, deliberately far
# plainer: this one is a progress readout, not a title sequence.
#
# It draws OVER the post-process dither layer (which sits at layer 128), because
# the world underneath is half-built for the couple of seconds it is up and there
# is no reason to show it dithering into existence.
#
# Everything here is driven by two signals — `pregen_progress` and
# `pregen_finished` — so this node knows nothing about chunks, LODs or threads.
# Point `world_path` at any node that emits them.

## Node emitting `pregen_progress(stage, done, total)` and `pregen_finished()`.
## Normally the scene's IslandWorld.
@export var world_path: NodePath
## Optional second stage: nodes with `prefill_step()` / `prefill_ratio()`, run
## after the world is built and before the screen clears. The tree and grass
## scatters use this, so the forest is standing and the ground cover is down when
## the screen lifts rather than sprouting around the player.
##
## Stepped ROUND-ROBIN, all of them every frame, and the stage ends when they all
## report finished. They mesh on worker threads, so the frames here are mostly
## spent waiting; running them one after another would serialise two things that
## are already parallel underneath.
##
## A scatter MAY also offer `prefill_label() -> String`, which is printed under the
## bar the way `meshing terrain N / M` is printed for the world. It is optional and
## checked per node, so a scatter without one costs nothing but a plainer line.
##
## Stepping them is an ACCELERATOR, not the contract. A scatter is responsible for
## finishing on its own — this screen gives up on a wall clock (`scatter_timeout`)
## and then stops processing for good, and a scatter that only advanced when
## stepped was left permanently half-built by that. See `veg_scatter._process`.
@export var scatter_paths: Array[NodePath] = []
## Held for this long after everything is ready, so a fast machine still reads
## "READY" rather than flashing a bar and vanishing.
@export var settle := 0.35
@export var fade_time := 0.45
## Give up on the optional second stage after this long and clear anyway.
##
## Load-bearing, not belt-and-braces. The tree scatter reports "not finished"
## while it is still baking its impostor, and that bake awaits a drawn frame —
## which never arrives under `--headless`, and need not arrive on a machine whose
## renderer refused the bake either. Without a ceiling here the screen would sit
## at 80% forever, and a loading screen that can strand the player behind it is
## worse than no loading screen.
@export var scatter_timeout := 12.0

@export_group("Look")
@export var back_color := Color(0.02, 0.025, 0.02, 1.0)
@export var text_color := Color(0.55, 0.95, 0.55, 1.0)
@export var dim_color := Color(0.28, 0.55, 0.30, 1.0)
@export var bar_color := Color(0.40, 1.0, 0.45, 1.0)
@export var title := "GENERATING TERRAIN"
## Shown INSTEAD of `title` when the world did not have to generate anything —
## when it came out of a bake, in memory or on disk. See `IslandWorld.bake_source`.
##
## The two loads look identical from in front of the screen and are not remotely
## the same thing: one is ninety seconds of meshing, the other is a few seconds of
## reading a file. Saying "GENERATING" over both is how a pre-generated world gets
## reported as a world that regenerates itself after every battle.
@export var held_title := "LOADING TERRAIN"
@export var bar_size := Vector2(560.0, 18.0)
@export var title_size := 30
@export var text_size := 16

enum _Phase { WORLD, SCATTER, SETTLE, FADING, GONE }

var _phase := _Phase.WORLD
var _font: Font
var _fade := 1.0
var _settle_left := 0.0
var _scatter_left := 0.0
var _t := 0.0
var _stage := "survey"
var _done := 0
var _total := 0
var _scatters: Array[Node] = []
var _rect: Control = null
# Progress the bar has actually reached. Chased toward the true ratio rather than
# snapped to it, so a burst of installs in one frame reads as motion instead of a
# jump — and so the bar never sits frozen while a long survey frame runs.
var _shown := 0.0


func _ready() -> void:
	layer = 129   # above PostFX's dither layer
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = _pick_font()

	_rect = Control.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.draw.connect(_draw_screen)
	add_child(_rect)

	for p in scatter_paths:
		var n := get_node_or_null(p)
		if n != null and n.has_method("prefill_step") and n.has_method("prefill_ratio"):
			_scatters.append(n)

	var world := get_node_or_null(world_path)
	# The SIGNAL is not the test. `SCRIPT_island_world.gd` declares `pregen_finished`
	# whether or not it is going to build anything up front, so a purely streaming
	# world passes a has_signal() check and then never emits — which strands the
	# player behind a screen that will never lift, exactly the failure this branch
	# exists to prevent. Ask the flags.
	#
	# BOTH flags, and forgetting the second one is what this cost last time. W2
	# carried this node, and a `world_path` pointing straight at its IslandWorld,
	# while the world itself only ever streamed — so every load took the branch
	# below, warned into a log nobody reads, and cleared the screen at frame 8. The
	# terrain then built in front of the player instead of behind the screen, which
	# is precisely the bug the screen exists to prevent.
	#
	# COMPARED TO `true` RATHER THAN PUT THROUGH `bool()`, and that is not style.
	# `Object.get` on a property the node does not have returns null, and `bool(null)`
	# is not a falsy conversion — there is no bool constructor from Nil and the call
	# THROWS. It never fired while the only world here was an IslandWorld, which has
	# both flags. `SCRIPT_terrain_world.gd` prewarms and does not pregenerate, so one
	# of the two is always absent on it, and the `or` only short-circuits past the
	# missing one while the present one is TRUE — i.e. this crashed on exactly the
	# case the branch exists to handle. `== true` asks the same question of a
	# property that may not exist at all.
	if world == null or not world.has_signal("pregen_finished") \
			or not (world.get("prewarm") == true or world.get("pregenerate") == true):
		push_warning("world_loading_screen: world at '%s' builds nothing up front "
				% world_path + "(prewarm and pregenerate both off); clearing.")
		_phase = _Phase.SETTLE
		_settle_left = 0.0
		return
	world.pregen_progress.connect(_on_progress)
	world.pregen_finished.connect(_on_world_done)


# The project's terminal face, via a lookup rather than the `Fonts` global.
#
# Naming the autoload directly is a COMPILE-time reference, so this whole script
# fails to load in any context where autoloads are absent — which includes every
# `--script` test harness. Since the only thing at stake is which font the bar is
# labelled in, resolving it by path and falling back costs nothing and keeps the
# screen testable.
func _pick_font() -> Font:
	var fonts := get_tree().root.get_node_or_null("Fonts")
	if fonts != null and fonts.has_method("technical"):
		var f: Font = fonts.call("technical")
		if f != null:
			return f
	return ThemeDB.fallback_font


func _on_progress(stage: String, done: int, total: int) -> void:
	_stage = stage
	_done = done
	_total = total


func _on_world_done() -> void:
	if _phase == _Phase.WORLD:
		_phase = _Phase.SCATTER if _can_prefill() else _Phase.SETTLE
		_settle_left = settle
		_scatter_left = scatter_timeout


func _can_prefill() -> bool:
	return not _scatters.is_empty()


func _process(delta: float) -> void:
	_t += delta
	# TELL THE SCATTERS THEY ARE STILL BEHIND A BAR, every frame and in every phase.
	#
	# A scatter that builds the world up front wants to run as wide as the machine
	# allows while nothing can be seen, and to get out of the frame's way the
	# instant something can — `veg_scatter._prescatter_width` is the one that acts
	# on it. Only this node knows which of those is true.
	#
	# IT CANNOT BE INFERRED FROM `prefill_step()`, which was the first attempt.
	# Stepping does not begin until `_on_world_done`, so a scatter reading "was I
	# stepped recently" as "is a screen up" concluded it was exposed for the whole
	# terrain build — the seventeen seconds it has the machine most completely to
	# itself — and throttled itself down to one lane through all of it.
	#
	# Optional and checked per node, like `prefill_label()`: a scatter that does
	# not care about being covered simply never hears about it.
	for s in _scatters:
		if s.has_method("prefill_covered"):
			s.call("prefill_covered")
	match _phase:
		_Phase.SCATTER:
			# One slice per scatter per frame, same reason the survey is spread
			# out: what is left on the main thread is still field sampling and
			# the screen has to keep drawing. Note the loop does NOT short-circuit
			# — every scatter is stepped every frame, and only then is the stage
			# judged finished.
			_scatter_left -= delta
			var all_done := true
			for s in _scatters:
				if not bool(s.call("prefill_step")):
					all_done = false
			if all_done or _scatter_left <= 0.0:
				_phase = _Phase.SETTLE
				_settle_left = settle
		_Phase.SETTLE:
			_settle_left -= delta
			if _settle_left <= 0.0:
				_phase = _Phase.FADING
		_Phase.FADING:
			_fade = maxf(0.0, _fade - delta / maxf(fade_time, 0.001))
			if _fade <= 0.0:
				_phase = _Phase.GONE
				visible = false
				set_process(false)
				return
	_shown = move_toward(_shown, _ratio(), delta * 1.6)
	_rect.queue_redraw()


# 0..1 across the whole load. The world build is the bulk of it; the scatter
# prefill, when there is one, gets the last fifth so the bar keeps moving.
func _ratio() -> float:
	var world_share := 0.8 if _can_prefill() else 1.0
	match _phase:
		_Phase.WORLD:
			if _total <= 0:
				return 0.0
			return world_share * clampf(float(_done) / float(_total), 0.0, 1.0)
		_Phase.SCATTER:
			var acc := 0.0
			for s in _scatters:
				acc += clampf(s.call("prefill_ratio"), 0.0, 1.0)
			return world_share + (1.0 - world_share) * acc / float(_scatters.size())
	return 1.0


## ASKED EVERY FRAME RATHER THAN CACHED, because this node's `_ready` and the
## world's race: the flag is set in the world's, and which of the two runs first
## is a fact about the scene file rather than about anything here.
func _held() -> bool:
	var world := get_node_or_null(world_path)
	# `== null` rather than a falsy check: a world without the property answers
	# `null`, and `SCRIPT_terrain_world.gd` is one — it carries no bake at all.
	return world != null and world.get("bake_source") != null \
			and String(world.get("bake_source")) != ""


func _title() -> String:
	return held_title if _held() else title


func _label() -> String:
	match _phase:
		_Phase.WORLD:
			if _stage == "survey":
				return "surveying landmass"
			# Not "chunks": under `prewarm` the total counts every LOD of every
			# chunk, so it runs several times the number of chunks on screen.
			#
			# And not "meshing" when nothing is being meshed: a held world walks
			# the same jobs to build the same nodes, but every one of them is
			# answered out of the store rather than by the mesher.
			if _held():
				return "installing terrain   %d / %d" % [_done, _total]
			return "meshing terrain   %d / %d" % [_done, _total]
		_Phase.SCATTER:
			return "planting forest"
	return "ready"


# The scatters' own line, under the terrain's. This node counts nothing and knows
# the word "plant" no better than it knows "chunk" — each scatter names its own
# figure through the optional `prefill_label()`, and one with nothing worth saying
# yet returns "" and is left off rather than printing a zero.
#
# DRAWN IN THE WORLD PHASE TOO, not only in SCATTER, and that is the whole reason
# it is a separate line. `veg_scatter._process` now steps its own prescatter, so
# the wood goes down WHILE the terrain is still meshing rather than after it — on
# a machine where the planting finishes first the SCATTER phase is over inside a
# frame, and a count that only appeared there would never be seen at all.
func _sub_label() -> String:
	if _phase != _Phase.WORLD and _phase != _Phase.SCATTER:
		return ""
	var parts := PackedStringArray()
	for s in _scatters:
		if not s.has_method("prefill_label"):
			continue
		var t: String = s.call("prefill_label")
		if t != "":
			parts.append(t)
	return "   ".join(parts)


func _draw_screen() -> void:
	if _font == null or _fade <= 0.0:
		return
	var vp := _rect.size
	_rect.draw_rect(Rect2(Vector2.ZERO, vp),
			Color(back_color.r, back_color.g, back_color.b, back_color.a * _fade), true)

	var center := vp * 0.5
	var head := _title()
	var tw := _font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	_rect.draw_string(_font, Vector2(center.x - tw * 0.5, center.y - 54.0), head,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, _tint(text_color))

	var bar := Rect2(center - Vector2(bar_size.x * 0.5, 0.0), bar_size)
	_rect.draw_rect(bar, _tint(dim_color), false, 1.5)
	var filled := clampf(_shown, 0.0, 1.0)
	if filled > 0.0:
		_rect.draw_rect(Rect2(bar.position + Vector2(3.0, 3.0),
				Vector2(maxf((bar_size.x - 6.0) * filled, 1.0), bar_size.y - 6.0)),
				_tint(bar_color), true)

	var pct := "%3d%%" % int(round(filled * 100.0))
	_rect.draw_string(_font, Vector2(bar.position.x + bar_size.x + 14.0,
			bar.position.y + bar_size.y - 4.0), pct,
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, _tint(text_color))

	var msg := _label()
	var mw := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	_rect.draw_string(_font, Vector2(center.x - mw * 0.5, center.y + bar_size.y + 30.0),
			msg, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, _tint(dim_color))

	# Blinking caret, purely so a long frame never looks like a hang.
	if _phase != _Phase.FADING and fmod(_t, 0.7) < 0.4:
		_rect.draw_rect(Rect2(Vector2(center.x + mw * 0.5 + 8.0,
				center.y + bar_size.y + 30.0 - float(text_size) * 0.8),
				Vector2(float(text_size) * 0.45, float(text_size) * 0.9)),
				_tint(dim_color), true)

	var sub := _sub_label()
	if sub != "":
		var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		_rect.draw_string(_font, Vector2(center.x - sw * 0.5,
				center.y + bar_size.y + 30.0 + float(text_size) + 8.0), sub,
				HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, _tint(dim_color))


func _tint(c: Color) -> Color:
	return Color(c.r, c.g, c.b, c.a * _fade)
