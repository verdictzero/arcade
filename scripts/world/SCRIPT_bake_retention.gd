class_name BakeRetention
extends RefCounted

# WHAT IS ON DISK, WHAT IT IS STILL FOR, AND WHAT SHOULD BECOME OF IT.
#
# `tools/TOOL_bake_world.gd` makes bakes and `BakeStore` reads them. Between
# those two there has never been anything that knows what the pile of files
# adds up to, and the pile grows on its own: a bake is named for the SIGNATURE
# of the world it holds, so every edit to the mesher or the field writes a new
# hundred-megabyte file beside the old one and nothing ever removes the old one.
# After a week of terrain work `user://bake` is most of a gigabyte, of which one
# file describes a world anybody can still load.
#
# That is one half. The other is that a SHIPPED build must read its world rather
# than generate it — two and a half minutes of meshing in front of a player is
# not a loading screen — and nothing today can answer "is every world this game ships
# actually in the build, and current". `BakeStore.READ_DIRS` has put
# `res://data/bake` first since the day it was written; nothing has ever put a
# file there.
#
# So this file answers four questions, and it is the ONLY thing that answers
# them:
#
#   what is here        `inventory` — both directories, every bake, its size
#   is it still a world `signatures_for_zone` — per zone, per store, right now
#   what is it for      `classify` — that inventory against those signatures
#   what should happen  `plan` — stage, sweep, or a gate failure
#
# NOTHING HERE DECIDES WHAT A SIGNATURE IS, which is the same promise the baker
# makes and for the same reason. `signatures_for_zone` stands the zone up exactly
# as far as `--check` does and asks `TerrainBake` and `VegBake` themselves. A
# librarian with its own opinion about which bakes match would be a second
# opinion about the island, and the first one is already load-bearing.
#
# See `docs/DOC_bake_retention.md`.

## The two stores a bake run writes, in the order a person reads them.
const STORES := ["terrain", "veg"]

## Where a bake may live, in `BakeStore.READ_DIRS` order: the shipped one first.
const SHIP_DIR := "res://data/bake"
const CACHE_DIR := "user://bake"
const DIRS := [SHIP_DIR, CACHE_DIR]

## Where the bakeable worlds live. The same three directories the World Baker
## dock walks, for the same reason — `island_0` is the game and sits at the top
## of `scenes/`, the lettered zones it was forked from are under `scenes/utility/`,
## and `scenes/test/` is walked so that the day something bakeable lands there it
## is not silently missing. `TEST_bake_retention.gd` asserts this list and the
## dock's are the same list.
const SCENE_DIRS := ["res://scenes", "res://scenes/utility", "res://scenes/test"]

const TERRAIN_SCRIPT := "res://scripts/autoload/AUTOLOAD_terrain_bake.gd"
const VEG_SCRIPT := "res://scripts/autoload/AUTOLOAD_veg_bake.gd"

## What a file is for. One of these is written onto every row `classify` returns.
const SHIPPED := "shipped"      ## in the build, current, for a zone that ships
const READY := "ready"          ## current for a ship zone, but only on this machine
const CACHED := "cached"        ## current for a zone kept but not shipped
const MIRRORED := "mirrored"    ## current for a ship zone, and already in the build
const UNCLAIMED := "unclaimed"  ## current for a zone the roster does not name
const DROPPED := "dropped"      ## current, but only for a zone the roster retired
const STALE := "stale"          ## describes no world any scene in this project builds
const SPARED := "spared"        ## stale, but within `keep_stale`
const FREIGHT := "freight"      ## in the build and has no business being there

## What should be done with it.
const KEEP := "keep"
const STAGE := "stage"
const SWEEP := "sweep"


# ================================================================= the files ==

## Split `terrain_1573686522.bake` into its store and its signature, or `{}`.
##
## FROM THE RIGHT, because a store name is allowed to hold an underscore and a
## signature is not: `BakeStore.signature_for` ends in `"%d" % acc.hash()`, and
## `String.hash` is a uint32, so the last underscore is always the separator.
## Splitting from the left would work today and break the day somebody adds a
## store called `golf_props`.
static func parse_name(file: String) -> Dictionary:
	if not file.ends_with(".bake"):
		return {}
	var stem := file.trim_suffix(".bake")
	var cut := stem.rfind("_")
	if cut <= 0 or cut >= stem.length() - 1:
		return {}
	var store := stem.substr(0, cut)
	var sig := stem.substr(cut + 1)
	if not sig.is_valid_int():
		return {}
	return {"store": store, "signature": sig}


## Every bake in `dirs`, newest first within each directory.
##
## Sorted by modification time because that is the order `keep_stale` counts in
## and the order a person scanning a list wants: the one you made this afternoon
## is the one you might still want.
static func inventory(dirs: Array = DIRS) -> Array:
	var out: Array = []
	for d in dirs:
		if not DirAccess.dir_exists_absolute(String(d)):
			continue
		for f in DirAccess.get_files_at(String(d)):
			var parsed := parse_name(String(f))
			if parsed.is_empty():
				continue
			var path := "%s/%s" % [String(d), String(f)]
			out.append({
				"dir": String(d),
				"file": String(f),
				"path": path,
				"store": String(parsed["store"]),
				"signature": String(parsed["signature"]),
				"bytes": _size_of(path),
				"modified": FileAccess.get_modified_time(path),
			})
	out.sort_custom(func(a, b):
		if a["dir"] != b["dir"]:
			return dirs.find(a["dir"]) < dirs.find(b["dir"])
		if a["modified"] != b["modified"]:
			return a["modified"] > b["modified"]
		return a["file"] < b["file"])
	return out


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


# ================================================================= the zones ==

## Every scene carrying an `IslandWorld`, which is what a bake can be OF.
##
## READ AS TEXT rather than loaded, because this is asked for every scene in the
## project and loading `SCENE_island_0.tscn` to find out whether it is bakeable
## costs most of a second and every resource it references. The same test the
## World Baker dock uses, and the tool refuses anything that fails it, so the
## three agree by construction.
static func zones_in(dirs: Array = SCENE_DIRS) -> PackedStringArray:
	var out: PackedStringArray = []
	for d in dirs:
		if not DirAccess.dir_exists_absolute(String(d)):
			continue
		for f in DirAccess.get_files_at(String(d)):
			if not String(f).ends_with(".tscn"):
				continue
			var path := "%s/%s" % [String(d), String(f)]
			if FileAccess.get_file_as_string(path).find('name="IslandWorld"') < 0:
				continue
			out.append(path)
	out.sort()
	return out


## What this zone's bakes would be called if you baked it right now.
##
## Returns `{"terrain": sig, "veg": sig}` — `veg` empty when the scene carries no
## `VegScatter` — or `{"error": why}`.
##
## `terrain` and `veg` are anything answering `signature_of` — the running
## autoloads when there are any, and otherwise the two `AUTOLOAD_*_bake.gd`
## scripts themselves, since `signature_of` is `static` on both. That second way
## in is what makes this answerable from a process with no autoloads at all.
##
## THE SCENE IS INSTANTIATED AND NOT ENTERED, which is the whole trick and is
## exactly what `TOOL_bake_world.gd --check` does: both signatures are a function
## of settings and source files, so they are knowable without meshing a chunk or
## planting a fern. The field has to be `prepare`d first because its noises are
## built there and they are part of what is hashed.
##
## THE VEGETATION'S IS TAKEN TOO, which `--check` has never done. Its objection
## was that the scatter's signature is over exports resolved in `_ready` — and
## that turns out to be half true in the direction that matters: `_ready` resolves
## the FIELD and the multimeshes, and assigns not one `@export`. `exports_of`
## walks only what the script declares as `@export`, and those are set from the
## `.tscn` at instantiation. `TEST_bake_retention.gd` pins that by walking
## `_ready` for an assignment to any exported name, so the day one appears this
## claim fails out loud instead of quietly reporting a stale forest as current.
static func signatures_for_zone(scene_path: String, terrain: Object,
		veg: Object) -> Dictionary:
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return {"error": "%s did not load" % scene_path}
	var scene := packed.instantiate()
	if scene == null:
		return {"error": "%s did not instantiate" % scene_path}
	var world := scene.get_node_or_null("IslandWorld")
	if world == null:
		scene.free()
		return {"error": "%s carries no IslandWorld" % scene_path}
	var out := {"terrain": "", "veg": ""}
	var field: Object = world.get("field")
	out["terrain"] = signature_of_world(terrain, world)
	var scatter := scene.get_node_or_null("VegScatter")
	if scatter != null and field != null:
		out["veg"] = String(veg.signature_of(field, scatter))
	scene.free()
	return out


## The terrain signature of an already-instantiated zone.
##
## THE ONE PLACE THIS IS DERIVED. `TOOL_bake_world.gd` calls it too, on the scene
## it is about to build, rather than spelling the same two lines out beside a
## comment promising they match. The seam is "a world node" rather than "a scene
## path" precisely so the baker can share it: it has already instantiated the
## scene and is going to keep it.
static func signature_of_world(terrain: Object, world: Node) -> String:
	var field: Object = world.get("field")
	if field != null and not field._ready:
		field.prepare()
	return String(terrain.signature_of([field, {
			"chunk_size": float(world.get("chunk_size"))}]))


# =============================================================== the verdict ==

## Every row of `inv`, told what it is for and what should happen to it.
##
## `current` maps a signature to the zones it is the CURRENT signature of — one
## signature can belong to several zones, since two scenes wiring up the same
## field and the same chunk size describe the same terrain and rightly share a
## bake. Built by `current_signatures`.
static func classify(inv: Array, current: Dictionary, roster: BakeRoster,
		ship_dir: String = SHIP_DIR, cache_dir: String = CACHE_DIR) -> Array:
	var out: Array = []
	# Stale rows, in the order `keep_stale` spares them: newest first, per store.
	var stale_seen := {}
	# WHAT THE BUILD ALREADY HAS, taken in a pass of its own before anything is
	# judged. Without it a bake that has been staged reads as one that still needs
	# staging — the cache copy is still current and still for a ship zone, and
	# nothing in the row itself says its twin is sitting in the build directory.
	# The visible cost was a plan that said "stage 2" over a complete build and a
	# `--stage` that re-copied a hundred megabytes on every run.
	var in_build := {}
	for row in inv:
		if String(row["dir"]) == ship_dir:
			in_build["%s|%s" % [row["store"], row["signature"]]] = true
	for row in inv:
		var r: Dictionary = (row as Dictionary).duplicate()
		var claims: Array = current.get(r["signature"], [])
		var ships := false
		var keeps := false
		var drops := false
		for z in claims:
			var policy := roster.policy_for(String(z))
			ships = ships or policy == BakeRoster.SHIP
			keeps = keeps or policy == BakeRoster.CACHE
			drops = drops or policy == BakeRoster.DROP
		r["zones"] = claims
		if claims.is_empty():
			var store := String(r["store"])
			var n := int(stale_seen.get(store, 0))
			stale_seen[store] = n + 1
			# A stale bake in the BUILD directory is never spared. `keep_stale` is
			# for going back to yesterday's terrain on your own machine; a hundred
			# megabytes of a world nothing can load has no version of itself that
			# belongs in an APK.
			var spare: bool = n < maxi(roster.keep_stale, 0) \
					and String(r["dir"]) == cache_dir
			r["verdict"] = SPARED if spare else STALE
			r["action"] = KEEP if spare else SWEEP
		elif String(r["dir"]) == ship_dir:
			# It is in the build. The only excuse for that is a zone that ships.
			r["verdict"] = SHIPPED if ships else FREIGHT
			r["action"] = KEEP if ships else SWEEP
		elif ships:
			# STAGING COPIES RATHER THAN MOVES, so this row survives it. That is
			# deliberate: `res://data/bake` is gitignored and disposable — a
			# `git clean` takes it — and the copy here is the master a re-stage
			# comes from. Two copies of a chosen world is the price of the build
			# directory being a staging area rather than a home.
			var staged: bool = in_build.has("%s|%s" % [r["store"], r["signature"]])
			r["verdict"] = MIRRORED if staged else READY
			r["action"] = KEEP if staged else STAGE
		elif keeps:
			r["verdict"] = CACHED
			r["action"] = KEEP
		elif drops:
			# ONLY WHEN NOBODY ELSE WANTS IT. `ships` and `keeps` are both false
			# here, so every zone this bake belongs to has been retired — which is
			# the only circumstance under which retiring one is allowed to delete
			# anything. See `BakeRoster.DROP`.
			r["verdict"] = DROPPED
			r["action"] = SWEEP
		else:
			r["verdict"] = UNCLAIMED
			r["action"] = KEEP
		out.append(r)
	return out


## `signature -> [zone, ...]`, from a `zone -> {"terrain":.., "veg":..}` map.
static func current_signatures(per_zone: Dictionary) -> Dictionary:
	var out := {}
	for zone in per_zone.keys():
		var sigs: Dictionary = per_zone[zone]
		for store in STORES:
			var s := String(sigs.get(store, ""))
			if s == "":
				continue
			if not out.has(s):
				out[s] = []
			if not (out[s] as Array).has(zone):
				(out[s] as Array).append(zone)
	return out


## What to do, and what is wrong.
##
## `missing` is the gate: one row per (ship zone, store) whose bake is not in the
## build directory. `stageable` on a row says the file exists on this machine and
## a `--stage` would fix it; without it somebody has to run the baker.
##
## A SHIP ZONE THAT IS NOT IN `per_zone` FAILS rather than being skipped. It is
## usually a renamed scene, and the other way round — a roster key nobody can
## resolve quietly dropping out of the gate — is a zone that stops being shipped
## without anybody deciding to stop shipping it.
static func plan(rows: Array, per_zone: Dictionary, roster: BakeRoster,
		ship_dir: String = SHIP_DIR) -> Dictionary:
	var stage: Array = []
	var sweep: Array = []
	var bytes_swept := 0
	for row in rows:
		match String(row["action"]):
			STAGE: stage.append(row)
			SWEEP:
				sweep.append(row)
				bytes_swept += int(row["bytes"])
	# What is already in the build, so `missing` can tell absent from unstaged.
	var shipped := {}
	var on_hand := {}
	for row in rows:
		var k := "%s|%s" % [row["store"], row["signature"]]
		if String(row["dir"]) == ship_dir:
			shipped[k] = true
		else:
			on_hand[k] = true
	var missing: Array = []
	for zone in roster.ship_zones():
		if not per_zone.has(zone):
			missing.append({"zone": zone, "store": "", "signature": "",
					"stageable": false, "why": "not a bakeable zone"})
			continue
		var sigs: Dictionary = per_zone[zone]
		if sigs.has("error"):
			missing.append({"zone": zone, "store": "", "signature": "",
					"stageable": false, "why": String(sigs["error"])})
			continue
		for store in STORES:
			var sig := String(sigs.get(store, ""))
			if sig == "":
				# No VegScatter in the scene: there is no vegetation bake to want.
				continue
			var k := "%s|%s" % [store, sig]
			if shipped.has(k):
				continue
			missing.append({"zone": zone, "store": store, "signature": sig,
					"stageable": on_hand.has(k),
					"why": "on this machine, not in the build" if on_hand.has(k)
							else "not baked"})
	return {"stage": stage, "sweep": sweep, "missing": missing,
			"bytes_swept": bytes_swept}


## Bytes per directory, and how many of them the plan would give back.
static func disk_summary(rows: Array) -> Dictionary:
	var per_dir := {}
	var reclaimable := 0
	var total := 0
	for row in rows:
		var d := String(row["dir"])
		per_dir[d] = int(per_dir.get(d, 0)) + int(row["bytes"])
		total += int(row["bytes"])
		if String(row["action"]) == SWEEP:
			reclaimable += int(row["bytes"])
	return {"per_dir": per_dir, "total": total, "reclaimable": reclaimable}


# ================================================================== the acts ==

## Copy a bake into the build directory, beside whatever is already there.
##
## THROUGH A `.part` AND A RENAME, the same discipline `BakeStore.save_to` uses
## and for the same reason: a hundred megabytes takes long enough to copy that a
## full disk or a killed process in the middle of it is a real event, and the
## file at the destination should be the old bake or the new one and never half
## of either. Returns "" on success or the reason it failed.
static func stage_file(path: String, to_dir: String = SHIP_DIR) -> String:
	if not FileAccess.file_exists(path):
		return "%s is not there" % path
	if not DirAccess.dir_exists_absolute(to_dir):
		var mk := DirAccess.make_dir_recursive_absolute(to_dir)
		if mk != OK:
			return "could not make %s (%d)" % [to_dir, mk]
	var dest := "%s/%s" % [to_dir, path.get_file()]
	var part := "%s.part" % dest
	var err := DirAccess.copy_absolute(path, part)
	if err != OK:
		DirAccess.remove_absolute(part)
		return "could not copy %s (%d)" % [path, err]
	if _size_of(part) != _size_of(path):
		DirAccess.remove_absolute(part)
		return "%s copied short" % path
	err = DirAccess.rename_absolute(part, dest)
	if err != OK:
		DirAccess.remove_absolute(part)
		return "could not put %s in place (%d)" % [dest, err]
	return ""


## Delete one bake. Returns "" on success or the reason it failed.
##
## REFUSES ANYTHING THAT IS NOT A BAKE, by name, in one of the two directories
## this file knows about. The sweep is the only destructive thing here and it is
## driven by a plan built from a directory listing — so the check is cheap,
## belongs at the point of the deletion rather than at the point of the decision,
## and closes the gap between them.
static func sweep_file(path: String, dirs: Array = DIRS) -> String:
	if parse_name(path.get_file()).is_empty():
		return "%s is not a bake" % path
	if not dirs.has(path.get_base_dir()):
		return "%s is not in a bake directory" % path
	if not FileAccess.file_exists(path):
		return "%s is not there" % path
	var err := DirAccess.remove_absolute(path)
	return "" if err == OK else "could not remove %s (%d)" % [path, err]


## `104857600` -> `"104.9 MB"`. One place, so every readout agrees.
static func mb(bytes: int) -> String:
	if bytes < 1000:
		return "%d B" % bytes
	if bytes < 1000000:
		return "%.1f kB" % (float(bytes) / 1.0e3)
	return "%.1f MB" % (float(bytes) / 1.0e6)
