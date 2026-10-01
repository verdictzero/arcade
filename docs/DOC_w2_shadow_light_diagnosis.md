# SCENE_test_zone_W2 — shadow & lighting diagnosis (handoff)

Portable task pack for continuing this investigation in Claude Code on the web / cloud.
Everything an agent needs is inline — no dependency on the originating session.

**Repo:** `github.com:verdictzero/golf` · **Branch:** `main` · **Commit at time of writing:** `c96819b`
**Scene under investigation:** `res://scenes/utility/SCENE_test_zone_W2.tscn`

---

## 0. The bug report

Verbatim from the user:

> something is really fucked up with shadows and light in scene W2, sun is pointed
> wrong direction, when i point it right direction (down toward the terrain) shadows
> seem to be working in reverse? is there some giant object casting shadows? what is up

Three questions to answer explicitly:

- **(a)** Why is the sun pointed the wrong direction?
- **(b)** Why do shadows look reversed once it's aimed down correctly?
- **(c)** Is there a giant object casting shadows — yes or no?

---

## 1. Environment constraints (must be respected by every proposed fix)

- Godot **4.7** (`config/features=PackedStringArray("4.7", "GL Compatibility")`).
  Local editor is `4.7.stable.mono` (snap); a `4.6.2` binary exists at
  `/home/evan/godot/Godot_v4.6.2-stable_linux.arm64` and is used for headless parse-checks.
- Renderer is **GL Compatibility** (`gl_compatibility`), **not** Forward+.
  Shadow handling differs between the two — reason about Compatibility specifically.
- Target hardware is **Raspberry Pi / V3D 7.1, GLES3**. Shaders must be potato-safe
  **and stay at or under 16 varyings**. A Mobile/Vulkan experiment was tried on
  2026-06-26 and **reverted** — Mobile cannot lift the 16-varying cap on V3D, and there
  is no Forward+ option. Do not propose fixes that assume Forward+ features.
- The scene ends in a palette-LUT post-process (`shaders/SHADER_post_dither.gdshader`,
  `lut_levels = 16`, `dither_strength = 0.9`), which quantises the final image to
  16 levels. This matters when reasoning about shadow contrast.

### Headless parse-check

```bash
/home/evan/godot/Godot_v4.6.2-stable_linux.arm64 --headless --editor --quit 2>&1 \
  | grep -E 'SCRIPT ERROR|Parse Error'
```

---

## 2. Established ground truth

Verified directly before the fan-out. Do **not** re-derive these, but **do** challenge
any of them if you find contradicting evidence.

### 2.1 The sun aims upward

`scenes/utility/SCENE_test_zone_W2.tscn:52`:

```
transform = Transform3D(0.6550641, 0.66672033, -0.35564262,
                        -0.26321968, 0.64199656, 0.72027475,
                        0.7080473, -0.37773812, 0.5963535, 0, 800, 0)
```

Basis Z axis is `(0.7080473, -0.37773812, 0.5963535)`. A `DirectionalLight3D` shines
along its local **−Z**, so light forward is `(-0.708, +0.378, -0.596)` — **Y is
positive**, elevation **+22.2°**, i.e. aimed up into the sky.

At commit `02a9f11` the same light had basis Z `(0.4, 0.799, 0.449)` → forward
`(-0.400, -0.799, -0.449)`, elevation **−53.0°**, correctly pointing down.

Something in `02a9f11..c96819b` rotated it past horizontal.

### 2.2 Terrain and cliffs are double-sided

```
shaders/SHADER_terrain_flatcolor.gdshader:2   render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
shaders/SHADER_cliff_gradient.gdshader:2      render_mode cull_disabled, depth_draw_opaque, diffuse_lambert;
```

Both are applied as `material_override` by `scripts/world/SCRIPT_island_world.gd`
(`:463` terrain, `:474` cliff). `cull_disabled` was introduced by commit `cb94e9d`
*"Make terrain double-sided and let chunk surfaces frustum-cull"*.

### 2.3 The cloud sea is a 12 km shadow caster

`scripts/world/SCRIPT_cloud_sea.gd:39-50` builds a `PlaneMesh` of `deck_size × deck_size`
(default **12000 × 12000 m**) at `y = sea_altitude` (default **−45**), sets
`custom_aabb` reaching **2000 m downward**, sets `extra_cull_margin = 4000`, and
**never sets `_mi.cast_shadow`** — `MeshInstance3D` defaults to
`SHADOW_CASTING_SETTING_ON`. `_process` re-centres it on the camera every frame, so
it is always in view.

Its material runs `shaders/SHADER_cloud_volumetric.gdshader:2`:

```
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, ...
```

and writes `ALPHA` at `:198`.

### 2.4 Shadow configuration

The scene sets `shadow_bias = 0.012`, `shadow_normal_bias = 0.8`,
`directional_shadow_split_1/2/3 = 0.06 / 0.15 / 0.4`, `directional_shadow_fade_start = 0.92`,
and does **not** set `directional_shadow_max_distance` or `directional_shadow_mode`.

`IslandWorld.view_distance = 3600`, `FlyCamera.far = 12000`.

### 2.5 Trees already opt out

`scripts/world/SCRIPT_veg_scatter.gd` sets
`inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF` on every
MultiMeshInstance3D it creates. Trees are **not** a suspect. (Since this was
written the vegetation also became `unshaded`, so there is a second reason: a
shadow cast by something that does not respond to the light casting it reads as
wrong immediately.)

### 2.6 A note on scene-file churn

The `claude/*` branches author `.tscn` / `.tres` / `.import` as plain text without
`uid=` / `unique_id=` fields. The local 4.7 editor rewrites them into canonical form on
open, so these files re-dirty in git after every pull while the editor is running. This
churn is cosmetic (verified: dropped properties all equal engine or script defaults) —
**do not mistake it for a code change**, and close the editor before pulling if it gets
in the way.

---

## 3. Sub-agent task pack

Six independent investigation lenses, each followed by adversarial verification, then a
synthesis pass. Each lens prompt below is self-contained — prepend §1 and §2 as shared
context.

### Lens 1 — `sun-direction`

> LENS: the sun / DirectionalLight3D orientation.
> Confirm or refute that the committed light aims upward. Work out WHICH commit rotated it:
> run `git log -p --follow -- scenes/utility/SCENE_test_zone_W2.tscn | grep -nE 'commit|DirectionalLight|transform'`
> or bisect the transform line across commits `02a9f11..c96819b` with
> `git show <sha>:scenes/utility/SCENE_test_zone_W2.tscn`.
> For each commit that touched the light, compute the −Z forward vector and its elevation.
> Report the exact `Transform3D` that restores a sane sun (elevation about −50°, matching
> `02a9f11`) AND identify whether any script (`SCRIPT_island_world.gd`, `SCRIPT_cloud_sea.gd`, the sky
> material, or a tool script) also writes to the light's rotation at runtime. Grep for
> `DirectionalLight`, `look_at`, `rotation`, `basis`.

### Lens 2 — `backface-shadows`

> LENS: `cull_disabled` backface shadow casting on terrain and cliffs.
> In Godot's GL Compatibility renderer, what exactly does `render_mode cull_disabled` do to
> the DIRECTIONAL SHADOW pass for a heightfield mesh? Determine whether backfaces are
> rendered into the shadow map, and whether that makes a heightfield self-shadow (the
> underside of the ground casting onto its own topside), which would read to a user as
> "shadows working in reverse".
> Read `shaders/SHADER_terrain_flatcolor.gdshader` and `shaders/SHADER_cliff_gradient.gdshader` in full.
> Check git log for WHY `cull_disabled` was added (commit `cb94e9d` "Make terrain
> double-sided and let chunk surfaces frustum-cull") and whether it is still needed.
> Assess the interaction with `shadow_normal_bias = 0.8` and `shadow_bias = 0.012`.
> Propose the minimal fix that keeps whatever `cull_disabled` was for while stopping
> backface shadow casting (consider: `shadows_disabled` on the shadow pass, `cull_back`,
> per-instance `cast_shadow = SHADOW_CASTING_SETTING_DOUBLE_SIDED` vs `ON`, or splitting
> the shadow material).

### Lens 3 — `cloud-sea-caster`

> LENS: the cloud sea as a giant shadow caster. This is the user's explicit "is there some
> giant object casting shadows?" question — answer it definitively.
> Read `scripts/world/SCRIPT_cloud_sea.gd` and `shaders/SHADER_cloud_volumetric.gdshader` in full.
> Determine precisely: does a 12000×12000 `PlaneMesh` with `material_override` of a
> `blend_mix` + `depth_draw_never` + `unshaded` shader, on a `MeshInstance3D` whose
> `cast_shadow` was never set (defaults ON), actually render into the directional shadow map
> in GL Compatibility? Consider how Godot treats TRANSPARENT shader materials in the shadow
> pass, and whether `depth_draw_never` suppresses it. If it DOES cast, describe the visual
> result given the quad sits at y = −45 under the islands and is re-centred on the camera
> every frame.
> ALSO assess the second-order damage: `custom_aabb` reaching 2000 m down plus
> `extra_cull_margin = 4000` on an instance that is always in view — what does that do to the
> CSM cascade fit / shadow texel density for everything else in the scene?
> Give the exact one-line fix.

### Lens 4 — `shadow-range`

> LENS: directional shadow range and cascade configuration.
> The scene does NOT set `directional_shadow_max_distance`. Establish its DEFAULT value in
> Godot 4.7 for `DirectionalLight3D` (check docs or the engine; state your source).
> Compare that default against `IslandWorld.view_distance = 3600` and `FlyCamera.far = 12000`.
> Work out what the splits 0.06 / 0.15 / 0.4 and `fade_start 0.92` mean in absolute metres
> under that default, and whether shadows simply stop existing a short way from the camera —
> which on a 3600 m island world would look profoundly broken.
> Also evaluate `directional_shadow_mode`: the scene no longer sets it (it was dropped as a
> default). State what the default is and whether it suits this scene.
> Recommend concrete values for `max_distance` and the splits for a 3600 m view distance on a
> Raspberry Pi V3D (shadow atlas cost matters — do not recommend anything extravagant).

### Lens 5 — `env-ambient`

> LENS: environment, ambient and sky lighting — the "light is fucked up" half.
> Read the Environment block in `scenes/utility/SCENE_test_zone_W2.tscn` and
> `materials/MAT_sky_w2_void.tres` and `shaders/SHADER_sky_void_gradient.gdshader` (or whichever sky
> shader the material uses).
> Evaluate: `ambient_light_source = 2`, `ambient_light_energy = 1.8`, `ambient_light_color`
> (0.42, 0.42, 0.43), `reflected_light_source = 2`, `tonemap_mode = 2`, `glow_enabled` with
> `glow_intensity 0.5`, and the height fog block (`fog_light_color` 0.089 grey,
> `fog_density 0.0012`, `fog_height −45`, `fog_height_density 2.0`, `fog_sky_affect 0.0`).
> Ambient energy 1.8 with a `light_energy 3.0` sun is a LOT of fill — determine whether
> ambient is washing out shadow contrast so badly that shadows read as inverted or absent.
> Note: this project uses a palette LUT post-process (`SHADER_post_dither.gdshader`,
> `lut_levels 16`, `dither_strength 0.9`) which quantises the final image to 16 levels —
> assess whether heavy ambient plus 16-level quantisation collapses shadow gradients into
> flat banding. Flag anything that fights the sun.

### Lens 6 — `terrain-normals`

> LENS: terrain geometry, winding order and vertex normals.
> Read `scripts/world/SCRIPT_island_world.gd` in full, focusing on how chunk meshes are generated:
> triangle winding / index order, whether normals are computed or generated
> (`SurfaceTool.generate_normals`, `ArrayMesh`, custom `NORMAL`), and whether the
> faceted-terrain work introduced flat normals with a possibly FLIPPED sign.
> "Shadows working in reverse" is also the classic symptom of INVERTED NORMALS: lit where it
> should be dark. Determine whether the normals point up (+Y-ish) for ground faces.
> Check `shaders/SHADER_terrain_flatcolor.gdshader` for any `NORMAL` assignment, normal flipping, or
> use of `FRONT_FACING`, and `SHADER_cliff_gradient.gdshader` likewise.
> Cross-check against the recent commits `4bf2977` "jagged connected coast, faceted terrain"
> and `6ac8202` "fix faceted terrain lighting" — read those diffs with `git show`. Did
> `6ac8202` fully fix it, or half-fix it?

### Verification pass (run per finding, adversarial)

> ADVERSARIAL VERIFICATION. Another agent claims the following about the W2 scene:
>
> - **TITLE:** `{title}`
> - **WHERE:** `{file}:{line}`
> - **CLAIM:** `{explanation}`
> - **EXPLAINS:** `{symptom_explained}`
> - **FIX:** `{fix}`
>
> Your job is to REFUTE it. Read the actual files and check whether the mechanism is real in
> Godot 4.7 GL Compatibility specifically (not Forward+ — they differ in shadow handling).
> Verify the `file:line` actually says what is claimed. Verify the proposed fix would not
> break something else (this project has a 16-varying cap on V3D and must stay potato-safe).
> Set `refuted = true` if the claim is wrong, overstated, targets the wrong line, or if the
> fix is harmful. Default to `refuted = true` when genuinely uncertain. If the claim is right
> but the FIX is wrong or incomplete, set `refuted = false` and put the corrected edit in
> `corrected_fix`.

### Synthesis pass

> Produce the final diagnosis for the user. Requirements:
> - Open by directly answering their three questions: (a) why is the sun pointed wrong,
>   (b) why do shadows look reversed when they aim it down, (c) IS there a giant object
>   casting shadows — yes or no.
> - Then a ranked list of root causes, most-severe first. Deduplicate overlapping findings
>   across lenses into one entry each.
> - For each: what is wrong, `file:line`, the mechanism in one or two sentences, and the
>   EXACT edit to make (old → new).
> - Separate genuine root causes from contributing/cosmetic factors. Be honest about which
>   are certain and which are likely.
> - Note anything that still needs on-device verification on the Pi.
> Be concise and technical. No preamble.

---

## 4. Schemas

Findings (`FINDING_SCHEMA`) — one object with a `findings` array, each entry:

| field | type | meaning |
|---|---|---|
| `title` | string | short name of the defect |
| `file` | string | repo-relative path |
| `line` | integer | 1-indexed anchor line |
| `explanation` | string | mechanism, in Godot GL Compatibility terms |
| `symptom_explained` | string | `sun-wrong-direction` / `shadows-in-reverse` / `giant-shadow-caster` / `other` |
| `fix` | string | exact edit: file, line, old → new |
| `confidence` | enum | `high` / `medium` / `low` |

Verdict (`VERDICT_SCHEMA`):

| field | type | meaning |
|---|---|---|
| `refuted` | boolean | true if the claim does not survive |
| `reasoning` | string | why |
| `corrected_fix` | string | corrected edit if the original was wrong/incomplete, else repeat |

---

## 5. Orchestration shape

`pipeline` over the six lenses — each lens's findings go straight into their own
adversarial verification without waiting for the other lenses (no barrier). Then one
synthesis agent over everything that survived.

```
phase('Investigate')  →  6 lenses in parallel
phase('Verify')       →  per-finding refutation, fanned out per lens as it lands
phase('Synthesize')   →  single agent over confirmed + refuted
```

The original run script is preserved at:

```
.claude/projects/-home-evan-Projects-golf/02099286-f0a2-4784-b7d5-9a0199bcba2e/workflows/scripts/ww-shadow-light-diagnosis-wf_550c08c2-644.js
```

(that path is machine-local; the prompts above are the portable form. It keeps
the old `ww-` spelling because it is a record of a file that was written under
that name, not a reference into this repo.)

---

## 6. Prime suspects going in

Ranked by the lead's confidence before verification:

1. **Sun aimed up** — `scenes/utility/SCENE_test_zone_W2.tscn:52`. Certain; arithmetic is in §2.1.
   Explains (a) outright.
2. **Cloud sea casting + wrecking the cascade fit** — `scripts/world/SCRIPT_cloud_sea.gd:42-50`.
   Certain that `cast_shadow` is unset and the AABB is enormous; the open question is how
   much of it survives the transparent shadow pass. Answers (c).
3. **`cull_disabled` backface self-shadowing** — `SHADER_terrain_flatcolor.gdshader:2`,
   `SHADER_cliff_gradient.gdshader:2`. Strong candidate for (b).
4. **Flipped/faceted normals** — `scripts/world/SCRIPT_island_world.gd`. Competing explanation
   for (b); `6ac8202` claims to have fixed faceted lighting, so check whether it fully did.
5. **`directional_shadow_max_distance` unset** — defaults to 100 m against a 3600 m view
   distance. Would make shadows vanish just past the camera.
6. **Ambient 1.8 vs sun 3.0, then 16-level LUT quantisation** — contributing factor,
   flattens shadow contrast rather than inverting it.

---

## 7. Results

Continued and closed out against the **committed** tree, then **verified by rendering
the scene in Godot 4.7.1** (software GL / llvmpipe under xvfb — the same discipline as
`tests/RENDER_island_shots.gd`). The render overturned an earlier paper-only reading of
this file, so read the correction below carefully.

> **Correction to an intermediate write-up.** A prior pass of this section concluded,
> from arithmetic alone, that the committed sun points *down* at −53° and that suspect
> #1 was a red herring. **That was wrong**, and so is §2.1's stated basis vector, and so
> is commit `6ac8202`'s "the sun points down at 53 deg" — **all three made the same
> row-vs-column error**. Godot's `basis.z` is the third *column* of the matrix, not the
> third row that the flat `.tscn` triple `(0.4, 0.799, 0.449)` sits in. Loading the
> actual committed scene and reading `-DirectionalLight3D.global_transform.basis.z`
> gives **`(0.665, 0.597, -0.449)`, Y positive, elevation +36.7° — aimed UP.** The
> engine is ground truth; the hand arithmetic (mine, §2.1's, and `6ac8202`'s) was not.

### Direct answers to the user's three questions

**(a) Why is the sun pointed the wrong direction?** — Because it genuinely is, in git.
`scenes/utility/SCENE_test_zone_W2.tscn:56` (identical across every W2 commit) resolves in-engine
to light forward `(0.665, 0.597, -0.449)`, **elevation +36.7°, shining up into the sky**.
Rendered, the whole island is a near-black silhouette on a bright cloud sea (`00_gameplay`
before): the terrain *tops* receive no direct sun — only `ambient_light_energy` 1.8 — so
the landmass reads as a dark mass. That is the "light is fucked up." No script writes the
light at runtime (grep confirms), so it is purely the committed transform. **§6 suspect #1
is CONFIRMED. FIXED and verified.** Replacement transform (same azimuth, elevation flipped
to −48.1°, computed via `Basis.looking_at` and read back in-engine):

```
-transform = Transform3D(0.747, 0, -0.665, -0.531, 0.601, -0.597, 0.4, 0.799, 0.449, 0, 800, 0)
+transform = Transform3D(0.558177, 0.618025, -0.55361, 0, 0.667224, 0.744857, 0.829722, -0.415762, 0.372429, 0, 800, 0)
```

After: forward `(0.554, -0.745, -0.372)`, −48.1° down. Rendered, the island is fully lit
green terrain rising out of the cloud (see `hills_low`/`gameplay` after) — mean frame
luma on the `hills_low` view rose **0.245 → 0.434**. This is the decisive fix.

**(b) Why do shadows look reversed when aimed down?** — Two things, now separable because
the scene actually renders:
  1. **The dominant effect was (a).** With the sun up, every terrain top is unlit, so
     "aiming it down" in the editor swings large areas between lit and unlit in a way that
     reads as inverted. With the transform fixed, the faceted relief lights correctly —
     lit faces toward the sun, dark faces away — no inversion.
  2. **A real secondary artifact remains: the flat-shading facet normal**
     (`SHADER_terrain_flatcolor.gdshader:68`, `SHADER_cliff_gradient.gdshader:44`) is rebuilt from
     screen-space derivatives `cross(dFdx(world_pos), dFdy(world_pos))`, reliable only when
     a triangle covers more than a pixel or two. This camera views ~5.3 m facets
     (`chunk_cells = 24`) from 690–3150 m, so distant derivatives straddle facets and add
     shimmer. Commit `6ac8202` already softened this (`chunk_cells 48→24`); it survives at
     this distance but is minor once (a) is fixed. **Mesh normals are NOT flipped**
     (`SCRIPT_chunk_mesher.gd:181`, `nrm.y = +1.0`), winding is enforced (`_push_tri`, `:576`),
     and both shaders re-orient outward and flip on `!FRONT_FACING`. **§6 suspects #3/#4
     (backface self-shadow / flipped normals) refuted; flat-shading is a contributing
     shimmer, not a reversal.**

**(c) Is there a giant object casting shadows?** — **No.** `SHADER_cloud_volumetric.gdshader:2-3`
declares `render_mode ... shadows_disabled ...` (§2.3 truncated the render mode with "…"
and missed it), and the material is `blend_mix` — alpha-blended transparents are excluded
from the shadow pass anyway. The oversized `custom_aabb`/`extra_cull_margin` do not affect
the CSM cascade fit (cascades fit the camera frustum, not caster AABBs). **§6 suspect #2
refuted as a caster.** Hardened anyway — see root cause 2. Confirmed against the render:
no world-spanning shadow appears.

### Root causes, ranked

**1. Sun aimed up (`scenes/utility/SCENE_test_zone_W2.tscn:56`). CONFIRMED by render. FIXED.**
The transform swap above. This is the whole "light is fucked up" report; nothing else
comes close.

**2. Cloud sea left `MeshInstance3D.cast_shadow` at its ON default
(`scripts/world/SCRIPT_cloud_sea.gd`). CONFIRMED, low severity, hygiene. FIXED.** The shader
disables shadows so this is latent, not live, but one render-mode edit away from a 12 km
shadow. Set OFF explicitly, mirroring `SCRIPT_veg_scatter.gd`:

```gdscript
_mi.material_override = cloud_material
+_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
```

**3. `directional_shadow_max_distance` unset → Godot default 100 m
(`scenes/utility/SCENE_test_zone_W2.tscn`, DirectionalLight3D block). CONFIRMED. APPLIED, with a
caveat.** All terrain is 690–3150 m out, so at 100 m the elaborate PSSM split/bias config
was dead — no sun shadow reached any island. Raised to match the view:

```
directional_shadow_fade_start = 0.92
+directional_shadow_max_distance = 3600.0
```

Verified by an A/B render (fixed sun, `maxdist` 100 vs 3600): cast shadows **do** now
appear, as coherent contour-following bands in the mid-distance (a numeric diff shows
~4–9k changed samples, max Δ up to 1.8). **Caveat — the predicted `cull_disabled` speckle
is real:** the same diff shows sparse red/green self-shadow noise in the near field, the
double-sided-caster acne §6 suspect #3 warned about. It is **invisible in the final frame**
(washed out by ambient 1.8) but present under amplification. Kept the fix because the net
is clearly positive and the artifact is sub-perceptual here; the levers if it surfaces on
the Pi are `SHADOW_CASTING_SETTING_DOUBLE_SIDED` on the chunk `MeshInstance3D`s
(`SCRIPT_island_world.gd:460/470` — but that file is shared with `SCENE_test_zone_W`, so
re-verify W), or a small `shadow_bias` bump. **3.6 km × 4 splits is coarse on V3D; if it
is too soft or too costly, lower toward ~1500 m** (loses only fog-dissolved far shadows).

### Contributing / cosmetic

- **Flat-shading derivative shimmer** — see (b.2). Durable options if it bothers on-device:
  drop `flat_shading=false` at far LODs (smooth mesh normal is already correct), or bake
  real per-face normals in `SCRIPT_chunk_mesher.gd`. Not changed — the sun fix addresses the
  reported symptom and this needs a look at real facet sizes.
- **Ambient 1.8 vs sun 3.0 through the 16-level LUT** — heavy fill flattens shadow contrast
  and is why root-cause-3's shadows read faint. Not a bug; a look to take now that terrain
  is actually lit, if crisper shadows are wanted (lower ambient, or raise sun).

### Verified how

Godot **4.7.1** headless import + parse-check clean; `tests/TEST_island_world.gd` passes.
Rendered `SCENE_test_zone_W2` under `xvfb` + `--rendering-driver opengl3` (llvmpipe,
`LP_NUM_THREADS=1`) at 1280×720 with the real WorldEnvironment, terrain/cliff materials
and the palette-LUT post pass, from three viewpoints (gameplay pose, high rake, low
three-quarter), before/after the sun fix and at `maxdist` 100 vs 3600. Harness committed
at `tests/RENDER_w2_shadows.gd` (`--maxdist=N` reproduces the A/B). Milliseconds are
llvmpipe, not V3D — the *look* transfers, the frame cost does not.

### Still wants an on-device (Pi / V3D) look

- ~~`max_distance = 3600` shadow quality and cost of 4 PSSM splits over 3.6 km on V3D 7.1~~
  — **answered below**, on the cost half. The quality half still wants a device.
- Whether the near-field `cull_disabled` speckle ever becomes visible there.
- The flat-shading-at-distance decision (b.2), judged against real facet sizes.

---

## 8. Follow-up: the shadow pass was 70% of the frame's draw calls

Section 7 left the cost of 4 PSSM splits over 3.6 km as an open question for the
device. It turns out most of the answer is measurable here, because draw calls do
not care what GPU they are submitted to.

`tests/PROBE_draw_calls.gd` (new) attributes them by **ablation** — settle the
scene, read `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`, hide one system, read it
again. That is the only honest way to attribute a draw call: the same
MeshInstance3D is submitted once per pass it survives, so walking the scene graph
can tell you how many instances exist and never how many times each is drawn.

At the `ridge` viewpoint, on the config section 7 left behind:

| after removing | draws left | that system cost |
|---|---|---|
| baseline | 1,118 | |
| − shadows | 333 | **785** |
| − vegetation | 324 | 9 |
| − grass | 323 | 1 |
| − cliff bands | 217 | 106 |
| − terrain surfaces | 3 | 214 |
| − clouds / post FX | 0 | 3 |

**The whole visible scene is 333 draw calls and the shadow pass redrew it 2.4
times over.** 624 terrain instances (368 chunk surfaces + 256 cliff wall bands)
were all at Godot's `cast_shadow = ON` default, and each is submitted once per
split whose frustum it touches.

### What changed

1. **`IslandWorld.cliff_cast_shadows`, new, default off.** The walls hang *below*
   the shoreline of an island in a void, and section 2.1's sun is 17.6° above the
   horizon (measured off the scene: forward `(0.877, -0.303, -0.372)`, 3.15 m of
   throw per metre of height). A wall's shadow therefore travels outward *and
   down* — it cannot reach the plateau, which is above and inward, and by the time
   it has crossed the island it is 400 m beneath it. The only receiver under the
   shore is the cloud sea at −45 m, and the terrain's own rim already casts onto
   exactly that band from the same edge.
2. **Reach 3600 → 1800 m, atlas 8192 → 4096**, together and for one reason:
   sharpness is `reach / atlas`, so `3600/8192` and `1800/4096` are the same
   0.4395 and every shadow that still exists is pixel-for-pixel as sharp as it
   was. **This is the Pi-relevant half** — the atlas went from 256 MB of 32-bit
   depth to 64, cleared and rasterised across 4 splits every frame. Section 7's
   own caveat applies in reverse here: the *look* was verified under llvmpipe, the
   *bandwidth saving* is arithmetic and still wants a device to confirm.
3. **`IslandWorld.terrain_shadow_lod`, new, default off (−1).** Chunks at or past
   an LOD level stop casting. Rides the existing ladder, so it needs no new
   distance test and survives LOD swaps for free (`_install` caches one node per
   chunk-and-resolution, so a node built at level 3 is only ever shown far away).

   **It has to exempt coastal chunks, and that is not a detail.** The export reads
   a chunk's LOD as a stand-in for its distance, which is true of an inland chunk
   and false of a coastal one: every chunk holding coastline is pinned to
   `coast_lod` by geometry at any range. With `coast_lod` at 2, a naive
   `terrain_shadow_lod = 2` stops **the shore under the player's feet** from
   casting — permanently, at point-blank range, 450 m inside where the fog even
   starts. Measured, that trap was 83 of the level-2 saving (397 draws naive vs
   480 exempt); the exemption is asserted in `test_island_world`.

1800 m is where the fog has finished, and getting that right needs **both** fogs:
`MAT_terrain_splat_w2`'s own falloff is **squared** off an 850 m start
(`fog_distance_power = 2`), which is nothing like the Environment's plain
exponential. Multiplied, the contrast a shadow can still show is 19.9% at 1200 m,
3.1% at 1800 m, 0.2% at 2400 m — and `directional_shadow_fade_start = 0.92` puts
the dither-out band at 1656–1800 m, between 5.4% and 3.1%. At 1200 m that band
would land at 24% and read as a ring on the ground; that is why 1800 and not
lower.

### Measured, 1280×720, four viewpoints

| viewpoint | before | after | cut |
|---|---|---|---|
| gameplay (the shipped pose) | 1,476 | 823 | −44% |
| rake_high | 1,452 | 915 | −37% |
| hills_low | 1,106 | 791 | −28% |
| plan | 1,583 | 818 | −48% |

Triangles fall with them (297k → 185k at `gameplay`) because the shadow pass
submits geometry, not just calls.

### The atlas, not the reach, is the frame-time half

Draw calls were the brief; frame time is what anyone actually wanted. Section 7
recorded that llvmpipe milliseconds do not transfer to V3D and that stays true —
but the **ratio between two rows of the same sweep** is fill against fill, and
fill is exactly what a weak GPU runs out of. At 960×540, vegetation off, `ridge`:

| config | draws | ms/frame |
|---|---|---|
| shipped, 3600 m / 8192 | 1,118 | 544.3 |
| cliffs cast no shadow | 907 | 487.6 |
| + 1800 m reach, atlas still 8192 | 741 | 514.8 |
| + atlas 4096 (**shipped**) | 741 | **430.9 (−21%)** |
| shadows off entirely | 333 | 306.3 (−44%) |

Read the third and fourth rows together: they are the **same 741 draw calls** and
differ by 84 ms. Halving the atlas is worth 16 of the 21 points, and cutting the
reach on its own is worth about 5 — the reach is the draw-call lever and the
atlas is the fill one. It is also the one that scales with the device rather than
the scene: 8192² at 32 bits is 256 MB of depth cleared and rasterised four splits
deep every frame, against a Pi's shared LPDDR4. Absolute figures here are
llvmpipe and mean nothing on device; the 3-vs-4 comparison is the transferable
part.

### What it costs to look at

Per-pixel image diffs on this scene are **not** a usable measure and it is worth
recording why: the vegetation is wind-animated and the frame ends in a 16-level
palette-LUT dither, so two runs of the *identical* config differ by several
units per pixel wherever a plant is. Mean frame luma is the stable statistic, and
across all four viewpoints it moves by 0.02–0.1% (e.g. `gameplay` 0.4994 →
0.4993, stddev 0.1682 → 0.1685). One LUT level is 6.25%.

### Left on the table

`terrain_shadow_lod` is worth another 741 → 601 at level 3 and 741 → 480 at level
2 — the latter more than the reach and the cliffs together, and it works at any
reach. It is off by default because
it is the one cut here that costs an image: level 2 is only 400 m out, where 62%
of a shadow's contrast still survives, and what goes is the dark side of every
middle-distance hill. On a stylised island under a raking sun that is most of
what makes the ground read as shaped rather than painted. Turn it on for the Pi
if the honest cuts are not enough; look at it first.

`scripts/autoload/AUTOLOAD_perf_tier.gd` already seeds a tier from a CPU benchmark and governs
`detail` / `ai_stride` live. It does **not** touch shadows, and the shadow atlas
is now the most expensive single thing a weak device renders — a tier-driven
`directional_shadow_atlas_set_size` plus a reach step is the obvious next lever
and is not built.
