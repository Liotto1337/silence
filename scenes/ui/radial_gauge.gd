class_name RadialGauge
extends Control
## Circular charge meter for the flashlight battery.

@export var value: float = 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var label: String = "":
	set(v):
		label = v
		queue_redraw()
@export var thickness: float = 7.0
@export var color_full: Color = Color("f2e6b8")
@export var color_low: Color = Color("e0503a")
@export var color_back: Color = Color(1, 1, 1, 0.12)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - thickness
	draw_arc(c, r, 0.0, TAU, 48, color_back, thickness, true)
	if value > 0.0:
		var col := color_low.lerp(color_full, clampf(value * 3.0, 0.0, 1.0))
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * value, maxi(4, int(48 * value)), col, thickness, true)
	if label != "":
		var font := get_theme_default_font()
		var fs := 15
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-ts.x * 0.5, ts.y * 0.3), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, color_full)
