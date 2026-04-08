class_name Cannon
extends Node2D
## A single cannon with a muzzle point for projectile spawning.
## Placed as a child of Marker2D slots on the ship.
##
## `weapon` slot is a Phase 2 Step 12 forward declaration; the actual
## cannonball-spawn read happens in Phase 4 Step 26 when Cannon becomes
## a real component and takes over cannonball.gd's @exports.

@export var weapon: WeaponConfig

@onready var _muzzle: Marker2D = $Muzzle


func _ready() -> void:
	assert(_muzzle != null, "Cannon: Muzzle Marker2D is missing")


## Returns the spawn position and fire direction for a cannonball.
func fire() -> Dictionary:
	return {
		"position": _muzzle.global_position,
		"direction": global_transform.x.normalized(),
	}
