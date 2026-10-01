# Island world — handoff

State of the procedural island world as merged to `main` (`cb94e9d`). This is the
"what to know before you touch it" document; `docs/DOC_procedural_island_world.md`
is the design doc and explains *why* each mechanism is shaped the way it is.
Read this one first, that one when you need to change something.

Since the first handoff the world has gained labelled golf holes, buildable
flats, a lattice of recurring hub islands, double-sided terrain and working
frustum culling on chunk surfaces. The golf zone system is the large one — see
"Golf zones" in the design doc before changing any `zone_*` parameter.

Most recently the atmosphere was rebuilt: the void fog is genuinely thick now
(the old one could not saturate — see the cheat sheet's haze row), the
Environment carries a second, *height* fog because the terrain shader's fog
cannot bury anything it is not painting, and there are two Hexen-style 2D cloud
decks. That work is verified by screenshot rather than by argument; see "What has
and has not been verified".

## Where it is

- Scene: `scenes/utility/SCENE_test_zone_W.tscn`. **Not** the main scene — the project
  still boots to `SCENE_title` (the title screen). Open W directly, or
  change `run/main_scene` while working on it.
- Code: `scripts/world/` (four files — `SCRIPT_island_field.gd`, `SCRIPT_chunk_mesher.gd`,
  `SCRIPT_island_world.gd`, `SCRIPT_cloud_planes.gd`), `shaders/SHADER_terrain_splat.gdshader`,
  `shaders/SHADER_sky_void_gradient.gdshader`, `shaders/SHADER_cloud_plane.gdshader`.
- Atmosphere that is **not** in a script: the Environment's height fog lives on
  the `Environment` sub-resource inside `SCENE_test_zone_W.tscn` itself, and the
  deck altitudes live on that scene's `CloudPlanes` node. Grep for `fog_height`
  if you cannot find where the fog under the cliffs is coming from. Rationale for
  those values is in the design doc, deliberately not in the scene file —
  comments in a `.tscn` are discarded the next time the editor saves it.
- Tuning: `data/ISLANDFIELD_default.tres`. **This is the file to edit.** Almost
  every world parameter lives here and is documented at its declaration in
  `scripts/world/SCRIPT_island_field.gd`.
- The old system (`scripts/SCRIPT_infinite_islands.gd`, `scripts/SCRIPT_procedural_island.gd`,
  `SCENE_test_zone_C.tscn`) is untouched and still works. Retiring it is an open
  decision, not an oversight.

## How to verify a change

```
godot --headless --path . --import                          # fresh checkout only
godot --headless --path . --script res://tests/TEST_island_world.gd
godot --headless --path . --script res://tests/TEST_scatter_tiles.gd
godot --headless --path . --script res://tests/TEST_prescatter.gd
godot --headless --path . --script res://tests/TEST_handheld_controls.gd
```

The last one is here because `SCENE_island_0` is the game the shipping build
offers — the debug picker's `SHIPPED` list narrows to it and to the ruin
dungeon's test scene, nothing else — so anything that breaks this island breaks
the handheld build outright. It also pins the pad
schema and the fixed 720p viewport; see `docs/DOC_handheld_controls.md`.

The two before it cover the vegetation; see "Vegetation is built up front" below.
There are six probes alongside them that assert nothing and are the fastest way
to answer "how much is there" and "what is it costing":

```
tests/PROBE_veg_census.gd      how many trees and tufts the field describes
tests/PROBE_scatter_cost.gd    what a scan costs, and how often one fires
tests/PROBE_scatter_threads.gd how tile meshing scales across the worker pool
tests/PROBE_sand_profile.gd    a bunker in cross-section: depth, lip, wall angle
tests/PROBE_zone_skirt.gd      the slope and the drop as you walk off a fairway
tests/PROBE_rock_veg.gd        where vegetation stops vs where rock starts
```

The last two take `--skirt=N` and `--samples=N`, and both print the world with
the change and without it side by side, so the difference is measured rather than
described. See "The ground around a hole" below.

**Run `--import` first on a fresh checkout**, or the test dies in a heap of
`Could not find type "IslandField"` parse errors. `.godot/` is gitignored, and
`class_name` registration lives in it — so with no import cache every
`class_name` in the project is invisible and the failure looks like the script
is broken rather than the cache being absent. The import also has to *finish*;
killing it partway leaves textures unimported and anything that loads a material
fails instead.

Verified against **Godot 4.7.stable** (`config/features` pins 4.7).

Exits non-zero on failure. It runs against `data/ISLANDFIELD_default.tres` — the
preset that actually ships — not against the script defaults. It is not a
formality; it covers twelve things that fail silently and invisibly:

1. **Seam continuity.** The contour is stitched by float equality; the failure
   mode is a hairline crack you cannot find by reading code.
2. **LOD grid nesting.** If this breaks, the skirts stop covering LOD joins.
3. **Coastal classification.** If a chunk holding coastline is misclassified as
   inland, it floats its LOD and tears a slit down the cliff face.
4. **Splat stability across LODs.** Regression guard for a bug where distant
   terrain reclassified its surfaces and turned grey.
5. **Island disjointness + hub clearance.** If islands overlap, the mesh tears.
   Now checked against the *nearest* hub, since hubs recur.
6. **Zone disjointness and inland margin.** Overlapping zones make "which hole am
   I on" ambiguous; a zone reaching the shore ramp is a fairway tilted toward the
   sea. Both are geometry bugs you would have to fly out and notice.
7. **Flat where it should be, hilly where it should not.** Asserts golf zones and
   build pads are markedly flatter than the ground around them *and* that real
   relief survives between them — a `zone_separation` set too tight silently
   deletes the hills rather than erroring.
8. **Hole identity.** The same seed, a fresh field and a worker clone must all
   lay out the identical course. This is the whole basis for storing nothing.
9. **The fog band**, read out of `MAT_terrain_splat.tres` and checked against
   `cliff_cutoff_y` and `vertical_spread`, so the numbers that decide whether a
   cliff bottom dissolves cannot drift apart across two files unnoticed. Also
   that every fog uniform the material sets actually exists on the shader, and
   that **fogged fragments kill their specular** — the one-line omission that
   made "fully fogged" rock render a whole palette entry brighter than the sky
   behind it, and defeated every previous attempt to thicken the fog.
10. **Culling bounds.** Asserts a chunk's surface AABB stays inside its own
    footprint and is dramatically smaller than the merged one. Re-merging the
    cliff's bounds into the surface mesh is an easy accident and costs you
    frustum culling on every coastal chunk with no visible symptom.
11. **Double-sidedness, and no second normal flip.** The shell is
    `cull_disabled`, and under that the engine already turns NORMAL toward the
    viewer on a back face, so the shader must not flip it again on
    `!FRONT_FACING` (it did, and lit every back face as its own front). The test
    asserts `cull_disabled` and reads the code, not the comments, for the flip.
12. **The cloud decks and the Environment's height fog**, which live in
    `SCENE_test_zone_W.tscn` rather than in any script or preset — the fog is on
    an `Environment` sub-resource and the altitudes are on the `CloudPlanes`
    node, so nothing else would notice them drifting. Covers the coupling that is
    easiest to get wrong: `sea_altitude` has to stay **above** the altitude where
    the fog ramp already saturates (y = −262 as shipped, rederived by the test
    from `fog_curve` and `fog_opacity_gain`, so it tracks them), not merely below
    `fog_top`. Also that `fog_height` matches `fog_top`, that the three tinting
    fog terms are 0, and that every grey in both deck materials is an exact
    neutral. Set the deck back to the script's `-300` default and the suite fails.

If you change any *_radius, *_spacing, `coast_irregularity`, `cliff_cutoff_y`,
`hub_lattice`, any `zone_*` parameter or the fog band, run it. Those are the
coupled ones.

## What has and has not been verified

Verified headless:

- Full project imports from a clean `.godot/` with no script or parse errors.
- All tests pass.
- **Rendered and looked at**, under `xvfb-run` with `--rendering-driver opengl3`,
  i.e. software GL (llvmpipe). Orthographic top-downs of a hub and a satellite,
  a low-angle fog check, and a view up at an island's underside. What those
  actually confirmed, beyond the assertions:
  - the nine fairways and six build pads read as distinct groomed ground from
    above, and bunkers sit inside fairways rather than scattered over the island;
  - satellites carry a build pad and no golf, as intended;
  - cliff bottoms are swallowed by the fog band rather than terminating;
  - undersides render solid rather than see-through, which is the case
    `cull_disabled` exists for. (These renders predate the removal of the second
    back-face flip; since then a back face is lit from the side it is seen
    from.)

Verified by **screenshot**, via `tests/RENDER_island_shots.gd` — 7 named
viewpoints, the real WorldEnvironment, the real terrain material and the real
palette-LUT post pass, each shot held until the chunk count stops moving. This
is the atmosphere test, and it exists because every previous round of fog tuning
was argued from numbers in a `.tres` and from renders of a world that had not
finished streaming. What the current shots establish:

- **The `deep_below` shot is the one that matters** (y = -520, looking up at the
  undersides — the user's complaint measured directly). At baseline every cliff
  column was traceable all the way down. Now **61.7% of the frame is exactly
  `(17, 17, 17)`**: the fogged cliffs and the sky are the *same pixel*, so the
  silhouette is gone rather than merely dimmed. Frame stddev 0.208 → 0.097.
- Both decks read as surfaces rather than as sheets, and the `horizon` shot —
  ceiling above, sea below, islands as dark silhouettes between — is the shot
  that shows the whole design working at once.
- **No palette step was introduced.** Every grey in the fog, sky and cloud
  colours resolves to an exact neutral entry. The ~1% of non-neutral pixels in a
  frame are lit terrain albedo on unfogged island tops, which predates this work.

**The cloud decks are fill-rate bound, and the 2x render scale is the multiplier
that matters.** Measured with `tests/PERF_cloud_decks.gd`, which draws each frame
with the decks hidden and then shown and subtracts, at a settled 575-chunk world
(llvmpipe — read the ratios, not the milliseconds):

| viewpoint | scale | decks off | decks on | delta | ratio |
| --- | --- | --- | --- | --- | --- |
| `horizon` (both decks, half-screen each) | 1.0 | 709 ms | 735 ms | +25 ms | 1.04 |
| `look_up` (one deck, full screen) | 1.0 | 242 ms | 259 ms | +17 ms | 1.07 |
| `hub_low` (terrain occludes most of the sea) | 1.0 | 633 ms | 649 ms | +17 ms | 1.03 |
| `horizon` | **2.0** | 1603 ms | 1660 ms | +58 ms | 1.04 |
| `look_up` | **2.0** | 398 ms | 530 ms | **+132 ms** | **1.33** |
| `hub_low` | **2.0** | 1293 ms | 1378 ms | +85 ms | 1.07 |

Two things to take from it. First, **when terrain fills the frame the decks are
noise** (+3–7%) — the depth test throws away most deck fragments before they
blend, so the expensive case is not the busy one. Second, **the case that costs
is looking at sky**: one full-screen deck with nothing occluding it is +33% at 2x
scale, and the delta grows ~8x for 4x the pixels, which is the signature of a
fill/bandwidth limit rather than a shading one. That is the risk worth carrying
to the Pi, and if it bites, the lever is `scaling_3d/scale` or the fade radii —
not deleting a deck, which is cheap exactly when you can see the ground.

**Not verified at all.** Treat these as unknowns, not as working:

- **Real GPU performance on the target device.** Everything measured so far is
  llvmpipe under `xvfb` — a software rasteriser on the CPU, not a Broadcom V3D.
  The deck cost *ratio* transfers as an indication; the milliseconds do not. The
  hub is ~400 chunks and the renderer is `gl_compatibility` at 2x render scale.
  This is still the single biggest open risk, and
  `tests/PERF_cloud_decks.gd` is written so the same command works on the Pi.
- **Collision has never been touched by a physics body.** It is generated and the
  shapes are built, but no ball, player or aircraft has ever collided with it.
- **The floating-origin rebase has never fired.** Threshold is 8000 m and nothing
  in testing flew that far. `apply_origin_shift` is written and reviewed but
  unexercised — on `SCRIPT_island_world.gd` and now on `SCRIPT_cloud_planes.gd` too. Both use
  the same convention (`logical = render + _origin_offset`, `_origin_offset -=
  shift`) and the cloud deck's world-anchored UVs cancel correctly against it on
  paper, but no rebase has ever happened to prove it. Flying 8 km out and
  watching for the sky to reshuffle is the cheapest possible test of this and has
  not been done.
- **LOD transitions in motion.** Renders used near-static cameras, so LOD
  hysteresis and the swap-in path have not been watched while moving.
- **Sustained threading.** Worker meshing ran, but not for long enough to shake
  out a rare race.
- **Nobody has stood on a golf zone.** The holes are generated, labelled and
  provably flat, but no camera has been down at player height on a fairway. How
  the zone bank reads from the ground, and whether `green_undulation` at 0.55 m
  is enough for a putt to break, are both untested by eye.
- **Frustum culling was fixed by measuring AABBs, not by counting draw calls.**
  The bounds are demonstrably chunk-sized now; that the renderer's visible-object
  count actually drops has not been observed.

## Vegetation is built up front

The vegetation is no longer streamed. `VegScatter.prescatter` is on in W2, so every
tile of the island is meshed behind the loading screen and kept, and nothing is
meshed, pruned or re-meshed for the rest of the session. The ground cover still
streams, and the section ends with why that asymmetry is right rather than an
oversight.

### The numbers this was decided on

All from `tests/PROBE_veg_census.gd` against `data/ISLANDFIELD_hub_solid.tres`,
whose island is 1,525 m across including the coast wobble:

|        | grid | count over the island | instance buffers | candidate cells |
|--------|------|-----------------------|------------------|-----------------|
| trees  | 11 m | 6,237                 | 0.9 MB           | 61,260          |
| tufts  | 1 m  | 2,771,146             | 169 MB           | 7,438,592       |

`IslandField.sample()` costs ~0.15 ms, and that sample is the entire cost of
placing anything. So the forest is ten seconds of arithmetic and the ground cover
is twenty-five minutes of it. That is the whole decision: one of them fits behind
a loading screen and the other does not, by three orders of magnitude.

### What it was costing before

`tests/PROBE_scatter_cost.gd`, standing in filled-in rough with every tile the
camera can see already meshed — i.e. with nothing whatever left to build:

```
grass  2.07 ms per scan, re-run every  2 m of travel
trees  3.33 ms per scan, re-run every  6 m of travel   (worst single scan 19.6 ms)
                                        -> 5.4 ms per scan, 10.8% of a 60 fps frame
```

Half of that was re-packing instance buffers whose contents had not moved and
handing them to the GPU again; the other half was re-walking the tile box to reach
the same conclusion as last time. A 19.6 ms scan is a dropped frame on its own.

### The two changes

1. **A scan is quantised to a SCAN CELL.** The eye is snapped to a lattice and
   every distance is measured from that cell's *box* rather than from the eye
   point, so a scan's whole output is a function of the cell — and a scan whose
   cell has not changed is skipped outright instead of recomputed. The cost is a
   slightly wider emitted set (tiles within view of anywhere in the cell), and
   everything extra it admits has already been faded out by the material drawing
   it. `scan_cell` is the dial: scans get `scan_cell / old move gate` rarer, and
   the sets widen by about `scan_cell` metres at each edge. **0 disables the
   lattice**, which is what `RENDER_island_flyover.gd` wants so its stills are
   exact.

2. **The whole island's vegetation is prescattered, and then stops being a
   stream at all.** Every tile in the world is built behind the loading screen
   and kept, so nothing is ever meshed, probed, pruned or re-meshed again and a
   scan from the far side of the island dispatches no work.

   It is *not* frozen, and that changed: each of the three classes now carries
   its own material and its own far fade, and a scan selects each class's tiles
   against its own `far_end` — firs to 1300 m, bushes to 820, ferns to 300. Held
   and drawn are different numbers now (`total_plant_count()` vs
   `live_plant_count()`): the island **holds 482,500 plants and submits 122,208**
   of them from its centre, 965k triangles down to 244k in the same nine draw
   calls. Almost all of the gap is ferns — they are two thirds of the world's
   plants and were being submitted from a kilometre away to be drawn a pixel and
   a half tall. `_fill` fingerprints its per-class selection, so a scan that moved
   no tile across a band uploads nothing.

Also, both `_evaluate_cell`s now test the density roll's **ceiling** before
touching the field. The roll is a lerp between two densities scaled by factors
that are each at most 1, so a cell failing against the larger density fails
whatever the ground turns out to be — exactly equivalent, same trees and tufts
out, and it skips the sample for 29% of tree cells and 15% of grass cells.

Result, measured the same way:

```
grass  1.95 ms per scan, every  8 m      trees  0.32 ms per scan, every 44 m
                                                (worst single scan 0.38 ms)
```

Those tree figures are from before the three plant classes moved onto one 4 m
grid. `PROBE_scatter_cost.gd` on the shipped scene now reads **trees 4.12 ms per
scan, worst 7.81 ms** — a prescattered island keeps all 1,020 tiles resident, so
every scan walks the whole box and `_fill` re-selects three classes across it
whether or not anything moved. It is still only 2.5% of one core at 120 m/s
because the scan cell makes it rare, but a single 7.8 ms scan is a dropped frame
and the number no longer resembles what is written above. Left as-is here because
it is the honest before/after of the change it documents; treat 4.12 ms as the
figure to beat.

```
cost of a second of movement:   6 m/s   9.5 -> 1.5 ms      (6.4x)
                               30 m/s  47.7 -> 7.5 ms      (6.4x)
                              120 m/s   108 -> 30.0 ms     (3.6x)
```

### Three things that will bite

- **`prescatter` is for a BOUNDED world only.** It enumerates every tile of every
  island in range; an endless field has no such number. W2 qualifies because
  `ISLANDFIELD_hub_solid.tres` is one hub in a void.
- **`scatter_timeout` on the loading screen is a deadlock guard, not a budget**,
  and it has to clear the longest legitimate scatter stage. W2 sets 180.
  `tests/TEST_prescatter.gd` prints the real figure every run, and
  `tests/PROBE_veg_timeline.gd` prints it against the terrain's, which is what
  the screen actually waits on now. Overrunning it is neither fatal nor expensive
  — see the next entry.
- **The prescatter was single-threaded, and the note that said otherwise was
  wrong.** `PROBE_scatter_threads.gd` used to report a flat wall time at every
  in-flight width and that was written up here as a GDScript scaling cliff:
  "does not scale past four workers, do not set it from the core count". It was
  not a cliff. Every tile was dispatched at LOW worker priority, and Godot caps
  concurrent low-priority tasks at `low_priority_thread_ratio` (0.3) of the pool
  — **one thread on a four-core box** — so widths 1 through 16 were all measuring
  the same single worker. The probe now takes `--priority=` and the two curves
  are nothing alike: 3.0 s at one lane against 1.7 s at three, same 48 tiles.

  So the prescatter runs on lanes off a shared cursor, exactly like
  `island_world`'s prewarm (`_pregen_staff_lanes`) — on threads of their own
  rather than on the pool, for the reason `SCRIPT_build_lanes.gd` gives — and
  `prescatter_in_flight` defaults to 0 = one per core less one. End to end on the reference container:
  **prescatter 47.5 s → 28.0 s, whole load 48.3 s → 35.4 s.** The terrain prewarm
  is the long pole now, not the vegetation.
- **The build narrows to ONE lane when nothing is covering the screen.** A
  prescatter that keeps every core busy after the bar has gone is the "vegetation
  tanks my FPS and then it recovers" report: the drop lasts exactly as long as the
  build and ends the instant it lands. `world_loading_screen` calls
  `prefill_covered()` every frame it is up, and `veg_scatter._prescatter_width`
  reads three lanes behind it and one in front. Measure both halves with
  `tests/PROBE_veg_timeline.gd` (`--expose` deletes the screen outright, which is
  the worst case: 49.6 s of uncovered build at one lane, and it still completes).

### Why grass is not prescattered too

Grass is visible for 90 m. The prefill the loading screen already runs lays down
every tuft that can be seen from where the player spawns — about 21,000 of them —
and everything past it is invisible until they walk there. Building the other 2.75
million would cost twenty-five minutes of loading and 169 MB to have *nothing* on
screen that is not there now. So the ground cover streams, and what stopped it
costing frames is the scan cell, not a bigger fill.

If that ever needs revisiting, the lever is `IslandField.sample()` itself, not the
scatter: grass needs height, slope, flatten, weights and the forest mask, and the
full sample also derives a surface normal, four sand-surface neighbours, a zone
name, a hole id and a twelve-key dictionary. A cover-only fast path is the only
thing that would move the twenty-five minutes — at the cost of a second code path
that could drift from the one painting the ground, which is exactly the drift
these scatters are built to make impossible.

## The ground around a hole, and the ground nothing grows on

Two changes to `IslandField`, made together because the second one needs the
first to be safe.

### A flat collar around every golf zone — `zone_skirt`, 16 m

`zone_at` used to hand out one weight: 1 inside a zone, falling to 0 over the
apron. That weight starts descending the instant it leaves the boundary, so a
hill crowding a hole gets to lean over the mown edge before the bank does
anything about it. Measured by `tests/PROBE_zone_skirt.gd`:

```
metres outside |    slope (mean / worst)   | drop below shelf | rock-dominant
the boundary   |   no collar     collar    |  no collar  with |  no collar with
  inside       | 0.006 /0.166  0.006/0.166 |   -0.14   -0.14  |   0.0%   0.0%
   0..4        | 0.018 /0.243  0.005/0.161 |   -0.04   -0.19  |   0.0%   0.0%
   4..8        | 0.062 /0.359  0.006/0.160 |    0.81   -0.17  |   0.0%   0.0%
   8..12       | 0.106 /0.492  0.007/0.146 |    2.28   -0.19  |   0.0%   0.0%
  12..16       | 0.136 /0.566  0.007/0.144 |    4.25   -0.13  |   0.0%   0.0%
  16..24       | 0.161 /0.576  0.038/0.338 |    7.78    0.48  |   6.0%   0.0%
  24..40       | 0.116 /0.526  0.135/0.496 |   14.20    5.47  |   2.7%   6.4%
```

Ground still as flat as the fairway reached **4 m** out; it now reaches the full
**16**. The bank past it is the same bank — mean slope 0.112 → 0.111, worst 0.487
→ 0.496 — because the ramp is **translated, not compressed**. That is the whole
implementation: `1 - smoothstep(0, apron, sd - skirt)` instead of
`1 - smoothstep(0, apron, sd)`.

**`zone_at` now returns two weights, and picking the wrong one is silent.** The
return value is the COURSE's — grooming, the hole label, buildable ground — and
is unchanged. `out[4]`, when `out` is sized 5, is the LAND's, and `base_height`
is the only thing that may read it. A caller that passes a shorter array and uses
the return value for height gets terrain that looks correct and sits a collar's
width away from the ground the player stands on. `test_island_world`'s "the
meshed ground and `sample()` describe the same collar" check compares real
`ChunkMesher` vertices against `sample()` for exactly this, and reads 0.00000 m.

Two consequences worth knowing:

- **Aprons of neighbouring holes now overlap by 23 m** at the minimum
  `zone_separation` (2 × (78 + 16) = 188 against 165). Survivable rather than
  accidental: the smoothstep is nearly flat that far out, so the midpoint between
  two holes keeps 94% of its relief instead of 100%. Past ~25 m of skirt that
  stops being true.
- **Bunkers follow the flattened ground**, at 2.5% of collar points. Not a leak —
  `sand_at` gates traps on local slope, so collar points that used to be too
  steep for one are now flat enough. The zone weight scaling them has not moved.

### Rock where nothing grows — `rock_follows_veg`

The splat's rock ramp (0.42 → 0.68) and the vegetation cutoffs (canopy thinning
from 0.294, gone by 0.42) were tuned against different things and nothing made
them meet. The ground between was **bald green**: too steep for a tuft or a
trunk, not steep enough to be painted rock. `tests/PROBE_rock_veg.gd`:

```
                     OLD  rock 0.42..0.68        NEW  rock follows veg
 slope band | land% | rock w | dominant        | rock w | dominant
 0.29..0.35 | 0.18% |  0.010 | g198 s1  r0     |  0.131 | g199 r0
 0.35..0.42 | 0.11% |  0.016 | g121 s0  r0     |  0.660 | g24  r97
 0.42..0.55 | 0.06% |  0.086 | g63  s1  r0     |  0.934 | g0   r64

 bald green past the vegetation ceiling: 2,922 m2 -> 0 m2  (of 5.02 km2 of land)
```

**Small in area is not the same as small.** 0.058% of the hub, but a footprint
measured flat under-reads a steep face by the factor that makes it steep, and
this is the part of the island presented to the eye rather than to the map.
Two thirds of it is zone banks; the rest is hill flank.

The band is `[forest_max_slope * FOREST_SLOPE_KNEE, forest_max_slope]` — ask
`rock_band()`, never the `rock_slope_lo/hi` exports, which are now only the
manual fallback. `grass_scatter.max_slope` is the third copy of the vegetation
ceiling and `test_island_world` asserts it stays equal to the field's.

**The loop through the scatters converges.** Both reject a cell whose dominant
surface is rock, so moving the ramp down also pulls the effective vegetation
ceiling to where rock passes 0.5 — slope 0.357 rather than 0.42. That is the
intended direction (no bald band is left over) and it stops there, because the
splat reads slope alone and never reads back what grew.

### Why the collar had to come first

`rock_follows_veg` starts painting rock at slope 0.294, which zone banks reach
and hills mostly do not — so the two changes meet on the same ground. With the
new rock rule and no collar, **6.0% of the ground 16–24 m outside a fairway
boundary comes out bare rock**. With the collar it is 0.0%, and the rock has
moved out past 24 m onto the bank, where an outcrop below a raised green is the
point rather than the problem.

## Known issues

- **The cloud tops are blocky at grazing angles.** Visible in `high_above` as
  large axis-aligned rectangular plates in the mid-distance. This is
  `filter_nearest_mipmap` on a 128² noise map viewed almost edge-on: one texel
  covers ~9 m of world at `scale_a = 1150`, and from 100 m above the deck those
  texels project to big screen-space rectangles. It was always there — the dark
  colours simply hid it, and giving the tops real contrast is what made it
  legible. `filter_linear_mipmap` would smooth it, but the nearest filter is a
  deliberate choice (see the sampler comment: it keeps texels chunky and stops
  grazing minification aliasing into crawling speckle that the LUT amplifies into
  confetti), so this is a genuine trade rather than an oversight. The other levers
  are `graze_gain` on the top deck, or pulling `horizon_fade_start` inward so the
  mid-distance converges to sky colour sooner.
- **The sky's horizon glow has its own hard palette step.** `horizon_glow_width =
  0.34` against `horizon_height = 0.25` puts the glow band's foot at
  `EYEDIR.y = -0.09`, about a degree *above* the true horizon — exactly where
  distant fogged island tops silhouette, and it is plainly visible as a
  horizontal edge across the `hub_low` and `horizon` shots. Nothing to do with
  the fog: the sky gradient alone crosses a LUT boundary there. Proposed fix is
  `horizon_glow_width` → 0.25, which puts the foot at 0.0 so the whole lower sky
  is one flat `0x11`. Not applied — it changes the sky everywhere and wants a
  look on real hardware first.
- **Wide shot lighting reads inside-out.** From ~2 km the hub's lit top is darker
  than its fogged cliff. Partly improved (grass ramp lifted, ambient raised) but
  not solved. It is a balance between `fog_distance_density`, `fog_color_high`
  and `grass_tint` — a judgement call best made on real hardware.
- ~~**Cliff rock is close to white and carries a strong repeating chevron
  pattern**~~, very obvious in the `cliff_side` shot, where 200 m of unfogged
  cliff face is the brightest thing on screen. Filed as a terrain-material issue
  — rock albedo, `normal_strength`, and the triplanar scale on near-vertical
  faces. **It was none of those: it was the rim's NORMALS.**

  `chunk_mesher._emit_column` built every rim vertex's normal from the column's
  radial direction, which is only the direction the shore faces if the coastline
  is a circle. It is the zero contour of `1 - d/radius + wobble *
  coast_irregularity`, and the wobble's gradient beats the radial term by an
  order of magnitude, so the two disagree by a mean of 48 degrees on the shipped
  hub and by more than 45 over 59% of its shoreline (`tests/PROBE_rim_normals.gd`
  measures it). Both cliff shaders are triplanar at `triplanar_sharpness = 4`, so
  past 45 degrees the wrong axis wins the `pow(abs(n), 4)` blend — and the wrong
  axis on a cliff is one whose plane lies ALONG the wall, where world position
  barely moves as you travel round the island. That is the chevron: rock smeared
  into metre-long horizontal streaks, at its worst on the stretches of perimeter
  that recede from the camera. The whiteness was the same error in the other half
  of the shader, the lighting reading a normal turned up to 81 degrees away from
  the face it was shading.

  Fixed by taking the coastline's own facing from the mask gradient
  (`chunk_mesher._coast_out`). The wall now reads as fractured rock at every
  angle, and it also has real relief for the first time — coastal inlets shade
  dark where they turn away from the sun instead of lighting like the headlands
  either side of them.

  WHAT IS LEFT OF IT is a grade question rather than a bug. Every number in
  `MAT_cliff_wall.tres` and the rock channel of `MAT_terrain_splat_w2.tres` —
  `rock_tint` at 2.8, `rock_contrast` at 0.7, `sun_bands` at 4 — was tuned
  against normals that swept smoothly round the compass and never pointed away
  from the sun. Against the real ones the wall's contrast is wider: measured on
  the `cliff_near` viewpoint it goes from mean luminance 66 to 127 with the same
  local spread (std 22.4 -> 20.9, nothing clipped). That is the shading finally
  distinguishing a lit face from a shaded one, but if the perimeter now reads too
  hot in daylight, `rock_tint` is the dial and it has never been re-measured
  since the normals were wrong.
- **`scripts/world/SCRIPT_cliff_scatter.gd` still makes the assumption the mesher just
  dropped.** Its `outward` and `radial_jitter` push each rock column out from the
  coastline along `dir`, and its lean and roll are taken in the `dir`/tangent
  frame — the same radial direction, carrying the same 48-degree mean error — so
  how far a column actually stands proud of the wall is that offset times the
  cosine of an angle nobody measured, which on the shipped hub averages 0.66 and
  bottoms out near 0.16. Nothing about this changed with the rim fix: the
  geometry did not move, only its normals. Filed rather than fixed because the
  scatter is not wired into SCENE_test_zone_W2 at all right now (see
  `DOC_scene_w2_skybox_terrain.md`), so there is nothing on screen to judge a fix by.
  `_coast_out` is the query it wants, and `_coast_radius` already proves the
  field is reachable from there.
- **`SCRIPT_cloud_planes.gd` writes to the shared deck materials at runtime.**
  `_refresh()` pushes the four fade radii and `world_offset`, and `_sort_decks()`
  writes `render_priority`, onto the `.tres` resources themselves. The node is
  `@tool`, so opening the scene in the editor dirties both materials and an
  unrelated save will commit that churn. Harmless at runtime; mildly annoying in
  git.
- **Grass colour is opinionated.** The greens come as much from the palette LUT
  as from the texture. If it reads wrong, try `grass_tint` before regenerating
  textures.
- **Coastlines are close to circular at island scale.** Obvious in any top-down
  render: the hub reads as a disc with a crinkled fringe rather than as a lobed
  landmass. `coast_irregularity` is the wobble, and it is capped at 0.15 because
  the disjointness proof needs it — `2 * max_radius * (1 + coast_irregularity) <
  0.7 * island_spacing`, and that cap is load-bearing because two islands that
  touch tear the mesh. Genuinely lobed coastlines therefore are *not* a knob;
  they need a different way of guaranteeing disjointness (per-island wobble
  budgeted against the actual gap to each neighbour, say) rather than one global
  constant sized for the worst case.
- **The hub takes a long time to stream in.** 449 land tiles at 128 m, and under
  software GL it needed several minutes to finish — long enough that a naive
  "wait until the chunk count stops rising" check fires early, on a plateau,
  while the far side is still queued. Dispatch is nearest-first by design, so
  that plateau is expected, not a bug. Worth knowing before concluding that
  something is broken on a first load.
- **`coast_lod` is global.** Coastal chunks are pinned to one LOD for all
  islands, so 8 m contour resolution is proportionally fine on the 2.5 km hub and
  chunky on a 90 m satellite. Making it scale with island radius is a small,
  obvious improvement nobody has needed yet.
- **Cliff bounds are still huge, by design.** Splitting the surface out fixed
  culling for the walkable ground, but a coastal chunk's cliff node still carries
  a box reaching to the island's centre axis and 629 m down, so cliffs
  essentially never cull. Fixing that means giving up the single shared tip the
  watertight underside depends on. If cliff overdraw ever shows up in a profile,
  that is the trade to reopen — not before.
- **`cull_disabled` and shadows.** Double-sided geometry casts shadows from both
  faces, which removes the usual front-face-culled shadow pass as an option and
  can bring on acne. Nothing visible at the current `shadow_bias` 0.012 /
  `shadow_normal_bias` 0.8 in headless renders, but those were software GL and
  near-static — worth a look on hardware with the sun low.
- **Zone meshing costs about 11%.** A hub LOD 0 chunk measured 40.2 ms with zones
  against 36.1 ms without, headless under llvmpipe. The per-chunk
  `zones_in_rect()` prefilter is what keeps it there — a 128 m chunk overlaps
  nought to two of the hub's fifteen zones, so the per-vertex loop is nearly
  always empty. Remove the prefilter and it becomes a per-vertex loop over every
  zone on the island.
- **The rough is gentler than "hills" suggests.** Mean slope in the rough was
  about 0.077 against 0.023 inside a zone — a clear contrast, but the hills were
  rolling rather than dramatic.

  *Since superseded.* The hill field is now sparsified (`hill_sparsity` /
  `hill_ramp`, see `docs/DOC_procedural_island_world.md`): most of the wild ground is
  level and the whole of a larger `hill_height` is spent on the minority that is
  not. Measured on the same sweep the numbers above came from, the rough is at
  0.115 against 0.034 in a zone — half again as much relief, and a wider contrast,
  from a taller but *gentler-flanked* hill. `hill_ramp` is the dial that made that
  possible and is the one to reach for before `hill_height`.

## Tuning cheat-sheet

Knobs you will reach for first, and what they cost:

| Want | Change | Cost |
| --- | --- | --- |
| Bigger/smaller hubs | `hub_radius` | Streaming load scales with area |
| Courses closer together / further apart | `hub_lattice` (cells between hubs) | Free — but keep hubs disjoint |
| More/fewer satellites | `satellite_density_near/far`, `satellite_reach` | Linear |
| Bigger satellites | `satellite_radius_near/far` **and** `island_spacing` | Radius is capped by spacing — see below |
| Rougher/smoother hills | `hill_ramp` **first** (it is the gentleness dial and costs no altitude), then `hill_height`, `ridge_height`, `micro_height` | Free |
| More/less flat wild ground | `hill_sparsity` (fraction of the hill noise clipped to level) | Free — strong dial, overshoots easily |
| More/fewer holes | `holes_max`, `golf_area_fraction` | Free |
| Longer/shorter holes | `hole_length_min/max` | Free — but see the club-power coupling |
| Wider/narrower fairways | `hole_width_ratio`, `hole_width_min/max` | Free |
| More/less hilly rough between holes | `zone_separation`, `zone_separation_ratio` | Free |
| Steeper/gentler banks around zones | `zone_apron` (lower = steeper), `zone_apron_ratio` / `zone_apron_min` for how it scales with the zone | Free — but re-check `zone_separation > 2 * (zone_apron + zone_skirt)`, and `zone_label_min` / `buildable_flatten` move in metres with it |
| Wider/narrower flat collar around a hole | `zone_skirt` (16 m; 0 disables) | Free — height only, the mown stripe does not move. Past ~25 m neighbouring aprons start eating the rough between holes |
| Golf sunk deeper into the land | `golf_inset` | Free — deepens the bank, so check `zone_apron` |
| Tracks between zones | `path_width`, `path_apron` (thin), `path_waypoint_tries` / `_spread` (how much they bend); `path_enabled` off to remove | Free |
| More/less building room | `build_area_fraction`, `build_pads_max`, `build_pad_radius_*` | Free |
| More/fewer bunkers | `sand_coverage`, `sand_scale` | Free |
| Deeper/shallower bunkers | `sand_depth` (1.4 m now; ball is 0.18 m) | Free — but re-measure with `tests/PROBE_sand_profile.gd` rather than with `atan(2d/r)`, which is the dish alone and was wrong here by 30°. Deepening also needs mesh resolution to read, see `pregen_cells` / `chunk_cells` |
| Bunkers off the tee and pin | `sand_end_clear` | Free |
| Sand outside courses | `sand_rough_gain` — 0 now, needs >0.5 to show at all | Free |
| More rock/soil showing | `rock_convexity`, `soil_concavity` (lower = more), `rock_convex_gain` | Free — set them ABOVE the fBm's own curvature noise floor (~0.3) or the ground speckles |
| Where rock faces start | `forest_max_slope` — the rock ramp follows it while `rock_follows_veg` is on, and `rock_slope_lo/hi` are inert | Free — but `grass_scatter.max_slope` has to move with it, and a test says so |
| Where the woods are | `forest_coverage`, `forest_scale`, `forest_edge`; `forest_litter` for how bare the floor goes | Free |
| How thick the woods are | `VegScatter.tree_forest_density` / `bush_*` / `fern_*` / `veg_grid` | Linear in plant count — **and in load time**, since it is all built up front |
| Vegetation built up front vs streamed | `VegScatter.prescatter` (on in W2), `prescatter_radius` | ~40 s of loading for the whole island; zero at run time |
| How often the scatters do any CPU work | `scan_cell` on either scatter (8 m grass, 44 m trees) | Inverse — see below |
| Thicker/thinner haze | `fog_opacity_gain` **first** (it is the only knob that can saturate the ramp — `fog_curve` alone mathematically cannot), then `fog_top/bottom`; `fog_distance_start/density/power` for the far field | Free |
| Bury the world seen from *below* the cliffs | `fog_density` / `fog_height_density` on the **Environment**, not the terrain shader — the shader's fog is an altitude lookup with no view ray in it | Free |
| Cloud altitudes | `sea_altitude`, `ceiling_altitude` on `CloudPlanes` — sea is coupled to the fog ramp, see coupling 7 | Free |
| More/less cloud | `cloud_threshold` (raise = more open void), `detail_weight`, `gap_weight` per deck material | Free |
| Cloud chunkiness | `cloud_steps` (4 is the Hexen read; 8 is a smooth gradient, 2 a stencil) | Free |
| Horizon height | `horizon_height` on the sky material | Free |
| Draw distance | `view_distance` | Large — this is the perf knob |
| Sharper coastlines | `coast_lod` (lower = finer) | Large — doubles rim geometry per step |

**Nine couplings that will bite.** Full explanations in the design doc:

1. Satellite radius is capped against `island_spacing` — raising radius alone
   silently clamps. Raise spacing too.
2. `cliff_cutoff_y` must stay below the shader's `fog_bottom` **by ~150 m**, or
   the cliff bottom stops rather than dissolving. `-vertical_spread` must stay
   above `fog_top`, or the lowest islands generate inside the haze.
3. Sky colours and terrain fog colours must stay matched, or distant cliffs
   resolve against the sky instead of dissolving into it. **Every grey in this
   world is an exact neutral (r == g == b) on purpose**, and the ones meant to
   vanish into the void sky have to land in 0.069–0.107; 0.108 and up is a
   visible hard palette step. There is a measured table in the design doc — read
   it before picking a new grey, not after.
4. `hub_lattice * island_spacing` must exceed `2 * hub_radius * (1 +
   coast_irregularity)` or two hubs merge — the same tear satellites are capped
   against.
5. `zone_coast_margin` must exceed `shore_width`, or zones land on the shore ramp
   and come out tilted. `zone_separation` must exceed `2 * zone_apron`, or there
   is no hilly rough left between holes.
6. **Hole length is coupled to club power, and nothing enforces it.**
   `SCRIPT_golf_controller.gd` gives the driver 65 m/s at 11° with `POWER_MULTIPLIER =
   2.0`, which carries roughly 600 m — past every par 4 and most par 5s in the
   180–450 m band. Either raise `hole_length_min/max` or lower that multiplier
   toward 1.0. This was left alone deliberately: it is a gameplay-balance call,
   not a terrain one.
7. **`sea_altitude` is coupled to the fog ramp, not just to `fog_top`.** The ramp
   saturates 62 m under `fog_top` (y = -262 as shipped), and a deck below *that*
   floats under cliffs which have already dissolved, with a gap of nothing
   between rock and cloud. -212 keeps the cliff ~47% fogged where it meets the
   deck. Move `fog_opacity_gain` or the band and this number moves with them.
   Neither fog touches the decks (`fog_disabled`), so nothing paints that
   transition for you.
8. **`vertical_spread` sets the visible cliff length and the shader cannot
   narrow it.** Visible length is exactly `fog_top - base_y` and bases span
   ±`vertical_spread`, so the spread of visible cliff lengths is exactly
   `2 * vertical_spread`. The fog band is a world-space constant and the mesh
   carries no per-island altitude channel (`COLOR` is fully spent on the four
   splat weights), so escaping the trade means feeding a per-island fog offset
   through `UV2` and touching `SCRIPT_chunk_mesher.gd` — not attempted.

   | value | visible cliff | flat deck reads as one surface? |
   | --- | --- | --- |
   | 180 (original) | 20–380 m | no |
   | **90 (now)** | **110–290 m** | yes |
   | 50 | 150–250 m | yes, tightly — exactly the brief's window |

   90 is shipped in preference to 50 on the judgement that "dramatic and legible
   for the first 150–250 m" describes the intent rather than specifies a
   tolerance: 110–290 m all reads that way, and the wider spread keeps the
   archipelago from flattening into a pancake of same-height islands. Drop to 50
   if the window turns out to be a hard requirement.
9. **`horizontal_only = true` on `FloatingOrigin` is mandatory in this scene.**
   Several things pin themselves to absolute world Y — the shader's fog band, the
   Environment's `fog_height`, both cloud decks — and none of them can be told
   they moved. A full-vector rebase at cruise altitude slides every island up in
   render space against all of it, un-fogging the top of every cliff and dropping
   the islands through the cloud sea. The export defaults to `false` because the
   script is shared with the fleet game, which rebases all three axes and always
   has.

## Next steps, roughly in order

1. **Run it on real hardware and get a frame time.** Everything else is guesswork
   until this exists. If it is heavy, in order: `view_distance`, then `coast_lod`,
   then `lod_distances`. Two commands, both of which work unchanged on the Pi:
   `tests/PERF_cloud_decks.gd` for what the decks cost, and
   `tests/RENDER_island_shots.gd` to confirm the atmosphere still looks right at
   whatever settings you land on. If the decks turn out to be the problem, the
   cheapest lever is `graze_max` and the fade radii — not deleting a deck.
2. **Wire the gameplay hooks.** `IslandWorld.sample_at(pos)` returns
   `{on_land, height, normal, slope, weights, surface, zone, flatten, hole,
   buildable}` and handles the floating-origin conversion. Nothing calls it yet.
   The obvious first use is `SCRIPT_golf_ball.gd` reading `surface == "sand"` and adding
   drag — the renderer and the query run the same classifier, so the sand that
   slows the ball is exactly the sand you can see.
3. **Put a player on it** and confirm collision actually holds, then a golf ball,
   then aircraft. Collision is on by default out to 1400 m and covers cliffs as
   well as the surface.
4. **Point `SCRIPT_golf_controller.gd` at the generated holes.** It currently finds its
   hole by scanning the scene tree for a node whose name contains "hole"
   (`_find_hole_in_tree`). `IslandWorld.nearest_hole(pos)` and `holes_near(pos,
   r)` now return `{id, index, par, length, width, tee, pin}` with tee and pin
   already in render space, so the replacement is a small one — and it is what
   turns the generated courses into playable golf. Nothing places a physical pin
   or tee marker node yet.
5. **Gate the build controller on `is_buildable()`.** The build pads exist, are
   flat, and read as bare soil so the player can see them, but
   `SCRIPT_build_controller.gd` does not consult the world at all yet.
6. **Decide the fate of `SCRIPT_infinite_islands.gd`.** Keep for the flight scene, or
   retire once this replaces it everywhere.

## Planned, not built: hub biomes

Hubs are now a lattice of large islands rather than one hand-placed island, and
the intent is for them to differ from each other — **many hub islands with
different biomes**. Nothing of that exists yet; every hub is generated from the
same parameters and differs only in `base_y` and `peak`.

The seam it would attach to is `_cell_island()`, in the branch that builds a hub:
that is already the one place where a hub's identity is decided, it is already
seeded per hub cell, and `hub_base_spread` is the existing example of per-hub
variation hanging off it. A biome would most likely be an index rolled there and
carried on `Island`, with the terrain, splat and zone parameters read through it.
Two things to know before starting:

- The splat has exactly four channels and they are packed into vertex COLOR.
  A biome that wants a fifth surface is not a parameter change; it needs a new
  vertex attribute and shader work.
- `IslandField` is a flat bag of exported parameters by deliberate choice (see
  "Things deliberately not done" — no node-graph editor). Per-biome parameter
  sets want a different shape, most likely a `Resource` per biome that the field
  holds an array of. That is the decision to make first, and it is a bigger one
  than it looks.

## Things deliberately not done

- No day/night cycle (explicitly deferred).
- No water, no vegetation, no props.
- The sun is a plain `DirectionalLight3D` with shadows; no atmospheric scattering.
- No node-graph editor. Generation is one tuned script with exported parameters,
  which was the chosen scope over a MapMagic-style graph UI.
- Cliffs assume a star-shaped coastline (radius single-valued in angle). The
  `coast_irregularity` cap keeps that true. If you ever want overhangs or arches,
  the converging cliff sweep is the thing that has to change.

## Traps worth naming

`textures/proc/*.import` **UID churn from a running editor is noise, not a
change.** The editor rewrites those files with fresh UIDs whenever it re-imports,
but `MAT_terrain_splat.tres` references the *committed* UIDs — so keeping the
repo's values is what stays self-consistent. Discard it; expect it back.

`scripts/SCRIPT_fly_camera.gd` **overwrites the camera's rotation every frame** from its
own `_yaw`/`_pitch`, seeded once in `_ready`. Setting a camera transform in the
scene file works, but only because `_ready` reads the euler back out. If you set
a camera orientation from code after `_ready`, it will be silently reverted.

Related: the directional light in scenes copied from `SCENE_test_zone_C` points
*upward*. It went unnoticed for as long as a bright sky panorama supplied all the
ambient; the moment the sky went grey, everything rendered black. The light in
`SCENE_test_zone_W` is fixed — check any other scene you copy from C.
