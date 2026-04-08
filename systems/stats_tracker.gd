class_name StatsTracker
extends Node

## Phase 7 Step 37 — Owns the run's RunStats lifecycle and the game-over
## grace timer that used to live inline on main.gd. Subscribes to
## Events.run_ended, runs a short polled Cooldown, and then shows the
## appropriate results screen.
##
## RunStats is created here and handed out via get_stats() — WaveDirector
## and SpawnService both write to it via the RunStats API. A future pass
## (Phase 8+) will migrate those direct calls onto the typed stat_recorded
## bus signals, at which point StatsTracker will subscribe instead of
## sharing the instance.

@export var game_over_screen: GameOverScreen
@export var victory_screen: GameOverScreen

var _stats: RunStats = null
var _grace_cooldown: Cooldown = Cooldown.new()
var _grace_pending: bool = false
var _grace_victory: bool = false


func _ready() -> void:
	assert(game_over_screen != null, "StatsTracker: game_over_screen export is null")
	assert(victory_screen != null, "StatsTracker: victory_screen export is null")
	_stats = RunStats.new()
	Events.run_ended.connect(_on_run_ended)
	set_process(false)


func get_stats() -> RunStats:
	return _stats


func _process(_delta: float) -> void:
	if not _grace_pending or not _grace_cooldown.is_ready():
		return
	_grace_pending = false
	set_process(false)
	if _grace_victory:
		if is_instance_valid(victory_screen):
			victory_screen.show_results(_stats, true)
	else:
		if is_instance_valid(game_over_screen):
			game_over_screen.show_results(_stats, false)


func _on_run_ended(_stats_payload: RunStats, victory: bool) -> void:
	# Short grace so the death explosion + HP drain (or final-wave clear
	# flourish) reads before the panel slides in. Phase 6 Step 34h: grace
	# timer is a polled Cooldown, not an await create_timer, so the
	# scheduler never holds a SceneTreeTimer reference across a scene
	# unload. StatsTracker only enables its own _process for the ~1s
	# grace window and clears the flag on fire.
	_grace_victory = victory
	_grace_pending = true
	_grace_cooldown.start(1.0)
	set_process(true)
