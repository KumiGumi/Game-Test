extends Node
## Headless smoke harness. Exits non-zero on failure.
##   godot --headless --path . tests/smoke.tscn --quit-after 20000
##
## Written as one coroutine rather than a step machine: the sequencing is the
## readable part, and `await` keeps it that way.

var arena: Arena
var player: Player
var warden: Warden
var fails := 0


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		printerr("FAIL  ", label)


## Real-time sleep: ignores time_scale so hitstop can't make tests flaky.
func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _taken() -> float:
	return warden.max_hp - warden.hp


func _aim_at_boss() -> void:
	# There is no cursor in a headless run, so drive the aim hook directly.
	player.aim_override_active = true
	player.aim_override = warden.world_pos
	player.act_aim = (warden.world_pos - player.world_pos).normalized()
	player.act_target = warden.world_pos
	player.facing = player.act_aim


func _ready() -> void:
	_test_shapes()
	_test_view()

	var ps := load("res://scenes/main.tscn") as PackedScene
	arena = ps.instantiate() as Arena
	add_child(arena)
	player = arena.player
	warden = arena.warden
	print("--- boot ok, player %s, warden %s" % [player.world_pos, warden.world_pos])

	_test_layers()

	# Park the boss while the player's own kit is under test.
	warden.process_mode = Node.PROCESS_MODE_DISABLED
	player.god_mode = true

	await _test_player()

	player.god_mode = false
	warden.process_mode = Node.PROCESS_MODE_INHERIT
	await _test_warden()
	await _test_restart()

	print("=== %s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	get_tree().quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------------------
# GEOMETRY
# ---------------------------------------------------------------------------

func _test_shapes() -> void:
	var c := AtkShape.circle(Vector2.ZERO, 100.0)
	_check("circle inside", c.contains(Vector2(50, 0)))
	_check("circle outside", not c.contains(Vector2(150, 0)))
	_check("circle body overlap", c.overlaps_circle(Vector2(120, 0), 30.0))

	var d := AtkShape.donut(Vector2.ZERO, 80.0, 200.0)
	_check("donut band hit", d.contains(Vector2(120, 0)))
	_check("donut safe hole", not d.contains(Vector2(20, 0)))
	_check("donut outside", not d.contains(Vector2(400, 0)))

	var cone := AtkShape.cone(Vector2.ZERO, Vector2.RIGHT, 200.0, 45.0)
	_check("cone in front", cone.contains(Vector2(100, 0)))
	_check("cone in arc edge", cone.contains(Vector2(100, 90)))
	_check("cone behind", not cone.contains(Vector2(-100, 0)))
	_check("cone out of range", not cone.contains(Vector2(300, 0)))
	_check("cone apex overlap", cone.overlaps_circle(Vector2(-5, 0), 20.0))

	var r := AtkShape.rect(Vector2.ZERO, Vector2.RIGHT, 200.0, 50.0)
	_check("rect inside", r.contains(Vector2(100, 30)))
	_check("rect past end", not r.contains(Vector2(250, 0)))
	_check("rect too wide", not r.contains(Vector2(100, 80)))
	_check("rect body clips edge", r.overlaps_circle(Vector2(100, 70), 30.0))


func _test_view() -> void:
	var w := Vector2(400.0, 900.0)
	var s := View.to_screen(w)
	_check("view squashes depth only", is_equal_approx(s.x, w.x) and s.y < w.y)
	_check("view round-trips", View.to_world(s).is_equal_approx(w))
	_check("arena clamp keeps inside", Actor.in_arena(
		Actor.clamp_to_arena(Tune.ARENA_CENTER + Vector2(9999, 9999))))


## Godot resolves z_index relative to the parent unless z_as_relative is off,
## so the number on a node is not the number it draws at. This walks the chain
## the same way the renderer does.
func _effective_z(ci: CanvasItem) -> int:
	var z := ci.z_index
	if ci.z_as_relative:
		var parent := ci.get_parent()
		if parent is CanvasItem:
			z += _effective_z(parent as CanvasItem)
	return z


## Regression: the ground layer once sat below the backdrop because the root
## carried a low z_index that dragged its children down with it, so every AoE
## indicator was painted underneath the floor.
func _test_layers() -> void:
	var back := _effective_z(arena.backdrop)
	var ground := _effective_z(arena.ground)
	var actors := _effective_z(arena.actors)
	var tg := Telegraph.spawn(AtkShape.circle(Tune.ARENA_CENTER, 50.0), 5.0, 0.05, Color.RED)
	var tele := _effective_z(tg)
	print("--- effective z: backdrop %d, ground %d, telegraph %d, actors %d"
		% [back, ground, tele, actors])
	_check("ground draws above the backdrop", ground > back)
	_check("telegraphs draw above the floor", tele > back)
	_check("actors draw above telegraphs", actors > tele)
	tg.queue_free()


# ---------------------------------------------------------------------------
# PLAYER
# ---------------------------------------------------------------------------

func _test_player() -> void:
	print("--- auto attack: one press, one shot")
	player.world_pos = warden.world_pos + Vector2(0, 200)
	_aim_at_boss()
	player._begin_action(Tune.AUTO_ACTION)
	_check("auto entered a short action", player.state == Player.State.ACTING)
	await _sleep(0.8)
	_check("auto dealt damage", _taken() > 0.0)
	_check("auto charged overheat", player.identity > 0.0)
	var after_one := _taken()
	_check("one press produced exactly one hit",
		is_equal_approx(after_one, float(Tune.AUTO["damage"])))

	print("--- instants")
	_check("skill 1 is instant", Tune.cast_time(0, player.variant_idx) == 0.0)
	_check("skill 2 is instant", Tune.cast_time(1, player.variant_idx) == 0.0)
	_aim_at_boss()
	player._begin_action(0)
	_check("instant did not enter a cast", player.state != Player.State.ACTING)
	_check("rain went on cooldown", player.cooldowns[0] > 0.0)

	# The rain must arrive SPREAD OVER its duration, not all on one frame.
	var rain_start := _taken()
	await _sleep(1.2)
	var rain_mid := _taken()
	await _sleep(2.0)
	var rain_end := _taken()
	_check("rain still landing mid-duration", rain_mid > rain_start)
	_check("rain still landing after mid", rain_end > rain_mid)
	print("--- rain: %.0f by mid, %.0f total over %.1fs"
		% [rain_mid - rain_start, rain_end - rain_start, Tune.SKILLS[0]["duration"]])

	_aim_at_boss()
	player._begin_action(1)
	_check("counter is instant too", player.state != Player.State.ACTING)
	await _sleep(0.4)

	print("--- long casts and queuing")
	_aim_at_boss()
	player._begin_action(2)
	_check("long cast entered ACTING", player.is_casting())
	await _sleep(0.3)
	player._buffer(3)
	_check("queue outlives the input buffer", player._buf_time > Tune.INPUT_BUFFER)
	await _sleep(1.4)
	_check("queued cast fired", player.act_idx == 3 or player.cooldowns[3] > 0.0)
	_check("first cast went on cooldown", player.cooldowns[2] > 0.0)
	await _sleep(2.2)

	print("--- dash-cancel")
	player.cooldowns[2] = 0.0
	_aim_at_boss()
	player._begin_action(2)
	await _sleep(0.25)
	_check("is casting before cancel", player.is_casting())
	player._buffer(Tune.SKILL_COUNT)
	await _sleep(0.15)
	_check("dash cancelled the cast", not player.is_casting())
	_check("cancel charged the cooldown", player.cooldowns[2] > 0.0)
	_check("dash spent a charge", player.dash_charges < Tune.DASH_CHARGES)
	_check("i-frames active", player.invuln > 0.0)
	player.god_mode = false
	_check("i-frames avoided a hit", not player.take_hit(100.0, "TEST"))
	await _sleep(0.5)
	_check("hit lands once i-frames expire", player.take_hit(100.0, "TEST"))
	player.god_mode = true

	print("--- overheat")
	player.identity = Tune.IDENTITY_MAX
	player.cooldowns[3] = 20.0
	_check("overheat activates at full", player._try_overheat())
	_check("overheat reset cooldowns", player.cooldowns[3] == 0.0)
	_check("overheat consumed the meter", player.identity == 0.0)
	_check("overheat shortens casts",
		Tune.cast_time(2, player.variant_idx, true) < Tune.cast_time(2, player.variant_idx, false))
	_check("overheat raises damage",
		Tune.damage_mult(2, player.variant_idx, true) > Tune.damage_mult(2, player.variant_idx, false))
	_check("cannot re-activate mid-window", not player._try_overheat())

	print("--- variants")
	player._toggle_variant()
	_check("variant switched", player.variant_idx == Tune.VARIANT_FLOW)
	_check("flow shortens casts",
		Tune.cast_time(2, Tune.VARIANT_FLOW) < Tune.cast_time(2, Tune.VARIANT_COMMIT))
	_check("flow lowers cast damage",
		Tune.damage_mult(2, Tune.VARIANT_FLOW) < Tune.damage_mult(2, Tune.VARIANT_COMMIT))
	_check("variant does not touch instants",
		is_equal_approx(Tune.damage_mult(0, Tune.VARIANT_FLOW), Tune.damage_mult(0, Tune.VARIANT_COMMIT)))
	_check("variant does not touch autos",
		is_equal_approx(Tune.damage_mult(Tune.AUTO_ACTION, Tune.VARIANT_FLOW),
			Tune.damage_mult(Tune.AUTO_ACTION, Tune.VARIANT_COMMIT)))
	player._toggle_variant()

	print("--- multi-hit telegraph")
	var tg := Telegraph.spawn(AtkShape.circle(warden.world_pos, 120.0), 0.1, 0.05, Color.RED)
	tg.hits = 4
	tg.hit_interval = 0.15
	set_meta("pulses", 0)
	tg.activated.connect(func(_s: AtkShape, _x: Telegraph) -> void:
		set_meta("pulses", int(get_meta("pulses")) + 1))
	await _sleep(1.2)
	_check("telegraph pulsed 4 times", int(get_meta("pulses")) == 4)
	_check("telegraph cleaned itself up", arena.telegraphs().is_empty())


# ---------------------------------------------------------------------------
# WARDEN
# ---------------------------------------------------------------------------

## Wait until the boss leaves PATTERN, or give up.
func _await_pattern_end(timeout: float) -> bool:
	var t := 0.0
	while warden.state == Warden.State.PATTERN and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	return warden.state != Warden.State.PATTERN


func _test_warden() -> void:
	print("--- warden fsm")
	player.god_mode = true
	warden.reset()
	_check("warden starts alive", warden.is_alive())
	_check("warden starts idle", warden.state == Warden.State.IDLE)
	_check("pool holds the phase-1 patterns", warden.pool.size() == Tune.WARDEN_POOL_PHASE1.size())

	# Every pattern must run start to finish and hand the state machine back.
	for i in range(Tune.WARDEN_PATTERNS.size()):
		var nm: String = String(Tune.WARDEN_PATTERNS[i]["name"])
		warden.force_pattern(i)
		_check("%s entered" % nm,
			warden.state == Warden.State.PATTERN and warden.current_pattern == i)
		await _sleep(0.35)
		var showing := arena.telegraphs().size() > 0
		_check("%s telegraphed" % nm, showing)
		var ended := await _await_pattern_end(8.0)
		_check("%s completed and released the fsm" % nm, ended)
		await _sleep(0.1)

	print("--- interruption (run token)")
	warden.force_pattern(Tune.P_CLEAVE)
	await _sleep(0.2)
	var live := arena.telegraphs()
	_check("cleave produced a telegraph", live.size() > 0)
	set_meta("aborted_fired", 0)
	for t in live:
		t.activated.connect(func(_s: AtkShape, _x: Telegraph) -> void:
			set_meta("aborted_fired", int(get_meta("aborted_fired")) + 1))
	# Cut it off well before its wind-up would have completed.
	warden.force_pattern(Tune.P_TRIPLE)
	_check("forcing a pattern switches immediately", warden.current_pattern == Tune.P_TRIPLE)
	await _sleep(2.0)
	_check("aborted telegraph never went live", int(get_meta("aborted_fired")) == 0)
	warden._abort()
	warden._enter_idle()
	await _sleep(0.2)
	_check("abort cleared the telegraphs", arena.telegraphs().is_empty())

	print("--- patterns damage the player")
	player.god_mode = false
	player.invuln = 0.0
	player.hp = Tune.PLAYER_MAX_HP
	# Stand right on top of it: PULSE is the point-blank, so this must hurt.
	player.world_pos = warden.world_pos + Vector2(30, 0)
	warden.force_pattern(Tune.P_PULSE)
	await _await_pattern_end(8.0)
	_check("standing in PULSE cost health", player.hp < Tune.PLAYER_MAX_HP)

	# RING is the inverse: melee range is the SAFE spot.
	player.hp = Tune.PLAYER_MAX_HP
	player.invuln = 0.0
	player.world_pos = warden.world_pos + Vector2(30, 0)
	warden.force_pattern(Tune.P_RING)
	await _await_pattern_end(8.0)
	_check("melee range is safe from RING", is_equal_approx(player.hp, Tune.PLAYER_MAX_HP))
	player.god_mode = true

	print("--- death")
	warden._abort()
	warden._enter_idle()
	warden.hp = 10.0
	warden.apply_hit(999.0, 0.0, Tune.AUTO_ACTION, false)
	_check("warden died at 0 hp", warden.state == Warden.State.DEAD)
	_check("warden reports not alive", not warden.is_alive())
	warden.force_pattern(Tune.P_CLEAVE)
	_check("a dead warden refuses to attack", warden.state == Warden.State.DEAD)


func _test_restart() -> void:
	print("--- restart")
	arena.restart()
	await _sleep(0.2)
	_check("restart reset player hp", is_equal_approx(player.hp, Tune.PLAYER_MAX_HP))
	_check("restart reset cooldowns", player.cooldowns[2] == 0.0)
	_check("restart reset dash", player.dash_charges == Tune.DASH_CHARGES)
	_check("restart reset overheat", player.identity == 0.0 and player.overheat == 0.0)
	_check("restart revived the warden", warden.is_alive() and is_equal_approx(warden.hp, warden.max_hp))
	_check("restart cleared telegraphs", arena.telegraphs().is_empty())
	_check("hostile registry intact", Hostile.all().size() == 1)
