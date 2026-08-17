class_name Bolt
extends Node2D
## Player projectile. Analytic sweep against hostiles - no physics.
##
## Targets come from Hostile.all(); that contract is the whole interface, so
## the Warden drops in later with no changes to this file.

var dir: Vector2 = Vector2.RIGHT
var speed: float = 1200.0
var radius: float = 9.0
var damage: float = 0.0
var stagger: float = 0.0
var skill_idx: int = -1
var is_counter: bool = false
var col: Color = Color.WHITE
var max_range: float = 900.0

var _travelled: float = 0.0
var _trail: Array[Vector2] = []


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	var step := speed * delta
	var from := global_position
	var to := from + dir * step

	var target := _sweep(from, to)
	if target != null:
		global_position = to
		_hit(target)
		return

	global_position = to
	_travelled += step

	_trail.push_front(global_position)
	if _trail.size() > 6:
		_trail.resize(6)

	if _travelled >= max_range or global_position.distance_to(Tune.ARENA_CENTER) > Tune.ARENA_RADIUS + 120.0:
		_fizzle()
		return

	queue_redraw()


func _sweep(from: Vector2, to: Vector2) -> Hostile:
	var targets := Hostile.all()
	if targets.is_empty():
		return null
	# Sample along the step so a fast bolt can't tunnel through a target.
	var samples := maxi(1, int(from.distance_to(to) / maxf(radius, 4.0)) + 1)
	for i in range(1, samples + 1):
		var p := from.lerp(to, float(i) / float(samples))
		for h in targets:
			if p.distance_to(h.global_position) <= h.body_radius + radius:
				return h
	return null


func _hit(target: Hostile) -> void:
	# Contact point on the target's surface, so the pop reads at the edge.
	var contact: Vector2 = target.global_position + (global_position - target.global_position).normalized() * target.body_radius
	target.apply_hit(damage, stagger, skill_idx, is_counter)
	FxRing.pop(get_parent(), contact, radius, radius + 34.0, col, 0.22)
	Events.shake_requested.emit(Tune.SHAKE_ON_HIT)
	queue_free()


func _fizzle() -> void:
	FxRing.pop(get_parent(), global_position, radius, radius + 12.0, Color(col.r, col.g, col.b, 0.4), 0.15)
	queue_free()


func _draw() -> void:
	for i in range(_trail.size()):
		var p := to_local(_trail[i])
		var f := 1.0 - float(i) / float(_trail.size())
		draw_circle(p, radius * f * 0.8, Color(col.r, col.g, col.b, 0.16 * f))
	draw_circle(Vector2.ZERO, radius, col)
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 1, 1, 0.85))
