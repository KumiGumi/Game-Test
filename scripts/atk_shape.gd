class_name AtkShape
extends RefCounted
## One shape, used for BOTH the telegraph drawing and the hitbox resolution.
##
## This is the central idea of the prototype: a telegraph and a hitbox are the
## same geometry at two different moments in time. There is no physics anywhere
## in this project - no Area2D, no collision layers. There is one player and one
## boss, both circles, so hits are resolved analytically. That makes them
## frame-exact, order-deterministic, cheap, and it means the debug hitbox
## visualiser draws literally the same shape the game tested against.
##
## All coordinates are WORLD space.

enum Kind {
	CIRCLE,   ## filled disc. danger inside.
	DONUT,    ## annulus. danger in the band; SAFE in the hole.
	CONE,     ## circular sector from origin along dir.
	RECT,     ## from origin, extending `length` along dir, `half_width` either side.
}

const ARC_SEGMENTS := 64

var kind: Kind = Kind.CIRCLE
var origin: Vector2 = Vector2.ZERO
## Outer radius (CIRCLE, DONUT, CONE).
var radius: float = 100.0
## Inner radius (DONUT only). The safe hole.
var inner_radius: float = 0.0
## Facing, normalised (CONE, RECT).
var dir: Vector2 = Vector2.RIGHT
## Half the total opening angle, in radians (CONE).
var half_angle: float = deg_to_rad(45.0)
## RECT extent along dir, and to either side of it.
var length: float = 200.0
var half_width: float = 50.0


# ---------------------------------------------------------------------------
# CONSTRUCTION
# ---------------------------------------------------------------------------

static func circle(p_origin: Vector2, p_radius: float) -> AtkShape:
	var s := AtkShape.new()
	s.kind = Kind.CIRCLE
	s.origin = p_origin
	s.radius = p_radius
	return s


static func donut(p_origin: Vector2, p_inner: float, p_outer: float) -> AtkShape:
	var s := AtkShape.new()
	s.kind = Kind.DONUT
	s.origin = p_origin
	s.inner_radius = p_inner
	s.radius = p_outer
	return s


static func cone(p_origin: Vector2, p_dir: Vector2, p_radius: float, p_half_angle_deg: float) -> AtkShape:
	var s := AtkShape.new()
	s.kind = Kind.CONE
	s.origin = p_origin
	s.dir = p_dir.normalized() if p_dir.length_squared() > 0.0 else Vector2.RIGHT
	s.radius = p_radius
	s.half_angle = deg_to_rad(p_half_angle_deg)
	return s


static func rect(p_origin: Vector2, p_dir: Vector2, p_length: float, p_half_width: float) -> AtkShape:
	var s := AtkShape.new()
	s.kind = Kind.RECT
	s.origin = p_origin
	s.dir = p_dir.normalized() if p_dir.length_squared() > 0.0 else Vector2.RIGHT
	s.length = p_length
	s.half_width = p_half_width
	return s


func duplicate_shape() -> AtkShape:
	var s := AtkShape.new()
	s.kind = kind
	s.origin = origin
	s.radius = radius
	s.inner_radius = inner_radius
	s.dir = dir
	s.half_angle = half_angle
	s.length = length
	s.half_width = half_width
	return s


# ---------------------------------------------------------------------------
# HIT RESOLUTION
# ---------------------------------------------------------------------------

## Point test. Use overlaps_circle() for anything with a body radius.
func contains(p: Vector2) -> bool:
	return overlaps_circle(p, 0.0)


## Circle-vs-shape. `r` is the target's body radius.
func overlaps_circle(c: Vector2, r: float) -> bool:
	match kind:
		Kind.CIRCLE:
			return c.distance_squared_to(origin) <= (radius + r) * (radius + r)

		Kind.DONUT:
			var d := c.distance_to(origin)
			return d <= radius + r and d >= inner_radius - r

		Kind.CONE:
			var to := c - origin
			var d := to.length()
			if d > radius + r:
				return false
			# Overlapping the apex counts as a hit regardless of angle.
			if d <= r or d < 0.0001:
				return true
			var ang := absf(to.angle_to(dir))
			# Inflate the sector by the angular size of the target circle.
			var inflate := asin(clampf(r / d, 0.0, 1.0))
			return ang <= half_angle + inflate

		Kind.RECT:
			var to := c - origin
			var along := to.dot(dir)
			var across := absf(to.dot(Vector2(-dir.y, dir.x)))
			# Distance from the circle centre to the closest point on the box.
			var dx := maxf(0.0, maxf(-along, along - length))
			var dy := maxf(0.0, across - half_width)
			return dx * dx + dy * dy <= r * r

	return false


## Nearest safe spot outside the shape, used by debug / AI hints. Best-effort.
func nearest_safe_point(from: Vector2, pad: float) -> Vector2:
	match kind:
		Kind.CIRCLE:
			var away := (from - origin)
			if away.length_squared() < 0.0001:
				away = Vector2.RIGHT
			return origin + away.normalized() * (radius + pad)
		Kind.DONUT:
			return origin + (from - origin).normalized() * maxf(inner_radius - pad, 0.0)
		_:
			var side := Vector2(-dir.y, dir.x)
			var s := 1.0 if (from - origin).dot(side) >= 0.0 else -1.0
			return origin + side * s * (half_width + pad)


# ---------------------------------------------------------------------------
# DRAWING
# ---------------------------------------------------------------------------
#
# `progress` (0..1) sweeps the danger fill outward during the wind-up so the
# player can read *when* it lands, not just *where*. The sweep always reaches
# the shape's true extent exactly when the hitbox goes live.

## Draw the filled danger region at the given wind-up progress.
func draw_fill(ci: CanvasItem, col: Color, progress: float) -> void:
	var t := clampf(progress, 0.0, 1.0)
	match kind:
		Kind.CIRCLE:
			if radius * t > 0.5:
				ci.draw_circle(origin, radius * t, col)

		Kind.DONUT:
			var outer := lerpf(inner_radius, radius, t)
			var band := outer - inner_radius
			if band > 0.5:
				ci.draw_arc(origin, inner_radius + band * 0.5, 0.0, TAU, ARC_SEGMENTS, col, band, true)

		Kind.CONE:
			if radius * t > 0.5:
				ci.draw_colored_polygon(_cone_points(radius * t), col)

		Kind.RECT:
			if length * t > 0.5:
				ci.draw_colored_polygon(_rect_points(length * t), col)


## Draw the outline at the shape's full extent - this is the readable boundary
## and must NOT animate, or the player can't learn the safe spot early.
func draw_outline(ci: CanvasItem, col: Color, width: float) -> void:
	match kind:
		Kind.CIRCLE:
			ci.draw_arc(origin, radius, 0.0, TAU, ARC_SEGMENTS, col, width, true)

		Kind.DONUT:
			ci.draw_arc(origin, radius, 0.0, TAU, ARC_SEGMENTS, col, width, true)
			if inner_radius > 1.0:
				ci.draw_arc(origin, inner_radius, 0.0, TAU, ARC_SEGMENTS, col, width, true)

		Kind.CONE:
			var pts := _cone_points(radius)
			pts.append(pts[0])
			ci.draw_polyline(pts, col, width, true)

		Kind.RECT:
			var rpts := _rect_points(length)
			rpts.append(rpts[0])
			ci.draw_polyline(rpts, col, width, true)


func _cone_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(origin)
	var base := dir.angle()
	var steps := maxi(4, int(ARC_SEGMENTS * (half_angle * 2.0) / TAU) + 2)
	for i in range(steps + 1):
		var a := base - half_angle + (half_angle * 2.0) * (float(i) / float(steps))
		pts.append(origin + Vector2.from_angle(a) * r)
	return pts


func _rect_points(l: float) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x) * half_width
	var tip := origin + dir * l
	return PackedVector2Array([
		origin + side,
		tip + side,
		tip - side,
		origin - side,
	])
