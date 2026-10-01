# Horizon parallax clouds

A two-layer cloud band painted around the horizon, in front of the sky and behind
everything else, fading out toward the bottom. Tiles horizontally and only
horizontally; the back layer is bigger and slower, the front layer smaller and
faster.

| | |
| --- | --- |
| shader | `shaders/SHADER_horizon_clouds.gdshader` |
| material | `materials/MAT_horizon_clouds.tres` |
| node | `scripts/world/SCRIPT_horizon_clouds.gd` |
| artwork | `textures/TEX_clouds_parallax_band.png` (512 x 256) |
| artwork tool | `tools/TOOL_fix_cloud_band_alpha.py` |
| test | `tests/TEST_horizon_clouds.gd` |
| wired into | `scenes/utility/SCENE_test_zone_W2.tscn`, `scenes/utility/SCENE_test_zone_Q2.tscn` |

To add it to another scene: drop a `Node3D`, put `SCRIPT_horizon_clouds.gd` on it, set
`material`. That is the whole installation — the node finds the camera itself and
sizes its own geometry off the camera's far plane.

## Which of the two backgrounds

`textures/` ships two parallax cloud backgrounds. This uses the **512 x 256**
one — the less elongated of the pair. The 4:1 `TEX_clouds_parallax_background_2.png`
drops in unchanged, but the band's aspect is set by `*_height` against `*_tiles`
and swapping to a 4:1 image means halving every `*_height` or the clouds come out
at twice their drawn height.

Both images are the same shape: transparent sky above, a cumulus bank filling the
frame below, opaque along the bottom edge.

**Neither ships in a state a GPU can filter, and the band does not use either
directly.** It samples `TEX_clouds_parallax_band.png`, derived from the 512 x 256 by
`tools/TOOL_fix_cloud_band_alpha.py`. Two defects, both of which only appear once the
sampler interpolates:

* **One-bit alpha.** The source is palettized with a single transparent index, so
  its alpha takes exactly two values. Measured on the imported `.ctex` the GPU
  actually receives, mip 0 has two distinct alpha levels — no antialiasing
  anywhere in a silhouette, and at the shipped tile counts the band is magnified,
  so each stair-step is several screen pixels.
* **Teal under the transparency.** The transparent palette entry is `(0, 92, 94)`,
  and 82% of the transparent region still holds it in the imported texture.
  `process/fix_alpha_border` bleeds opaque colour exactly **four texels** in from
  the silhouette and stops — 4067 texels rewritten, no alpha bytes touched. That
  is enough that nothing bilinear can reach *at mip 0* is teal, which is why this
  document used to say the problem was covered. It is not covered, because **the
  band does not stay at mip 0** (see *The vertical clamp* below), and everything
  five texels or deeper is teal at every level.

The derived file inpaints the whole transparent region with the nearest opaque
colour — not just a border — so there is no key colour anywhere for any sampler at
any LOD to find, and reconstructs a soft edge by blurring the mask by 0.6 of a
texel. The opaque region is byte-identical to the original.

Be honest about which half does the work: **the inpaint matters, the soft edge
mostly does not.** The project renders at `scaling_3d/scale = 2.0` and then snaps
through a 16-level LUT, and measured at the final 720p output the edge hardness is
the same for the original, the derived file and the `_2` sibling alike — the
supersample and the quantiser erase the difference. Judge cloud-band artwork on
silhouette and coverage, not on edge softness.

Rerun the script if the source art is ever replaced; `tests/TEST_horizon_clouds.gd`
asserts the result has real alpha and no surviving key colour.

## The vertical clamp, and the veil that made the band look like two banks

`repeat_enable` is **both axes** — it has to be, for `u` — so the `clamp` on `v` is
the only thing stopping the artwork tiling vertically. The inset is half a texel:

    v_inset = 0.5 / textureSize(cloud_band, 0).y

`textureSize(..., 0)` is **mip 0**. At LOD `L` the clamped coordinate lands
`0.5/2^L` of a texel from the edge, so bilinear takes texel `-1` with weight
`0.5 - 0.5/2^L`: 0.000 at LOD 0, but **0.250 at LOD 1**. Texel `-1` wraps to the
artwork's last row, which is 100% opaque at every mip, and whose colour at mip 1 is
the teal key.

And the band is not reliably at mip 0. Measured at screen centre, where the tangent
projection is densest:

| 3D buffer | front layer | back layer |
| --- | --- | --- |
| 2560 x 1440 (`scaling_3d 2.0`) | LOD 0.52 | LOD 0.00 |
| 1280 x 720 | **LOD 1.11** | LOD 0.31 |

`RenderQuality` lowers the render scale on weak hardware, so LOD 1 is a shipped
configuration, not a corner case. The result was a flat veil of alpha ≈ 0.26 —
**identical at every azimuth**, because it comes from one texel row — painted over
the entire 47% of the band above the front layer's top, in teal, and cut off at its
foot by a hard horizontal line. That line measured **8.86/255**, the largest step
anywhere in the frame, and it is what made one cloud bank read as two stacked ones.

What fixes it is the alpha window below, which is evaluated on the **unclamped**
`v` and is therefore exactly zero wherever the clamp binds. Removing the veil
brightened that zone from 0.482 to 0.559 and dropped its chroma from 0.021 to
0.015. The inset stays — it is still correct at mip 0 and costs nothing.

This is why `art_solid_end <= 1.0` is load-bearing rather than cosmetic: push it
past 1 and there is a live region where the window is open and the clamp binds at
once. The test asserts it.

They tile horizontally already. Measured across the wrap, the left and right
columns differ by about as much as any two adjacent interior columns — there is no
seam to hide, which is why the shader can simply set `repeat_enable` and be done.

## Where it draws

Ordinary transparent geometry: a camera-centred open cylinder at 9 km with
`render_priority = -2`.

Not a sky shader, because Godot allows one sky material per Environment (so it
would have to be forked into every sky it is wanted over) and because the sky pass
runs before transparents with no depth — a mountain on the skyline would lose to a
cloud that is supposed to be behind it. Not a screen-space overlay, for the same
occlusion reason.

As geometry it composites over whatever sky is behind it, is hidden by anything
nearer than the shell, and costs one draw call.

## Where the parallax comes from

**Not from turning your head.** Rotating a camera in place moves everything by the
same angle regardless of distance — rotation gives zero parallax, and two layers
differing only in scale would slide together and read as one flat wallpaper. This
is the thing most "parallax sky" attempts get wrong.

Parallax is a translation effect. An object at horizontal distance `R`, when the
camera moves by `d`, shifts in apparent azimuth by `-(d . t̂) / R`, with `t̂` the
horizontal unit vector across the line of sight. Inverted for a fragment shader —
given the azimuth `phi` a pixel looks along, which part of the pattern is there? —
that is

    theta = phi + (C . t̂) / R

with `C` the camera's logical horizontal position. Small `R` means a large shift
per metre travelled, so the front layer moves faster. It is one dot product, and
it is the entire mechanism. `*_distance` is the only knob that creates depth
between the layers; `*_tiles` changes how big the clouds are, not how fast they
move.

At the shipped distances, 2400 m of travel slides the back layer 8.6° of azimuth
and the front layer 30.6° — before the ceiling below, which takes those to 8.2°
and 20.9°.

Wind rides on top of that as a constant azimuthal drift, also faster on the front
layer.

## The ceiling on the parallax, and the tear that made it necessary

**The small-angle model has a horizon of its own, and past it the band tears.**
Write the camera's logical offset as `C = E (sin a, cos a)` and the view direction
as `p = (sin φ, cos φ)`; then `C · t̂ = E sin(a − φ)` and

    θ(φ)     = φ + (E / R) sin(a − φ)
    dθ/dφ    = 1 − (E / R) cos(a − φ)

which stops being monotonic the moment `E` passes `R`. At `E = R` the derivative
touches zero along the bearing `a` and the artwork is stretched infinitely wide
there; past it the derivative goes negative over an arc and **the azimuth map
folds back on itself** — the same clouds drawn twice, mirrored, meeting at a seam
that slides as you fly.

Onset is **4.5 km of travel on the front layer and 16 km on the back**: the layer's
own `*_distance`, and nothing else. It is absent at the origin, which is where
every headless render is taken, and permanent everywhere else.
`SCRIPT_floating_origin.gd` does not save it and cannot — the accumulated offset it
hands the shader in `world_offset` *is* that `E`, and it grows without bound by
design. That is the whole point of `world_offset`: without it the band would slew
by radians in the frame the origin snapped.

**No model avoids this.** Ask for both `dθ/dφ = 1` (no warp) and
`dθ/d(C · t̂) = 1/R` (parallax at the layer's distance) and integrating the second
gives `θ = φ + (C · t̂)/R + h(φ)`, whose φ-derivative is forced back to
`1 − (C · p̂)/R`, because `t̂` turns with `φ`. Sustained constant-rate parallax on a
constant-distance azimuthal band is not on offer at any price; the offset driving
it has to saturate somewhere.

`parallax_limit` is where. It soft-limits the offset's magnitude to that fraction
of **each layer's own** `*_distance` — per layer, because the quantity that has to
stay bounded is the ratio `E/R` the derivation is written in:

    |off| = |C| / sqrt(1 + (|C| / (R · parallax_limit))²)

Exact to second order near the origin, smoothly asymptotic to `R · parallax_limit`,
no kink to cross and nothing to pop. `dθ/dφ` is then confined to
`1 ± parallax_limit` and can never reach zero.

**0.5 is a compression budget.** The worst azimuthal stretch anywhere in frame is
`1 / (1 − parallax_limit)` — 2× at the shipped value, 3.3× at 0.7, 5× at 0.8 — and
since the camera spends essentially all its time saturated, the saturated picture
is the one to protect. What it costs is near-origin parallax:

| `E` from logical origin | front `\|off\|` | front min `dθ/dφ` | back `\|off\|` | back min `dθ/dφ` |
| --- | --- | --- | --- | --- |
| 0 | 0 | 1.000 | 0 | 1.000 |
| 1 km | 914 m | 0.797 | 992 m | 0.938 |
| 2.4 km | 1641 m | 0.635 | 2299 m | 0.856 |
| 4.5 km (front `R`) | 2012 m | 0.553 | 3922 m | 0.755 |
| 16 km (back `R`) | 2228 m | 0.505 | 7155 m | 0.553 |
| 100 km | 2249 m | 0.500 | 7975 m | 0.502 |

`dθ/dφ` is normalised to 1 at the origin, and its minimum over the compass is what
matters — that is the stretch along the bearing `a`. Unlimited, the same column
reads 0.000 at `E = R` and **−21.2** for the front layer at 100 km: negative is the
fold, and the magnitude is how many times over the band is drawn.

Far out both layers are pinned, and the band's motion is the wind drift plus a
slow swing as the bearing from the logical origin turns. `tests/TEST_horizon_clouds.gd`
reproduces the map and asserts it runs one way out to 10,000 km;
`_get_configuration_warnings()` catches a `parallax_limit` at or over 1.

One incidental benefit: the parallax term is now bounded, so `u` is bounded, and
the offset feeding it is uniform across the draw — which means `d(cross_c)` has the
same closed form the cross product does and no longer needs a `dFdx` of a quantity
that grew with the distance from the origin.

**No altitude parallax, on purpose.** Real cloud 4 km out would drop 7° if you
climbed 500 m, and the band would leave the horizon. Climbing is not wired to the
vertical coordinate at all, so elevation zero is elevation zero at any altitude.

## The two coordinates

The band is sampled from the **view direction**, never from the mesh. Move the
cylinder, resize it, swap it for a sphere: the picture does not change. That is
what makes "always at the horizon" exact rather than approximate, and it is why
`SCRIPT_horizon_clouds.gd` owns no part of the look.

* `u` — azimuth. Wraps at 360°, so `repeat_enable` on the X axis *is* the
  horizontal tiling. `*_tiles` is how many copies of the image fit around the
  compass; **fewer tiles means bigger clouds.**
* `v` — `tan(elevation)`, remapped into the band and **clamped, not wrapped**. The
  artwork has a definite top and a definite bottom; repeating it vertically would
  stack cloud banks up the sky.

`tan(elevation)` rather than the angle because it is what a cylinder gives for
free, it is the projection the artwork wants (a band on a cylinder compresses
toward the top exactly as a real cloud bank does), and it costs a divide against
an `atan`.

The artwork is 2:1, so `height = PI / tiles` reproduces it undistorted. Both
shipped layers are within 1% of that:

| | tiles | tile width | `height` | undistorted | band | cloud tops |
| --- | --- | --- | --- | --- | --- | --- |
| back | 7 | 51.4° | 0.45 | 0.449 | -5.1° .. 19.8° | 19.8° |
| front | 12 | 30.0° | 0.26 | 0.262 | -5.7° .. 9.1° | 9.1° |

## The fade toward the bottom, and the invariant under it

`fade_start` / `fade_end` are in `tan(elevation)`: opaque above, gone below. The
band's colour converges on `haze_color` **before** the alpha goes, so its foot is
already indistinguishable from the sky by the time it stops being drawn — the same
ordering `SHADER_cloud_plane.gdshader` uses for its horizon ring, and for the same
reason.

That fade is also load-bearing for a second thing. Because `v` is clamped, below a
layer's `*_base` the sampler would repeat the artwork's solid bottom row down the
sky forever. Two things now stop that: the window below takes alpha to zero well
before `v` reaches 1, and as a backstop **every `*_base` sits below `fade_end`**.
Both `_get_configuration_warnings()` and `tests/TEST_horizon_clouds.gd` assert the
second, because it fails as a picture and not as an error.

`haze_color` is the exact neutral **0.30** — see *One haze value* below.

## The window on the artwork, and the banding it fixes

The artwork is a photograph of a cloud bank, and **only part of its height is
usable**. Row 123 of 256 is the first row that is 100% opaque across the full
width, and every row under it is too: the bottom 52% is a solid wall, because in
the source photograph that part is meant to sit below the horizon.

Drawn unwindowed, each layer therefore painted a flat opaque rectangle of its own
tint with a hard top edge, and two layers painted two of them, one above the
other. That is what "banding" in this band meant. Measured on the version that
shipped:

| | alpha pinned at | for every `tan(elev)` below |
| --- | --- | --- |
| back | 0.800 | 0.144 |
| front | 1.000 | 0.035 |
| composite | > 0.99 | 0.04 |

The band also simply **stopped** at `*_base + *_height`. There was a fade at its
foot and nothing at all at its crown, so the top was a cut — drawn as a curved arc
across the sky, because a constant-elevation locus is a conic under a rectilinear
projection, not a straight line. It measured a 4.85/255 step in a frame whose sky
is otherwise smooth.

So alpha is windowed at both ends, **in the artwork's own `v` rather than in
elevation**: in over `art_fade_in`, out from `art_solid_start` to
`art_solid_end`. Doing it in `v` is what makes it self-tuning — each layer windows
itself wherever it happens to sit in the sky, and moving a `*_base` or `*_height`
cannot leave the window behind. Per-row opaque fraction runs 40% at `v` 0.125,
59% at 0.19, 77% at 0.25 and 97% at 0.375, so the roll-off starts at 0.30: past
about a third of the way down the image is a wall in all but name.

## One haze value

Everything in W2 that is drawn at distance converges on **one exact neutral,
0.30**: the Environment's fog, `MAT_sky_w2_void`'s `bottom_color`, the band's
`haze_color`, the cloud sea's `fog_color`, and the terrain, cliff, grass and tree
fog colours. Anything left behind draws a seam at exactly the horizon, where it is
most visible. `tests/TEST_horizon_clouds.gd` asserts all eight against each other.

**It was 0.089**, and that number came from a scene with nothing under the islands
but void. Once the volumetric cloud sea went in underneath, 0.089 was four times
darker than the thing it was supposed to blend into, and it drew a near-black bar
right across the horizon — measured 0.28 deep against its surroundings, with a
21.8/255 step at its lower edge, about 19 rows tall in a 720p frame.

It was also the worst available value for the current palette. `ps1-soft`'s
neutral ramp is `0.000, 0.031, 0.282, 0.314, 0.345, 0.376, ...` — one enormous gap
and then even 0.031 steps. 0.089 sits in the gap, so a large flat area of it had
to dither between two entries eight steps apart, which is visible as noise rather
than as a tone.

0.30 was chosen by sweeping the value and measuring the horizon discontinuity
directly, with `tests/RENDER_cloud_band.gd`:

| value | horizon trough depth | largest step |
| --- | --- | --- |
| 0.089 | 0.287 | 21.8/255 |
| 0.18 | 0.161 | 15.0/255 |
| 0.24 | 0.064 | 10.1/255 |
| **0.30** | **0.021** | **6.6/255** |
| 0.36 | 0.016 | 8.6/255 |

0.27 through 0.33 are within measurement noise of each other; 6.6/255 is under one
palette step, i.e. the floor. Note that 0.30 is an *input* colour and the sea's
measured *rendered* tone is 0.364 — the difference is the filmic tonemap, which is
why the value has to be found by rendering rather than by reading the sea's
`cloud_color` off its material.

Two independent checks landed on the same number. Reimplementing
`SHADER_cloud_volumetric.gdshader`'s march analytically (exact OpenSimplex2, 1.1M rays,
transmittance-weighted) gives the sea's mean emitted tone as **sRGB 0.3021**, with
p10/p90 of 0.271/0.331 — the same window the sweep found. Screen-area weighted
over the real 780-frame flyover it is 0.3031. The tone is also almost entirely
view-independent: 0.017 sRGB of spread across depression angle, 0.0014 across
camera altitude. One scalar is genuinely correct here.

### And a third reason, which is not about the sea at all

Godot linearises `Environment.fog_light_color` **CPU-side with the exact sRGB
curve**, but linearises a `source_color` shader uniform **in the GLES3 scene
shader with a cheap cubic** (`c*(c*(c*0.305306 + 0.682171) + 0.012523)`). The two
disagree, and they disagree worst in the dark:

| authored value | exact (Environment fog) | cubic (shader `fog_color`) | ratio |
| --- | --- | --- | --- |
| 0.089 | 0.00840 | 0.00673 | **1.248** |
| 0.20 | 0.03310 | 0.03223 | 1.027 |
| **0.30** | 0.07324 | 0.07340 | **0.998** |
| 0.666 | 0.40109 | 0.40111 | 1.000 |

So at 0.089 the Environment's fog and every shader's `fog_color` were painting
linear values **25% apart** while both `.tres` files said the same number — the
"one exact neutral, asserted everywhere" contract was not actually producing one
colour on screen. At 0.30 the gap is 0.2%. The contract only became true when the
value moved.

## Tone

| | tint | |
| --- | --- | --- |
| back | 0.50 / 0.53 / 0.58 | the **lighter** layer, faintly cool |
| front | 0.38 / 0.38 / 0.38 | the **darker** layer |
| `saturation` | 0.28 | applied to the composite, not per layer |

Two things set those numbers, and both are about the band belonging to the scene
rather than sitting on top of it.

**The near layer is darker than the far one.** Atmospheric perspective washes
distance out toward the sky, so a near cloud reads as a darker silhouette against
a paler far one. This started with the front layer at full white, which inverted
the cue — the small near puffs became the brightest thing on screen and the two
layers flattened into a single sheet. The back layer's residual blue is the other
half of the same cue: distance is colder as well as paler, and enough of it
survives `saturation` to register.

**Both are pitched against the cloud sea underneath.**
`MAT_cloud_sea_volumetric` paints its billow tops at 0.34, and the band has to
look like the same weather as the deck it sits on. At full white the front layer
was roughly three times the sea's brightest tone and glared over it.

`saturation` is heavy for the palette's sake: the artwork is blue-and-pink
photographic cumulus, and under a neutral overcast the LUT will happily find
tinted entries for all of it. Applying it to the composite rather than per layer
is what lets the two tints separate the layers before it lands.

## The shell

`cover_up` / `cover_down` size the cylinder in the same `tan(elevation)` units, and
have to clear the tallest band top and `fade_end` respectively or the rim cuts the
picture. `auto_fit` recomputes the radius from the live camera's `far` each frame
(`far_fraction`, default 0.75), which in W2 is 12000 → 9000 m: outside the 3600 m
terrain stream so islands still occlude it, inside the far plane so it is not
clipped away. A shell outside `far` vanishes with no warning and no obvious cause,
which is the whole reason `auto_fit` defaults on.

The node chases the camera in **all three axes**, unlike `SCRIPT_cloud_planes.gd`, which
refuses to follow in Y. There, one fixed altitude is what makes a deck a floor.
Here the band is meant to be at the horizon from any altitude, so the shell has to
stay centred on the eye or its rim swings into view the moment you climb.

## Filtering, and the seam that is not there

`filter_linear_mipmap`, and the import now generates mips. At the shipped tile
counts the band is magnified (12 x 512 texels is ~1800 across a 2560 px
supersampled frame) so the mips are inert; they start earning their keep the moment
anyone raises `*_tiles` or shrinks `*_height`, and this project has a standing
reason to care — `SHADER_post_dither.gdshader` turns ordinary minification shimmer into
crawling confetti.

Mips are also why the fetches are `textureGrad`. `atan` has a branch cut, so `u`
jumps by a full turn along one column of pixels; the hardware derivative there is
enormous, selects the coarsest mip, and paints a permanent blurred vertical stripe
down the sky at world azimuth 180°. The cut is in `phi` alone and `phi`'s
derivative has a closed form, so it is computed analytically and handed to the
sampler. Everything else the fragment needs is continuous and uses `dFdx`
directly.

`detect_3d/compress_to` is off on that texture. It feeds a palette LUT; letting
the editor silently reimport it as block-compressed the first time it appears in
3D would put banding into the one asset in the frame that cannot afford it.

`process/fix_alpha_border` is **off** on the derived artwork, and deliberately:
the derivation already fills the whole transparent region correctly, and the
import pass would only overwrite that with its own shorter-range dilation.

## Is the band fogged?

**No, and it is checked two ways.** The shader declares `fog_disabled`, which the
test asserts against the `render_mode` declaration rather than against the file
text. And empirically: rendering the same frame with the Environment's
`fog_density` at the shipped 0.0012 and at 0.05 — 41 times higher, enough to make
transmittance at the 9 km shell exp(-450) if any of it reached the band — gives
**bit-identical output**, 100.0000% of pixels equal, max channel difference 0.

The band's own convergence on `haze_color` toward the horizon is not fog; it is
the art-directed handoff to the sky described above, and it is the reason the band
can be unfogged without its foot showing a hard edge.

## The hourly hitch

Godot rolls `TIME` over every 3600 s. A wind drift that is not a whole number of
tiles by then snaps the sky sideways once an hour. The shipped drifts are chosen so
`drift * 3600 * tiles / TAU` lands on a whole number (9 for the back layer, 40 for
the front). Retune them alongside `*_tiles`, or accept the hitch; the test prints
the slip either way.
