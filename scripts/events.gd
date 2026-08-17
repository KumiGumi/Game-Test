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
## Screen shake request.
signal shake_requested(strength: float)
## Brief time freeze request, in seconds of real time.
signal hitstop_requested(duration: float)
## Full scene reset.
signal restart_requested()

# The registry of live targets is NOT here - it's a static on Hostile. Putting
# it on the autoload would mean events.gd referencing Hostile while Hostile
# calls back into Events, and GDScript will not compile that cycle.
