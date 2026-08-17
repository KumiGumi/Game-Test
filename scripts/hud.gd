class_name Hud
extends Control
## Debug readout, hotbar and the Overheat meter. Drawn immediately rather than
## built from nodes, so adding a line in the step-5 tooling pass is one line of
## code and not a scene edit.

var player: Player
var dummy: Dummy
## Run time in seconds, pushed in by the Arena each frame. A plain float rather
## than an Arena reference, so the HUD doesn't depend on the Arena class.
var elapsed: float = 0.0

var _font: Font
## Rolling [timestamp, amount] pairs for the DPS window.
var _dmg_log: Array = []
var _total_damage: float = 0.0
var _identity_flash: float = 0.0

const DPS_WINDOW := 5.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	Events.damage_dealt.connect(_on_damage)
	Events.identity_full.connect(func() -> void: _identity_flash = 1.0)


## Layout is driven off the viewport rather than Control.size: this HUD is drawn
## immediately, and size isn't reliably populated before the first draw.
func _vp() -> Vector2:
	return get_viewport_rect().size


func _on_damage(amount: float, _at: Vector2, _idx: int) -> void:
	_dmg_log.append([elapsed, amount])
	_total_damage += amount


func reset() -> void:
	_dmg_log.clear()
	_total_damage = 0.0
	elapsed = 0.0


func dps() -> float:
	while _dmg_log.size() > 0 and elapsed - float(_dmg_log[0][0]) > DPS_WINDOW:
		_dmg_log.pop_front()
	if _dmg_log.is_empty():
		return 0.0
	var sum := 0.0
	for e in _dmg_log:
		sum += float(e[1])
	return sum / minf(DPS_WINDOW, maxf(elapsed, 0.25))


func total_dps() -> float:
	return _total_damage / maxf(elapsed, 0.25)


func _process(delta: float) -> void:
	_identity_flash = maxf(0.0, _identity_flash - delta * 1.5)
	queue_redraw()


func _draw() -> void:
	if player == null or _font == null:
		return
	_draw_readout()
	_draw_variant_banner()
	_draw_identity()
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
	_text(Vector2(x, y), "DAMAGE   %9.0f" % _total_damage, Tune.COL_TEXT_DIM)
	y += line + 6.0

	var st: String = ["FREE", "ACTING", "DASHING"][player.state]
	var st_col: Color = Tune.COL_TEXT_DIM if player.state == Player.State.FREE else Tune.COL_CASTBAR
	_text(Vector2(x, y), "PLAYER    %s" % st, st_col)
	y += line
	if player.state == Player.State.ACTING and player.act_total > 0.0:
		var nm: String = String(Tune.action(player.act_idx)["name"])
		_text(Vector2(x, y), "  %s  %.2f / %.2fs" % [nm, player.act_elapsed, player.act_total], Tune.COL_CASTBAR)
		y += line
	if player.invuln > 0.0:
		_text(Vector2(x, y), "  I-FRAMES %.2fs" % player.invuln, Color(0.6, 1.0, 0.8))
		y += line
	if player.is_overheated():
		_text(Vector2(x, y), "  OVERHEAT %.1fs" % player.overheat, Tune.COL_IDENTITY)
		y += line
	_text(Vector2(x, y), "  auto chain  %d / %d" % [player.auto_step + 1, Tune.AUTO["cast_times"].size()],
		Tune.COL_TEXT_DIM, 13)
	y += line + 6.0

	if dummy != null:
		_text(Vector2(x, y), "TARGET STAGGER  %d / %d" % [roundi(dummy.stagger), roundi(Tune.DUMMY_STAGGER_MAX)],
			Tune.COL_STAGGER)


func _draw_variant_banner() -> void:
	var v := player.variant()
	var cx := _vp().x * 0.5
	_text_center(cx, 30.0, "VARIANT: %s" % String(v["name"]), v["color"], 22)
	var sub := "casts root you completely  -  aim locks at cast start"
	if player.variant_idx == Tune.VARIANT_FLOW:
		sub = "move at %d%% while casting  -  aim tracks  -  %d%% cast damage" % [
			roundi(float(v["move_mult"]) * 100.0), roundi(float(v["damage_mult"]) * 100.0)]
	_text_center(cx, 50.0, sub, Tune.COL_TEXT_DIM, 13)


## The Overheat meter. Given real estate because the whole loop is: fill it with
## autos and multi-hits, then spend it to make the committed casts cheap.
func _draw_identity() -> void:
	var vp := _vp()
	var w := 420.0
	var h := 16.0
	var pos := Vector2(vp.x * 0.5 - w * 0.5, vp.y - 168.0)
	var f := player.identity / Tune.IDENTITY_MAX
	var full := f >= 1.0

	draw_rect(Rect2(pos, Vector2(w, h)), Color(0, 0, 0, 0.65))
	if player.is_overheated():
		# During the window the bar drains as the timer runs out.
		var t := player.overheat / maxf(Tune.IDENTITY_DURATION, 0.0001)
		draw_rect(Rect2(pos, Vector2(w * t, h)), Tune.COL_IDENTITY)
		_text_center(vp.x * 0.5, pos.y - 4.0, "OVERHEAT  %.1fs" % player.overheat, Tune.COL_IDENTITY, 15)
	else:
		draw_rect(Rect2(pos, Vector2(w * f, h)), Tune.COL_IDENTITY.darkened(0.15 if full else 0.45))
		var label := "OVERHEAT READY  [F]" if full else "OVERHEAT  %d%%" % roundi(f * 100.0)
		var col: Color = Tune.COL_IDENTITY if full else Tune.COL_TEXT_DIM
		if full:
			# Pulse so a ready burst window is impossible to miss mid-fight.
			var pulse := 0.5 + 0.5 * sin(elapsed * 8.0)
			draw_rect(Rect2(pos - Vector2(2, 2), Vector2(w + 4, h + 4)),
				Color(1, 1, 1, 0.25 + 0.45 * pulse), false, 2.0)
		_text_center(vp.x * 0.5, pos.y - 4.0, label, col, 15)
	draw_rect(Rect2(pos, Vector2(w, h)), Color(1, 1, 1, 0.25), false, 1.0)


func _draw_hotbar() -> void:
	var vp := _vp()
	# RMB auto, four skills, dash, identity.
	var slots := 3 + Tune.SKILL_COUNT
	var bw := 96.0
	var bh := 54.0
	var gap := 8.0
	var total := float(slots) * bw + float(slots - 1) * gap
	var x0 := vp.x * 0.5 - total * 0.5
	var y0 := vp.y - bh - 26.0

	for i in range(slots):
		var r := Rect2(Vector2(x0 + float(i) * (bw + gap), y0), Vector2(bw, bh))
		if i == 0:
			_draw_slot(r, "RMB", String(Tune.AUTO["name"]), Tune.AUTO["color"], true, 0.0,
				"chain %d/%d" % [player.auto_step + 1, Tune.AUTO["cast_times"].size()],
				"", player.state == Player.State.ACTING and player.act_idx == Tune.AUTO_ACTION)
		elif i <= Tune.SKILL_COUNT:
			var idx := i - 1
			var s := Tune.skill(idx)
			var cd: float = player.cooldowns[idx]
			var ready := cd <= 0.0
			var ct := Tune.cast_time(idx, player.variant_idx, player.is_overheated())
			var meta := "instant" if ct <= 0.0 else "%.2fs cast" % ct
			_draw_slot(r, str(idx + 1), String(s["name"]), s["color"], ready,
				clampf(cd / maxf(float(s["cooldown"]), 0.0001), 0.0, 1.0),
				meta, "" if ready else "%.1f" % cd,
				player.state == Player.State.ACTING and player.act_idx == idx)
			if bool(s["is_counter"]):
				_text(r.position + Vector2(r.size.x - 15, 47), "C", Color(0.45, 1.0, 0.85), 12)
		elif i == Tune.SKILL_COUNT + 1:
			var frac := 0.0 if player.dash_charges >= Tune.DASH_CHARGES \
				else clampf(player.dash_recharge / Tune.DASH_CHARGE_COOLDOWN, 0.0, 1.0)
			_draw_slot(r, "SPC", "DASH", Color(0.65, 0.95, 1.0), player.dash_charges > 0, frac,
				"%.2fs iframe" % Tune.DASH_IFRAMES, "x%d" % player.dash_charges, false)
		else:
			var full := player.identity >= Tune.IDENTITY_MAX
			var active := player.is_overheated()
			_draw_slot(r, "F", "OVERHEAT", Tune.COL_IDENTITY, full or active,
				0.0 if (full or active) else 1.0 - player.identity / Tune.IDENTITY_MAX,
				"%.0fs burst" % Tune.IDENTITY_DURATION,
				"%.1f" % player.overheat if active else ("!" if full else ""), active)


func _draw_slot(r: Rect2, key: String, name: String, col: Color, ready: bool,
		cd_frac: float, meta: String, label: String, casting: bool) -> void:
	draw_rect(r, Color(0.10, 0.11, 0.14, 0.92))
	# Cooldown drains from the top down.
	if cd_frac > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * cd_frac)), Color(0, 0, 0, 0.58))
	var border: Color = col if ready else Color(0.30, 0.33, 0.40)
	if casting:
		border = Color.WHITE
	draw_rect(r, border, false, 2.0)

	_text(r.position + Vector2(6, 16), key, Tune.COL_TEXT_DIM, 12)
	_text(r.position + Vector2(6, 32), name.substr(0, 12), border, 12)
	_text(r.position + Vector2(6, 47), meta, Tune.COL_TEXT_DIM, 11)
	if label != "":
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_text(r.position + Vector2(r.size.x - lw - 6, 20), label, Tune.COL_TEXT, 18)


func _draw_player_hp() -> void:
	var vp := _vp()
	var w := 260.0
	var h := 12.0
	var pos := Vector2(vp.x * 0.5 - w * 0.5, vp.y - 140.0)
	draw_rect(Rect2(pos, Vector2(w, h)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(pos, Vector2(w * (player.hp / Tune.PLAYER_MAX_HP), h)), Tune.COL_HP)
	draw_rect(Rect2(pos, Vector2(w, h)), Color(1, 1, 1, 0.25), false, 1.0)


func _draw_hints() -> void:
	var vp := _vp()
	var y := vp.y - 8.0
	_text(Vector2(18.0, y), "WASD move   MOUSE aim   RMB auto   1-4 skills   SPACE dash   F overheat   TAB variant   F5 restart",
		Tune.COL_TEXT_DIM, 13)
	var cancel_txt := "dash-cancel pays %d%% cooldown" % roundi(Tune.CANCEL_COOLDOWN_FRACTION * 100.0)
	var w := _font.get_string_size(cancel_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(Vector2(vp.x - w - 18.0, y), cancel_txt, Tune.COL_TEXT_DIM, 13)
