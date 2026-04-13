extends Node
## Dynamic controller vibration mapped to game events. Intensity scales
## with event severity — light for player actions (fire, mine), medium
## for incoming damage, heavy for death.
##
## Toggle on/off via the "toggle_rumble" input action. Persists the
## preference to user://settings.cfg so it survives restarts.

const SETTINGS_PATH: String = "user://settings.cfg"

## Vibration presets: [weak_motor, strong_motor, duration_sec].
const RUMBLE_FIRE: Array = [0.15, 0.0, 0.08]
const RUMBLE_MINE_DROP: Array = [0.1, 0.1, 0.1]
const RUMBLE_HIT_LIGHT: Array = [0.3, 0.2, 0.15]
const RUMBLE_HIT_HEAVY: Array = [0.4, 0.5, 0.25]
const RUMBLE_DEATH: Array = [0.6, 0.8, 0.4]
const RUMBLE_EXPLOSION: Array = [0.2, 0.3, 0.2]

var enabled: bool = true


func _ready() -> void:
	_load_setting()
	Events.cannonball_fired.connect(_on_cannonball_fired)
	Events.mine_dropped.connect(_on_mine_dropped)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(_on_player_died)
	Events.explosion_requested.connect(_on_explosion_requested)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_rumble"):
		enabled = not enabled
		_save_setting()
		if not enabled:
			_stop_all()
		Events.cheat_toggled.emit(&"rumble", enabled)


func toggle() -> void:
	enabled = not enabled
	_save_setting()
	if not enabled:
		_stop_all()


func _vibrate(preset: Array) -> void:
	if not enabled:
		return
	for device: int in Input.get_connected_joypads():
		Input.start_joy_vibration(device, preset[0], preset[1], preset[2])


func _stop_all() -> void:
	for device: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)


func _on_cannonball_fired(_pos: Vector2, _dir: Vector2, by_player: bool) -> void:
	if by_player:
		_vibrate(RUMBLE_FIRE)


func _on_mine_dropped(_pos: Vector2) -> void:
	_vibrate(RUMBLE_MINE_DROP)


func _on_player_damaged(amount: int, _source: Node) -> void:
	if amount >= 2:
		_vibrate(RUMBLE_HIT_HEAVY)
	else:
		_vibrate(RUMBLE_HIT_LIGHT)


func _on_player_died() -> void:
	_vibrate(RUMBLE_DEATH)


func _on_explosion_requested(
	_pos: Vector2,
	_kind: StringName,
	_dir: Vector2,
	_vel: Vector2,
) -> void:
	_vibrate(RUMBLE_EXPLOSION)


func _load_setting() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_PATH)
	if err != OK:
		return
	enabled = config.get_value("rumble", "enabled", true)


func _save_setting() -> void:
	var config: ConfigFile = ConfigFile.new()
	# Preserve existing settings if the file already exists.
	if FileAccess.file_exists(SETTINGS_PATH):
		config.load(SETTINGS_PATH)
	config.set_value("rumble", "enabled", enabled)
	config.save(SETTINGS_PATH)
