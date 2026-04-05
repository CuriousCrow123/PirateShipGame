class_name Cannon
extends Node2D
## A single cannon with a muzzle point for projectile spawning.
## Placed as a child of Marker2D slots on the ship.

@onready var _muzzle: Marker2D = $Muzzle


func _ready() -> void:
	assert(_muzzle != null, "Cannon: Muzzle Marker2D is missing")


## Returns the spawn position and fire direction for a cannonball.
func fire() -> Dictionary:
	return {
		"position": _muzzle.global_position,
		"direction": global_transform.x.normalized(),
	}
