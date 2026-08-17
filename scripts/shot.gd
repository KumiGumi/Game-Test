class_name Shot
extends Actor
## Boss projectile. The mirror of Bolt: travels the ground plane in world space,
## drawn lifted so it reads as flying, resolved analytically against the player.

var dir: Vector2 = Vector2.RIGHT
var speed: float = 320.0
var damage: float = 60.0
var label: String = "SHOT"
var col: Color = Tune.COL_TELEGRAPH

var _trail: Array[Vector2] = []


static func fire(from: Vector2, p_dir: Vector2, p_speed: float, p_radius: float,
		p_damage: float, c: Color, p_label: String = "SHOT") -> Shot:
	var s := Shot.new()
	s.world_pos = from
	s.dir = p_dir.normalized()
	s.speed = p_speed
	s.body_radius = p_radius
	s.damage = p_damage
	s.col = c
	s.label = p_label
	s.height = Tune.SHOT_HEIGHT
	View.actors.add_child(s)
	return s


func _process(delta: float) -> void:
	var from := world_pos
	var to := from + dir * speed * delta

	var p := Player.instance
	if p != null and is_instance_valid(p):
		# Sample along the step so a fast shot can't tunnel past the player.
		var samples := maxi(1, int(from.distance_to(to) / maxf(body_radius, 6.0)) + 1)
		for i in range(1, samples + 1):
			var q := from.lerp(to, float(i) / float(samples))
			if q.distance_to(p.world_pos) <= p.body_radius + body_radius:
				world_pos = q
				_hit(p)
				return

	world_pos = to
	if not Actor.in_arena(world_pos, Tune.SHOT_DESPAWN_PAD):
		queue_free()
		return

	_trail.push_front(world_pos)
	if _trail.size() > 5:
		_trail.resize(5)

	sync_view()
	queue_redraw()


func _hit(p: Player) -> void:
	# take_hit reports false when i-frames or god mode ate it. Either way the
	# projectile is spent - a dodged shot must not keep flying and clip you again.
	p.take_hit(damage, label)
	FxRing.pop(View.to_screen(world_pos) - Vector2(0.0, height),
		body_radius, body_radius + 28.0, col, 0.20)
	queue_free()


func _draw() -> void:
	var origin := View.to_screen(world_pos)
	for i in range(_trail.size()):
		var q := View.to_screen(_trail[i]) - origin
		var f := 1.0 - float(i) / float(_trail.size())
		draw_circle(q, body_radius * f * 0.75, Color(col.r, col.g, col.b, 0.15 * f))
	draw_circle(Vector2.ZERO, body_radius, col)
	draw_circle(Vector2.ZERO, body_radius * 0.45, Color(1, 1, 1, 0.8))
	draw_ground_ellipse(Vector2(0.0, height), body_radius * 0.7, Color(0, 0, 0, 0.22))
