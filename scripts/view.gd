class_name View
## World <-> screen projection, and the layer registry.
##
## THE COORDINATE RULE, because everything depends on it:
##
##   WORLD space is flat 2D. x = across the arena, y = depth into the screen.
##   All gameplay lives here - positions, distances, every AtkShape, every hit
##   test. Nothing in the combat code knows the view is angled.
##
##   SCREEN space is world with y multiplied by VIEW_SQUASH, which is what
##   gives the low side-on camera. A circle on the ground becomes an ellipse
##   for free; a distance test stays a distance test.
##
## The ground layer carries the squash as a node scale, so anything drawn in it
## (the floor, every telegraph) is projected automatically with no per-shape
## work. Actors sit in an unscaled layer and place themselves via to_screen(),
## which keeps characters standing upright instead of squashed flat.
##
## The layer statics are set by the Arena at startup. They live here rather
## than on the Arena so that spawning code never has to name the Arena class -
## GDScript will not compile that dependency cycle.

## Squashed ground plane. Telegraphs, floor, shadows. Scaled (1, VIEW_SQUASH).
static var ground: Node2D = null
## Upright things: player, boss, projectiles, damage numbers. Unscaled.
static var actors: Node2D = null


static func to_screen(w: Vector2) -> Vector2:
	return Vector2(w.x, w.y * Tune.VIEW_SQUASH)


static func to_world(s: Vector2) -> Vector2:
	return Vector2(s.x, s.y / Tune.VIEW_SQUASH)


## Depth ordering for actors: things further back draw behind things in front.
static func depth_z(world_y: float) -> int:
	return clampi(int(world_y * 0.05), -400, 400)
