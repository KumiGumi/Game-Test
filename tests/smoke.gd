extends Node
## TEMPORARY headless smoke harness. Deleted after use - not part of the build.

var arena: Arena
var player: Player
var dummy: Dummy
var t := 0.0
var step := 0
var fails := 0


func _ready() -> void:
	_test_shapes()
	var ps := load("res://scenes/main.tscn") as PackedScene
	arena = ps.instantiate() as Arena
	add_child(arena)
	player = arena.player
	dummy = arena.dummy
	print("--- boot ok, player at %s, dummy at %s" % [player.global_position, dummy.global_position])


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


func _aim_at_dummy() -> void:
	player.cast_aim = (dummy.global_position - player.global_position).normalized()
	player.facing = player.cast_aim


func _process(delta: float) -> void:
	t += delta
	arena.hud.elapsed = t

	match step:
		0:
			if t > 0.3:
				print("--- casting every skill, COMMIT")
				player._begin_cast(0)
				_aim_at_dummy()
				step = 1
		1:
			if player.state == Player.State.CASTING:
				_aim_at_dummy()
			elif t > 1.5:
				player._begin_cast(2)
				_aim_at_dummy()
				step = 2
		2:
			if player.state == Player.State.CASTING:
				_aim_at_dummy()
			elif t > 3.4:
				player._begin_cast(4)   # rect / stagger
				_aim_at_dummy()
				step = 3
		3:
			if t > 4.8:
				_check("bolts + rect dealt damage", dummy.total_taken > 0.0)
				_check("stagger applied", dummy.stagger > 0.0)
				print("--- damage so far: %.0f, stagger %.0f" % [dummy.total_taken, dummy.stagger])
				print("--- testing AoE shape resolution")
				player._resolve_shape(AtkShape.circle(dummy.global_position, 120.0), 50.0, 10.0, 1, false)
				step = 4
		4:
			if t > 5.0:
				print("--- testing dash-cancel")
				player._begin_cast(2)  # long nuke
				step = 5
		5:
			if t > 5.3:
				_check("is casting before cancel", player.state == Player.State.CASTING)
				player._buffer(Tune.SKILL_COUNT - 1)  # dash input
				step = 6
		6:
			if t > 5.5:
				_check("dash cancelled the cast", player.state != Player.State.CASTING)
				_check("cancel charged the cooldown", player.cooldowns[2] > 0.0)
				_check("dash spent a charge", player.dash_charges < Tune.DASH_CHARGES)
				_check("i-frames active after dash", player.invuln > 0.0)
				print("--- testing player damage + i-frame avoidance")
				var took := player.take_hit(100.0, "TEST")
				_check("i-frames avoided the hit", not took)
				step = 7
		7:
			if t > 6.2:
				var took2 := player.take_hit(100.0, "TEST")
				_check("hit lands once i-frames expire", took2)
				_check("player hp dropped", player.hp < Tune.PLAYER_MAX_HP)
				print("--- switching to FLOW")
				player._toggle_variant()
				_check("variant switched", player.variant_idx == Tune.VARIANT_FLOW)
				player._begin_cast(0)
				_aim_at_dummy()
				step = 8
		8:
			if t > 7.0:
				_check("flow cast is shorter", Tune.cast_time(0, Tune.VARIANT_FLOW) < Tune.cast_time(0, Tune.VARIANT_COMMIT))
				_check("flow damage is lower", Tune.damage(0, Tune.VARIANT_FLOW) < Tune.damage(0, Tune.VARIANT_COMMIT))
				print("--- telegraph lifecycle")
				var tg := Telegraph.spawn(arena.world, AtkShape.cone(dummy.global_position, Vector2.UP, 200.0, 40.0), 0.4, 0.1, Color.RED)
				tg.activated.connect(func(_s: AtkShape, _x: Telegraph) -> void: print("--- telegraph went live"))
				step = 9
		9:
			if t > 7.9:
				var live := arena.telegraphs().size()
				print("--- live telegraphs after expiry: %d" % live)
				print("--- restart")
				arena.restart()
				step = 10
		10:
			if t > 8.3:
				_check("restart reset hp", is_equal_approx(player.hp, Tune.PLAYER_MAX_HP))
				_check("restart reset cooldowns", player.cooldowns[2] == 0.0)
				_check("restart reset dash", player.dash_charges == Tune.DASH_CHARGES)
				_check("restart reset target", dummy.total_taken == 0.0)
				_check("hostile registry intact", Hostile.all().size() == 1)
				print("=== %s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
				step = 11
		11:
			get_tree().quit(1 if fails > 0 else 0)
