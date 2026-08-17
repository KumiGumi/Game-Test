extends Node
## Headless smoke harness. Exits non-zero on failure.
##   godot --headless --path . tests/smoke.tscn --quit-after 3000

var arena: Arena
var player: Player
var dummy: Dummy
var t := 0.0
var step := 0
var fails := 0


func _ready() -> void:
	_test_shapes()
	_test_view()
	var ps := load("res://scenes/main.tscn") as PackedScene
	arena = ps.instantiate() as Arena
	add_child(arena)
	player = arena.player
	dummy = arena.dummy
	print("--- boot ok, player world %s, dummy world %s" % [player.world_pos, dummy.world_pos])


func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS  ", name)
	else:
		fails += 1
		printerr("FAIL  ", name)


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


func _aim_at_dummy() -> void:
	# There is no cursor in a headless run, so drive the aim hook directly.
	player.aim_override_active = true
	player.aim_override = dummy.world_pos
	player.act_aim = (dummy.world_pos - player.world_pos).normalized()
	player.act_target = dummy.world_pos
	player.facing = player.act_aim


func _process(delta: float) -> void:
	t += delta
	arena.hud.elapsed = t

	match step:
		0:
			if t > 0.3:
				print("--- auto attack chain")
				_check("chain starts at 0", player.auto_step == 0)
				_aim_at_dummy()
				player._begin_action(Tune.AUTO_ACTION)
				step = 1
		1:
			if player.state == Player.State.ACTING:
				_aim_at_dummy()
			elif t > 0.8:
				_check("chain advanced", player.auto_step == 1)
				_aim_at_dummy()
				player._begin_action(Tune.AUTO_ACTION)
				step = 2
		2:
			if player.state != Player.State.ACTING and t > 1.4:
				player._begin_action(Tune.AUTO_ACTION)   # finisher step
				_aim_at_dummy()
				step = 3
		3:
			if player.state != Player.State.ACTING and t > 2.0:
				_check("chain wrapped after finisher", player.auto_step == 0)
				_check("autos dealt damage", dummy.total_taken > 0.0)
				_check("autos charged overheat", player.identity > 0.0)
				print("--- instants: 1 (rain) and 2 (counter)")
				_check("skill 1 is instant", Tune.cast_time(0, player.variant_idx) == 0.0)
				_check("skill 2 is instant", Tune.cast_time(1, player.variant_idx) == 0.0)
				player.world_pos = dummy.world_pos + Vector2(0, 150)
				_aim_at_dummy()
				player._begin_action(0)
				step = 4
		4:
			if t > 2.05:
				_check("instant did not enter a cast", player.state != Player.State.ACTING)
				_check("rain went on cooldown", player.cooldowns[0] > 0.0)
				set_meta("rain_start", dummy.total_taken)
				step = 5
		5:
			# The rain must arrive SPREAD OVER its duration, not all on one frame.
			# Sampling at three points proves it is still landing later.
			if t > 3.2:
				set_meta("rain_mid", dummy.total_taken)
				step = 6
		6:
			if t > 5.2:
				var a: float = get_meta("rain_start", 0.0)
				var b: float = get_meta("rain_mid", 0.0)
				var c := dummy.total_taken
				_check("rain landed damage", c > a)
				_check("rain still landing mid-duration", b > a)
				_check("rain still landing after mid", c > b)
				print("--- rain: %.0f by mid, %.0f total over %.1fs" % [b - a, c - a, Tune.SKILLS[0]["duration"]])
				_aim_at_dummy()
				player._begin_action(1)  # counter
				step = 7
		7:
			if t > 5.5:
				_check("counter is instant too", player.state != Player.State.ACTING)
				print("--- long casts + queuing")
				_aim_at_dummy()
				player._begin_action(2)
				step = 8
		8:
			if player.state == Player.State.ACTING and t > 5.8:
				# Queue 4 during 3's cast. It must survive to the end of the cast.
				player._buffer(3)
				_check("queue outlives the input buffer",
					player._buf_time > Tune.INPUT_BUFFER)
				step = 9
		9:
			if t > 7.2:
				_check("queued cast started with no gap", player.act_idx == 3 or player.cooldowns[3] > 0.0)
				_check("first cast went on cooldown", player.cooldowns[2] > 0.0)
				step = 10
		10:
			if t > 9.6:
				print("--- dash-cancel")
				player.cooldowns[2] = 0.0
				player._begin_action(2)
				step = 11
		11:
			if t > 9.9:
				_check("is casting before cancel", player.is_casting())
				player._buffer(Tune.SKILL_COUNT)
				step = 12
		12:
			if t > 10.1:
				_check("dash cancelled the cast", not player.is_casting())
				_check("cancel charged the cooldown", player.cooldowns[2] > 0.0)
				_check("dash spent a charge", player.dash_charges < Tune.DASH_CHARGES)
				_check("i-frames active", player.invuln > 0.0)
				_check("i-frames avoided a hit", not player.take_hit(100.0, "TEST"))
				step = 13
		13:
			if t > 10.8:
				_check("hit lands once i-frames expire", player.take_hit(100.0, "TEST"))
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
				step = 14
		14:
			if t > 11.2:
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
				print("--- multi-hit telegraph")
				var tg := Telegraph.spawn(AtkShape.circle(dummy.world_pos, 120.0), 0.1, 0.05, Color.RED)
				tg.hits = 4
				tg.hit_interval = 0.15
				set_meta("pulses", 0)
				tg.activated.connect(func(_s: AtkShape, _x: Telegraph) -> void:
					set_meta("pulses", int(get_meta("pulses")) + 1))
				step = 15
		15:
			if t > 12.4:
				_check("telegraph pulsed 4 times", int(get_meta("pulses")) == 4)
				_check("telegraph cleaned itself up", arena.telegraphs().is_empty())
				print("--- restart")
				arena.restart()
				step = 16
		16:
			if t > 12.8:
				_check("restart reset hp", is_equal_approx(player.hp, Tune.PLAYER_MAX_HP))
				_check("restart reset cooldowns", player.cooldowns[2] == 0.0)
				_check("restart reset dash", player.dash_charges == Tune.DASH_CHARGES)
				_check("restart reset overheat", player.identity == 0.0 and player.overheat == 0.0)
				_check("restart reset target", dummy.total_taken == 0.0)
				_check("hostile registry intact", Hostile.all().size() == 1)
				print("=== %s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
				step = 17
		17:
			get_tree().quit(1 if fails > 0 else 0)
