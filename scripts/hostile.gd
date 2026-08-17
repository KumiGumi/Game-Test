class_name Hostile
extends Actor
## Anything the player can hit. The Warden implements it; the contract is what
## lets Bolt and the player's skills resolve damage without knowing what they hit.
##
## It owns the registry of live targets as a static, so damage-dealing code
## never has to name the Arena. Routing that through the Arena (or an autoload)
## would make the class_name dependency graph cyclic, which GDScript refuses to
## compile.

static var _all: Array[Hostile] = []


## Everything currently alive and hittable.
static func all() -> Array[Hostile]:
	var out: Array[Hostile] = []
	for h in _all:
		if is_instance_valid(h):
			out.append(h)
	return out


func _ready() -> void:
	if not _all.has(self):
		_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)


## damage / stagger arrive already scaled by variant and Overheat.
## `action_idx` is -1 for autos, 0..3 for hotbar skills.
## `is_counter` is true only for Riposte.
func apply_hit(_damage: float, _stagger_value: float, _action_idx: int, _is_counter: bool) -> void:
	pass


## True only while a counter window is open.
func counter_window_open() -> bool:
	return false


## Directional windows: a counter has to land on the FRONT of the hitbox, so
## the window alone is not enough - where you are standing matters too.
func counter_reachable_from(_from: Vector2) -> bool:
	return counter_window_open()


## Called when a counter lands while the window was open.
func on_countered(_stun_time: float) -> void:
	pass
