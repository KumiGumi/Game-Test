class_name FxRing
extends Node2D
## Throwaway expanding ring. Impact feedback, dash trails, Overheat pops.
## Screen space - spawn it with an already-projected position.

var col: Color = Color.WHITE
var start_radius: float = 6.0
var end_radius: float = 40.0
var lifetime: float = 0.25
var width: float = 3.0
var filled: bool = false
## Squash the ring vertically so it reads as lying on the ground rather than
## facing the camera. Set to Tune.VIEW_SQUASH for ground impacts, 1.0 for
## body-height hits.
var squash: float = 1.0

var _t: float = 0.0


static func pop(at: Vector2, r0: float, r1: float, c: Color, life: float = 0.25) -> FxRing:
	var f := FxRing.new()
	f.position = at
	f.start_radius = r0
	f.end_radius = r1
	f.col = c
	f.lifetime = life
	View.actors.add_child(f)
	return f


## Impact on the ground plane: flattened to match the view angle.
static func ground_pop(at_world: Vector2, r0: float, r1: float, c: Color, life: float = 0.25) -> FxRing:
	var f := FxRing.pop(View.to_screen(at_world), r0, r1, c, life)
	f.squash = Tune.VIEW_SQUASH
	return f


func _ready() -> void:
	z_index = 150


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var p := clampf(_t / maxf(lifetime, 0.0001), 0.0, 1.0)
	var r := lerpf(start_radius, end_radius, ease(p, 0.35))
	var a := (1.0 - p) * col.a
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, squash))
	if filled:
		draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, a * 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col.r, col.g, col.b, a), width * (1.0 - p * 0.5), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
