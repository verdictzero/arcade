extends Node
## Autoload "Fonts". The single source of truth for the project's type system.
## Pick a font by ROLE, never by filename, so the rules live in one place:
##
##   title()        Draco          — BIG titles / branding moments only
##   technical()    ShareTechMono  — in-game technical UI: flight systems,
##                                    machine/console readouts, diegetic HUDs
##   ui(weight)     Zalando Sans   — "normal" (non-diegetic) UI: menus, etc.
##   clock()        digital-7      — the clock (and LCD-style numeric readouts)
##   prompts()      PromptFont     — button prompts: one character per physical
##                                    control. NEVER for words — see below.
##
## Fonts are lazy-loaded and cached. Registered first in [autoload] so every
## other script (including other autoloads like ModeLabel) can use it in _ready.
##
## PROMPTFONT IS A SPECIAL CASE and the one role with a rule attached. Its
## glyphs sit on REAL Unicode — U+21D3 is ⇓ anywhere else and the A button
## there — so it is never a fallback on another font and never the font of a
## sentence: it draws the glyph, `ui()` draws the words beside it. Which
## codepoint is which control lives in `ButtonGlyphs`; the notes are in
## `docs/DOC_button_glyphs.md`.

const _DRACO := "res://vendor/fonts/Draco.otf"
const _MONO := "res://vendor/fonts/ShareTechMono-Regular.ttf"
const _CLOCK := "res://vendor/fonts/digital-7 (mono).ttf"
const _PROMPTS := "res://vendor/fonts/promptfont/promptfont.ttf"

# Zalando Sans weights, keyed by the name passed to ui(). Add more weights here
# as needed rather than loading font files directly elsewhere.
const _ZALANDO := {
	"extralight": "res://vendor/fonts/ZalandoSans/ZalandoSans-ExtraLight.ttf",
	"light": "res://vendor/fonts/ZalandoSans/ZalandoSans-Light.ttf",
	"regular": "res://vendor/fonts/ZalandoSans/ZalandoSans-Regular.ttf",
	"medium": "res://vendor/fonts/ZalandoSans/ZalandoSans-Medium.ttf",
	"semibold": "res://vendor/fonts/ZalandoSans/ZalandoSans-SemiBold.ttf",
	"bold": "res://vendor/fonts/ZalandoSans/ZalandoSans-Bold.ttf",
	"extrabold": "res://vendor/fonts/ZalandoSans/ZalandoSans-ExtraBold.ttf",
	"black": "res://vendor/fonts/ZalandoSans/ZalandoSans-Black.ttf",
}

# Narrow (Condensed) cut of the same weights, for tight rows like menu items.
# "extralight" is the thinnest available; "black" the heaviest.
const _ZALANDO_CONDENSED := {
	"extralight": "res://vendor/fonts/ZalandoSans/ZalandoSans-CondensedExtraLight.ttf",
	"light": "res://vendor/fonts/ZalandoSans/ZalandoSans-CondensedLight.ttf",
	"regular": "res://vendor/fonts/ZalandoSans/ZalandoSans-Condensed.ttf",
	"medium": "res://vendor/fonts/ZalandoSans/ZalandoSans-CondensedMedium.ttf",
	"semibold": "res://vendor/fonts/ZalandoSans/ZalandoSans-CondensedSemiBold.ttf",
	"bold": "res://vendor/fonts/ZalandoSans/ZalandoSans-CondensedBold.ttf",
	"extrabold": "res://vendor/fonts/ZalandoSans/ZalandoSans-CondensedExtraBold.ttf",
	"black": "res://vendor/fonts/ZalandoSans/ZalandoSans-CondensedBlack.ttf",
}

var _cache: Dictionary = {}


func title() -> Font:
	return _cached(_DRACO)


func technical() -> Font:
	return _cached(_MONO)


func clock() -> Font:
	return _cached(_CLOCK)


# PromptFont: controller and keyboard glyphs, one character each. Pair it with
# `ButtonGlyphs` for the codepoints — nothing should paste the characters into
# a string literal, where they read as arrows and maths in every editor.
func prompts() -> Font:
	return _cached(_PROMPTS)


# Zalando Sans in the requested weight ("regular", "medium", "semibold", "bold",
# "light", "black"). Pass condensed=true for the narrow cut (tight menu rows).
# Unknown weights fall back to regular.
func ui(weight: String = "regular", condensed: bool = false) -> Font:
	var table := _ZALANDO_CONDENSED if condensed else _ZALANDO
	var path: String = table.get(weight, table["regular"])
	return _cached(path)


func _cached(path: String) -> Font:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]
