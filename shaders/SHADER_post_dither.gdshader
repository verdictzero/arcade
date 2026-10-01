shader_type canvas_item;

// Fullscreen post: chunky pixelation + 4x4 Bayer ordered-dither + palette
// LUT lookup. Each pixel snaps the sampled (and dither-offset) screen color
// to the nearest entry in a baked palette LUT.
//
// LUT format: tiled-horizontally. For LUT_LEVELS = N, the texture is
// (N*N) x N. Cell (r, g, b) in [0, N) lives at pixel (b*N + r, g) and stores
// the nearest palette color to that quantized RGB triple. Bake with
// tools/TOOL_build_palette_lut.py.

// CHUNK WIDTH IN SCREEN PIXELS. 2 is the shipped default: the frame is resolved
// at half resolution in each axis and every 2x2 block takes one colour.
//
// IT WAS 1, WHICH IS NOT PIXELATION AT ALL — at 1 this pass quantises colour and
// dithers, but the chunk grid lands exactly on the screen grid and no pixel is
// ever merged with its neighbour. Everything the project does to look like a
// PlayStation 1 title — the palette LUT, the nearest-filtered textures, the
// crunched art in `SCRIPT_crunch_art.gd` — was being drawn at whatever native resolution
// the window happened to be, so the chunkiness came from the palette alone and
// scaled away on a large monitor. 2 makes the pixel a fixed object again.
//
// WHAT IT WORKS OUT TO: at 2, this project's 1280x720 base viewport resolves
// 640x360. The console this is imitating usually output 320x240, which at 16:9
// is nearer `pixel_size` 4 — so 2 is deliberately short of the reference. The
// settings menu exposes the dial (Pixel Density) for anybody who wants to go
// further; this is the default, not a ceiling.
//
// WHAT IT DOES NOT TOUCH, measured by `tests/RENDER_dither_pixel_size.gd` on a
// paused frame with only this uniform moved: the HUD and the menu panels. They
// are drawn on layers ABOVE this pass, and the numbers say so — going 1 -> 2
// changes 21.6% of a flight frame and 41.6% of the menu, but only 0.6% of the
// HUD's top-left readout box. The ring gauges DO go through it (29.1%), so the
// split is per-element rather than "all UI is safe"; the 3D frame and the
// in-world target markers take the full change. Do not reach for this uniform
// expecting it to make text chunkier — most of the text is not behind it.
//
// The DITHER MATRIX IS INDEXED PER CHUNK, not per pixel (see `cell` below), so
// raising this coarsens the Bayer pattern with the pixels rather than leaving a
// fine dither crawling underneath a coarse grid. That is the reason this is one
// uniform and not two.
uniform int pixel_size : hint_range(1, 16) = 2;
// Chunk height / width ratio. 1.0 => square chunks (the shipped default);
// 2.0 => pixels twice as tall as wide. Selectable at runtime; never 0 (a 0
// chunk size collapses the pixelation and divides by zero below).
uniform float pixel_aspect : hint_range(0.25, 4.0) = 1.0;
// LEVELS PER CHANNEL IN THE LUT'S GRID, and it MUST equal what the bake used or
// every lookup addresses the wrong cell — a frame that stays plausible with every
// colour in it wrong. `TOOL_build_palette_lut.py` bakes at 16.
//
// IT IS NOT THE NUMBER OF COLOURS IN THE PALETTE, which two dozen comments across
// this project say it is. 16 here means a 16x16x16 quantisation grid — 4096 cells,
// stored as the 256x16 image. `palette/PALETTE_ps1-soft.hex` holds FIVE HUNDRED AND TWELVE
// colours, of which this bake can reach 389; the other 123 lose their cells to a
// nearer neighbour, because the grid is coarser than the palette in places.
// Measured by `tests/TEST_palette_lock.gd`, which asserts both numbers.
//
// The qualitative argument every one of those comments is making survives intact —
// this is a quantiser, so a colour landing between two entries jumps to the nearer
// one instead of blending, which is why surfaces in this project are graded onto
// entries rather than tuned by eye. Only the count was wrong, by a factor of 32.
uniform int lut_levels : hint_range(2, 32) = 16;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D palette_lut : repeat_disable, filter_nearest;

const float bayer[16] = float[](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

vec3 palette_lookup(vec3 c) {
	float n = float(lut_levels);
	vec3 q = floor(clamp(c, 0.0, 1.0) * (n - 1.0) + 0.5);
	vec2 uv = vec2(
		(q.b * n + q.r + 0.5) / (n * n),
		(q.g + 0.5) / n);
	return textureLod(palette_lut, uv, 0.0).rgb;
}

void fragment() {
	// Chunk size: width = pixel_size, height = pixel_size * pixel_aspect. The
	// shipped pair is 2 and 1.0 — square chunks, two screen pixels on a side.
	// (This comment used to say the default aspect was 2.0 and kept a 1:2 look;
	// the uniform above has defaulted to 1.0 for as long as it has existed.)
	vec2 ps = vec2(float(pixel_size), max(float(pixel_size) * pixel_aspect, 1.0));
	vec2 chunk_origin = floor(FRAGCOORD.xy / ps) * ps;
	vec2 sample_uv = (chunk_origin + ps * 0.5) * SCREEN_PIXEL_SIZE;
	vec3 col = texture(screen_tex, sample_uv).rgb;

	ivec2 cell = ivec2(mod(chunk_origin / ps, 4.0));
	int idx = cell.y * 4 + cell.x;
	float threshold = (bayer[idx] + 0.5) / 16.0 - 0.5;

	col += vec3(threshold) * dither_strength / float(lut_levels - 1);

	COLOR = vec4(palette_lookup(col), 1.0);
}
