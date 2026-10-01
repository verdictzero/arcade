# Procedural island world

A chunked, streaming, MapMagic-style terrain system: **hub islands** on a coarse
lattice with smaller satellites scattering out from each, separated by sky-void,
under a flat grey overcast with a raised horizon. Undersides plunge and dissolve
into fog. Every hub carries a labelled golf course; satellites carry hills and
buildable flats.

The atmosphere is **two fogs and two cloud decks**: the terrain shader's
altitude-banded void fog, the Environment's height fog (which is what actually
buries the world when you drop below the cliffs — the first one cannot, see "The
fog floor"), a cloud sea under the islands and a cloud ceiling over them.

Scene: `scenes/utility/SCENE_test_zone_W.tscn`. It does not touch
`scripts/SCRIPT_infinite_islands.gd` or `SCENE_test_zone_C.tscn`, so the old island
field still works and the two can be compared side by side.

## Files

| File | Role |
| --- | --- |
| `scripts/world/SCRIPT_island_field.gd` | The world as pure functions of world XZ. No storage. |
| `scripts/world/SCRIPT_chunk_mesher.gd` | Field → mesh. Marching squares, cliff sweep, LOD skirts. Thread-safe, static. |
| `scripts/world/SCRIPT_island_world.gd` | Streaming, per-chunk LOD, worker threads, collision, floating origin. |
| `scripts/world/SCRIPT_bake_store.gd` | The keyed cross-scene store both bakes are: holding, signature, byte accounting. |
| `scripts/autoload/AUTOLOAD_terrain_bake.gd` | Chunk meshes and collision shapes held across scene loads, keyed on what the geometry is a function of. See "The bake". |
| `scripts/autoload/AUTOLOAD_veg_bake.gd` | The same, for the prescattered vegetation's packed instance buffers — the other 41 seconds of a battle re-entry. |
| `shaders/SHADER_terrain_splat.gdshader` | 4-surface splat from vertex colour + void fog (W). |
| `shaders/SHADER_terrain_splat_w2.gdshader` | 7-layer textured splat: the four weights plus golf / forest / path from the two UV sets (W2). |
| `shaders/SHADER_sky_void_gradient.gdshader` | Grey gradient sky with the raised horizon. |
| `shaders/SHADER_cloud_plane.gdshader` | The 2D cloud decks: two scrolling noise layers combined by difference, hard coverage edge, interior quantised in-shader. |
| `scripts/world/SCRIPT_cloud_planes.gd` | `@tool` node owning both deck quads. Follows the camera in XZ only, never in Y. |
| `materials/MAT_terrain_splat.tres`, `MAT_sky_void.tres` | The terrain and sky materials. |
| `materials/MAT_cloud_deck_bottom.tres`, `MAT_cloud_deck_top.tres` | The cloud sea and cloud ceiling. One shader, two tunings. |
| `data/ISLANDFIELD_default.tres` | Tunable preset. This is the thing to edit. |
| `data/palettes/PALETTE_ps1-soft.hex` + its LUT | The project default palette. Built by `tools/TOOL_build_ps1_palette.py` — see "The grey sky needs its own palette". |
| `tools/TOOL_bake_world.gd` | Pre-generates a zone to `user://bake` so no cold start pays for it. `--check` says whether the one on disk is still current. |
| `addons/world_baker/` | The same tool with a button on it: pick a zone, see whether its bake is current, bake it from the editor with a progress bar. See `DOC_world_baker.md`. |
| `scripts/world/SCRIPT_bake_roster.gd` | `BakeRoster`: which zones the game has CHOSEN, and whether their bakes ship or are merely kept. |
| `scripts/world/SCRIPT_bake_retention.gd` | `BakeRetention`: what is on disk, what world each file is still for, and what should become of it. Also the one place a zone's terrain signature is derived — `TOOL_bake_world.gd` calls it. |
| `tools/TOOL_bake_retention.gd` | Lists, stages into `res://data/bake`, sweeps what no scene can load, and gates a build that would ship a world it does not have. |
| `addons/bake_retention/` | The same tool with a table on it. See `docs/DOC_bake_retention.md`. |
| `tools/TOOL_gen_terrain_textures.py` | Bakes the 8 pixel-art textures. |
| `tools/TOOL_gen_cloud_noise.py` + `TEX_cloud_noise.png` | Bakes the seamless 128² RGBA noise the decks sample. Four channels: mass, breakup, fray, gaps. |
| `tests/TEST_island_world.gd` | Headless checks. Run before trusting any change here. |
| `tests/RENDER_island_shots.gd` | Offscreen screenshot harness, 7 named viewpoints. The atmosphere test whose output is pictures. |
| `tests/RENDER_island_flyover.gd` | The moving-camera counterpart: a flyover merging into a 720° orbit, one PNG per frame. See "Filming the island". |
| `tools/TOOL_encode_video.py` | Muxes a frame directory into an mp4 without destroying the dither. |
| `tests/PERF_cloud_decks.gd` | Draws the frame with the decks hidden and shown and subtracts, to cost their fill rate. |
| `tests/TEST_terrain_bake.gd` | The bake's signature and store. Aimed at the dangerous direction: a hit that should have missed. Also checks the code digest is wired to the geometry code. |
| `tests/TEST_veg_bake.gd` | The vegetation store, and a battle re-entry planting the same forest — byte for byte, not merely the same count. |
| `tests/TEST_bake_retention.gd` | The librarian's verdicts, the roster, and the four couplings that rot quietly. |
| `tests/TEST_bake_retention_tool.gd` | The retention tool as a process: exit codes, dry runs, the protocol. |
| `tests/TEST_bake_retention_dock.gd` | The dock against the real tool in a real subprocess. |
| `tests/TEST_bake_shipped_world.gd` | The far end: the real island coming out of `res://data/bake`, and the screen saying LOADING rather than GENERATING. |
| `tests/PROBE_w3_load_frames.gd` | Whether the loading screen kept ANIMATING while the world built. A build timer cannot see a 46-second frame. |
| `tests/PROBE_bake_footprint.gd` | What the bake holds after a prewarm, and whether walking the world makes it grow. |
| `tests/PERF_w3_reentry.gd` | Builds W3, then builds it again the way a battle return does. What the bake is measured with. |
| `tests/PERF_w3_frame.gd` | Where a W3 frame goes, split into pregen / settling / walking. Renders, so run it under xvfb. |

## How it works

**Composition.** Hub islands (default 1250 m radius, ~2.5 km across) sit on a
coarse sub-lattice of the island lattice — every `hub_lattice` cells on each
axis, phase-aligned so that `hub_center` is always one of them. Each replaces the
satellite its cell would otherwise have rolled, so streaming, meshing and point
queries all stay on one uniform "ask the lattice" path. Satellites come from the
lattice as before, but their radius and density both fall off with distance out
from the **nearest** hub's rim, so the world reads as one landmass shedding
debris — around every hub, not just the first one. Past `satellite_reach` they
level off rather than stopping, so streaming still works forever.

Hubs recur because golf is hub-only. A single hand-placed hub would put exactly
one course in an otherwise infinite world; a lattice of them means flying far
enough in any direction always brings up another course island, each with its own
nine holes and its own stable hole ids.

**Terrain.** A mixture of noises (rolling fBm + ridged spines + micro detail)
multiplied by a shore ramp that is zero at the coastline, so land rises out of
its own edge and the plateau meets the cliff top at exactly the island's base
altitude — and then flattened away inside zones, so hills only ever occupy the
ground between them.

The hill term is **sparsified**. `hill_sparsity` clips the bottom off the
remapped hill noise, so everything under it is dead flat at the island's base
altitude and only the top of the distribution rises; `hill_ramp` sets how quickly
it does. Raw fBm is a uniform swell — every square metre is some way up or down
some slope, so there is no level ground anywhere and the relief budget is spread
thin over the whole island. Clipping inverts that: about 60% of the wild ground
is flat, and the whole of `hill_height` is spent on the
minority that is not. That is what lets the hills get taller and the world get
flatter at the same time, and it is why raising `hill_scale` alone was never
enough — a lower-frequency swell is still a swell. `ridge_on_hills` masks the
ridged spines by the same shape, because a 20 m spine field carpeting the "flat"
ground would quietly undo all of it.

**Forests.** `forest_at` is a blob mask over the wild ground, read by **two**
consumers: `SCRIPT_veg_scatter.gd` interpolates each class's keep probability between
its `*_open_density` and `*_forest_density` by it, and `splat_weights` moves
`forest_litter` of the turf into the `soil` channel under the canopy. One noise,
on the field, so the trees and the floor they stand on can never disagree about
where the wood is — two separate noises would drift and the ground would go brown
a hundred metres from the nearest tree. The mask is multiplied out by the zone
weight, so a wood never grows on a fairway.

**Geometry.** Not a heightmap — a heightmap can only fall as fast as its vertex
spacing allows. Each chunk contours the land mask with Sutherland–Hodgman:
interior cells emit two triangles, void cells nothing, coastline cells are
clipped to the exact zero-crossing. Crisp shoreline, and it hands back the
coastline as segments for the cliff to hang off.

**Cliffs.** Each coastline segment sweeps down, converging on the island's centre
axis through terraces, all columns meeting one shared tip. Depth is proportional
to radius and truncated at the fog floor (see below).

**Splat.** Weights are computed CPU-side from slope, curvature and the sand mask,
packed into vertex COLOR as (grass, soil, rock, sand). Concave hollows collect
soil, convex ridges scour to rock, steep ground is rock, and there is a bare rock
band around every coastline. The shader blends colour and normal maps only.

**The thresholds are set against the noise floor, not against the landform.**
This is the single most important thing to know about tuning them. Curvature is a
second derivative, so it goes as amplitude over feature size squared — and a
4-octave fBm's top octave has a quarter of the size and an eighth of the
amplitude, which makes it dominate the measurement by an order of magnitude over
the hills you can actually see. Measured on the shipped preset, ordinary ground
reads |curvature| ≈ 0.3. The old `soil_concavity` of 0.30 and `rock_convexity` of
0.40 were therefore *below the noise floor*: every wrinkle in the fBm classified
as a gully or a crag, and the wild ground came out as grey-and-brown static with
grass showing through it. Set above that floor (0.90 / 1.20) the two rules go
back to firing on real hollows and real spines, and `rock_convex_gain` caps what
convexity alone may expose so proud ground scours to a streak rather than a crag.
`rock_slope_lo` / `_hi` moved the same way (0.42 / 0.68, ~55° and ~72°): at 0.30
the onset sat below the gradient of an ordinary grassy hillside, so rock stopped
meaning "too steep to stand on". The hill flanks `hill_ramp` produces top out
around 0.31, deliberately just under the onset — those numbers are a pair.

**Double sided.** The terrain is a shell, not a solid — the surface, the skirts
and the cliff cone are each one layer of triangles wound outward — so back-face
culling let you see straight through an island from underneath or from inside the
cone. The shader runs `cull_disabled`, and leaves the back-face normal to the
engine, which turns NORMAL toward the viewer on a back face before `fragment()` runs
(`tests/PROBE_ruin_light_normals.gd` measures it on 4.7 GLES3). The shaders used to
flip it again on `!FRONT_FACING`, which lit every back face as its own front — an
underside seen from below came out sunlit. Visible consequence of double-sidedness:
looking down through a gap in the coastline shows the far inner wall of the cliff
cone instead of the void behind the island.

**Sand traps.** A **jittered grid of discs**: ground within `sand_radius` of a
grid feature point, suppressed on slopes and near coastlines, dishing out
`sand_depth` (1.4 m — the ball is 0.18 m) with a raised lip, and gated on golf
zone membership so a bunker is always part of a hole. Suppressed within
`sand_end_clear` of a hole's tee and its pin: those two points *are* the ends of
the fairway capsule, so nothing was stopping the traps landing on top of them,
and two of the hub's nine holes did come out teeing off from inside a bunker.

Depth is **coupled to mesh resolution**, which is why it could not simply be
raised before. The dish is carved into the vertex grid, so at the old 10.7 m
spacing a 34 m trap was three vertices wide and a deep one came out as a
triangular pit. The grid is 2 m now (`chunk_size` 128 over `chunk_cells` 64), so
a 26 m trap is thirteen vertices across and holds a scooped profile.

Depth was long assumed to be coupled to `sand_radius` from the other side too —
that what you see is the wall angle, roughly `atan(2 * depth / radius)`, so
shrinking traps steepens them at fixed depth. **That closed form is the dish
alone, and it was wrong here by thirty degrees.** `sand_at` multiplies the
radial ramp by a wobbled outline, a slope veto and a tee/pin veto, and all of
them fall off together across the same few metres, so the real face is much
steeper than the dish that nominally makes it. Walked with
`tests/PROBE_sand_profile.gd` over 480 rays through 30 traps on the hub:

| | depth 3.4 m | depth 1.4 m |
|---|---|---|
| median wall | 59° | 42° |
| 90th percentile | 68° | 55° |
| worst | 73° | 62° |
| raised lip above grass | 0.00 m | 0.19 m |
| `atan(2d/r)` says | 28° | 12° |

**Depth is now 1.4 m**, down from 3.4. The angles barely move with it because
they are the wobble's rather than the depth's; what depth controls is how *tall*
that face is, and that is the number the player reads. The player capsule is
1.8 m with the head at 1.6 m, so a 3.4 m drop at 59° put the rim a metre and a
half overhead — a hole punched in the map, with the green you are playing to
hidden behind it. At 1.4 m the floor is shoulder high and the eye sits level
with the 1.59 m lip crest, a sightline that grazes the rim. It is still 7.8 ball
diameters, so it stays a hazard you have to chip out of.

It also gave `sand_rim` something to do. Lip and dish are summed over the same
band, so the lip only shows where it outruns the dish, and at 3.4 m it never did
— the probe measured **0.00 m** of rise above surrounding grass. The same 0.7 m
rim now clears grass by 0.19 m about a third of the way out along the edge band.

It is also coupled to the **shading** normal. `SCRIPT_chunk_mesher.gd` now derives two:
the landform normal off the pre-sand surface, which is what the splat classifies
from (so a trap can never repaint its own walls as scree, and LOD splat stability
is untouched), and the shading normal off the dished surface, which is what goes
into `ARRAY_NORMAL`. They were the same expression while traps were 0.6 m deep
and are visibly not at 2.4 m: geometry you can plainly see, lit as though it
were not there. The second is only derived where a trap can exist at all
(`sand_possible`), so everywhere else it costs nothing.

## Golf zones

The world is built from **one construction repeated at three nested scales**:
a disc (or capsule) with a noise wobble on its boundary, each living inside the
one above it.

| Scale | Shape | Wobble | Feature size |
| --- | --- | --- | --- |
| Island | disc about the cell's centre | `coast_noise` | 130 m |
| Zone — a hole or a build pad | capsule from tee to pin, or a disc | `zone_noise` | 70 m |
| Path — a track between two zones | capsule, two per link | `zone_noise` | 70 m |
| Bunker | disc about a jittered grid point | `sand_wobble` | 16 m |

**A trap is a disc around a point, not a level set of a noise field.** This is
the one place the "wobbled shape" construction above does not apply to the shape
itself, only to its outline, and the reason is that thresholding noise cannot
control size. The size of a level set is not something the threshold decides:
the field has broad high plateaux in some places and barely crests the line in
others, so one blob sprawls and the next is a speck. Measured on the model this
replaced: **nine traps spanning 208 to 6512 m², a 31-fold spread**, off a single
threshold — and before that, 41 bunkers plus **436 sub-120 m² specks**.

No dial fixes that, and two passes were spent discovering it. `sand_coverage`
was not an area fraction (it was inverted to a threshold, and simplex piles up
mid-range, so the mapping was neither linear nor guessable). `sand_contrast`
sharpened the *edge* without making the lobes any more alike. Reaching for
either to get "fewer traps" instead resized the ones already there.

Distance to the nearest point of a jittered grid inverts the problem, and every
parameter becomes a measurement:

| Want | Dial | Mechanism |
| --- | --- | --- |
| more/fewer traps | `sand_spacing` | grid cell size — count is area / spacing² |
| bigger/smaller | `sand_radius` | a literal radius, identical for every trap |
| less lattice-like | `sand_jitter` | how far a centre leaves its grid node |
| organic outline | `sand_wobble` | noise added to the radius |

This rests on FastNoiseLite's cellular `RETURN_DISTANCE` being a **true Euclidean
distance field**, measured in cells and biased by −1, so `metres = (value + 1) *
spacing` is exact rather than fitted. The defining property is that the gradient
magnitude is 1; it measures 1.0000 at both the median and the 90th percentile.
`TEST_island_world.gd` asserts it, because an engine upgrade that changed the
cellular normalisation would silently resize every trap in the world and nothing
else would notice.

Three things this model still cannot do for free, all of them measured:

- **Per-hole cover is tuned, not guaranteed.** The grid is laid over the *world*,
  not the course, so a hole whose flat core is smaller than a grid cell only gets
  a trap if the lattice happens to fall inside it. It is not even monotone —
  spacing 96 m covers *fewer* holes than 108 m. 108 covers every hole on both
  shipped presets; re-measure after any change to the layout, radius or seed.
- **Slope is the binding constraint on hilly holes**, not spacing. Two holes came
  up empty and the cause was `sand_max_slope`, not grid coverage: the fairway
  *core* is dead flat everywhere (median slope 0.001), and all the slope lives in
  the apron where hill relief deliberately returns. Tightening the spacing would
  never have fixed it.
- **Traps can still merge if `sand_jitter` goes too high.** The clearance needed
  is `2 * (sand_radius + sand_wobble)` — radius *plus wobble*, because two
  neighbours can each wobble toward the other. Measured: 0.7 clears by 9 m, 0.85
  touches.

**Measuring the centres is itself a trap.** Hunting the distance field's local
minima on a raster finds false ones on cell boundaries and reports separations
far too small — it condemned jitter 0.7, which is fine. The analytic guess
(`(1 - 0.874 * jitter) * spacing`) errs the other way, describing the typical
pair rather than the closest one on a whole island. `trap_centres_in_disc` gets
it right: `|grad| = 1` means one Newton step along the gradient lands exactly on
a centre, and it then checks the refined point really is one.

`scripts/SCRIPT_measure_sand.gd` reports count, size spread, per-hole cover and the
merge clearance for both presets (`--default` for the nine-hole one, `--sweep`
for a spacing × radius table). Measure with it rather than reasoning about the
dials.

**A hole is a capsule, not a blob.** The mask is the distance to the *axis*,
less a wobbled half-width. Two reasons. A circular clearing reads as a green
rather than as a hole you play down — the tee and the pin have to be far apart
and the ground between them is the thing that has to be flat. And taking the axis
as the definition means the tee and the pin **fall out of the geometry**, so
there is no second placement pass that could drop a pin on a slope. `Zone` covers
build pads too, with `a == b` so the capsule degenerates to a disc and one mask
serves both.

**And every hole doglegs.** The axis is the polyline `a -> m -> b`, not the
segment `a -> b`: `Zone.bent` says whether there is an elbow and `Zone.segments()`
hands out one segment or two. Everything downstream was already expressed through
`axis_distance()`, so the bend cost nothing there — the places that *did* need
teaching are the ones that reasoned about the axis from its endpoints instead:
`zones_in_rect` (a corner sits outside the box its endpoints span, and a zone
dropped for the chunk its corner lands in is a fairway with an unflattened hole
punched through it) and the separation test (the `a -> b` chord of a bent hole
runs through ground the hole does not occupy).

The elbow is *constructed* from the requested deflection rather than fitted to
it, via `_dogleg_offset()`. The obvious offset — `min(p, 1-p) * L * tan(turn/2)`
— is exact only when the elbow is halfway along and decays as it moves toward
either end, delivering 35° for a requested 45° at split 0.35. Solving
`tan(turn) = u / (pq - u²)` for the offset instead makes the angle exact at any
split, which is what lets the band be asserted without a tolerance.

**A hole that cannot dogleg is not placed.** The earlier version fell back to a
straight capsule, and produced a course of eight doglegs and one driving range —
the kind of defect an average over the course hides completely. When an elbow
would leave the island the placement tries the *other* side rather than pulling
the corner in, because pulling it in shallows the turn out of the requested band
silently; the spine already fits, so one of the two sides nearly always does.

**Why placement is rejection sampling and not a noise threshold.** Thresholding
blob noise gives you blobs, and you cannot name the third one. Labelling is the
whole point here: `Hole.id` is `"cellX:cellZ:n"`, derived from the world seed and
nothing else, so hole 3 of the island two cells north has the same tee, pin and
par whether you visit it now or after flying a thousand kilometres away and back.
That is what makes the golf infinite without storing anything. Getting an
enumerable, nameable set out of a noise field would need a raster
connected-component pass; seeding sites and testing candidates gets it directly,
and the acceptance tests (fit inside the island, hold clear of the other zones)
are trivial to evaluate even though they are awkward to satisfy by construction.

**Flattening replaces relief, it does not scale it.** `base_height` lerps the
whole relief expression toward a flat shelf. Scaling relief down instead would
leave a zone flat only in the sense of "less bumpy" — it would still inherit
whatever slope the hill field had across it, so a fairway laid over a hillside
would come out as a smooth ramp. The apron carries the hills back up around the
rim, and a per-zone `lift` keeps the course terraced rather than one flat pan.

**Build pads are the `soil` channel.** Golf zones groom to grass, build pads
groom to bare earth. That is a free visual language: `soil` is already one of the
four splat weights, so telling the player where they can build costs no fifth
channel, no extra vertex attribute and no shader change. Paths groom to the same
channel; the flat-colour shader tells the two apart from UV2, not from the
weights.

### Paths

`zone_separation` deliberately leaves 165 m of un-flattened hill between any two
zones, which — once the hills got taller and the ground between them got flatter
— turned every clearing on an island into an island of its own: you dropped off a
65 m apron into the rough, crossed a hill, and climbed another apron to reach the
next hole. **Paths are the connective tissue**, and they are the fourth scale of
the same construction everything else is built from, with two properties none of
the others have.

**They are allowed to overlap what they join.** A track that held
`zone_separation` from the zones at its two ends would connect nothing. So they
are placed *after* the separation test rather than being subject to it, and
appended to the zone array *after* everything else — `zone_at` breaks ties by
array order, so a hole or a pad always wins the ground it shares with the track
running onto it, and "which hole am I on" keeps its unambiguous answer.

**Their shelf ramps instead of being level.** `Zone.lift_b` is the altitude at
the `b` end; every other zone sets it equal to `lift`, because a hole or a pad is
a *shelf* and a shelf that sloped would be a ramp you cannot putt on or build on.
`Zone.lift_at()` short-circuits on that equality, so the graded case costs the
twenty flat ones nothing.

**Topology is a minimum spanning tree** over the zone centres. Not every pair
(that is a road network, and n² tracks would flatten more ground than the zones
they connect) and not a chain (whose length is unbounded and which routes you
through hole 5 to get from 4 to 6). An MST is the shortest set of links that
leaves nothing stranded. n is a couple of dozen, so the naive O(n³) Prim runs
once per island and costs nothing.

**Each link is two capsules, not one**, meeting at a waypoint whose own shelf
altitude *is* the terrain height there. A single straight capsule between two
shelves is a cutting: it holds one grade and whatever hill lies between gets
sliced through it. Bending at a ground-level waypoint lets the track climb with
the land, and choosing that waypoint from a handful of candidates scored by how
much earth the two halves move (`_path_cut`) makes paths route around hills for
free — no search, no routing pass, nothing stored.

**The apron is per-zone now** (`Zone.apron`), because a 4 m track banked over a
fairway's 65 m earthwork would be a motorway cutting. `path_apron` is 11 m, so a
path reads as incised into the hillside it crosses.

### Three couplings inside the zone system

1. **`zone_apron` is metres, not mask units — but not a single number.** The drop
   from full hill relief to a flat shelf is tens of metres. An apron specified as
   a fraction of zone width would be a few metres wide on a narrow par 3 and put
   a near-vertical rock wall around it, so the apron is fixed in world units,
   which fixes the *slope* of the bank — the thing that has to stay walkable and
   stay under `rock_slope_lo`. It also scales with `hill_height`: 50 m against a
   39 m worst-case relief became 65 m against 58.

   The ceiling alone stopped fitting at that size. A 31 m build pad with a 65 m
   bank is four times as much earthwork as pad, and most of what `sample()` was
   willing to call "a build pad" was hillside — the ground reported flat enough
   to build on averaged four times the slope of the pad's own dead-level core.
   `zone_apron_for()` sizes the bank at `zone_apron_ratio` × the zone's own
   half-width, capped by `zone_apron` and floored by `zone_apron_min` (which is
   the narrow-par-3 constraint, and the reason the apron cannot simply *be* a
   fraction of zone width).

2. **`zone_separation` has to clear `2 * zone_apron`, and it is capped
   proportionally.** Disjointness alone only needs
   `2 * hole_width_max * zone_irregularity` (20 m at the defaults). The rest of
   the gap is the hills: set it under `2 * zone_apron` and neighbouring aprons
   meet, so the ground between two holes never returns to full relief and there
   is no hilly rough at all. But a fixed gap that is a comfortable walk on the
   2.5 km hub is more than a 400 m satellite can spare, and the failure is
   silent and total — the sampler rejects every candidate and the island comes
   out with no build pads whatever. `zone_separation_ratio` caps it against the
   island's own size, the same way `cliff_depth_ratio` scales cliffs.

   It is also what *shortens the holes*: separation only rejects, so a wider gap
   skews the accepted set toward short candidates. 190 m turned the hub's course
   into eight par 3s; 165 m puts the par 4s back. Paths are exempt from all of
   this — see "Paths" above.

3. **`zone_coast_margin` must exceed `shore_width`.** The shore ramp multiplies
   the whole height expression, so a zone reaching onto it comes out tilted
   toward the sea with its `lift` scaled by an amount that varies across the
   zone. `_zone_safe_radius()` converts the margin into metres against the
   *worst case* coastline wobble, which reserves more shore than it strictly
   needs — losing a little placeable area is the cheap failure; a fairway
   hanging over a cliff is not.

### Two traps that already cost a debugging pass

**Size the footprint from what the island can hold, then derive the count.**
Deriving `want_holes` from the global 180–450 m length band makes a small
island's holes look far more expensive than the ones it will actually place, so
the count rounds to zero and the island comes out bare — while being perfectly
able to hold the short par 3 the sampler would have proposed.

**Trim the capsule to fit; do not propose and reject.** The longest hole an
island can hold is only attainable through its exact centre, so a length near
that bound is accepted only by a candidate that is centred and aligned to within
metres. Random proposals essentially never are, and small islands ended up with
no golf at all while every attempt failed a test it could not have passed.
`_max_half_length()` solves for the longest capsule that fits at the proposed
midpoint and angle, so containment holds by construction.

### Labelling is thresholded; blending is not

`sample()` reports `flatten` continuously, because height, sand and splat all
need the gradient — a bank that snapped between hill and shelf would be a cliff.
But "which hole am I on" is a yes/no question, and answering yes anywhere the
weight is non-zero puts the player on hole 3 while they are still forty metres up
the hillside above it. `zone_label_min` gates the *name*; `buildable_flatten` is
stricter still, so you can be told you are on a build pad while still too far up
its bank to found anything level.

**Both are coupled to the apron width, and the units hide it.** The weight is
`1 - smoothstep(0, apron, distance_outside)`, so a fixed weight is a fixed
*fraction* of the apron and moves in metres whenever the apron does: 0.6 was 22 m
outside a zone at a 50 m apron and would be 29 m at 65. Raise the apron and these
two have to come up with it, or "on the hole" quietly starts meaning "on the
hillside above it".

## Four things that will bite you

**1. Island disjointness.** `max_radius()` caps satellite radius against
`island_spacing` so satellite land discs can never overlap:

    2 * max_radius * (1 + coast_irregularity) < 0.7 * island_spacing

This is load-bearing: the mesher builds each island from its own disc alone, and
two touching islands would blend two different base altitudes across one
coastline and tear. Bigger satellites need proportionally wider spacing.

The hub is placed by hand and is far wider than a cell, so nothing structural
protects it — satellites landing within `hub_clearance` of it are rejected
outright. The test checks both.

**2. The fog floor.** Cliff depth is `radius * cliff_depth_ratio`, proportional
because no fixed depth serves both sizes — 800 m under a 200 m satellite is a
dramatic spike and the same 800 m under the 1250 m hub is a shallow plate you
look straight across. But a proportional depth would put the hub's tip 5 km down,
which is pure waste (it is all inside solid fog) and gives every coastal chunk an
AABB too tall to frustum-cull. So cliffs stop and cap at `cliff_cutoff_y`.

The band is bracketed from both ends, and `tests/TEST_island_world.gd` asserts
both against the shipped material:

    cliff_cutoff_y  <  fog_bottom  - 150 m      (cliff bottoms dissolve)
    -vertical_spread  >  fog_top                (lowest islands stay visible)

Defaults are a **-200 / -320** band against a -600 cliff cut and a **±90 m**
island altitude spread — 280 m of tail below full fog and 110 m of clearance on
the second inequality. **The margin matters as much as the sign.** A cut a metre
under `fog_bottom` satisfies the inequality and still shows you a cliff that
visibly terminates; 200 m of tail below full fog is what makes it dissolve.
Break the first and you see the flat cap where the underside was sliced off;
break the second and the lowest islands generate inside the haze and are never
visible.

`fog_curve` shapes the ramp and `fog_opacity_gain` is what lets it saturate.
This distinction is the whole reason the fog used to be too thin: `pow(t, 1/curve)`
reaches 1.0 **only at t == 1.0** no matter how large the curve, so the old fog
was mathematically incapable of being solid until the last metre of the band.
Raising `fog_curve` therefore never fixed it. `fog_opacity_gain` multiplies
before the clamp, so the ramp clips *strictly inside* the band: at 1.35 it
saturates at t ≈ 0.52, i.e. 62 m under `fog_top` (y = -262). The ramp itself is
linear rather than `smoothstep`, because `smoothstep` has zero derivative at
*both* ends and the first ten metres under `fog_top` contributed nothing.

Measured opacity, depth below fog onset:

| below onset | 5 m | 10 m | 20 m | 30 m | 40 m | 50 m | 62 m |
| --- | --- | --- | --- | --- | --- | --- | --- |
| opacity | 0.32 | 0.44 | 0.60 | 0.72 | 0.82 | 0.91 | **1.00** |

Distance fog is a separate three-knob term: a clear bubble
(`fog_distance_start`, 700 m) that nothing inside is touched by, a density, and
a power ≥ 1 so the falloff accelerates outside the bubble. One density could not
do the job — strong enough to erase an island at 2 km also greys out the fairway
under your feet. Clear to 700 m, 0.42 at 1250 m, 0.89 at 1800 m, 0.997 at
2500 m: fully gone a kilometre before `view_distance = 3600` unloads anything,
so nothing pops.

### Fogged geometry must not stay a lit surface

The single most important line in the fog block, and the one whose absence made
every previous tuning pass fail:

```glsl
SPECULAR = 0.5 * (1.0 - fog);
```

Zeroing `ALBEDO` and writing `EMISSION` does **not** make a fragment unlit.
`SPECULAR` defaults to 0.5 — an f0 of 0.04 — and that 4% still catches the sun
and the sky reflection (the scene runs `reflected_light_source = SKY`) and is
*added* on top of the emission. Four percent sounds ignorable and is not,
because of the palette LUT: the void sky sits dead centre of entry `0x11` with
only ~0.0017 of scene-linear headroom before it snaps to `0x22`, and the leaked
specular is several times that. "Fully fogged" rock rendered one whole palette
entry brighter than the sky behind it — **34/255 against 17/255, twice the
brightness**. That was the silhouette, and no density could ever have fixed it.

Recorded as **refuted**: Filmic tonemapping was the prime suspect. It does the
opposite (`filmic(0.089) = 0.148`), monotonically, and the sky goes through the
identical tonemap — tonemapping alone cannot create a silhouette.

### Two fogs, because one cannot do it

The terrain shader's fog is a **per-fragment altitude lookup, not a
participating medium**. It has no view ray in it, so it cannot bury anything:
drop the camera below `fog_top` and every island above you is perfectly crisp,
because each fragment is painted purely by its own world Y. That is why the
`deep_below` viewpoint stayed legible no matter what the band did.

The Environment's **height fog** closes that gap, and it is wired in
`SCENE_test_zone_W.tscn`: `FOG_MODE_EXPONENTIAL`, `fog_density = 0.0006`,
`fog_height = -200` (the same altitude as `fog_top`, so the two turn on at one
line), `fog_height_density = 0.055`. It integrates along the ray, so being under
the cliffs means being behind hundreds of metres of it. It is also the only fog
that reaches anything that is *not* terrain — the ball, vehicle parts, the build
lattice, thruster FX, the exit marker, and anything added later.

`fog_light_color` is 0.089, the sky's own value. `fog_sky_affect`,
`fog_aerial_perspective` and `fog_sun_scatter` are all **0**: the sky is already
the fog colour so fogging it double-counts, and the other two tint, which the
palette LUT turns into a coloured stripe.

Probed empirically under `gl_compatibility` before being relied on, because it
decides whether a whole class of fix exists: exponential depth fog matches
`1 - exp(-d · density)` to under 1%, height fog matches
`1 - exp(-(fog_height - y) · height_density)` exactly, and `fog_light_color` is
sRGB→linear converted by the engine. Volumetric fog was *not* tested and is not
proposed — Compatibility has none.

### The measured palette table

Consult this before choosing **any** new grey in this world. Uniform exact-neutral
input → palette entry, through the real pipeline (sky material, Filmic, glow 0.5,
16-level LUT):

| linear in | screen sRGB | LUT entry |
| --- | --- | --- |
| 0.050 | 0.0039 | `0x00` |
| 0.070 | 0.0353 | `0x11` |
| **0.089** | **0.0667** | **`0x11`** (dead centre) |
| 0.100 | 0.0824 | `0x11` |
| 0.120 | 0.1137 | `0x22` |
| 0.141 | 0.1451 | `0x22` |
| 0.170 | 0.1882 | `0x33` |
| 0.240 | 0.2941 | `0x44` |
| 0.666 | 0.7961 | `0xcc` |

**Rule: any exact neutral in 0.069–0.107 is pixel-indistinguishable from the void
sky. 0.108 and up is a visible hard step.** The old `fog_color_high` of 0.141 was
a full entry brighter than the sky it was supposed to dissolve into, and since
`fog_col = mix(low, high, 1 - depth_t)` and distant island tops have
`depth_t ≈ 0`, distant islands never disappeared — they were *repainted as pale
grey blobs* against a darker sky. Both fog colours are now 0.089.

### The 2D cloud decks

A cloud **sea** below the islands and a cloud **ceiling** above them, each a
single 12 km horizontal quad running `shaders/SHADER_cloud_plane.gdshader`. The target
is Hexen's scrolling sky bitmaps, not modern volumetric puffs; Compatibility has
no volumetrics anyway and this runs on a Broadcom V3D, so two textured
full-screen passes is the entire budget for "there is weather here".

Three decisions carry the read, and each is load-bearing:

1. **The two noise layers are combined by difference**, not multiply or max.
   Subtraction produces re-entrant iso-contours: holes open inside a cloud mass
   and tendrils peel off its edges. Multiply and max only ever darken, which
   unions the layers into blobby soup with no interior structure.
2. **The coverage edge is hard** (`cloud_softness` ≈ 0.035 of field range), so a
   cloud has a boundary you could trace.
3. **The interior is quantised in the shader**, not left smooth. `post_dither`
   would band a smooth ramp anyway — but banded by *screen* luminance, so the
   bands would sit still while the shapes scrolled underneath them, which reads
   as a broken shader. Quantising here locks the bands to the cloud field so they
   travel with the shapes.

**Each deck carries two pairs of greys, picked by `FRONT_FACING`.** A deck is a
horizontal plane drawn `cull_disabled` and `unshaded`, so it is seen from both
sides — you fly above the ceiling and below the sea, and the fly camera boosts to
3000 m/s — and the two sides do not look alike: a cloud top is the brightest thing
in an overcast sky and an underside is the darkest. `unshaded` means no light will
do that for you, so the material states both explicitly. `PlaneMesh` has its
normal on +Y, so `FRONT_FACING` is true when you are looking *down* at a deck.
The coverage field and the quantised bands are identical on both sides — a cloud
is the same cloud from underneath — and only the two endpoints it is painted
between swap, so shapes stay put as you pass through a deck.

With one pair this was plainly broken: the ceiling's values are chosen for viewing
from beneath, so flying over it painted a dark smear across the entire world and
the `high_above` shot was a near-black frame with the islands invisible behind it.
The shipped values are ceiling 0.30/0.62 from above and 0.055/0.141 from below,
sea 0.089/0.267 from above (0.089 being the terrain's fog colour, so the deck
emerges *from* the haze) and 0.055/0.141 from below.

Only two of the seven harness viewpoints sit outside the decks — `high_above` at
y = 950 and `deep_below` at y = -520 — so those are the only two shots the
side-swap can affect, which is what makes it cheap to verify. Note that the decks
scroll with `TIME`, so no two runs are pixel-identical; judge a regression by
whether a shot moves more than the ~0.004 of frame-mean that cloud phase alone
accounts for.

**The grazing term saturates opacity, and must not manufacture coverage.** Alpha
is `cov * mix(base_opacity, 1.0, thick)`, deliberately not the more obvious
`mix(cov * base_opacity, 1.0, thick)`. Written that second way a hole in the
cloud keeps `a = thick` instead of 0, so every gap gets veiled in
`cloud_color_dark` at *every* angle, straight down included. That was invisible
for as long as the ceiling's dark endpoint was 0.055 — the veil composited to
0.087 over the void, inside the 0.069–0.107 window where nothing is
distinguishable from sky — and became glaring the moment the top-side pair went
to 0.30/0.62: 0.120 at nadir, 0.161 at 20°, a whole palette entry above the sky
and then two. Measured in `high_above`, the void seen through the gaps was 28% of
the frame at `0x22` against 3% still at the sky's `0x11`; corrected, that is 27%
at `0x11` and the islands are visible through the holes again.

Coverage saturation is a separate mechanism and was always handled correctly:
`thr` collapses toward 0 as `thick` approaches 1, so at grazing angles `cov` goes
to 1 across the whole field and the sheet still closes up solid edge-on. Only the
opacity half ever belonged on that line.

**UVs come from world position, not the mesh UV**, and the quads chase the camera
in **XZ only, never in Y**. Y is the whole point of a deck — it is what makes the
sea a floor and the ceiling a lid. XZ following is invisible precisely because
the UVs are world-anchored: sliding the quad sideways moves no cloud, and the
only thing that follows you is the 5 km rim fade ring. `world_offset` re-anchors
that field to the *logical* frame after a floating-origin rebase, or the whole
sky would reshuffle the instant the origin snapped.

The deck converges to `horizon_color` and goes fully **opaque** at the rim before
its alpha is dropped. Opaque-and-exactly-sky-coloured is invisible *and* it
occludes the far rim of the other deck and any island the streamer has not
dropped yet; fading to zero instead would put those back on screen.

**`sea_altitude` is -212, and that number is coupled to the fog ramp.** The ramp
saturates at y = -262, so the -300 the script defaults to would put the deck 38 m
*below* the altitude where cliffs have already dissolved completely: rock would
vanish into haze and the deck would then reappear beneath it as a separate object
with a gap of nothing between them. At -212 the cliff is only ~47% fogged where
it meets the deck, so rock still reads as rock plunging into cloud. The decks are
not touched by either fog (`fog_disabled`, and the terrain fog is a terrain
shader), so nothing else will paint that transition for you.

**3. Curvature must be measured at a fixed WORLD distance.** Curvature drives the
splat. Read it off the vertex grid and it scales with the grid, so a chunk
reclassifies its surfaces the moment it changes LOD: distant grass turns grey and
pops back to green as you approach. The mesher uses grid neighbours only while
the grid is finer than `curvature_radius`, and asks the field directly at coarser
LODs. `tests/TEST_island_world.gd` asserts the surface mix holds across LODs.

**4. The grey sky needs its own palette.** `SHADER_post_dither.gdshader` snaps every
pixel to the nearest palette entry, and a palette with a sparse grey ramp has
luminance bands where a *tinted* entry is the nearest match to a neutral input —
which paints a coloured stripe across the sky. `allstars` was the best of the
shipped palettes by that measure but still had one bad cell (grey 68 → `#3d324f`,
a purple), and it was plainly visible at the horizon. `data/palettes/PALETTE_allstars-void.hex`
was the first fix: allstars plus one neutral per LUT quantisation level.

`data/palettes/PALETTE_ps1-soft.hex` is the project default now and it satisfies the same
constraint by construction rather than by patch. It is snapped to the PS1's
15-bit grid, so every channel is a multiple of 8 and there are 32 levels of each
— and its first 32 entries ARE that grey ramp, `000000` through `f8f8e8`, split
toned but neutral through the middle. The worst gap anywhere in its luminance
ladder is 8/255, so no neutral input has far to travel to find a neutral entry.
The remaining 480 are 15 hues x 4 saturation tiers x 8 brightness steps, built in
Oklch with a chroma ceiling near half the sRGB gamut edge.

Rebake either one, or any `palette/*.hex`, with:

    python3 tools/TOOL_build_palette_lut.py --palette palette/<name>.hex \
        --output data/palettes/LUT_<name>.png

and regenerate `PALETTE_ps1-soft.hex` itself (to move hues, tiers or the ceiling) with:

    python3 tools/TOOL_build_ps1_palette.py

If you swap palettes, re-check the grey-ramp property above before trusting the
sky.

Related: the sky colours are deliberately exact neutrals (r == g == b) and the
terrain's fog colours are matched to the sky's lower half, or distant cliffs
resolve against the sky instead of dissolving into it.

## Frustum culling

Godot culls per `VisualInstance3D` against its mesh AABB, so on a chunked world
the AABB *is* the culling — and a cliff makes a rim chunk's bounds enormous. Each
cliff column sweeps from its coastline point to a tip on the island's centre
axis, hundreds of metres down, so a rim chunk's cliff bounds reach all the way to
the middle of the island. Measured on the hub: coastal chunks averaged **169x the
volume of a 128 m cube**, up to 1556 m across and 629 m tall.

That is honest — the geometry really is that spread out — but while the surface
and the cliff shared one mesh, the *walkable ground* inherited those bounds too,
and 162 of the hub's 387 chunks were effectively never culled.

So the mesher reports `aabb_top` and `aabb_cliff` separately and `SCRIPT_island_world.gd`
builds two `MeshInstance3D`s. The surface then culls on its own footprint (185 m
diagonal, 36 m tall — the same as an inland chunk) and only the cliff carries the
oversized box. They were already two surfaces, i.e. two draw calls, so the split
costs nothing to draw. The cliff node is parented to the surface node purely so
one `queue_free()` drops both; culling ignores the parent and tests each
independently.

Tightening the cliff's own bounds would mean not converging every column on one
shared tip, and that convergence is what makes the underside watertight without
chaining coastline into loops. Not worth trading.

## Streaming and LOD

**LOD is per chunk**, which the hub forces: stand on a 2.5 km island and the
distance to it is zero, so a single per-island LOD would try to mesh the whole
thing at 2 m spacing. That reintroduces seams in two very different sizes:

- **Height mismatch** along a shared edge. The LOD grids nest — halving the cell
  count doubles the step — so both chunks agree on the points they share and only
  the finer one's in-between vertices deviate. Centimetres to a metre or two, and
  the skirt in `SCRIPT_chunk_mesher.gd` covers it. Tested.
- **Contour mismatch**, where the coastline lands in a different place at two
  resolutions. Not survivable: the cliff hangs off the coastline, so a few metres
  of disagreement opens a slit running hundreds of metres down the cliff face
  with sky visible through it.

So every chunk containing coastline is pinned to `coast_lod` regardless of
distance, and only chunks certainly inland float their LOD. That costs less than
it sounds, because the shore ramp drives relief to zero at the coastline — the
ground there is nearly flat, so coarse sampling loses almost nothing. A chunk
with no coastline is entirely land, so its edges are solid ground and the skirt
always suffices where it meets a pinned neighbour. The classifier is a cheap
annulus test followed by a grid probe, computed **once per island**; the test
asserts it catches every chunk that actually produces cliff geometry.

STREAMED meshing runs on `WorkerThreadPool` (each task gets its own
`IslandField.clone()`; never share one across threads). Work is dispatched
**nearest-first** with a cap on in-flight builds — this is a priority mechanism,
not just a throttle. The hub alone offers ~400 chunks, and handing them all to
the pool at once means it works through them in submission order while the ground
under your feet waits behind the far rim.

The UP-FRONT build does not, and must not. `prewarm` and `pregenerate` run
long-lived LANES rather than one task per chunk, and a lane that runs for a minute
does not share a pool thread — it owns one. Two lane pools sized from the core
count (the terrain's and `veg_scatter`'s) left Godot's pool with no free thread at
all, and the pool is not ours: **Jolt queues its physics jobs there**, so its
fixed pool of job records drained and `PhysicsServer3D`'s step blocked the main
thread for the whole build. One frame of 46 seconds behind a loading screen that
had stopped drawing, with the world finishing perfectly underneath. The lanes live
on threads of their own now — `scripts/world/SCRIPT_build_lanes.gd` is the whole
argument, and `tests/PROBE_w3_load_frames.gd` is what measures it.

Measured build cost for one 128 m chunk: roughly 35 ms at 2 m spacing, falling
about 4x per LOD level.

### The ladder

    LOD      0     1     2     3     4+
    cells   64    32    16     8      4
    metres   2     4     8    16     32
    to (m) 160   400   900  1800   beyond

**`chunk_cells` is quadratic and it bites.** It went to 128 (a 1 m LOD 0) to give
the deepened bunkers something to be carved into, and came straight back: a
128-cell chunk is 32k triangles, four times a 64-cell one, and the ring of them
around the camera dominated the frame budget on its own. 2 m is still half
`curvature_radius`, so a 34 m bunker is seventeen vertices across — the depth
reads fine, it never needed metre spacing.

**`coast_lod` is the most expensive number here**, and the least obvious. The
coastal ring is pinned by GEOMETRY rather than by distance, so every chunk in it
pays whatever that says, everywhere, forever — and on the hub the rim ring is
most of the island's geometry. It is the first thing to check when the triangle
count is too high, before `chunk_cells` and long before `lod_distances`.

**Keep `chunk_cells` divisible by 2^N** for the deepest level N you stream, or
the grids stop nesting and the shared edges stop being seam-free. A plain power
of two is the easy way to stay safe; `TEST_island_world.gd` asserts it, along
with the bounds ascending and `coast_lod` naming a level that exists.

**And check the ladder is RUNNING AT ALL.** `IslandWorld.pregenerate` builds the
world at one uniform resolution and never rebuilds anything, which makes every
number above dead code — see "The world is PREWARMED" in
`docs/DOC_scene_w2_skybox_terrain.md` for how that went unnoticed at ~2.2M triangles.
`prewarm` is the setting to reach for instead: it meshes every rung of the ladder
up front and caches them, so the numbers above still decide what gets DRAWN, they
just stop deciding what gets built while the player is playing.

## The bake: chunks that outlive the scene that built them

> **The round trip this was built for no longer happens.** A fight now holds the
> field rather than reloading it (§8 of `DOC_glitch_blob_encounters.md`), so
> nothing is torn down and there is nothing to rebuild on the walk home — holding
> the island and letting it go cost single-digit milliseconds each. The bake is
> not obsolete: it is what makes **entering** the zone an install rather than a
> generation, on the first load of a session and on every genuine scene change,
> and `tools/TOOL_bake_world.gd` and the World Baker dock exist to put one on
> disk ahead of time. What follows is the measurement that motivated it, and it
> is still what the numbers say about meshing this island.

`prewarm` stops the world being meshed *while you play*. It does nothing about
the world being meshed *again*, and W3 used to do that on a schedule: the
encounter loop ended a fight with `EncounterFx.return_to_field`, which was a
`change_scene_to_file`, so the field was built from nothing on the walk home. The
chunk cache above is `_islands[cell]["cache"]` — instance state on the node, dead
with the scene.

Measured headless with `tests/PERF_w3_reentry.gd`, before any of this existed:

| | prewarm | wall |
|---|---|---|
| entering the zone | 1,328 chunks, 415 MB | 139.1 s |
| returning from a battle | 1,328 chunks, 415 MB | 91.0 s |

The same island, twice, for the same megabytes. (The second is cheaper only
because the process is warm.) So **every won fight in W3 cost a full world
generation** — and on a 2.5 km hub at `view_distance = 3600` that is the most
expensive thing the game does.

`AUTOLOAD_terrain_bake.gd` holds the chunk across the swap, keyed on what the
geometry is a function of. Same harness, with it:

| | prewarm | wall |
|---|---|---|
| entering the zone | 1,328 chunks, 415 MB | 136.6 s |
| returning from a battle | 1,328 chunks, **0 MB** | **4.5 s** |

The 0 MB is the proof rather than the seconds: that is `prewarm_budget_mb`'s
vertex counter, and it says not one vertex was built. (Wall clocks on this
container swing by 40% run to run — llvmpipe on a shared box — so compare the
counters, and compare seconds only within one sitting.)

### What is stored: the resources, not the arrays, and not the nodes

**The mesher is the cost, so a hit is worth having.** A chunk at
`chunk_cells = 64` is 65x65 field samples, each an FBM evaluation, and W3 builds
1,328 of them — about 5.6 million samples on worker lanes. Building the same
world with `generate_collision` off, which drops every `ConcavePolygonShape3D`,
did not shorten the prewarm at all: the shapes are not where the time goes.

**Nodes cannot outlive their scene.** An installed chunk is a child of its
island's holder and is freed with it, so keeping nodes would mean pulling every
one out of the tree on the way down and hoping nothing else held a reference.

**The resources inside them can.** An `ArrayMesh` and a `ConcavePolygonShape3D`
are RefCounted — owned by whoever holds them rather than by a tree, and *shared*
rather than copied. So the store holds those: `_built_of` turns the mesher's
arrays into the surface mesh, one mesh per cliff band, and the collision shape,
and `_node_from_built` wraps whatever comes back in fresh instances. The mesh a
live scene's `MeshInstance3D` points at is the same object the store points at,
so **while the field is up the store costs nothing beyond what the scene was
already paying**, and when the field goes down it is the only thing still
holding them.

The first version stored the mesher's raw output arrays instead. It worked, and
it cost twice: `ArrayMesh.add_surface_from_arrays` copies what it is given into
mesh buffers, so every chunk was resident as arrays *and* as a mesh built from
them. `tests/PROBE_bake_footprint.gd` measured the arrays at 445.9 MB — data
that had been transient before the bake existed. Three A/B runs of
`PERF_w3_reentry.gd`, arrays versus resources:

| | peak RSS | re-entry prewarm |
|---|---|---|
| holding the arrays | 1,030 / 1,032 / 1,029 MB | 2,077 / 2,150 / 2,609 ms |
| holding the resources | 852 / 831 / 839 MB | 815 / 863 / 1,025 ms |

**~190 MB back, and the re-entry about 2.5x quicker** — quicker because a hit
now skips building the mesh and the shape as well as skipping the mesher. (Peak
RSS is sampled from `/proc` while the harness runs; the two builds overlap in it,
which is the case that matters.)

**Nothing world-specific goes in.** Materials, `cast_shadow`, the
`cliff_visible_depth` cutoff — all decided per instance by `_node_from_built`,
from the world's own exports, every time. Retuning any of them takes effect on
the next load without invalidating one chunk of geometry.

The store holds 1,908 entries for W3, which is 1,328 built chunks and 580 that
mesh to nothing. That second number has to be storable as an answer or the void
around the island is re-meshed on every load forever.

### The signature is the whole safety argument

A store that misses when it should hit costs a rebuild you notice. A store that
**hits when it should miss** hands the world geometry built from settings it no
longer has — terrain disagreeing with its own collision, a coastline in the
wrong place — and it does that on the *second* load, so the first look at any
change you make is a look at the world from before it.

So `TerrainBake.signature_for` takes two kinds of thing, and the asymmetry is
deliberate:

- **The field is walked whole** — every `PROPERTY_USAGE_STORAGE` property it
  has, whatever they are today. `IslandField` is a big resource that grows new
  knobs, every one of them feeds the height function, and a hand-kept list is a
  list somebody adds a field to and forgets.
- **The world's contribution is declared**, and it is one number: `chunk_size`.
  `ChunkMesher.build` is handed the field, the island, the chunk corner,
  `chunk_size`, `cells` and the pivot; everything but `chunk_size` is either
  field-derived (hashed) or already in the bake key, which carries the cell, the
  chunk and the resolution.

**The LOD ladder is deliberately absent.** `chunk_cells`, `min_chunk_cells`,
`lod_distances` and `coast_lod` decide *which* resolutions get built and when
they swap, never what a chunk at a given resolution looks like — and the
resolution is in the key. Hashing them would bin the store every time somebody
nudged a swap distance, for a rebuild producing the vertices it just discarded.
Walking `IslandWorld` whole would do the same for materials, shadow flags and
`view_distance`.

**The generation code is in the signature too**, which is the half no settings
hash can see. Nothing about hashing settings will notice an edit to
`SCRIPT_chunk_mesher.gd` or to the height function in `SCRIPT_island_field.gd`,
and a store held across one is the one way this can serve geometry that no
longer matches the game. So `signature_of` folds in a SHA-256 of both files:
edit either and the store invalidates itself, on the same run, with nobody
asked to notice.

That used to be `BAKE_VERSION` plus a table of digests in
`tests/TEST_terrain_bake.gd`, and a failing test telling a human to make a
judgement call. It worked and it was still a human in the loop on a mechanical
question. The test now checks the MECHANISM instead — that the digest reaches
the signature at all, that an edited file is a different digest, and that
neither source preloads a third script the list does not name, which is the one
failure hashing cannot catch by itself. A comment-only edit invalidates too,
which is the right way round: it costs one rebuild and the other error costs a
world.

`BAKE_VERSION` stays for what a digest cannot see — a change to the **shape of
what is stored**, which is a decision about the store rather than about the
generator, and which a bake read back off disk by newer code has to be able to
refuse.

The same test asserts the one structural assumption the walk makes: **the field
holds no `Resource` of its own.** `var_to_str` of a Resource is its *path*, so a
nested noise or curve would hash identically however it was retuned — a silent
stale world arriving the day somebody adds a perfectly reasonable export.

### The other half: the forest

The terrain came back for nothing and the player still waited. Measured to the
frame the loading screen actually lifts — which is the number that matters, and
is not `pregen_finished`:

| | terrain | vegetation | screen up |
|---|---|---|---|
| entering the zone | 85.8 s | 97.8 s | 98.9 s |
| returning from a battle | 2.0 s | 42.8 s | **43.7 s** |

Forty-one of those forty-four seconds is `veg_scatter`'s prescatter planting
481,522 plants off a 4 m grid — the identical set it planted on the way in, from
the identical field. "The terrain is regenerated after a battle" is what that
looks like from outside, and it is not wrong about the wait.

`AUTOLOAD_veg_bake.gd` is the same store with a different payload: tile key to
the packed MultiMesh instance buffers, one `PackedFloat32Array` per sprite
variant, plus the plant count, the height band and the render-space origin they
were packed against. That last field is not bookkeeping — `_install_tile`
already compares it and patches the drift three floats at a time, because a tile
can land after a rebase moved the world under it, and a tile out of the store is
the same case. So a bake taken either side of an origin shift installs correctly
with no code that knows the store exists.

| | terrain | vegetation | screen up |
|---|---|---|---|
| returning from a battle | 1.9 s | 1.3 s | **4.6 s** |

Two things differ from the terrain's store and both are in
`AUTOLOAD_veg_bake.gd` at length. **The scatter is walked, not declared:** its
world contribution is forty-odd exports of which about thirty move a plant, so
`BakeStore.exports_of` walks what the script declares (`Script.get_script_property_list`
narrowed to `STORAGE`, which is exactly the `@export`s and none of the Node3D
built-ins) rather than trusting a hand-kept list. **There is no "empty"
answer:** a tile that grows nothing still produces a full record, so "held" is
the only question there is.

And one thing that is neither: the store hands out its own **list**. A
`PackedFloat32Array` is copy-on-write, so the 31 MB is shared with the scene and
costs nothing twice — but `Array` is a reference and `_shift_bufs` writes back
into it after a rebase. Share the list and a rebase in the scene silently moves
the store's plants while its `off` field still names the old origin, and every
tile out of it from then on lands a rebase away from the island.

### What it is not

**On disk, when somebody has run the tool.** The store in memory dies with the
process, so the FIRST entry to a zone in a session pays full generation —
96.5 s on W3 — and the same ninety seconds is paid by every run of the game for
a world that has not changed since the last one.

`tools/TOOL_bake_world.gd` writes it down. It stands the real scene up, lets it
build itself exactly as the game would, and saves what the two stores ended up
holding; the game finds the file on its next cold start through
`BakeStore.open_with_disk`. `addons/world_baker/` is the same tool with a button
on it — it runs this one in a separate headless process and shows a bar, so
nobody has to keep a terminal open for five minutes to find out whether it
hung. Measured end to end on the reference container:

| | terrain | vegetation | screen up |
|---|---|---|---|
| cold, nothing baked | 85.8 s | 97.8 s | 98.9 s |
| cold, pre-baked | 3.7 s | 2.9 s | **6.5 s** |
| back from a battle | 1.9 s | 1.2 s | **4.5 s** |

The bake is 93.8 MB of terrain and 10.0 MB of vegetation, Zstd through
`FileAccess.open_compressed` — the mesher's arrays come back to about 21% of
their size, because float data that describes a surface is enormously more
predictable than float data in general.

Three things are worth knowing before touching it:

- **What is held cannot be written.** An `ArrayMesh` is not a Variant, and the
  way to get its contents back is a readback off the rendering server per
  surface. So the terrain store writes the mesher's *arrays* and runs
  `built_of` again on load, which is why `record_arrays` exists: the arrays are
  446 MB the game has no reason to keep, and the tool is the only thing that
  sets it. `VegBake` holds plain data and needs none of this — that split is
  what `_encode_entry` / `_decode_entry` are.
- **The collision soup is not in the file.** It is unindexed — three vertices a
  triangle, nothing shared — so it is roughly the size of everything else put
  together, and it is a gather off indices that are already there. It is
  rebuilt on load, *for the chunks whose key asked for one*: a shape is what
  makes `_node_from_built` create a `StaticBody3D`, so handing one to a far-LOD
  chunk would give the physics server a collider the world never wanted.
- **`user://bake` by default, not `res://`.** A hundred megabytes reproducible
  from two files and a seed is a cache, not an asset. Pass
  `--dir=res://data/bake` to ship one — `READ_DIRS` puts `res://` first, so a
  deliberately committed bake beats whatever is in a user directory.
- **A bake run refuses to read a bake.** `BakeStore.refuse_disk`, set by the
  tool and by nothing else. The signature of a world you have not changed is the
  same signature, so the file a rebake is about to overwrite is a file it would
  otherwise *find and open* — and a store filled from disk holds what a store
  filled by the mesher does not, since the arrays only exist for a chunk this
  process meshed. Every adopted chunk then encodes to nothing. Left alone, a
  rebake replaced 93.8 MB of terrain with 2 kB of empty-chunk markers, which is
  a file that matches its signature and answers every chunk with a miss: the
  world comes up empty and the bake says it is correct.

  `save_to` is the second, independent guard. It writes beside the destination
  and renames over it at the end, and **refuses a short write** rather than
  warning about one, so a disk that fills, a process that is killed, or a store
  that has nothing to write all leave the previous bake where it was.
  `TEST_bake_disk.gd` puts a good file in the way and checks it survives.

`--check` answers "is the bake on disk current?" without building anything,
exiting non-zero when it is not, because the signature is knowable from the
settings and the source digests alone.

**Uncapped, which is safe for a bounded world and would not be for an endless
one.** `ISLANDFIELD_hub_solid.tres` is one hub in a void, and what the store
holds is what the live scene holds anyway — so on a pregenerated zone it settles
at the prewarm and stops. `PROBE_bake_footprint.gd` walks a camera 3.1 km across
W3 and the store does not gain a single chunk, because `pregenerate` already
built every chunk in range at one resolution and there is nothing left to ask
for. A *streaming* field would grow it without limit, and would want a budget
here before it wanted this at all. `IslandWorld.bake_cache` turns it off.

**Shared between zones that share a field.** The signature is over the field's
values and `chunk_size`, not over the scene, and W2 and W3 both point at
`ISLANDFIELD_hub_solid.tres` with the same chunk size — so they hold *one* store
between them. `PERF_w3_reentry.gd` builds W2 as its third phase to check that
rather than assume it: after W3 has been built, W2 comes up in **550 ms and
0 MB**, against 47 s for the cold build of the same island. Walking from one
zone into the other costs no terrain at all. Change either scene's field or
chunk size and they simply stop sharing, with no other consequence.

## The rim rounds over: a shoulder in the surface, a banded wall under it

`chunk_mesher._build_rim` sweeps each coastline segment down a profile with two
halves, and puts the two halves in **different meshes**.

**The shoulder** leaves the shore at `IslandField.cliff_shoulder_angle` (18°) and
steepens asymptotically to vertical over `cliff_shoulder_height` (28 m). The
curve is an exponential in the cotangent:

```
cot(theta(d)) = cot(theta_0) * exp(-d / L)      L = height / SHOULDER_SPANS
r(d)          = r0 + S * (1 - exp(-d / L))      S = L * cot(theta_0)
```

so the angle approaches vertical and never reaches it, and `dr/dd` is positive
and shrinking — the lip **flares**, steadily and by less and less, until it is a
wall.

**The sign is the thing to get right**, and the first version had it backwards.
A surface that descends while moving *inward* is an UNDERCUT: its outer face
points at the ground, sees no sun, and renders blue under sky ambient — measured
at rgb (66, 54, 72) against a swept cone that measured (86, 83, 62). A fillet
runs the other way. Round over the edge of a cylinder and the arc goes from the
top face down and *out* to meet the wall: radius grows with depth and the normal
swings from straight up to straight out, which is what makes a shoulder read as
one.

The cost is that the island is ~10 m wider just below its shore than at it, so
the wall stands a little proud of the turf line — which is what a weathered cliff
edge looks like anyway, and is why the coastline itself did not have to move. A
true fillet on an *unchanged* top face has to put its arc outside that face; the
only alternative is pulling the walkable ground in, and every zone, scatter and
collider in the world is placed against where that ground currently ends.

`S` is capped at `cliff_shoulder_inset_max` of the island's radius, never binding
on the hub and always on a satellite; clamping the *flare* rather than the angle
is what keeps the curve monotone when it does bite.

The shoulder's vertices go into the **walkable surface's** arrays, splat weights
and UVs and all, so the lip is drawn by the terrain material. That is the point:
the rock on the lip is then the same shader sampling the same texture at the same
world coordinates as the bare-rock band on the shore above it, and the two are
continuous by construction rather than by two materials being tuned to match.

**There is no tangent matching**, and it is worth recording that this was looked
for. The plateau arrives at the coastline exactly flat, by construction:
`base_height` ramps the shore with a smoothstep, whose derivative is zero at both
ends, and `shore_width` spreads that ramp over 0.22 of the mask — 275 m on the
hub. Six metres inland the ground has risen about a centimetre. Matching that
tangent would open the shoulder at a tenth of a degree and pull the lip hundreds
of metres into the island. So the opening angle is a chosen number, and the break
it leaves at the rim is the price of keeping the coastline exactly where the rest
of the world thinks it is. At 18° against a plateau arriving at 0.1°, that break
reads as a lip. The corner it replaced was 90°.

**The wall** picks up at the handoff ring and plunges from there, still governed
by `cliff_taper` / `cliff_ring_bias` / `cliff_cutoff_y` exactly as before — just
started from the shoulder's radius instead of the coastline's. The handoff ring
is *shared*: index `sr` of the profile is both the shoulder's last ring and the
wall's first, emitted into both meshes from the same computed value, and both
copies take their normal from the same following segment. Sharing the value
rather than recomputing it is what makes a crack there impossible;
`tests/TEST_island_rim.gd` asserts the two are bit-identical.

The depth wobble moved here too. It used to be applied to the wall's drop and
faded out toward the tip; it is now spent on the shoulder's *height*, so each
column's lip rolls over at its own depth and the wall simply starts wherever the
lip finished. The rim still gets its irregularity, and the handoff becomes one
number per column used by both halves — which is why the two meshes meet exactly
whatever the noise did.

### The wall is cut into vertically stacked bands

`cliff_wall_bands` (4, clamped to at least two rings per band). Purely a culling
change — no vertex moves, only which mesh it lands in.

One mesh from the rim to the tip carries an AABB reaching from the coastline to
the island's centre axis and hundreds of metres down: measured at ~169× the
volume of the chunk's own footprint on the hub. That box intersects the frustum
from almost anywhere, so the whole sweep was submitted whenever any part of a rim
chunk was on screen — including the 500-odd metres of it the material had already
faded to nothing. Each band's box is a few tens of metres tall and the deep ones
fail the test on their own.

`IslandWorld.cliff_visible_depth` (340 m) then drops the deepest bands from the
draw outright. They are still **built**, and their faces still go into the
chunk's collider — culling decides what is drawn, and a collider that only exists
where you can see it is worse than none at all.

### Rings are only bought where the profile bends

`IslandField.cliff_wall_rings_for` scales the wall's ring budget by how much the
island's cone genuinely converges before `cliff_cutoff_y` slices it off.

The hub does not converge. `cliff_taper` deliberately holds the wall vertical
under the plateau and only closes it hundreds of metres down, and the hub's
underside is cut at the fog floor long before that — at `t_end` = 0.41, where the
raw convergence is 5%. Its wall is, to within a few degrees, a straight vertical
extrusion, and the twenty rings it used to get were twenty copies of the same
ring: **102,746 triangles across the streamed hub to describe a shape four rings
describe exactly as well.** A satellite is the opposite case — its cone fits
above the cutoff, converges all the way to a point, and keeps the full budget.

The count is computed **per island, never per column**. That is a correctness
requirement, not a saving: neighbouring columns must agree on how many rings they
have, or the wall between them is not a quad strip.

## Collision

On by default. Chunks get a `ConcavePolygonShape3D` covering the surface **and the
cliff**, so aircraft hit an island from any angle including flying up underneath.
(The rim's rock columns are a MultiMesh and carry no bodies — you collide with
the cone behind them, a few metres further in. At the speeds anything moves near
a cliff face that difference is not detectable, and giving a few thousand
instances concave shapes would be.)
The reach is well beyond the LOD 0 ring on purpose: fast movers would otherwise
outrun the streaming and pass through terrain that had not been given collision
yet.

Collision uses whatever LOD the chunk already is, rather than forcing LOD 0.
Anything close enough to walk or putt on is inside the LOD 0 ring anyway.

**Which chunks get it is decided by LOD LEVEL, not by distance** —
`_collides_at(lod)`, which is true for every level whose band starts inside
`collision_distance`. The per-chunk distance test it replaced was equivalent in
intent and incompatible with the chunk cache: a chunk crossing the collision
radius wants the same mesh with a body bolted on, which means either a second
cached variant of every chunk or a rebuild, and rebuilds are what `prewarm` exists
to abolish. Deciding on the level makes a chunk's collision state fixed at build
time. It rounds one way at the stock ladder — level 3 keeps collision to 1800 m
rather than losing it at 1400 — which costs a ring of 8 m-grid shapes.

**Swaps that move a body in or out of the tree are rationed**, at
`collision_swaps_per_scan` (2). On a prewarmed world every other install is free —
a cached node, a reparent — but giving the physics server a fresh
`ConcavePolygonShape3D` is not, and it is FIRST-TOUCH work, so having built the
shape earlier does not pay it down. Measured walking the hub, a burst of these was
a 64 ms frame while the rest of the streamer ran in 3; spread over scans it is
several ordinary frames instead of one dropped one. Raising it trades frame time
for how quickly collision catches a fast mover — the geometry is right either way,
it just arrives a scan or two later.

## Gameplay hooks

The field is a pure function, so game code can query any point without touching
the mesh:

```gdscript
var s := island_world.sample_at(ball.global_position)
if s["on_land"] and s["surface"] == "sand":
    # slow the ball — the same classifier the renderer uses, so this is
    # exactly the sand you can see
```

`sample_at()` returns `on_land`, `height`, `normal`, `slope`, `weights`,
`surface`, `forest`, `zone`, `flatten`, `hole` and `buildable`, and handles the
floating-origin conversion. `height_at()` is the shorthand.

`normal` and `slope` are taken off the **final** surface, bunker dish included —
that is what a ball rolling into a trap needs. The splat is still classified from
the pre-sand landform normal inside `sample()`, so the two never fight. `zone` is
`"golf"`, `"build"`, `"path"` or `"rough"`; `forest` runs 0 on open ground to 1
deep inside a wood.

For golf and building specifically:

```gdscript
# What can I play from here? Nearest tee first, tee/pin already in render space.
for h in island_world.holes_near(player.global_position, 2000.0):
    print("%s — par %d, %.0f m" % [h["id"], h["par"], h["length"]])

var h := island_world.nearest_hole(player.global_position)
if not h.is_empty():
    tee_marker.global_position = h["tee"]
    pin_marker.global_position = h["pin"]

if island_world.is_buildable(ghost.global_position):
    ...   # flat cleared ground, and the player can see it: it reads as bare soil
```

`hole["id"]` is stable for the life of `world_seed` and derived from nothing but
the lattice, so it is safe to write straight into a scorecard or a save file.

## Textures

`tools/TOOL_gen_terrain_textures.py` bakes eight 64×64 seamless PNGs from
periodic value noise and Worley. Deterministic. Re-run after editing:

    python3 tools/TOOL_gen_terrain_textures.py

Albedo is quantised to a short hand-picked ramp before export, so the palette LUT
does not re-band a smooth gradient into mush. Two ramp choices are load-bearing
and were arrived at by measuring against the palette rather than by eye: the sand
ramp is narrow and mid-key (a wider one runs off both ends of the palette's tan
entries — dark end to dusty rose, light end to yellow-green, so bunkers read
pink), and the grass ramp's dark end is lifted (pushing a quarter of the texture
into the darkest steps looks fine head-on but mipmaps to near-black, so distant
ground ends up darker than the fogged cliff beside it).

Imports are lossless with `detect_3d/compress_to=0` — letting Godot auto-switch
these to VRAM compression on first 3D use would destroy the pixel art.

## Filming the island

`tests/RENDER_island_flyover.gd` is `RENDER_island_shots.gd` with a moving
camera: it writes one PNG per frame of a single continuous move over W2's hub —
a Bezier flyover that merges into a 720° orbit — and `tools/TOOL_encode_video.py`
muxes the directory into an mp4.

    LP_NUM_THREADS=1 xvfb-run -a -s "-screen 0 960x540x24" \
        <godot> --path . --rendering-driver opengl3 --audio-driver Dummy \
        --script res://tests/RENDER_island_flyover.gd -- \
        --out=/tmp/fly --size=960x540 --seconds=26 --fps=30 --resume
    python3 tools/TOOL_encode_video.py --frames /tmp/fly --out /tmp/fly.mp4

Everything in the stills harness's header still applies — `-screen ...x24` and
`LP_NUM_THREADS=1` above all. Three things are specific to filming.

**The fog decides the framing, and it rules out the obvious shot.** The
environment runs `fog_density = 0.0012` against a `fog_light_color` of 0.089:
dark fog, light sky. Transmittance is `exp(-0.0012 d)`, so 500 m → 0.55,
1500 m → 0.17, 2950 m → 0.03. An orbit wide enough to hold the whole 2.5 km hub
as a disc puts the far rim near 3 km and the island renders as a **black blob**
against pale cloud — that is measured, from a first pass at r=2420 that had to be
thrown away. Fly it close and low instead (the default is r=1500, 250 m outside
the rim, at 240–540 m altitude): the near coastline reads vivid, the far side
falls into haze, and that is what the world actually looks like in play. This is
also why an external "show the whole island" shot is not available at these fog
settings and should not be attempted by pulling the camera back.

**Frames are gated on streaming, not on a sleep.** W2 prewarms, and
`_free_out_of_range` returns early in that mode, so terrain the camera drags into
range stays resident — a prepass walks the path once and the island streamer is
idle for most of the capture. The scatters are the opposite: `SCRIPT_veg_scatter.gd`
and `SCRIPT_grass_scatter.gd` free tiles behind them, so every frame waits on all three
`_pending` queues. A fixed sleep instead gets you trees flickering in and out.
Note `_stream_idle()` cannot be trusted for the first few frames after a camera
move — nothing is queued until each streamer's next `_process` — hence
`STREAM_MIN`.

**Meter the shader clock, or the sky boils.** `SHADER_cloud_plane.gdshader` and
`SHADER_horizon_clouds.gdshader` scroll on `TIME`, and `TIME` advances with real
elapsed engine time — so a harness that spends four seconds of wall clock
settling each frame bakes four seconds of cloud drift into every 1/30 s of
video, about 130× speed. The harness therefore runs the engine with
`--fixed-fps 60`, holds `Engine.time_scale` at 0 for the whole settle, and steps
it deliberately for `ADVANCE_FRAMES` frames before each grab so the clock moves
exactly one video frame. Both halves were measured before being relied on:
`time_scale = 0` does freeze shader `TIME`, and under `--fixed-fps` the clock
advances in exact `1/fps` steps. Dropping `--fixed-fps` silently breaks the
metering, so `_check_fixed_fps` makes it an error.

Note the frame-to-frame difference metric is a poor judge here — the ordered
dither is screen space, so any small change in the underlying colour flips whole
runs of pixels between palette entries and swamps the measurement. Metering the
clock took the cloud band from 13.1 to 10.2 mean absolute difference; the
residual is camera motion and dither, not weather.

**Don't move the camera before the scene enters the tree.** `pregen_anchor` is
zero on W2, which means "wherever the camera stands at `_ready`". Posing the
camera at the flyover's start first anchors the prewarm 2.3 km out past the
3.6 km view distance and it builds *nothing* — measured, "prewarmed 0 chunk
meshes". Let the scene's own camera transform drive the prewarm; pose it after.

The encoder's two choices are both about the dither. Frames are upscaled by an
integer factor with **nearest neighbour before** the `yuv420p` conversion, so
that a 1 px dither pattern — precisely the signal 4:2:0 chroma subsampling
destroys — becomes a 2×2 block the subsampler can represent; and `-tune grain`
with a low CRF stops x264 smoothing the pattern into blocking. Upscaling at
encode rather than render time also keeps the 3D cost at the native size.
