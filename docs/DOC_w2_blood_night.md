# The blood night — normalcy vs. the ontological nightmare, in SCENE_test_zone_W2

The brief: everything goes over to a deep red, as though the sky had been covered
in blood and all the light in the world were filtering down through it — and the
open sky *beyond* the cumulus ring on the horizon goes essentially **black**,
because the blood is the lid, not the source.

**It is not a day/night cycle**, and the node is only still called `TimeOfDay`
because renaming it would break every NodePath and harness pointing at it. There is
no clock. There are two states — ordinary overcast daylight, and the world gone
wrong — and a bool that crosses between them in **three seconds**. Nobody can stand
still for five minutes and catch it half way round; when it turns, it turns because
something in the game turned it (`docs/DOC_notes_jogolf_mechanic.txt`: *"ontological concerns increase"*).

**Daylight is 100% and is meant to be unremarkable.** The whole effect is a
contrast, and the thing being contrasted against has to be the plain daylight this
scene is already known by.

| | |
| --- | --- |
| controller | `scripts/SCRIPT_sky_cycle_controller.gd` |
| preset | `scripts/SCRIPT_sky_cycle_preset.gd` + `data/SKYCYCLE_w2_blood_night.tres` |
| scene | `scenes/utility/SCENE_test_zone_W2.tscn` (the `TimeOfDay` node) |
| globals | `tod_haze_tint`, `tod_art_tint` (project.godot `[shader_globals]`) |
| sky | `shaders/SHADER_sky_void_gradient.gdshader` via `materials/MAT_sky_w2_void.tres` |
| test | `tests/TEST_w2_cycle.gd` |
| screenshots | `tests/RENDER_w2_cycle.gd` |

---

## The thing that had to be fixed first

**The TimeOfDay bus in W2 was never wired, and had never been wired.**

`sun_pivot` and `world_environment` are node-typed exports. A `.tscn` stores one of
those as a `NodePath`, and Godot only turns it back into a node for properties
named in the node header's `node_paths` array:

```
[node name="TimeOfDay" type="Node3D" parent="." node_paths=PackedStringArray("sun_pivot", "world_environment")]
```

W2 is hand-authored and that array was absent. Without it the `NodePath` is
assigned to a `Node3D`-typed property, the type check fails silently, and the
property stays `null`. `SCENE_test_zone_A2` and `SCENE_test_zone_A` both carry the
array and both resolve; they were written in the editor, which emits it.

What that cost is the whole of the scene's pseudo-lighting. `_apply` publishes
`tod_sun_dir` and `tod_sun_color` only inside `if sun_node:` — so with the pivot
null it published **neither**, and the island has been lit its entire life by the
`project.godot` fallbacks: a pure **white** sun at full strength, aimed down the
default `(0, 0.8, 0.6)` rather than down the transform that three paragraphs of the
`SunPivot` comment and the whole of `DOC_w2_shadow_light_diagnosis.md` exist to defend.
A white sun at 1.0 against an ambient of 0.16 swamps the ambient completely, which
is why the shipped island read as near-flat albedo, and why the figures the scene's
own comment quotes for a lit and a shaded face (0.41 and 0.16) had never been what
the frame contained. The Environment was unreached the same way —
`ambient_light_color`, `ambient_light_energy` and `fog_light_color` are all written
behind `if world_environment`.

It was invisible because the scene was **parked**: `advance_with_time` was off and
the phase never moved, so a bus that publishes nothing and a bus that publishes the
same thing every frame look identical. Everything downstream was tuned against the
picture, and the picture was self-consistent — just not the picture the numbers
described. Turning the cycle on is what made it a visible fault: the plants and the
sky recoloured, being on their own multipliers, and the ground under them did not
move at all.

**Fixing it changed the daytime look, and then the daytime look was put back.**

With the wire in and the authored `day_sun_energy` of 0.25, mid-distance ground on
the `ridge` viewpoint went from `(87, 135, 72)` to `(47, 76, 44)` — the island got
its shading back and lost a third of its brightness. That was the right first move
(the authored values are the documented intent, and re-tuning against a bug is how
you get two bugs) and it was the wrong final answer, because **normalcy has to be
the daylight this scene is already known by.**

So `day_sun_color` is white and `day_sun_energy` is `1.0`, which is *exactly* what
the fallback was doing. The factor-of-PI argument in the scene comment — the engine
divides by PI for the lambert term and an unlit shader does not, so an energy
carried over from a lit scene blows the island out — is still sound, and it
described a picture nobody had ever seen. Six hundred lines of per-layer grading in
`MAT_terrain_splat_w2.tres` were then tuned against the *fallback*, so the grade and
the white sun agree with each other and both disagree with the derivation. The
picture wins. Anyone re-deriving that grade from first principles should start here
and expect to move both together.

What the fix does keep is everything else the bus was silently not doing: the sun's
real **direction** (off `SunPivot`, not the default vector), the ambient and bounce
hemisphere, and the Environment's ambient and fog — none of which were reaching
anything before.

`tests/TEST_w2_cycle.gd` asserts the references are live **after `instantiate()`**
rather than checking that a NodePath appears in the file — which it did, and which
told you the opposite of the truth.

---

## The two buses

W2's look is a family of colours that all have to move together, and the scene
documents at length (in `MAT_sky_w2_void.tres`) why: **one haze value**, the exact
neutral `0.30`, shared by fourteen materials, the Environment's fog and the sky's
own `bottom_color`, so that fogged distance and empty low sky resolve to the same
palette entry instead of drawing a line across the world.

That pin is exactly why the cycle was unusable here. Recolour the sun and the world
recolours against a horizon that does not.

So the family is on the bus, as **two global multipliers**:

| global | multiplies | consumers |
| --- | --- | --- |
| `tod_haze_tint` | every fog / haze / veil colour | terrain, cliff, vegetation, cloud sea, horizon band, crash debris, plates, hull, smoke, and the sky's `bottom_color` |
| `tod_art_tint` | the albedo of everything with no lighting model | vegetation, grass, cloud sea, horizon band, smoke, the zenith vortex, and `sea_surface_color` where the cliff dissolves into the deck |

### Why multipliers and not colours

Both default to **white** — in `project.godot`, and at all three phases of the
cycle — and white times anything is anything. So:

* every shader takes one unconditional multiply and needs **no per-material enable
  flag**, which is the thing that would have been forgotten somewhere;
* every scene that has not authored a tint (W, A, A2, D, …) renders **exactly** the
  pixels it rendered before, provably rather than by inspection.

An absolute `tod_haze_color` was the alternative and is worse for one concrete
reason: W2 hazes to `0.30` and `SCENE_test_zone_W` hazes to `0.089`. An absolute
bus value has to be one of them, so every shader would need a `use_bus_haze` bool
and every material in both scenes would need it set correctly.

### The contract is now enforced by construction

The controller writes the sky's bottom edge as

```
bottom_color = sky_haze_base * haze_tint          # 0.30 * tint
```

and every fog in the scene is `its own pinned 0.30 * the same haze_tint`. Same
product. They cannot come apart at any phase of the cycle. Previously this was
fourteen files that had to be edited together by hand, and the material comments
say so in as many words.

### Why the art tint is a separate bus

`SHADERINC_island_light.gdshaderinc` recolours the terrain and the cliff the instant
`tod_sun_color` and friends move, because the island computes its own light off
those globals. **Nothing else in the scene does.** The vegetation, the grass, the
volumetric cloud sea, the horizon cloud band and the smoke were never lit by
anything and have no term a lighting cycle can reach. Under a cycle that moved only
the lit surfaces, W2's firs stayed noon-green over ground that had gone red — which
reads as a broken material, not as nightfall.

### What the art tint deliberately does not reach

**Fire.** `fire_particle`, `fire_sprite` and `molten_glow` read neither global. A
flame, an ember and molten rock are light *sources*; tinting one by the colour of
the night it is lighting is backwards. `veg_billboard`'s ember block is the same
rule inside a shader that does take the tint: the tint is on `ALBEDO`, the embers
are added after the fog and are the one value allowed past 1.0 so the environment's
glow blooms them. The test asserts the exclusion, because it looks like an omission.

---

## The sky

`sky_material` on W2's `TimeOfDay` was deliberately null, because
`sky_void_gradient` has none of the rotating panorama's parameters — so the cycle
could recolour the island but not the dome it is silhouetted against along its whole
coastline. `drive_void_sky` closes that with five writes, four of them **derived**:

| uniform | written as |
| --- | --- |
| `bottom_color` | `sky_haze_base * haze_tint` — the haze contract |
| `horizon_glow` | `sky_glow_base * haze_tint` — light pooling on the overcast's edge is haze |
| `sun_glow_color` | `sky_sun_glow_base * (blended sun / day sun)` — normalised, so it is exactly the authored value at day |
| `vortex_color` | `sky_vortex_base * art_tint` — the swirl is unlit greyscale artwork, like the clouds |
| `top_color` | authored per phase |

`top_color` is the one value authored rather than derived, and that is the whole
reason the brief works: it has to **leave** the haze family. The dome goes to
`(0.015, 0.004, 0.004)` at night while the haze at the horizon stays at
`0.30 * (0.90, 0.25, 0.20)` — lit blood under black. No single multiplier on 0.666
produces both.

The panorama block in `_apply` is now skipped entirely when `drive_void_sky` is on.
Godot does not reject a `set_shader_parameter` for a name the shader has never heard
of — it stores it on the material — so pushing the seven panorama uniforms at the
void sky was harmless at runtime and quietly wrong in the editor, where this `@tool`
script would have written seven dead parameters into `MAT_sky_w2_void.tres` the next
time anyone saved the scene.

For the same reason `manual_time_of_day` stays at **0.45**: that is the phase the
editor renders, it is inside the day band, and every value the sky material would be
written at that phase is the value already in the `.tres`. Opening the scene in the
editor therefore cannot dirty that resource. Move it and that stops being true.

---

## The numbers

Day is unchanged from what the scene authored. Multiplied out the way the scene's
own comment does:

```
                  colour              energy    published
day    sky        0.520 0.545 0.580    0.30     0.156 0.164 0.174
       ground     0.380 0.355 0.320    0.30     0.114 0.107 0.096
       sun        1.000 0.950 0.820    0.25     0.250 0.238 0.205

night  sky        1.000 0.075 0.055    0.32     0.320 0.024 0.018
       ground     0.920 0.085 0.065    0.32     0.294 0.027 0.021
       sun        1.000 0.085 0.055    0.21     0.210 0.018 0.012
```

so a fully-lit top face lands near **0.41 neutral** at day and **0.53 red against
0.04 green and 0.03 blue** at night. That is the brief held to a number: the frame
keeps its luminance — gains some, which is the point of a night that is not dark —
and loses two of its channels.

The tints:

```
              haze_tint              art_tint             sky_top
day       1.00 1.00 1.00         1.00 1.00 1.00      0.666 0.666 0.666
trans     0.88 0.48 0.38         1.05 0.60 0.46      0.300 0.150 0.120
night     0.82 0.135 0.10        1.40 0.17 0.13      0.010 0.001 0.001
```

`night_art_tint` is **over 1.0 in red** on purpose. It is not "the light the clouds
receive", it is the whole of what the cycle does to a surface that has no light term
at all, so it has to carry the level as well as the hue — the cumulus ring is the
brightest thing in a night frame and is supposed to be, because it is the source.

### Why the night's bounce is brighter than its sky, inverting the day

At noon the dome overhead is the bright thing and the cloud sea below is the darker,
warmer one, and `SHADERINC_island_light.gdshaderinc` lerps between them by the world normal's
Y — that contrast *is* the shading on a landform this size. At night the dome is
**black** and the lit things are the ring and the sea, so the relationship turns
over: the light comes from the horizon and from below, and a cliff face picks up
more of it than a fairway does.

They are within 10% of each other rather than fully inverted, because the
environment ball still distributes them by a daytime measurement — see the caveat
below.

### Two passes it took to get there

**The first night was a third darker** (ambient 0.26, sun 0.17, both tints down with
them), which put a lit face at 0.41 red — exactly the day's figure, on the theory
that "not dark" meant "the same luminance". Rendered, it read as dusk rather than as
a lit night: the sky above the ring is *black* at this phase and the dome is most of
the frame, so matching the day's lit face still loses most of the day's light.
Measured on `ridge`, mid-distance ground came back at 39/255 red against the day's
47 — darker than noon, not brighter. The shipped values are that pass lifted by half
in linear terms, about a third once sRGB has compressed it.

**The green had to be crushed twice.** At `night_sun_color = (1, 0.24, 0.15)` a
patch of mown fairway in the middle distance stayed visibly **olive** in an
otherwise red frame. That is not a bug in the bus, it is arithmetic: the fairway's
albedo is a strongly saturated green, so `0.85 green × 0.14 light` and
`0.20 red × 0.61 light` come out equal and the palette LUT picks a green entry for
the result. Taking the light's green to 0.087 — a 7:1 red ratio rather than 4:1 —
makes red win on every albedo in the scene. Anything that keeps a hue under this
night is a surface whose albedo is more saturated than the light is.

**And then a third pass took it further, to 13:1.** Saturation and level are not
independent dials here, which is worth stating because "more saturated" and
"darker" sound like opposing requests and are not. Saturation of the light is
`(max - min) / max`, and red is already pinned at 1.0 — so the *only* way to raise
it is to take green and blue down, which lowers luminance as a side effect, because
green carries 71% of it. The shipped values are 13:1 red-to-green at a level 15%
below the 7:1 pass, and most of that 15% is the saturation move's own shadow rather
than a separate darkening. Pushing saturation further from here does not need a
matching darkening; it *is* one.

The palette is what makes this safe to keep pushing. ps1-soft carries fully
saturated reds at 0.063, 0.094, 0.125, 0.157, 0.251 and 0.282 — `G = B = 0`
exactly — so the large flat areas of near-pure red that a 13:1 light produces have
entries to land on and dither between, rather than the two-entries-eight-steps-apart
problem that shaped the grey look.

---

## The environment ball, and the second bake

`SHADERINC_island_light.gdshaderinc` is the whole of the island's lighting — every surface of
the landmass is `render_mode unshaded`, there is no light node in the scene, and
what that function returns is multiplied into albedo and goes to screen. Its
ambient term is an **octahedral environment ball**: a 66×66 texture (64 core, one
texel of gutter across the fold) sampled by the **world** normal, baked against
this scene's actual sky by `scripts/SCRIPT_bake_env_ball.gd`.

It stores **weights, never colours**, which is the only way a bake and a cycle can
coexist:

```
R = share of the lobe's light arriving from the sky
G = share arriving from the cloud deck        (R + G == 1)
B = how much light that lobe collects, vs the best-lit normal

ambient = (tod_sky_color * R + tod_ground_color * G) * B
```

### The problem, and it was real

**A ball measures one environment, and W2 has two.** They are not a tint apart —
the angular profile *inverts*. Measured over the shipped pair:

| normal | day level | night level |
| --- | --- | --- |
| up | 0.997 | 0.997 |
| 45° up | 0.825 | 0.876 |
| horizon | 0.573 | **0.718** |
| 45° down | 0.332 | **0.739** |
| down | 0.294 | **0.800** |

At day the dome is the bright thing and the deck is dark, so an up-facing surface
collects 3.4× a down-facing one. In the nightmare the dome is authored to `0.01`
sRGB and the light is coming from the burning cumulus ring, the cloud sea and the
vortex, so the spread flattens to 1.25:1 and **the horizon becomes the darkest
direction** rather than a middling one — something that cannot happen under a
bright dome. No multiplier on the day ball produces that.

So there are two bakes now, mixed at runtime by `tod_env_blend` (0 at day, 1 in the
nightmare, published off the same phase weights as everything else). The second
fetch sits behind `if (tod_env_blend > 0.0)` — a global, so uniform control flow —
and the day path costs exactly what it always did.

`SCRIPT_bake_env_ball.gd --phase=day|night` writes them, and the night pass **reads
`SKYCYCLE_w2_blood_night.tres`** rather than restating the night colours, so the
bake cannot drift from the look. Only the scene's own bases stay constants in the
baker, which is the same split the preset itself makes.

### Two things the bake was getting wrong

**It ignored the horizon cloud band entirely.** At day that was nearly free — the
band's front layer is the artwork (opaque-region mean `0.5334` linear, measured)
times `front_tint` 0.38 sRGB = 0.1195 linear, so ≈ `0.064`, within a whisker of the
low sky's own `0.073`. But the band takes `tod_art_tint` and the dome does not, so
at the nightmare end it goes from indistinguishable to **the brightest thing in the
upper hemisphere by two orders of magnitude**. A night bake without it says the sky
is black; the picture says the sky is a ring of burning cloud. It is modelled as a
ring of measured mean radiance over its measured angular extent rather than
transcribed — a cosine lobe integrates over a solid angle thousands of times larger
than any feature in that shader, so what survives is total energy, not profile.

**It measured radiance as luminance.** That distinction does not exist at the day
end, where the whole "one haze value" contract is about exact neutrals — but at the
other end the environment is 13:1 red, and luminance weights green at 71%. It would
have reported a sky about four times darker than the one the eye is given. The
baker now reduces with an **unweighted mean of linear RGB**, which is the reduction
that treats the channels the way the shader does: hue is already the bus's job, and
`B` only has to rank directions against each other.

### The surprise

The night ball does **not** collapse to a bottom-lit world, which is what the
physics looked like it was going to say. `up` stays at the peak — because the
**vortex** takes the art tint, so the swirl over the zenith is a large, bright red
source directly overhead. The dome between the vortex and the cloud ring is what
goes dark, which is why the *horizon* is the night's darkest direction. That is a
measurement, not a choice, and it is the reason the ground does not go black.

### What actually changed on screen

Almost nothing on the fairway, and that is correct: up-facing normals read `0.997`
in both bakes, so flat ground is identical by construction. The change is on
**vertical and downward-facing surfaces** — the cliff wall, steep scree, the
undersides of the rim — which pick up between 25% and 170% more ambient in the
nightmare than the day-only bake was giving them.

### The old caveat, retired

This document used to carry a paragraph saying the ball "keeps saying upward-facing
ground is best lit" in the nightmare and that it "cannot be fixed by re-baking:
the ball is one static texture and the cycle is continuous." The second half was
the error — one texture cannot span a continuous cycle, but the cycle only has two
ends, and two textures and a `mix` span it exactly.

### A stale claim in the include, corrected

`SHADERINC_island_light.gdshaderinc` asserted that the R/G split "comes out within a percent
of `n.y * 0.5 + 0.5`". That is true for a **solid-angle**-weighted half-space and is
a standard result — but `_weights` deliberately weights the shares by **radiance**,
because the solid-angle version applies the deck's colour at the deck's share of the
*sky* rather than of the *light* (measured: it over-weighted the deck by 2.9× on an
up-facing normal). Once radiance-weighted, the split stops tracking `n.y`: the
shipped day ball reads **0.749** sky at a horizontal normal, not 0.500, because the
half of the sphere that is sky is about four times brighter than the half that is
deck. `tests/TEST_env_ball.gd` has always asserted the 0.749; only the comment was
wrong.

---

## The palette got lucky, and it is worth knowing why

`SHADER_post_dither.gdshader` snaps every pixel to `data/palettes/PALETTE_ps1-soft.hex`. That palette's
**neutral** ramp has a notorious hole — entries at 0.031 and then nothing until
0.282 — which is most of the reason W2's haze value is 0.30 rather than the 0.089 it
started at.

### The palette pushes it toward crimson, and that is why it reads as blood

Worth knowing before anyone re-derives these numbers from the authored light: **the
frame comes out with more blue in it than green, and the light does not.** At the
shipped values a lit face is `(0.530, 0.042, 0.029)` — green above blue — while the
measured frame mean on `ridge` at night is `(0.212, 0.008, 0.026)`, with blue three
times green. The LUT did that, not the lighting.

The reason is which entries a near-pure red can reach. Of the twenty ps1-soft
entries with `r > 0.05` and `g < 0.05`, the ones the quantiser actually lands on
through the useful part of the range are

```
280000  0.157 0.000 0.000        480008  0.282 0.000 0.031
200008  0.125 0.000 0.031        680010  0.408 0.000 0.063
```

— every one of which carries a little **blue** and exactly **zero green**. So the
harder the light is pushed toward pure red, the more the snap drags the result
toward crimson rather than toward rust. That is the difference between this looking
like blood and looking like an orange filter, and it is free: it comes out of the
palette rather than out of a colour anybody typed. Do not "fix" the discrepancy by
putting blue back into the light — the authored value and the drawn value are
allowed to disagree here, and the LUT is the reason the drawn one is better.

Its **red** ramp has no such hole. Sorted by value, the saturated reds run 0.063,
0.094, 0.125, 0.157, 0.188, 0.220, 0.251, 0.282, 0.314, 0.345, 0.408, 0.471, 0.533
— thirteen entries through exactly the band this night lives in. So the large flat
areas of dark red that the sky, the haze and the cloud sea produce have somewhere to
land and dither between, and none of the banding arguments that shaped the grey look
apply. A blood night is, by accident, the best-served hue in this palette.

---

## The switch

`use_nightmare_switch` replaces the clock. It drives exactly the same `t` a clock
would have driven — lerped from `normal_phase` (0.45) to `nightmare_phase` (0.85)
— so the blend, the tints, the sky writes and every test stay **one code path**;
only the thing moving `t` is different.

```gdscript
$TimeOfDay.set_nightmare(true)      # the world goes wrong over `nightmare_seconds`
$TimeOfDay.nightmare_blend()        # 0..1, for a HUD or an audio bus to ride
```

Three properties worth knowing:

* **Constant duration, not constant rate.** `nightmare_seconds` is how long the
  *whole* crossing takes, so retargeting the anchors does not silently retime the
  flip. A flip interrupted half way costs half the time to undo, which is what you
  want the first time anything toggles it twice quickly.
* **It passes through the transition band, and that is the best part.** Crossing
  0.40 of the clock in 3 s puts the 0.12-wide sunset band at about **0.9 s** of
  ember — the half-breath of warning before the red arrives, and again on the way
  back. Those colours are authored to be seen in motion and nowhere else, which is
  why they are hotter and less plausible than a real sunset.
* **Smoothstepped**, so the ends ease and the middle is quick. Linear over three
  seconds reads as a fader being pulled; this reads as something arriving.

`advance_with_time` loses to it when both are set, and the two are meant to be
mutually exclusive: one is a world with a sun in it, the other is a world with a
switch. Scenes A and A2 keep the clock.

`tests/TEST_w2_cycle.gd` steps the real controller and measures the crossing at
3.00 s each way — it has to run from `_process` rather than `_initialize`, because
nothing is inside the tree during `_initialize` and `sun_pivot.global_transform`
returns identity with an error for a node that is not.

---

## The broadcast

The flip is not only a sky, and everything else that has to move with it would
otherwise start its own three-second timer on the frame the switch is thrown. Four
timers agree right up until somebody interrupts a flip half way — which
`set_nightmare()` explicitly supports, and which is the first thing anyone does the
first time they can toggle it. So the crossing is **published**:

```gdscript
signal nightmare_started(to_nightmare: bool)          # the cue — a decision was made
signal nightmare_stage_changed(stage: float)          # 0..1, only on frames it moved
signal nightmare_beat(stage: Stage, to_nightmare: bool)
signal nightmare_finished(in_nightmare: bool)
```

`Stage` is `NORMAL / COLLAPSE / FLASH / REVEAL / NIGHTMARE`, named for what the sky
is doing, because that is what a listener synchronises to — a sting lands on
`FLASH`, not on `0.50`. The thresholds are in `SkyCycleController.STAGE_STARTS`.

**Ride `nightmare_stage()`, not `nightmare_blend()`.** The second is the switch's
own fader and is zero in a scene running the clock, zero under a hand-set
`manual_time_of_day`, and zero in every capture harness in `tests/` — all three of
which move the world through the same states without touching it. The first is
derived from the **phase**, so one definition covers all four routes:

```gdscript
stage = clamp((t - normal_phase) / (nightmare_phase - normal_phase), 0, 1)
```

which is 0 at `normal_phase` and 1 at `nightmare_phase` by construction, with the
switch's own smoothstep already folded in. It is also why a strip photographed by
sweeping `manual_time_of_day` shows the same choreography the switch produces at the
matching instant, which is what makes the strip evidence about the flip rather than
about the harness.

`nightmare_started` is emitted from the `nightmare` setter rather than from
`_process`, because that is the only place that knows a *decision* was made: by the
next frame, a flip that was just thrown and a flip already running look identical.

---

## The four beats

`scripts/world/SCRIPT_nightmare_sky_director.gd`. The controller moves the world's
**colour** across the crossing and has always done that as one continuous blend,
which is the right model for a colour and the wrong one for an **event** — nothing
about a lerp says *the old sky was taken away and a new one arrived*. The director
is the event, and it is a listener with no clock of its own:

| stage | beat | what happens |
|---|---|---|
| 0.00 – 0.50 | `COLLAPSE` | the vortex winds up — faster every frame — while its disc shrinks toward the zenith, and fades out over the last quarter of that |
| 0.50 – 0.74 | `FLASH` | full frame, blood red, hard attack and a longer decay, peaking at 0.57 |
| 0.58 – 0.86 | `REVEAL` | `sky/SKY_eye_hdri.hdr` fades up over the grey, under the tail of the flash |
| 0.62 – 1.00 | — | a massive red lens flare lights at the zenith, in the pupil of the eye the panorama puts there |

**Every beat is a pure function of the stage, so the way back is free.** Coming
back, the pupil dims, the dome fades out, the world flashes again and the vortex
spins down out of the point it vanished into — no second code path, nothing to keep
in step, and an interrupted flip turns round with everything else.

Four things in it are less obvious than they look.

**The spin is an integral, and it is the one exception.** Angle is history, not
state. `_extra_a` accumulates and never runs backwards, because a swirl slowing
down does not un-rotate — driving the angle itself off the stage would rewind the
arms on the way back, which reads as the footage being played in reverse. It is
also why the boost is added as an **angle** rather than by rewriting
`vortex_spin_rad_per_sec`: the shader spins by `offset + rate * TIME`, so raising
the rate moves the arms by `(new - old) * TIME` instantly — thousands of radians a
few minutes into a session.

An earlier draft released the accumulator back to zero on settling at `NORMAL`, to
hand the material back the value it ships with. That is a visible half-turn snap of
the arms on the last frame of every return trip, paid for a cosmetic property of an
in-memory resource that is never written to disk. `fposmod` keeps it bounded
instead.

**The collapse has to end before the flash peaks, not on it.** Both sat at 0.55 in
the first draft and the swirl's last frame was also the flash's brightest — so the
point did not wink out, it was painted over, and what that reads as is a transition
that was *interrupted* rather than one that completed. 0.50 leaves a beat of empty
sky for the flash to land in. `tests/TEST_w2_cycle.gd` asserts the whole ordering.

**The flash is under the palette pass.** `PostFX` is layer 128; the flash rect is
at 80. Above it, the flash would be the one surface in the scene that is not
quantised — a smooth red gradient over a posterised world, which reads as a UI
element that has escaped. And `flash_color` is not pure red, for the reason the
next section gives.

**The eye panorama is not allowed to reach the horizon.** This is the only load-
bearing part. The HDRI is black along its bottom edge and `bottom_color` is the
contract with fourteen fog values, so a dome that faded in all the way down would
paint black over the low sky while every fog stayed lit — exactly the line across
the world the haze scheme exists to prevent. `eye_fade_low` (0.06) sits above
`horizon_height - horizon_softness` (0.05), where `bottom_color` stops being pure,
and the fade multiplies the **blend** rather than the colour: fading the panorama
toward black would still darken the sky under it.

### The eyes are as red as this palette goes

`sky/SKY_eye_hdri.hdr` is 4096×2048 equirectangular, every texel exactly 10:1:1
R:G:B, eyes at a true-HDR **6.0**, black between them and black below
EYEDIR.y ≈ −0.2. `tests/PROBE_eye_hdri.gd` measures it. There is a large eye
centred on the pole — a solid bright core 4.3° in radius, then a dark ring, then
the iris — and the flare goes in the middle of it.

`eye_energy` 0.16 brings 6.0 down to 0.96, and **that is the top of the range, not a
preference**. Walk the LUT up the pure-red axis with green and blue pinned at zero:

| quantised r | palette entry |
|---|---|
| 8 – 9 | `680010` (104, 0, 16) |
| 10 – 12 | `882828` (136, 32, 40) |
| 13 – 15 | `a84820` (168, 72, 32) |

The whole top fifth of the axis resolves to one entry. **`ps1-soft` has no bright
saturated red at all** — you can have bright and rust, or saturated and dark, and
nothing else. Anything from `eye_energy` 0.14 to 0.24 lands on `a84820`; 0.16 sits
in the middle of that plateau rather than near an edge, so the eyes do not dither
between two entries and come out mottled. Past 0.30 the green channel clears the
next quantiser step and the entry becomes `c86848`, which is brighter and reads as
salmon — a pink sky, not a blood one.

This is the same fact as *The palette got lucky* above, seen from the other side:
the LUT's reds all carry blue and drop green, and the practical ceiling on
"bright red" in this scene is a rust.

### The pupil

`scripts/SCRIPT_space_sun.gd` is `SCENE_test_zone_A2`'s lens flare, and it self-wires by
hunting the tree for a `DirectionalLight3D`. **W2 has no light at all**, so the hunt
would recurse every node every frame and never find one. `direction_override` is the
one addition that makes it work here — point it straight up and every element
(halo, streak, ghost chain) still works, because none of them ever cared that the
bright point was a star.

Four smaller exports came with it, all defaulting to the space-scene behaviour:
`show_disc` (off here — the sky already draws the thing the disc would stand for),
`flare_scale` (`flare_intensity` scales brightness and saturates; this is the dial
for "massive"), `core_whiteness` (a white pinpoint is what makes a flare read as a
*star*; a pupil has to stay the colour of the eye it is in), and `fringe_warm` /
`fringe_cool` — the streak's chromatic split was hardcoded warm/cool, and in a scene
where the whole palette is red a blue line under the flare is the only cool pixel on
screen. It reads as a bug in the flare rather than as an artefact of a lens.

`master_alpha` is what the director drives, and the `nightmare_beat` signal puts the
flare's `_process` to sleep whenever the world is settled at `NORMAL` — it runs a
full screen projection and a physics raycast every frame regardless of its alpha,
and 99% of a session is daylight.

### The night ball was baked against a sky that no longer exists

The two-ball scheme in *The environment ball* above is unchanged, but the **night**
end is a different sky now and `scripts/SCRIPT_bake_env_ball.gd` had to follow it twice
over: the vortex is not dimmed at the nightmare end, it is **gone**, and what
arrives in its place is a genuine HDR source rather than a dark cap.

Both are read off the director rather than restated — `vortex_strength_at(1.0)`,
`vortex_coverage_at(1.0)`, `eye_blend_at(1.0)`, `eye_energy` — the same "one place
for the look" argument `_configure` already makes about the preset. Retime a beat
and the bake follows.

The panorama is ring-averaged by elevation, the way the vortex is ring-averaged by
radius, and for the same reason: a cosine lobe integrates over a solid angle
thousands of times larger than any eye in the artwork, so what survives the
convolution is the energy per elevation band and not the arrangement within it. One
trap — a Radiance `.hdr` imports as `RGBE9995` and `get_pixel` hands back **linear**
radiance, so it must *not* go through `_mean_linear`'s sRGB decode.

The day ball is byte-identical after all of this, which is the check that the change
is confined to the end it was aimed at.

---

## Reusing it: the preset

The look is thirty-odd numbers, not a sky material, so it is saved as a
**`SkyCyclePreset`** resource — `data/SKYCYCLE_w2_blood_night.tres`. A
`MAT_sky_blood.tres` would have captured the dome and nothing else, and only at one
phase, statically, when the whole point is that these move.

`SkyCycleController._apply` binds it in one line:

```gdscript
var src: Variant = preset if preset != null else self
```

and reads every blended field off `src`. The preset is a **drop-in stand-in** for
the node's own exports rather than a second code path, so there is one blend and it
does not know where its inputs came from. The field names have to match; the test
asserts the two sets agree rather than waiting for a runtime error on the frame
somebody first assigns one.

**What is in it:** everything the cycle blends — the phase boundaries, all three
lighting blocks, both tint families, the three dome colours.

**What deliberately is not:** `sky_haze_base` and its siblings, and the wiring and
pacing. That split is the entire reason a preset can travel. W2 hazes to the exact
neutral `0.30` and `SCENE_test_zone_W` hazes to `0.089`; both are correct, each is a
property of *that scene's* own sky and fog, and neither is a property of the
weather. The tints are multipliers on whichever a scene holds, so the same nightmare
lands correctly on either without knowing which it is in.

### To put it on W

W already draws the same `sky_void_gradient` shader through `MAT_sky_void.tres`,
with the same `0.666` dome and `0.85` horizon glow — it differs only in hazing to
`0.089`, and in having a real `DirectionalLight3D` where W2 has a bare pivot. So:

1. add a `SkyCycleController` node;
2. point `directional_light` at W's light and `world_environment` at its
   `WorldEnvironment` — **with `node_paths=PackedStringArray(...)` in the node
   header**, or they resolve to null, which is the bug the top of this document is
   about;
3. set `sky_material` to `MAT_sky_void.tres` and `sky_haze_base` to W's own
   `Color(0.089, 0.089, 0.089)`;
4. turn on `drive_void_sky` and `use_nightmare_switch`;
5. assign `SKYCYCLE_w2_blood_night.tres`.

Nothing in the preset changes. To make a different night, duplicate the `.tres` and
edit the numbers.

---

## Screenshots

`tests/RENDER_w2_cycle.gd` — the same viewpoint at several phases, which is the only
way to judge a change whose entire subject is colour.

```
LP_NUM_THREADS=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  <godot4.7-bin> --path . --rendering-driver opengl3 --audio-driver Dummy \
  --script res://tests/RENDER_w2_cycle.gd -- --out=/tmp/w2_cycle --no-prewarm
```

It settles the world **once per viewpoint** and then sweeps the clock inside that
settle. `manual_time_of_day` moves no vertex and builds no chunk, so a settle per
picture would be twenty-four settles for a strip whose frames must differ in nothing
but the light — and a chunk arriving between two grabs would show up as a difference
the cycle did not cause.

Four viewpoints, all found against the field: `ridge` (lit terrain, unlit
vegetation, the ring and the dome in one frame), `horizon` (level off the shore,
where the sea, the band's foot and the sky's bottom edge meet along one line and a
broken haze contract would show), `zenith` (straight up at the blackout and the
vortex — the part of the dome no other harness in this repo has ever photographed),
and `crash` (the fire, which must *not* follow the cycle).

**Every harness that touches W2 now freezes the clock.** `advance_with_time` ships
on; a settle is minutes of software GL; frame time depends on how loaded the machine
is. Left running, the phase at each shutter is a number nobody chose and no two runs
agree on it. `RENDER_w2_ground.gd` and `RENDER_w2_shadows.gd` both take a `--tod=`
flag and default to 0.45, the scene's parked daytime phase, so they still produce
the pictures they always did.

---

## The build pieces had to join the model too

`shaders/SHADER_concrete_proc.gdshader` began as an ordinary lit spatial shader, which
is the right thing to be in `SCENE_test_zone_A`, and the wrong thing here for the
reason `SHADER_wreck_hull_w2.gdshader` already records at length: **there is no light in
this scene**, so a lit material samples an empty loop and comes back with the
Environment's flat ambient — one colour on every face, no direction, and no
response to the crossing at all.

The wreck was a prop. A shelter is worse, because the player puts it in the middle
of the frame *on purpose* and then stands inside it while the world goes over to
blood. Left lit, the walls would have been the one grey object in a red scene, and
they would have failed at exactly the moment the scene is about.

So every material a placed piece can wear is now `unshaded` and resolves its light
through `SHADERINC_island_light.gdshaderinc` off the `tod_*` bus, with the prop constants for
the void fog and the haze:

| | |
| --- | --- |
| cubes, wedges, plate, slab | `MAT_concrete_proc.tres` |
| foundation | `MAT_foundation_proc.tres` — same shader, darker grey |
| door | `MAT_build_door.tres` → `SHADER_build_door.gdshader` |
| window | `MAT_build_window.tres` → `SHADER_build_glass.gdshader` |

**And unshaded in every scene, not only this one.** The bus is not a W2 invention:
`SCRIPT_sky_cycle_controller.gd` publishes `tod_sun_dir` and `tod_sun_color` *from* the
scene's DirectionalLight wherever there is one, so in A and A2 the pieces track the
real sun through the bus rather than in spite of it. One model for a piece the
player can place anywhere beats two materials and a rule for choosing between them,
and nothing authored changes either way — build pieces only exist at runtime.

### The window could not just come along

It was a `StandardMaterial3D` at metallic 0.9 / roughness 0.05, which got its whole
look from reflecting the environment. W2 has no light *and* its sky is a
ShaderMaterial panorama rather than anything the reflection path samples, so a pane
here resolved to a flat dark rectangle — a hole cut in the wall with the fog colour
behind it. `SHADER_build_glass.gdshader` fakes the one term that mattered as a fresnel
tinted by `tod_sky_color`, so the glass reflects the sky the scene actually has and
goes red with it. It stays see-through, which is the property to protect: a window
is the piece that stops a body without stopping sight, and that distinction is what
the shelter work turns on.

### The ambient is inherited from the ground, not authored

`island_ambient` takes its sky-vs-bounce split from a baked ball, or from the
analytic hemisphere `mix(ground, sky, n.y)` when none is bound. The hemisphere is
right in any scene whose sky outshines its bounce — **and wrong here, at night,
where that inverts.** The measured pair reads 0.996 up against 0.800 down, while
the hemisphere, driven by a `tod_ground_color` brighter than `tod_sky_color` (see
"Why the night's bounce is brighter than its sky"), says the opposite. A wall on
the fallback is lit upside down relative to the ground it stands on, and only
during the flip.

A ball is a measurement of one sky and a build piece can be placed in any scene, so
the .tres files name none. `BuildController._inherit_island_ambient` copies
`env_ball` / `env_ball_night` / `env_ball_enabled` off whatever the scene's terrain
is using, at `_ready`. A shelter therefore shares the measurement of the ground it
was built on, follows a re-bake for free, and needs no per-scene wiring. It writes
the **disabled** case too: these are shared resources that outlive a scene change,
and without that, W2's sky would follow the player into the next scene.

### What it looks like, measured

`tests/RENDER_build_in_w2.gd` builds a hut out of real registry pieces on the real
streamed terrain and shoots it at both ends of the crossing with ground in frame —
the ground being the control. Red share (`r / (r+g+b)`, which unlike an R:G ratio
does not explode when the green channel bottoms out at 0.000, as it does across
whole regions of the settled nightmare):

| viewpoint | hut | bare ground |
| --- | --- | --- |
| close | +0.509 | +0.664 |
| wide | +0.696 | +0.652 |

`tests/TEST_build_lighting.gd` is the cheap half that runs every time: every piece
material is a ShaderMaterial, is `unshaded`, includes the island model, joins the
haze bus, and inherits — and releases — the terrain's ball.

### Two traps this cost, both worth knowing

**A `--script` harness that names `BuildController` at compile time gets a broken
one.** There is no main scene under `--script`, so the autoload singletons are not
registered as globals when the harness compiles, and `SCRIPT_build_controller.gd` names
one (`MiddleClickEmu`). It becomes a dependency that fails to compile, and the
broken copy is what the class name resolves to for the rest of the run: constants
still read, because the parser reached them, and every method is missing. Worse,
`set_script` on it returns a node whose `_ready` never runs — which reads exactly
like "the feature is broken" rather than "the script is". A runtime `load()` from a
file that never mentions the class gets a good one.

**A node added during `_initialize` is not in the tree yet.** It gets no `_ready`
until the first frame, and `get_tree()` inside it returns null until then. The
harness reported "env ball: none" for two rounds because it asked before `_ready`
had run — the inheritance had been working the whole time.

## The shadows came up, and the ship got twice as big

Four changes that turned out to be one change: everything in this scene resolves
its own light off the `tod_*` bus, so "lighter shadows" and "the wreck reads wrong"
are the same conversation held about two surfaces.

### The ambient floor

The env ball's `B` channel is the WHOLE of the ambient here, where in a renderer
with a light loop it would be the FIRST TERM of it. There is no bounce in an
`unshaded` scene: nothing leaks off the crater floor into the underside of the
hull, nothing comes back off the far wall. So the bake was right that a
downward-facing surface collects 0.294 of what an upward-facing one does, and it
was still too dark to look at.

`SCRIPT_bake_env_ball.gd --shadow-lift` remaps `B' = lift + (1 - lift) * B` after the peak
normalisation. Shipped at 0.35:

| normal | day before | day after | night before | night after |
|---|---|---|---|---|
| up | 0.996 | 0.996 | 0.996 | 0.996 |
| horizon | 0.573 | 0.722 | 0.839 | 0.894 |
| down | 0.294 | **0.541** | 0.800 | 0.882 |

The peak cannot move — that is what applying it after normalisation buys — so a
lift can never blow anything out, and the ordering the bake measured survives
intact. What it costs is the spread, 3.4:1 down to 1.8:1, and that spread was the
whole argument for a ball over a `mix`. So `TEST_env_ball.gd` now separates the two
claims: the spread assertions **un-lift first** and read the measurement, and a new
assertion covers the shipped floor, which nothing else would have noticed going
missing.

**Raised to 0.6** when every face the fixed sun misses was still drawing near
black, with the preset's `day_ambient_energy` doubled (0.30 to 0.60) at the same
time — the floor alone cannot do much by day, because the peak's own level is
`tod_sky_color`:

| normal | day at 0.35 | day at 0.6 | night at 0.35 | night at 0.6 |
|---|---|---|---|---|
| up | 0.996 | 0.996 | 0.996 | 0.996 |
| horizon | 0.722 | 0.827 | 0.894 | 0.933 |
| down | 0.541 | 0.718 | 0.882 | 0.929 |

The shipped spread is now 1.4:1 by day. The night-against-day assertion moved onto
the measurement with the lift undone, as the spread ones already were; the floor
assertion keeps the shipped day floor under 0.8 of the peak. See
`docs/DOC_ruin_materials.md`, *The island's shadows*, for what it looks like.

### The wreck doubled, and the crater had to go with it

`crash_site_wreck.wreck_scale` is 2. The prefab is 276 hand-placed nodes and one
uniform scale on the root is the only way to resize a pose without re-authoring it.

The crater's four LENGTHS moved with it — radius 31 → 62, depth 6.75 → 13.5, rim
2.1 → 4.2, wobble 2.75 → 5.5 on a 15.5 → 31.0 feature. Everything else in that
group is a FRACTION and followed for free, which is why the shape is unchanged:
the wall angle is `1.5 * depth / (radius * (1 - floor_frac))`, a ratio of two
lengths, so scaling both leaves every measurement taken against it — the scour
bands above all — still valid without re-measuring.

Three things did not follow and had to be found:

* **The crown fires outgrew their pool.** Sites are placed off the crater weight
  over a ring, so four times the collar area gave 371 fires against ~150, and 19
  crowns against a `max_live` of 12. Every crown must be a hero or it gutters on
  the shared emitter, so the pool went to 24. Draw calls 32 → 56, for 2.5x the
  fire — the field tier doing exactly what it exists for.
* **The pall sank.** It is born `pall_height` above the crater FLOOR, and the floor
  dropped 6.75 m, so the sheet went from 13.25 m over the surrounding plain to
  6.5 — under the burning collar it is supposed to be the smoke of. 20 → 26.75.
* **One steep sample went bald.** The bigger rim landed on steeper ground 72 m out,
  and `splat_weights` lerps `soil` to 1 outside `crater_scour_floor` whatever the
  slope, because the lip must not scour. Charred ash on a steep lip is correct and
  the test's blanket "no turf past the vegetation ceiling" rule was always
  incomplete; the crash site is now exempt, by burn weight rather than by radius.

### The hull had never had any plating at all

The user asked for the normal map to be visible on all surfaces. It was visible on
none, for **two independent reasons**, and both rendered perfectly well.

**The height ramp was clipped.** The `Gradient` feeding the hull's `NoiseTexture2D`
carried `offsets = [0, 0.332]` and no `colors` line, which keeps the default black
and white stops and so puts white at 0.332. Measured over the exact noise, **82.8%
of the texture saturates** — a constant height field, and a constant height field
has a flat normal by construction.

**The triplanar weights underflowed.** `pow(abs(obj_n), 150.0)` is zero to float
precision for anything not nearly axis-aligned: 0.707^150 is 1e-23, 0.577^150 is
1e-36. All three components hit zero, the `max(sum, 1e-5)` guard turned the
normalise into `0 / 1e-5`, and the perturbation came out **exactly zero** on every
plate that was not square to the model axes — which on a hand-posed wreck is nearly
all of them. Dividing by the largest component before the pow fixes it and keeps
the authored intent: at 150 it is still very nearly a hard per-axis pick.

The evidence that both were dead: raising `normal_strength` from 1.3 to **8.0**
moved the rendered hull's spread by 0.009. There was nothing to amplify.

A third thing was needed to make it read once the first two were fixed. `sun_bands`
is 4, so the sun term takes four values and a bump that moves `dot(n, sun)` within
a band changes nothing at all; and the ambient, having just been floored, spans
1.8:1 across the whole sphere. Every face turned away from the sun had no term left
that responded to the normal. `detail_relief` adds the missing one — the
*difference* the perturbation makes to the sun's lambert, unposterised, as a
proportional multiplier. It is zero on genuinely flat surfaces, so it adds detail
without shifting the hull's value or palette, and being proportional it reads the
same in shadow as in light.

### Uniform roughness is not damage

The first fix opened the ramp to the full 0..1 range, which perturbs every texel by
a little. That is a uniformly rough surface — crumpled foil, or cast concrete — and
it is not what a beaten hull looks like. Damage is INTERMITTENT: most of a plate is
untouched, and the parts that are not are gouges with steep walls and a level floor.

The ramp is now a narrow band high in the distribution, `0.60 .. 0.72`, which splits
the hull three ways:

| region | share | reads as |
|---|---|---|
| noise ≤ 0.60 | 70.7% | flat — undamaged plate, no perturbation at all |
| 0.60 – 0.72 | 19.7% | the sloped flank of a dent; ALL the relief lives here |
| noise ≥ 0.72 | 9.6% | the level floor of a gouge, clipped flat |

Clipping BOTH ends is what makes it read. The flat top does as much work as the flat
base: an unclipped peak is a spike, and a spike reads as noise however tall it is.

This is not the bug the file used to have, though both involve clipping — the
difference is which end and how much. The bug ramped over `0.00 .. 0.332`, the dark
TAIL where the noise has almost no mass, and saturated the other 82.8% to a single
level. Now 9.6% is clipped, the relief band sits where the noise actually has mass,
and the large flat region is at the BASE, where it means "this part of the plate is
fine".

`bump_strength` came down 5.0 → 1.5 in the same move, and it is the same change
rather than a second one: the height now climbs its full range inside a 0.12-wide
slice of the noise where it used to take the whole 1.0, so the gradient is about
eight times steeper for the same strength. Left at 5.0 the dent walls saturate to
near-tangent and the chunks come back as hard white rims with no form in them.

The test asserts the three-way SPLIT rather than the offsets, since "not much is
clipped" would now be arguing against the intent — what still has to hold is that
the relief band carries a real share (>8%) and the clipped top stays a minority
(<40%), which is precisely what the original bug violated at 82.8%.

### And the damage is darker, off the same noise

Reused rather than re-authored: the prefab now holds two `NoiseTexture2D`s sharing
ONE `FastNoiseLite` and ONE `Gradient`, differing only in `as_normal_map`. The
second is the height, and `tests/TEST_wreck_hull.gd` asserts the sharing — copy
either subresource instead of sharing it and the darkening drifts off the dents on
the next re-tune, silently, because slightly-misregistered damage still just looks
like damage.

The height is needed because **a normal map cannot say where a gouge is**. The ramp
clips flat at both ends, so the derived normal is `(0, 0, 1)` on the undamaged plate
AND `(0, 0, 1)` again on the floor of the damage — only the sloped walls between
carry any tilt. Keying the darkening off `npert` draws a dark RIM around each dent
and leaves the dent itself the colour of clean hull, which is the one thing it must
not be. The height reads 0 on the plate and 1 in the damage: exactly the mask.

It multiplies the ALBEDO, before the light, at `gouge_darken` 0.28. Before the light
because a gouge is darker for having less paint and more soot in it, which is a
property of the surface — applied after `island_light` it would darken the light
instead, and the damage would fade out wherever the hull is already dim, which is
most of a wreck lying in a hole. Multiplicative rather than a mix toward a colour so
it composes with `char` instead of fighting it.

0.45 was the first value and it was too much — the patches stopped reading as scorch
and started reading as camouflage.

### And then it was too bright

With the plating working the ship was still a white cutout: 4.5x the value of
everything around it, measured over an exact pixel mask. That is the papercraft
complaint in `SHADER_wreck_hull_w2.gdshader`'s header arriving a second time by a
different route — the first time it had no shading model, this time it had one and
was too bright for the frame. `char` was the dial all along, shipped at 0 because
grading the ship was an art decision and the file that added the lighting model
declined to make it silently. It is 0.5 now: 2.5:1, neutral grey against warm
brown, hue carrying the separation that value was over-carrying.

### The measuring rig

`tests/RENDER_wreck_hull.gd` loads the prefab and a swatch of crater char and
nothing else — the ground harness takes ten minutes and streams an island, which is
the wrong tool for turning a dial. Two things it got wrong first, both instructive:

**`await` inside `SceneTree._process` breaks the main loop.** The bool return is
what quits the tree; an `await` turns the function into a coroutine returning a
signal object, which reads as truthy. The rig printed its parameters and exited
without taking a shot. Frames are counted instead.

**A luma threshold cannot separate hull from ground while the hull is being
graded.** It worked only while the ship was white — the bug being fixed. At
`char` 0.7 the darkened plating fell below the threshold, counted as ground, and
the reported ratio went back UP while the ship was plainly still darkening. Each
shot is now taken twice, with the hull hidden and shown, and the difference IS the
mask.

## The plating pointed the wrong way

Reported by eye, not by measurement: *"the normal maps look inconsistently
inverted, which I don't think is a texture issue as much as it is an issue with our
baked lighting."* Half right, and the interesting half is which half.

Nothing was wrong with the texture, and nothing was wrong with the bake. Two
separate faults compounded, and between them they sat exactly in the seam.

### Godot's normal maps are Y-flipped and the shader was not undoing it

The documented convention is X+, **Y−**, Z+. The `NORMAL_MAP` builtin knows that and
undoes it on the way in. A triplanar sample never goes through `NORMAL_MAP` — it
reads the texture by hand, three times, on three uv sets — so the decode becomes the
shader's job, and it was not being done.

Measured against the shipped texture by differencing `gouge_map`, which is the same
noise through the same ramp kept as height and therefore *is* the height field the
normal was derived from:

| | agrees with the slope a normal offset wants |
|---|---|
| red | 84% |
| green | 8% |

Opposite signs against the same central difference in the same frame. Taken as a
direction rather than per channel, the slope the fragment was reading sat **100.6°
away from the true one on average** — worse than the 90° of no information at all,
because a mirror is not noise, it is a wrong answer. Negating green brings it to
32.5°, and that residue is the crude difference kernel and 8-bit quantisation.

**Why it read as *inconsistently* inverted rather than as inverted.** A mirror about
the texture's v axis is a mirror about a *different world axis on each projection* —
world Y on the X- and Z-dominant plates, world Z on the Y-dominant ones. So
neighbouring plates on a hand-posed wreck disagreed with each other about which way
the damage was dented, and a single gouge running across a corner changed its mind
halfway. The 74.6% of the map that is flat by design (the intermittent-chunks ramp)
made it worse, not better: with the relief in isolated patches there is no
continuous surface to average the error out against, so each patch reads
individually as a bump or a dent.

### The map is a depth field and was being read as a height field

**This one was reported against the fix, not against the bug** — "the before looks
right, the after does not" — and that reaction was correct.

`Image.bump_map_to_normal_map`, which is what `as_normal_map` calls, reads **bright
as high**. The ramp runs black to white across 0.60..0.72 of the noise, so the
damage — the intermittent chunks the ramp was re-shaped to carve out, and precisely
the texels `gouge_map` darkens — is the **white** end. Decoded faithfully that is a
field of *raised blisters with soot on them*. The exact opposite of the "intermittent
chunks of **depth**" the ramp was authored for.

**The two faults hid each other, and that is the whole story.** A relief mirrored
per-projection is neither a hill nor a hole; it is a scramble, and a scramble does
not read as either. Fixing green alone turned the scramble into *consistent
blisters* — a strictly better decode that looked strictly worse, because for the
first time the polarity error was legible.

The fix is one more negation, turning `(-dH/du, -dH/dv)`, the slope of a hill, into
`(+dH/du, +dH/dv)`, the slope of a hole. Not by inverting the ramp: `gouge_map`
shares that `Gradient` subresource, and sharing it is the only thing keeping the
darkening registered with the dents, so inverting it would move the soot onto the
clean plate.

### How it was actually settled: a reference with no convention in it

Variant-against-variant comparison could not answer this, and the first attempt at
it produced a confidently wrong result. A sphere in the hull material lit from
**straight overhead** showed the shipped shader and the depth-negated one as
near-identical (per-tile correlation +0.87, sd 0.08) — which looked like proof that
the green flip was wrong. It was an artefact of the test: with the sun on +Y, the
only thing the lighting can see is the world-Y component of the perturbation, and
that component comes almost entirely from the green channel via the X and Z
projections. *Negate green* and *negate everything* are the same operation under an
overhead sun.

What settled it was a **reference variant with no normal-map decode at all**: the
same height field, differentiated in screen space into a Mikkelsen surface gradient,
the way `SHADER_greeble_surface.gdshader` does. It has no convention to get wrong, so it is
ground truth. Two of them were built — one where bright is raised, one where bright
is sunk — and each candidate scored against both, per tile across the sphere, under
a sun with all three axes exercised:

| | vs "bright is raised" | vs "bright is sunk" |
|---|---|---|
| shipped before | +0.10, **47% of tiles wrong sign** | +0.17, 22% wrong |
| green fixed only | **+0.45, 0% wrong** | −0.18, 78% wrong |
| green + depth | −0.17, 81% wrong | **+0.45, 0% wrong** |

Both fixed variants are *internally consistent* and the old one is not — 47% wrong
sign is a coin flip, which is what "inconsistently inverted" means as a number. The
green negation is therefore right and stays. Which of the two consistent answers is
wanted is a separate, purely authoring question, and "chunks of depth" answers it.

### The relief was keyed to a sun that was not on the face

This is the half that really is about the lighting, and it is the user's hypothesis.

`detail_relief` exists because a four-band posterised sun cannot describe a bump and
a floored ambient spanning 1.84:1 barely can either. It carried the plating by
differencing `dot(n, tod_sun_dir)` — and it did that *everywhere*, on the stated
grounds of wanting "detail on ALL surfaces, not just the ones the sun is
describing". Right about the goal, wrong about the method: on a plate past the
terminator there is no sun on it. `island_light`'s own sun term has already wrapped
to zero and every photon that plate gets came off the ball. So the macro shading
said "lit from the sky" while the micro relief went on saying "lit from over there",
and wherever those disagreed by more than a right angle the plating read backwards
against the very surface it sat on.

The key direction now blends to the ambient's dominant direction as the sun runs
out, using the same wrapped term `island_light` uses so the crossover lands exactly
where the sun term does. Up is not a guess — the day ball measures 1.00 at up, 0.573
at the horizon, 0.294 at down, monotonic in `n.y`. In the nightmare the ball
flattens to 1.4:1 and up is still its peak with much less authority, which is what a
nearly isotropic dome should produce. A plate in full sun keys to the sun exactly as
before, so the lit half of the hull did not move.

### What the numbers did and did not show

Rendered spread barely moved across all three variants — 56.2% → 61.2% → 61.4% of
mean on the close shot, and *down* on the wide one. That is the correct result and
worth writing down: a sign error does not change how much variation there is, only
where it points. **Every magnitude metric this project had was calling the hull
fixed the whole time**, through both bugs, and would have gone on doing so.

So the guard in `tests/TEST_wreck_hull.gd` is a sign chain, end to end and scored as
one number: decode, negate green, negate the perturbation, then require the finished
slope to agree with `+dH` — the slope of a hole — on both axes (88%/88%). One number
rather than two greps on purpose, because the two negations are only correct
together and a check that scored them separately would have passed the shader in the
state that looked *worst*. The convention itself is measured live through
`Image.bump_map_to_normal_map`, the same call `NoiseTexture2D` makes internally, so a
future Godot that changes it reports the new convention rather than silently guarding
a compensation that has become the bug.

### Still outstanding

`PREFAB_rabbit_v3_original_shot_down.tscn` — the A2 authoring wreck — carries the
identical clipped gradient, so the same flat-normal bug is live in
SCENE_test_zone_A2. Left alone deliberately: that scene was not in scope and the
fix would change a second scene's look without anyone having looked at it.

**The same decode is in five other shaders and its status there is unknown.**
`cliff_rock`, `cliff_wall`, `terrain_splat`, `terrain_splat_w2` and
`triplanar_layered` all carry a byte-identical `texture(...).xyz * 2.0 - 1.0`
triplanar block — the wreck's was plainly copied from `terrain_splat_w2` — and none
of them negates green either. (`greeble_surface` is fine: it rebuilds a Mikkelsen
surface gradient from `dFdx` of a procedural height and never samples a normal map
at all.)

What made the wreck *provable* was that its normal had a companion height in the
same file: `gouge_map` is the same noise through the same ramp, so the ground truth
was sitting right there. The rock shaders bind an authored PNG,
`TEX_dark_rock_02_normal_128.png`, with no height companion. Correlating it against its
paired albedo — on the usual bet that a scanned rock has cavity darkening baked in,
which would make albedo a proxy for height — returns **51% and 52%**, chance in
*both* channels. So the albedo carries no usable cavity signal and that route is a
dead end; the convention of those PNGs cannot be settled from the assets in the
repo.

The likely story, and it is a hypothesis rather than a finding: `NoiseTexture2D`
produces Y− because *Godot* generates it, whereas a PNG exported from Substance or
Blender is Y+ by default. That would make the wreck the genuine odd one out and
would mean applying the same negation to the terrain **introduces** the bug rather
than fixing it. Which is exactly why it was not applied there. Settling it needs
either the textures' provenance or a deliberate A/B render of a lit slope, and
neither was in scope for a wreck fix.
