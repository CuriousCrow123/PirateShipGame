class_name ShipConfig
extends Resource
## Data-driven ship configuration: hull, sail, and cannon slot setup.
## Read-only at runtime — ship reads config to set up sprites.

enum HullSize { LARGE }
enum CannonType { STANDARD, MOBILE, LOOSE }

@export var hull_size: HullSize = HullSize.LARGE
@export var hull_variant: int = 0  ## 0-3, damage state index
@export var sail_variant: int = 0  ## 0-23 for large sails
@export var cannon_slots: Array[bool] = [true, true, true, true]  ## port1, port2, star1, star2
@export var cannon_type: CannonType = CannonType.STANDARD


## Returns the spritesheet region rect for the current hull.
static func get_hull_region(variant: int) -> Rect2:
	return Rect2(variant * 50, 522, 50, 108)


## Returns the spritesheet region rect for the current sail.
static func get_sail_region(variant: int) -> Rect2:
	@warning_ignore("integer_division")
	return Rect2((variant % 6) * 66, 742 + (variant / 6) * 47, 66, 47)


## Returns the spritesheet region rect for a cannon type.
static func get_cannon_region(type: CannonType) -> Rect2:
	return Rect2(type * 29, 943, 29, 20)
