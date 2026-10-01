# Bake retention

**Status: in.** The roster, the librarian, the tool, the dock and the build gate
are all here and tested. `res://data/bake` has files in it for the first time.

---

## What this is for

Procedural generation is the labour-saving half of this project: nobody models
an island, a field and a seed do it. That stays true for content nobody has
chosen yet, and it is the reason the generator exists.

It stops being the right answer the moment a build ships. `SCENE_island_0` takes
**144 seconds** to mesh from nothing on the reference container — 1,908 chunk
meshes and 1,020 vegetation tiles — and ninety-odd seconds of meshing in front
of a player is not a loading screen, it is a fault report with a progress bar.
So the worlds the game has **chosen** are pre-baked, put in the build, and read
back; the player sees a load, and the loading screen says so.

`tools/TOOL_bake_world.gd` and the World Baker dock have been able to make a
bake since they were written. What has never existed is anything that KEEPS
them:

- A bake is named for the **signature** of the world it holds, so every edit to
  the mesher or the field writes a new ~104 MB file beside the old one, and
  nothing has ever removed the old one. After a week of terrain work `user://bake`
  is most of a gigabyte, of which one file describes a world anybody can load.
- `BakeStore.READ_DIRS` has put `res://data/bake` first since the day it was
  written. Nothing had ever put a file there.
- Nothing could answer "is every world this game ships actually in the build,
  and current" — which is the one question a build has to pass.

## The pieces

| | |
|---|---|
| `scripts/world/SCRIPT_bake_roster.gd` | `BakeRoster`. Which zones the game has chosen, and what becomes of their bakes. A list of decisions; nothing computes it. |
| `data/BAKEROSTER_shipping.tres` | This game's roster. `island_0` ships; `W` and `W2` are kept and never shipped. |
| `scripts/world/SCRIPT_bake_retention.gd` | `BakeRetention`. The librarian: what is on disk, what world each file is still for, and what should become of it. Also the one place a zone's terrain signature is derived. |
| `tools/TOOL_bake_retention.gd` | The tool. `--list`, `--stage`, `--sweep`, `--gate`, `--verify=APK`, `--dry-run`. Emits `>>retain` JSON lines. |
| `addons/bake_retention/` | The dock. The same tool with a table on it. See `DOC_bake_retention.md` in that directory. |
| `tools/TOOL_build_apk.sh` | Runs `--gate` before it exports and `--verify` after, and has `*.bake` in the include filter. |
| `addons/bake_retention/SCRIPT_bake_digest_export.gd` | Carries the generating code's digests into every export, so the build can recognise the bake it was given. See "The gate passed and the build still generated". |

## The policies

A roster maps a scene path to one of three words. The fourth state is not being
in the roster at all, and it is the safe one.

| | |
|---|---|
| **`ship`** | Must be pre-baked and **in `res://data/bake`**, or the build is refused. The player's machine must never generate this world. `island_0` is the game, so it is the one zone that carries this. |
| **`cache`** | Worth keeping on the machine that baked it, never worth putting in an APK. `W` is where terrain work happens: its bake is the difference between a six-second iteration and a two-and-a-half-minute one, and it is nobody's content. |
| **`drop`** | Deprecated. The zone is still in the tree, but nobody works on it and its bakes are not worth the disk. `W2` is the zone `island_0` was forked from. |
| *(absent)* | Reported and left alone, forever. A bake for a zone nobody listed is never swept. |

**Being absent from the roster is how a zone stops being shipped**, which is why
a key naming a scene that no longer exists is *reported* rather than dropped: a
rename wants a person to retype the key, not a tool to quietly leave the game
shipping one zone fewer than yesterday.

### `drop` loses every argument it is in

`drop` is the only policy that deletes something that still works, so it is the
only one whose **precedence** is load-bearing — and it comes last. A bake claimed
by a `drop` zone *and* by a `ship` or `cache` zone is **kept**.

That is not caution in the abstract. `SCENE_test_zone_W2` and `SCENE_island_0`
wire up the same field and the same chunk size, so they have the same terrain
signature and **one 93.8 MB terrain bake is both of theirs**. A rule that swept
on a single dropped claim would delete the shipping game's terrain because its
ancestor was retired. What retiring W2 actually reclaims is W2's own 10 MB of
vegetation, which nothing else claims.

Leaving a zone out of the roster is the other way to stop caring about it, and
it is the quiet one. `drop` is for when you want the disk back.

## What every file on disk is for

The librarian asks every bakeable zone what it hashes to right now, then judges
the two directories against the answers. Seven verdicts, and each is a different
hundred megabytes and a different fate:

| Verdict | Where | Means | Action |
|---|---|---|---|
| `shipped` | `res://` | current, for a zone that ships | keep |
| `freight` | `res://` | current, but for a zone that does **not** ship | **sweep** |
| `ready` | `user://` | current for a ship zone, not in the build yet | **stage** |
| `mirrored` | `user://` | current for a ship zone, already staged | keep |
| `cached` | `user://` | current for a `cache` zone | keep |
| `dropped` | `user://` | current, but every zone claiming it has been retired | **sweep** |
| `unclaimed` | either | current for a zone the roster does not name | keep |
| `stale` | either | describes no world any scene in this project builds | **sweep** |
| `spared` | `user://` | stale, but within `keep_stale` | keep |

`freight` is the one nobody thinks of: a perfectly good bake, for a real zone,
weighing an APK down for a world the game does not ship.

### Nothing current is ever swept

The only destructive verdict reachable without a roster entry is `stale`, and
stale means *no scene in this project builds this world*. Deleting one cannot
lose anything that is not reproducible by pressing Bake.

A bake that is **current for a zone nobody listed** is a live world somebody
built on purpose and forgot to write down, and an afternoon of meshing is not
something a housekeeping button gets to decide about. `BakeRoster.SWEEPS_UNCLAIMED`
is a constant, it is `false`, and it is not configurable.

The one exception is `drop`, which has to be typed on purpose, against a named
scene, and still loses to any other claim on the same file.

### And a partial survey cannot sweep at all

"Stale" means *no scene in this project builds this world*, and the only evidence
for that is having asked every scene. `--zone` narrows a survey, a zone that will
not load has no signature, and a survey can run out of time — in all three cases
every unasked zone's perfectly good bake is indistinguishable from a dead one.

So the tool tracks whether its survey was whole and **refuses `--sweep` when it
was not**, with exit 2 and the reason. Without that, `--zone=W --sweep` would
have deleted `island_0`'s 93.8 MB terrain bake: two and a half minutes of
meshing, removed by a housekeeping button, with nothing anywhere reporting an
error.

### `keep_stale`

How many stale bakes to spare, newest first, **per store**. Zero by default: a
stale bake is a hundred megabytes that describes no loadable world, and it is
reproducible. One is for the case where you are bisecting a terrain change and
want last version's world back without a two-minute wait.

Counted per store so that sparing one does not spare two terrains and no
vegetation, which would spare nothing usable. Never applied in `res://` — going
back to yesterday's terrain is something you do on your own machine, and no
version of a world nothing can load belongs in an APK.

## Staging copies, and why there are two of everything

`--stage` copies `user://bake/x.bake` into `res://data/bake/`, through a `.part`
and a rename — the same discipline `BakeStore.save_to` uses, because a hundred
megabytes takes long enough to copy that a full disk in the middle of it is a
real event, and the file at the destination should be the old bake or the new
one and never half of either.

It **copies rather than moves**, so a shipped world costs ~208 MB on the machine
that staged it. That is deliberate: `res://data/bake` is gitignored and
disposable — a `git clean` takes it — and the copy in `user://` is the master a
re-stage comes from. The cost is the build directory being a staging area rather
than a home.

Once staged, the `user://` copy reads as `mirrored` rather than `ready`, so a
second `--stage` copies nothing. Getting that wrong was a real bug during
development: the plan said "stage 2" over a complete build and every run
re-copied a hundred megabytes.

## The gate

```
godot --headless --script res://tools/TOOL_bake_retention.gd -- --gate
```

Exits **1** if any `ship` zone's bakes are not in `res://data/bake`, **0** if
they are, **2** if the tool itself fell over. `tools/TOOL_build_apk.sh` runs it
before exporting and refuses the build on 1.

**It writes nothing and fixes nothing, on purpose.** A gate that staged what it
found would make a build that passed and a build that was *made* to pass
indistinguishable, and the second one is a build nobody chose the contents of.

It does tell you which of the two problems you have — `on this machine, not in
the build` means run `--stage`; `not baked` means go and bake it.

`BAKE_GATE=off ./tools/TOOL_build_apk.sh` skips it, for a throwaway build where a
two-minute first load is nobody's problem.

### The one line nobody would find

`export_presets.cfg` is **gitignored** and rewritten from a heredoc on every run
of `TOOL_build_apk.sh`, so the include filter that lets a `.bake` into the APK
has to live in the **script**, not the config — anything written into the config
is wiped on the next build. It is `include_filter="*.json, *.bake"` at
`tools/TOOL_build_apk.sh:94`. Without it the APK ships bakeless and generates on
the player's phone, and nothing anywhere is an error: the loading screen would
honestly say GENERATING.

## The gate passed and the build still generated

**This happened, for one whole release, and it is the most instructive thing in
this document.**

`000.0.008` shipped with `data/bake/terrain_1573686522.bake` inside it — 93.8 MB,
staged, gated, present in the APK at `assets/data/bake/`. On a handheld it meshed
the island from nothing anyway. Two and a half minutes, every launch.

Nothing was broken. A bake is found by **signature**, and part of a signature is
a **digest of the code that generates the world** — `BakeStore.source_digest`
hashes `SCRIPT_chunk_mesher.gd`, `SCRIPT_island_field.gd` and
`SCRIPT_veg_scatter.gd`, so that editing the mesher invalidates every bake made
before the edit without anybody having to remember to bump a version. That is a
good rule and it is not the problem.

The problem is that `export_presets.cfg` carries `script_export_mode=2`. An
exported build contains `.gdc` — binary tokens — and **not one `.gd`**. So on the
player's machine every one of those `get_sha256` calls opened nothing and
answered `""`, and the signature came out as a completely different number:

| | terrain | veg |
|---|---|---|
| the machine that baked, and the gate | `1573686522` | `2734263492` |
| the shipped build | `1400194824` | `211603203` |

The build looked for two files nobody has ever written, did not find them, and
did the honest thing.

**Every check upstream was asking the right question of the wrong machine.** The
gate runs where the sources are, so it gets the baker's answer. `--stage` copies
the file the baker named. The include filter put it in the APK. All three were
correct and the build was wrong, and the only symptom was a loading screen
truthfully saying GENERATING TERRAIN.

### Carrying the number

Hashing what the build *does* contain is not an option: `.gdc` is a different
file and would hash differently on the machine that bakes. The digest is a
**build-time fact**, so it is computed once, at export, and carried.

`addons/bake_retention/SCRIPT_bake_digest_export.gd` is an `EditorExportPlugin`
that reads `_SOURCES` off the two stores, hashes the real files, and `add_file`s
`res://data/bake/CODE_DIGESTS.json` into the export. `add_file` rather than
writing to disk, deliberately: the table exists **only inside the build that
shipped it**, so there is nothing to gitignore, nothing to commit by accident,
and — the point — nothing that can still be lying around describing last week's
code. A table is built by the export that carries it or it does not exist.

`BakeStore.source_digest` reads it back, and only when it has to:

* a source that **opens** always wins, so the editor and the baker never consult
  the table and the one machine that can be wrong about its own code is the one
  that cannot read a cached answer;
* a table that is **missing, or short of a path**, leaves that digest `""` — the
  signature does not match, the world is generated, the player waits. Slow, and
  not wrong. The alternative is a build adopting a bake for code it is not
  running, which is a world with holes in it.

### `--verify`, which reads the artefact

```
godot --headless --script res://tools/TOOL_bake_retention.gd -- --verify=build/....apk
```

The gate asks *is the bake in the build*. This asks **will this build find it**,
and it is the only check here that opens the APK instead of the project. It
reads `CODE_DIGESTS.json` out of the zip, calls `BakeStore.read_as_exported`
with it — which makes every digest come from the table and ignores the sources
on this disk — recomputes each `ship` zone's signature, and requires
`assets/data/bake/<store>_<signature>.bake` to actually be in there. On failure
it prints what the APK *does* carry, because "it shipped one, under another
name" is almost always the answer.

`TOOL_build_apk.sh` runs it **after** the export and refuses to ship on exit 1.
`TEST_bake_export_digests.gd` covers the arithmetic; this covers the artefact,
and neither can replace the other.

## The staged bake is not in git

~104 MB per zone, and a **new** 104 MB every time the mesher or the field
changes. Committing that would put it in every clone and a fresh blob in history
on every terrain tune, forever, for a file reproducible from two scripts and a
seed in the time it takes to make a coffee.

So the build **stages** rather than carries: `/data/bake/` is in `.gitignore`,
the gate refuses a build that has not staged, and a machine that has never baked
cannot accidentally produce an APK that looks fine and generates its world on a
phone. That makes the gate load-bearing rather than a nicety, which is the
trade.

The roster itself **is** committed. It is the decision, not the output.

## One author for a signature

Deciding whether a bake is current means knowing what a zone hashes to, and
there is exactly one piece of code that works that out:
`BakeRetention.signature_of_world`. `tools/TOOL_bake_world.gd` calls it too,
rather than spelling the same three lines out beside a comment promising they
match — the baker's own header says a second opinion about the island is one too
many, and this is the same argument.

The seam takes an **instantiated world node** rather than a scene path precisely
so the baker can share it: the baker has already instantiated the scene and is
going to keep it, and retention instantiates, measures and frees.

### The vegetation signature, which `--check` used to refuse to answer

`TOOL_bake_world.gd --check` reported the terrain's verdict and said of the
forest only that "whether it MATCHES is decided when the scene loads, since its
signature is over the scatter's exports". The reasoning was that
`VegScatter._ready` resolves what the signature is taken over.

It does not. `_ready` resolves the **field** and builds the multimeshes, and
assigns **no `@export` at all** — and `BakeStore.exports_of` reads nothing but
`@export`s, which are set from the `.tscn` at instantiation. So the vegetation's
signature is exactly as knowable as the terrain's, and both tools now take it.

That is a claim about somebody else's file, so it is checked against somebody
else's file: `TEST_bake_retention.gd` walks `_ready`'s body for an assignment to
any name in the scatter's export list. The day one appears, the test says so
instead of a stale forest quietly being reported as current.

`--check` still gives the terrain's verdict the exit code, and that is a
judgement about what a check is *for* rather than about what is knowable: a zone
whose terrain is current and whose forest is not still loads in seconds and then
plants; a zone with no terrain bake meshes for two and a half minutes. Retention
reports both as equals, because "is this build complete" has no such asymmetry
in it.

## The loading screen was already right

`SCRIPT_world_loading_screen.gd` has had `title = "GENERATING TERRAIN"` and
`held_title = "LOADING TERRAIN"` since it was written, swapping on
`IslandWorld.bake_source`. Nothing here changed it. What was missing was never
the screen — it was any **guarantee** that a shipped build lands on the held
path, which is what the gate is.

`TEST_bake_shipped_world.gd` pins both halves: the screen's branch against a stub
world (including `bake_source == "memory"`, which is a held world too), and then
the real `SCENE_island_0` standing up and coming back with
`res://data/bake/terrain_1573686522.bake` and `LOADING TERRAIN`.

## Measured

Reference container, `SCENE_island_0`:

| | |
|---|---|
| bake from nothing | 144.8 s build, 7.0 s write |
| terrain bake | 93.8 MB, 1,908 entries |
| vegetation bake | 10.0 MB, 1,020 entries |
| a survey of all three zones | ~10 s, builds nothing |
| staging both | under a second |
| the APK, before | 294 MB, and it generated its world |
| the APK, after | 388 MB, and it reads it |

That last pair is the whole feature in two numbers. The 94 MB is the bake going
in — the terrain half is already Zstd'd, so the APK cannot squeeze it further —
and it buys a first launch that reads a file instead of meshing 1,908 chunks.
Verified by looking inside the exported APK for the packed paths:

    res://data/bake/terrain_1573686522.bake
    res://data/bake/veg_2734263492.bake

`island_0` and `SCENE_test_zone_W2` **share a terrain signature** — same field,
same chunk size — so one 93.8 MB terrain bake serves both, and retention reports
it as belonging to both. Their vegetation signatures differ, so their forests do
not share. That is why W2 being `drop` reclaims 10 MB and not 104: the terrain is
the shipping game's too.

## Running the tests

```
godot --headless --path . --script res://tests/TEST_bake_retention.gd
godot --headless --path . --script res://tests/TEST_bake_retention_tool.gd
godot --headless --path . --script res://tests/TEST_bake_retention_dock.gd
godot --headless --path . --script res://tests/TEST_bake_shipped_world.gd
godot --headless --path . --script res://tests/TEST_bake_export_digests.gd
```

| | |
|---|---|
| `TEST_bake_export_digests.gd` | The agreement between three files that are otherwise unrelated: what the stores list in `_SOURCES`, what the export plugin puts in the table, and what `source_digest` does when a source is not there. Any one can drift silently, and the failure costs a build. |
| `TEST_bake_retention.gd` | The verdicts, from fabricated rows; the two destructive calls against real files in a scratch directory; the roster; and the four couplings that rot quietly — the directories, the zone list, the signature's single author, and the `_ready` walk that backs the vegetation claim. |
| `TEST_bake_retention_tool.gd` | The tool as a **process**, hermetically: exit codes, `--dry-run` actually doing nothing, staging twice copying once, the protocol against the dock, and an `exit` line on every path out. |
| `TEST_bake_retention_dock.gd` | The dock against the real tool in a real subprocess. Refresh only — the destructive buttons are the same flags the tool test drives against scratch, where they cannot reach a real bake. Plus a cancelled run being reported as cancelled. |
| `TEST_bake_shipped_world.gd` | The far end. Skips its second half, loudly, on a machine with nothing staged. |

The last one is the only test here that needs a bake to exist. To make it run in
full:

```
godot --headless --script res://tools/TOOL_bake_world.gd
godot --headless --script res://tools/TOOL_bake_retention.gd -- --stage
```

## What is not here yet

- **Nothing stages automatically.** The gate refuses a build and tells you to
  run `--stage`; it will not run it for you, for the reason above. A CI job that
  wants one-button builds should run `--stage` then `--gate` as two steps, so the
  log says which one it was.
- **`--prune-mirrored`.** Once a world is staged the `user://` copy is pure
  redundancy for *shipping*, and reclaiming it would halve the cost. It is not
  here because `res://data/bake` is gitignored and easy to blow away, and the
  master copy is what a re-stage comes from.
- **Retention knows about terrain and vegetation.** `BakeRetention.STORES` is
  two strings; a third kind of bake would need adding there, and the filename
  parser already splits from the right so a store called `golf_props` works.
- **`SCRIPT_terrain_field_base.gd` (the Q2 fork) has none of this.** It is a
  deliberate byte-for-byte fork owned by the flight sim and its header says
  changes made for the island must not land there.
