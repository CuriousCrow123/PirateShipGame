class_name RunStats
extends Resource

## Aggregated stats for a single playthrough. Owned by GameState; consumed by
## the GameOver and (post-Phase 3.5) Victory screens.
##
## Defined here in Phase 1 Step 6 as a forward declaration so that the
## Events autoload can declare typed `run_ended(stats: RunStats, ...)`
## signatures at parse time. Phase 1 Step 9 expands this with the
## production fields and the GUT unit suite.

@export var kills: int = 0
@export var deaths: int = 0
@export var damage_taken: int = 0
@export var time_elapsed: float = 0.0
@export var waves_cleared: int = 0
@export var wave_times: PackedFloat32Array = PackedFloat32Array()
