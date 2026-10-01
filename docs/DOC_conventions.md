# Naming and layout conventions

Every file in this project is named `PREFIX_name.ext`, where the prefix says
**what kind of thing the file is** and the directory says **what subsystem it
belongs to**. The extension is not enough on its own: a `.tscn` is either a
scene you run or a scene you instance, and a `.tres` is a material, a theme, a
noise field or a tuning resource. The prefix answers that at a glance, in the
filesystem, in a `git log --stat`, and in the editor's file picker.

The convention is redundant with the directory in places — `MAT_` files live in
`materials/`, `SCRIPT_` files in `scripts/`. That is deliberate. Files get
quoted in comments, moved between directories, and listed out of context; a
name that only makes sense next to its siblings stops making sense the moment
it is on its own.

## The prefixes

| Prefix | What it marks | Typical extension |
|---|---|---|
| `SCENE_` | A scene you run — a zone, a menu, a screen | `.tscn` |
| `PREFAB_` | A scene you instance into another scene | `.tscn` |
| `SCRIPT_` | A script attached to a node, or a resource script | `.gd` |
| `AUTOLOAD_` | A script registered as an autoload singleton | `.gd` |
| `SHADER_` | A shader | `.gdshader` |
| `SHADERINC_` | A shader include, `#include`d by shaders | `.gdshaderinc` |
| `MAT_` | A material | `.tres` |
| `THEME_` | A UI theme | `.tres` |
| `NOISE_` | A noise resource | `.tres` |
| `ENV_` | An Environment resource, shared by the scenes that draw with it | `.tres` |
| `ISLANDFIELD_`, `TERRAINFIELD_`, `SKYCYCLE_`, `GOLFCONFIG_`, `BAKEROSTER_`, `RUINGAPGROWTH_` | Typed tuning resources with their own script | `.tres` |
| `MODEL_` | A 3D model the engine imports | `.glb` |
| `MESH_` | A baked mesh or collision resource | `.res` |
| `BLEND_` | A Blender source file the engine does not import | `.blend` |
| `SRC_` | Any other source art the engine does not import | `.webp`, `.xcf` |
| `TEX_` | A texture a 3D material samples | `.png`, `.tga` |
| `SPRITE_` | A 2D cutout or frame, drawn as a billboard or particle | `.png` |
| `LUT_` | A baked colour lookup table | `.png` |
| `PALETTE_` | A palette definition | `.hex` |
| `SKY_` | A sky panorama or HDRI | `.png`, `.hdr` |
| `UI_` | UI and HUD art | `.png`, `.svg` |
| `LOGO_`, `BRAND_` | Brand marks, and their exported sizes | `.png`, `.svg` |
| `MUSIC_` | A music track | `.ogg`, `.mp3` |
| `SFX_` | A sound effect | `.ogg` |
| `TEST_` | A headless harness that asserts and exits non-zero on failure | `.gd` |
| `PROBE_` | A harness that measures and reports; it does not assert | `.gd` |
| `RENDER_` | A harness that writes screenshots or frames | `.gd` |
| `PERF_` | A harness that measures frame cost | `.gd` |
| `TOOL_` | Offline tooling — run by hand, never part of a frame | `.py`, `.html`, `.gd` |
| `DOC_` | Documentation | `.md`, `.txt` |
| `DATA_` | Plain data | `.json`, `.csv`, `.cfg` |
| `REF_`, `SHOT_` | Reference imagery — mockups, contact sheets, screenshots | `.png`, `.html` |

A harness's companion scene takes the harness's prefix, not `SCENE_`:
`TEST_touch_pad.gd` sits next to `TEST_touch_pad.tscn`.

## Zones, and the variants of a zone

Test zones are lettered: `SCENE_test_zone_A`, `_B`, `_C`, `_D`, `_M`, `_Q`,
`_W`, `_X`, `_Y`, `_Z`. **A variant of a zone is the letter plus a number** —
`A2`, `B2`, `Q2`, `W2` — and the numbering continues from there (`W3`, `W4`) for
further variants.

It used to be the letter doubled: `AA`, `BB`, `WW`. That is gone, because a
doubled letter is not readable as "a variant of" — it reads as a different
letter — and it does not extend: there is no third form after `WW` that anyone
would guess. It also collides. `AA` is the WCAG contrast rating, which
`DOC_title_screen_and_menu.md` uses in its own sense, and `AABB` is a Godot
type; a project-wide rename has to pick those apart by hand, which is a cost
paid once here and not worth paying twice.

**The zone tag travels into every file that belongs to that zone**, lowercased:
`MAT_terrain_splat_w2.tres`, `SHADER_prop_layered_w2.gdshader`,
`TEST_w2_cycle.gd`, `DOC_w2_blood_night.md`. Renaming a zone therefore means
renaming its whole family and rewriting every reference — paths, identifiers,
and the prose in the comments, which in this project is most of the text. It is
worth doing right, and it is worth not doing twice.

**Three scenes have left the lettered scheme.** `_D` is `SCENE_title` and `_W3`
is `SCENE_island_0`, because neither is a test any more: one is the screen the
game opens on and the other is the game. A scene that ships gets named for what
it is. `_R` is `SCENE_test_ruin_0`, the ruin dungeon (`DOC_ruin_dungeon.md`). It
IS still a test, and its name says so, but the title screen's picker offers it,
which is the line the other two crossed. It had no family to drag: its scripts
are named for the dungeon, not for the zone. `SCENE_test_ruin_1`, the
underground ruins (`DOC_ruin_underground.md`), was born under that name and
never had a letter; its scripts are named for the underground.

The first two renames deliberately did NOT drag their families with them, against
the rule above. `MAT_veg_billboard_w3.tres`, `MAT_veg_understory_w3.tres` and
`SCRIPT_title_screen_D.gd` still carry the old tags. The rule says the tag
travels, and it still does — that sweep is simply owed, and is listed here so it
reads as a debt rather than as a counter-example. The scene headers say the same
thing where a reader will meet it.

**`scenes/` holds only what the game routes to; `scenes/utility/` holds the
rest; `scenes/test/` holds the UI test benches.** Four files are at the top:
`SCENE_title` (`run/main_scene`), `SCENE_island_0`, `SCENE_test_ruin_0` and
`SCENE_test_ruin_1` — the last three are what the title screen's picker offers. Under `utility/` are the
surfaces you ARRIVE in rather than start at — the pause overlay, the battle, the
debug menu, the FX gallery — and the lettered zones the island was built from.
Under `test/` is a scene per UI archetype, shown over a stand-in for gameplay
so it can be looked at and shot on its own: the lower-left command menu
(`DOC_command_menu.md`) is the first. A bench is not a retirement home — that
menu is also the battle's command column and both its submenus. The bench stays
because what it is for is looking at the archetype on its own, over a backdrop
chosen to be awkward, without a fight running underneath it.

The lettered zones were FILED rather than deleted, and the distinction is the
point. A scene is the only mount for the scripts it instances, so deleting one
can orphan a live subsystem without touching a line of it and without the
toolchain saying anything: `_Q2` is the sole scene standing up the terrain
world, its mesher, its two scatters and the runway. Filing a scene costs a path
rewrite and is reversible. Deleting one is neither.

The split is load-bearing for three directory scans, and each of them reads ALL
THREE directories: the world baker's zone picker
(`addons/world_baker/SCRIPT_baker_dock.gd`), the debug scene launcher
(`SCRIPT_debug_menu.gd`) and the pause-menu scene list
(`SCRIPT_menu_system.gd`). None of them recurses on its own. A fourth scan added
later that reads only `res://scenes` will find four files, look finished, and be
wrong — `TEST_world_baker.gd` pins the `utility/` half for the baker, which is
the one whose list is a set of buttons, and `TEST_command_menu.gd` pins the
`test/` third for all three.

The debug scene launcher now shows only three of what it finds: its `SHIPPED`
list narrows the OFFER to `SCENE_island_0`, `SCENE_test_ruin_0` and
`SCENE_test_ruin_1` for the handheld build. That is a filter applied AFTER the
scan and not a shorter scan, precisely so the rule above still holds —
`TEST_handheld_controls.gd` asserts both halves, that the offer is exactly those
three and that `SCENES_DIRS` still names all three directories. Empty the list and the picker goes back to offering
everything.

## The layout

```
addons/object_palette/   the placement plugin
addons/world_baker/      the pre-generation plugin
data/                    tuning resources; data/palettes/ holds PALETTE_ + LUT_
docs/                    every .md and .txt that is not a source file
experimental/            work that is not wired into the game
materials/               MAT_
models/                  MODEL_ + MESH_ + the TEX_ pulled out of the GLBs
  source/                BLEND_ — Blender files the engine never imports
music/                   MUSIC_, by context (battle, overworld, town, ...)
prefabs/                 PREFAB_
reference/               material that ships with nothing: brand/, shots_island/
scenes/                  SCENE_ — only the ones the game routes to
  utility/               SCENE_ — every other scene: the overlays the game
                         arrives in, and the lettered zones it was built from
  test/                  SCENE_ — UI test benches, one archetype per scene
scripts/                 SCRIPT_
  autoload/              AUTOLOAD_ — the singletons in project.godot
  world/                 SCRIPT_ for the streaming worlds — the island one and
                         the infinite terrain that shares its mesher
sfx/                     SFX_
shaders/                 SHADER_ + SHADERINC_
sky/                     SKY_
sprites/                 SPRITE_, by family: vegetation, debris, fire,
                         explosions, gore, exp_orbs, pickups; raw/ holds the
                         SRC_ art they cut from
textures/                TEX_; proc/ is what the generators in tools/ bake,
                         ruins/ is the ashen plating the ruins are clad in
tools/                   TOOL_ — everything offline
ui/                      UI_ + LOGO_ + THEME_; hud/ is the HUD kit,
                         touch/ is the on-screen control art, tarot/ is a
                         neon deck kept for its own sake, off the machine
vendor/                  third-party assets, under their upstream filenames
project.godot            the only file at the repo root
```

## The four exceptions, and why

**`vendor/`.** Third-party assets keep the filenames they were downloaded
with — the licensed typefaces in `vendor/fonts/` and Kenney's control pack in
`vendor/kenney_onscreen_controls/`. For a typeface the filename *is* the
identity, and for a pack the original names are what make it diffable against a
re-download. Rather than leave ninety-one silently-exempt files scattered
through the tree, the exception is a directory: everything under `vendor/` is
upstream's, everything outside it is ours and carries a prefix.

**`plugin.cfg`, in each addon.** Godot requires that exact filename to discover
a plugin, so `addons/object_palette/` and `addons/world_baker/` each carry one.
Their `script=` entries point at the prefixed script.

**The textures extracted out of the GLBs.** `models/MODEL_*.png` are not models;
they are images the GLTF importer pulls out of a `.glb`'s embedded textures on a
cold import, and it names them `<glb_stem>_<image_name>`. Renaming them does not
stick — delete `.godot`, reimport, and the importer's names come back alongside
whatever you renamed them to. So the importer's name wins here, and the `MODEL_`
prefix on a `.png` is a signal that the file is generated rather than authored.
Do not edit them; edit the `.glb`.

**Three textures keep upstream channel suffixes.** The project's convention is
`_albedo` / `_normal`, and `_C_`/`_N_`/`_c`/`_n` were normalised onto it. But
`TEX_rocky_trail_02_diff_128.png`, `TEX_rocky_trail_02_nor_gl_128.png` and
`TEX_pine_bark_nor_gl_512.png` would then collide with the crunched versions
that superseded them, so they keep the source naming that distinguishes them.

## Texture channel suffixes

A `TEX_` that is one map of a material set is named
`TEX_<material>_<NN>_<channel>_<size>`, and the channel comes from this list:

| Suffix | Channel |
|---|---|
| `_albedo` | Base colour |
| `_normal` | Tangent-space normal, **OpenGL (+Y)** — Godot's own convention |
| `_rough` | Roughness, greyscale |
| `_ao` | Ambient occlusion, greyscale |
| `_height` | Height / displacement, greyscale |
| `_orm` | Occlusion, roughness and metallic packed into R, G and B |

`_orm` is what `ORMMaterial3D` wants and is redundant with the separate `_ao`
and `_rough` beside it — both are kept because the packed map is one sampler
instead of two, and the loose ones are what you edit. Upstream sets that arrive
as `_roughness` are normalised to `_rough`; a set whose maps carry a generator
seed in the filename is renumbered `_01`, `_02` and so on, in seed order, so the
names say which variants exist rather than which random numbers made them.

A normal map that is DirectX-handed (-Y) must have its green channel inverted on
the way in, not at import time — `process/normal_map_invert_y` is a per-file
setting that is easy to lose in a reimport, and a flipped normal is invisible
until the light moves.

## Generated files

Anything under `textures/proc/`, and the `_burn` maps beside the sprites, is
baked by a `TOOL_` script and should be regenerated rather than hand-edited.
Those tools resolve their output paths from the repository root, so they can be
run from anywhere:

```
python3 tools/TOOL_gen_terrain_textures.py     # -> textures/proc/
python3 tools/TOOL_gen_burn_maps.py            # -> sprites/**/*_burn.png
python3 tools/TOOL_build_palette_lut.py        # -> data/palettes/
```

A `TOOL_` is not always Python. Some of what this project generates can only be
made by the engine that consumes it — a mesh repaired against a `.glb`'s real
geometry, a world meshed by the real mesher — so those tools are `.gd` scripts
run headless. They are still `TOOL_`: run by hand, never part of a frame.

```
godot --headless --script res://tools/TOOL_bake_world.gd           # -> user://bake/
```

**A `TOOL_` output that is a CACHE goes to `user://`, not into the tree.** The
world bake is ~100 MB and is reproducible from two source files and a seed; it
belongs on the machine that made it, not in every clone. The rule for telling
the two apart is whether the artefact is AUTHORED — `textures/proc/` is
generated but is the only copy of a decision about what rock looks like, so it
is committed and diffable. A bake is a saved computation and nothing more.

## Adding a file

Pick the prefix from what the file *is*, then the directory from what it is
*for*. If no prefix in the table fits, the honest move is to add a row here
rather than to leave the file untyped — one unprefixed file is how a convention
starts to rot.

## Bringing a model in: scale, origin, collider

Three things are wrong with nearly every `.glb` that arrives, and each has one
place it gets fixed.

**Scale goes in the `.import`,** as `nodes/root_scale`. Never as a scale on a
node in a prefab: the `.glb`'s own AABB and any collider the importer generates
are built at the import scale, so a node-level scale leaves every measurement
anybody takes describing a thing that is not what they see. Two models are
scaled today — `MODEL_orion_brat_v1` at 0.5 and `MODEL_golf_tee_box_platform`
at 0.4.

**Pick the scale off something real,** not off the model's overall size in
isolation. For the golf machine it was the thing it is — a vending machine, so
72 inches, with the two screens straddling the 1.6 m eye line as the check that
the number was right. For the tee box it was the staircase, whose risers have
to fit under the player's step budget. Overall size is the *result* of that
choice, not the input to it, and the reason belongs in the prefab where the
next person will look.

A model may not be internally proportioned to a person at all, and uniform
scale cannot fix that. The tee box's stairs were built about 2.8x human while
its backstop wall was already about right, so the two want scales that differ
by 3x. Say which feature won, in the prefab, and leave the other stated.

**Origin goes in a prefab,** because the importer has no setting for it. The
convention is the base of the model, centred in plan, so that placing the
prefab at a point on the terrain stands it there. Measure it, do not eyeball
it; `PREFAB_golf_tee_box_platform.tscn` shows the arithmetic.

**The collider belongs to the model where it possibly can.** Name the mesh
`something-col` in Blender and the importer builds a body from it — that is how
`MODEL_golf_tee_box_platform` gets its trimesh, and it costs nothing here. Only
when that is impossible does a collider go in a prefab: `PREFAB_golf_machine`
carries a hand-measured box because the machine is fifteen mesh nodes, and the
importer's `generate/physics` would give fifteen boxes rather than one.

**Then walk the player over it.** A model that scales and origins correctly can
still be unusable — see `TEST_golf_stairs.tscn`, which exists because
`move_and_slide` has no step handling and the shipped capsule could mount
0.10 m before `max_step_height` was added.

**And then walk the player over the ground beside it.** `TEST_player_slopes.tscn`
is the other half of that pair and it measures a different thing: not whether the
body ARRIVES, which it always did, but whether the ride is steady. The step code
`TEST_golf_stairs` protects used to fire on ramps as well — an incline blocks a
forward `test_move` exactly as a wall does — and lifted the body several times
further than a frame of walking rises, so every hill over about twenty degrees
was a sawtooth with the camera bolted to it. Nothing in the project failed. Both
harnesses run because a fix for either one is a plausible way to break the other.

## One GDScript rule that has its own harness

**Never read a node out of a container into a TYPED local and then test it for
validity.** The test cannot run:

```gdscript
var node: Node3D = _live[cell]                       # raises here
if node == null or not is_instance_valid(node):      # never reached
```

A typed assignment checks the object's class before storing it, and a freed
object has no class to check, so the assignment raises "Trying to assign invalid
previously freed instance" — and in a debug build a raise ABORTS the running
function. The guard is unreachable by construction, and the symptom is not a
stray console line but a system that stops: everything after the raise, in that
function and in its caller, simply does not happen.

Read it as a `Variant`, validate, and type it afterwards:

```gdscript
var entry: Variant = _live[cell]
if not is_instance_valid(entry):
    _live.erase(cell)
    continue
var node: Node3D = entry
```

`is_instance_valid` takes a Variant and is false for `null` too, so the two
cases the typed version tested separately become one test that runs.

`tests/TEST_freed_instance_guards.gd` reads the whole project and fails on the
broken shape. It found twenty of them the first time it was run;
`docs/DOC_glitch_blob_encounters.md` has the one that was reported and what it
actually cost.
