class_name WaveDirector
extends Node

## Phase 7 Step 35 — Wave lifecycle FSM extracted from main.gd.
##
## Owns the INTERMISSION/SPAWNING/CLEARING/ENDED progression, reads the
## active WaveSet Resource for per-wave tuning, and emits wave lifecycle
## events on the Events bus. Spawning is delegated: each spawn tick emits
## the local `spawn_requested(config)` signal that SpawnService consumes.
##
## Alive-enemy queries are delegated to SpawnService via the setup
## back-ref — WaveDirector does not maintain its own enemy list.
##
## Player death is routed in via `notify_player_game_over()` rather than a
## bus subscription so that the main.tscn wiring path stays explicit.

signal spawn_requested(config: WaveConfig)

enum WavePhase { INTERMISSION, SPAWNING, CLEARING, ENDED }

const WAVE_TOAST_LEAD_TIME: float = 1.5

@export var wave_set: WaveSet

var _spawn_service: SpawnService = null
var _stats: RunStats = null

var _current_wave: int = 0
var _wave_phase: WavePhase = WavePhase.INTERMISSION
var _intermission_timer: float = 4.0
var _toast_shown_for_wave: int = 0
var _enemies_spawned_this_wave: int = 0
var _enemies_to_spawn_this_wave: int = 0
var _spawn_cadence_timer: float = 0.0


func _ready() -> void:
	assert(wave_set != null, "WaveDirector: wave_set Resource must be assigned")
	# Seed the first intermission timer from the WaveSet's first wave so the
	# value is data-driven from frame 0.
	_intermission_timer = wave_set.get_wave(0).intermission_duration
	set_process(false)


func setup(spawn_service: SpawnService, stats: RunStats) -> void:
	assert(spawn_service != null, "WaveDirector.setup: spawn_service is null")
	assert(stats != null, "WaveDirector.setup: stats is null")
	_spawn_service = spawn_service
	_stats = stats


func _physics_process(delta: float) -> void:
	## Wave lifecycle:
	##   INTERMISSION → (toast lead-time elapses) → wave_announced
	##                → (timer hits zero) → SPAWNING
	##   SPAWNING     → (cadence timer ticks, respect concurrent cap)
	##                → (quota filled) → CLEARING
	##   CLEARING     → (alive count == 0) → INTERMISSION (next wave)
	## Player death does NOT reset wave state — combat resumes on respawn.
	match _wave_phase:
		WavePhase.INTERMISSION:
			_intermission_timer -= delta
			var next_wave: int = _current_wave + 1
			if _toast_shown_for_wave < next_wave and _intermission_timer <= WAVE_TOAST_LEAD_TIME:
				Events.wave_announced.emit(next_wave)
				_toast_shown_for_wave = next_wave
			if _intermission_timer <= 0.0:
				_begin_wave(next_wave)
		WavePhase.SPAWNING:
			_spawn_cadence_timer -= delta
			if _spawn_cadence_timer <= 0.0:
				if _try_spawn():
					_spawn_cadence_timer = _current_spawn_interval()
				else:
					# Concurrent cap hit — try again next physics tick.
					_spawn_cadence_timer = 0.1
			if _enemies_spawned_this_wave >= _enemies_to_spawn_this_wave:
				_wave_phase = WavePhase.CLEARING
		WavePhase.CLEARING:
			if _spawn_service.alive_enemy_count() == 0:
				_stats.end_wave()
				# Phase 3.5: if the cleared wave was the last one in the
				# active WaveSet, end the run with a victory instead of
				# rolling into another intermission.
				if wave_set.is_final_wave(_current_wave - 1):
					_wave_phase = WavePhase.ENDED
					Events.run_ended.emit(_stats, true)
				else:
					_intermission_timer = (_wave_config_for(_current_wave).intermission_duration)
					_wave_phase = WavePhase.INTERMISSION
		WavePhase.ENDED:
			# Run over — no further spawning, ticking, or state changes.
			pass


func notify_player_game_over() -> void:
	# Guard against a victory→death race: if the last wave already cleared
	# and we're waiting on the grace timer, swallow the death.
	if _wave_phase == WavePhase.ENDED:
		return
	# The in-progress wave is intentionally NOT closed out — only fully
	# completed waves get a row in the stats list. Halt wave progression so
	# no new enemies spawn between death and the run_ended route.
	_wave_phase = WavePhase.ENDED
	Events.run_ended.emit(_stats, false)


func _begin_wave(wave: int) -> void:
	_current_wave = wave
	_enemies_spawned_this_wave = 0
	_enemies_to_spawn_this_wave = _wave_config_for(wave).enemies_to_spawn
	_spawn_cadence_timer = 0.0
	_wave_phase = WavePhase.SPAWNING
	_stats.start_wave(wave)
	Events.wave_started.emit(wave, _enemies_to_spawn_this_wave)


func _try_spawn() -> bool:
	var config: WaveConfig = _wave_config_for(_current_wave)
	if _spawn_service.alive_enemy_count() >= config.max_concurrent:
		return false
	spawn_requested.emit(config)
	_enemies_spawned_this_wave += 1
	return true


func _wave_config_for(wave: int) -> WaveConfig:
	# WaveSet uses 0-indexed lookups; the in-game wave counter is 1-indexed.
	return wave_set.get_wave(maxi(wave - 1, 0))


func _current_spawn_interval() -> float:
	return _wave_config_for(_current_wave).spawn_interval
