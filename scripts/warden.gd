class_name Warden
extends Hostile
## The boss.
##
## OUTER FSM (driven by _process, plain timers):
##
##   IDLE -> REPOSITION -> PATTERN -> RECOVER -> IDLE
##                            ^
##                    STUNNED / DEAD can cut in at any point
##
## IDLE and RECOVER are the beats that let the fight breathe; REPOSITION stops
## it becoming a static turret check.
##
## PATTERNS (coroutines). Attack choreography reads as a script - wind up, fire,
## pause, fire again - and is miserable as a step table, so each pattern is an
## `await`-driven function. The hard part of that approach is interruption, and
## it's solved with a RUN TOKEN: every abort bumps `_run_token`, and every wait
## site checks it, so a pattern dies within one frame of being cancelled by a
## counter stun, a phase change, or the debug force-pattern key. Any telegraph a
## dying pattern left behind is cancelled with it.
##
## Nothing here knows how damage is drawn or how a shape is tested - patterns
## build an AtkShape, hand it to a Telegraph, and connect to `activated`.

enum State { IDLE, REPOSITION, PATTERN, RECOVER, STUNNED, DEAD }

static var instance: Warden

var max_hp: float = Tune.WARDEN_MAX_HP
var hp: float = Tune.WARDEN_MAX_HP
var stagger: float = 0.0
var phase: int = 1

var state: State = State.IDLE
## Seconds in the current state - the debug readout wants this.
var state_time: float = 0.0
## Index into Tune.WARDEN_PATTERNS, or -1 when not attacking.
var current_pattern: int = -1

var pool: Array[int] = []

var _timer: float = 0.0
var _run_token: int = 0
var _live: Array[Telegraph] = []
var _last_pattern: int = -1
var _reposition_to: Vector2 = Vector2.ZERO
var _stagger_hold: float = 0.0
var _hit_flash: float = 0.0
var _font: Font

# --- counter window (pattern 6) ---
var counter_open: bool = false
## The facing a counter must land within, and how wide that arc is.
var counter_facing: Vector2 = Vector2.RIGHT
var counter_arc: float = 85.0
var _was_countered: bool = false

# --- stagger check (pattern 7) ---
var stagger_check: bool = false
var stagger_required: float = 0.0
var stagger_left: float = 0.0


func _ready() -> void:
	super._ready()
	instance = self
	body_radius = Tune.WARDEN_RADIUS
	height = Tune.WARDEN_HEIGHT
	_font = ThemeDB.fallback_font
	pool.assign(Tune.WARDEN_POOL_PHASE1)
	_enter_idle()


func _exit_tree() -> void:
	super._exit_tree()
	if instance == self:
		instance = null


func state_name() -> String:
	return ["IDLE", "REPOSITION", "PATTERN", "RECOVER", "STUNNED", "DEAD"][state]


func pattern_name() -> String:
	if current_pattern < 0:
		return "-"
	return String(Tune.WARDEN_PATTERNS[current_pattern]["name"])


func is_alive() -> bool:
	return state != State.DEAD


func counter_window_open() -> bool:
	return counter_open


## The window is only on his FRONT. Standing behind him during the charge
## wind-up is safe but useless - the counter demands you run into his face,
## which is the most committal movement the fight asks for.
func counter_reachable_from(from: Vector2) -> bool:
	if not counter_open:
		return false
	var to := from - world_pos
	if to.length_squared() < 1.0:
		return true
	return absf(to.angle_to(counter_facing)) <= deg_to_rad(counter_arc)


func on_countered(stun_time: float) -> void:
	if state == State.DEAD:
		return
	_was_countered = true
	_set_counter_window(false)
	_abort()
	_set_state(State.STUNNED)
	_timer = stun_time
	current_pattern = -1


func _set_counter_window(open: bool) -> void:
	if counter_open == open:
		return
	counter_open = open
	Events.counter_window_changed.emit(open)


# ---------------------------------------------------------------------------
# OUTER FSM
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	state_time += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 7.0)

	# A check's bar never decays - the timer is the pressure, not leakage.
	if not stagger_check:
		if _stagger_hold > 0.0:
			_stagger_hold -= delta
		elif stagger > 0.0:
			stagger = maxf(0.0, stagger - Tune.WARDEN_STAGGER_DECAY * delta)

	match state:
		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				if randf() < Tune.WARDEN_REPOSITION_CHANCE:
					_enter_reposition()
				else:
					_enter_pattern()

		State.REPOSITION:
			_timer -= delta
			var to := _reposition_to - world_pos
			if to.length() > 8.0:
				world_pos += to.normalized() * Tune.WARDEN_MOVE_SPEED * delta
				world_pos = Actor.clamp_to_arena(world_pos)
			if _timer <= 0.0 or to.length() <= 8.0:
				_enter_pattern()

		State.PATTERN:
			pass  # the coroutine owns this state and exits it when done

		State.RECOVER, State.STUNNED:
			_timer -= delta
			if _timer <= 0.0:
				_enter_idle()

		State.DEAD:
			pass

	sync_view()
	queue_redraw()


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0


func _enter_idle() -> void:
	current_pattern = -1
	_set_state(State.IDLE)
	_timer = randf_range(Tune.WARDEN_IDLE_MIN, Tune.WARDEN_IDLE_MAX)


func _enter_reposition() -> void:
	_set_state(State.REPOSITION)
	_timer = Tune.WARDEN_REPOSITION_MAX_TIME
	var p := Player.instance
	var anchor := p.world_pos if p != null and is_instance_valid(p) else Tune.ARENA_CENTER
	var ang := randf() * TAU
	_reposition_to = Actor.clamp_to_arena(anchor + Vector2.from_angle(ang) * Tune.WARDEN_PREFERRED_DISTANCE)


func _enter_recover() -> void:
	current_pattern = -1
	_set_state(State.RECOVER)
	_timer = randf_range(Tune.WARDEN_RECOVER_MIN, Tune.WARDEN_RECOVER_MAX)


## Start a pattern. Pass an index to force one (debug), or -1 to roll.
func _enter_pattern(forced: int = -1) -> void:
	if state == State.DEAD:
		return
	var idx := forced if forced >= 0 else _pick_pattern()
	if idx < 0 or idx >= Tune.WARDEN_PATTERNS.size():
		_enter_idle()
		return
	_abort()
	current_pattern = idx
	_last_pattern = idx
	_set_state(State.PATTERN)
	Events.warden_pattern_started.emit(idx, String(Tune.WARDEN_PATTERNS[idx]["name"]))
	_run_pattern(idx, _run_token)


## Debug entry point: interrupt whatever is happening and run pattern N now.
func force_pattern(idx: int) -> void:
	if state == State.DEAD or idx < 0 or idx >= Tune.WARDEN_PATTERNS.size():
		return
	_enter_pattern(idx)


func _pick_pattern() -> int:
	if pool.is_empty():
		return -1
	if Tune.WARDEN_AVOID_REPEATS and pool.size() > 1:
		for _attempt in range(6):
			var candidate: int = pool[randi() % pool.size()]
			if candidate != _last_pattern:
				return candidate
	return pool[randi() % pool.size()]


# ---------------------------------------------------------------------------
# INTERRUPTION
# ---------------------------------------------------------------------------

## Kill the running pattern and everything it spawned, within one frame.
func _abort() -> void:
	_run_token += 1
	_set_counter_window(false)
	stagger_check = false
	for tg in _live:
		if is_instance_valid(tg):
			tg.cancel()
	_live.clear()


## Wait, but bail the instant the pattern is invalidated. Every await site in
## every pattern goes through here, which is what makes interruption reliable
## rather than something each pattern has to remember to handle.
func _wait(seconds: float, token: int) -> bool:
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		if not is_inside_tree() or token != _run_token or state == State.DEAD:
			return false
		left -= get_process_delta_time()
	return true


## Glide between two world points over `seconds`, abortable.
func _move_over(from: Vector2, to: Vector2, seconds: float, token: int) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		if not is_inside_tree() or token != _run_token or state == State.DEAD:
			return false
		elapsed += get_process_delta_time()
		world_pos = Actor.clamp_to_arena(from.lerp(to, clampf(elapsed / seconds, 0.0, 1.0)))
	return true


# ---------------------------------------------------------------------------
# PATTERN PLUMBING
# ---------------------------------------------------------------------------

func _windup(base: float) -> float:
	return base * Tune.WARDEN_WINDUP_SCALE


## Spawn a telegraph and track it, so an abort can take it down with the pattern.
func _tele(shape: AtkShape, windup: float, active: float, tint: Color = Tune.COL_TELEGRAPH) -> Telegraph:
	var tg := Telegraph.spawn(shape, windup, active, tint)
	_live.append(tg)
	tg.expired.connect(func(t: Telegraph) -> void: _live.erase(t))
	return tg


## Resolve one shape against the player. The mirror of what the player's skills
## do to hostiles, using the same AtkShape test.
func _strike(shape: AtkShape, damage: float, label: String, knock: float = 0.0) -> void:
	var p := Player.instance
	if p == null or not is_instance_valid(p):
		return
	if shape.overlaps_circle(p.world_pos, p.body_radius):
		# Knockback pushes away from the shape's origin, not the boss's body -
		# a cross arm should shove you out of the arm you were standing in.
		p.take_hit(damage, label, shape.origin, knock)


func _to_player() -> Vector2:
	var p := Player.instance
	if p == null or not is_instance_valid(p):
		return Vector2.RIGHT
	var d := p.world_pos - world_pos
	return d.normalized() if d.length_squared() > 1.0 else Vector2.RIGHT


func _run_pattern(idx: int, token: int) -> void:
	match idx:
		Tune.P_CLEAVE:
			await _p_cleave(token)
		Tune.P_PULSE:
			await _p_pulse(token)
		Tune.P_RING:
			await _p_ring(token)
		Tune.P_LANCE:
			await _p_lance(token)
		Tune.P_CROSS:
			await _p_cross(token)
		Tune.P_TRIPLE:
			await _p_triple(token)
		Tune.P_COUNTER:
			await _p_counter_charge(token)
		Tune.P_STAGGER:
			await _p_stagger_check(token)

	# Only the pattern that is still current gets to end the state. An aborted
	# one must not drag the boss out of the STUNNED it was interrupted into.
	if token == _run_token and state == State.PATTERN:
		_enter_recover()


# ---------------------------------------------------------------------------
# PATTERNS 1-5
# ---------------------------------------------------------------------------

## 1. Frontal cone. Tracks the player for the first part of the wind-up, then
## commits - so the read isn't "where is it", it's "when does it stop following".
func _p_cleave(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_CLEAVE]
	var windup := _windup(float(p["windup"]))
	var shape := AtkShape.cone(world_pos, _to_player(), float(p["radius"]), float(p["half_angle"]))
	var tg := _tele(shape, windup, float(p["active"]))
	tg.anchor = self
	tg.lock_at = float(p["track_until"])
	var track: float = float(p["track_until"])
	tg.update_hook = func(t: Telegraph, prog: float) -> void:
		if prog < track:
			t.shape.dir = _to_player()
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_strike(sh, float(p["damage"]), "CLEAVE", float(p["knockback"]))
		Events.shake_requested.emit(5.0)
	)
	await _wait(windup + float(p["active"]) + 0.05, token)


## 2. Point-blank. Safe zone is OUTSIDE - get out.
func _p_pulse(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_PULSE]
	var windup := _windup(float(p["windup"]))
	var tg := _tele(AtkShape.circle(world_pos, float(p["radius"])), windup, float(p["active"]))
	tg.anchor = self
	tg.lock_at = 1.0  # stays glued to the boss, so it can't be outrun by its drift
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_strike(sh, float(p["damage"]), "PULSE", float(p["knockback"]))
		FxRing.ground_pop(sh.origin, body_radius, sh.radius * 1.15, Tune.COL_TELEGRAPH, 0.40)
		Events.shake_requested.emit(7.0)
	)
	await _wait(windup + float(p["active"]) + 0.05, token)


## 3. Ranged ring - the exact inverse of PULSE. Safe zone is AT MELEE, so the
## correct answer is to run TOWARD the thing winding up. Pairing 2 and 3 in one
## pool is what stops "always stay at range" from being a strategy.
func _p_ring(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_RING]
	var windup := _windup(float(p["windup"]))
	var tg := _tele(AtkShape.donut(world_pos, float(p["inner"]), float(p["outer"])),
		windup, float(p["active"]), Tune.COL_TELEGRAPH_ALT)
	tg.anchor = self
	tg.lock_at = 1.0
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_strike(sh, float(p["damage"]), "RING", float(p["knockback"]))
		FxRing.ground_pop(sh.origin, sh.inner_radius, sh.inner_radius * 0.4, Tune.COL_TELEGRAPH_ALT, 0.35)
		Events.shake_requested.emit(7.0)
	)
	await _wait(windup + float(p["active"]) + 0.05, token)


## 4. Dash along a telegraphed lane. Multi-hit, so the lane is lethal for the
## whole dash rather than only on the frame it goes live - standing just behind
## the boss and walking in after the flash should not be free.
func _p_lance(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_LANCE]
	var windup := _windup(float(p["windup"]))
	var dir := _to_player()
	var start := world_pos
	var length := float(p["length"])
	var dash_time := float(p["dash_time"])
	var hits := int(p["hits"])

	var tg := _tele(AtkShape.rect(start, dir, length, float(p["half_width"])),
		windup, float(p["active"]), Tune.COL_TELEGRAPH)
	tg.hits = hits
	tg.hit_interval = dash_time / float(maxi(hits, 1))
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_strike(sh, float(p["damage"]), "LANCE", float(p["knockback"]))
	)

	if not await _wait(windup, token):
		return
	Events.shake_requested.emit(6.0)
	var target := Actor.clamp_to_arena(start + dir * length)
	if not await _move_over(start, target, dash_time, token):
		return
	await _wait(0.1, token)


## 5. Axe slam into an X of shockwaves. Every arm starts at the boss, so melee
## range is inside all four of them - the answer is to be out in a gap, which is
## the exact inverse of RING and the reason both are in the pool.
func _p_cross(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_CROSS]
	var windup := _windup(float(p["windup"]))
	var arms := int(p["arms"])
	var aim := _to_player()
	var base := aim.angle() + deg_to_rad(float(p["arm_offset"]))
	# The axe comes down in FRONT of him and the cross radiates from the impact,
	# so the safe gaps sit around that point rather than around his body.
	var impact := Actor.clamp_to_arena(world_pos + aim * float(p["impact_offset"]))

	for i in range(arms):
		var a := base + TAU * float(i) / float(maxi(arms, 1))
		var shape := AtkShape.rect(impact, Vector2.from_angle(a),
			float(p["length"]), float(p["half_width"]))
		var tg := _tele(shape, windup, float(p["active"]))
		tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
			_strike(sh, float(p["damage"]), "CROSS", float(p["knockback"]))
		)

	if not await _wait(windup, token):
		return
	FxRing.ground_pop(impact, 20.0, 280.0, Tune.COL_TELEGRAPH, 0.45)
	Events.shake_requested.emit(9.0)
	await _wait(float(p["active"]) + 0.05, token)


## 6. Three swings: front, behind, front. One pattern with three beats, so it is
## answered by moving twice rather than standing still once - and the second
## swing is aimed at whoever rolled straight through the first.
func _p_triple(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_TRIPLE]
	var swings := int(p["swings"])
	var facing := _to_player()
	var retarget: bool = bool(p["retarget_each"])

	for i in range(swings):
		var windup := _windup(float(p["windup"]) if i == 0 else float(p["windup_rest"]))
		if retarget:
			facing = _to_player()
		# Alternate front / behind / front.
		var dir := facing if i % 2 == 0 else -facing
		var shape := AtkShape.cone(world_pos, dir, float(p["radius"]), float(p["half_angle"]))
		var tg := _tele(shape, windup, float(p["active"]),
			Tune.COL_TELEGRAPH if i % 2 == 0 else Tune.COL_TELEGRAPH_ALT)
		tg.anchor = self
		tg.lock_at = 1.0
		tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
			_strike(sh, float(p["damage"]), "SWING", float(p["knockback"]))
			Events.shake_requested.emit(5.0)
		)
		if not await _wait(windup + float(p["active"]) + 0.05, token):
			return


## 7. THE COUNTER. He plants, aims, and slams three times on a fixed beat. The
## window is on the SECOND slam and only from his front, so the answer is to run
## into his face on beat two - the most committal movement in the fight, on a
## rhythm you have to learn. Miss it and the charge hits hard and shoves you a
## long way, which near a broken ledge is the whole point.
func _p_counter_charge(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_COUNTER]
	_was_countered = false

	# He locks on before the first slam and does NOT re-aim: the charge lane is
	# decided early, so reading it is a positioning problem, not a reaction.
	counter_facing = _to_player()
	counter_arc = float(p["counter_front_arc"])
	var aim := counter_facing
	var slams := int(p["slams"])
	var counter_slam := int(p["counter_on_slam"])

	for i in range(slams):
		var windup := _windup(float(p["windup"]))
		var at := Actor.clamp_to_arena(world_pos + aim * float(p["slam_offset"]))
		var tg := _tele(AtkShape.circle(at, float(p["slam_radius"])), windup, float(p["active"]),
			Tune.COL_COUNTER if i == counter_slam else Tune.COL_TELEGRAPH)
		tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
			_strike(sh, float(p["slam_damage"]), "SLAM", float(p["slam_knockback"]))
			Events.shake_requested.emit(6.0)
		)

		if not await _wait(windup, token):
			return

		# The window opens as the counterable slam LANDS, not while it winds up:
		# you have to commit to being in his face before you know it's safe.
		if i == counter_slam:
			_set_counter_window(true)
			FxRing.ground_pop(world_pos, body_radius, body_radius + 190.0, Tune.COL_COUNTER, 0.5)
			var ok := await _wait(float(p["counter_window"]), token)
			_set_counter_window(false)
			if not ok:
				return  # countered: on_countered aborted us
		elif not await _wait(float(p["active"]) + float(p["slam_gap"]), token):
			return

	# Not countered - the charge goes off.
	var charge_windup := _windup(float(p["charge_windup"]))
	var start := world_pos
	var lane := _tele(AtkShape.rect(start, aim, float(p["charge_length"]),
		float(p["charge_half_width"])), charge_windup, float(p["active"]))
	lane.hits = 4
	lane.hit_interval = float(p["charge_time"]) / 4.0
	lane.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_strike(sh, float(p["charge_damage"]), "CHARGE", float(p["charge_knockback"]))
	)
	if not await _wait(charge_windup, token):
		return
	Events.shake_requested.emit(10.0)
	var target := Actor.clamp_to_arena(start + aim * float(p["charge_length"]))
	if not await _move_over(start, target, float(p["charge_time"]), token):
		return
	await _wait(0.15, token)


## 8. THE STAGGER CHECK. He channels; fill the bar before the timer runs out.
## Fail and the knockback is enormous - on an intact floor that is a big hit, on
## a broken one it is simply death. Tuned to want the big cast, so spending it
## on filler a moment earlier is a real mistake.
func _p_stagger_check(token: int) -> void:
	var p: Dictionary = Tune.WARDEN_PATTERNS[Tune.P_STAGGER]
	var duration := _windup(float(p["windup"]))

	stagger_check = true
	stagger_required = float(p["required"])
	stagger = 0.0
	stagger_left = duration
	Events.stagger_check_started.emit(stagger_required, duration)

	var tg := _tele(AtkShape.circle(world_pos, float(p["radius"])), duration, float(p["active"]),
		Tune.COL_TELEGRAPH)
	tg.anchor = self
	tg.lock_at = 1.0

	# Poll rather than await the whole duration: filling the bar has to end the
	# channel the instant it happens, not when the timer would have expired.
	while stagger_left > 0.0:
		if not await _wait(0.0333, token):
			stagger_check = false
			return
		stagger_left -= 0.0333
		if stagger >= stagger_required:
			_stagger_success(p)
			return

	# Timer ran out.
	stagger_check = false
	tg.cancel()
	Events.stagger_check_ended.emit(false)
	var p2 := Player.instance
	if p2 != null and is_instance_valid(p2):
		p2.take_hit(float(p["fail_damage"]), "OVERBEAR", world_pos, float(p["fail_knockback"]))
	FxRing.ground_pop(world_pos, body_radius, 900.0, Tune.COL_TELEGRAPH, 0.6)
	Events.shake_requested.emit(16.0)
	await _wait(0.4, token)


func _stagger_success(p: Dictionary) -> void:
	stagger_check = false
	stagger = 0.0
	Events.stagger_check_ended.emit(true)
	Floater.spawn(View.to_screen(world_pos) - Vector2(0, height + 80.0),
		"STAGGERED", Color(1, 1, 1), 34, 1.0)
	FxRing.ground_pop(world_pos, body_radius, body_radius + 240.0, Tune.COL_STAGGER, 0.5)
	Events.shake_requested.emit(10.0)
	_abort()
	_set_state(State.STUNNED)
	_timer = float(p["success_stun"])
	current_pattern = -1


# ---------------------------------------------------------------------------
# DAMAGE
# ---------------------------------------------------------------------------

func apply_hit(damage: float, stagger_value: float, action_idx: int, is_counter: bool) -> void:
	if state == State.DEAD:
		return

	if damage > 0.0:
		hp = maxf(0.0, hp - damage)
		_hit_flash = 1.0
		Events.damage_dealt.emit(damage, world_pos, action_idx)
		var col: Color = Tune.action(action_idx)["color"] if action_idx != Tune.NO_ACTION else Color.WHITE
		var at := View.to_screen(world_pos) - Vector2(randf_range(-38, 38), height + randf_range(0, 44))
		Floater.damage(at, damage, col)
		Events.hitstop_requested.emit(
			Tune.HITSTOP_HEAVY if damage >= Tune.HITSTOP_HEAVY_THRESHOLD else Tune.HITSTOP_NORMAL)
		if hp <= 0.0:
			_die()
			return

	if stagger_value > 0.0:
		var cap := stagger_required if stagger_check else Tune.WARDEN_STAGGER_MAX
		stagger = minf(cap, stagger + stagger_value)
		_stagger_hold = Tune.WARDEN_STAGGER_RESET_DELAY
		Events.stagger_dealt.emit(stagger_value, world_pos)

	# Counter windows arrive in step 3; until then a counter is just a hit.
	if is_counter:
		pass


func _die() -> void:
	_abort()
	_set_state(State.DEAD)
	current_pattern = -1
	Floater.spawn(View.to_screen(world_pos) - Vector2(0, height + 80.0), "WARDEN DOWN", Color(1, 1, 1), 40, 1.0)
	FxRing.ground_pop(world_pos, body_radius, body_radius + 320.0, Color(1, 1, 1, 0.8), 0.7)
	Events.shake_requested.emit(14.0)
	Events.warden_defeated.emit()


func reset() -> void:
	_abort()
	_set_counter_window(false)
	stagger_check = false
	stagger_left = 0.0
	_was_countered = false
	hp = Tune.WARDEN_MAX_HP
	stagger = 0.0
	phase = 1
	_last_pattern = -1
	_stagger_hold = 0.0
	pool.assign(Tune.WARDEN_POOL_PHASE1)
	world_pos = Tune.ARENA_CENTER
	sync_view()
	_enter_idle()


# ---------------------------------------------------------------------------
# DRAW
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_shadow(body_radius * 1.05)

	var base: Color = Tune.COL_WARDEN if phase == 1 else Tune.COL_WARDEN_PHASE2
	base = base.lerp(Color.WHITE, _hit_flash * 0.45)
	if state == State.DEAD:
		base = base.darkened(0.6)

	draw_colored_polygon(PackedVector2Array([
		Vector2(-body_radius * 0.44, 0.0),
		Vector2(body_radius * 0.44, 0.0),
		Vector2(body_radius * 0.30, height),
		Vector2(-body_radius * 0.30, height),
	]), base.darkened(0.45))
	draw_circle(Vector2.ZERO, body_radius, base)
	draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.28), 2.0, true)

	if counter_open:
		# Unmissable: the whole point is that you see it and charge in.
		var pulse := 0.5 + 0.5 * sin(state_time * 22.0)
		draw_circle(Vector2.ZERO, body_radius + 6.0 + pulse * 5.0,
			Color(Tune.COL_COUNTER.r, Tune.COL_COUNTER.g, Tune.COL_COUNTER.b, 0.35))
		draw_arc(Vector2.ZERO, body_radius + 12.0, 0.0, TAU, 48, Tune.COL_COUNTER, 4.0, true)
		draw_ground_ring(feet(), body_radius * 2.2, Tune.COL_COUNTER, 3.0)

	if state == State.STUNNED:
		draw_arc(Vector2.ZERO, body_radius + 9.0, 0.0, TAU, 48, Color(1, 1, 0.5, 0.8), 4.0, true)

	# Stagger bar. Idle until step 3 gives it a stagger check to matter for.
	if stagger > 0.0:
		var w := body_radius * 2.2
		var top := Vector2(-w * 0.5, -body_radius - 20.0)
		draw_rect(Rect2(top, Vector2(w, 8.0)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top, Vector2(w * (stagger / Tune.WARDEN_STAGGER_MAX), 8.0)), Tune.COL_STAGGER)
		draw_rect(Rect2(top, Vector2(w, 8.0)), Color(1, 1, 1, 0.22), false, 1.0)
