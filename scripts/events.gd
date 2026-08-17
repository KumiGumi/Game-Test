extends Node
## Global signal bus.
##
## Combat code emits; HUD / debug readouts / juice listen. Nothing that deals
## damage needs to know a DPS meter exists. Autoloaded as `Events`.

## amount, world_position, source_skill_index (-1 for non-skill damage)
signal damage_dealt(amount: float, at: Vector2, skill_idx: int)
## amount, world_position
signal stagger_dealt(amount: float, at: Vector2)
## amount, world_position, was_avoided (i-frames / god mode)
signal player_hit(amount: float, at: Vector2, avoided: bool)
## Fired when a counter-flagged skill connects. success=false means it landed
## but the target had no counter window open.
signal counter_landed(success: bool, at: Vector2)
## The player finished a cast (skill index).
signal cast_completed(skill_idx: int)
## The player's cast was cancelled by dashing (skill index, cooldown paid).
signal cast_cancelled(skill_idx: int, cooldown_paid: float)
## Variant toggled. index into Tune.VARIANTS.
signal variant_changed(variant_idx: int)
## Overheat meter reached full and can be spent.
signal identity_full()
## Overheat window opened / closed.
signal identity_activated()
signal identity_ended()

## The Warden began a pattern: index into Tune.WARDEN_PATTERNS, and its name.
signal warden_pattern_started(idx: int, pattern_name: String)
signal warden_defeated()
## The player hit 0 HP. Step 4 turns this into the real failure loop.
signal player_died()
## The player went off a ledge.
signal player_fell()
## A side of the stage broke away. -1 left, +1 right.
signal platform_broke(dir: int)
## Counter window opened / closed on the boss.
signal counter_window_changed(open: bool)
## A stagger check began, and how it ended.
signal stagger_check_started(required: float, duration: float)
signal stagger_check_ended(success: bool)
## Screen shake request.
signal shake_requested(strength: float)
## Brief time freeze request, in seconds of real time.
signal hitstop_requested(duration: float)
## Full scene reset.
signal restart_requested()

# The registry of live targets is NOT here - it's a static on Hostile. Putting
# it on the autoload would mean events.gd referencing Hostile while Hostile
# calls back into Events, and GDScript will not compile that cycle.
