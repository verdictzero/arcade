extends SceneTree

# PRE-GENERATES A ZONE, SO NOBODY'S FIRST LOAD IS THE ONE THAT PAYS FOR IT.
#
# Run:
#   godot --headless --script res://tools/TOOL_bake_world.gd
#   godot --headless --script res://tools/TOOL_bake_world.gd -- --scene=res://scenes/utility/SCENE_test_zone_W2.tscn
#
#   --scene=res://...  the zone to bake (default W3)
#   --dir=res://...    where to write (default `user://bake`, see below)
#   --check            report whether a current bake exists and exit. Writes
#                      nothing; exits 0 when the bake on disk is current and 1
#                      when it is missing or stale, so a script can gate on it.
#   --max=N            give up after N seconds (default 900)
#   --log=PATH         mirror everything printed here into a file as it happens
#
# THE `>>bake` LINES ARE FOR A PROGRAM READING THIS ONE. Everything printed here
# is written for a person, and a person is still the common case — but the World
# Baker dock (`addons/world_baker/`) runs this tool as a separate process and has
# to show a progress bar for five minutes of work, which means parsing. Parsing
# prose is how prose stops being free to edit, so the machine gets its own
# channel: lines beginning `>>bake ` carry one JSON object each, and nothing else
# here is a promise to anybody.
#
#   >>bake {"kind":"signature","store":"terrain","value":"4055003055"}
#   >>bake {"kind":"progress","stage":"chunks","done":412,"total":1328}
#   >>bake {"kind":"wrote","store":"terrain","entries":1328,"bytes":93840715,...}
#   >>bake {"kind":"check","current":true,"path":"user://bake/terrain_....bake","veg":"..."}
#   >>bake {"kind":"exit","code":0}
#
# JSON rather than `key=value` because a path can hold a space and a signature is
# a number, and one parser both sides already have beats two conventions that
# agree until the day they do not. `exit` is written on EVERY path out, so a
# reader that sees the process end without one knows it was killed rather than
# finished — which is a different thing to report and worth being able to tell.
#
# Writes: <dir>/terrain_<signature>.bake and <dir>/veg_<signature>.bake
#
# WHY THIS EXISTS. W3's first load is ~96 seconds on the reference container:
# 1,328 chunk meshes across five LOD levels, and 481,522 plants off a 4 m grid.
# `TerrainBake` and `VegBake` already make the SECOND load of a session ~4.6 s by
# holding both across the scene reload the encounter loop performs — but a store
# in memory dies with the process, so every run of the game pays the ninety
# seconds once. Nothing about that ninety seconds is a function of anything that
# changes between runs. It is the same island, from the same seed, through the
# same code.
#
# So: run this once, and the game reads the answer instead. Run it again when the
# generation code or the settings change — and you will KNOW when that is, because
# the signature is a function of both and `--check` will say so.
#
# WHAT MAKES IT SAFE IS THAT NOTHING HERE DECIDES ANYTHING. This tool does not
# know how a chunk is meshed or where a fir goes; it stands the REAL SCENE up,
# lets it build itself exactly as the game would, and writes down what the two
# stores ended up holding. A bake can therefore never disagree with the game about
# how the world is generated — it can only be for a DIFFERENT world, which is what
# the signature catches. See `SCRIPT_bake_store.gd`.
#
# WHERE IT WRITES, AND WHY NOT `res://` BY DEFAULT. W3's terrain bake is on the
# order of a hundred megabytes after Zstd, which is a cache and not an asset:
# committing it would put it in every clone and every diff, and it is reproducible
# from two files and a seed in the time it takes to make a coffee. `user://bake`
# is where a machine keeps its own. Pass `--dir=res://data/bake` when you actually
# want to SHIP one — a build for a machine that should never generate, a demo, a
# console target — and the game will prefer it, because `BakeStore.READ_DIRS` puts
# `res://` first.
#
# IT TAKES AS LONG AS A COLD LOAD, roughly, plus the write. It is doing the same
# work; the point is that it is doing it once, here, rather than on every launch.
#
# THE ARRAYS ARE RECORDED, which the game never does. `TerrainBake` holds
# RESOURCES — an ArrayMesh cannot be written as a Variant — so writing a bake
# means keeping the mesher's arrays alongside the meshes built from them, which
# `PROBE_bake_footprint.gd` measured at an extra 446 MB. That is a fine price for
# the five minutes this runs and a terrible one for a session, so
# `record_arrays` is set here and nowhere else.

const SCENE := "res://scenes/SCENE_arena.tscn"

## Set by `pregen_finished`. A MEMBER rather than a local captured by the
## connected lambda, because GDScript lambdas capture by VALUE: a local assigned
## inside one is the lambda's own copy, the outer one never moves, and the wait
## below runs to its deadline while the world stands finished in front of it.
var _world_done := false

var _scene_path := SCENE
var _dir := ""
var _check_only := false
var _max_seconds := 900.0

## Mirrors stdout when `--log=` is given. Opened before anything can fail, so a
## run that dies in argument parsing still leaves a file saying so.
var _log: FileAccess = null
var _log_path := ""

## Last percentage emitted for the running stage, so a 1,328-chunk build sends a
## hundred progress lines rather than 1,328. The bar cannot show more than that
## and the log has to stay readable by a person.
var _last_pct := -1


func _initialize() -> void:
	_parse_args()
	_open_log()
	var code := await _run()
	_emit({"kind": "exit", "code": code})
	if _log != null:
		_log.close()
		_log = null
	quit(code)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--scene="):
			_scene_path = a.trim_prefix("--scene=")
		elif a.begins_with("--dir="):
			_dir = a.trim_prefix("--dir=").trim_suffix("/")
		elif a.begins_with("--max="):
			_max_seconds = maxf(a.trim_prefix("--max=").to_float(), 1.0)
		elif a.begins_with("--log="):
			_log_path = a.trim_prefix("--log=")
		elif a == "--check":
			_check_only = true


func _open_log() -> void:
	if _log_path == "":
		return
	var dir := _log_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	_log = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log == null:
		push_error("tool_bake_world: could not open %s for the log" % _log_path)


## Everything this tool says goes through here, so `--log=` cannot miss a line.
##
## FLUSHED EVERY TIME, which is the whole point of the file: a reader tailing it
## wants the line that says what is happening NOW, and a buffer that shows up
## five minutes later at process exit is a progress bar that only moves once.
func _say(text: String) -> void:
	print(text)
	if _log != null:
		_log.store_line(text)
		_log.flush()


## The machine channel. See the header.
func _emit(d: Dictionary) -> void:
	_say(">>bake %s" % JSON.stringify(d))


## An error a person reads AND a reader downstream can show. `push_error` alone
## goes to stderr, which is a separate pipe nobody here is reading.
func _fail(text: String) -> void:
	push_error(text)
	_say("ERROR: %s" % text)
	_emit({"kind": "error", "message": text})


func _run() -> int:
	await process_frame
	var terrain: Node = root.get_node_or_null("TerrainBake")
	var veg: Node = root.get_node_or_null("VegBake")
	if terrain == null or veg == null:
		_fail("tool_bake_world: the bake autoloads are not registered")
		return 2
	if _dir == "":
		_dir = terrain.WRITE_DIR

	var packed := load(_scene_path) as PackedScene
	if packed == null:
		_fail("tool_bake_world: %s did not load" % _scene_path)
		return 2
	var scene := packed.instantiate()
	var world := scene.get_node_or_null("IslandWorld")
	var scatter := scene.get_node_or_null("VegScatter")
	if world == null:
		_fail("tool_bake_world: %s carries no IslandWorld" % _scene_path)
		scene.free()
		return 2

	# THE SIGNATURES BEFORE THE BUILD, which is what makes `--check` cheap: both
	# are a function of settings and source files, so they are knowable without
	# meshing a single chunk or planting a fern.
	#
	# DERIVED IN `BakeRetention`, NOT HERE. `tools/TOOL_bake_retention.gd` has to
	# ask the same question of every zone in the project, and a second copy of
	# these lines would be a second opinion about which bake belongs to which
	# world — the exact thing this tool's header promises not to have. The seam
	# takes an instantiated world rather than a scene path precisely so this can
	# go on to build the scene it just measured.
	var terrain_sig := BakeRetention.signature_of_world(terrain, world)
	# AND THE VEGETATION'S, which this used to refuse to answer. The objection was
	# that the scatter's signature is over exports resolved in its `_ready` — and
	# it is not: `_ready` resolves the field and builds the multimeshes, and moves
	# no `@export` at all, which is all `BakeStore.exports_of` reads. The field is
	# prepared by the line above, which is the only part `_ready` would have
	# contributed. `TEST_bake_retention.gd` pins that by walking `_ready` for an
	# assignment to an exported name.
	var field: Object = world.get("field")
	var veg_sig := ""
	if scatter != null and field != null:
		veg_sig = String(veg.signature_of(field, scatter))

	_say("== %s ==" % _scene_path.get_file())
	_say("   terrain signature  %s" % terrain_sig)
	_emit({"kind": "signature", "store": "terrain", "value": terrain_sig,
			"scene": _scene_path, "dir": _dir})
	if veg_sig != "":
		_say("   veg signature      %s" % veg_sig)
		_emit({"kind": "signature", "store": "veg", "value": veg_sig,
				"scene": _scene_path, "dir": _dir})

	if _check_only:
		scene.free()
		return _report_check(terrain, veg, terrain_sig, veg_sig)

	# Recording ON before the scene enters the tree, so the very first chunk that
	# lands is kept with its arrays. See the header.
	terrain.record_arrays = true
	# AND THE DISK REFUSED, for the run that is about to write to it. Without this
	# a rebake finds the bake it is replacing — same world, same signature — opens
	# it, meshes nothing, and writes back a store whose entries it never had the
	# arrays for. See `BakeStore.open_with_disk`. Set on both stores rather than
	# only the terrain one that needs it, because a bake run should BUILD the
	# world; a run that copied a file from one name to the same name would be
	# reporting work it did not do.
	terrain.refuse_disk = true
	veg.refuse_disk = true

	var t0 := Time.get_ticks_msec()
	root.add_child(scene)
	current_scene = scene
	var ok := await _build(world, scatter)
	_say("   built in %.1f s" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	if not ok:
		_fail("tool_bake_world: the world did not finish building")
		scene.queue_free()
		return 2

	# Taken AFTER the build: `veg_scatter._ready` is what resolves the sprite
	# layout the scatter's signature is over, and it is also what opened the store
	# — so asking the store what it is holding is both simpler and harder to get
	# wrong than recomputing the signature here.
	var written := 0
	written += _write(terrain, terrain.STORE_NAME)
	if scatter != null:
		written += _write(veg, veg.STORE_NAME)
	scene.queue_free()
	await process_frame
	if written <= 0:
		_fail("tool_bake_world: nothing was written")
		return 2
	_say("\n   %d entries written to %s" % [written, _dir])
	_say("   the game will find them on its next cold start; run --check to confirm")
	return 0


# Wait for the terrain prewarm AND the vegetation prescatter, stepping the
# scatter the way a loading screen would so it builds at full width.
func _build(world: Node, scatter: Node) -> bool:
	_world_done = false
	world.connect("pregen_finished", _on_world_done)
	# The terrain half of the bar. `pregen_progress` is what the loading screen
	# reads, so this is the same number the game shows rather than a second guess
	# at it — and it is the ~85 s the bar used to sit still through, since the
	# planting below was the only stage that reported anything.
	world.connect("pregen_progress", _on_world_progress)
	_last_pct = -1
	var deadline := Time.get_ticks_msec() + int(_max_seconds * 1000.0)
	var last := -1
	while Time.get_ticks_msec() < deadline:
		if scatter != null and scatter.has_method("prefill_step"):
			scatter.call("prefill_step")
		await process_frame
		if not _world_done:
			continue
		if scatter == null or not scatter.has_method("prefill_ratio"):
			return true
		# `_prescattered` rather than the ratio, because the ratio goes back below
		# 1.0 the moment the prescatter finishes: a prescattered world falls
		# through to the ordinary scan, which recomputes `_todo` against what is in
		# VIEW. The flag is the one that means "every tile in the world is built".
		if bool(scatter.get("_prescattered")):
			return true
		var pct := int(float(scatter.call("prefill_ratio")) * 100.0)
		_progress("plants", pct)
		if pct >= last + 10:
			last = pct - pct % 10
			_say("   planting %d%%" % last)
	return false


func _on_world_progress(stage: String, done: int, total: int) -> void:
	if total > 0:
		_progress(stage, int(float(done) * 100.0 / float(total)))


## One line per whole percent, per stage. See `_last_pct`.
func _progress(stage: String, pct: int) -> void:
	pct = clampi(pct, 0, 100)
	if pct <= _last_pct:
		return
	_last_pct = pct
	_emit({"kind": "progress", "stage": stage, "pct": pct})


func _on_world_done() -> void:
	_world_done = true
	_say("   terrain done, planting")
	# Back to zero for the planting stage, which is a second bar and not a
	# continuation of the first.
	_last_pct = -1
	_emit({"kind": "stage", "name": "plants"})


func _write(store: Node, name: String) -> int:
	var sig := String(store.stats()["signature"])
	var held := int(store.stats()["held"])
	if held == 0:
		_say("   %s: nothing held, nothing written" % name)
		return 0
	var path := "%s/%s" % [_dir, store.file_name(name, sig)]
	var t0 := Time.get_ticks_msec()
	var n: int = store.save_to(path)
	if n < 0:
		return 0
	var size := 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	_say("   %s: %d entries, %.1f MB, %.1f s -> %s" % [
			name, n, float(size) / 1.0e6,
			float(Time.get_ticks_msec() - t0) / 1000.0, path])
	_emit({"kind": "wrote", "store": name, "entries": n, "bytes": size,
			"path": path, "ms": Time.get_ticks_msec() - t0})
	return n


# `--check`: is there a bake on disk for the world this scene describes RIGHT NOW?
#
# THE TERRAIN'S IS THE VERDICT, and the vegetation's is a note beside it. That is
# a judgement about what a check is FOR rather than about what is knowable — both
# signatures are exact now (see the block that takes them) — and the two go stale
# together in practice, since both hash `SCRIPT_island_field.gd`, which is the
# file that changes. A zone whose terrain is current and whose forest is not still
# loads in seconds and then plants; a zone with no terrain bake meshes for two
# and a half minutes.
# Those are not the same answer and the exit code belongs to the second.
#
# `tools/TOOL_bake_retention.gd` reports both as equals, because the question it
# is asking — is this build complete — has no such asymmetry in it.
func _report_check(terrain: Node, veg: Node, terrain_sig: String,
		veg_sig: String) -> int:
	var path: String = terrain.find_bake(terrain.STORE_NAME, terrain_sig)
	var vpath: String = "" if veg_sig == "" \
			else veg.find_bake(veg.STORE_NAME, veg_sig)
	if path == "":
		_emit({"kind": "check", "current": false, "path": "", "veg": vpath})
		_say("\n   NO CURRENT BAKE for this world.")
		_say("   Looked in: %s" % ", ".join(terrain.READ_DIRS))
		_say("   Run this tool without --check to make one.")
		return 1
	_emit({"kind": "check", "current": true, "path": path, "veg": vpath})
	_say("\n   CURRENT: %s" % path)
	if veg_sig == "":
		_say("   (this zone has no VegScatter, so there is no forest to bake)")
	elif vpath == "":
		_say("   (no CURRENT vegetation bake — the forest will be planted)")
	else:
		_say("   (and the forest: %s)" % vpath)
	return 0
