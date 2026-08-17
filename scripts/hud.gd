class_name Hud
extends Control
## Debug readout + hotbar. Drawn immediately rather than built from nodes so
## that adding a line in step 5 is one line of code, not a scene edit.

var player: Player
var dummy: Dummy
## Run time in seconds, pushed in by the Arena each frame. Held as a plain float
## rather than an Arena reference so the HUD doesn't depend on the Arena class.
var elapsed: float = 0.0

var _font: Font
## Rolling [timestamp, amount] pairs for the DPS window.
var _dmg_log: Array = []
var _total_damage: float = 0.0

const DPS_WINDOW := 5.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	Events.damage_dealt.connect(_on_damage)


## Layout is driven off the viewport rather than Control.size: this HUD is
## drawn immediately rather than laid out, and size isn't reliably populated
## before the first draw.
func _vp() -> Vector2:
	return get_viewport_rect().size


func _on_damage(amount: float, _at: Vector2, _skill_idx: int) -> void:
	_dmg_log.append([elapsed, amount])
	_total_damage += amount


func reset() -> void:
	_dmg_log.clear()
	_total_damage = 0.0
	elapsed = 0.0


func dps() -> float:
	var t := elapsed
	while _dmg_log.size() > 0 and t - float(_dmg_log[0][0]) > DPS_WINDOW:
		_dmg_log.pop_front()
	if _dmg_log.is_empty():
		return 0.0
	var sum := 0.0
	for e in _dmg_log:
		sum += float(e[1])
	return sum / minf(DPS_WINDOW, maxf(t, 0.25))


func total_dps() -> float:
	return _total_damage / maxf(elapsed, 0.25)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or _font == null:
		return
	_draw_readout()
	_draw_variant_banner()
	_draw_hotbar()
	_draw_player_hp()
	_draw_hints()


func _text(pos: Vector2, s: String, c: Color, sz: int = 14) -> void:
	draw_string(_font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.7))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)


func _text_center(cx: float, y: float, s: String, c: Color, sz: int) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_text(Vector2(cx - w * 0.5, y), s, c, sz)


func _draw_readout() -> void:
	var x := 18.0
	var y := 28.0
	var line := 19.0
	_text(Vector2(x, y), "ELAPSED   %6.2fs" % elapsed, Tune.COL_TEXT)
	y += line
	_text(Vector2(x, y), "DPS (%ds)  %6.0f" % [int(DPS_WINDOW), dps()], Tune.COL_TEXT)
	y += line
	_text(Vector2(x, y), "DPS (avg)  %6.0f" % total_dps(), Tune.COL_TEXT_DIM)
	y += line
	_text(Vector2(x, y), "DAMAGE    %8.0f" % _total_damage, Tune.COL_TEXT_DIM)
	y += line + 6.0

	var st: String = ["FREE", "CASTING", "DASHING"][player.state]
	var st_col: Color = Tune.COL_TEXT_DIM if player.state == Player.State.FREE else Tune.COL_CASTBAR
	_text(Vector2(x, y), "PLAYER    %s" % st, st_col)
	y += line
	if player.state == Player.State.CASTING:
		var s := Tune.skill(player.cast_idx)
		_text(Vector2(x, y), "  %s  %.2f / %.2fs" % [s["name"], player.cast_elapsed, player.cast_total], Tune.COL_CASTBAR)
		y += line
	if player.invuln > 0.0:
		_text(Vector2(x, y), "  I-FRAMES %.2fs" % player.invuln, Color(0.6, 1.0, 0.8))
		y += line

	if dummy != null:
		y += 6.0
		_text(Vector2(x, y), "TARGET STAGGER  %d / %d" % [roundi(dummy.stagger), roundi(Tune.DUMMY_STAGGER_MAX)],
			Tune.COL_STAGGER)


func _draw_variant_banner() -> void:
	var v := player.variant()
	var cx := _vp().x * 0.5
	_text_center(cx, 34.0, "VARIANT: %s" % String(v["name"]), v["color"], 24)
	var sub := "full move lock  -  long casts  -  high damage per cast"
	if player.variant_idx == Tune.VARIANT_FLOW:
		sub = "moves at %d%% while casting  -  short casts  -  %d%% damage" % [
			roundi(float(v["move_mult"]) * 100.0), roundi(float(v["damage_mult"]) * 100.0)]
	_text_center(cx, 54.0, sub, Tune.COL_TEXT_DIM, 13)
	_text_center(cx, 74.0, "[TAB] switch variant", Tune.COL_TEXT_DIM, 12)


func _draw_hotbar() -> void:
	var n := Tune.SKILL_COUNT
	var bw := 96.0
	var bh := 54.0
	var gap := 8.0
	var total := float(n) * bw + float(n - 1) * gap
	var vp := _vp()
	var x0 := vp.x * 0.5 - total * 0.5
	var y0 := vp.y - bh - 26.0

	for i in range(n):
		var s := Tune.skill(i)
		var r := Rect2(Vector2(x0 + float(i) * (bw + gap), y0), Vector2(bw, bh))
		var is_dash: bool = String(s["kind"]) == "dash"
		var ready := true
		var frac := 0.0
		var label := ""

		if is_dash:
			ready = player.dash_charges > 0
			frac = 0.0 if player.dash_charges >= Tune.DASH_CHARGES else clampf(player.dash_recharge / Tune.DASH_CHARGE_COOLDOWN, 0.0, 1.0)
			label = "x%d" % player.dash_charges
		else:
			var cd: float = player.cooldowns[i]
			ready = cd <= 0.0
			frac = clampf(cd / maxf(float(s["cooldown"]), 0.0001), 0.0, 1.0)
			label = "" if ready else "%.1f" % cd

		draw_rect(r, Color(0.10, 0.11, 0.14, 0.92))
		# Cooldown drains from the top down.
		if frac > 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * frac)), Color(0, 0, 0, 0.55))
		var border: Color = Color(s["color"]) if ready else Color(0.30, 0.33, 0.40)
		if player.state == Player.State.CASTING and player.cast_idx == i:
			border = Color.WHITE
		draw_rect(r, border, false, 2.0)

		_text(r.position + Vector2(6, 16), "%d" % (i + 1), Tune.COL_TEXT_DIM, 12)
		_text(r.position + Vector2(6, 32), String(s["name"]).substr(0, 12), border, 12)

		var meta := ""
		if is_dash:
			meta = "%.2fs iframe" % Tune.DASH_IFRAMES
		else:
			meta = "%.2fs cast" % Tune.cast_time(i, player.variant_idx)
		_text(r.position + Vector2(6, 47), meta, Tune.COL_TEXT_DIM, 11)

		if label != "":
			var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			_text(r.position + Vector2(r.size.x - lw - 6, 20), label, Tune.COL_TEXT, 18)

		if bool(s["is_counter"]):
			_text(r.position + Vector2(r.size.x - 16, 47), "C", Color(0.45, 1.0, 0.85), 12)
		if float(s["stagger"]) >= 50.0:
			_text(r.position + Vector2(r.size.x - 28, 47), "S", Tune.COL_STAGGER, 12)


func _draw_player_hp() -> void:
	var w := 260.0
	var h := 12.0
	var vp := _vp()
	var pos := Vector2(vp.x * 0.5 - w * 0.5, vp.y - 100.0)
	draw_rect(Rect2(pos, Vector2(w, h)), Color(0, 0, 0, 0.6))
	var f := player.hp / Tune.PLAYER_MAX_HP
	draw_rect(Rect2(pos, Vector2(w * f, h)), Tune.COL_HP)
	draw_rect(Rect2(pos, Vector2(w, h)), Color(1, 1, 1, 0.25), false, 1.0)
	_text_center(vp.x * 0.5, pos.y - 4.0, "%d / %d" % [roundi(player.hp), roundi(Tune.PLAYER_MAX_HP)], Tune.COL_TEXT_DIM, 12)


func _draw_hints() -> void:
	var vp := _vp()
	var y := vp.y - 22.0
	_text(Vector2(18.0, y), "WASD move   MOUSE aim   1-6 skills   SPACE dash   TAB variant   R restart", Tune.COL_TEXT_DIM, 13)
	var cancel_txt := "dash-cancel pays %d%% cooldown" % roundi(Tune.CANCEL_COOLDOWN_FRACTION * 100.0)
	var w := _font.get_string_size(cancel_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(Vector2(vp.x - w - 18.0, y), cancel_txt, Tune.COL_TEXT_DIM, 13)
