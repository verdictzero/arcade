class_name BakeRoster
extends Resource

# WHICH WORLDS THIS GAME HAS CHOSEN, AND WHAT IS TO BECOME OF THEIR BAKES.
#
# `tools/TOOL_bake_world.gd` can pre-generate any zone that carries an
# `IslandWorld`, and `BakeStore` will read one back from either of two
# directories. Neither of them has an opinion about WHICH zones matter. That was
# fine while a bake was a developer's local accelerator — you baked the thing you
# were working on, and the hundred megabytes it cost was your own business.
#
# It stops being fine the moment a build ships. A shipped game must not generate
# its world in front of a player: `SCENE_island_0` measures 144.8 s of meshing
# on the reference container, and two and a half minutes behind a progress bar is
# a fault report, not a loading screen. So somebody has to write down
# which zones are the game's, and that is this file.
#
# IT IS A LIST OF DECISIONS, NOT A CACHE POLICY. Every entry here is a sentence
# somebody meant: "island_0 is the game and must never generate on a player's
# machine", "W2 is where I work, keep its bake but do not ship it". Nothing
# derives these and nothing should — a roster a tool could compute would be a
# roster that changes when you are not looking, which is the opposite of what
# "chosen" means.
#
# See `SCRIPT_bake_retention.gd` for what is done WITH it, and
# `docs/DOC_bake_retention.md` for the whole argument.

## Where the game's roster lives. A single path rather than a picker: there is one
## answer to "what does this game ship", and a project with two rosters has
## already lost the argument this file exists to settle.
const PATH := "res://data/BAKEROSTER_shipping.tres"

## MUST be present and current in the ship directory, or the build is wrong.
const SHIP := "ship"
## Worth keeping on this machine, never worth putting in a build. The zones you
## develop against.
const CACHE := "cache"
## DEPRECATED. The zone is still in the tree — something may still open it — but
## nobody is working on it and its bakes are not worth the disk.
##
## THE ONLY POLICY THAT DELETES SOMETHING THAT STILL WORKS, so it is the only one
## that has to be typed on purpose, and it loses every argument: a bake claimed by
## a `drop` zone AND by a `ship` or `cache` zone is KEPT. Two scenes that wire up
## the same field and the same chunk size describe the same terrain and share one
## bake — `SCENE_test_zone_W2` and `SCENE_island_0` do exactly that today — so a
## rule that swept on a single dropped claim would delete the shipping game's
## terrain because its ancestor was retired.
##
## Leaving a zone OUT of the roster entirely is the other way to stop caring about
## it, and it is the quiet one: an unlisted zone's bakes are reported and left
## alone forever. `drop` is for when you want the disk back.
const DROP := "drop"
## Every policy there is, in the order they are listed to a person.
const POLICIES := [SHIP, CACHE, DROP]

## `res://...tscn` -> one of `POLICIES`.
##
## KEYED ON THE SCENE, not on a zone name or a signature. The scene is what the
## baker bakes, what the tool takes as `--scene=`, and the only name for a world
## that survives a re-tune: a signature changes every time you touch the mesher,
## and a zone letter is prose. A key that names a scene which no longer exists is
## reported rather than ignored — a roster quietly pointing at a deleted file is
## how a zone stops being shipped without anybody deciding to stop shipping it.
@export var zones: Dictionary = {}

## How many STALE bakes to spare, per store, newest first.
##
## Zero by default, and the default is the argument: a stale bake is a hundred
## megabytes that no longer describes any world anybody can load, and it is
## reproducible by pressing Bake. Keeping one is for the case where you are
## bisecting a terrain change and want last version's world back without a
## five-minute wait — a real case, and not the common one.
##
## Counted per store ("terrain", "veg") rather than overall, so sparing one does
## not spare two terrains and no vegetation, which would spare nothing usable.
@export var keep_stale := 0

## Bakes for zones this roster does not name are never swept, only reported.
##
## THE SAFE DIRECTION, and deliberately not configurable. A stale bake is dead by
## definition — no scene in the project describes the world it holds — so deleting
## it cannot lose anything that is not reproducible. A bake that is CURRENT for a
## zone nobody listed is a live world somebody built on purpose and forgot to
## write down, and an afternoon of meshing is not a thing a housekeeping button
## should be allowed to decide about.
const SWEEPS_UNCLAIMED := false


## The roster at `PATH`, or an empty one when there is none.
##
## NEVER NULL, because every caller would otherwise have to decide what an absent
## roster means, and they would not all decide the same thing. An empty roster
## says "nothing is chosen", which makes the gate pass vacuously and the sweep
## touch only what is stale — the behaviour a project that has not adopted any of
## this should get.
static func load_default() -> BakeRoster:
	if ResourceLoader.exists(PATH):
		var r := ResourceLoader.load(PATH) as BakeRoster
		if r != null:
			return r
	return BakeRoster.new()


## What was decided about this scene, or "" when nothing was.
func policy_for(scene: String) -> String:
	var p := String(zones.get(scene, ""))
	return p if POLICIES.has(p) else ""


## Every scene named here, in a stable order so two runs print the same list.
func listed() -> PackedStringArray:
	var out: PackedStringArray = []
	for k in zones.keys():
		out.append(String(k))
	out.sort()
	return out


## The scenes that must be in a build.
func ship_zones() -> PackedStringArray:
	return _zones_with(SHIP)


## The scenes whose bakes are not worth keeping.
func drop_zones() -> PackedStringArray:
	return _zones_with(DROP)


func _zones_with(policy: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for s in listed():
		if policy_for(s) == policy:
			out.append(s)
	return out


## Roster entries pointing at a scene that is not there any more.
##
## Reported rather than pruned. A missing scene is usually a rename, and a rename
## wants a person to retype the key, not a tool to quietly drop the line and leave
## the game shipping one zone fewer than it was yesterday.
func dangling() -> PackedStringArray:
	var out: PackedStringArray = []
	for s in listed():
		if not ResourceLoader.exists(s):
			out.append(s)
	return out
