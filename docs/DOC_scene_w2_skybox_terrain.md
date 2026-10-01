# SCENE_test_zone_W2 — procedural sky, volumetric cloud sea, jagged island, faceted terrain

`scenes/utility/SCENE_test_zone_W2.tscn` is a variant of `SCENE_test_zone_W`. It keeps the
fly camera, floating origin and dither post-FX, runs its own single JAGGED-island
field (`data/ISLANDFIELD_hub_solid.tres`), and swaps the *look* wholesale: one
faceted, flat-shaded landmass rising out of a raymarched volumetric cloud sea under
a grey overcast, lit hard by a bright directional sun.

`scenes/SCENE_island_0.tscn` is a copy of it, to fly variants without
disturbing the one this document describes. **Only the scene file is its own.**
The terrain material, the sky material, the day/night preset and the field are
still the shared `MAT_terrain_splat_w2.tres`, `MAT_sky_w2_void.tres`,
`SKYCYCLE_w2_blood_night.tres` and `ISLANDFIELD_hub_solid.tres`, as are the plant,
cliff, cloud-sea and horizon-band materials and the crash-site prefab — so
retuning any of those moves both scenes, and everything below applies to both.
Fork the `.tres` first (and tag the fork `_w3`) if you need them apart. What W3
already owns is what is inline in its file: the Sky, the Environment and the
dither material, the camera, the SunPivot transform, `IslandWorld`'s streaming
knobs, every scatter's exports, and which nodes are present at all.

## What changed vs. W

1. **Procedural void-gradient skybox — the cloud panorama is removed for now.**
   - `shaders/SHADER_sky_void_gradient.gdshader` via `materials/MAT_sky_w2_void.tres`:
     the flat two-tone gradient (dark grey below a raised horizon, light grey
     above), same shader W uses.
   - This replaces the rotating cloud panorama
     (`shaders/SHADER_sky_panorama_rotating.gdshader` + `MAT_sky_rotating_day.tres`,
     `sky/SKY_day_3_var3.png`). That material is left in the project unused so the
     panorama sky can be restored later; nothing else references it.
   - As in W there is no `CloudPlanes` node — the gradient IS the sky.
   - The sky's `bottom_color` is the exact neutral **0.30**, the value every fog
     in the scene is tuned to (see 4/6), so "empty sky at the horizon" and "fully
     fogged" are the same pixel. It was 0.089 until the volumetric cloud sea (9)
     went in underneath: against a mid-grey sea, 0.089 drew a near-black bar
     across the horizon. See *One haze value* in
     `docs/DOC_horizon_parallax_clouds.md` for the measurements and the sweep.
   - The Environment's `ambient_light_color` is neutralised to grey
     (`0.42, 0.42, 0.43`) to sit under the grey overcast — the old bluish ambient
     (`0.5, 0.56, 0.64`) belonged to the daytime panorama.

2. **Seven-layer textured terrain**, from the `textures/` photo set.
   `shaders/SHADER_terrain_splat_w2.gdshader` + `materials/MAT_terrain_splat_w2.tres`.
   **Golf zones are mown striped turf.** The four splat weights can't tell a
   groomed fairway from flat rough (both are grass = 1), so `SCRIPT_chunk_mesher.gd`
   writes zone membership into **both UV channels** and the shader resolves each
   to its own texture:

   | | `x` | `y` |
   | --- | --- | --- |
   | `UV` | golf grooming → mown fairway | build grooming → cleared earth |
   | `UV2` | forest → needle floor | path grooming → worn trail |

   UV2 exists for the same reason UV did: a wooded hillside is grass-dominant
   exactly like open rough, and a worn track is soil-dominant exactly like a build
   pad, so neither is derivable from the four weights. The stock
   `SHADER_terrain_splat.gdshader` ignores both channels, so **every other scene is
   unaffected.**

   **Why a third terrain shader.** `SHADER_terrain_splat.gdshader` is the textured
   terrain for SCENE_test_zone_W and knows nothing about the grooming channels: it
   has four layers, no UV inputs, and its own fog band (-200 .. -320) that W's
   cloud decks and palette assertions are tuned against. W2's fog is a different
   band (-170 .. -320) with a single colour, and W2 needs all seven layers. Fusing
   them would mean one shader carrying two fog models and three dead samplers for
   whichever scene was not using them. Everything below the texture assignments —
   the fog band, the exact neutral fog colour, the smooth shading — is carried over
   from `MAT_terrain_flatcolor.tres` unchanged, because those numbers are tied to
   the sky material and the palette LUT rather than to how the ground is painted;
   the test asserts the two materials still agree on every one of them.

   **The variant layers borrow their base's normal map.** Fairway, forest floor
   and trail are mixed into the *albedo* of the grass and soil channels and take
   those channels' normals. Seven independent normal maps would be seven more
   fetches for a difference nobody can see — the three variants are ground at the
   same relief scale as the layer they replace, and it is the albedo the eye reads.
   The shader is at sixteen texture fetches on GL Compatibility — fifteen for the
   splat, plus one for the environment ball `SHADERINC_island_light.gdshaderinc` samples
   since the island went unlit. Twelve distinct samplers are bound against the
   sixteen texture image units GLES3 guarantees and V3D provides exactly.

   | layer | texture | alternates in the set |
   | --- | --- | --- |
   | rough | `forest_ground_01` (moss + twigs) | — |
   | fairway | `lawn_striped` | — |
   | soil / build pad | `dirt_01` | — |
   | forest floor | `forest_ground_06` | — |
   | path | `rocky_trail_02` | `rocky_trail_01` |
   | rock | `dark_rock_02` (fractured slabs) | `dark_rock_01` (smoother, reads as marble) |
   | sand | `coast_sand_02` | `coast_sand_01`, `aerial_beach_01` |

   Scales are **metres per tile** and are set against feature size, not against
   each other: 512 px of mower stripe wants to cover about a mower's width, 512 px
   of rock slab wants to cover a slab. Raise them together to pull the whole
   surface back if it reads as busy from the air.

   The flat-colour pair is still in the repo and still tested, so flipping back to
   the graphic look is a one-line scene change.

   **The cliffs are textured from the same set** — `dark_rock_02`, on the same two
   side projections the banding already used, in object space so it stays locked to
   the landform across a rebase. It MULTIPLIES the gradient rather than replacing
   it: the vertical ramp to dark and the alpha fade to nothing are what make a
   cliff bottom dissolve into the fog band instead of terminating, and both are
   asserted. The sample is divided through by `rock_mid`, the texture's measured
   mean luminance (0.0368 for the 128 px `dark_rock_02` bake) — sampling a photo
   that dark raw would pull the whole wall down and move the depth at which the fog
   takes over. Per channel, not per luminance, so the wall picks up the rock's own
   warm hue instead of staying a grey card with grey variation on it.

### The cliff is a 45 m band, and everything about it follows from that

`CloudSea.sea_altitude` is -45 and the hub's shore is y = 0, so the ONLY cliff
anyone ever sees is the top 45 m. That one fact sets every number on the rim:

- `IslandField.cliff_shoulder_height` is **20 m** — 44% of the visible band, and
  it leaves 25 m of unmistakable wall below it. Any deeper and the lip would
  still be curving when it reached the clouds and the island would read as a dome
  with no cliff at all; any shallower and the corner it replaced starts showing
  through again.
- `MAT_cliff_wall.tres`'s `dark_depth` is **46**, so the wall reaches `deep_level`
  almost exactly as it enters the cloud deck. Everything past that is fog and
  fade. (The old gradient material had this at 150, which spent the entire ramp
  below the deck and left the visible band one flat mid-grey.)
- `cliff_ring_bias` is **2.4**, which bunches the wall's rings toward the top —
  the only part above the fog. It matters more now, not less, because
  `cliff_wall_rings_for` cuts the hub to four rings and the bias decides where
  those four land.
- `cliff_depth_variance` is **0.10**, and it is now spent on the shoulder's height
  rather than the wall's drop, so all of it lands in the visible band by
  construction. At 0.22 it read as an unsteady rim rather than as rock.

**And the wall carries the terrain's DISTANCE fog.** It has no height fog by
design — it dissolves, and the cloud sea and the Environment's height fog take
what is left — but it needs the distance term, because the ground above it has
one. Without it a far island hazed out to nothing and left a crisp ring of rock
hanging under a ghost. `fog_distance_start` / `_density` / `_power` on
`MAT_cliff_wall.tres` have to track `MAT_terrain_splat_w2.tres`'s exactly; the
test asserts it, along with the band rules above against the cloud sea's
altitude.

If you want MORE cliff visible, the lever is `CloudSea.sea_altitude` (and the
scene Environment's `fog_height`, which is coupled to it), not these numbers.

### The rim ROUNDS OVER: a shoulder in the terrain mesh, a banded wall under it

`chunk_mesher._build_rim` + `shaders/SHADER_cliff_wall.gdshader` +
`materials/MAT_cliff_wall.tres`.

The coastline used to be a corner — dead-level plateau meeting a sheer cone in
one 90° edge — and the corner was the reason the cliff never read as land however
it was graded. It now rounds over. Each coastline segment is swept down a profile
with two halves, and the two halves go into **different meshes**:

- **The shoulder** leaves the shore at `cliff_shoulder_angle` (18°) and steepens
  asymptotically to vertical over `cliff_shoulder_height` (28 m). Its vertices go
  into the **walkable surface's** arrays — splat weights, UVs and all — so the lip
  is drawn by `MAT_terrain_splat_w2.tres`. That is the point: the rock on the lip
  is the same shader sampling the same texture at the same world coordinates as
  the bare-rock band on the shore above it, so the two are continuous *by
  construction* rather than by two materials being tuned to match.
- **The wall** picks up at the handoff and plunges from there, in vertically
  stacked bands, drawn by `MAT_cliff_wall.tres`.

The curve is an exponential in the cotangent, which is what makes "ever tapering
angle that eventually goes full vertical" exact rather than approximate:

```
cot(theta(d)) = cot(theta_0) · exp(−d / L)      L = height / SHOULDER_SPANS
r(d)          = r0 + S · (1 − exp(−d / L))      S = L · cot(theta_0)
```

The angle approaches vertical and never reaches it, and `dr/dd` is positive and
shrinking — the lip **flares**, by less and less, until it is a wall.
`SHOULDER_SPANS` is **4**, and that figure is why the handoff is invisible: at
three spans the surface is at 81° against a wall that starts at exactly 90, a 9°
shading break landing precisely where two meshes and two materials already meet.
At four it is 87.8°, under the noise in the rock normal map.

**The sign is the one thing to get right here.** The first version flared the
wrong way, and it compiled, tessellated, passed every watertightness check and
rendered a shape that was wrong in a way no assertion caught. A surface that
descends while moving *inward* is an UNDERCUT — its outer face points at the
ground, sees no sun, and is lit almost entirely by sky ambient. It came back
**blue**, rgb (66, 54, 72), against a rock texture whose own mean is warm and a
swept cone that measured (86, 83, 62). A fillet runs the other way: round over a
cylinder's edge and the arc goes from the top face down and *out*, radius growing
with depth, the normal swinging from straight up to straight out. The lip
therefore leaves the coastline and flares — 10.3 m out over a 20 m drop — so the
wall stands slightly proud of the turf line, which is what a cliff edge looks
like anyway. `tests/TEST_island_rim.gd` now asserts the direction explicitly.

**There is no tangent matching, and it was looked for.** The plateau arrives at
the coastline exactly flat, by construction: `base_height` ramps the shore with a
smoothstep (derivative zero at both ends) and `shore_width` spreads that ramp
over 0.22 of the mask — **275 m** on the hub. Six metres inland the ground has
risen about a centimetre. Matching that tangent would open the shoulder at a
tenth of a degree and pull the lip hundreds of metres into the island. So the
opening angle is a chosen number, and the soft break it leaves at the rim is the
price of keeping the coastline exactly where the rest of the world thinks it is
(zones, scatters, collision, `coast_lod`). 18° against a plateau arriving at 0.1°
reads as a lip; the corner it replaced was 90°.

**The handoff ring is shared, not recomputed.** Index `sr` of the profile is both
the shoulder's last ring and the wall's first, emitted into both meshes from the
same computed value, and both copies take their normal from the same following
segment. That is what makes a crack there impossible — the failure mode is a
recomputed handoff landing micrometres off, which is a slot you can see the sky
through from below and which no bounding-box check would catch.
`tests/TEST_island_rim.gd` asserts the two are bit-identical: 20 columns, 20
exact shares, worst near-miss 0.000000000 m.

**The depth wobble moved to the shoulder.** It used to be applied to the wall's
drop and faded out toward the tip so all of it landed above the cloud deck. The
shoulder now *is* that band, so the same noise varies how deep each column's lip
rolls over and the wall starts wherever the lip finished. The rim keeps its
irregularity, and the handoff becomes one number per column used by both halves —
which is why the two meshes meet exactly whatever the noise did.

#### The wall is cut into vertically stacked bands

`IslandField.cliff_wall_bands` (4, clamped to at least two rings per band). Purely
a culling change: no vertex moves, only which mesh it lands in.

One mesh from the rim to the tip carries an AABB reaching from the coastline to
the island's centre axis and hundreds of metres down — measured at **~169× the
volume of the chunk's own footprint** on the hub. That box intersects the frustum
from almost anywhere, so the whole sweep was submitted whenever any part of a rim
chunk was on screen, including the 500-odd metres of it the material had already
faded to nothing. Each band's box is a few tens of metres tall, and the deep ones
fail the test on their own.

`IslandWorld.cliff_visible_depth` (340 m) then drops the deepest bands from the
draw outright. They are still **built**, and their faces still go into the
chunk's collider — culling decides what is *drawn*, and a collider that only
exists where you can see it is worse than none at all. The figure has to sit at
or past the material's `fade_end` (330), or the deepest drawn band ends on a hard
horizontal edge instead of dithering out.

#### Rings are only bought where the profile bends

`IslandField.cliff_wall_rings_for` scales the ring budget by how much the island's
cone genuinely converges before `cliff_cutoff_y` slices it off.

The hub does not converge. `cliff_taper` deliberately holds the wall vertical
under the plateau and only closes it hundreds of metres down, and the hub's
underside is cut at the fog floor long before that — at `t_end` = 0.41, where the
raw convergence is **5%**. Its wall is a straight vertical extrusion to within a
few degrees, and the twenty rings it used to get were twenty copies of the same
ring: **102,746 triangles across the streamed hub to describe a shape four rings
describe exactly as well.** A satellite is the opposite case — its cone fits above
the cutoff, converges to a point, and keeps all twenty.

Computed **per island, never per column**: neighbouring columns must agree on how
many rings they have, or the wall between them is not a quad strip.

#### The wall's material is the terrain's rock, dithered

`SHADER_cliff_wall.gdshader` is a verbatim port of `SHADER_terrain_splat_w2.gdshader`'s rock
channel — and here that is a requirement, not a nicety, because the shoulder above
it is drawn by that very shader and the two meet **mid-curve**, 28 m below the
shore and in plain view above the cloud deck. `MAT_cliff_wall.tres` carries the
same seven parameters (`rock_albedo`, `rock_normal`, `rock_scale`, `rock_tint`,
`triplanar_sharpness`, `normal_strength`, `slope_shade`); the test asserts all
seven against the terrain material.

It also **dithers instead of blending**, and that fixed a defect rather than
changing a style. `SHADER_cliff_gradient.gdshader` was `cull_disabled` *and*
alpha-blended, so it tested depth without writing it and the near wall never
occluded the far one. Its fade had to be kept at 70…240 m not to show more wall
but to stop showing the *far* wall through the near — the "pale vertical curtains"
the old material's comments record two failed attempts to lengthen past. Opaque
with a Bayer discard, the far side is properly hidden and the band runs 150…330.

`SHADER_cliff_gradient.gdshader` and `MAT_cliff_gradient.tres` are still in the tree and
still work; nothing in the shipped scene uses them.

#### What happened to the rock-chunk scatter

`SCRIPT_cliff_scatter.gd` + `SHADER_cliff_rock.gdshader` + `MAT_cliff_rock.tres` +
`models/MODEL_cliff_chunk.glb` stood ~5,100 copies of one rock model around the rim.
It is **no longer in the scene**. Generated geometry that rounds the island's own
edge is a better cliff than a scatter of one repeated mesh, and it costs a
fraction of the triangles — the scatter was **319,440 of them, 17% of the frame,
in one draw call**.

The machinery is kept, and so is `tests/TEST_cliff_scatter.gd`, because what it
covers is not the rock: it is a general "stream instances along a coastline by
bearing" engine, with a closed-form coastline query, island-global slots that
tile without a seam, and render-space buffers patched through a rebase. The test
now builds its own node instead of pulling one out of the scene. Wire it back in
and it works.


   - **SMOOTH shading** (`flat_shading`, now default **off**). The mesh normals
     `SCRIPT_chunk_mesher.gd` emits are computed analytically from the height field, not
     averaged from faces, so they are smooth and continuous across chunk and LOD
     boundaries by construction — the shader just interpolates them. Faceting is
     still one uniform away: on, the per-fragment normal is the geometric FACE
     normal from world-position derivatives (`cross(dFdx, dFdy)`, oriented into
     the mesh normal's hemisphere so its sign is dependable).

     It went off because **faceting is resolution-coupled and the resolution
     moved.** At `pregen_cells = 32` the facets are 4 m, small enough to fall
     under a pixel at any distance, which is exactly the regime where the
     derivative trick stops being dependable. It also fought the bunkers: a
     3.4 m dish shaded as flat plates does not read as a bowl.

     **The rim is still a hard edge, and not by luck.** The plateau and the cliff
     are separate meshes with separate materials, so no normal is ever averaged
     between them: the top surface's coastline vertices look straight up (the
     shore ramp is zero there, so the ground really is level) and the cliff's
     first ring looks out and down. Smoothing each smooths each; the crease
     between them is untouched. `SHADER_cliff_gradient.gdshader` therefore turned its own
     `flat_shading` off *independently* rather than to match — the test asserts
     both, as a pair, because one drifting back to faceted while the other did not
     would make the join read as a seam instead of an edge.

3. **Cliff gradient.** `shaders/SHADER_cliff_gradient.gdshader` +
   `materials/MAT_cliff_gradient.tres` give the island undersides a triplanar,
   object-space, side-projected vertical gradient: **medium grey → dark grey →
   transparent.** Object space is exact for free — cliff vertices are emitted
   pivot-relative, so model-space `-VERTEX.y` is height below the coastline.
   `SCRIPT_island_world.gd` gained an optional `cliff_material` export (null → cliffs
   share `terrain_material`, the old behaviour) so this rides on the same
   streamed cliff meshes.

3b. **The cliff you actually SEE is a scatter of rock columns.** The swept cone
   in (3) is still generated, still collided against and still the island's
   silhouette at range — but from the shore it is a featureless dark card, and
   that is what it now stops being. `scripts/world/SCRIPT_cliff_scatter.gd` stands a few
   thousand copies of `models/MODEL_cliff_chunk.glb` (a 6.9 × 17.5 × 6.9 m column, 242
   triangles) around every island's coastline, overlapping, stretched and
   re-sized, tops held level at the shore. See the section below.

4. **Fog matched to the sky, at an exact neutral.** The Environment fog, the W2
   terrain shader's haze, the cliff wall, the grass and tree billboards, the
   volumetric cloud sea's fog and the horizon band's haze all use **0.30** — the
   sky's `bottom_color` — so a fully fogged fragment and the low sky resolve to the
   same pixel, and the neutral snaps cleanly through the palette LUT (a tint here
   would paint a coloured stripe across the sky). This replaces the bluish
   panorama-mean (0.458, 0.539, 0.624) the fog matched while the panorama was the
   sky. Environment distance `fog_density` is 0.0012. The cliff-gradient shader
   carries no fog of its own — it fades to transparent and the cloud sea (9) plus
   the height-fog backstop (6) take it.

   **The value was 0.089 and had to move.** 0.089 was chosen for a scene whose
   islands floated in empty void; once the cloud sea went in underneath, it was
   four times darker than the surface it was supposed to blend into and drew a
   near-black bar across the horizon — 0.28 deep against its surroundings with a
   21.8/255 step at its lower edge. It also sat in the one large gap in ps1-soft's
   neutral ramp (0.031 → 0.282, where every other step is 0.031), so a flat area
   of it dithered between two entries eight steps apart. 0.30 was found by sweep:
   the horizon trough falls from 0.287 to 0.021. All eight consumers are asserted
   against each other by `tests/TEST_horizon_clouds.gd`.

   Note 0.30 is an *input* colour; the sea's measured *rendered* tone is 0.364.
   The gap is the filmic tonemap, which is why the number has to be found by
   rendering rather than read off the sea's `cloud_color`.

5. **Dense unlit billboard vegetation, in actual forests.**
   `scripts/world/SCRIPT_veg_scatter.gd` populates the island with the crunched
   `sprites/` firs, bushes and ferns from the same field that paints the ground
   — plants stand only on vegetated rough (not rock, not sand, low slope, off
   every zone and its apron), placed on a deterministic logical hash grid so they
   are storage-free and stable across a floating-origin rebase, and meshed in
   tiles on worker threads (6c).

   **There is no poly LOD and no impostor bake.** A plant is a Y-axis billboard
   of one sprite from a metre to the horizon. What that replaced was a
   1,264-triangle pine .glb rendered as two MultiMeshes out to 120 m and
   cross-dissolved into a runtime-baked impostor beyond it — 1.1 million
   triangles from the ridge, sixty per cent of the frame. The whole island's
   vegetation is now nine draw calls, one per sprite variant, and that is what
   pays for the density below. What it costs in triangles is set by the per-class
   fades rather than by the population; see the table in 6d.

   **One grid, three classes.** The obvious construction is a scatter node per
   class and it is wrong twice over: `IslandField.sample` is ~0.11 ms and is the
   entire cost here, so three nodes over the same ground pay for the same ground
   three times; and three independent grids let a fir, a bush and a fern land on
   the same square metre. Instead one cell is sampled once and then decides what
   — if anything — grows in it. `keep` is one uniform roll on [0, 1), the three
   class weights are laid end to end, and whichever band it lands in is the
   class, with everything past their sum growing nothing. That is a weighted
   choice and a keep test in one number.

   **Density follows `IslandField.forest_at`**, per class, interpolated between
   each class's `*_open_density` and `*_forest_density`. Measured on the shipped
   field by `tests/PROBE_veg_census.gd`: 459,040 candidate cells at a 4 m grid,
   **482,500 plants — 30,286 firs, 135,318 bushes, 316,896 ferns**, 22 MB of
   instance buffers. (An accepted cell emits `bush_per_cell` / `fern_per_cell`
   plants, 3 and 12, which is where the understory's share comes from: only
   26,408 cells grow ferns.) The mask lives on the *field*, not here, precisely
   so the plants and the needle-litter floor under them cannot disagree about
   where the wood is.

   - **Firs** are near-zero in the open (`tree_open_density` 0.02) and 0.55
     inside a wood, so where the trees are and are not is exactly the shape of
     the `forest_at` contour.
   - **Bushes** are the one class that is *denser in the open than in the wood*
     (0.55 against 0.22), because their open figure is multiplied by a
     **thresholded** clump noise rather than a scaled one. `bush_clump_lo`/`_hi`
     smoothstep the raw noise, which clusters about 0.5 with a spread near 0.19,
     so roughly half of open ground comes out completely bare and about a tenth
     at full scrub — clumps in a field, not an even speckle. The other two
     classes use the plain `0.5 + 0.5 * noise` compression, which is what keeps a
     forest from having bald patches in it and is exactly what has to go if a
     threshold is to reach zero anywhere.
   - **Ferns** are understory and nothing else (`fern_open_density` 0), so a fern
     is always a sign you are under canopy.

   Each class clumps on **its own noise field** (`_value_noise` takes a salt), or
   the undergrowth would clump exactly where the canopy does and read as a
   texture on the forest rather than as its own layer.

   One trap worth knowing: `IslandField.forest_litter` deliberately moves turf
   into the *soil* channel under a canopy, so the old "grass must be the dominant
   surface" gate would have made the densest woods the one place a tree refused
   to stand. The gate is "not rock, not sand, and vegetated", and the litter
   fraction is capped under 0.5 so grass stays dominant anyway. Both halves are
   asserted.

   **`forest_edge` should not go to zero** — the scatter interpolates its keep
   probability across the band, so a step function puts a hard line of trees on
   the ground where a couple of tree-widths of ramp reads as a treeline.

   **Under `prescatter` it stops *meshing* altogether.** Every tile is built
   behind the loading screen and kept; once that is done the tile set can no
   longer change — nothing is meshed, probed, pruned or re-meshed for the rest
   of the session, and a scan from the far side of the island dispatches no work
   at all.

   **What a scan still does is choose, and that reversed on the per-class
   fades.** It used to pack every plant in the world into its MultiMesh once and
   never repack, on the argument that per-scan selection would save "maybe a
   third of the quads" against a multi-megabyte re-pack per scan cell. That was
   measured when all three classes shared one 1,300 m band. With the bands split
   (6c above) the numbers are not close: ferns submit ~6% of their population
   and bushes ~45%, so the cut is about two thirds of the vegetation rather than
   a third, and the re-pack is correspondingly smaller. `_fill` fingerprints the
   tile set it selected per class, so a class whose selection did not change does
   not re-upload — which is *every* frame for a class whose band already reaches
   past the island, and most frames for the others.

6b. **Ground-cover grass**, `scripts/world/SCRIPT_grass_scatter.gd`, sharing
   `shaders/SHADER_veg_billboard.gdshader` with everything above through its own
   `MAT_grass_billboard.tres`. Y-axis billboards of the crunched `sprites/`
   grass, on the same storage-free hash grid the plants use and reading the same
   field — so grass, needle litter and canopy cannot disagree about what a patch
   of ground is.

   **Its own node, not a class in the veg scatter.** The two want opposite
   budgets: plants are ~4 m apart and visible for 1300 m, grass ~1 m apart and
   visible for 90. One shared grid would either starve the woods of range or
   drown the frame in tufts. They share the field — the part that has to agree —
   and the tiling construction, and nothing else. Grass is also the one thing
   that is *never* built up front: what the loading screen would lay down IS
   everything the player can see from where they spawn, and the census puts the
   island's full complement at 2.77M tufts against the ~21,000 that fit in a 90 m
   view. Building the rest is not a trade, it is a loss.

   **The pivot is the base**, via `QuadMesh.center_offset`, plus a small `sink`
   so the sprite's soil root is buried rather than hovering on a slope.

   **`grass_grid` is quadratic in cost.** Each cell is one `IslandField.sample`
   (five height evaluations), and the scan box grows as the square of the view
   distance over it. Halving the grid quadruples the cells. That cost is real but
   it is not the frame's problem — it is paid once per cell, on a worker thread,
   and kept (6c). What the grid still buys directly is draw-side.

6b-i. **One billboard shader for every plant in the world**,
   `shaders/SHADER_veg_billboard.gdshader`, with two materials configuring it:
   `MAT_veg_billboard.tres` for the firs/bushes/ferns and
   `MAT_grass_billboard.tres` for the ground cover. There used to be two separate
   programs (`grass_billboard` and `tree_billboard`) and they drifted apart on
   tint, on fog and on what "upright" means.

   - **Unlit.** `render_mode unshaded`: ALBEDO goes straight to the tonemapper,
     no sun term, no ambient, no normal, no shadow. That deleted three things
     that were each their own bug — the `up_bias` normal fudge (a camera-facing
     quad has no honest normal, so a tuft flipped between blown out and black as
     you walked round it), the roughness uniform, and the whole per-instance
     ground-tint machinery. The art is painted with its own light and shade;
     lighting it again was double-counting. What carries exposure now is the flat
     linear `tint`, and it is the *only* thing between the sprite's painted
     brightness and the screen — the source art is photographic against a terrain
     graded to ~0.14 linear, so at 1.0 the woods read as a lighter layer sitting
     on top of the island and the 16-entry palette LUT paints the brightest
     needles white.
   - **Shadow casting is off**, and now for a second reason beyond cost: a shadow
     cast by something that does not respond to the light casting it is a lie the
     eye picks up immediately.
   - **The near proximity fade** is the unusual one and it is a gameplay
     requirement, not a rendering one. Plants dither OUT as the camera approaches
     and are gone inside `near_gone` (3 m), fully solid from `near_solid` (10 m).
     A ~4 m-grid wood is otherwise a wall a metre from the eye — an occlusion
     problem and a fill-rate one — and this opens a clearing exactly as wide as
     the player. **Grass is the one material that switches it off**, by setting
     `near_solid` at or below `near_gone`: grass is ankle-high and occludes
     nothing, and a bald ring following the player across a meadow is far worse
     than the tuft you clip through. `tests/TEST_island_world.gd` asserts both
     directions.
   - **The far fade** dithers out across [`far_start`, `far_end`] with the same
     ordered Bayer 4×4 the rest of the project uses. Screen-door needs no
     back-to-front sort across tens of thousands of instances and writes real
     depth, so vegetation never mis-sorts against itself, the terrain or the
     ball. Keep `far_end` at or under the scatter's `view_distance` or plants pop
     while still fully opaque; `tests/TEST_island_world.gd` asserts that too.
   - **…and it is per class, because it is also the cull.** `veg_scatter` reads
     `far_end` off the material each class draws with and stops *submitting* a
     tile once every plant in it is past that distance, so the fade and the cull
     are one number and cannot drift apart. Three materials, three bands:

     | class  | material                    | fade      | held    | submitted |
     |--------|-----------------------------|-----------|---------|-----------|
     | firs   | `MAT_veg_billboard.tres`    | 1080–1300 | 30,286  | 30,195    |
     | bushes | `MAT_veg_understory.tres`   | 600–820   | 135,318 | 73,365    |
     | ferns  | `MAT_veg_fern.tres`         | 200–300   | 316,896 | 18,648    |
     | | | | **482,500** | **122,208** |

     Both columns measured, not estimated: *held* by
     `tests/PROBE_veg_census.gd`, *submitted* by `tests/TEST_prescatter.gd`
     standing at the island's centre. **965k triangles down to 244k, in the same
     nine draw calls.** Across the island the submitted total runs 35,610 (on the
     shore, looking mostly at sea) to 122,208 (dead centre).

     Whole-frame effect, same build, same viewpoints, before and after
     (`tests/PROBE_tri_budget.gd` and `tests/RENDER_w2_ground.gd`, Godot 4.7
     headless / llvmpipe):

     | viewpoint                    | before      | after     | draw calls |
     |------------------------------|-------------|-----------|------------|
     | probe_tri_budget "ridge"     | 1,330,884   | 602,562   | —          |
     | ground: rough                | 1,623,664   | 847,474   | 1,213 both |
     | ground: wood                 | 1,609,157   | 847,687   | 1,156 both |
     | low over the island, across  | 1,564,404   | 802,136   | 1,334 both |
     | mid-altitude oblique         | 1,343,720   | 552,984   | 1,175 both |
     | treetop height, long view    | 2,113,733   | 1,381,661 | 1,668 both |

     **Roughly half the frame's triangles, and the draw call count does not move
     by one** — the vegetation was already nine calls and still is. Whatever the
     scene's ~1.3k draw calls are, they are not the plants; see the shadow note
     below. Side-by-side captures of every row above show no visible difference
     at ground level and, from the air, scrub that thins into the haze slightly
     sooner. No edge, no ring.

     One band for all three is one band sized for the tallest of them, and a
     22 m fir wants 1,300 m. The population is nowhere near evenly split: the
     **ferns are two thirds of every plant in the world** (`fern_per_cell` is
     twelve), so that single number was never a compromise between the classes —
     it was the fir's number applied to a population that is mostly not firs, and
     316,896 ankle-high plants were submitted across the whole island every frame
     to be drawn about a pixel and a half tall through a canopy.

     Splitting the bands takes three quarters of the vegetation's triangles out
     of the frame without touching a density, which is the only kind of cut that
     costs nothing where you are actually looking.
     `tests/TEST_island_world.gd` asserts the ordering (canopy outreaches scrub
     outreaches floor) and that the scatter's own `Distance` exports stay at 0,
     i.e. that the numbers are not duplicated.

     **What it costs is a re-pack when the camera crosses a `scan_cell`**, which
     `_fill` spreads over frames (`fill_sprites_per_scan`, 3). Measured by
     `tests/PROBE_scatter_cost.gd`: 2.56 ms mean and 4.74 ms worst per scan, one
     scan per 40 m of travel, which is 0.08% of one core at walking pace and
     1.7% flying at 120 m/s. Unspread it was 9.37 ms worst — a visibly long
     frame every 40 m — which is the whole reason the budget exists.

     **The draw calls are NOT the vegetation and never were.** The scene runs
     1,150–1,700 of them and exactly nine belong to plants, one per sprite
     variant, before and after this change. The rest are terrain chunks and
     cliff bands multiplied by the shadow pass, WHICH NO LONGER EXISTS — the
     light and its shadow are both gone from the scene now, and the census
     below was taken while `DirectionalLight3D` still shipped with
     four PSSM splits and `directional_shadow_max_distance` 3600, so every
     visible chunk and band is submitted up to five times. That is the next
     thing to go after if the draw call count is what hurts.
   - **Half the instances are mirrored horizontally**, chosen by a hash of the
     instance's own world position in the vertex shader. Ten sprites over a
     hundred thousand plants is a lot of repeat, and this doubles the apparent
     variety for no texture memory, no per-instance data and no extra draw call.
     U only — flipping V would stand the plant on its head.

   The sprites are **crunched by `scripts/SCRIPT_crunch_art.gd`** and sampled
   `filter_nearest_mipmap`, to sit with the rest of the project's pixel art
   rather than as photographs pasted into it. Two size tiers, split by how big
   the thing gets on screen rather than by what it is: firs at 128×256, bushes,
   ferns and grass at 128×128 — 13.4 MB of source art down to 115 KB. That script
   is worth reading before regenerating them:

   - the downsample is alpha-WEIGHTED (a straight average drags the transparent
     background's colour into every edge texel and haloes each blade);
   - the alpha is thresholded below half (thin blades occupy a minority of their
     texel, so a half cut leaves the tuft bald);
   - the colours are quantised at the source so the palette LUT crushes them
     once, deliberately, rather than per frame;
   - and plants are **cropped to their alpha box, then PADDED to exactly the
     output's aspect, never scaled to it**. The billboard quad is sized in metres
     from the texture's own dimensions, so a texture whose aspect disagreed with
     its content's would draw every fir stretched — by a different amount per
     variant, which is the version of that bug that is hard to see and impossible
     to unsee. Extra width is split evenly; **extra height goes entirely on top**,
     because the scatter plants the quad by its bottom edge and a symmetrically
     padded plant would hover half its padding above the ground.

   Because the padding is transparent, a sprite's content occupies only part of
   its quad — `SCRIPT_crunch_art.gd` prints the fraction (0.74 for `large_bush_1`, 1.00
   for every fir), and the metre sizes in `SCRIPT_veg_scatter.gd` are read against it.

6c. **Both scatters stream TILES, meshed on worker threads.** This is where the
   scene's moving-camera cost went, and the number is worth stating before the
   design: with a camera walking the hub at 120 m/s the two scatters cost **145 ms
   and 73 ms per frame on average, and 875 ms and 996 ms at worst**. The terrain
   under them cost 7 ms. Prewarming the LOD ladder had already taken meshing out
   of play; this was what was left, and it was ninety-five per cent of the frame.

   Both were written the obvious way: one dictionary entry per candidate grid
   cell. At the grass's 1 m grid over a 90 m view that is fifty thousand entries,
   and every rescan walked all of them — once to discover, once to emit, once in
   eight to prune — then re-packed the whole MultiMesh buffer a float at a time in
   GDScript. The forest did the same over fifty-six thousand cells at 1300 m. None
   of that is meshing; it is bookkeeping about meshing.

   The clincher was measuring it with the camera at 160 m, where the grass emitted
   **zero tufts**: 248 ms a frame to produce nothing. The membership test is a true
   3D distance, so an aircraft is simply too far above the ground for any tuft to
   be in range — but nothing was in a position to notice, because the cost was
   incurred before the test.

   So the unit of work is a TILE — `tile_cells` square of grid cells, ~16 m for
   grass and ~88 m for trees — and:

   - A tile is meshed ONCE, into finished MultiMesh instance buffers in render
     space. Emitting is `PackedFloat32Array.append_array` per visible tile, which
     is a memcpy, not a scripted loop.
   - A rescan walks a few hundred tiles instead of fifty thousand cells, and
     **samples the field zero times**. Every sample — the height probe that places
     a tile as well as the mesh that fills it — is on a `WorkerThreadPool` task
     with a pooled `IslandField` clone, exactly as `SCRIPT_island_world.gd` meshes chunks.
     `IslandField.sample` costs about 0.1 ms; keeping up with a camera at 120 m/s
     takes ~360 of them a frame, which is 36 ms that has no business on the main
     thread.
   - A tile carries the height band of the things standing on it, so the
     visibility test is a 3D distance to a box. A camera 600 m up matches no tiles
     and meshes nothing. (The band comes from probing the tile's four corners and
     its centre, not just the centre: this island has hundred-metre cliffs, and a
     tile straddling one has ground at your feet AND ground far below.)
   - Cutting the visible set per TILE rather than per plant survives because it
     does not have to be exact. A tile is admitted whole, and the few plants that
     land past the view edge are ALREADY invisible — the shader has dithered them
     out over [`far_start`, `far_end`] before the scatter's own cut reaches them.
     Over-including at the seam costs instances, never correctness. (This is also
     why the cut can be taken per CLASS off each material's `far_end` without a
     margin: the tile is only dropped once the shader has finished dithering
     every plant in it away.)

   Measured after, same walk, same container:

   | per frame, walking the hub at 120 m/s | before | after |
   |---|---|---|
   | grass scatter | 145 ms avg, 875 worst | 1.7 avg, 3.3 worst |
   | tree scatter | 73 ms avg, 996 worst | 2.7 avg, 5.3 worst |
   | terrain streamer | 7.4 avg, 128 worst | 3.3 avg, 22 worst |
   | whole frame, median | 84 ms | 6.4 ms |
   | whole frame, 90th | 764 ms | 12.5 ms |
   | whole frame, worst | 1800 ms | 26 ms |

   Flying at 600 m/s the grass goes from 248 ms average to 0.6, which is the
   altitude cut doing exactly what it says.

   **Every tuft and every tree is in the same place as before.** `_evaluate_cell`
   is untouched in both files; this changed how the results are stored, batched
   and shipped, and nothing about what grows where.

   The terrain's remaining spikes were a different animal and are dealt with by
   `IslandWorld.collision_swaps_per_scan`: on a prewarmed world every chunk
   install is a cache hit and costs nothing, EXCEPT that handing the physics server
   a fresh `ConcavePolygonShape3D` does real first-touch work that prewarming
   cannot pay down. A burst of those was a 64 ms frame. Rationed to two a scan it
   is several ordinary frames instead of one dropped one. `tests/TEST_scatter_tiles.gd`
   asserts the shape of all of this.

6. **Opaque height fog as the cloud sea's backstop.** The Environment's built-in
   height fog (`fog_height=-45`, `fog_height_density=2.0`) — the cheap per-pixel
   term, no volumetrics — is cranked to full opacity: Godot's height term is
   `1 - exp(y_dist · density)` for `y_dist = y - fog_height`, so at density 2.0 it
   reaches ~1.0 within ~3 m below the plane. It is aligned to the cloud sea's
   surface (`sea_top = -45`, see 9), so it is an INVISIBLE floor of sky-coloured
   (0.089) fog directly under the clouds: anything the volumetric sea leaves gappy
   shows this flat 0.089 instead of the raw void, and since that is the low-sky
   colour it reads as thinner cloud, never a hole. The shore (y≈0) and plateaus sit
   clear above it. `fog_sky_affect`, `fog_aerial_perspective` and `fog_sun_scatter`
   stay 0 — the sky is already the fog colour, so fogging it double-counts, and the
   other two tint (a coloured stripe once the LUT snaps it). Environment distance
   `fog_density` is 0.0012 (down from W's denser value) so the lone hub stays
   legible from the air instead of fogging to a flat silhouette too near.

7. **Smooth island terrain on a live LOD ladder, prewarmed.** The scene sets no
   detail overrides at all: it takes `SCRIPT_island_world.gd`'s own `chunk_cells` (64, a
   2 m grid at LOD 0), `lod_distances` and `coast_lod`. Its one world override is
   `prewarm = true`, which builds every rung of that ladder before the loading
   screen lifts — see "The world is PREWARMED" below.

       LOD      0     1     2     3     4+
       cells   64    32    16     8      4
       metres   2     4     8    16     32
       to (m) 160   400   900  1800   beyond

   `coast_lod` (2, an 8 m contour) is the most expensive number in that group and
   the first to check when the triangle count is too high: the coastal ring is
   pinned by GEOMETRY rather than by distance, so every chunk in it pays whatever
   that says, everywhere, forever. Under prewarm it is also the CHEAPEST kind of
   chunk to hold, because a pinned chunk needs one cached level where an inland one
   needs all five.

   `pregen_cells = 32` (the uniform-resolution path, which W2 no longer uses)
   puts the whole island on a **4 m** vertex grid (it was 12,
   i.e. 10.7 m). Three things wanted it and one thing paid for it:

   - `IslandField.sand_depth` went to 2.4 m (1.4 m now), and a bunker needs to be
     eight or nine vertices across to hold a scooped profile rather than coming
     out as a triangular pit. Traps are 26 m across now rather than 34, and the
     grid has since gone finer still, so this holds with room to spare.
   - The terrain is smooth-shaded now (2), so the coarse grid that used to be half
     of the deliberate low-poly look no longer buys anything.
   - Paths are 9 m wide including their banks; at 10.7 m spacing a track could
     fall between two vertices entirely.

   And it is **cheaper than the 24 that sits between them** — 4.0 s against 6.7 s
   for the whole island, despite 1.6× the triangles. `chunk_mesher.build` measures
   curvature over a fixed world distance, and when the vertex step is coarser than
   `IslandField.curvature_radius` (4 m) it cannot read its neighbours off the grid
   and probes the field four extra times per vertex instead. At
   `chunk_size / cells <= curvature_radius`, i.e. cells ≥ 32 on W2's 128 m chunks,
   that probe switches off and pays for the extra vertices several times over. 32
   is exactly that threshold; there is no reason to stop short of it.

   (`chunk_cells` still moved for every *streaming* scene — 64 → 128, with the
   ladder shifted out one rung and `coast_lod` 2 → 3. See "The ladder" in
   `docs/DOC_procedural_island_world.md`. W2 does not use any of it.)

8. **Single JAGGED-island field.** `data/ISLANDFIELD_hub_solid.tres` is W2's own
   field, forked from `ISLANDFIELD_default.tres`:
   - `satellite_density_near = satellite_density_far = 0` — every non-hub lattice
     cell rolls empty in `island_field._cell_island()`, so the world is the anchor
     hub and nothing else. The sibling hubs on the 12-cell lattice sit 10.8 km out,
     far past W2's `view_distance + hub_radius` reach (~4.85 km), so only the core
     hub ever renders. **No sub-islands.**
   - `coast_jagged = true`, `coast_irregularity = 0.2` — a serrated shore that is
     still guaranteed one connected piece. `SCRIPT_island_field.gd` gained a JAGGED coast
     mode: instead of the stock 2D positional wobble (which can pinch islets off the
     rim and open void lagoons), the wobble is read from the coast noise around a
     circle indexed by BEARING from the island centre, so it depends on angle alone.
     That makes the land the star domain `{d ≤ R(angle)}` — along every ray out from
     the centre the mask `1 - d/R + wobble(angle)·irreg` is strictly decreasing, so
     it crosses zero exactly once. **Jagged edge, no edge holes, no detached
     scatter, provably** (validated: 720/720 test rays a single land interval, shore
     radius swinging ~34%). `coast_jag_scale` sets serration fineness. The mode is
     off by default, so W and `tests/TEST_island_world.gd` are unaffected.

   Everything else is copied verbatim, so the hub's terrain, golf course, build
   pads and cliffs are unchanged. W still uses the stock field with its satellites.

9. **Raymarched volumetric cloud sea.** `shaders/SHADER_cloud_volumetric.gdshader` +
   `materials/MAT_cloud_sea_volumetric.tres`, driven by `scripts/world/SCRIPT_cloud_sea.gd`
   — the fluffy layer the flat height fog was standing in for. One huge quad sits at
   the sea surface (`sea_top = -45`, well below the island shore so the land rises out
   of it without the cloud clipping through the terrain) and chases the camera in XZ;
   for every pixel that
   looks at it the fragment shader marches the view ray through the bounded slab
   `[-220 .. -45]` and integrates Beer–Lambert transmittance to an alpha, colouring
   each sample by its HEIGHT in the slab. The sea is **UNLIT** — no sun term and no
   self-shadow — but carries a vertical TONAL GRADIENT (`cloud_color` at the billow
   tops fading to `cloud_bottom_color` at the base) so the billows read with form
   while staying sun-independent. `cloud_bottom_color` is the sky's own bottom value
   (0.089), so the cloud base and the low sky are the same tone. It is a
   **SOLID mass with no holes**: a seamless fbm `NoiseTexture2D` (two world scales,
   differenced; world-anchored via `world_offset` for floating-origin stability)
   does NOT gate coverage — it only sets the height of the billowing TOP SURFACE
   (`surface_y = sea_top - (1-f)·bump_amp`), and everything from that surface down to
   the floor is filled, so the top undulates but never opens a gap the void could
   show through. `depth_draw_never` + the depth
   TEST gives it terrain occlusion for free — land in front hides the sea, the sea
   hides the submerged cliffs. Colours are exact neutrals.
   - **The sea is IN the weather.** Every marched sample is faded toward the scene's
     haze by ITS OWN distance from the camera, so the far side of the sea dissolves
     into the same haze a distant island does. It keeps `fog_disabled` and rolls the
     model itself for two reasons. First, the engine fogs a fragment at ONE depth —
     for this shader that is where the view ray crosses the trigger quad at
     `sea_top`, which for a grazing ray is kilometres from the cloud actually being
     looked at; a volume has to be fogged where its mass is. Second, the model has
     to be the TERRAIN'S (`1 - exp(-(max(d - 850, 0) · 0.0012)^2)`), not the
     Environment's, because what has to blend here is the sea against the islands
     sitting in it, and `terrain_splat_w2` / `cliff_wall` / `veg_billboard` (via
     both its materials) all roll that same curve. The test asserts the numbers
     match the terrain's. `horizon_fade_*` no longer converges the colour — by
     3800 m the fog exponent is 12.5, i.e. transmittance 4e-6 — and now only closes
     the sheet to opaque so the far sea still occludes what is behind it.
   - **Compatibility renderer, kept cheap.** No compute and no engine volumetrics, so
     the whole march is in `fragment()`; cost is bounded by the thin slab, an early
     transmittance break, rays that miss the slab doing zero work, and `steps` (22),
     the hard performance dial. A start jitter keeps the low step count from banding.
   - The island's shore rises just above `sea_top`, so it reads as land emerging from
     cloud; the opaque height fog (6) sits at the same altitude as an invisible
     backstop under it.

10. **A permanent vortex over a blacked-out zenith**, in the same sky shader.
    `textures/TEX_vortex_7_extra.png` mapped as a disc centred on straight-up and
    turning at −0.04 rad/s — one revolution every two and a half minutes.

    - **Sized by area, not by angle.** `vortex_coverage` (0.35) and
      `zenith_black_coverage` (0.05) are fractions of the sky dome, and the shader
      reads them straight off `EYEDIR.y` with no trigonometry: by Archimedes'
      hat-box theorem a spherical cap's area goes as its *height*, so the cap edge
      is simply `EYEDIR.y = 1 - coverage`. The swirl owns the top third of the sky,
      the blackout the top twentieth. Angles would not have been interchangeable
      like this — half the dome's area is the top 60°, not the top 45°.
    - **Both default to off in the shader**, and only `MAT_sky_w2_void.tres` turns
      them on. `MAT_sky_void.tres` shares the shader and is what SCENE_test_zone_W
      renders, so W is byte-for-byte the sky it was.
    - **The blackout goes under the swirl, not over it.** The texture's core is
      near-black and its arms brighten outwards, so the middle of the swirl
      disappears into the blacked-out zenith and only the arms carry — which is
      what makes it read as something you are looking *into*. Widening the blackout
      past `vortex_coverage` gives a black lid with a ring under it instead; at
      0.35 (the whole swirl darkened) it reads considerably heavier, if the flat
      overcast ever wants that.
    - **It is not a mesh, and cannot be.** A sky shader is evaluated per view
      direction and has no position, so the vortex is at infinity by construction:
      the fly camera can chase it forever without closing distance, and it never
      enters the depth buffer, takes fog, or clips the near plane. A dome mesh
      would have to be camera-parented and scaled past the far plane and would
      still do all three.
    - **Two things in the mapping are load-bearing.** The bearing is carried as a
      unit *vector*, not an `atan()` angle: atan jumps by TAU across the meridian
      behind the camera, and a UV that jumps drives mip selection to its coarsest
      level along that line — a blurred radial scar through the swirl. And the
      rotation is *rigid*. Spinning the middle faster than the rim is the obvious
      way to sell a vortex and it eats itself: a shear that never stops winds the
      arms sub-pixel-tight and the whole thing greys out, the same winding problem
      real spiral galaxies have.
    - `TEX_vortex_7_extra.png` was imported with `mipmaps/generate=false` and
      `detect_3d/compress_to=1`; both are now flipped, to match every other texture
      the sky samples. Without mips a 2048² image drawn across a third of the
      screen shimmers, and the dither post-FX turns shimmer into crawling dither.
      Pinning `detect_3d` stops Godot silently re-importing it to VRAM compression
      the moment it is detected in 3D — block compression on a smooth swirl this
      large is exactly where DXT artefacts show.
    - `vortex_color` stays exact white and the texture is greyscale, for the same
      reason `bottom_color` is an exact neutral: the palette LUT resolves an
      off-neutral grey to a *tinted* entry, and here that entry would swing as the
      arms turned.
    - It sits entirely above `EYEDIR.y = 0.65`, well clear of the horizon at 0.25,
      so it does not touch the sky/fog contract in (1).

## The world is PREWARMED: the LOD ladder, built in full, before you get it

**W2 sets `IslandWorld.prewarm = true`.** Every LOD of every chunk is meshed
behind the loading screen and kept in a per-island cache. The ladder still runs
during play — chunks still coarsen and refine as you move — but a level change is
a `remove_child` / `add_child` of a mesh that already exists, and nothing is
meshed after the screen lifts. Ever.

This is the third answer to the same question, and the first two are both still
in the tree because each was wrong in an instructive direction.

**Pregeneration was wrong because uniform resolution means the LOD ladder never
runs.** Not "runs less" — never. Every threshold in `lod_distances`, the
hysteresis, the coastal pin: all dead code while `pregenerate` is on, because
nothing is ever rebuilt. The far rim of a 2.5 km island carried the same grid as
the ground underfoot, and the scene sat at ~2.2M triangles standing still.

**Streaming was wrong because the scene was lying about it.** W2 carried a
`LoadingScreen` wired straight to its `IslandWorld` — which reads, in the scene
tree and in every screenshot of the editor, as "the terrain is built before the
player gets it". It was not. The screen tests a FLAG, not the signal, and with
both up-front flags off it took its "nothing to wait for" branch, pushed a warning
into a log nobody reads, and cleared at **frame 8**. The 484 chunks then meshed in
front of the player. Two assertions now guard this from outside, in
`tests/TEST_island_world.gd`, against the scene file: that W2 does not flatten its
ladder, and that it prewarms. A setting that silently disables a whole subsystem
cannot be policed by that subsystem's own tests.

**And underneath both of those, the streamer could not finish at all.** Measured
on the shipped scene before any of this: the world reached **2 chunks of 484** and
stayed there for as long as anyone cared to watch.

> 116 of the hub's 484 surveyed chunks mesh to nothing. They are footprint corners
> — `rect_touches_island` keeps a chunk whose rect overlaps the island's bounding
> DISC, and the mask then finds the corner is all void. A void build installed no
> node and left nothing behind saying so, so the next `_scan` two frames later
> asked for it again. They are also the chunks nearest the W2 spawn camera, which
> sits off the +z rim — so nearest-first dispatch, the mechanism that exists to
> put the ground under your feet ahead of the far rim, handed every one of the 12
> in-flight slots to the same void corners in perpetuity.
>
> The fix is one line of intent and it is why the cache stores nulls: "this chunk
> is void at this resolution" is a real answer and has to be remembered like any
> other. The livelock is worth knowing about because nothing about it looked like
> a livelock — no error, no warning, no spin, just a world that was quietly 0.4%
> built while the CPU stayed busy.

**What prewarm costs**, measured on the reference container (headless, 4 cores,
the hill-climb settling on 2 lanes):

| | streaming, as shipped | `prewarm` |
|---|---|---|
| chunks on screen when you get control | 2 of 484 | 368 of 484 |
| time before control | none (screen cleared at frame 8) | 21 s behind the bar |
| chunk meshes held | 2 | 1328, across 5 LOD levels |
| memory | — | +396 MB |
| meshing during play | permanent | **none** |

The 21 s and the 396 MB are the honest price of "no terrain generation after the
player has control", and `prewarm_budget_mb` is the dial for a machine that cannot
pay it. It cuts the tail of the build list, and the list is ordered so the tail is
the least valuable: the level each chunk needs at the spawn anchor is built first
and is never refused, then the spare levels COARSEST first. That ordering matters
because the finest level is nearly all of the bill — LOD 0 is 4.3M of the 5.9M
cached vertices, being 64×64 cells on all 356 inland chunks whether or not you
ever stand on one, and every coarser level put together is 1.5M. At 96 MB the load
drops to 7.6 s and about 100 MB, and buys its way out with 136 frames of meshing
during play, worst frame 1.1 s. Zero is the default for a reason.

**Collision moved from distance to LOD level.** It used to be
`dist <= collision_distance` per chunk per scan, which fought the cache: a chunk
crossing the collision radius wants the same mesh with a body bolted on, i.e.
either a second cached variant of every chunk or a rebuild — and a rebuild is the
one thing prewarming exists to abolish. LOD level is already a function of
distance, so `_collides_at(lod)` says nearly the same thing one step coarser and
makes a chunk's collision state fixed at build time. "Nearly", because only a
level's NEAR edge is tested: at the stock ladder that rounds one way exactly once,
so level 3 chunks keep collision out to 1800 m instead of losing it at 1400.

**What is still main-thread work after the screen lifts** is the tree and grass
scatter, not terrain. Teleporting the camera across the island costs ~985 ms in
the worst frame with the scatters in, and ~120 ms with them out — and that 120 ms
is the physics server re-registering collision shapes for a burst of swapped
chunks, not meshing. The forest at least gets its prefill now: the loading screen
has a second stage for it that could never run while the screen was clearing at
frame 8.

## How the up-front build works

Both up-front modes share all of the machinery below — the survey, the lanes, the
field pool, the width tuning. They differ only in what goes on the work list:
`prewarm` puts one job per chunk PER LOD LEVEL and installs only the level the
spawn anchor calls for, while `pregenerate` puts one job per chunk at
`pregen_cells` and installs all of them. Everything from here down was written
against `pregenerate` and reads that way; it is all equally true of `prewarm`,
which simply has a longer list.

**Why.** The streamer was spending seconds of CPU meshing chunks *during play*,
and it was worst on the fastest-looking hardware: on a dual-socket Xeon E5-2630
v2 (2×6 cores, 24 threads) it stuttered badly, while a four-core Pi 5 ran it
fine. Three separate causes, all measured on the W2 hub (484 candidate chunks):

1. **A clone of the whole `IslandField` per chunk.** `island_world._build_task`
   called `field.clone()` every time, and a fresh clone arrives with an empty
   island cache — so each chunk re-ran `IslandField._place_zones`, the 40-attempt
   rejection sampler that lays out the golf holes and build pads, before meshing a
   single vertex. **4828 ms** to mesh the island that way, **1205 ms** reusing
   prepared fields. Now pooled (`_take_field` / `_release_field`); the streaming
   path in `SCENE_test_zone_W` gets the same 4x for free.

2. **More threads made it slower.** Chunk meshing is GDScript calling GDScript,
   and GDScript call throughput does not scale on this box — it *degrades*:

   | work in a worker thread | 2 threads | 4 | 8 | 16 | 24 |
   |---|---|---|---|---|---|
   | pure arithmetic | 1.0x | 1.6x | 4.2x | 6.4x | **7.9x** |
   | native method call in a loop | 1.6x | **3.4x** | 1.7x | 1.2x | 1.1x |
   | GDScript function call | 1.2x | 1.0x | 0.5x | 0.4x | **0.4x** |
   | `IslandField.mask_for` | **1.1x** | 0.7x | 0.5x | 0.4x | 0.3x |

   Whole-island build time by lane count says the same thing: 1 lane 3717 ms,
   2 lanes 2060, 3 lanes 2068, 4 lanes 2039, then 6 lanes 3261, 8 lanes 4358,
   12 lanes **5559** — slower than a single lane at 12, on a 24-thread machine.
   Contention inside the interpreter, not the hardware (pure arithmetic on the
   same cores reaches 7.9x), and reproduced identically on Godot 4.5.1 and 4.7.
   A single-socket Pi 5 scales cleanly to four. **There is no constant that is
   right for both**, so `pregen_workers = 0` measures it: `_pregen_retune`
   hill-climbs the lane count against observed chunks-per-second and settles.
   On the Xeon it settles at 2 and hits 2039 ms — the best time in the sweep —
   and never touches the cliff.

3. **The frame loop throttled the workers.** Dispatching one task per chunk and
   topping the queue up from `_process` means a task that finishes mid-frame idles
   until the next frame, capping the build at N chunks/frame regardless of machine
   speed. Measured, it held the island to ~0.6 chunks per frame. Pregeneration
   uses **lanes** instead: `_pg_width` long-lived tasks looping on a shared cursor.
   Same work, **5833 ms → ~2050 ms**.

**What it costs.** One uniform resolution for the whole island instead of a LOD
ladder. That is mostly a gain — from the shipped camera the ladder gave 144
chunks at 4 cells, 294 at 6 and 46 at 12, and everything is now 12 — but it does
mean the far rim carries detail it does not need. It also retires the contour-seam
problem `SCRIPT_island_world.gd`'s header is largely about: with one cell count, no two
chunks can disagree about where the coastline is, so `coast_lod`, `lod_distances`
and `lod_hysteresis` are unused here.

**`pregen_cells` is the one detail dial**, and it is not linear in cost. Whole
island, this machine, best lane count:

| cells | spacing | triangles | build |
|---|---|---|---|
| 6 | 21.3 m | 64k | 0.6 s |
| 12 | 10.7 m | 174k | ~2.0 s |
| 16 | 8.0 m | 271k | 3.1 s |
| 24 | 5.3 m | 525k | 6.7 s |
| **32** | **4.0 m** | **857k** | **4.0 s** |

32 is faster than 24 despite 1.6x the triangles, and that is not a typo:
`chunk_mesher.build` measures curvature over a fixed world distance, and when the
vertex step is coarser than `IslandField.curvature_radius` (4 m) it cannot read
its neighbours off the grid and has to probe the field four extra times per
vertex — three GDScript calls each. At `chunk_size / cells <= curvature_radius`,
i.e. cells >= 32 on W2's 128 m chunks, the probe switches off and pays for the
extra vertices several times over. **If you want more terrain detail, go to 32
rather than 24.**

Only suitable for a bounded world — W2 is one hub island in a void. Do not turn
`pregenerate` OR `prewarm` on for an endless field: one meshes every chunk in
range, the other meshes every chunk in range five times over.

(Shipped at 32 since the terrain went smooth-shaded — see 7. Measured again on
the current field, with paths and forests added: 484 chunks in 4.5 s.)

## Loading screen

`scripts/world/SCRIPT_world_loading_screen.gd`, a `CanvasLayer` at layer 129 (above the
dither post-FX at 128). It knows nothing about chunks or threads: it listens to
`IslandWorld.pregen_progress(stage, done, total)` and `pregen_finished()`, so it
will sit in front of anything that emits those.

Optionally it also runs a second stage first — `prefill_step()` / `prefill_ratio()`
on every node named in `scatter_paths` — so the forest is standing AND the ground
cover is down when the screen lifts, rather than growing around the player over
the first seconds of play. W2 names both scatters. They are stepped round-robin,
all of them every frame, and the stage ends when they all report finished: they
mesh on worker threads, so running one after the other would serialise two things
that are already parallel underneath.

`scatter_timeout` (180 s in the shipped scene) is a DEADLOCK GUARD rather than a
budget, and it has to clear the longest legitimate scatter stage or it truncates
one. That stage is the plant prescatter, which builds every tile of the island off
a 4 m grid: `tests/TEST_prescatter.gd` measures 1,020 tiles and 482,500 plants in
**36 s** on this container (4 cores), with the terrain streaming underneath it
where in the real scene it is already prewarmed and idle. A loading screen that
can strand the player behind it is worse than no loading screen, so it always
clears.

## Shared files touched (backward-compatible)

- `scripts/world/SCRIPT_chunk_mesher.gd` — additive `ARRAY_TEX_UV` (zone grooming) and
  `ARRAY_TEX_UV2` (forest weight, path grooming), plus the sand-aware shading
  normal. Other scenes' shaders ignore both UV channels; collision is unaffected
  (it reads `ARRAY_VERTEX`).
- `scripts/world/SCRIPT_island_world.gd` — optional `cliff_material`; new `get_field()`
  and `origin_offset()` accessors for the scatters; the `Prewarm` and
  `Pregeneration` export groups and the worker field pool. Both build-up-front
  flags default **off**, so W and every other scene keep streaming — but they do
  get the pooled fields (the 4x above), the per-island chunk cache, and the
  void-chunk fix, without which a streaming world can livelock on its own
  footprint corners. Collision also moved from a per-scan distance test to
  `_collides_at(lod)`, which changes one thing for streaming scenes: level-3
  chunks keep collision to 1800 m rather than losing it at `collision_distance`.
- `scripts/world/SCRIPT_veg_scatter.gd` and `scripts/world/SCRIPT_grass_scatter.gd` — both on
  TILE streaming with the meshing on worker threads (6c), and both offering
  `prefill_step()` / `prefill_ratio()` to the loading screen. Nothing calls the
  prefill unless a screen is wired up. The scatters are W2-only, so nothing else
  in the project changes when they do.
- `scripts/world/SCRIPT_island_field.gd` — new `coast_jagged` / `coast_jag_scale` exports
  and the angular-wobble path in `mask_for`/`mask_at`. **Default off**, and the
  positional path is byte-for-byte the old behaviour, so W and the test suite are
  untouched.

## New W2-only files

- `shaders/SHADER_terrain_splat_w2.gdshader`, `materials/MAT_terrain_splat_w2.tres` — the
  seven-layer textured terrain (2). `MAT_terrain_flatcolor.tres` and its shader
  stay for the flat graphic alternative.
- `scripts/world/SCRIPT_veg_scatter.gd`, `scripts/world/SCRIPT_grass_scatter.gd`,
  `shaders/SHADER_veg_billboard.gdshader`, `materials/MAT_veg_billboard.tres`,
  `materials/MAT_grass_billboard.tres`, `scripts/SCRIPT_crunch_art.gd` and the crunched
  `sprites/` art it bakes — all of the vegetation (5, 6b, 6b-i).
- `shaders/SHADER_cloud_volumetric.gdshader`, `materials/MAT_cloud_sea_volumetric.tres`,
  `scripts/world/SCRIPT_cloud_sea.gd` — the volumetric cloud sea (9).
- `data/ISLANDFIELD_hub_solid.tres`, `materials/MAT_sky_w2_void.tres` — the field
  and the procedural sky. The sky material is also the only caller of the zenith
  blackout and vortex (10); the shader defaults both off, so `MAT_sky_void.tres`
  and SCENE_test_zone_W are unchanged.
- `scripts/world/SCRIPT_escape_pod.gd`, `models/MODEL_escape_pod.glb` — the second
  impact site: the escape pod, leaning against the bank of its own shallow dent a
  long way from the crash crater. The dent is `IslandField.divot_at` and the
  shader's `divot` group, whose surface rides in the char plate's spare alpha
  because the sampler budget above is spent. See `docs/DOC_escape_pod_divot.md`.
- `scripts/world/SCRIPT_world_loading_screen.gd` — the loading screen.
- `tests/TEST_world_pregen.gd` — drives the real scene headless and asserts the
  build finishes, comes out at one uniform resolution, leaves the streamer
  completely idle afterwards, and clears its own screen.
- `tests/TEST_scatter_tiles.gd` — drives the real scene headless and asserts the
  scatters' tile streaming (6c): a few hundred tile entries rather than fifty
  thousand cells, a scan that never touches the field, no meshing at all for a
  camera 600 m up, the identical field on revisiting ground, and every tuft
  surviving a floating-origin rebase.
- `scripts/world/SCRIPT_cliff_scatter.gd`, `shaders/SHADER_cliff_rock.gdshader`,
  `materials/MAT_cliff_rock.tres`, `models/MODEL_cliff_chunk.glb` — the rock columns
  around the rim (3b).
- `tests/TEST_cliff_scatter.gd` — asserts the geometry rather than the streaming:
  that the coastline query lands on the mask's exact zero with land a metre
  inside it and void a metre outside on all 360 bearings, that the segments tile
  the slot ring with no gap and no double, that every top sits inside the jitter
  the exports allow, that no bearing along the rim is left uncovered by rock,
  that a segment built twice is the same bytes, and that a rebase moves every
  column by exactly the shift.

## The cycle runs, and its night is blood — see `docs/DOC_w2_blood_night.md`

Everything below this heading describes W2's **daytime**, which is still what the
scene looks like at its parked phase — but the scene is no longer parked. It runs a
day/night cycle whose night is not dark: the dome above blacks out, the cumulus ring
and the cloud sea stay lit and turn deep red, and every surface takes its light from
those two instead of from an overcast.

Three things in that change reach back into everything written here:

1. **The one haze value is a product now.** It is still the exact neutral `0.30`
   in all fourteen places, and it is still pinned for the reason this document
   gives — but every one of them is multiplied by the global `tod_haze_tint`
   where it is used, and the sky's `bottom_color` is written by the cycle as
   `sky_haze_base * tod_haze_tint`. Same product, so the contract the "Tuning
   knobs" section below asks you to maintain by hand is now maintained by
   construction across the whole cycle. Both new globals are **white** by default,
   at every phase and in `project.godot`, so nothing outside W2 moves.

2. **A second global, `tod_art_tint`, reaches the unlit half of the scene** — the
   vegetation, the grass, the cloud sea, the horizon band, the smoke and the zenith
   vortex, none of which has a light term for a cycle to move. Fire is deliberately
   excluded: a flame is a light source.

3. **The `TimeOfDay` bus was never actually wired**, and fixing it changed the
   daytime picture. Its node-typed exports were stored as NodePaths with no
   `node_paths=` array in the node header, so `sun_pivot` and `world_environment`
   resolved to null on every load and the island was lit by `project.godot`'s
   fallback white sun rather than by anything in this document. Mid-distance ground
   on the `ridge` viewpoint moves from `(87, 135, 72)` to `(47, 76, 44)` with the
   wire in. The full account, and the two knobs for taking the brightness back, are
   in `DOC_w2_blood_night.md`.

## Tuning knobs

- Sky gradient / horizon / overcast sun: `MAT_sky_w2_void.tres`. Its `bottom_color`
  is the fog contract — change it and you must move all seven of the others with
  it: `fog_light_color` (scene Environment), `fog_color` on
  `MAT_terrain_splat_w2.tres`, `MAT_cliff_wall.tres`, `MAT_grass_billboard.tres`
  and `MAT_cloud_sea_volumetric.tres`, `MAT_veg_billboard.tres`, and `haze_color`
  on `MAT_horizon_clouds.tres`. (Under the cycle, `bottom_color` is written every
  frame from `TimeOfDay.sky_haze_base`, so that export is the one to move — the
  `.tres` value is only what the editor shows at the parked phase.)
  `tests/TEST_horizon_clouds.gd` asserts all eight against each other. Find a new
  value by sweeping it with `tests/RENDER_cloud_band.gd --set` and measuring the
  horizon discontinuity, not by reasoning about it — the filmic tonemap sits
  between the number you type and the pixel you get.
- Zenith vortex: `MAT_sky_w2_void.tres` — `vortex_coverage` (how much of the sky
  dome the swirl owns, by area), `zenith_black_coverage` and `zenith_darkness`
  (the blackout under it), `vortex_spin_rad_per_sec` (sign is the direction) and
  `vortex_strength` (0 removes it). All of it lives above `EYEDIR.y = 0.65`, so
  none of these touch the fog contract above. Swap the swirl by pointing
  `vortex_texture` at another alpha-masked disc — it must fade to zero alpha at
  the edge of its inscribed circle, or raise `vortex_edge_fade` until it does.
- Cloud sea: `MAT_cloud_sea_volumetric.tres` — `cloud_color` (flat unlit tone),
  `bump_amp` (billow height of the solid surface), `thickness`, `density_gain`
  (opacity), `steps` (performance), and `CloudSea.sea_altitude` (where the sea sits;
  keep the scene's `fog_height` equal to it).
- Sun brightness: `TimeOfDay.day_sun_energy` (0.25) and `day_sun_color`, which
  become the `tod_sun_color` global. THE SCENE HAS NO DirectionalLight3D — it is
  entirely unshaded, so the light reached no pixel and its shadow pass was
  already off; what is left of the sun is a `SunPivot` Node3D holding the
  DIRECTION and the `tod_*` bus carrying the colour. The energy came down from
  3.0 because everything lit by it had been graded against a different reference
  — see the grading note above — and the terrain, cliffs and vegetation were
  clipping at different points rather than together.
- Sun direction: the `SunPivot` node's transform, read by `SkyCycleController`
  as `tod_sun_dir`. It is also what the sky's own sun glow aims at when there is
  no light to supply `LIGHT0_DIRECTION`.
- Palette: `PostFX/DitherRect`'s `palette_lut`, now
  `data/palettes/LUT_ps1-soft.png` — the project default, 512 entries, built by
  `tools/TOOL_build_ps1_palette.py`. Bake a different one from any `palette/*.hex`
  with `python3 tools/TOOL_build_palette_lut.py --palette palette/<name>.hex
  --output data/palettes/LUT_<name>.png`.

  WHY THE PALETTE CHANGED, because the old one had a specific failure worth not
  reintroducing. The shader scales the Bayer offset by `1 / (lut_levels - 1)`,
  i.e. by the LUT GRID's step, which is a good proxy for the palette's own step
  only when the two are comparable. Under `uzebox` they were not: RGB332 gives 8
  red levels, 8 green and **4 blue**, so the blue step was 0.33 against a dither
  offset of 0.033. Blue banded in wide flat bars the dither could not break up,
  worst in the sky, and `dither_strength` caps at 2.0 so it could not close that
  gap on its own. The same coarseness put the cliff wall's lower third under the
  palette's darkest step — the `deep_level` 0.55 → 0.72 change below was fighting
  the palette, not the shading, and the rock's lavender cast went with it.

  `ps1-soft` is snapped to the 15-bit grid the hardware actually used (every
  channel a multiple of 8), which gives 32 levels per channel, and its neutral
  row IS that grey ramp. Worst gap anywhere in its luminance ladder is 8/255. If
  you swap it out, check that number first.
- Height-fog backstop: scene Environment `fog_height` / `fog_height_density`.
- The rim: `IslandField`'s cliff group, in order of effect on how it READS:
  - `cliff_shoulder_angle` (26°) — the look knob, and it trades two things off.
    Lower leaves the shore more nearly horizontally so the break against the flat
    plateau is softer, but the flare is `height / SPANS × cot(angle)`, so it also
    throws the brim further out — 18° puts it 21 m past the coastline and reads as
    a mushroom. Higher is a tighter brim and a sharper corner, walking back toward
    the 90° this replaced. 26° gives a 10 m brim on a 20 m drop.
  - `cliff_shoulder_height` (20 m) — how far down the lip takes to go vertical.
    Sized against the 45 m band above the cloud deck; much past that and the
    island is a dome, much under and the corner reappears.
  - `cliff_shoulder_rings` (5) — the curve's whole geometry budget, and the one
    place on the rim where rings are always worth buying: every one lands above
    the deck. `cliff_shoulder_inset_max` (0.10) caps the flare as a fraction of
    island radius — never binding on the hub, always on a satellite.
  - `cliff_wall_bands` (4) and `IslandWorld.cliff_visible_depth` (340 m) — pure
    culling, no vertex moves. Keep `cliff_visible_depth` at or past
    `MAT_cliff_wall.tres`'s `fade_end` (330).
  - `cliff_wall_rings_min` (3) — the floor under `cliff_wall_rings_for`'s adaptive
    budget. The hub lands on 4 of a possible 20 because its wall is straight.
- Vegetation density: **`VegScatter.veg_grid` (4 m) is the most expensive single
  number in the scene**, and it is quadratic in BOTH directions — halving it
  quadruples the cells to field-sample (which the loading screen pays for, once)
  and quadruples the plants to draw (which every frame pays for, forever). It is
  one grid for firs, bushes and ferns together, so it moves all three at once;
  what moves them against each other is the six `*_forest_density` /
  `*_open_density` numbers.

  The draw side is not currently the binding constraint — the whole island is
  nine draw calls, and the per-class fades decide how much of it is submitted —
  so the figure to watch when lowering the grid is the **prescatter time**
  against `LoadingScreen.scatter_timeout`. `tests/PROBE_veg_census.gd` prints
  both without launching the scene.

  An older revision of this file quoted `76,605 plants`, which was the
  **accepted-cell** count from before `bush_per_cell` (3) and `fern_per_cell`
  (12) existed. The census now counts emitted plants: **482,500**. If you touch
  either per-cell number, re-run the probe — it is the population that decides
  what the per-class bands in 6d are worth.
- Flat vs. smooth terrain: `flat_shading` on `MAT_terrain_splat_w2.tres` and
  `MAT_cliff_gradient.tres`. Both ship smooth; flip them together if you want
  the faceted look back, and expect to lower `pregen_cells` with them.
- Landform: `data/ISLANDFIELD_hub_solid.tres`.
  - Hills — `hill_height` (34) is the altitude, `hill_scale` (430) the breadth,
    `hill_sparsity` (0.32) how much of the ground stays level, and `hill_ramp`
    (0.40) how GENTLE the flanks are. Reach for `hill_ramp` before `hill_height`:
    widening it flattens the slopes without costing any altitude.
  - Golf sits IN the land, not on it: `golf_inset` (7 m below base) plus
    `zone_apron` / `zone_apron_ratio` for how broadly the rim grades back up.
    Move `zone_apron` and you must re-check `zone_separation > 2 * zone_apron`,
    and `zone_label_min` / `buildable_flatten` with it — those are a fraction of
    the apron, so they slide in metres whenever it changes.
  - Bunkers: `sand_depth` (1.4 m, inset again relative to the fairway),
    `sand_scale`, `sand_coverage`, and `sand_end_clear` which keeps them off the
    tee and the pin.
  - Paths: OFF (`path_enabled = false`). A track is 7 m of flattened ground plus
    two 9 m banks crossing every stretch of rough on the island, and at that
    width it read as a scar rather than as a route. The machinery is intact and
    still tested — turn `path_enabled` back on and tune `path_width` /
    `path_apron` (thin) and `path_waypoint_tries` / `_spread` (how much they bend
    around hills).
  - Deliberate flat ground: `build_area_fraction` / `build_pads_max`.
- Flat-colour surface palette (only if you swap the material back):
  `MAT_terrain_flatcolor.tres`.
- Cliff SHELL look — the surface behind the rock columns, and what you see past
  their view distance: `MAT_cliff_gradient.tres` — `rock_scale` / `rock_strength`
  for how hard the rock reads, `dark_depth` for the ramp, `fade_start/end` for
  where it dissolves. All three are sized against the 45 m band the cloud sea
  leaves visible; see "The cliff is a 45 m band" above before moving any of them.
  Cliff shell GEOMETRY is `IslandField.cliff_terraces` /
  `cliff_rings_per_terrace` / `cliff_ring_bias` / `cliff_depth_variance`. For the
  cliff you actually look at, see the `CliffScatter` entry above.
- Island shape: `data/ISLANDFIELD_hub_solid.tres`. Re-enable sub-islands with
  `satellite_density_near/far`; `coast_jagged` + `coast_irregularity` set how
  serrated the (always-connected) shore is; `coast_jag_scale` its fineness.
- Restore the rotating cloud panorama: point the scene's `5_sky` ext_resource back
  at `MAT_sky_rotating_day.tres` and re-tune the fog colours to its mean.
- What grows where: `VegScatter.tree_forest_density` / `tree_open_density` (firs,
  effectively woods-only), `bush_*` (the open figure is the high one — it is
  multiplied by a THRESHOLDED clump noise, so `bush_clump_lo`/`_hi` is what sets
  how patchy the scrub in the fields is), `fern_*` (understory only). Where the
  woods ARE is `IslandField.forest_coverage` / `forest_scale` / `forest_edge`
  (the threshold's sharpness). Plant SIZE is `tree_height` / `bush_height` /
  `fern_height`, in metres of quad — remember a sprite's content fills only part
  of its padded quad, and `SCRIPT_crunch_art.gd` prints the fraction.
- How close vegetation lets you get: `MAT_veg_billboard.tres`'s `near_gone` (3 m)
  and `near_solid` (10 m). Widen the band to clear more of the shot line; set
  `near_solid <= near_gone` to switch the fade off entirely, which is what
  `MAT_grass_billboard.tres` does.
- How the plants sit in the exposure: `tint` on the two billboard materials. The
  shader is `unshaded`, so this is the ONLY control — there is no light term.
- Ground cover: `GrassScatter.grass_grid` (quadratic cost, but paid on worker
  threads — raise `max_in_flight` with it if the field visibly lags a moving
  camera) / `density` / `view_distance`, `forest_falloff` for how hard the canopy
  thins it, plus tuft size, wind and the fade band. Re-crunch the sprites AND the
  terrain textures with
  `godot --headless --script res://scripts/SCRIPT_crunch_art.gd` after touching any
  source art.
- Island terrain poly budget, in the order to reach for them: **`coast_lod`**
  (the coastal ring is pinned by geometry, so it pays everywhere forever),
  **`chunk_cells`** (LOD 0; quadratic — 128 is four times the triangles of 64),
  then `lod_distances[0]` (how wide the LOD 0 ring is). `pregen_cells` only
  matters if `pregenerate` is turned back on, and turning it on retires the whole
  list above — see "The world was PREGENERATED".
- Streaming smoothness vs. detail: `max_uploads_per_frame`, `max_in_flight` and
  `rescan_interval`. (If pregeneration is turned back on instead: `pregen_cells`
  and nothing else; `pregen_workers` is auto-tuned.)
- Faceting is off (`flat_shading = false` on MAT_terrain_splat_w2.tres,
  MAT_terrain_flatcolor.tres and MAT_cliff_gradient.tres). Turn them back on
  together, never one alone.
- Ground textures: `MAT_terrain_splat_w2.tres`, one albedo per layer out of
  `textures/` plus four normal maps; per-layer `*_scale` is metres per tile.
  Swap in `MAT_terrain_flatcolor.tres` for the old flat graphic look.
- **Draw calls: reach for the shadow pass first, and nothing else second.**
  `tests/PROBE_draw_calls.gd` attributes them by ablation — hide a system, read
  `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME` back, and the difference is that
  system's true cost including whatever it spends in the shadow pass, which no
  amount of walking the scene graph can tell you. At the `ridge` viewpoint, before
  this pass:

  | source | draw calls |
  |---|---|
  | **shadow pass** | **785** |
  | terrain surfaces (368 chunks, 214 through the frustum) | 214 |
  | cliff wall bands (256 exist, 106 through the frustum) | 106 |
  | vegetation (9 MultiMeshes, one per sprite) | 9 |
  | grass / clouds / post FX | 4 |
  | **total** | **1,118** |

  The whole visible scene is 333 calls and the shadow pass redrew it 2.4 times
  over. Everything else is rounding: the vegetation is already one draw call per
  sprite variant, and atlasing all nine into one would save eight calls out of
  eleven hundred.

  In the order to reach for them:
  1. `IslandWorld.cliff_cast_shadows` (now off) — 1,118 → 907. The walls hang
     below the shore of an island in a void and the sun is 17.6 degrees up, so
     they were casting onto nothing.
  2. `DirectionalLight3D.directional_shadow_max_distance` (3600 → 1800) — 907 →
     741. Paired with `directional_shadow/size` 8192 → 4096 in `project.godot`,
     which holds sharpness (`reach / atlas`) at exactly 0.4395 and takes the
     shadow atlas from 256 MB to 64 — the number that actually matters on the
     Raspberry Pi / V3D target.
  3. `IslandWorld.terrain_shadow_lod` (off) — 741 → 601 at level 3, 741 → 480 at
     level 2. The biggest lever left and the only one that costs an image: level 2
     is 400 m out, where 62% of a shadow's contrast still survives the fog, and
     what goes is the dark side of every middle-distance hill. It exempts coastal
     chunks, which are pinned to `coast_lod` by geometry rather than by distance —
     without that, level 2 un-shadows the shoreline you are standing on.

  `tests/TEST_island_world.gd::_check_shadow_budget` asserts the two invariants
  rather than the numbers — that the reach ends where the fog has (under 8%
  contrast at the fade band, counting BOTH the terrain shader's squared falloff
  and the Environment's exponential) and that `reach / atlas` never gets blurrier
  than the 0.4395 it was tuned at.
