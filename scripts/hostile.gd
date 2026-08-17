class_name Hostile
extends Node2D
## Anything the player can hit. The Dummy implements it in step 1, the Warden
## in step 2, and no calling code changes in between.
##
## Two jobs beyond the obvious one:
##
## 1. It keeps GDScript's static typing happy. Hit resolution in Bolt and Player
##    iterates a typed Array[Hostile], so `body_radius` and `apply_hit` are
##    checked at parse time instead of failing at runtime.
## 2. It owns the registry of live targets as a static, so damage-dealing code
##    never has to name the Arena. Routing that through the Arena (or the Events
##    autoload) would make the class_name dependency graph cyclic, which
##    GDScript refuses to compile.

static var _all: Array[Hostile] = []

var body_radius: float = 10.0


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


## damage / stagger arrive already variant-scaled. `skill_idx` is -1 for
## anything that didn't come from the hotbar. `is_counter` is true only for
## skill 4.
func apply_hit(_damage: float, _stagger_value: float, _skill_idx: int, _is_counter: bool) -> void:
	pass


## Step 3: the Warden returns true only during pattern 6's blue window.
func counter_window_open() -> bool:
	return false
