extends Node2D
## Scene root — Phase 7 Step 35-38 thin orchestrator. Wave lifecycle lives
## on WaveDirector, spawning on SpawnService, RunStats + results screens on
## StatsTracker, and displacement / wake trail on WaterEffectsManager.
##
## Main.gd's only remaining responsibilities:
##   * Hold @onready references and run the assertion gate.
##   * Wire cross-service signal connections in a single place (setup
##     calls + ship/service signal hookup).
##   * Handle scene-level input toggles (fullscreen, explosion mode).
##   * Snap the camera to the respawn point on Ship.respawned.
##
## Phase 11 Step 48c: WaveToast forwarders deleted — WaveToast now
## subscribes directly to Events.wave_announced and Events.cheat_toggled.

@onready var _ship: Ship = $Ship
@onready var _minimap_display: MinimapDisplay = $Minimap/MinimapDisplay
@onready var _hp_display: HPDisplay = $HPDisplay
@onready var _lives_display: LivesDisplay = $LivesDisplay
@onready var _mine_cooldown_display: MineCooldownDisplay = $MineCooldownDisplay
@onready var _camera: GameCamera = $GameCamera
@onready var _wave_director: WaveDirector = $WaveDirector
@onready var _spawn_service: SpawnService = $SpawnService
@onready var _stats_tracker: StatsTracker = $StatsTracker
@onready var _water_effects: WaterEffectsManager = $WaterEffectsManager


func _ready() -> void:
	assert(_ship != null, "Main: Ship node is missing")
	assert(_minimap_display != null, "Main: MinimapDisplay node not found")
	assert(_hp_display != null, "Main: HPDisplay not found")
	assert(_lives_display != null, "Main: LivesDisplay not found")
	assert(_mine_cooldown_display != null, "Main: MineCooldownDisplay not found")
	assert(_camera != null, "Main: GameCamera not found")
	assert(_wave_director != null, "Main: WaveDirector not found")
	assert(_spawn_service != null, "Main: SpawnService not found")
	assert(_stats_tracker != null, "Main: StatsTracker not found")
	assert(_water_effects != null, "Main: WaterEffectsManager not found")

	var stats: RunStats = _stats_tracker.get_stats()
	_water_effects.setup(_ship, _spawn_service)
	_spawn_service.setup(_ship, _water_effects, stats)
	_wave_director.setup(_spawn_service, stats)

	_ship.cannon_fired.connect(_spawn_service.spawn_player_cannonball)
	_ship.mine_dropped.connect(_spawn_service.spawn_mine)
	_ship.died.connect(_water_effects.on_player_died)
	_ship.respawned.connect(_water_effects.on_player_respawned)
	_ship.respawned.connect(_on_ship_respawned)
	_ship.game_over.connect(_wave_director.notify_player_game_over)
	_wave_director.spawn_requested.connect(_spawn_service.spawn_wave_enemy)

	_minimap_display.setup(_ship)
	_hp_display.setup(_ship)
	_lives_display.setup(_ship)
	_mine_cooldown_display.setup(_ship)
	# Defer camera target injection: Ship's _ready has already run by the time
	# Main._ready fires, but deferring keeps the contract explicit that the
	# camera accepts target injection after-the-fact and handles null cleanly.
	_camera.call_deferred("set_target", _ship)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("toggle_explosion_mode"):
		ExplosionSprite.use_sprite = not ExplosionSprite.use_sprite
		print("Explosions: ", "sprite" if ExplosionSprite.use_sprite else "3D")


func _on_ship_respawned() -> void:
	# Snap the camera to the respawn position so position_smoothing doesn't
	# rubber-band the view back from the death location. WaterEffectsManager
	# handles the wake-trail reset via its own connection.
	_camera.snap_to_target()
