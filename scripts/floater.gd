class_name Floater
extends Node2D
## Rising damage number. Screen space - spawn it with an already-projected
## position.
##
## Size scales with the hit, so a rain of small ticks and one big cast look
## different at a glance. Multi-hit skills throwing a stream of numbers is a
## large part of why they feel better than one number, so this is not decoration.

var text: String = ""
var col: Color = Color.WHITE
var font_size: int = 16
var lifetime: float = 0.8
var rise: float = 52.0
var drift: float = 0.0
## Extra pop on the first frames. Big hits punch harder.
var punch: float = 0.0

var _t: float = 0.0
var _font: Font


static func spawn(at: Vector2, txt: String, c: Color, size: int = 16, p_punch: float = 0.0) -> Floater:
	var f := Floater.new()
	f.position = at
	f.text = txt
	f.col = c
	f.font_size = size
	f.punch = p_punch
	f.lifetime = Tune.FLOATER_LIFETIME
	f.rise = Tune.FLOATER_RISE
	f.drift = randf_range(-22.0, 22.0)
	View.actors.add_child(f)
	return f


## Damage number with size derived from how big the hit was.
static func damage(at: Vector2, amount: float, c: Color) -> Floater:
	var f := clampf(amount / maxf(Tune.FLOATER_BIG_DAMAGE, 1.0), 0.0, 1.0)
	var size := int(lerpf(float(Tune.FLOATER_SIZE_MIN), float(Tune.FLOATER_SIZE_MAX), sqrt(f)))
	return Floater.spawn(at, str(roundi(amount)), c, size, f)


func _ready() -> void:
	z_index = 200
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
	# Overshoot scale on spawn, settling to 1.0.
	var scale_pop := 1.0 + punch * 0.5 * maxf(0.0, 1.0 - p * 6.0)
	var sz := maxi(8, int(float(font_size) * scale_pop))
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var pos := off - Vector2(w * 0.5, 0.0)
	# Outline pass, so numbers stay readable over bright telegraphs.
	for o in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		draw_string(_font, pos + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, a * 0.75))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(col.r, col.g, col.b, a))
