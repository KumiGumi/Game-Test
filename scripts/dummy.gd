class_name Dummy
extends Hostile
## Step-1 practice target. It does not attack, does not move and does not die.
## It exists so movement, animation lock and the cast variants can be judged in
## isolation before there is a boss to react to.

var hp: float = Tune.DUMMY_MAX_HP
var stagger: float = 0.0
var total_taken: float = 0.0

var _stagger_hold: float = 0.0
var _staggered_flash: float = 0.0
var _hit_flash: float = 0.0
var _font: Font


func _ready() -> void:
	super._ready()
	z_index = 1
	body_radius = Tune.DUMMY_RADIUS
	_font = ThemeDB.fallback_font


func apply_hit(damage: float, stagger_value: float, skill_idx: int, is_counter: bool) -> void:
	if damage > 0.0:
		hp = maxf(0.0, hp - damage)
		total_taken += damage
		_hit_flash = 1.0
		Events.damage_dealt.emit(damage, global_position, skill_idx)
		var col: Color = Tune.SKILLS[skill_idx]["color"] if skill_idx >= 0 else Color.WHITE
		Floater.spawn(get_parent(), global_position + Vector2(randf_range(-30, 30), -body_radius * 0.6),
			str(roundi(damage)), col, 20 if damage >= Tune.HITSTOP_HEAVY_THRESHOLD else 16)
		var heavy := damage >= Tune.HITSTOP_HEAVY_THRESHOLD
		Events.hitstop_requested.emit(Tune.HITSTOP_HEAVY if heavy else Tune.HITSTOP_NORMAL)

	if stagger_value > 0.0:
		stagger = minf(Tune.DUMMY_STAGGER_MAX, stagger + stagger_value)
		_stagger_hold = Tune.DUMMY_STAGGER_RESET_DELAY
		Events.stagger_dealt.emit(stagger_value, global_position)
		if stagger_value >= 50.0:
			Floater.spawn(get_parent(), global_position + Vector2(randf_range(-20, 20), -body_radius - 26.0),
				"STAGGER +%d" % roundi(stagger_value), Tune.COL_STAGGER, 15)
		if stagger >= Tune.DUMMY_STAGGER_MAX:
			_on_stagger_full()

	if is_counter:
		# The dummy never opens a counter window - the Warden will, in step 3.
		Events.counter_landed.emit(false, global_position)


func _on_stagger_full() -> void:
	stagger = 0.0
	_staggered_flash = 1.0
	Floater.spawn(get_parent(), global_position + Vector2(0, -body_radius - 46.0), "STAGGERED", Color(1, 1, 1), 26)
	FxRing.pop(get_parent(), global_position, body_radius, body_radius + 130.0, Tune.COL_STAGGER, 0.45)
	Events.shake_requested.emit(6.0)


func reset() -> void:
	hp = Tune.DUMMY_MAX_HP
	stagger = 0.0
	total_taken = 0.0


func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta * 7.0)
	_staggered_flash = maxf(0.0, _staggered_flash - delta * 2.2)
	if _stagger_hold > 0.0:
		_stagger_hold -= delta
	elif stagger > 0.0:
		stagger = maxf(0.0, stagger - Tune.DUMMY_STAGGER_DECAY * delta)
	queue_redraw()


func _draw() -> void:
	var base := Tune.COL_DUMMY.lerp(Color.WHITE, _hit_flash * 0.5)
	draw_circle(Vector2.ZERO, body_radius, base)
	draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	if _staggered_flash > 0.0:
		draw_arc(Vector2.ZERO, body_radius + 8.0, 0.0, TAU, 48,
			Color(Tune.COL_STAGGER.r, Tune.COL_STAGGER.g, Tune.COL_STAGGER.b, _staggered_flash), 5.0, true)

	# Stagger bar above the body.
	var w := body_radius * 2.4
	var top := Vector2(-w * 0.5, -body_radius - 20.0)
	draw_rect(Rect2(top, Vector2(w, 9.0)), Color(0, 0, 0, 0.55))
	var f := stagger / Tune.DUMMY_STAGGER_MAX
	if f > 0.0:
		draw_rect(Rect2(top, Vector2(w * f, 9.0)), Tune.COL_STAGGER)
	draw_rect(Rect2(top, Vector2(w, 9.0)), Color(1, 1, 1, 0.25), false, 1.0)

	if _font != null:
		draw_string(_font, Vector2(-w * 0.5, -body_radius - 26.0), "TARGET",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tune.COL_TEXT_DIM)
