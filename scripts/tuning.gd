class_name Tune
## SINGLE SOURCE OF TRUTH FOR EVERY TUNABLE NUMBER.
##
## Nothing in this prototype should hardcode a timing, damage, radius, speed or
## cooldown. If you want to change how the game feels, you change it here and
## nowhere else. Scenes contain no numbers; nodes are built in code from these.
##
## Sections:
##   ARENA        - playfield geometry
##   PLAYER       - movement, dash, health
##   VARIANTS     - the Commit / Flow comparison (the point of the prototype)
##   SKILLS       - the 1-6 hotbar
##   DUMMY        - step-1 practice target
##   FEEL         - hitstop, shake, floaters
##   PALETTE      - colors


# ============================================================================
# ARENA
# ============================================================================

const ARENA_CENTER := Vector2(800.0, 470.0)
const ARENA_RADIUS := 400.0
## Player is clamped to ARENA_RADIUS - this, so the circle stays readable.
const ARENA_EDGE_PAD := 14.0


# ============================================================================
# PLAYER
# ============================================================================

const PLAYER_RADIUS := 14.0
const PLAYER_MAX_HP := 1000.0
const PLAYER_MOVE_SPEED := 340.0
## Seconds to reach full speed / full stop. 0.0 = instant, snappy. Raise for weight.
const PLAYER_ACCEL_TIME := 0.055
const PLAYER_DECEL_TIME := 0.045

## --- Dash (skill 6) -------------------------------------------------------
const DASH_DISTANCE := 210.0
## How long the movement itself takes. Shorter = snappier, harder to read.
const DASH_DURATION := 0.16
## Invulnerability window, starts the frame the dash starts.
const DASH_IFRAMES := 0.30
const DASH_CHARGES := 2
const DASH_CHARGE_COOLDOWN := 7.0
## Brief lockout after a dash before you may act again. 0.0 = fully free.
const DASH_END_LAG := 0.04
## Dash aims at the WASD input direction; if no keys held, uses mouse direction.
const DASH_USES_MOUSE_WHEN_IDLE := true

## --- Cast cancelling ------------------------------------------------------
## THE IMPORTANT TRADEOFF. Dashing cancels a cast, but the skill still goes on
## cooldown. 1.0 = full cooldown paid for nothing (harshest, most committal).
## 0.5 = half. 0.0 = free cancel (no commitment at all - try it to feel the
## difference, the fight should get noticeably worse).
const CANCEL_COOLDOWN_FRACTION := 1.0
## Can you cancel a cast in its final moments? Below this fraction remaining,
## the cast is locked in and the dash input is dropped. 0.0 = always cancellable.
const CANCEL_LOCKOUT_TAIL := 0.0

## Recovery after a completed cast before the next action. Lost-Ark-ish combat
## has no global cooldown, so keep this small; it exists only to stop 1-frame
## skill chaining from feeling soupy.
const CAST_RECOVERY := 0.08
## Holding a skill key re-fires it the moment it comes off cooldown.
const ALLOW_HOLD_TO_REPEAT := true
## An input pressed this many seconds before you're free will still fire.
const INPUT_BUFFER := 0.18


# ============================================================================
# VARIANTS - the A/B comparison. Toggle live with TAB.
# ============================================================================

const VARIANT_COMMIT := 0
const VARIANT_FLOW := 1

## move_mult    : movement speed multiplier WHILE casting (0.0 = full lock)
## damage_mult  : scales all skill damage
## cast_mult    : scales cast times on top of the per-skill values below
## aim_locks    : true  = facing is captured when the cast STARTS (committal)
##                false = facing keeps tracking the mouse until the cast lands
## turn_locked  : true  = the body cannot even rotate during the cast
const VARIANTS := [
	{
		"name": "COMMIT",
		"move_mult": 0.0,
		"damage_mult": 1.0,
		"cast_mult": 1.0,
		"aim_locks": true,
		"turn_locked": true,
		"color": Color(1.0, 0.55, 0.25),
	},
	{
		"name": "FLOW",
		"move_mult": 0.55,
		"damage_mult": 0.44,
		"cast_mult": 1.0,
		"aim_locks": false,
		"turn_locked": false,
		"color": Color(0.35, 0.8, 1.0),
	},
]

const START_VARIANT := VARIANT_COMMIT


# ============================================================================
# SKILLS - hotbar 1-6
# ============================================================================
#
# cast_commit / cast_flow : cast time per variant, in seconds. Given explicitly
#   rather than as one global multiplier so each skill's feel can be tuned
#   independently (Commit 0.8-1.6s, Flow 0.2-0.5s).
# dmg_commit / dmg_flow   : damage per cast, before VARIANTS.damage_mult.
# kind: "bolt"          - travelling projectile toward aim
#       "aoe_at_mouse"  - circle placed at the cursor, resolves after a delay
#       "rect_ahead"    - rectangle from the player along aim
#       "dash"          - handled by the dash code, not a cast

const SKILL_COUNT := 6

const SKILLS := [
	{   # 1 - fast filler
		"name": "EMBERBOLT",
		"kind": "bolt",
		"cast_commit": 0.80,
		"cast_flow": 0.24,
		"dmg_commit": 105.0,
		"dmg_flow": 105.0,
		"cooldown": 4.0,
		"stagger": 6.0,
		"is_counter": false,
		"bolt_speed": 1250.0,
		"bolt_radius": 9.0,
		"bolt_range": 900.0,
		"color": Color(1.0, 0.72, 0.32),
	},
	{   # 2 - medium AoE
		"name": "CINDER BLOOM",
		"kind": "aoe_at_mouse",
		"cast_commit": 1.10,
		"cast_flow": 0.34,
		"dmg_commit": 175.0,
		"dmg_flow": 175.0,
		"cooldown": 10.0,
		"stagger": 12.0,
		"is_counter": false,
		"radius": 105.0,
		## Delay between the cast finishing and the hitbox going live.
		"impact_delay": 0.30,
		"max_cast_range": 520.0,
		"color": Color(1.0, 0.45, 0.30),
	},
	{   # 3 - nuke, longest cast
		"name": "VOIDLANCE",
		"kind": "bolt",
		"cast_commit": 1.60,
		"cast_flow": 0.50,
		"dmg_commit": 460.0,
		"dmg_flow": 460.0,
		"cooldown": 24.0,
		"stagger": 20.0,
		"is_counter": false,
		"bolt_speed": 1700.0,
		"bolt_radius": 18.0,
		"bolt_range": 1100.0,
		"color": Color(0.72, 0.45, 1.0),
	},
	{   # 4 - COUNTER
		"name": "RIPOSTE",
		"kind": "bolt",
		"cast_commit": 0.35,
		"cast_flow": 0.20,
		"dmg_commit": 45.0,
		"dmg_flow": 45.0,
		"cooldown": 9.0,
		"stagger": 4.0,
		"is_counter": true,
		"bolt_speed": 1900.0,
		"bolt_radius": 12.0,
		"bolt_range": 620.0,
		"color": Color(0.45, 1.0, 0.85),
	},
	{   # 5 - STAGGER
		"name": "SUNDER",
		"kind": "rect_ahead",
		"cast_commit": 0.90,
		"cast_flow": 0.30,
		"dmg_commit": 70.0,
		"dmg_flow": 70.0,
		"cooldown": 18.0,
		"stagger": 220.0,
		"is_counter": false,
		"length": 240.0,
		"half_width": 62.0,
		"impact_delay": 0.06,
		"color": Color(1.0, 0.90, 0.45),
	},
	{   # 6 - MOBILITY (dash constants live in the PLAYER section above)
		"name": "BLINK",
		"kind": "dash",
		"cast_commit": 0.0,
		"cast_flow": 0.0,
		"dmg_commit": 0.0,
		"dmg_flow": 0.0,
		"cooldown": DASH_CHARGE_COOLDOWN,
		"stagger": 0.0,
		"is_counter": false,
		"color": Color(0.65, 0.95, 1.0),
	},
]


# ============================================================================
# DUMMY TARGET (step 1 only - replaced by the Warden in step 2)
# ============================================================================

const DUMMY_RADIUS := 62.0
const DUMMY_MAX_HP := 100000.0
const DUMMY_STAGGER_MAX := 1000.0
## Stagger decays back down this fast when not being hit.
const DUMMY_STAGGER_DECAY := 40.0
const DUMMY_STAGGER_RESET_DELAY := 2.0


# ============================================================================
# FEEL - juice. Cheap to turn off if it's masking a bad core.
# ============================================================================

## Frames of frozen time on a hit landing. 0.0 disables.
const HITSTOP_NORMAL := 0.035
const HITSTOP_HEAVY := 0.09
## Damage above this counts as heavy.
const HITSTOP_HEAVY_THRESHOLD := 300.0

const SHAKE_ON_CAST := 1.5
const SHAKE_ON_HIT := 3.0
const SHAKE_DECAY := 9.0

const FLOATER_RISE := 46.0
const FLOATER_LIFETIME := 0.75

## Telegraph fill sweep: how much of the wind-up is spent filling. 1.0 = the
## fill reaches the edge exactly as the hitbox goes live.
const TELEGRAPH_FILL_RATIO := 1.0
const TELEGRAPH_ACTIVE_FLASH := 0.10
const TELEGRAPH_FADE := 0.14


# ============================================================================
# PALETTE
# ============================================================================

const COL_BG := Color(0.06, 0.065, 0.08)
const COL_ARENA_FLOOR := Color(0.105, 0.115, 0.145)
const COL_ARENA_EDGE := Color(0.28, 0.31, 0.40)
const COL_PLAYER := Color(0.55, 0.88, 1.0)
const COL_PLAYER_IFRAME := Color(1.0, 1.0, 1.0)
const COL_DUMMY := Color(0.55, 0.30, 0.38)
const COL_HP := Color(0.85, 0.25, 0.30)
const COL_STAGGER := Color(1.0, 0.82, 0.30)
const COL_CASTBAR := Color(1.0, 0.85, 0.45)
const COL_CASTBAR_FLOW := Color(0.45, 0.85, 1.0)
const COL_TEXT := Color(0.86, 0.89, 0.95)
const COL_TEXT_DIM := Color(0.50, 0.55, 0.65)
const COL_WARN := Color(1.0, 0.35, 0.35)


# ============================================================================
# HELPERS
# ============================================================================

static func variant(idx: int) -> Dictionary:
	return VARIANTS[idx]

static func skill(idx: int) -> Dictionary:
	return SKILLS[idx]

## Cast time for a skill under a variant, with the variant multiplier applied.
static func cast_time(skill_idx: int, variant_idx: int) -> float:
	var s: Dictionary = SKILLS[skill_idx]
	var base: float = s["cast_commit"] if variant_idx == VARIANT_COMMIT else s["cast_flow"]
	return base * float(VARIANTS[variant_idx]["cast_mult"])

## Damage for a skill under a variant, with the variant multiplier applied.
static func damage(skill_idx: int, variant_idx: int) -> float:
	var s: Dictionary = SKILLS[skill_idx]
	var base: float = s["dmg_commit"] if variant_idx == VARIANT_COMMIT else s["dmg_flow"]
	return base * float(VARIANTS[variant_idx]["damage_mult"])
