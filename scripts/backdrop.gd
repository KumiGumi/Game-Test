class_name Backdrop
extends Node2D
## Sky, hills and the stage floor. Screen space - the camera is static, so this
## can be drawn flat.
##
## This lives in its own node rather than on the Arena root for one reason:
## z_index is RELATIVE to the parent by default. With the backdrop drawn on the
## root, the root needed a low z_index, which then dragged every child's
## effective z down with it - and the ground layer (telegraphs) ended up
## underneath the floor it was supposed to be painted on. Giving the backdrop
## its own node lets the root sit at z 0 and every layer state its depth
## honestly.

func _ready() -> void:
	z_index = Tune.Z_BACKDROP


func _draw() -> void:
	_draw_sky()
	_draw_hills()
	_draw_stage()


func _draw_sky() -> void:
	# Wide enough to cover the viewport regardless of aspect.
	var left := Tune.ARENA_CENTER.x - 1400.0
	var w := 2800.0
	var top := -400.0
	var bottom := View.to_screen(Tune.ARENA_CENTER + Tune.ARENA_HALF).y
	var bands := 24
	for i in range(bands):
		var f0 := float(i) / float(bands)
		var y0 := lerpf(top, bottom, f0)
		var y1 := lerpf(top, bottom, float(i + 1) / float(bands))
		draw_rect(Rect2(Vector2(left, y0), Vector2(w, y1 - y0 + 1.0)),
			Tune.COL_SKY_TOP.lerp(Tune.COL_SKY_BOTTOM, f0))

	# Moon, well off to one side so it doesn't sit behind the fight.
	var horizon := View.to_screen(Tune.ARENA_CENTER - Tune.ARENA_HALF).y
	var moon := Vector2(Tune.ARENA_CENTER.x + 470.0, horizon - 250.0)
	draw_circle(moon, 46.0, Color(0.92, 0.93, 1.0, 0.85))
	draw_circle(moon, 70.0, Color(0.92, 0.93, 1.0, 0.06))


func _draw_hills() -> void:
	var horizon := View.to_screen(Tune.ARENA_CENTER - Tune.ARENA_HALF).y
	var cx := Tune.ARENA_CENTER.x
	# Flat silhouettes. This is scenery, not art.
	var peaks := [
		[-900.0, 210.0], [-560.0, 130.0], [-250.0, 260.0],
		[80.0, 150.0], [420.0, 235.0], [760.0, 120.0], [1050.0, 200.0],
	]
	for p in peaks:
		var x: float = cx + float(p[0])
		var h: float = float(p[1])
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - h * 1.5, horizon + 40.0),
			Vector2(x, horizon - h),
			Vector2(x + h * 1.5, horizon + 40.0),
		]), Tune.COL_HILLS)


func _draw_stage() -> void:
	var c := Tune.ARENA_CENTER
	var hs := Tune.ARENA_HALF
	var tl := View.to_screen(c - hs)
	var br := View.to_screen(c + hs)
	var rect := Rect2(tl, br - tl)

	draw_rect(rect, Tune.COL_ARENA_FLOOR)

	# Grid on the floor. Judging distance is most of what the boss patterns ask
	# of you, and a flat plane with no reference points makes that guesswork.
	var step := 140.0
	var x := c.x - hs.x + step
	while x < c.x + hs.x:
		draw_line(Vector2(x, tl.y), Vector2(x, br.y), Color(1, 1, 1, 0.04), 1.0)
		x += step
	var y := c.y - hs.y + step
	while y < c.y + hs.y:
		var sy := View.to_screen(Vector2(0.0, y)).y
		draw_line(Vector2(tl.x, sy), Vector2(br.x, sy), Color(1, 1, 1, 0.04), 1.0)
		y += step

	draw_rect(rect, Tune.COL_ARENA_EDGE, false, 3.0)
	# Front lip: a brighter near edge reads as the stage coming toward you.
	draw_line(Vector2(tl.x, br.y), Vector2(br.x, br.y), Color(1, 1, 1, 0.18), 4.0)
