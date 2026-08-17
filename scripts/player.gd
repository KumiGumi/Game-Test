class_name Player
extends Actor
## Movement, the dash, the auto attack, four skills, and Overheat.
##
## The action economy is the point of this file:
##
##   RMB   auto attack   - 3-step chain, no cooldown, holdable. Fills the gaps
##                         so the hands are never idle, and charges Overheat.
##   1 / 2 instants      - low cooldown, usable as filler. 1 is multi-hit,
##                         2 is the counter (a counter you have to CAST is not
##                         a counter, so it must be instant).
##   3 / 4 long casts    - the commitment. Queue 4 during 3 and they chain with
##                         no gap; that chain is the signature of the build.
##   F     Overheat      - convert a full meter into a burst window.
##
## States are FREE / ACTING / DASHING. ACTING covers autos, instants and casts
## alike - they differ only in how long they hold you and what they cost to
## break out of.

enum State { FREE, ACTING, DASHING }

var state: State = State.FREE
var variant_idx: int = Tune.START_VARIANT

var hp: float = Tune.PLAYER_MAX_HP
var god_mode: bool = false
var invuln: float = 0.0

## World-space velocity.
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT

## Blocks all actions. Recovery and dash end-lag both write here.
var act_lock: float = 0.0

var cooldowns: PackedFloat32Array = PackedFloat32Array()
var dash_charges: int = Tune.DASH_CHARGES
var dash_recharge: float = 0.0

# --- current action ---
var act_idx: int = Tune.NO_ACTION
var act_elapsed: float = 0.0
var act_total: float = 0.0
var act_aim: Vector2 = Vector2.RIGHT
## Ground point the action is aimed AT, for placed skills (rain, meteor).
## Captured at cast start and frozen under COMMIT - a meteor must land where you
## committed it, not where the cursor drifted to during the 1.8s cast.
var act_target: Vector2 = Vector2.ZERO
## Variant captured when the action STARTED, so a mid-cast TAB can't rewrite
## what you already committed to.
var act_variant: int = 0
## Overheat state captured at start, for the same reason.
var act_overheated: bool = false

# --- auto attack chain ---
var auto_step: int = 0
var _auto_chain_timer: float = 0.0

# --- Overheat (identity) ---
var identity: float = 0.0
var overheat: float = 0.0

# --- dash ---
var _dash_time: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _dash_trail: float = 0.0

# --- input ---
var _move_input: Vector2 = Vector2.ZERO
var _buf_idx: int = Tune.NO_ACTION
var _buf_time: float = 0.0

var _hit_flash: float = 0.0
var _pulse: float = 0.0

## Debug hook: when active, this replaces the cursor as the aim source. Used by
## the headless tests, and by the step-5 tooling to fire skills at a fixed spot.
var aim_override_active: bool = false
var aim_override: Vector2 = Vector2.ZERO


func _ready() -> void:
	body_radius = Tune.PLAYER_RADIUS
	height = Tune.PLAYER_HEIGHT
	cooldowns.resize(Tune.SKILL_COUNT)
	for i in range(Tune.SKILL_COUNT):
		cooldowns[i] = 0.0
	Events.damage_dealt.connect(_on_damage_dealt)


func variant() -> Dictionary:
	return Tune.variant(variant_idx)


## The ground point the player is aiming at, in world space.
func aim_world() -> Vector2:
	return aim_override if aim_override_active else View.to_world(get_global_mouse_position())


func is_overheated() -> bool:
	return overheat > 0.0


func act_progress() -> float:
	if state != State.ACTING or act_total <= 0.0:
		return 0.0
	return clampf(act_elapsed / act_total, 0.0, 1.0)


## Is the current action a real cast, as opposed to an auto or an instant?
func is_casting() -> bool:
	return state == State.ACTING and act_total > 0.0 and act_idx != Tune.AUTO_ACTION


# ---------------------------------------------------------------------------
# FRAME
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_timers(delta)
	_read_input()

	match state:
		State.FREE:
			_state_free()
		State.ACTING:
			_state_acting(delta)
		State.DASHING:
			_state_dashing(delta)

	_apply_motion(delta)
	sync_view()
	queue_redraw()


func _tick_timers(delta: float) -> void:
	_pulse += delta
	act_lock = maxf(0.0, act_lock - delta)
	invuln = maxf(0.0, invuln - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)

	if overheat > 0.0:
		overheat = maxf(0.0, overheat - delta)
		if overheat <= 0.0:
			Events.identity_ended.emit()
	elif Tune.IDENTITY_DECAY > 0.0:
		identity = maxf(0.0, identity - Tune.IDENTITY_DECAY * delta)

	for i in range(Tune.SKILL_COUNT):
		if cooldowns[i] > 0.0:
			cooldowns[i] = maxf(0.0, cooldowns[i] - delta)

	if dash_charges < Tune.DASH_CHARGES:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = Tune.DASH_CHARGE_COOLDOWN if dash_charges < Tune.DASH_CHARGES else 0.0

	if _auto_chain_timer > 0.0:
		_auto_chain_timer -= delta
		if _auto_chain_timer <= 0.0:
			auto_step = 0

	if _buf_time > 0.0:
		_buf_time -= delta
		if _buf_time <= 0.0:
			_buf_idx = Tune.NO_ACTION


func _read_input() -> void:
	_move_input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if _move_input.length_squared() > 1.0:
		_move_input = _move_input.normalized()

	if Input.is_action_just_pressed("toggle_variant"):
		_toggle_variant()
	if Input.is_action_just_pressed("identity"):
		_try_overheat()

	for i in range(Tune.SKILL_COUNT):
		if Input.is_action_just_pressed("skill_%d" % (i + 1)):
			_buffer(i)
	if Input.is_action_just_pressed("auto_attack"):
		_buffer(Tune.AUTO_ACTION)
	if Input.is_action_just_pressed("dash"):
		_buffer(Tune.SKILL_COUNT)  # dash uses the slot past the hotbar

	# Hold-to-repeat, but never stomping an explicit press that's already queued.
	if Tune.ALLOW_HOLD_TO_REPEAT and _buf_idx == Tune.NO_ACTION:
		if Input.is_action_pressed("auto_attack"):
			_buffer(Tune.AUTO_ACTION)
		elif state == State.FREE and act_lock <= 0.0:
			for i in range(Tune.SKILL_COUNT):
				if Input.is_action_pressed("skill_%d" % (i + 1)) and cooldowns[i] <= 0.0:
					_buffer(i)
					break

	# Facing tracks the cursor unless the current cast has locked the body.
	var to_mouse := aim_world() - world_pos
	if to_mouse.length_squared() > 1.0:
		var locked := is_casting() and bool(Tune.variant(act_variant)["turn_locked"])
		if not locked:
			facing = to_mouse.normalized()


func _buffer(idx: int) -> void:
	_buf_idx = idx
	# Pressing during a cast holds the input until the cast ends - that's what
	# makes 3 -> 4 chain seamlessly instead of dropping the second press.
	if Tune.CAST_QUEUE_ENABLED and state == State.ACTING and act_progress() >= Tune.CAST_QUEUE_WINDOW:
		_buf_time = maxf(act_total - act_elapsed, 0.0) + Tune.INPUT_BUFFER
	else:
		_buf_time = Tune.INPUT_BUFFER


func _consume_buffer() -> void:
	_buf_idx = Tune.NO_ACTION
	_buf_time = 0.0


func _ready_to_use(idx: int) -> bool:
	if idx == Tune.AUTO_ACTION:
		return true
	if idx == Tune.SKILL_COUNT:
		return dash_charges > 0
	return cooldowns[idx] <= 0.0


# ---------------------------------------------------------------------------
# STATES
# ---------------------------------------------------------------------------

func _state_free() -> void:
	if act_lock > 0.0 or _buf_idx == Tune.NO_ACTION:
		return
	var idx := _buf_idx
	if idx == Tune.SKILL_COUNT:
		if _try_dash():
			_consume_buffer()
		return
	if not _ready_to_use(idx):
		return  # stays buffered; fires the instant the cooldown ends
	_consume_buffer()
	_begin_action(idx)


func _state_acting(delta: float) -> void:
	# Dash-cancel. THE tradeoff: you get out, but you paid for the skill.
	if _buf_idx == Tune.SKILL_COUNT and _can_cancel_now() and dash_charges > 0:
		_consume_buffer()
		_cancel_action()
		_try_dash()
		return

	if not bool(Tune.variant(act_variant)["aim_locks"]):
		var aim := aim_world()
		var to_mouse := aim - world_pos
		if to_mouse.length_squared() > 1.0:
			act_aim = to_mouse.normalized()
		act_target = aim

	act_elapsed += delta
	if act_elapsed >= act_total:
		_finish_action()


func _state_dashing(delta: float) -> void:
	_dash_time -= delta
	_dash_trail -= delta
	if _dash_trail <= 0.0:
		_dash_trail = 0.03
		var r := FxRing.pop(View.to_screen(world_pos) - Vector2(0, height), body_radius, body_radius * 0.4,
			Color(Tune.COL_PLAYER.r, Tune.COL_PLAYER.g, Tune.COL_PLAYER.b, 0.5), 0.22)
		r.filled = true
	if _dash_time <= 0.0:
		state = State.FREE
		act_lock = maxf(act_lock, Tune.DASH_END_LAG)
		velocity = _dash_dir * Tune.PLAYER_MOVE_SPEED * 0.5


func _can_cancel_now() -> bool:
	# Autos and instants have nothing worth protecting; only real casts lock out.
	if not is_casting():
		return true
	return (1.0 - act_progress()) >= Tune.CANCEL_LOCKOUT_TAIL


# ---------------------------------------------------------------------------
# ACTIONS
# ---------------------------------------------------------------------------

func _begin_action(idx: int) -> void:
	act_variant = variant_idx
	act_overheated = is_overheated()
	act_idx = idx
	act_elapsed = 0.0
	act_total = _action_cast_time(idx)

	var aim := aim_world()
	var to_mouse := aim - world_pos
	act_aim = to_mouse.normalized() if to_mouse.length_squared() > 1.0 else facing
	act_target = aim
	facing = act_aim
	state = State.ACTING

	if act_total > 0.0:
		Events.shake_requested.emit(Tune.SHAKE_ON_CAST)
	else:
		# Instant: resolve on the same frame it was pressed.
		_finish_action()


func _action_cast_time(idx: int) -> float:
	if idx == Tune.AUTO_ACTION:
		var times: Array = Tune.AUTO["cast_times"]
		var t := float(times[auto_step % times.size()])
		return t * (Tune.IDENTITY_CAST_MULT if act_overheated else 1.0)
	return Tune.cast_time(idx, act_variant, act_overheated)


func _cancel_action() -> void:
	if state != State.ACTING:
		return
	var idx := act_idx
	if idx >= 0:
		var paid := float(Tune.SKILLS[idx]["cooldown"]) * Tune.CANCEL_COOLDOWN_FRACTION
		cooldowns[idx] = paid
		Events.cast_cancelled.emit(idx, paid)
		if paid > 0.0 and act_total > 0.0:
			Floater.spawn(View.to_screen(world_pos) - Vector2(0, height + 44.0),
				"CANCELLED", Tune.COL_WARN, 16)
	state = State.FREE
	act_idx = Tune.NO_ACTION


func _finish_action() -> void:
	var idx := act_idx
	var mult := _damage_mult(idx)

	if idx == Tune.AUTO_ACTION:
		_resolve_auto(mult)
	else:
		var s: Dictionary = Tune.SKILLS[idx]
		match String(s["kind"]):
			"rain":
				_cast_rain(s, mult, idx)
			"counter":
				_cast_counter(s, mult, idx)
			"bolt":
				_cast_bolt(s, mult, idx)
			"meteor":
				_cast_meteor(s, mult, idx)
		cooldowns[idx] = s["cooldown"]
		if float(s["cast_time"]) > 0.0:
			_gain_identity(Tune.IDENTITY_GAIN_PER_CAST)
		Events.cast_completed.emit(idx)

	state = State.FREE
	act_idx = Tune.NO_ACTION
	_apply_recovery(idx)


## Recovery, unless something is queued - a queued action skips the gap. That
## seam is exactly what makes chained casts feel continuous instead of stepped.
func _apply_recovery(finished_idx: int) -> void:
	var recovery := float(Tune.AUTO["recovery"]) if finished_idx == Tune.AUTO_ACTION \
		else float(Tune.SKILLS[finished_idx]["recovery"])
	if Tune.CAST_QUEUE_ENABLED and _buf_idx != Tune.NO_ACTION and _ready_to_use(_buf_idx):
		act_lock = Tune.CAST_QUEUE_GAP
	else:
		act_lock = recovery


func _damage_mult(idx: int) -> float:
	if idx == Tune.AUTO_ACTION:
		return Tune.IDENTITY_DAMAGE_MULT if act_overheated else 1.0
	return Tune.damage_mult(idx, act_variant, act_overheated)


# --- auto attack ------------------------------------------------------------

func _resolve_auto(mult: float) -> void:
	var a: Dictionary = Tune.AUTO
	var times: Array = a["cast_times"]
	var step := auto_step % times.size()
	var dmg := float(a["damages"][step]) * mult
	var stag := float(a["staggers"][step]) * mult

	if step == int(a["finisher_step"]):
		# The chain finisher opens up into a small blast - repetition needs a
		# shape, and a 1-2-BOOM rhythm is the cheapest way to give it one.
		var shape := AtkShape.circle(world_pos + act_aim * 70.0, float(a["finisher_radius"]))
		var tg := Telegraph.spawn(shape, 0.04, 0.08, a["color"])
		tg.flash_only = true
		tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
			_resolve_shape(sh, dmg, stag, Tune.AUTO_ACTION, false)
		)
	else:
		var b := Bolt.fire(world_pos + act_aim * (body_radius + 6.0), act_aim, a["color"])
		b.speed = a["bolt_speed"]
		b.body_radius = a["bolt_radius"]
		b.max_range = a["bolt_range"]
		b.damage = dmg
		b.stagger = stag
		b.action_idx = Tune.AUTO_ACTION

	auto_step = (auto_step + 1) % times.size()
	_auto_chain_timer = float(a["chain_reset"])


# --- skills -----------------------------------------------------------------

## Multi-hit rain. One boundary marker plus a stream of small impacts spread
## over the duration. A single number is a worse hit than eight numbers, even
## for the same total - this is where that comes from.
func _cast_rain(s: Dictionary, mult: float, idx: int) -> void:
	var centre := _aim_point(float(s["max_cast_range"]))
	var radius := float(s["radius"])
	var count := int(s["impacts"])
	var duration := float(s["duration"])
	var dmg := float(s["dmg_per_impact"]) * mult
	var stag := float(s["stagger_per_impact"]) * mult

	# Boundary marker: outline only, so it reads as "my zone", not "dodge this".
	var zone := Telegraph.spawn(AtkShape.circle(centre, radius), duration, 0.01, s["color"])
	zone.flash_only = true

	for i in range(count):
		var ang := randf() * TAU
		var dist := sqrt(randf()) * radius * 0.85
		var at := centre + Vector2.from_angle(ang) * dist
		var tg := Telegraph.spawn(AtkShape.circle(at, float(s["impact_radius"])),
			float(s["impact_windup"]), 0.06, s["color"])
		tg.start_delay = duration * (float(i) / float(maxi(count, 1)))
		tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
			_resolve_shape(sh, dmg, stag, idx, false)
			FxRing.ground_pop(sh.origin, 6.0, sh.radius, s["color"], 0.22)
		)


## Instant counter strike. Landing it inside a boss counter window is the whole
## reason it exists, so it reports success or failure either way.
func _cast_counter(s: Dictionary, mult: float, idx: int) -> void:
	var shape := AtkShape.rect(world_pos, act_aim, float(s["length"]), float(s["half_width"]))
	var tg := Telegraph.spawn(shape, float(s["impact_windup"]), 0.10, s["color"])
	tg.flash_only = true
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_resolve_counter(sh, s, mult, idx)
	)


func _resolve_counter(shape: AtkShape, s: Dictionary, mult: float, idx: int) -> void:
	var base := float(s["damage"]) * mult
	var stag := float(s["stagger"]) * mult
	var any := false
	var landed := false
	for h in Hostile.all():
		if not shape.overlaps_circle(h.world_pos, h.body_radius):
			continue
		any = true
		if h.counter_window_open():
			landed = true
			h.apply_hit(base * float(s["counter_damage_mult"]), stag, idx, true)
			h.on_countered(float(s["counter_stun"]))
			Floater.spawn(View.to_screen(h.world_pos) - Vector2(0, h.height + 70.0),
				"COUNTER!", Color(0.45, 1.0, 0.85), 34, 1.0)
			FxRing.pop(View.to_screen(h.world_pos) - Vector2(0, h.height),
				20.0, 220.0, Color(0.45, 1.0, 0.85), 0.45)
			Events.shake_requested.emit(12.0)
			Events.hitstop_requested.emit(Tune.HITSTOP_HEAVY * 2.0)
		else:
			h.apply_hit(base, stag, idx, true)
	if any:
		Events.counter_landed.emit(landed, world_pos)


func _cast_bolt(s: Dictionary, mult: float, idx: int) -> void:
	var b := Bolt.fire(world_pos + act_aim * (body_radius + 6.0), act_aim, s["color"])
	b.speed = s["bolt_speed"]
	b.body_radius = s["bolt_radius"]
	b.max_range = s["bolt_range"]
	b.damage = float(s["damage"]) * mult
	b.stagger = float(s["stagger"]) * mult
	b.action_idx = idx


func _cast_meteor(s: Dictionary, mult: float, idx: int) -> void:
	var centre := _aim_point(float(s["max_cast_range"]))
	var shape := AtkShape.circle(centre, float(s["radius"]))
	var tg := Telegraph.spawn(shape, float(s["impact_windup"]), 0.10, s["color"])
	var dmg := float(s["damage"]) * mult
	var stag := float(s["stagger"]) * mult
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_resolve_shape(sh, dmg, stag, idx, false)
		FxRing.ground_pop(sh.origin, 20.0, sh.radius * 1.3, s["color"], 0.40)
		Events.shake_requested.emit(9.0)
	)


## The action's ground target, clamped to the skill's range and the arena.
## Reads act_target rather than the live cursor, so an aim-locked cast lands
## where it was committed.
func _aim_point(max_range: float) -> Vector2:
	var target := act_target
	var off := target - world_pos
	if off.length() > max_range:
		target = world_pos + off.normalized() * max_range
	return Actor.clamp_to_arena(target)


## Apply one shape to every hostile it overlaps. The mirror image of what the
## boss will do to the player, using the same AtkShape test.
func _resolve_shape(shape: AtkShape, dmg: float, stag: float, idx: int, is_counter: bool) -> void:
	for h in Hostile.all():
		if shape.overlaps_circle(h.world_pos, h.body_radius):
			h.apply_hit(dmg, stag, idx, is_counter)


# ---------------------------------------------------------------------------
# OVERHEAT
# ---------------------------------------------------------------------------

func _on_damage_dealt(_amount: float, _at: Vector2, _idx: int) -> void:
	# Per HIT, not per damage: multi-hit skills and autos are what charge it.
	_gain_identity(Tune.IDENTITY_GAIN_PER_HIT)


func _gain_identity(amount: float) -> void:
	if is_overheated():
		return
	var before := identity
	identity = clampf(identity + amount, 0.0, Tune.IDENTITY_MAX)
	if before < Tune.IDENTITY_MAX and identity >= Tune.IDENTITY_MAX:
		Events.identity_full.emit()
		FxRing.pop(View.to_screen(world_pos) - Vector2(0, height), 20.0, 90.0, Tune.COL_IDENTITY, 0.4)


func _try_overheat() -> bool:
	if is_overheated() or identity < Tune.IDENTITY_MAX:
		return false
	identity = 0.0
	overheat = Tune.IDENTITY_DURATION
	if Tune.IDENTITY_RESETS_COOLDOWNS:
		for i in range(Tune.SKILL_COUNT):
			cooldowns[i] = 0.0
	Events.identity_activated.emit()
	Events.shake_requested.emit(10.0)
	Floater.spawn(View.to_screen(world_pos) - Vector2(0, height + 60.0), "OVERHEAT", Tune.COL_IDENTITY, 34, 1.0)
	FxRing.pop(View.to_screen(world_pos) - Vector2(0, height), 10.0, 260.0, Tune.COL_IDENTITY, 0.5)
	return true


# ---------------------------------------------------------------------------
# DASH
# ---------------------------------------------------------------------------

func _try_dash() -> bool:
	if dash_charges <= 0:
		return false
	var d := _move_input
	if d.length_squared() < 0.01:
		if not Tune.DASH_USES_MOUSE_WHEN_IDLE:
			return false
		d = facing
	d = d.normalized()

	if dash_charges == Tune.DASH_CHARGES:
		dash_recharge = Tune.DASH_CHARGE_COOLDOWN
	dash_charges -= 1

	_dash_dir = d
	_dash_time = Tune.DASH_DURATION
	_dash_trail = 0.0
	invuln = maxf(invuln, Tune.DASH_IFRAMES)
	state = State.DASHING
	act_lock = 0.0
	return true


# ---------------------------------------------------------------------------
# MOTION
# ---------------------------------------------------------------------------

func _apply_motion(delta: float) -> void:
	if state == State.DASHING:
		velocity = _dash_dir * (Tune.DASH_DISTANCE / maxf(Tune.DASH_DURATION, 0.0001))
	else:
		var mult := 1.0
		if state == State.ACTING:
			mult = float(Tune.AUTO["move_mult"]) if act_idx == Tune.AUTO_ACTION \
				else float(Tune.variant(act_variant)["move_mult"])
			# Instants never root you; only things with a cast time do.
			if act_total <= 0.0:
				mult = 1.0
		var input := _move_input
		# Depth movement covers less screen distance, so it needs a nudge to
		# stop the stick feeling oval.
		input.y *= Tune.PLAYER_DEPTH_SPEED_MULT
		var target := input * Tune.PLAYER_MOVE_SPEED * mult
		var speeding_up := target.length() > velocity.length()
		var t := Tune.PLAYER_ACCEL_TIME if speeding_up else Tune.PLAYER_DECEL_TIME
		velocity = velocity.move_toward(target, (Tune.PLAYER_MOVE_SPEED / maxf(t, 0.0005)) * delta)

	world_pos += velocity * delta
	var clamped := Actor.clamp_to_arena(world_pos)
	if clamped.x != world_pos.x:
		velocity.x = 0.0
	if clamped.y != world_pos.y:
		velocity.y = 0.0
	world_pos = clamped


# ---------------------------------------------------------------------------
# DAMAGE
# ---------------------------------------------------------------------------

func take_hit(amount: float, source: String = "") -> bool:
	var avoided := invuln > 0.0 or god_mode
	Events.player_hit.emit(amount, world_pos, avoided)
	var at := View.to_screen(world_pos) - Vector2(0, height + 34.0)
	if avoided:
		Floater.spawn(at, "AVOID" if invuln > 0.0 else "GOD", Color(0.6, 1.0, 0.8), 16)
		return false
	hp = maxf(0.0, hp - amount)
	_hit_flash = 1.0
	Events.shake_requested.emit(7.0)
	Floater.spawn(at, "-%d %s" % [roundi(amount), source], Tune.COL_WARN, 20)
	return true


func reset() -> void:
	hp = Tune.PLAYER_MAX_HP
	state = State.FREE
	velocity = Vector2.ZERO
	invuln = 0.0
	act_lock = 0.0
	act_idx = Tune.NO_ACTION
	auto_step = 0
	_auto_chain_timer = 0.0
	identity = 0.0
	overheat = 0.0
	dash_charges = Tune.DASH_CHARGES
	dash_recharge = 0.0
	for i in range(Tune.SKILL_COUNT):
		cooldowns[i] = 0.0
	_consume_buffer()


func _toggle_variant() -> void:
	variant_idx = (variant_idx + 1) % Tune.VARIANTS.size()
	Events.variant_changed.emit(variant_idx)
	var v := variant()
	Floater.spawn(View.to_screen(world_pos) - Vector2(0, height + 70.0), String(v["name"]), v["color"], 26)


# ---------------------------------------------------------------------------
# DRAW - local origin is the body centre; feet() is the ground point.
# ---------------------------------------------------------------------------

func _draw() -> void:
	var v := variant()
	var vcol: Color = v["color"]

	draw_shadow(body_radius * 1.05)

	# Ground aim marker. In a side-on view a facing nub at body height is hard
	# to read, so the direction indicator lies on the floor where the shapes are.
	_draw_aim_marker(vcol)

	if is_overheated():
		var pulse := 0.5 + 0.5 * sin(_pulse * 9.0)
		draw_ground_ring(feet(), body_radius * 2.6 + pulse * 6.0,
			Color(Tune.COL_IDENTITY.r, Tune.COL_IDENTITY.g, Tune.COL_IDENTITY.b, 0.55), 3.0)

	# Body: an upright figure, not a disc lying on the floor.
	var col := Tune.COL_PLAYER
	if is_casting():
		col = col.lerp(vcol, 0.45 + 0.25 * act_progress())
	if is_overheated():
		col = col.lerp(Tune.COL_IDENTITY, 0.35)
	if _hit_flash > 0.0:
		col = col.lerp(Tune.COL_WARN, _hit_flash)

	var torso := PackedVector2Array([
		Vector2(-body_radius * 0.62, 0.0),
		Vector2(body_radius * 0.62, 0.0),
		Vector2(body_radius * 0.42, height),
		Vector2(-body_radius * 0.42, height),
	])
	draw_colored_polygon(torso, col.darkened(0.35))
	draw_circle(Vector2.ZERO, body_radius, col)

	if invuln > 0.0:
		draw_arc(Vector2.ZERO, body_radius + 5.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 3.0, true)
	if god_mode:
		draw_arc(Vector2.ZERO, body_radius + 10.0, 0.0, TAU, 32, Color(0.5, 1.0, 0.6, 0.6), 2.0, true)

	# Full movement lock during a COMMIT cast is drawn, never implied.
	if is_casting() and float(Tune.variant(act_variant)["move_mult"]) <= 0.001:
		draw_ground_ring(feet(), body_radius * 1.9, Color(vcol.r, vcol.g, vcol.b, 0.55), 2.0)

	_draw_cast_bar()
	_draw_dash_pips()


func _draw_aim_marker(vcol: Color) -> void:
	var f := feet()
	# Locked aim during a COMMIT cast: this is where the skill is going,
	# regardless of where the mouse ends up. That read is the variant.
	if is_casting():
		var tip := Vector2(act_aim.x, act_aim.y * Tune.VIEW_SQUASH) * 130.0
		draw_line(f, f + tip, Color(vcol.r, vcol.g, vcol.b, 0.4), 2.5, true)
	var d := Vector2(facing.x, facing.y * Tune.VIEW_SQUASH).normalized()
	var side := Vector2(-d.y, d.x)
	var base := f + d * (body_radius + 6.0)
	draw_colored_polygon(PackedVector2Array([
		base + d * 11.0, base + side * 6.0, base - side * 6.0,
	]), Color(1, 1, 1, 0.5))


func _draw_cast_bar() -> void:
	if state != State.ACTING or act_total <= 0.0:
		return
	var w := 88.0
	var h := 8.0
	var top := Vector2(-w * 0.5, -body_radius - 26.0)
	draw_rect(Rect2(top, Vector2(w, h)), Color(0, 0, 0, 0.7))
	var fill: Color = Tune.COL_CASTBAR if act_variant == Tune.VARIANT_COMMIT else Tune.COL_CASTBAR_FLOW
	if act_idx == Tune.AUTO_ACTION:
		fill = Tune.AUTO["color"]
	draw_rect(Rect2(top, Vector2(w * act_progress(), h)), fill)
	if Tune.CANCEL_LOCKOUT_TAIL > 0.0 and act_idx >= 0:
		var x := w * (1.0 - Tune.CANCEL_LOCKOUT_TAIL)
		draw_line(top + Vector2(x, -2.0), top + Vector2(x, h + 2.0), Tune.COL_WARN, 1.5)
	draw_rect(Rect2(top, Vector2(w, h)), Color(1, 1, 1, 0.3), false, 1.0)


func _draw_dash_pips() -> void:
	var pip_r := 3.5
	var gap := 12.0
	var total := gap * float(Tune.DASH_CHARGES - 1)
	var y := -body_radius - 36.0
	for i in range(Tune.DASH_CHARGES):
		var p := Vector2(-total * 0.5 + gap * float(i), y)
		if i < dash_charges:
			draw_circle(p, pip_r, Color(0.65, 0.95, 1.0, 0.95))
		else:
			draw_circle(p, pip_r, Color(0.3, 0.35, 0.45, 0.85))
			if i == dash_charges and Tune.DASH_CHARGE_COOLDOWN > 0.0:
				var f := 1.0 - clampf(dash_recharge / Tune.DASH_CHARGE_COOLDOWN, 0.0, 1.0)
				draw_arc(p, pip_r + 2.0, -PI * 0.5, -PI * 0.5 + TAU * f, 16, Color(0.65, 0.95, 1.0, 0.8), 1.5, true)
