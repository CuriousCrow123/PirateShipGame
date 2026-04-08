class_name BroadsideComponent
extends Node

## Thin orchestrator that drives the port/starboard Cannon groups, owns the
## per-side broadside cooldown, and emits cannon_fired so the Ship root can
## forward to main.gd's existing cannonball spawn handler.
##
## Phase 4 Step 27: replaces ship.gd._fire_broadside. The Cannon nodes
## themselves were expanded in Step 26 to expose try_fire() + a `fired`
## signal; this component groups them by side and gates the salvo on a
## single Cooldown per side.

signal cannon_fired(pos: Vector2, dir: Vector2)

@export var fire_rate_mult: float = 1.0

var _stats: ShipStats = null
var _port_cannons: Array[Cannon] = []
var _starboard_cannons: Array[Cannon] = []
var _port_cooldown: Cooldown = Cooldown.new()
var _starboard_cooldown: Cooldown = Cooldown.new()


func _ready() -> void:
	set_physics_process(false)
	set_process(false)


## Wired by Ship root after _ready. cannon_slots is the CannonSlots Node2D
## containing PortCannon1/2/StarboardCannon1/2 markers.
func setup(cannon_slots: Node2D, stats: ShipStats) -> void:
	assert(cannon_slots != null, "BroadsideComponent.setup: cannon_slots is null")
	assert(stats != null, "BroadsideComponent.setup: stats is null")
	_stats = stats
	for slot: Node in cannon_slots.get_children():
		if slot.get_child_count() == 0:
			continue
		var cannon: Cannon = slot.get_child(0) as Cannon
		if cannon == null:
			continue
		cannon.fired.connect(_on_cannon_fired)
		if String(slot.name).begins_with("Port"):
			_port_cannons.append(cannon)
		elif String(slot.name).begins_with("Starboard"):
			_starboard_cannons.append(cannon)


func is_port_ready() -> bool:
	return _port_cooldown.is_ready()


func is_starboard_ready() -> bool:
	return _starboard_cooldown.is_ready()


## Fire all port cannons. No-op if the side is on cooldown.
func fire_port() -> bool:
	if not _port_cooldown.is_ready():
		return false
	for cannon: Cannon in _port_cannons:
		if cannon.visible:
			cannon.try_fire()
	_port_cooldown.start(_stats.broadside_cooldown / fire_rate_mult)
	return true


func fire_starboard() -> bool:
	if not _starboard_cooldown.is_ready():
		return false
	for cannon: Cannon in _starboard_cannons:
		if cannon.visible:
			cannon.try_fire()
	_starboard_cooldown.start(_stats.broadside_cooldown / fire_rate_mult)
	return true


func _on_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	cannon_fired.emit(pos, dir)
