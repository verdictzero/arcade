# Burnt and burning vegetation (SCENE_test_zone_W2)

Every plant in W2 can burn. There is no second set of art, no second shader and
no extra draw call — one baked texture per sprite and one scalar.

Nothing in the scene looks different until someone moves that scalar. The bus
ships at rest.

## Status: THE CRATER COLLAR AND ITS WRECKAGE ARE LIVE; THE ISLAND-WIDE BUS IS STILL DORMANT

**Two callers now exist, and both are the crash site.** The crater stands a burning
collar of forest around its bowl and lies a field of burnt WRECKAGE inside it — the
only two things on the shipped island that move the burn stage off zero. Neither uses
the bus: both go through a per-plant burn in a MultiMesh custom-data channel
(`SCRIPT_veg_scatter.gd`/`SCRIPT_grass_scatter.gd`/`SCRIPT_stump_scatter.gd` write it,
`SHADER_veg_billboard.gdshader` reads it as `INSTANCE_CUSTOM.x`, folded in as
`max(bus, patch)`); `docs/DOC_crash_crater.md` has the detail on both.

The COLLAR has been through Godot and been looked at — the shader compiles under GL
Compatibility, the maps and ramp bind, `tests/TEST_veg_burn.gd` passes, and it has
been rendered. The WRECKAGE has been through Godot only as far as its numbers:
`tests/TEST_stump_scatter.gd` passes against the real field and the real wreck
prefab, the scene instantiates, and the look is judged from
`TOOL_gen_burn_maps.py --preview`'s `burn_wreckage.png` rather than from a frame. The five
sprites are 64x64 and 128x32 — half the ground layer's linear resolution, because
this class is 1.7 m tall and is only ever seen on the floor of one crater.

**The wreckage is the same mechanism aimed at a different question**, and it is worth
saying which. The collar asks what a LIVING plant looks like partway through a fire,
which is the sweep this whole document is about. The wreckage is art that is already
charred — no green anywhere in the source pixels — so the sweep has nothing to sweep;
what the burn stage gives it instead is the ember field, the palette cycle and the
flame band, i.e. everything that MOVES. Without a burn map those five sprites would be
flat black props standing in a crater that is otherwise alive. See
`gen_burn_maps.SPRITES` for why the same baker serves both without a special case.

**The bus itself is still dormant.** `VegBurn.burn` / `veg_stump` / the spreading
front still ship at rest, and **no scene draws a burnt pixel from THEM until someone
moves one.** That is deliberate — W2's grade, fade bands and fog are tuned to numbers
that took measuring, and the island-wide burn has not been re-measured against them.
The crater proves the stages read on a real frame at ONE burn level per plant; a whole
island passing through the fire together is a different picture and is still unproven.

**The numbers below were still set against numpy.** Every constant in this document was
produced by `tools/TOOL_gen_burn_maps.py --preview`, which re-implements the fragment
shader — the crater used them as-shipped and they held up, but the alight brightness of
a full-island burn (`ember_energy` in particular) has not been tuned against the
scene's tonemapper and bloom. Expect it to move the first time the bus is actually
driven.

So the first hour of implementing this is not tuning, it is finding out what does
not compile or bind. In rough order of how expensive each is to discover late:

1. **Does the shader compile.** It gained three `global uniform`s (`veg_burn`,
   `veg_burn_front`, `veg_stump`), a `textureSize` call, and a `hint_default_transparent`
   sampler. A global that project.godot does not declare, or a hint the compatibility
   backend rejects, takes out *every plant in the world* rather than failing quietly.
   Load W2 with the bus at 0 and confirm the island is unchanged before anything else.
2. **Do the burn maps and the ember ramp bind.** Both are resolved by PATH at
   runtime (`VegBurn.map_for`, `VegBurn.bind_ember_ramp`), so a missing `.import`
   sidecar or a renamed sprite is a plant that silently never burns. `VegBurn` pushes
   a warning naming the sprite; watch for it. White fire means the ramp did not bind.
3. **Run `tests/TEST_veg_burn.gd`.** It is the cheapest check that the maps, the
   palette, the four materials and the crater's per-instance channel all still agree.
4. **Then look at it.** Set `burn` to 1.0, then 0.55, then take `stump` to 1.0. The
   preview sheets say what each should look like. To judge one of the five burn
   characters on its own, pin it with `burn_character` — see THE FIVE BURN
   CHARACTERS below.

Expect the *numbers* to move. Ember brightness in particular was chosen against a
numpy approximation of an unshaded albedo, with no tonemapper and no bloom in front
of it — the scene has both, and `ember_energy` is the first dial to reach for.

## The pieces

| File | What it is |
| --- | --- |
| `tools/TOOL_gen_burn_maps.py` | Bakes `sprites/**/*_burn.png` (+ `.import`) from the sprites' own pixels. Also renders the preview sheets, including the labelled per-character one. |
| `shaders/SHADER_veg_billboard.gdshader` | The burn stage. Same shader every plant already used. |
| `scripts/world/SCRIPT_veg_burn.gd` | `VegBurn`: publishes the three globals, and resolves each sprite's burn map and the ember ramp for the scatters. |
| `data/palettes/TEX_ember_ramp_ps1-soft.png` | The eight palette entries the embers cycle through. Baked by the same script; bound by `VegBurn`, not by the materials. |
| `tests/TEST_veg_burn.gd` | Asserts every sprite has a map, that the maps span the full burn, that the ember ramp is a real palette ramp, and that the bus is declared and at rest. |
| `tools/TOOL_cut_chroma_key.py` | Cuts the five already-charred sprites out of the flat magenta they were drawn on, into `sprites/vegetation` sources. |
| `scripts/world/SCRIPT_stump_scatter.gd` | `StumpScatter`: the second consumer of the burn stage — the wreckage in the crater's bowl. |
| `materials/MAT_veg_stump.tres` | Its material, and the only one that sets a burn block: darker char, higher cooling, `ember_energy` 1.6. |
| `tests/TEST_stump_scatter.gd` | Its placement, its clearance against the wreck, and its burn. |

## How it works

`TOOL_gen_burn_maps.py` packs four scalar fields into one RGBA texture per sprite:

```
R  EMBER      where coals sit and glow after the flame has gone
G  CHAR       how black this texel ends up
B  ORDER      WHEN it burns, 0 first to 1 last
A  FOLIAGE    how leaf-like this texel is, 0 wood to 1 leaf
```

The shader's `burn` uniform is one number swept across the ORDER field. Every
texel crosses its own threshold at its own moment, so a plant is never uniformly
"on fire" — it has a burning band with green above it and char below, climbing
from the base into the crown and eating in from the silhouette's fringe.

The fields are **derived, not painted**. Foliage is green and wood is not, which
one chroma test separates; a texel's distance into the silhouette says whether it
is an exposed needle tip or sheltered crown; height says which way fire climbs.

**Nothing is ever eroded away.** The fourth channel used to be an ASH LOSS field
and the shader discarded against it, on the theory that a burnt plant is a thinner
plant. It is, and it did not work: a per-texel discard against baked noise is a
spray of holes rather than a plant losing its leaves, and at 128 px with
`filter_nearest` it read as a bad dissolve — worse the closer you got, which is the
opposite of what a detail effect should do. **The burn is a colour effect.** The
silhouette a plant has when green is the silhouette it has when black, and the only
thing that ever removes geometry is the `stump` break, which is a clean cut rather
than a stipple. The channel survives because that break still needs it — inverted,
so wood stands proud and leaf drops through.

A second charred albedo would have been the obvious build and cannot do any of
this: it doubles the art, has to be re-baked whenever `SCRIPT_crunch_art.gd` re-crunches
a source, and can only show the END of the burn. What reads as fire is the
transition.

## THE FIVE BURN CHARACTERS

**Where they are defined:** `shaders/SHADER_veg_billboard.gdshader`, the `VAR_SOFTNESS` /
`VAR_ENERGY` / `VAR_COOLING` const arrays. That is the canonical copy. Two mirrors
have to move with it — `CHARACTERS` in `tools/TOOL_gen_burn_maps.py`, and the table
below.

**How to look at one on its own:** set `burn_character` on the class's material.

```
# materials/MAT_veg_billboard.tres   (or _understory / _fern / _grass_billboard)
shader_parameter/burn_character = 3
```

`0` is the shipped behaviour — every plant picks its own from a hash of where it
stands. `1`..`5` pins **every** plant of that class to that character, which is how
one gets judged without the other four in the frame. The scatters duplicate the
material per sprite, so the duplicates inherit the pin; there is nothing else to
change. IDs are 1-based, arrays are 0-based, and `burn_character - 1` in the vertex
stage is the only place those two conventions meet.

**What they look like:** `python3 tools/TOOL_gen_burn_maps.py --preview <dir>` writes
`burn_characters.png` — one labelled row per character, all ten sprites, held at
`burn` 0.6 where they differ most.

| id | name | softness | ember energy | cooling | reads as |
| --- | --- | --- | --- | --- | --- |
| 1 | shipped | ×1.00 | ×1.00 | — | the material's numbers, unchanged |
| 2 | tight band | ×0.45 | ×1.00 | — | a narrow, definite seam creeping up one side |
| 3 | crown alight | ×1.80 | ×1.00 | — | most of the plant burning at once: the torch |
| 4 | hot | ×1.00 | ×2.00 | — | same shape, twice the brightness, blooms hard |
| 5 | smouldering | ×1.00 | ×0.44 | +0.10 | barely alight, mostly char with red seams |

### Why they exist and how the pick works

A fire in a real stand is ragged because the fuel is: one tree goes up like a
torch, the one beside it smoulders for an hour, a third burns as a seam creeping up
one side. Without this, a burning hillside is one effect applied five thousand
times, and every plant at a given distance from the front looks identical.

Each plant picks its character from a hash of its own position — no per-instance
buffer, no extra material, no second draw call, exactly like the sprite flip. It
costs one `flat vec3`.

Three things about the rows are load-bearing:

* **They are relative, not absolute.** Each scales or offsets the *material's* own
  values rather than replacing them, so the four materials keep control of the
  overall look. Multiply a class's `ember_energy` and all five of its characters
  move together — otherwise brightness would need retuning five times per class.
* **The pick uses a second, independent hash** off the same anchor. Sharing
  `v_seed` would tie a plant's character to its place in the burn spread, making
  every torch in the wood also an early one — a correlation the eye finds
  immediately even when it cannot name it.
* **`burn_softness` is not only a look.** It sets how much of a plant is mid-burn at
  any moment, so character 2 also reads as a *quicker* front than character 3 at the
  same `burn_rate`.

`burn_variety` (0..1) collapses the spread without pinning: at 0 every plant burns
the way its material says, which is what the shader did before the characters
existed. It is ignored while `burn_character` is pinned.

## The burnt-out set (patches)

The `burn` sweep gives a front with green above it and char below — that is a plant
**catching**. The other picture is a stand that went through the fire hours ago:
**no green left anywhere**, and fire still finding something to eat in a dozen
places at once. That is `burn = 1.0` plus `burn_patches`.

```
burn = 1.0            # nothing green survives
burn_patches = 0.45   # how much of the plant is alight at any moment
patch_scale  = 13.0   # blob size: low is a few big licks, high is a fine rash
patch_speed  = 0.35   # how fast they crawl and re-form
```

**It could not have been a stage of `burn`.** That sweep is monotonic by
construction — every texel crosses its threshold once and stays crossed — so
nothing in it can re-light a texel the flame has already passed. The patches are a
separate term added on top, and they want `burn` at 1.0 under them: at anything
less they sit on green foliage and read as fairy lights.

**The patch is modulated by the art's own luminance**, and the version without that
is what made it necessary. A noise field knows nothing about where the needles are,
so the patch came out a smooth blob laid over the silhouette and read as orange
paint. Multiplying it through the sprite's luminance puts the fire in the lit
foliage and leaves the gaps black, so the patch takes on the plant's structure
instead of hiding it.

`--preview` writes `burn_patchwork.png` — four densities across all ten sprites.
Off by default (`burn_patches = 0`), and the gate costs one compare: the two
octaves of value noise are the only per-fragment procedural in the shader, which is
why they sit behind it.

## The palette cycle

The embers are not one colour. They index an eight-entry ramp taken straight out
of `data/palettes/PALETTE_ps1-soft.hex` — the same palette `SHADER_post_dither.gdshader` puts the whole
frame through — and the index is a texel's heat plus a triangle wave, quantised to
whole steps before the lookup. Quantising is the point: it flips between real
palette colours instead of sliding through invented ones.

```
#181008  #302000  #503000  #704000  #985800  #c07820  #e89858  #f8d0a0
```

Three things make it read as fire rather than as a flashing plant:

* **The phase runs against the burn order**, so a feature sits at a fixed phase and
  travels *up* the plant as time advances — flames climbing, not a silhouette
  pulsing. `ember_cycle_climb` sets how many bands are visible at once.
* **The swing is scaled by the flame term**, so only the actively burning band
  animates hard; settled coals shimmer at a third of it and cold char does not move
  at all. That is why this lives in the vegetation shader and not in a screen-space
  palette pass — "actively burning" is a per-texel quantity here and nothing
  downstream knows where the fire is.
* **The ramp entries must come from the palette, be distinct, and climb.** Off-palette
  and the post LUT moves a rung onto its neighbour; repeated and the cycle stalls
  for two steps; dipping and it runs backwards in the middle. The baker asserts all
  three and `tests/TEST_veg_burn.gd` re-checks them against the shipped PNG. The
  first version of the baker snapped eight idealised colours independently and two
  of them landed on `#c07820`.

It ends on gold rather than white on purpose: the index is heat and the baked ember
field is speckle, so a white top entry turns every speckle into a star. White-hot
still happens, from **intensity** — the ember term multiplies this ramp and
routinely exceeds 1.0, which is what the environment's glow blooms.

Turn it off with `ember_cycle_depth = 0`, which leaves the ramp as a plain heat
lookup. An unbound `ember_ramp` gives white fire, deliberately: there is no sane
fallback for a missing palette and a silent orange one would hide the mistake.

## Stumps

`burn = 1` is a plant that has been through the fire and gone cold, and it still
has its whole silhouette: a black fir is a fir. That is a forest that burnt last
week. `stump` is the second axis — how much of what burnt has since come **down**.

At `stump = 1` the crown is gone and what stands is wood: a broken trunk with the
stubs of its lowest branches, a charred root crown where a bush was, essentially
nothing where a fern or a tuft of grass was.

Three things make it a stump rather than a shorter plant:

* **The stub is solid, because nothing erodes any more.** This took two goes. The
  original had the ash threshold *tighten* as the plant collapsed, on the reasoning
  that a stump is wood — right about a standing skeleton, wrong about a stub, which
  came out a moth-eaten fizz with daylight through it. Relaxing the erosion below
  the break fixed that, and then removing the erosion outright made the whole
  mechanism unnecessary: what is below the break is simply the plant, charred.
* **The break line is inverted against the foliage field, and drops four times as
  far as it lifts.** That field is near zero on wood, so the line lifts over the trunk
  — the trunk stands *proud* of its break. But a lift applied out at the branch tips
  strands loose texels in mid-air, because nothing in a fragment shader knows whether
  a texel is attached to anything. Capping the up half keeps the splinter and loses
  the flies.
* **The near fade shrinks with the collapse.** That fade exists because a wood is a
  wall a metre from the eye; a stump is shorter than the player. Scaling rather
  than switching means the clearing closes as the crown comes down, and it is why
  the `_stump` materials do not override `near_gone`/`near_solid` by hand.

**A separate axis, not the end of `burn`.** Folding it in would have made `burn = 1`
stop meaning "through the fire" and put the collapse on the same clock as the
flame, which is wrong by about a year. Orthogonal, they compose: a stump still
smouldering, a fresh char that has not fallen yet, and every mixture across an
island. It is also multiplied by each plant's own burn, so pushing it on a green
forest does nothing.

`stump_height` is a fraction of the **quad**, not of the plant, so it wants a
different value per class: a fir fills its texture, a bush sits in the bottom three
quarters of a square one. The figures the previews were tuned at are firs 0.11,
bushes 0.13, ferns 0.13, grass 0.09 — set in `TOOL_gen_burn_maps.py`'s `STUMP_HEIGHT`
for the preview, and to be set on whatever material drives a stump. The firs' one
is just below the lowest branch whorl rather than rounded: at 0.13 the break landed
in tall_fir_1's widest, sparsest fan of branch tips and left a horizontal scatter of
loose texels hanging off the stub.

## Burning the island

Two globals, published by the `VegBurn` node in the scene:

* `veg_burn` — 0..1, how far through the fire the island is.
* `veg_burn_front` — `xyz` origin, `w` radius in metres. `w <= 0` means no front.
* `veg_stump` — 0..1, how much of what burnt has since come down.

A bus rather than a material because both scatters DUPLICATE their material once
per sprite, so there are ten live materials and nothing to write "the island is on
fire" onto. Same problem the `tod_*` parameters solve for the lighting.

**Everywhere at once.** Leave `front_radius` at 0 and move `burn`. The shader's
per-instance variance still spreads neighbours out, so a hillside catches plant by
plant rather than wiping.

**A spreading front.** Give `front_radius` a value and a `front_speed`. The fire
is a disc growing from `front_origin`, burnt behind, a band of flame at the edge
(`burn_front_depth`, 120 m), untouched forest ahead. 900 m from the middle clears
every shore of the 1,525 m hub.

**A burnt place in a green world.** Duplicate the class's material and pin `burn`
(and `stump`) on the copy. There is no shipped `_burnt`/`_stump` material set — there
was, and it was eight near-duplicates of the fade and fog blocks, which is eight
more places for those to drift from the terrain they have to agree with.

The stages, as `burn` / `ember_energy`:

```
0.30 / 1.6   ground fire, crowns still green
0.55 / 1.6   ALIGHT — the front is in the canopy
0.80 / 1.0   dying, the whole silhouette in coals
1.00 / 0.22  cold char
```

and then `stump` 0 → 1 on top of `burn = 1`, at `ember_energy` 0.10.

## Re-baking and previewing

```
python3 tools/TOOL_gen_burn_maps.py --preview /tmp/burn
```

Deterministic — same art in, same maps out, so re-running does not churn the repo.
Eight things come out: the five stages across all ten sprites, the four raw
channels, the collapse to stumps (whose last row is cropped to the foot of each
quad and doubled, because a fir stump is 51 px at the bottom of a cell), a fire
front crossing a stand of plants (the only one that shows the per-instance spread,
since that lives in the vertex stage), `burn_cycle.gif` —
one loop of the palette cycle on four plants held at their most alight, which is
the only one that shows the animation at all — and `burn_characters.png`, one
labelled row per burn character, and `burn_wreckage.png`.

`burn_wreckage.png` is the only sheet drawn at a material OTHER than the trees'.
The five already-charred sprites, at `MAT_veg_stump.tres`'s numbers, across the
burns `SCRIPT_stump_scatter.gd` can hand them — its middle row is the shipped 0.60 and the
rows either side are what the shader's per-instance lag reaches at that setting, so
the three together are the actual spread standing in the crater rather than three
settings one of which will be chosen. `shade()` grew `char_col`/`ash_col`/`cooling`
overrides for it; the four vegetation materials pass none of them and are unchanged.

`--preview` re-implements the fragment shader in numpy, in linear light and with
the materials' `tint` applied, because there is no Godot binary in this repo's CI
and the scene takes ~35 s to settle under xvfb even where there is one. **If you
retune the shader, retune the previewer** — a previewer that has drifted is worse
than none.

## The crash site (done — this is what shipped)

The crater floor stays **bare** — the blast took everything inside the bowl, so
there are no plants in the crater and therefore no burning ones. The vegetation
burns in a **ring outside it**, thinning back to green. That boundary is where all
the reading happens: a bare disc with a hard green edge is a decal; the same disc
with a burnt fringe is an event.

**The weight the ring needs was already computed and thrown away.** In
`veg_scatter._evaluate_cell`, `f.crater_burn(...)` is the char weight for that cell
on the real elliptical footprint, and it used to only drive a clearing roll. It is
now handed to the shader as well, which is the whole feature — and it puts the burn on
exactly the footprint the char decal is painted on, which is what sells it from the
air. The five burn characters still apply, so the ring comes out as torches and
smoulders rather than one effect stamped on every instance.

**Scaled, though — a plant must not be handed 1.0.** `crater_burn` saturates at 1
across the whole interior, and 1 in this shader is not "as burnt as possible", it is
FINISHED: every texel swept past the flame band, `flame` down to about e⁻⁹·⁸, nothing
left but coals at `1 - ember_cooling`. Handed straight to the collar it produced a ring
of cold black poles round a still-glowing crater. It was also perfectly uniform,
because `burn_of`'s lag is scaled by `amount * (1 - amount)` and that is **zero** at
1.0 — the flatness was the value, not the art. `veg_scatter.crater_burn_peak` (0.7)
stops the plants inside the fire and hands the lag back its ±0.19: 1,383 cold-ash
plants and 309 alight became **0 and 1,557**. The GROUND still sits at 1, correctly —
the impact charred it and it is done; the wood standing on it is not. See
`docs/DOC_crash_crater.md`.

**The clearing and the burn are two questions off the same sample.** The clearing
rolls on the RAW crater weight, which falls off from the middle; the burn is
`crater_burn` of it, which is pinned at 1 across the whole interior. Keying the
clearing on `crater_burn` would clear the lip as readily as the floor and leave no
collar to burn — see `crater_veg_keep`.

**And the clearing finishes AT the lip crest, not past it.** The roll used to start at
`crater_veg_keep` and ramp to certainty by `+ 0.35`, which put the fully-cleared line
at 61% of the rim radius and left plants thinning out down the crater's inner slope —
burning ferns and bushes on a wall the blast scoured to fused rock, over a molten
floor. The ramp now runs outward and completes at the crest, across `crater_veg_band`
of weight spent on the outer drift: bare from the crest in, wood from the crest out,
with the edge lobed by `IslandField.crater_wobble` rather than mown.

**Cost:** MultiMesh custom data — `use_custom_data` on, `_STRIDE` 12 → 16, +33% on
the instance buffers and on the re-pack `veg_scatter` works hard to keep cheap. No
extra field sampling; the sample was already being taken.

Measured with `PROBE_scatter_cost.gd` either side (headless, parked at 400,400 —
inland rough, nowhere near the crash site, so this is the stride and nothing else).
**The +33% is real in MEMORY and is not measurable in TIME.** Two pairs of runs:

| | stride 12 | stride 16 |
| --- | --- | --- |
| grass CACHED / FRESH | 0.68 / 0.43 ms | 0.68 / 0.43 ms |
| trees CACHED / FRESH | 3.12 / 2.24 ms | 3.19 / 2.44 ms |
| *and the other pair* | 3.79 / 3.14 ms | 3.69 / 3.00 ms |

The second pair has the wider stride coming out *faster*, which is the honest
reading: the re-pack is not what a scan spends its time on, so a third more floats
to copy disappears into the variance. Do not quote a speedup from that row either —
it is the same noise with the sign flipped.

The memory is deterministic and is the number to hold: 78,606 plants at 16 floats
is **4.80 MB against 3.60 MB**, and the ~21k resident tufts 1.29 MB against 1.01 MB
— about **+1.5 MB CPU-side, and the same again on the GPU**. `PROBE_veg_census.gd`
costs instances at this stride.

### The world-space front, and why it was not used

`veg_burn_front` is a **circle** — xyz origin, w radius — and the crater is an
**ellipse**: `crater_elongation` is 1.45, so the footprint runs ~45 m along the
ship's track and ~31 m across it. A circle sized to the long axis overshoots the
short one by about twenty metres, a third of the feature, and that reads
immediately in a plan view. Good for seeing the ring at all; not the shipping
answer — and it would also have spent the bus, which the island-wide fire still
needs.

It also inverts badly against a bare bowl. The front ramps to *full* burn deep
inside itself and to zero at its own rim:

```
amount = clamp((front_radius - distance) / burn_front_depth, 0, 1)
```

so using it at all means `front_radius` = the outer ash radius and
`burn_front_depth` = the ring width (outer minus bowl). Sized *to* the crater
instead, it puts full burn on ground that was just cleared and leaves the survivors
barely scorched — which looks like the burn is broken rather than mis-sized.
`burn_front_depth` ships at 120 m, for a fire crossing a 1,525 m island, and would
have to come down either way.

**Do not rebuild either of the two things that were removed.** The `MAT_*_burnt` and
`MAT_*_stump` pinned materials are gone (2b41a13), and so is the burn's ASH LOSS
erosion, which discarded texels as the flame passed and produced a sparse,
moth-eaten plant with daylight through it. If the ring reads as *thin* or *decayed*,
that is the failure to look for, and the fix is never to punch holes in the sprite.

## What this does not do

**The ground, ISLAND-WIDE.** A burnt forest standing on a vivid green fairway is
half a picture, and `MAT_terrain_splat_w2.tres` knows nothing about the `veg_burn`
bus. Wiring the terrain's grade to the same bus is the obvious next step and is
deliberately not in this change. (The CRATER does not have this problem: its ground
is charred by the field and its plants burn off the same `crater_burn`, so the two
already agree there — see `docs/DOC_crash_crater.md`. It is the bus-driven whole-island
burn that has no matching ground.)

**Smoke.** The plants glow, and the environment's `glow_enabled` blooms embers
over 1.0, but nothing puts a column of smoke in the sky. `shaders/smoke_particle`
exists and is not wired to any of this.
