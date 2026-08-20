class_name Shard
extends Actor
## Non-damaging travel visual: a projectile arcing from the caster to a point
## where something is about to land.
##
## It exists purely for readability. A rain that just materialises impacts on
## the floor doesn't read as something YOU did - the eye needs to see it leave
## the player. The damage still belongs entirely to the impact Telegraph; this
## only has to arrive at the same moment.

var from_pos: Vector2 = Vector2.ZERO
var to_pos: Vector2 = Vector2.ZERO
## Wait this long before launching, then take `travel` seconds to arrive.
var delay: float = 0.0
var travel: float = 0.25
var col: Color = Color.WHITE
## Launch height, and how far the arc bulges above the straight line.
var start_height: float = 34.0
var arc: float = 90.0

var _t: float = 0.0
var _trail: Array[Vector2] = []


static func launch(from: Vector2, to: Vector2, p_delay: float, p_travel: float,
		c: Color, r: float = 7.0) -> Shard:
	var s := Shard.new()
	s.from_pos = from
	s.to_pos = to
	s.delay = p_delay
	s.travel = maxf(p_travel, 0.02)
	s.col = c
	s.body_radius = r
	s.world_pos = from
	View.actors.add_child(s)
	return s


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	_t += delta
	if _t < delay:
		return
	visible = true

	var p := clampf((_t - delay) / travel, 0.0, 1.0)
	world_pos = from_pos.lerp(to_pos, p)
	# Parabola: leaves at body height, peaks mid-flight, lands on the ground
	# exactly as the impact goes live.
	height = lerpf(start_height, 0.0, p) + arc * sin(PI * p)

	_trail.push_front(world_pos)
	if _trail.size() > 5:
		_trail.resize(5)

	if p >= 1.0:
		queue_free()
		return

	sync_view()
	queue_redraw()


func _draw() -> void:
	var origin := View.to_screen(world_pos)
	for i in range(_trail.size()):
		var q := View.to_screen(_trail[i]) - origin
		var f := 1.0 - float(i) / float(_trail.size())
		draw_circle(q, body_radius * f * 0.7, Color(col.r, col.g, col.b, 0.18 * f))
	draw_circle(Vector2.ZERO, body_radius, col)
	draw_circle(Vector2.ZERO, body_radius * 0.45, Color(1, 1, 1, 0.9))
