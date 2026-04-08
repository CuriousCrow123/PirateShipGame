extends Node

## Owns the per-run game state: current wave index, RunStats accumulator,
## and the read-only API HUD/screens consume.
##
## Registered SECOND in autoload order (after Events). Per the plan, this
## script may NOT preload other autoloads at file scope \u2014 cross-autoload
## references happen only inside _ready() or later. Loading a Resource
## from disk is fine (it is not an autoload).
##
## Phase 1 Step 7 stub: API methods only, no Events subscriptions yet (those
## land with the per-stat events being emitted from real game systems in
## Phases 4\u20137). HUD callers should already migrate to the methods listed
## below \u2014 NEVER read or write these fields directly from outside.

const _SHIP_STATS_PATH: StringName = &"res://resources/default_ship_stats.tres"

var _ship_stats: ShipStats = null
var _stats: RunStats = null
var _current_wave: int = 0
var _hp: int = 0
var _lives: int = 0


func _ready() -> void:
	# Source-of-truth for max HP / max lives is the ShipStats Resource. We load
	# the same .tres file the player Ship instance is wired to in main.tscn,
	# so a designer edit propagates to BOTH (Resource instances are shared
	# in-memory across loaders for the same path).
	_ship_stats = load(_SHIP_STATS_PATH) as ShipStats
	assert(_ship_stats != null, "GameState: failed to load ShipStats at " + _SHIP_STATS_PATH)
	start_new_run()


# --- Run lifecycle ---


func start_new_run() -> void:
	_stats = RunStats.new()
	_current_wave = 0
	_hp = _ship_stats.max_health
	_lives = _ship_stats.max_lives


# --- Mutators (call these instead of writing fields) ---


func record_damage(amount: int) -> void:
	if _stats == null:
		return
	_stats.damage_taken += amount
	_hp = max(0, _hp - amount)


func record_kill() -> void:
	if _stats == null:
		return
	_stats.kills += 1


func record_death() -> void:
	if _stats == null:
		return
	_stats.deaths += 1
	_lives = max(0, _lives - 1)
	# HP refill happens on respawn, not on death, so the HUD can show 0/4 in
	# the gap between death and the respawn cooldown elapsing.


func record_respawn() -> void:
	_hp = _ship_stats.max_health


func record_wave_cleared(index: int, duration: float) -> void:
	if _stats == null:
		return
	_stats.waves_cleared += 1
	_stats.wave_times.append(duration)
	_current_wave = index + 1


# --- Read-only getters ---


func get_stats() -> RunStats:
	return _stats


func get_current_wave() -> int:
	return _current_wave


func get_hp() -> int:
	return _hp


func get_max_hp() -> int:
	return _ship_stats.max_health


func get_lives() -> int:
	return _lives


func get_max_lives() -> int:
	return _ship_stats.max_lives
