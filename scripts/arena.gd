class_name Arena
extends Node2D
## Root. Builds the whole scene in code - the .tscn is one node with this
## script attached and nothing else, deliberately: no number in this prototype
## should live inside a scene file where it can't be found or diffed.
##
## Also owns the things that are global to a run: elapsed time, screen shake,
## hitstop, and the instant restart.

static var instance: Arena

var world: Node2D
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
	z_index = -20

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	dummy = Dummy.new()
	dummy.name = "Dummy"
	dummy.global_position = Tune.ARENA_CENTER
	world.add_child(dummy)

	player = Player.new()
	player.name = "Player"
	player.global_position = _player_spawn()
	world.add_child(player)

	camera = Camera2D.new()
	camera.position = Tune.ARENA_CENTER
	camera.name = "Camera"
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
	return Tune.ARENA_CENTER + Vector2(0.0, Tune.ARENA_RADIUS * 0.55)


## Every live telegraph, for the step-5 hitbox visualiser. Hostiles are tracked
## by the Events autoload instead - see Events.hostiles().
func telegraphs() -> Array[Telegraph]:
	var out: Array[Telegraph] = []
	for c in world.get_children():
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

	queue_redraw()


# ---------------------------------------------------------------------------
# RUN CONTROL
# ---------------------------------------------------------------------------

## Instant restart. Not a scene reload - transient nodes are dropped and the
## persistent ones are reset in place, so there is no hitch and no load.
## The selected variant deliberately survives, so A/B testing isn't interrupted.
func restart() -> void:
	for c in world.get_children():
		if c == player or c == dummy:
			continue
		c.queue_free()

	player.reset()
	player.global_position = _player_spawn()
	dummy.reset()
	hud.reset()
	elapsed = 0.0
	_shake = 0.0
	camera.offset = Vector2.ZERO
	FxRing.pop(world, Tune.ARENA_CENTER, Tune.ARENA_RADIUS, Tune.ARENA_RADIUS * 0.6, Color(1, 1, 1, 0.35), 0.35)


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
# FLOOR
# ---------------------------------------------------------------------------

func _draw() -> void:
	var c := Tune.ARENA_CENTER
	var r := Tune.ARENA_RADIUS
	draw_circle(c, r, Tune.COL_ARENA_FLOOR)

	# Concentric guides. These are not decoration - judging "am I at melee range
	# or ranged range" is most of what the boss patterns will ask of you.
	for i in range(1, 4):
		var rr := r * float(i) / 4.0
		draw_arc(c, rr, 0.0, TAU, 64, Color(1, 1, 1, 0.04), 1.0, true)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		draw_line(c + Vector2.from_angle(a) * (r * 0.18), c + Vector2.from_angle(a) * r, Color(1, 1, 1, 0.03), 1.0, true)

	draw_arc(c, r, 0.0, TAU, 96, Tune.COL_ARENA_EDGE, 3.0, true)
