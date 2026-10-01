class_name ArcadeHud
extends CanvasLayer

# THE SCOREBOARD, in seven-segment digits, one character to a rounded box:
#
#   top left      SCORE, then the digits stacked DOWN the left edge, most
#                 significant at the top
#   bottom left   [LEVEL] [0] [0] [1]
#   bottom right  [LIVES] [0] [0] [3]
#
# Every position always shows a digit: the unused high places are lit zeros, as
# on an arcade cabinet before the score has climbed into them, never blanks. Each
# digit's unlit segments stay faintly visible behind the lit ones, the way an LED
# readout looks.
#
# A box is a half-transparent dark panel with a dark stroke and round corners.
# The layer sits above PostFX (128), so the dither leaves the readout crisp.

@export var score_digits := 7
@export var counter_digits := 3
@export var lit := Color(1.0, 0.82, 0.18)
@export var unlit := Color(1.0, 1.0, 1.0, 0.07)
@export var box_fill := Color(0.0, 0.0, 0.0, 0.5)
@export var box_stroke := Color(0.03, 0.03, 0.04, 1.0)
@export var digit_size := Vector2(46, 72)
@export var margin := 24

var _score: Array[SevenSeg] = []
var _level: Array[SevenSeg] = []
var _lives: Array[SevenSeg] = []


func _ready() -> void:
	layer = 130
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.position = Vector2(margin, margin)
	root.add_child(col)
	col.add_child(_label_box("SCORE"))
	for i in score_digits:
		var d := _digit_box()
		_score.append(d)
		col.add_child(d.get_parent())
	for c in col.get_children():
		c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var lv := _counter_row("LEVEL", _level)
	lv.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, margin)
	root.add_child(lv)
	var lf := _counter_row("LIVES", _lives)
	root.add_child(lf)
	lf.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, margin)
	lv.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lf.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lf.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	set_score(0)
	set_level(1)
	set_lives(3)


func set_score(v: int) -> void:
	_show(_score, v)


func set_level(v: int) -> void:
	_show(_level, v)


func set_lives(v: int) -> void:
	_show(_lives, v)


func _show(digits: Array[SevenSeg], v: int) -> void:
	var n := digits.size()
	var s := str(clampi(v, 0, int(pow(10, n)) - 1)).lpad(n, "0")
	for i in n:
		digits[i].value = int(s[i])


func _counter_row(label: String, into: Array[SevenSeg]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label_box(label))
	for i in counter_digits:
		var d := _digit_box()
		into.append(d)
		row.add_child(d.get_parent())
	return row


func _box() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = box_fill
	sb.border_color = box_stroke
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _digit_box() -> SevenSeg:
	var p := _box()
	var d := SevenSeg.new()
	d.custom_minimum_size = digit_size
	d.lit = lit
	d.unlit = unlit
	p.add_child(d)
	return d


func _label_box(text: String) -> PanelContainer:
	var p := _box()
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", lit)
	l.add_theme_font_size_override("font_size", 30)
	var f: Font = Fonts.technical()
	if f != null:
		l.add_theme_font_override("font", f)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, digit_size.y)
	p.add_child(l)
	return p


## One seven-segment digit, drawn: seven bevelled bars, lit or faint.
class SevenSeg extends Control:
	# Segments a..g as bits 0..6: a top, b top right, c bottom right, d bottom,
	# e bottom left, f top left, g middle.
	const GLYPHS := [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]

	var lit := Color.WHITE
	var unlit := Color(1, 1, 1, 0.07)
	var value := 0:
		set(v):
			value = clampi(v, 0, 9)
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var t := w * 0.18          # bar thickness
		var gap := t * 0.18        # gap where bars meet
		var x0 := t * 0.5
		var x1 := w - t * 0.5
		var y0 := t * 0.5
		var ym := h * 0.5
		var y1 := h - t * 0.5
		var bars := [
			_h(x0 + gap, x1 - gap, y0, t),   # a
			_v(x1, y0 + gap, ym - gap, t),   # b
			_v(x1, ym + gap, y1 - gap, t),   # c
			_h(x0 + gap, x1 - gap, y1, t),   # d
			_v(x0, ym + gap, y1 - gap, t),   # e
			_v(x0, y0 + gap, ym - gap, t),   # f
			_h(x0 + gap, x1 - gap, ym, t),   # g
		]
		var bits: int = GLYPHS[value]
		for i in 7:
			draw_colored_polygon(bars[i], lit if bits & (1 << i) else unlit)

	func _h(xa: float, xb: float, y: float, t: float) -> PackedVector2Array:
		var e := t * 0.5
		return PackedVector2Array([Vector2(xa, y), Vector2(xa + e, y - e), Vector2(xb - e, y - e),
				Vector2(xb, y), Vector2(xb - e, y + e), Vector2(xa + e, y + e)])

	func _v(x: float, ya: float, yb: float, t: float) -> PackedVector2Array:
		var e := t * 0.5
		return PackedVector2Array([Vector2(x, ya), Vector2(x + e, ya + e), Vector2(x + e, yb - e),
				Vector2(x, yb), Vector2(x - e, yb - e), Vector2(x - e, ya + e)])
