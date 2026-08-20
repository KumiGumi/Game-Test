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


# ---------------------------------------------------------------------------
# THE FLOOR
# ---------------------------------------------------------------------------
#
# Two rects, both world space:
#
#   arena_rect - the outer bounds. Nothing walks past this, ever, so the camera
#                framing stays put and nobody wanders into the void by holding W.
#   floor_rect - the SOLID part. Starts equal to arena_rect. When a platform
#                breaks it shrinks, and the gap between the two becomes a hole
#                you fall through.
#
# Lives here as a static rather than on the Arena so that movement code never
# has to name the Arena class - the same reason the hostile registry does.

static var floor_rect: Rect2 = arena_rect()


static func arena_rect() -> Rect2:
	return Rect2(Tune.ARENA_CENTER - Tune.ARENA_HALF, Tune.ARENA_HALF * 2.0)


static func reset_floor() -> void:
	floor_rect = arena_rect()


## Break away one side of the stage. `dir` is -1 for the left, +1 for the right.
static func break_platform(dir: int) -> void:
	var r := floor_rect
	var cut := r.size.x * Tune.PLATFORM_BREAK_FRACTION
	if dir < 0:
		r.position.x += cut
	r.size.x -= cut
	floor_rect = r


static func floor_is_broken() -> bool:
	return floor_rect.size.x < arena_rect().size.x - 1.0


## Clamp to the OUTER bounds. Being over a hole is legal - that's the fall.
static func clamp_to_arena(p: Vector2) -> Vector2:
	var lim := Tune.ARENA_HALF - Vector2.ONE * Tune.ARENA_EDGE_PAD
	return Vector2(
		clampf(p.x, Tune.ARENA_CENTER.x - lim.x, Tune.ARENA_CENTER.x + lim.x),
		clampf(p.y, Tune.ARENA_CENTER.y - lim.y, Tune.ARENA_CENTER.y + lim.y)
	)


static func in_arena(p: Vector2, pad: float = 0.0) -> bool:
	var d := (p - Tune.ARENA_CENTER).abs()
	return d.x <= Tune.ARENA_HALF.x + pad and d.y <= Tune.ARENA_HALF.y + pad


## Is this point standing on something solid?
static func on_floor(p: Vector2) -> bool:
	return floor_rect.has_point(p)
