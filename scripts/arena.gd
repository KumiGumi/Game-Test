class_name Arena
extends Node2D
## Root. Builds the whole scene in code - the .tscn is one node with this
## script and nothing else, deliberately: no number in this prototype should
## live inside a scene file where it can't be found or diffed.
##
## Owns the layer split that makes the side-on view work:
##
##   backdrop  - screen space: sky, hills, the stage floor. Its own node, so
##               the root can sit at z 0 (see _ready).
##   ground    - scaled (1, VIEW_SQUASH). Telegraphs live here, so a circle
##               becomes a ground ellipse with no per-shape work.
##   actors    - unscaled. Characters, projectiles, numbers - upright.
##
## Also owns what's global to a run: elapsed time, shake, hitstop, restart.

static var instance: Arena

var backdrop: Backdrop
var ground: Node2D
var actors: Node2D
var player: Player
var warden: Warden
var hud: Hud
var camera: Camera2D

var elapsed: float = 0.0

var _shake: float = 0.0
var _base_time_scale: float = 1.0
var _hitstop_active: bool = false
var _restarting: bool = false


func _ready() -> void:
	instance = self
	# The root stays at z 0. z_index is RELATIVE to the parent, so a root with a
	# low z drags every layer below it down with it - which is how telegraphs
	# ended up painted underneath the floor. Each layer states its own depth.
	z_index = 0

	backdrop = Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)

	ground = Node2D.new()
	ground.name = "Ground"
	ground.scale = Vector2(1.0, Tune.VIEW_SQUASH)
	ground.z_index = Tune.Z_GROUND
	add_child(ground)

	actors = Node2D.new()
	actors.name = "Actors"
	add_child(actors)

	# Registered before anything can spawn into them.
	View.ground = ground
	View.actors = actors

	warden = Warden.new()
	warden.name = "Warden"
	warden.world_pos = Tune.ARENA_CENTER
	actors.add_child(warden)

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
	hud.warden = warden
	layer.add_child(hud)

	_register_debug_actions()

	Events.shake_requested.connect(_on_shake)
	Events.hitstop_requested.connect(_on_hitstop)
	Events.restart_requested.connect(restart)
	Events.player_died.connect(_on_player_died)


## Numpad 1-8 force the boss to run pattern N immediately, so a pattern can be
## tested in isolation instead of waiting on the RNG. Registered here rather
## than in project.godot so the keycodes come from the engine's own constants
## and can't drift. The rest of the debug tooling lands in step 5.
func _register_debug_actions() -> void:
	var keys := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5,
		KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
	for i in range(keys.size()):
		_bind("force_pattern_%d" % (i + 1), keys[i])
	# Platform breaks, so falling can be tested now. Step 4 hangs the real
	# trigger on an HP threshold.
	_bind("break_left", KEY_KP_DIVIDE)
	_bind("break_right", KEY_KP_MULTIPLY)
	_bind("restore_floor", KEY_KP_0)


func _bind(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


## Break away one side of the stage. Anyone standing there falls, which is the
## whole reason the mechanic exists.
func break_platform(dir: int) -> void:
	Actor.break_platform(dir)
	Events.shake_requested.emit(16.0)
	Events.platform_broke.emit(dir)
	# Shove the boss back onto solid ground; it does not fall.
	warden.world_pos = _nearest_solid(warden.world_pos)


func _nearest_solid(p: Vector2) -> Vector2:
	var r := Actor.floor_rect
	return Vector2(
		clampf(p.x, r.position.x + 40.0, r.position.x + r.size.x - 40.0),
		clampf(p.y, r.position.y + 40.0, r.position.y + r.size.y - 40.0)
	)


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

	for i in range(Tune.WARDEN_PATTERNS.size()):
		if Input.is_action_just_pressed("force_pattern_%d" % (i + 1)):
			warden.force_pattern(i)

	if Input.is_action_just_pressed("break_left"):
		break_platform(-1)
	if Input.is_action_just_pressed("break_right"):
		break_platform(1)
	if Input.is_action_just_pressed("restore_floor"):
		Actor.reset_floor()

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
		if c != player and c != warden:
			c.queue_free()

	Actor.reset_floor()
	player.reset()
	player.world_pos = _player_spawn()
	player.sync_view()
	warden.reset()
	hud.reset()
	elapsed = 0.0
	_shake = 0.0
	_restarting = false
	camera.offset = Vector2.ZERO


## Step 4 replaces this with the real failure loop; for now death just resets
## the run so a bad pull costs a couple of seconds rather than a menu.
func _on_player_died() -> void:
	if _restarting:
		return
	_restarting = true
	await get_tree().create_timer(Tune.DEATH_RESTART_DELAY, true, false, true).timeout
	restart()


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
