class_name Telegraph
extends Node2D
## The wind-up -> active -> recovery lifecycle for exactly one AtkShape.
##
## A Telegraph knows how to show itself and when its hitbox is live. It does NOT
## know who it hurts - whoever spawned it connects to `activated` and resolves
## damage itself. One class serves both the boss's attacks and the player's
## skills, so every hitbox in the game passes through a single choke point.
##
## Telegraphs live in View.ground, which carries the vertical squash as a node
## scale. That means a circle drawn here becomes a ground ellipse for free,
## while the shape's own maths stays flat world space.
##
## Multi-hit: set `hits` > 1 and the ACTIVE phase pulses `activated` on an
## interval. Continuous effects (a rain that keeps raining, a channel that keeps
## ticking) are one telegraph, not many.

signal activated(shape: AtkShape, tg: Telegraph)
signal expired(tg: Telegraph)

enum State { DELAY, WINDUP, ACTIVE, FADE }

var shape: AtkShape

## Timings, in seconds.
var start_delay: float = 0.0
var windup: float = 1.0
var active: float = 0.12

## Pulse the hitbox this many times while active, spaced by hit_interval.
var hits: int = 1
var hit_interval: float = 0.0

## Visuals.
var tint: Color = Color(1.0, 0.25, 0.25)
var outline_width: float = 3.0
var visible_telegraph: bool = true
## Skip the wind-up fill sweep. Instant player skills want the shape to just
## appear rather than pretend to be a threat you could dodge.
var flash_only: bool = false

## If set, the shape's origin follows this actor's world position until
## `lock_at` of the wind-up has elapsed, then freezes.
var anchor: Actor = null
var anchor_offset: Vector2 = Vector2.ZERO
var lock_at: float = 0.0

## Called every frame during the wind-up as `hook.call(self, progress)`.
var update_hook: Callable = Callable()

var state: State = State.DELAY
var elapsed: float = 0.0
var _locked: bool = false
var _cancelled: bool = false
var _hits_done: int = 0
var _next_hit_at: float = 0.0

## True only on the frames the hitbox is live - the debug visualiser reads this.
var is_live: bool = false


## Spawns into the ground layer, which is where every hitbox belongs.
static func spawn(p_shape: AtkShape, p_windup: float, p_active: float, p_tint: Color) -> Telegraph:
	var tg := Telegraph.new()
	tg.shape = p_shape
	tg.windup = p_windup
	tg.active = p_active
	tg.tint = p_tint
	View.ground.add_child(tg)
	return tg


func _ready() -> void:
	z_index = -5
	# Always start in DELAY and let the first process tick fall through when
	# start_delay is 0. Deciding here instead would bake in whatever start_delay
	# was at add_child() time, silently ignoring a delay set afterwards - which
	# is exactly how a staggered rain collapses into one simultaneous hit.
	state = State.DELAY
	set_process(true)


## Abort without ever going live. Used when a pattern is interrupted.
func cancel() -> void:
	if _cancelled:
		return
	_cancelled = true
	is_live = false
	state = State.FADE
	elapsed = 0.0


func windup_progress() -> float:
	if state == State.DELAY:
		return 0.0
	if state != State.WINDUP:
		return 1.0
	return clampf(elapsed / maxf(windup, 0.0001), 0.0, 1.0)


## How long the ACTIVE phase actually lasts, accounting for multi-hit pulses.
func active_duration() -> float:
	return maxf(active, float(maxi(hits - 1, 0)) * hit_interval)


func _process(delta: float) -> void:
	elapsed += delta

	match state:
		State.DELAY:
			if elapsed >= start_delay:
				elapsed -= start_delay
				state = State.WINDUP
				_advance_windup()

		State.WINDUP:
			_advance_windup()
			if elapsed >= windup:
				_go_live()

		State.ACTIVE:
			while _hits_done < hits and elapsed >= _next_hit_at:
				_pulse()
			if elapsed >= active_duration():
				is_live = false
				state = State.FADE
				elapsed = 0.0

		State.FADE:
			if elapsed >= Tune.TELEGRAPH_FADE:
				expired.emit(self)
				queue_free()
				return

	queue_redraw()


func _advance_windup() -> void:
	var p := windup_progress()
	if anchor != null and is_instance_valid(anchor) and not _locked:
		if p >= lock_at:
			_locked = true
		else:
			shape.origin = anchor.world_pos + anchor_offset
	if update_hook.is_valid():
		update_hook.call(self, p)


func _go_live() -> void:
	state = State.ACTIVE
	elapsed = 0.0
	is_live = true
	_hits_done = 0
	_next_hit_at = 0.0
	_pulse()


func _pulse() -> void:
	_hits_done += 1
	_next_hit_at += hit_interval
	activated.emit(shape, self)


# ---------------------------------------------------------------------------
# DRAW
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not visible_telegraph or shape == null:
		return

	match state:
		State.DELAY:
			pass

		State.WINDUP:
			if flash_only:
				shape.draw_outline(self, Color(tint.r, tint.g, tint.b, 0.55), outline_width)
				return
			# Static boundary at full extent - readable from the first frame, so
			# the safe spot can be learned before the fill tells you the timing.
			shape.draw_fill(self, Color(tint.r, tint.g, tint.b, 0.10), 1.0)
			shape.draw_outline(self, Color(tint.r, tint.g, tint.b, 0.75), outline_width)
			var sweep := clampf(windup_progress() / maxf(Tune.TELEGRAPH_FILL_RATIO, 0.0001), 0.0, 1.0)
			shape.draw_fill(self, Color(tint.r, tint.g, tint.b, 0.30), sweep)

		State.ACTIVE:
			# Pulse brightness on each hit so multi-hit reads as multi-hit.
			var since := elapsed - maxf(_next_hit_at - hit_interval, 0.0)
			var flash := 1.0 - clampf(since / maxf(Tune.TELEGRAPH_ACTIVE_FLASH, 0.0001), 0.0, 1.0)
			shape.draw_fill(self, Color(tint.r, tint.g, tint.b, 0.22 + 0.45 * flash), 1.0)
			shape.draw_outline(self, Color(1, 1, 1, 0.6 + 0.35 * flash), outline_width + 1.0)

		State.FADE:
			var a := 1.0 - clampf(elapsed / maxf(Tune.TELEGRAPH_FADE, 0.0001), 0.0, 1.0)
			if not _cancelled:
				shape.draw_fill(self, Color(1, 1, 1, 0.22 * a), 1.0)
			shape.draw_outline(self, Color(tint.r, tint.g, tint.b, 0.5 * a), outline_width)
