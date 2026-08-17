class_name Tune
## SINGLE SOURCE OF TRUTH FOR EVERY TUNABLE NUMBER.
##
## Nothing in this prototype should hardcode a timing, damage, radius, speed or
## cooldown. Change how the game feels here and nowhere else. Scenes contain no
## numbers; nodes are built in code from these values.
##
## Sections:
##   VIEW      - the side-on camera projection
##   ARENA     - playfield geometry (WORLD space, flat 2D - see view.gd)
##   PLAYER    - movement, dash, health
##   ACTIONS   - cast queuing, cancelling, buffering
##   VARIANTS  - the Commit / Flow movement-lock comparison
##   AUTO      - right-click filler attack
##   SKILLS    - the 1-4 hotbar: 2 instants, 2 long casts
##   IDENTITY  - Overheat, the burst-window mode
##   WARDEN    - the boss: FSM timings and per-pattern numbers
##   FEEL      - hitstop, shake, floaters
##   PALETTE   - colors


# ============================================================================
# VIEW
# ============================================================================

## Vertical compression of the ground plane. 1.0 = straight top-down.
## Lower = flatter, more side-on. ~0.5-0.65 reads like a stage.
const VIEW_SQUASH := 0.58
## How far above its ground point a character's body is drawn.
const PLAYER_HEIGHT := 26.0
const WARDEN_HEIGHT := 74.0
## Projectiles fly at this height above the ground plane.
const BOLT_HEIGHT := 30.0


## LAYER DEPTHS. z_index is RELATIVE to the parent in Godot, so every layer is
## a direct child of a root sitting at z 0 and states its depth here. Getting
## this wrong is how telegraphs end up painted underneath the floor.
const Z_BACKDROP := -100
const Z_GROUND := -10
const Z_TELEGRAPH := -5


# ============================================================================
# ARENA - world space, flat 2D. y is DEPTH, not height.
# ============================================================================

const ARENA_CENTER := Vector2(800.0, 965.0)
## Half-extents. The arena is a rectangle; it projects to a wide, shallow stage.
const ARENA_HALF := Vector2(560.0, 350.0)
const ARENA_EDGE_PAD := 12.0

## Screen y the camera centres on. Tune to trade sky for floor.
const CAMERA_SCREEN_Y := 470.0


# ============================================================================
# PLAYER
# ============================================================================

const PLAYER_RADIUS := 15.0
const PLAYER_MAX_HP := 1000.0
const PLAYER_MOVE_SPEED := 350.0
const PLAYER_ACCEL_TIME := 0.055
const PLAYER_DECEL_TIME := 0.045
## Vertical movement is in DEPTH, so it covers less screen distance than
## horizontal. Raise above 1.0 to compensate and keep the stick feeling round.
const PLAYER_DEPTH_SPEED_MULT := 1.15

## --- Dash ---
const DASH_DISTANCE := 215.0
const DASH_DURATION := 0.16
const DASH_IFRAMES := 0.30
const DASH_CHARGES := 2
const DASH_CHARGE_COOLDOWN := 7.0
const DASH_END_LAG := 0.04
const DASH_USES_MOUSE_WHEN_IDLE := true


# ============================================================================
# ACTIONS - the commitment rules
# ============================================================================

## THE TRADEOFF. Dashing cancels a cast, but the skill still goes on cooldown.
## 1.0 = full cooldown paid for nothing. 0.0 = free cancel, no commitment.
## Auto attacks are never charged (they have no cooldown).
const CANCEL_COOLDOWN_FRACTION := 1.0
## Below this fraction of cast REMAINING, the cast is locked in and a dash input
## is dropped. 0.0 = always cancellable.
const CANCEL_LOCKOUT_TAIL := 0.0

## CAST QUEUING. Press the next skill during a cast and it fires the instant the
## current one finishes, with no gap - this is what makes the two long casts
## chain smoothly instead of feeling like two separate stops.
const CAST_QUEUE_ENABLED := true
## Earliest point in a cast at which the next action may be queued.
## 0.0 = queue any time. 0.5 = only in the back half.
const CAST_QUEUE_WINDOW := 0.0
## A queued action fires with this much gap. 0.0 = seamless.
const CAST_QUEUE_GAP := 0.0

## An input pressed this long before you're free still fires.
const INPUT_BUFFER := 0.20
## Holding a skill key re-fires it the moment it comes off cooldown.
const ALLOW_HOLD_TO_REPEAT := true


# ============================================================================
# VARIANTS - Commit / Flow. TAB toggles live.
# ============================================================================
#
# Now that the loadout is 2 instants + 2 casts + autos, the variants are only
# about what the CAST-TIME skills cost you. The instants are unaffected - they
# were never the commitment.
#
# move_mult    : movement speed while casting (0.0 = full lock)
# damage_mult  : damage multiplier on cast-time skills only
# cast_mult    : scales cast times
# aim_locks    : true = facing captured at cast START and held
# turn_locked  : true = the body cannot rotate during the cast

const VARIANT_COMMIT := 0
const VARIANT_FLOW := 1

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
		"move_mult": 0.50,
		"damage_mult": 0.70,
		"cast_mult": 0.55,
		"aim_locks": false,
		"turn_locked": false,
		"color": Color(0.35, 0.8, 1.0),
	},
]

const START_VARIANT := VARIANT_COMMIT


# ============================================================================
# AUTO ATTACK - right mouse button
# ============================================================================
#
# The filler. One press, one shot. No cooldown, no resource, no chain - it
# exists to fill the space between casts so the hands are never idle, and it is
# the main way the Overheat meter charges.

const AUTO := {
	"name": "STAFF",
	"kind": "auto",
	"cast_time": 0.26,
	"damage": 62.0,
	"stagger": 5.0,
	"recovery": 0.06,
	## Autos let you drift - they should never feel like a full stop.
	"move_mult": 0.45,
	"bolt_speed": 1500.0,
	"bolt_radius": 9.0,
	"bolt_range": 640.0,
	"color": Color(0.85, 0.90, 1.0),
}

## Holding RMB keeps firing. Set false for strictly one shot per click.
const AUTO_HOLD_REPEAT := true


# ============================================================================
# SKILLS - hotbar 1-4
# ============================================================================
#
# Two instants (low cooldown, multi-hit, usable as filler) and two long casts
# (the commitment, chained via queuing). Deliberately four keys.
#
# cast_time : 0.0 means instant. Variants scale this.
# recovery  : action lock AFTER the skill. Instant does not mean free.
# kind      : "rain"    - a zone that drops many small impacts over a duration
#             "counter" - instant strike in front, carries the counter flag
#             "bolt"    - travelling projectile
#             "meteor"  - delayed impact circle at the cursor

const SKILL_COUNT := 4

const SKILLS := [
	{   # 1 - INSTANT filler. Multi-hit: 8 impacts over 2.4s, damage streams out.
		"name": "FROSTFALL",
		"kind": "rain",
		"cast_time": 0.0,
		"recovery": 0.18,
		"cooldown": 6.0,
		"is_counter": false,
		## Zone the impacts land inside.
		"radius": 135.0,
		"max_cast_range": 500.0,
		"impacts": 8,
		"duration": 2.4,
		"impact_radius": 36.0,
		"impact_windup": 0.22,
		"dmg_per_impact": 32.0,
		"stagger_per_impact": 16.0,
		## Visual only: the shard that flies from the player to each impact.
		"shard_radius": 8.0,
		"color": Color(0.55, 0.85, 1.0),
	},
	{   # 2 - INSTANT counter. Must be instant: you cannot cast into a window.
		"name": "RIPOSTE",
		"kind": "counter",
		"cast_time": 0.0,
		"recovery": 0.22,
		"cooldown": 9.0,
		"is_counter": true,
		"length": 200.0,
		"half_width": 74.0,
		"impact_windup": 0.05,
		## How long the strike stays visible. Short enough to feel instant, long
		## enough to actually see.
		"flash_time": 0.20,
		"damage": 80.0,
		"stagger": 30.0,
		## Landed inside a boss counter window: damage multiplier and stun.
		"counter_damage_mult": 4.0,
		"counter_stun": 3.0,
		"color": Color(0.45, 1.0, 0.85),
	},
	{   # 3 - LONG CAST. Queue 4 during this and they chain seamlessly.
		"name": "EMBERLANCE",
		"kind": "bolt",
		"cast_time": 1.20,
		"recovery": 0.10,
		"cooldown": 10.0,
		"is_counter": false,
		"damage": 380.0,
		"stagger": 45.0,
		"bolt_speed": 1700.0,
		"bolt_radius": 17.0,
		"bolt_range": 1000.0,
		"color": Color(1.0, 0.62, 0.28),
	},
	{   # 4 - LONGEST CAST, biggest hit, the stagger burst.
		"name": "STARFALL",
		"kind": "meteor",
		"cast_time": 1.80,
		"recovery": 0.14,
		"cooldown": 24.0,
		"is_counter": false,
		"damage": 640.0,
		"stagger": 190.0,
		"radius": 175.0,
		"max_cast_range": 560.0,
		## Delay between the cast finishing and the rock landing.
		"impact_windup": 0.45,
		"color": Color(0.78, 0.45, 1.0),
	},
]


# ============================================================================
# IDENTITY - "OVERHEAT". The burst window.
# ============================================================================
#
# Fills from landing hits, so autos and the multi-hit rain are what charge it.
# At full, F converts the meter into a short window where everything comes off
# cooldown at once and casts get faster. This is the payoff loop that makes the
# committed casts worth their cost, and later it's what you save for a phase.

const IDENTITY_MAX := 100.0
## Gained per damage instance landed. Multi-hit skills charge fastest.
const IDENTITY_GAIN_PER_HIT := 3.2
## Extra for landing a cast-time skill, on top of the per-hit gain.
const IDENTITY_GAIN_PER_CAST := 8.0
const IDENTITY_DURATION := 10.0
## Wipes every skill cooldown the moment it activates.
const IDENTITY_RESETS_COOLDOWNS := true
const IDENTITY_CAST_MULT := 0.60
const IDENTITY_DAMAGE_MULT := 1.35
## Meter decays outside the window. 0.0 = never lose charge.
const IDENTITY_DECAY := 0.0


# ============================================================================
# THE WARDEN - boss
# ============================================================================
#
# Every attack runs WIND-UP -> ACTIVE -> RECOVERY. The wind-up is the whole
# game: it must be long enough to read, short enough to threaten. Between
# patterns the boss idles and repositions so the fight breathes instead of
# being a continuous wall.

const WARDEN_MAX_HP := 70000.0
const WARDEN_RADIUS := 62.0
const WARDEN_MOVE_SPEED := 155.0

const WARDEN_STAGGER_MAX := 1000.0
const WARDEN_STAGGER_DECAY := 45.0
const WARDEN_STAGGER_RESET_DELAY := 2.0

## The breathing beat between patterns.
const WARDEN_IDLE_MIN := 0.45
const WARDEN_IDLE_MAX := 1.00
const WARDEN_RECOVER_MIN := 0.70
const WARDEN_RECOVER_MAX := 1.30

## Chance of drifting to a new spot before the next pattern, and how long it
## may spend doing so. Repositioning is what stops the fight feeling static.
const WARDEN_REPOSITION_CHANCE := 0.6
const WARDEN_REPOSITION_MAX_TIME := 1.30
## It aims to sit about this far from the player.
const WARDEN_PREFERRED_DISTANCE := 280.0

## Global multiplier on every wind-up. Phase 2 (step 4) drops this to ~0.85.
const WARDEN_WINDUP_SCALE := 1.0

## Never run the same pattern twice in a row if there's an alternative.
const WARDEN_AVOID_REPEATS := true

const COL_TELEGRAPH := Color(1.0, 0.32, 0.30)
const COL_TELEGRAPH_ALT := Color(1.0, 0.55, 0.20)

## Pattern indices. 5-7 arrive in steps 3 and 4.
const P_CLEAVE := 0
const P_PULSE := 1
const P_RING := 2
const P_LANCE := 3
const P_CROSS := 4
const P_TRIPLE := 5

## Which patterns can be rolled. Phase 2 (step 4) appends to this pool.
const WARDEN_POOL_PHASE1 := [P_CLEAVE, P_PULSE, P_RING, P_LANCE, P_CROSS, P_TRIPLE]

const WARDEN_PATTERNS := [
	{   # 0 - frontal cone. Tracks you, then commits: the read is WHEN it locks.
		"name": "CLEAVE",
		"windup": 1.15,
		"active": 0.14,
		"radius": 400.0,
		"half_angle": 50.0,
		"damage": 190.0,
		## Fraction of the wind-up spent tracking the player before locking.
		"track_until": 0.50,
	},
	{   # 1 - point blank. Safe zone is OUTSIDE: run away.
		"name": "PULSE",
		"windup": 1.35,
		"active": 0.16,
		"radius": 300.0,
		"damage": 210.0,
	},
	{   # 2 - ranged ring, the inverse of PULSE. Safe zone is AT MELEE: run in.
		"name": "RING",
		"windup": 1.35,
		"active": 0.16,
		"inner": 205.0,
		"outer": 1400.0,
		"damage": 210.0,
	},
	{   # 3 - dash along a telegraphed lane. Multi-hit, so the lane stays lethal
		# for the whole dash rather than only on the frame it starts.
		"name": "LANCE",
		"windup": 1.20,
		"active": 0.10,
		"length": 950.0,
		"half_width": 95.0,
		"damage": 240.0,
		"dash_time": 0.38,
		"hits": 4,
	},
	{   # 4 - axe slam into an X of shockwaves. The arms cover the diagonals, so
		# the gaps are the four cardinal directions - including straight out to
		# the boss's left and right. Melee range is inside every arm, which is
		# what makes this the opposite problem to RING.
		"name": "CROSS",
		"windup": 1.30,
		"active": 0.16,
		"arms": 4,
		## Rotation of the first arm away from the boss's facing. 45 gives an X
		## with cardinal gaps; 0 gives a + with diagonal gaps.
		"arm_offset": 45.0,
		"length": 900.0,
		"half_width": 105.0,
		"damage": 200.0,
	},
	{   # 5 - three-swing sequence: front, behind, front. One pattern with three
		# beats, so it is answered by moving twice rather than standing still
		# once. The second swing catches anyone who rolled straight through.
		"name": "TRIPLE SWING",
		"windup": 0.95,
		## Later swings wind up faster - the sequence accelerates.
		"windup_rest": 0.55,
		"active": 0.14,
		"swings": 3,
		"radius": 340.0,
		"half_angle": 55.0,
		"damage": 150.0,
		## Re-aim at the player before every swing instead of committing to the
		## facing at the start. Much harsher - off by default.
		"retarget_each": false,
	},
]


# ============================================================================
# FAILURE
# ============================================================================

## Player death restarts the run after this long. The real failure loop lands
## in step 4 with the wipe mechanic.
const DEATH_RESTART_DELAY := 1.60


# ============================================================================
# FEEL
# ============================================================================

const HITSTOP_NORMAL := 0.025
const HITSTOP_HEAVY := 0.09
const HITSTOP_HEAVY_THRESHOLD := 300.0

const SHAKE_ON_CAST := 1.5
const SHAKE_ON_HIT := 2.0
const SHAKE_DECAY := 9.0

const FLOATER_RISE := 52.0
const FLOATER_LIFETIME := 0.80
## Big hits get a bigger number. Scales between these two font sizes.
const FLOATER_SIZE_MIN := 15
const FLOATER_SIZE_MAX := 40
const FLOATER_BIG_DAMAGE := 500.0

const TELEGRAPH_FILL_RATIO := 1.0
const TELEGRAPH_ACTIVE_FLASH := 0.10
const TELEGRAPH_FADE := 0.14


# ============================================================================
# PALETTE
# ============================================================================

const COL_SKY_TOP := Color(0.09, 0.10, 0.20)
const COL_SKY_BOTTOM := Color(0.30, 0.28, 0.44)
const COL_HILLS := Color(0.10, 0.10, 0.17)
const COL_ARENA_FLOOR := Color(0.16, 0.17, 0.24)
const COL_ARENA_EDGE := Color(0.42, 0.45, 0.58)
const COL_PLAYER := Color(0.55, 0.88, 1.0)
const COL_WARDEN := Color(0.62, 0.33, 0.44)
const COL_WARDEN_PHASE2 := Color(0.72, 0.28, 0.34)
const COL_SHADOW := Color(0.0, 0.0, 0.0, 0.30)
const COL_HP := Color(0.85, 0.25, 0.30)
const COL_STAGGER := Color(1.0, 0.82, 0.30)
const COL_IDENTITY := Color(1.0, 0.52, 0.16)
const COL_CASTBAR := Color(1.0, 0.85, 0.45)
const COL_CASTBAR_FLOW := Color(0.45, 0.85, 1.0)
const COL_TEXT := Color(0.86, 0.89, 0.95)
const COL_TEXT_DIM := Color(0.50, 0.55, 0.65)
const COL_WARN := Color(1.0, 0.35, 0.35)


# ============================================================================
# HELPERS
# ============================================================================

## Sentinel for "no action". -1 is the auto attack, 0..3 are the hotbar.
const NO_ACTION := -99
const AUTO_ACTION := -1

static func variant(idx: int) -> Dictionary:
	return VARIANTS[idx]

static func skill(idx: int) -> Dictionary:
	return SKILLS[idx]

## Unified lookup: -1 is the auto attack, 0..3 the hotbar skills.
static func action(idx: int) -> Dictionary:
	return AUTO if idx == AUTO_ACTION else SKILLS[idx]

## Cast time for an action under a variant, with Overheat applied.
## Autos and instants are not scaled by the variant - only real casts are.
static func cast_time(idx: int, variant_idx: int, overheated: bool = false) -> float:
	var t: float
	if idx == AUTO_ACTION:
		t = float(AUTO["cast_time"])
	else:
		t = float(SKILLS[idx]["cast_time"])
		if t > 0.0:
			t *= float(VARIANTS[variant_idx]["cast_mult"])
	if overheated:
		t *= IDENTITY_CAST_MULT
	return t

## Damage multiplier that applies to an action right now.
static func damage_mult(idx: int, variant_idx: int, overheated: bool = false) -> float:
	var m := 1.0
	# The variant penalty is the price of moving while casting, so it only
	# applies to things that actually have a cast time.
	if idx != AUTO_ACTION and float(SKILLS[idx]["cast_time"]) > 0.0:
		m *= float(VARIANTS[variant_idx]["damage_mult"])
	if overheated:
		m *= IDENTITY_DAMAGE_MULT
	return m
