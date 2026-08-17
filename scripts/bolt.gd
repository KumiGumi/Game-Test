class_name Bolt
extends Actor
## Player projectile. Travels on the ground plane in world space, drawn lifted
## by `height` so it reads as flying. Analytic sweep against hostiles - no
## physics. Targets come from Hostile.all(); that contract is the whole
## interface, so the Warden drops in later with no changes to this file.

var dir: Vector2 = Vector2.RIGHT
var speed: float = 1200.0
var damage: float = 0.0
var stagger: float = 0.0
var action_idx: int = Tune.NO_ACTION
var is_counter: bool = false
var col: Color = Color.WHITE
var max_range: float = 900.0

var _travelled: float = 0.0
var _trail: Array[Vector2] = []


static func fire(from: Vector2, p_dir: Vector2, p_col: Color) -> Bolt:
	var b := Bolt.new()
	b.world_pos = from
	b.dir = p_dir
	b.col = p_col
	b.height = Tune.BOLT_HEIGHT
	View.actors.add_child(b)
	return b


func _process(delta: float) -> void:
	var step := speed * delta
	var from := world_pos
	var to := from + dir * step

	var target := _sweep(from, to)
	if target != null:
		world_pos = to
		sync_view()
		_hit(target)
		return

	world_pos = to
	_travelled += step

	_trail.push_front(world_pos)
	if _trail.size() > 6:
		_trail.resize(6)

	if _travelled >= max_range or not Actor.in_arena(world_pos, 160.0):
		_fizzle()
		return

	sync_view()
	queue_redraw()


func _sweep(from: Vector2, to: Vector2) -> Hostile:
	var targets := Hostile.all()
	if targets.is_empty():
		return null
	# Sample along the step so a fast bolt can't tunnel through a target.
	var samples := maxi(1, int(from.distance_to(to) / maxf(body_radius, 4.0)) + 1)
	for i in range(1, samples + 1):
		var p := from.lerp(to, float(i) / float(samples))
		for h in targets:
			if p.distance_to(h.world_pos) <= h.body_radius + body_radius:
				return h
	return null


func _hit(target: Hostile) -> void:
	target.apply_hit(damage, stagger, action_idx, is_counter)
	var contact := View.to_screen(world_pos) - Vector2(0.0, height)
	FxRing.pop(contact, body_radius, body_radius + 32.0, col, 0.20)
	Events.shake_requested.emit(Tune.SHAKE_ON_HIT)
	queue_free()


func _fizzle() -> void:
	FxRing.pop(View.to_screen(world_pos) - Vector2(0.0, height), body_radius,
		body_radius + 10.0, Color(col.r, col.g, col.b, 0.35), 0.14)
	queue_free()


func _draw() -> void:
	# Trail points are world positions; bring them into this node's local space.
	var origin := View.to_screen(world_pos)
	for i in range(_trail.size()):
		var p := View.to_screen(_trail[i]) - origin
		var f := 1.0 - float(i) / float(_trail.size())
		draw_circle(p, body_radius * f * 0.8, Color(col.r, col.g, col.b, 0.16 * f))
	draw_circle(Vector2.ZERO, body_radius, col)
	draw_circle(Vector2.ZERO, body_radius * 0.5, Color(1, 1, 1, 0.85))
	# A shadow on the ground under a flying bolt sells the height difference.
	draw_ground_ellipse(Vector2(0.0, height), body_radius * 0.7, Color(0, 0, 0, 0.22))
