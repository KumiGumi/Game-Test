extends Node
## Headless DPS bench. Answers "is WARDEN_MAX_HP in the right ballpark for the
## enrage timer?" without playing the fight.
##
##   godot --headless --path . tests/dps_sim.tscn --quit-after 40000
##
## Runs a simple priority rotation against a parked boss for SIM_SECONDS and
## reports sustained DPS and the implied time-to-kill. It is NOT a skill test -
## a real player weaves better than this - so treat the number as a floor.

const SIM_SECONDS := 60.0
## Priority order, highest first. -1 is the auto attack (the filler).
const ROTATION := [3, 2, 0, 1, Tune.AUTO_ACTION]

var arena: Arena
var player: Player
var warden: Warden
var t := 0.0
var done := false


func _ready() -> void:
	var ps := load("res://scenes/main.tscn") as PackedScene
	arena = ps.instantiate() as Arena
	add_child(arena)
	player = arena.player
	warden = arena.warden

	# Park the boss: this measures the player's ceiling, not dodging uptime.
	warden.process_mode = Node.PROCESS_MODE_DISABLED
	warden.max_hp = 1.0e12
	warden.hp = warden.max_hp
	player.god_mode = true
	player.aim_override_active = true
	player.world_pos = warden.world_pos + Vector2(0.0, 210.0)

	print("simulating %.0fs of rotation..." % SIM_SECONDS)


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	player.aim_override = warden.world_pos

	if t >= SIM_SECONDS:
		done = true
		_report()
		get_tree().quit()
		return

	# Use Overheat the moment it is available - it is a throughput cooldown,
	# and holding it is a loss unless a phase is imminent.
	if player.identity >= Tune.IDENTITY_MAX and not player.is_overheated():
		player._try_overheat()

	if player.state == Player.State.FREE and player.act_lock <= 0.0:
		for idx in ROTATION:
			if player._ready_to_use(idx):
				player._begin_action(idx)
				break


func _report() -> void:
	var dealt: float = warden.max_hp - warden.hp
	var dps := dealt / SIM_SECONDS
	print("")
	print("=== DPS BENCH ===")
	print("  total damage   %12.0f over %.0fs" % [dealt, SIM_SECONDS])
	print("  sustained DPS  %12.0f" % dps)
	print("")
	print("  WARDEN_MAX_HP  %12.0f" % Tune.WARDEN_MAX_HP)
	print("  time to kill   %12.1fs  (%.2f min)" % [Tune.WARDEN_MAX_HP / dps, Tune.WARDEN_MAX_HP / dps / 60.0])
	print("")
	# Step 4 puts the enrage at 4 minutes; size the boss against that.
	for minutes in [3.0, 3.5, 4.0]:
		print("  HP for a %.1f min kill: %.0f" % [minutes, dps * minutes * 60.0])
