class_name ShipStats
extends Resource

## Designer-tunable motion + combat stats for the player ship.
##
## Lives in `resources/default_ship_stats.tres`. Edit live in the inspector
## while the game runs and the changes propagate to the ship without
## restart (the ship reads through the Resource each frame).
##
## NOT to be confused with `ShipConfig` (visual variant data: hull/sail
## sprite regions). ShipConfig stays as-is per the deepen plan; the two
## Resources have different concerns and intentionally do not merge.

@export var thrust: float = 120.0
@export var turn_speed: float = 2.5
@export var linear_drag: float = 0.99
@export var brake_decel: float = 120.0
@export var broadside_cooldown: float = 0.5
@export var mine_cooldown: float = 2.5
@export var max_health: int = 4
@export var max_lives: int = 2
@export var respawn_delay: float = 2.0
