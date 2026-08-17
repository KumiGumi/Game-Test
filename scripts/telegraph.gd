class_name Telegraph
extends Node2D
## The wind-up -> active -> recovery lifecycle for exactly one AtkShape.
##
## A Telegraph knows how to show itself and when its hitbox is live. It does NOT
## know who it hurts or for how much - whoever spawned it connects to
## `activated` and resolves damage itself. That keeps one class serving both the
## boss's attacks and the player's AoE skills, and it means every hitbox in the
## game passes through a single choke point (useful for the debug visualiser and
## for the phase-change wind-up speed multiplier).
##
## Multi-hit patterns are just several Telegraphs with staggered start delays.

signal activated(shape: AtkShape, tg: Telegraph)
signal expired(tg: Telegraph)

enum State { DELAY, WINDUP, ACTIVE, FADE }

var shape: AtkShape

## Timings, in seconds.
var start_delay: float = 0.0
var windup: float = 1.0
var active: float = 0.12

## Visuals.
var tint: Color = Color(1.0, 0.25, 0.25)
var outline_width: float = 2.5
## Draw the shape at all? Counter windows sometimes want an invisible hitbox.
var visible_telegraph: bool = true

## If set, the shape's origin follows this node until `lock_at` of the wind-up
## has elapsed, then freezes. Lets a cone track the boss and then commit.
var anchor: Node2D = null
var anchor_offset: Vector2 = Vector2.ZERO
## 0.0 = locks immediately, 1.0 = tracks right up to the hit.
var lock_at: float = 0.0

## Called every frame during the wind-up as `hook.call(self, progress)`.
## Used by expanding rings and other shapes that change while telegraphing.
var update_hook: Callable = Callable()

var state: State = State.DELAY
var elapsed: float = 0.0
var _locked: bool = false
var _cancelled: bool = false

## True only on the frames the hitbox is live - the debug visualiser reads this.
var is_live: bool = false


static func spawn(parent: Node, p_shape: AtkShape, p_windup: float, p_active: float, p_tint: Color) -> Telegraph:
	var tg := Telegraph.new()
	tg.shape = p_shape
	tg.windup = p_windup
	tg.active = p_active
	tg.tint = p_tint
	parent.add_child(tg)
	return tg


func _ready() -> void:
	z_index = -5
	state = State.DELAY if start_delay > 0.0 else State.WINDUP
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


func _process(delta: float) -> void:
	elapsed += delta

	match state:
		State.DELAY:
			if elapsed >= start_delay:
				elapsed -= start_delay
				state = State.WINDUP
				_advance_windup(0.0)

		State.WINDUP:
			_advance_windup(delta)
			if elapsed >= windup:
				_go_live()

		State.ACTIVE:
			if elapsed >= active:
				is_live = false
				state = State.FADE
				elapsed = 0.0

		State.FADE:
			if elapsed >= Tune.TELEGRAPH_FADE:
				expired.emit(self)
				queue_free()
				return

	queue_redraw()


func _advance_windup(_delta: float) -> void:
	var p := windup_progress()
	if anchor != null and is_instance_valid(anchor) and not _locked:
		if p >= lock_at:
			_locked = true
		else:
			shape.origin = anchor.global_position + anchor_offset
	if update_hook.is_valid():
		update_hook.call(self, p)


func _go_live() -> void:
	state = State.ACTIVE
	elapsed = 0.0
	is_live = true
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
			var p := windup_progress()
			# Static boundary at full extent - readable from frame one.
			shape.draw_fill(self, Color(tint.r, tint.g, tint.b, 0.10), 1.0)
			shape.draw_outline(self, Color(tint.r, tint.g, tint.b, 0.75), outline_width)
			# Sweeping fill communicates the timing.
			var sweep := clampf(p / maxf(Tune.TELEGRAPH_FILL_RATIO, 0.0001), 0.0, 1.0)
			shape.draw_fill(self, Color(tint.r, tint.g, tint.b, 0.30), sweep)

		State.ACTIVE:
			var flash := 1.0 - clampf(elapsed / maxf(Tune.TELEGRAPH_ACTIVE_FLASH, 0.0001), 0.0, 1.0)
			shape.draw_fill(self, Color(1.0, 1.0, 1.0, 0.35 + 0.45 * flash), 1.0)
			shape.draw_outline(self, Color(1.0, 1.0, 1.0, 0.95), outline_width + 1.5)

		State.FADE:
			var a := 1.0 - clampf(elapsed / maxf(Tune.TELEGRAPH_FADE, 0.0001), 0.0, 1.0)
			if not _cancelled:
				shape.draw_fill(self, Color(1.0, 1.0, 1.0, 0.25 * a), 1.0)
			shape.draw_outline(self, Color(tint.r, tint.g, tint.b, 0.5 * a), outline_width)
