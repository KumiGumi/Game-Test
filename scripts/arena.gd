class_name Arena
extends Node2D
## Root. Builds the whole scene in code - the .tscn is one node with this
## script and nothing else, deliberately: no number in this prototype should
## live inside a scene file where it can't be found or diffed.
##
## Owns the layer split that makes the side-on view work:
##
##   backdrop  - drawn here, in screen space (sky, hills, the stage floor)
##   ground    - scaled (1, VIEW_SQUASH). Telegraphs live here, so a circle
##               becomes a ground ellipse with no per-shape work.
##   actors    - unscaled. Characters, projectiles, numbers - upright.
##
## Also owns what's global to a run: elapsed time, shake, hitstop, restart.

static var instance: Arena

var ground: Node2D
var actors: Node2D
var player: Player
var dummy: Dummy
var hud: Hud
var camera: Camera2D

var elapsed: float = 0.0

var _shake: float = 0.0
var _base_time_scale: float = 1.0
var _hitstop_active: bool = false


func _ready() -> void:
	instance = self
	z_index = -100

	ground = Node2D.new()
	ground.name = "Ground"
	ground.scale = Vector2(1.0, Tune.VIEW_SQUASH)
	ground.z_index = -10
	add_child(ground)

	actors = Node2D.new()
	actors.name = "Actors"
	add_child(actors)

	# Registered before anything can spawn into them.
	View.ground = ground
	View.actors = actors

	dummy = Dummy.new()
	dummy.name = "Dummy"
	dummy.world_pos = Tune.ARENA_CENTER
	actors.add_child(dummy)

	player = Player.new()
	player.name = "Player"
	player.world_pos = _player_spawn()
	actors.add_child(player)

	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2(Tune.ARENA_CENTER.x, Tune.CAMERA_SCREEN_Y)
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = Hud.new()
	hud.name = "Hud"
	hud.player = player
	hud.dummy = dummy
	layer.add_child(hud)

	Events.shake_requested.connect(_on_shake)
	Events.hitstop_requested.connect(_on_hitstop)
	Events.restart_requested.connect(restart)


func _player_spawn() -> Vector2:
	return Tune.ARENA_CENTER + Vector2(0.0, Tune.ARENA_HALF.y * 0.55)


## Every live telegraph, for the step-5 hitbox visualiser. Hostiles are tracked
## by Hostile.all() instead.
func telegraphs() -> Array[Telegraph]:
	var out: Array[Telegraph] = []
	for c in ground.get_children():
		var tg := c as Telegraph
		if tg != null:
			out.append(tg)
	return out


func _process(delta: float) -> void:
	elapsed += delta
	hud.elapsed = elapsed

	if Input.is_action_just_pressed("restart"):
		restart()

	if _shake > 0.0:
		_shake = maxf(0.0, _shake - Tune.SHAKE_DECAY * delta)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


# ---------------------------------------------------------------------------
# RUN CONTROL
# ---------------------------------------------------------------------------

## Instant restart. Not a scene reload - transient nodes are dropped and the
## persistent ones reset in place, so there's no hitch and no load. The selected
## variant deliberately survives, so A/B testing isn't interrupted.
func restart() -> void:
	for c in ground.get_children():
		c.queue_free()
	for c in actors.get_children():
		if c != player and c != dummy:
			c.queue_free()

	player.reset()
	player.world_pos = _player_spawn()
	player.sync_view()
	dummy.reset()
	hud.reset()
	elapsed = 0.0
	_shake = 0.0
	camera.offset = Vector2.ZERO


func set_base_time_scale(s: float) -> void:
	_base_time_scale = s
	if not _hitstop_active:
		Engine.time_scale = s


func _on_shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func _on_hitstop(duration: float) -> void:
	if duration <= 0.0 or _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.0
	# Real-time timer: process_always, not in physics, ignore time scale.
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = _base_time_scale
	_hitstop_active = false


# ---------------------------------------------------------------------------
# BACKDROP - screen space. The camera is static, so this can be drawn flat.
# ---------------------------------------------------------------------------

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
		var f1 := float(i + 1) / float(bands)
		var y0 := lerpf(top, bottom, f0)
		var y1 := lerpf(top, bottom, f1)
		draw_rect(Rect2(Vector2(left, y0), Vector2(w, y1 - y0 + 1.0)),
			Tune.COL_SKY_TOP.lerp(Tune.COL_SKY_BOTTOM, f0))

	# Moon, well off to one side so it doesn't sit behind the fight.
	var horizon := View.to_screen(Tune.ARENA_CENTER - Tune.ARENA_HALF).y
	draw_circle(Vector2(Tune.ARENA_CENTER.x + 470.0, horizon - 250.0), 46.0, Color(0.92, 0.93, 1.0, 0.85))
	draw_circle(Vector2(Tune.ARENA_CENTER.x + 470.0, horizon - 250.0), 70.0, Color(0.92, 0.93, 1.0, 0.06))


func _draw_hills() -> void:
	var horizon := View.to_screen(Tune.ARENA_CENTER - Tune.ARENA_HALF).y
	var cx := Tune.ARENA_CENTER.x
	# Two silhouette bands. Flat shapes only - this is scenery, not art.
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

	# Grid on the floor. Judging distance is most of what the boss patterns will
	# ask of you, and a flat plane with no reference points makes that guesswork.
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
