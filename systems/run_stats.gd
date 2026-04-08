class_name RunStats
extends Resource

## Aggregated stats for a single playthrough. Owned by Main for the duration
## of a run; handed to GameOverScreen and (post-Phase 3.5) VictoryScreen.
##
## `extends Resource` so the bus signal `Events.run_ended(stats: RunStats, ...)`
## resolves at parse time and instances are inspectable in the editor.
##
## Field set is the union of:
##   - the plan's Phase 1 Step 9 spec (kills/deaths/damage_taken/time_elapsed
##     /waves_cleared/wave_times)
##   - the existing pre-refactor API surface that main.gd and
##     game_over_screen.gd already consume (enemies_destroyed_by_mine,
##     player_shots_fired/hit, final_wave, hit_rate(), and the start_wave/
##     end_wave/register_* method bundle)
##
## `kills` replaces the pre-refactor `enemies_destroyed` field and is
## incremented by `register_enemy_destroyed()`.
## `wave_times` is the PackedFloat32Array per the plan; replaces the
## pre-refactor `wave_times_sec: Array[float]`.

@export var kills: int = 0
@export var deaths: int = 0
@export var damage_taken: int = 0
@export var time_elapsed: float = 0.0
@export var waves_cleared: int = 0
@export var wave_times: PackedFloat32Array = PackedFloat32Array()

# Existing API surface preserved verbatim ----------------------------------

@export var enemies_destroyed_by_mine: int = 0
@export var player_shots_fired: int = 0
@export var player_shots_hit: int = 0
@export var final_wave: int = 0

var _current_wave_started_at_msec: int = 0


func start_wave(wave: int) -> void:
	final_wave = wave
	_current_wave_started_at_msec = Time.get_ticks_msec()


func end_wave() -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _current_wave_started_at_msec) / 1000.0
	wave_times.append(elapsed)
	waves_cleared += 1


func register_shot_fired() -> void:
	player_shots_fired += 1


func register_shot_hit() -> void:
	player_shots_hit += 1


func register_enemy_destroyed(by_mine: bool = false) -> void:
	kills += 1
	if by_mine:
		enemies_destroyed_by_mine += 1


func hit_rate() -> float:
	if player_shots_fired <= 0:
		return 0.0
	return float(player_shots_hit) / float(player_shots_fired)
