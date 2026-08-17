class_name Floater
extends Node2D
## Rising damage / stagger number. Pure readability aid - if the numbers are
## distracting while judging feel, drop Tune.FLOATER_LIFETIME to 0.

var text: String = ""
var col: Color = Color.WHITE
var font_size: int = 16
var lifetime: float = 0.75
var rise: float = 46.0
var drift: float = 0.0

var _t: float = 0.0
var _font: Font


static func spawn(parent: Node, at: Vector2, txt: String, c: Color, size: int = 16) -> Floater:
	var f := Floater.new()
	f.global_position = at
	f.text = txt
	f.col = c
	f.font_size = size
	f.lifetime = Tune.FLOATER_LIFETIME
	f.rise = Tune.FLOATER_RISE
	f.drift = randf_range(-18.0, 18.0)
	parent.add_child(f)
	return f


func _ready() -> void:
	z_index = 20
	_font = ThemeDB.fallback_font
	if lifetime <= 0.0:
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var p := clampf(_t / maxf(lifetime, 0.0001), 0.0, 1.0)
	var off := Vector2(drift * p, -rise * ease(p, 0.4))
	var a := 1.0 - ease(p, 2.5)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := off - Vector2(w * 0.5, 0.0)
	draw_string(_font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, a * 0.6))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(col.r, col.g, col.b, a))
