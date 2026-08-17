class_name Player
extends Node2D
## Movement, the dash, and the two cast variants.
##
## The whole point of this file is the FREE / CASTING / DASHING machine and what
## it costs you to leave CASTING early. Variants are data (Tune.VARIANTS), not
## subclasses, so TAB can swap them mid-fight with no state to migrate.

enum State { FREE, CASTING, DASHING }

var body_radius: float = Tune.PLAYER_RADIUS

var state: State = State.FREE
var variant_idx: int = Tune.START_VARIANT

var hp: float = Tune.PLAYER_MAX_HP
var god_mode: bool = false
var invuln: float = 0.0

var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT

## Blocks all actions. Cast recovery and dash end-lag both write here.
var act_lock: float = 0.0

var cooldowns: PackedFloat32Array = PackedFloat32Array()
var dash_charges: int = Tune.DASH_CHARGES
var dash_recharge: float = 0.0

# --- current cast ---
var cast_idx: int = -1
var cast_elapsed: float = 0.0
var cast_total: float = 0.0
var cast_aim: Vector2 = Vector2.RIGHT
## Variant captured when the cast STARTED, so a mid-cast TAB can't rewrite the
## damage of a cast you already committed to.
var cast_variant: int = 0

# --- dash ---
var _dash_time: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _dash_trail: float = 0.0

# --- input ---
var _move_input: Vector2 = Vector2.ZERO
var _buf_idx: int = -1
var _buf_time: float = 0.0

var _hit_flash: float = 0.0
var _cast_flash: float = 0.0


func _ready() -> void:
	z_index = 4
	cooldowns.resize(Tune.SKILL_COUNT)
	for i in range(Tune.SKILL_COUNT):
		cooldowns[i] = 0.0


func variant() -> Dictionary:
	return Tune.variant(variant_idx)


func is_busy() -> bool:
	return state != State.FREE or act_lock > 0.0


func cast_progress() -> float:
	if state != State.CASTING:
		return 0.0
	return clampf(cast_elapsed / maxf(cast_total, 0.0001), 0.0, 1.0)


# ---------------------------------------------------------------------------
# FRAME
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_timers(delta)
	_read_input()

	match state:
		State.FREE:
			_state_free(delta)
		State.CASTING:
			_state_casting(delta)
		State.DASHING:
			_state_dashing(delta)

	_apply_motion(delta)
	queue_redraw()


func _tick_timers(delta: float) -> void:
	act_lock = maxf(0.0, act_lock - delta)
	invuln = maxf(0.0, invuln - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_cast_flash = maxf(0.0, _cast_flash - delta * 6.0)

	for i in range(Tune.SKILL_COUNT):
		if cooldowns[i] > 0.0:
			cooldowns[i] = maxf(0.0, cooldowns[i] - delta)

	if dash_charges < Tune.DASH_CHARGES:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = Tune.DASH_CHARGE_COOLDOWN if dash_charges < Tune.DASH_CHARGES else 0.0

	if _buf_time > 0.0:
		_buf_time -= delta
		if _buf_time <= 0.0:
			_buf_idx = -1


func _read_input() -> void:
	_move_input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if _move_input.length_squared() > 1.0:
		_move_input = _move_input.normalized()

	if Input.is_action_just_pressed("toggle_variant"):
		_toggle_variant()

	for i in range(Tune.SKILL_COUNT):
		if Input.is_action_just_pressed("skill_%d" % (i + 1)):
			_buffer(i)
	if Input.is_action_just_pressed("dash"):
		_buffer(Tune.SKILL_COUNT - 1)

	# Hold-to-repeat: keeps the hands honest about which skill is actually the
	# throughput one, instead of rewarding key mashing.
	if Tune.ALLOW_HOLD_TO_REPEAT and state == State.FREE and act_lock <= 0.0 and _buf_idx < 0:
		for i in range(Tune.SKILL_COUNT - 1):
			if Input.is_action_pressed("skill_%d" % (i + 1)) and cooldowns[i] <= 0.0:
				_buffer(i)
				break

	# Facing tracks the cursor unless the current cast has locked the body.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		var body_locked: bool = state == State.CASTING and bool(Tune.variant(cast_variant)["turn_locked"])
		if not body_locked:
			facing = to_mouse.normalized()


func _buffer(idx: int) -> void:
	_buf_idx = idx
	_buf_time = Tune.INPUT_BUFFER


func _consume_buffer() -> void:
	_buf_idx = -1
	_buf_time = 0.0


# ---------------------------------------------------------------------------
# STATES
# ---------------------------------------------------------------------------

func _state_free(_delta: float) -> void:
	if act_lock > 0.0 or _buf_idx < 0:
		return
	var idx := _buf_idx
	if idx == Tune.SKILL_COUNT - 1:
		if _try_dash():
			_consume_buffer()
		return
	if cooldowns[idx] > 0.0:
		return  # keep it buffered; it fires the instant the cooldown ends
	_consume_buffer()
	_begin_cast(idx)


func _state_casting(delta: float) -> void:
	# Dash-cancel. THE tradeoff: you get out, but you paid for the skill.
	if _buf_idx == Tune.SKILL_COUNT - 1 and _can_cancel_now() and dash_charges > 0:
		_consume_buffer()
		_cancel_cast()
		_try_dash()
		return

	if not bool(Tune.variant(cast_variant)["aim_locks"]):
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length_squared() > 1.0:
			cast_aim = to_mouse.normalized()

	cast_elapsed += delta
	if cast_elapsed >= cast_total:
		_finish_cast()


func _state_dashing(delta: float) -> void:
	_dash_time -= delta
	_dash_trail -= delta
	if _dash_trail <= 0.0:
		_dash_trail = 0.03
		var r := FxRing.pop(get_parent(), global_position, body_radius, body_radius * 0.4,
			Color(Tune.COL_PLAYER.r, Tune.COL_PLAYER.g, Tune.COL_PLAYER.b, 0.5), 0.22)
		r.filled = true
	if _dash_time <= 0.0:
		state = State.FREE
		act_lock = maxf(act_lock, Tune.DASH_END_LAG)
		velocity = _dash_dir * Tune.PLAYER_MOVE_SPEED * 0.5


func _can_cancel_now() -> bool:
	var remaining := 1.0 - cast_progress()
	return remaining >= Tune.CANCEL_LOCKOUT_TAIL


# ---------------------------------------------------------------------------
# CASTING
# ---------------------------------------------------------------------------

func _begin_cast(idx: int) -> void:
	cast_variant = variant_idx
	cast_idx = idx
	cast_elapsed = 0.0
	cast_total = Tune.cast_time(idx, cast_variant)
	var to_mouse := get_global_mouse_position() - global_position
	cast_aim = to_mouse.normalized() if to_mouse.length_squared() > 1.0 else facing
	facing = cast_aim
	state = State.CASTING
	_cast_flash = 1.0
	Events.shake_requested.emit(Tune.SHAKE_ON_CAST)

	# A zero-length cast (a fully-tuned-down Flow skill) still resolves cleanly.
	if cast_total <= 0.0:
		_finish_cast()


func _cancel_cast() -> void:
	if state != State.CASTING:
		return
	var s := Tune.skill(cast_idx)
	var paid: float = float(s["cooldown"]) * Tune.CANCEL_COOLDOWN_FRACTION
	cooldowns[cast_idx] = paid
	Events.cast_cancelled.emit(cast_idx, paid)
	if paid > 0.0:
		Floater.spawn(get_parent(), global_position + Vector2(0, -40.0), "CANCELLED", Tune.COL_WARN, 15)
	state = State.FREE
	cast_idx = -1


func _finish_cast() -> void:
	var idx := cast_idx
	var s := Tune.skill(idx)
	var dmg := Tune.damage(idx, cast_variant)
	var stag: float = s["stagger"]

	match String(s["kind"]):
		"bolt":
			_fire_bolt(s, dmg, stag, idx)
		"aoe_at_mouse":
			_fire_aoe(s, dmg, stag, idx)
		"rect_ahead":
			_fire_rect(s, dmg, stag, idx)

	cooldowns[idx] = s["cooldown"]
	state = State.FREE
	cast_idx = -1
	act_lock = maxf(act_lock, Tune.CAST_RECOVERY)
	Events.cast_completed.emit(idx)


func _fire_bolt(s: Dictionary, dmg: float, stag: float, idx: int) -> void:
	var b := Bolt.new()
	b.global_position = global_position + cast_aim * (body_radius + 4.0)
	b.dir = cast_aim
	b.speed = s["bolt_speed"]
	b.radius = s["bolt_radius"]
	b.max_range = s["bolt_range"]
	b.damage = dmg
	b.stagger = stag
	b.skill_idx = idx
	b.is_counter = s["is_counter"]
	b.col = s["color"]
	get_parent().add_child(b)


func _fire_aoe(s: Dictionary, dmg: float, stag: float, idx: int) -> void:
	var target := get_global_mouse_position()
	var off := target - global_position
	var max_range: float = s["max_cast_range"]
	if off.length() > max_range:
		target = global_position + off.normalized() * max_range
	var shape := AtkShape.circle(target, s["radius"])
	var tg := Telegraph.spawn(get_parent(), shape, s["impact_delay"], 0.08, s["color"])
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_resolve_shape(sh, dmg, stag, idx, s["is_counter"])
	)


func _fire_rect(s: Dictionary, dmg: float, stag: float, idx: int) -> void:
	var shape := AtkShape.rect(global_position, cast_aim, s["length"], s["half_width"])
	var tg := Telegraph.spawn(get_parent(), shape, s["impact_delay"], 0.08, s["color"])
	tg.activated.connect(func(sh: AtkShape, _t: Telegraph) -> void:
		_resolve_shape(sh, dmg, stag, idx, s["is_counter"])
	)


## Apply one shape to every hostile it overlaps. The mirror image of what the
## boss will do to the player in step 2, using the same AtkShape test.
func _resolve_shape(shape: AtkShape, dmg: float, stag: float, idx: int, is_counter: bool) -> void:
	for h in Hostile.all():
		if shape.overlaps_circle(h.global_position, h.body_radius):
			h.apply_hit(dmg, stag, idx, is_counter)


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
		if state == State.CASTING:
			mult = float(Tune.variant(cast_variant)["move_mult"])
		var target := _move_input * Tune.PLAYER_MOVE_SPEED * mult
		var speeding_up := target.length() > velocity.length()
		var t := Tune.PLAYER_ACCEL_TIME if speeding_up else Tune.PLAYER_DECEL_TIME
		var rate := Tune.PLAYER_MOVE_SPEED / maxf(t, 0.0005)
		velocity = velocity.move_toward(target, rate * delta)

	global_position += velocity * delta

	# Circular arena clamp; kill the radial component so you slide along the wall.
	var off := global_position - Tune.ARENA_CENTER
	var limit := Tune.ARENA_RADIUS - Tune.ARENA_EDGE_PAD
	if off.length() > limit:
		var n := off.normalized()
		global_position = Tune.ARENA_CENTER + n * limit
		var radial := velocity.dot(n)
		if radial > 0.0:
			velocity -= n * radial


# ---------------------------------------------------------------------------
# DAMAGE
# ---------------------------------------------------------------------------

func take_hit(amount: float, source: String = "") -> bool:
	var avoided := invuln > 0.0 or god_mode
	Events.player_hit.emit(amount, global_position, avoided)
	if avoided:
		Floater.spawn(get_parent(), global_position + Vector2(0, -34.0),
			"AVOID" if invuln > 0.0 else "GOD", Color(0.6, 1.0, 0.8), 15)
		return false
	hp = maxf(0.0, hp - amount)
	_hit_flash = 1.0
	Events.shake_requested.emit(7.0)
	Floater.spawn(get_parent(), global_position + Vector2(0, -34.0),
		"-%d %s" % [roundi(amount), source], Tune.COL_WARN, 18)
	return true


func reset() -> void:
	hp = Tune.PLAYER_MAX_HP
	state = State.FREE
	velocity = Vector2.ZERO
	invuln = 0.0
	act_lock = 0.0
	cast_idx = -1
	dash_charges = Tune.DASH_CHARGES
	dash_recharge = 0.0
	for i in range(Tune.SKILL_COUNT):
		cooldowns[i] = 0.0
	_consume_buffer()


func _toggle_variant() -> void:
	variant_idx = (variant_idx + 1) % Tune.VARIANTS.size()
	Events.variant_changed.emit(variant_idx)
	var v := variant()
	Floater.spawn(get_parent(), global_position + Vector2(0, -56.0), String(v["name"]), v["color"], 22)


# ---------------------------------------------------------------------------
# DRAW
# ---------------------------------------------------------------------------

func _draw() -> void:
	var v := variant()
	var vcol: Color = v["color"]

	# Locked-aim line: during a COMMIT cast this is where the skill is going,
	# no matter where the mouse ends up. That read is the whole variant.
	if state == State.CASTING:
		var lock_col := Color(vcol.r, vcol.g, vcol.b, 0.35)
		draw_line(Vector2.ZERO, cast_aim * 120.0, lock_col, 2.0, true)

	# Body.
	var col := Tune.COL_PLAYER
	if state == State.CASTING:
		col = col.lerp(vcol, 0.45 + 0.25 * cast_progress())
	if _hit_flash > 0.0:
		col = col.lerp(Tune.COL_WARN, _hit_flash)
	draw_circle(Vector2.ZERO, body_radius, col)

	# i-frames read as a hard white ring - it must be unmistakable.
	if invuln > 0.0:
		draw_arc(Vector2.ZERO, body_radius + 5.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 3.0, true)
	if god_mode:
		draw_arc(Vector2.ZERO, body_radius + 10.0, 0.0, TAU, 32, Color(0.5, 1.0, 0.6, 0.6), 2.0, true)

	# Facing nub.
	draw_circle(facing * (body_radius + 6.0), 4.0, Color(1, 1, 1, 0.9))

	# Movement-lock ring: a full stop during a COMMIT cast is drawn, not implied.
	if state == State.CASTING and float(Tune.variant(cast_variant)["move_mult"]) <= 0.001:
		draw_arc(Vector2.ZERO, body_radius + 13.0, 0.0, TAU, 40, Color(vcol.r, vcol.g, vcol.b, 0.5), 2.0, true)

	_draw_cast_bar()
	_draw_dash_pips()


func _draw_cast_bar() -> void:
	if state != State.CASTING:
		return
	var w := 84.0
	var h := 8.0
	var top := Vector2(-w * 0.5, -body_radius - 30.0)
	draw_rect(Rect2(top, Vector2(w, h)), Color(0, 0, 0, 0.65))
	var fill: Color = Tune.COL_CASTBAR if cast_variant == Tune.VARIANT_COMMIT else Tune.COL_CASTBAR_FLOW
	draw_rect(Rect2(top, Vector2(w * cast_progress(), h)), fill)

	# The point past which dashing will no longer cancel.
	if Tune.CANCEL_LOCKOUT_TAIL > 0.0:
		var x := w * (1.0 - Tune.CANCEL_LOCKOUT_TAIL)
		draw_line(top + Vector2(x, -2.0), top + Vector2(x, h + 2.0), Tune.COL_WARN, 1.5)
	draw_rect(Rect2(top, Vector2(w, h)), Color(1, 1, 1, 0.3), false, 1.0)


func _draw_dash_pips() -> void:
	var pip_r := 3.5
	var gap := 12.0
	var total := gap * float(Tune.DASH_CHARGES - 1)
	var y := body_radius + 16.0
	for i in range(Tune.DASH_CHARGES):
		var p := Vector2(-total * 0.5 + gap * float(i), y)
		if i < dash_charges:
			draw_circle(p, pip_r, Color(0.65, 0.95, 1.0, 0.95))
		else:
			draw_circle(p, pip_r, Color(0.3, 0.35, 0.45, 0.8))
			# Partial arc on the charge currently refilling.
			if i == dash_charges and Tune.DASH_CHARGE_COOLDOWN > 0.0:
				var f := 1.0 - clampf(dash_recharge / Tune.DASH_CHARGE_COOLDOWN, 0.0, 1.0)
				draw_arc(p, pip_r + 2.0, -PI * 0.5, -PI * 0.5 + TAU * f, 16, Color(0.65, 0.95, 1.0, 0.8), 1.5, true)
