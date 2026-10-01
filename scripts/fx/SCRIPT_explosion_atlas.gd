class_name ExplosionAtlas
extends RefCounted

# THE EXPLOSION'S PICTURES, baked in code: a spark, eight puffs of smoke that are
# one puff turning over, and eight fireballs. Taken as-is from verdictzero/mewd-engine
# (godot/scripts/game/effects.gd, the half of its Effects class that bakes the
# art — bake_atlases, its colour ramps and its value-noise/fbm), which ports it
# from that project's js/effects.js bakeEffectAtlases. Only the class around it is
# new; SCRIPT_explosion_fx.gd is what draws with them.

const SMOKE_PUFFS := 8
const FIREBALLS := 8

static var _atlases := {}

## {spark, smoke, fireball}: ImageTextures, frames side by side. Baked
## once and shared — the gun's stream wants the fireballs:
##   Particles.new({..., "map": Effects.atlases().fireball, "frames": Effects.FIREBALLS})
static func atlases() -> Dictionary:
	if _atlases.is_empty():
		_atlases = bake_atlases()
	return _atlases

static func bake_atlases() -> Dictionary:
	var spark := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	spark.fill(ramp("bone", 1.0))
	# EIGHT PUFFS THAT ARE ONE PUFF, which is the fix for smoke that
	# popped: one fbm field whose lattice wraps after PW rows, sampled with
	# a vertical offset of PW/N per frame. Frame N is frame 0 again, every
	# step between them the same small scroll, so a puff turns over over
	# its life rather than flickering.
	const PW := 32
	var pn := fbm(PW, PW, 4, 3, 70)
	var puffs := Image.create(PW * SMOKE_PUFFS, PW, false, Image.FORMAT_RGBA8)
	for f in SMOKE_PUFFS:
		var off := roundi(f * PW / float(SMOKE_PUFFS))
		for y in PW:
			for x in PW:
				var sy := (y + off) % PW
				var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
				var edge := maxf(0.0, 1.0 - d)
				var a := clampf(edge * 1.8 * (0.45 + pn[sy * PW + x] * 0.8) - 0.15, 0.0, 1.0)
				if a <= 0.05:
					continue
				puffs.set_pixel(f * PW + x, y, Color8(235, 232, 230, roundi(a * 255)))
	# The stream's particle: a ball of fire, white at the heart through
	# the ember colours to a soft dark-red rim, eight of them so a stream
	# is not one blob repeated. Drawn additively, so where they overlap
	# they add up to white — which is what makes a dense arc read as one
	# flame rather than beads on a string.
	var balls := Image.create(32 * FIREBALLS, 32, false, Image.FORMAT_RGBA8)
	for f in FIREBALLS:
		var n := fbm(32, 32, 4, 3, 300 + f * 17)
		for y in 32:
			for x in 32:
				var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
				var v := clampf((1.0 - d) * (0.6 + n[y * 32 + x] * 0.8), 0.0, 1.0)
				if v < 0.06:
					continue
				var c := ramp("fire", minf(1.0, v * 1.15))
				c.a8 = roundi(minf(1.0, v / 0.35) * 255)
				balls.set_pixel(f * 32 + x, y, c)
	return {
		"spark": ImageTexture.create_from_image(spark),
		"smoke": ImageTexture.create_from_image(puffs),
		"fireball": ImageTexture.create_from_image(balls),
	}

## js/palette.js's ramps this file and Giblets draw with (the stock box):
## stops, smoothstep between them, `gamma` bending where the entries sit.
const RAMPS := {
	"grey": {"n": 24, "gamma": 1.30, "stops": [[0.0, [6, 7, 11]], [0.5, [92, 94, 102]], [1.0, [248, 248, 252]]]},
	"bone": {"n": 16, "gamma": 1.25, "stops": [[0.0, [22, 20, 17]], [0.5, [130, 124, 108]], [1.0, [244, 238, 216]]]},
	"yellow": {"n": 16, "gamma": 1.15, "stops": [[0.0, [20, 16, 4]], [0.5, [168, 144, 24]], [1.0, [252, 248, 140]]]},
	"rust": {"n": 16, "gamma": 1.20, "stops": [[0.0, [16, 9, 6]], [0.5, [118, 62, 30]], [1.0, [224, 150, 92]]]},
	"fire": {"n": 44, "gamma": 1.0, "stops": [[0.00, [0, 0, 0]], [0.10, [34, 0, 0]], [0.24, [96, 6, 0]], [0.40, [168, 26, 0]],
		[0.56, [226, 74, 6]], [0.72, [248, 142, 14]], [0.87, [252, 216, 62]], [1.00, [255, 255, 226]]]},
}
static var _ramp_cache := {}

static func ramp(key: String, t: float) -> Color:
	if not _ramp_cache.has(key):
		var spec: Dictionary = RAMPS[key]
		var out := []
		var n: int = spec.n
		for i in n:
			var u := pow(float(i) / (n - 1), 1.0 if spec.gamma == 1.0 else 1.0 / spec.gamma)
			var stops: Array = spec.stops
			var k := 0
			while k < stops.size() - 2 and u > stops[k + 1][0]:
				k += 1
			var f := clampf((u - stops[k][0]) / maxf(1e-6, stops[k + 1][0] - stops[k][0]), 0.0, 1.0)
			var s := f * f * (3.0 - 2.0 * f)
			var c0: Array = stops[k][1]
			var c1: Array = stops[k + 1][1]
			out.append(Color8(roundi(c0[0] + (c1[0] - c0[0]) * s), roundi(c0[1] + (c1[1] - c0[1]) * s), roundi(c0[2] + (c1[2] - c0[2]) * s)))
		_ramp_cache[key] = out
	var r: Array = _ramp_cache[key]
	return r[clampi(roundi(t * (r.size() - 1)), 0, r.size() - 1)]

## js/util.js makeRng: xorshift32, as the JS runs it
static func _rng_next(s: int) -> int:
	s = (s ^ (s << 13)) & 0xFFFFFFFF
	s = s ^ (s >> 17)
	s = (s ^ (s << 5)) & 0xFFFFFFFF
	return s

## js/pixel.js valueNoise: a lattice of `cells` that wraps, smoothstepped
static func value_noise(w: int, h: int, cells: int, seed: int) -> PackedFloat32Array:
	var s := seed & 0xFFFFFFFF
	if s == 0:
		s = 0x9e3779b9
	var g := PackedFloat32Array()
	g.resize(cells * cells)
	for i in g.size():
		s = _rng_next(s)
		g[i] = s / 4294967296.0
	var out := PackedFloat32Array()
	out.resize(w * h)
	var sx := float(cells) / w
	var sy := float(cells) / h
	for y in h:
		var fy := y * sy
		var iy := floori(fy)
		var ty := fy - iy
		var wy := ty * ty * (3.0 - 2.0 * ty)
		var y0 := posmod(iy, cells)
		var y1 := (y0 + 1) % cells
		for x in w:
			var fx := x * sx
			var ix := floori(fx)
			var tx := fx - ix
			var wx := tx * tx * (3.0 - 2.0 * tx)
			var x0 := posmod(ix, cells)
			var x1 := (x0 + 1) % cells
			var a := g[y0 * cells + x0]
			var b := g[y0 * cells + x1]
			var c := g[y1 * cells + x0]
			var d := g[y1 * cells + x1]
			var top := a + (b - a) * wx
			out[y * w + x] = top + ((c + (d - c) * wx) - top) * wy
	return out

## js/pixel.js fbm: octaves of value noise, each twice as fine and half
## as strong
static func fbm(w: int, h: int, base_cells: int, octaves: int, seed: int, gain := 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var amp := 1.0
	var total := 0.0
	var cells := base_cells
	for o in octaves:
		var n := value_noise(w, h, cells, seed + o * 7919)
		for i in out.size():
			out[i] += n[i] * amp
		total += amp
		amp *= gain
		cells *= 2
		if cells > w:
			break
	for i in out.size():
		out[i] /= total
	return out
