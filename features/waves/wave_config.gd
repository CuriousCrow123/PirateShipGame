class_name WaveConfig
extends Resource

## Tuning for a single wave. Authored as a `.tres` so designers can hand-edit
## a campaign without touching code. WaveConfigs are aggregated into a
## `WaveSet` (one per campaign) and the active set is read by `main.gd` at
## wave-start time.
##
## Per the deepen plan: a WaveConfig is read-only template data. Per-run
## state (current spawn count, alive enemies) lives on the spawning Node,
## NOT on this Resource \u2014 two WaveSets pointing at the same wave_03.tres
## otherwise share an in-memory instance and stomp each other.
##
## The default values match wave 1 of the pre-refactor procedural formula
## at scripts/main.gd (WAVE_BASE_ENEMIES, WAVE_MAX_CONCURRENT_BASE, etc.).

@export var enemies_to_spawn: int = 3
@export var max_concurrent: int = 3
@export var spawn_interval: float = 2.0
@export var speed_mult: float = 1.0
@export var cooldown_mult: float = 1.0
@export var intermission_duration: float = 4.0
