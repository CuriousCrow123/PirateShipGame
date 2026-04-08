extends Node

## Runtime InputMap remap layer + gamepad defaults + user://keybinds.cfg
## persistence.
##
## Phase 3 Step 18. On boot:
##   1. Installs default gamepad bindings for the 9 remappable actions
##      (player gameplay + fullscreen), on top of the keyboard bindings
##      already declared in project.godot.
##   2. Loads any user overrides from `user://keybinds.cfg`, replacing the
##      corresponding InputMap entries.
##   3. Subscribes to `Input.joy_connection_changed` and re-emits
##      typed hotplug signals for any UI or HUD listeners.
##
## No UI is included in Phase 3 — the plan defers the controls-menu
## screen. This layer exists so any future remap screen can call
## `rebind_action()` / `save()` without touching InputMap directly.

signal gamepad_connected(device: int)
signal gamepad_disconnected(device: int)
signal bindings_changed(action: StringName)

const KEYBINDS_PATH: String = "user://keybinds.cfg"

## Actions the player is allowed to rebind. System-level actions
## (toggle_explosion_mode, toggle_debug_overlay) stay hard-wired to the
## project.godot defaults so debug shortcuts can't be accidentally clobbered.
const REMAPPABLE_ACTIONS: Array = [
	"move_forward",
	"move_back",
	"turn_left",
	"turn_right",
	"fire_port",
	"fire_starboard",
	"drop_mine",
	"dash",
	"toggle_fullscreen",
]


func _ready() -> void:
	_ensure_default_gamepad_bindings()
	_load_from_disk()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## True if at least one gamepad is currently connected.
func has_gamepad() -> bool:
	return not Input.get_connected_joypads().is_empty()


## Replace the binding list for an action with a single event. Caller is
## responsible for calling `save()` after a batch of rebinds.
func rebind_action(action: StringName, event: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	bindings_changed.emit(action)


## Append an additional binding to an action without removing existing ones.
func add_binding(action: StringName, event: InputEvent) -> void:
	InputMap.action_add_event(action, event)
	bindings_changed.emit(action)


## Returns the current binding events for an action (read-only).
func get_bindings(action: StringName) -> Array[InputEvent]:
	return InputMap.action_get_events(action)


## Reset every remappable action to its project.godot default + the
## gamepad defaults installed at boot. Deletes any user://keybinds.cfg.
func reset_to_defaults() -> void:
	InputMap.load_from_project_settings()
	_ensure_default_gamepad_bindings()
	if FileAccess.file_exists(KEYBINDS_PATH):
		DirAccess.remove_absolute(KEYBINDS_PATH)
	for action_name in REMAPPABLE_ACTIONS:
		bindings_changed.emit(StringName(action_name))


## Persist the current binding set to user://keybinds.cfg. Only the
## REMAPPABLE_ACTIONS section is written.
func save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for action_name in REMAPPABLE_ACTIONS:
		var action: StringName = StringName(action_name)
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var payload: Array = []
		for e in events:
			payload.append(e)
		config.set_value("bindings", action_name, payload)
	var err: int = config.save(KEYBINDS_PATH)
	if err != OK:
		push_error("KeybindsManager: failed to save %s (err %d)" % [KEYBINDS_PATH, err])


func _load_from_disk() -> void:
	if not FileAccess.file_exists(KEYBINDS_PATH):
		return
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(KEYBINDS_PATH)
	if err != OK:
		push_warning("KeybindsManager: failed to load keybinds.cfg (err %d); using defaults" % err)
		return
	for action_name in REMAPPABLE_ACTIONS:
		if not config.has_section_key("bindings", action_name):
			continue
		var payload: Variant = config.get_value("bindings", action_name, [])
		if not (payload is Array):
			continue
		var action: StringName = StringName(action_name)
		InputMap.action_erase_events(action)
		for e in payload as Array:
			if e is InputEvent:
				InputMap.action_add_event(action, e)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		gamepad_connected.emit(device)
	else:
		gamepad_disconnected.emit(device)


## Install default gamepad bindings for the 9 remappable actions. Guarded
## against duplicates so repeated calls (reset_to_defaults) are idempotent.
func _ensure_default_gamepad_bindings() -> void:
	# Left stick → turn; triggers → thrust/brake.
	_add_default_joy_motion("turn_left", JOY_AXIS_LEFT_X, -1.0)
	_add_default_joy_motion("turn_right", JOY_AXIS_LEFT_X, 1.0)
	_add_default_joy_motion("move_forward", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_default_joy_motion("move_back", JOY_AXIS_TRIGGER_LEFT, 1.0)
	# Shoulders fire broadsides; face buttons dash / drop mine.
	_add_default_joy_button("fire_port", JOY_BUTTON_LEFT_SHOULDER)
	_add_default_joy_button("fire_starboard", JOY_BUTTON_RIGHT_SHOULDER)
	_add_default_joy_button("dash", JOY_BUTTON_A)
	_add_default_joy_button("drop_mine", JOY_BUTTON_X)
	_add_default_joy_button("toggle_fullscreen", JOY_BUTTON_BACK)


func _add_default_joy_button(action: String, button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.device = -1  # all devices
	if not _action_has_joy_button(action, button):
		InputMap.action_add_event(action, event)


func _add_default_joy_motion(action: String, axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = -1  # all devices
	if not _action_has_joy_motion(action, axis, value):
		InputMap.action_add_event(action, event)


func _action_has_joy_button(action: String, button: JoyButton) -> bool:
	for existing in InputMap.action_get_events(action):
		if (
			existing is InputEventJoypadButton
			and (existing as InputEventJoypadButton).button_index == button
		):
			return true
	return false


func _action_has_joy_motion(action: String, axis: JoyAxis, value: float) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadMotion:
			var motion: InputEventJoypadMotion = existing as InputEventJoypadMotion
			if motion.axis == axis and signf(motion.axis_value) == signf(value):
				return true
	return false
