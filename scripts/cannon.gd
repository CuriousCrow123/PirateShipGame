class_name Cannon
extends Node2D
## A single cannon with a muzzle point for projectile spawning.
## Placed as a child of Marker2D slots on the ship.
##
## Phase 4 Step 26: expanded from a 19-line marker into a real component.
## Owns its own Cooldown so individual cannons could in principle fire on
## an independent rhythm. The salvo-wide broadside cooldown lives on
## BroadsideComponent (Step 27) and gates the whole side.
##
## `fire_cooldown` defaults to 0.0 — meaning the per-cannon cooldown is a
## no-op and Broadside drives all firing rate. Setting it >0 would gate
## individual cannons (unused by ship/enemy archetypes today).

signal fired(pos: Vector2, dir: Vector2)

@export var weapon: WeaponConfig
@export var fire_cooldown: float = 0.0

var _cooldown: Cooldown = Cooldown.new()

@onready var _muzzle: Marker2D = $Muzzle


func _ready() -> void:
	assert(_muzzle != null, "Cannon: Muzzle Marker2D is missing")


## Returns true and emits `fired` if the per-cannon cooldown has elapsed.
## BroadsideComponent gates the salvo-wide cadence on top of this.
func try_fire() -> bool:
	if not _cooldown.is_ready():
		return false
	if fire_cooldown > 0.0:
		_cooldown.start(fire_cooldown)
	fired.emit(_muzzle.global_position, global_transform.x.normalized())
	return true


## Legacy API kept for the EnemyShip path which still calls fire() directly
## and consumes the returned Dictionary. Will migrate in Phase 8.
func fire() -> Dictionary:
	return {
		"position": _muzzle.global_position,
		"direction": global_transform.x.normalized(),
	}
