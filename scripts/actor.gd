class_name Actor
extends Node2D
## Anything that stands on the ground plane: the player, the boss, projectiles.
##
## An Actor's truth is `world_pos` (flat 2D, y = depth). Its node position is
## derived from that every frame via View.to_screen(), lifted by `height` so the
## body floats above its ground point and the character reads as standing up
## rather than lying flat. Gameplay never touches the node position.

## Ground position, WORLD space. This is what every hit test uses.
var world_pos: Vector2 = Vector2.ZERO
## Collision radius on the ground plane, world units.
var body_radius: float = 14.0
## How far above the ground point the body is drawn. Purely visual.
var height: float = 26.0


## Push world_pos into the node transform. Call once per frame after moving.
func sync_view() -> void:
	position = View.to_screen(world_pos) - Vector2(0.0, height)
	z_index = View.depth_z(world_pos.y)


## The actor's feet, in this node's local space.
func feet() -> Vector2:
	return Vector2(0.0, height)


## Squashed ellipse on the ground beneath the actor. Sells the standing pose
## more than anything else on screen does.
func draw_shadow(r: float, col: Color = Tune.COL_SHADOW) -> void:
	draw_ground_ellipse(feet(), r, col)


## Draw a circle of world-radius `r` as it appears lying on the ground plane.
func draw_ground_ellipse(at: Vector2, r: float, col: Color) -> void:
	draw_set_transform(at, 0.0, Vector2(1.0, Tune.VIEW_SQUASH))
	draw_circle(Vector2.ZERO, r, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_ground_ring(at: Vector2, r: float, col: Color, width: float) -> void:
	draw_set_transform(at, 0.0, Vector2(1.0, Tune.VIEW_SQUASH))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, width, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Clamp to the rectangular arena. Returns true if it hit a wall.
static func clamp_to_arena(p: Vector2) -> Vector2:
	var lim := Tune.ARENA_HALF - Vector2.ONE * Tune.ARENA_EDGE_PAD
	return Vector2(
		clampf(p.x, Tune.ARENA_CENTER.x - lim.x, Tune.ARENA_CENTER.x + lim.x),
		clampf(p.y, Tune.ARENA_CENTER.y - lim.y, Tune.ARENA_CENTER.y + lim.y)
	)


static func in_arena(p: Vector2, pad: float = 0.0) -> bool:
	var d := (p - Tune.ARENA_CENTER).abs()
	return d.x <= Tune.ARENA_HALF.x + pad and d.y <= Tune.ARENA_HALF.y + pad
