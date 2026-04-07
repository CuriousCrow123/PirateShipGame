class_name RunStats
extends RefCounted
## Run-scoped stat accumulator for wave times, enemies destroyed, and player
## hit rate. Lives on Main for the duration of a single run and is handed to
## GameOverScreen when the run ends.

var wave_times_sec: Array[float] = []
var enemies_destroyed: int = 0
var enemies_destroyed_by_mine: int = 0
var player_shots_fired: int = 0
var player_shots_hit: int = 0
var final_wave: int = 0

var _current_wave_started_at_msec: int = 0


func start_wave(wave: int) -> void:
	final_wave = wave
	_current_wave_started_at_msec = Time.get_ticks_msec()


func end_wave() -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _current_wave_started_at_msec) / 1000.0
	wave_times_sec.append(elapsed)


func register_shot_fired() -> void:
	player_shots_fired += 1


func register_shot_hit() -> void:
	player_shots_hit += 1


func register_enemy_destroyed(by_mine: bool = false) -> void:
	enemies_destroyed += 1
	if by_mine:
		enemies_destroyed_by_mine += 1


func hit_rate() -> float:
	if player_shots_fired <= 0:
		return 0.0
	return float(player_shots_hit) / float(player_shots_fired)
