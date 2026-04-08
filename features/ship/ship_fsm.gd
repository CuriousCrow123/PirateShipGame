class_name ShipFSM
extends Node

## Owns the player ship's discrete state machine. Replaces the 5 flag-soup
## vars (`_is_dead`, `_input_locked`, `_dash_active`, `_iframes_left`,
## `_invincible`) that previously lived across Ship + HealthComponent +
## DashComponent.
##
## States:
##   NORMAL  — alive, vulnerable, accepting input
##   DASHING — dash burst is active. Dash does NOT grant invulnerability;
##             this state coexists with iframes via the timer below, and
##             we fall back to IFRAME or NORMAL on dash end accordingly.
##   IFRAME  — alive but invulnerable (post-hit, post-respawn, or cheat).
##   DEAD    — destroyed, awaiting respawn or game over; no input, no
##             damage, no movement.
##
## Priority on transition: DEAD > DASHING > IFRAME > NORMAL. The FSM never
## holds two states at once. The iframe countdown keeps ticking while
## DASHING so dash-end can fall back into IFRAME if iframes remain.
##
## HurtboxComponent, MovementComponent, and PlayerInputComponent subscribe
## to `state_changed` and gate their behavior. HealthComponent queries
## `is_vulnerable()` and calls `enter_dead()` / `respawn()` for transitions.
## HitFeedbackComponent listens to `iframes_started` / `iframes_ended` for
## the blink envelope.
##
## Phase 5 Step 33.

signal state_changed(old: int, new: int)
signal iframes_started
signal iframes_ended
signal invincibility_changed(active: bool)

enum State { NORMAL, DASHING, IFRAME, DEAD }

var _state: int = State.NORMAL
var _iframes_left: float = 0.0
var _invincible: bool = false


func _ready() -> void:
	# Iframe countdown ticks here so HealthComponent can return to default-off.
	set_physics_process(true)
	set_process(false)


func _physics_process(delta: float) -> void:
	if _iframes_left <= 0.0:
		return
	_iframes_left -= delta
	if _iframes_left > 0.0:
		return
	# Cheat invincibility pins iframes indefinitely even after the natural
	# timer elapses; only release when both sources are clear.
	if _invincible:
		return
	iframes_ended.emit()
	if _state == State.IFRAME:
		_set_state(State.NORMAL)


func _unhandled_input(event: InputEvent) -> void:
	# Secret invincibility cheat (Shift+5). Debug builds only — exporting a
	# release strips this entire branch.
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		if key_event.shift_pressed and key_event.physical_keycode == KEY_5:
			toggle_invincible()
			Events.cheat_toggled.emit(&"invincibility", _invincible)


func get_state() -> int:
	return _state


func is_dead() -> bool:
	return _state == State.DEAD


func is_dashing() -> bool:
	return _state == State.DASHING


func has_iframes() -> bool:
	return _iframes_left > 0.0 or _invincible


func is_invincible() -> bool:
	return _invincible


## True when damage may land. Dashing is intentionally vulnerable.
func is_vulnerable() -> bool:
	return _state != State.DEAD and not has_iframes()


## True when the player should be ignored by input handlers.
func is_input_locked() -> bool:
	return _state == State.DEAD


func enter_dashing() -> void:
	if _state == State.DEAD or _state == State.DASHING:
		return
	_set_state(State.DASHING)


func exit_dashing() -> void:
	if _state != State.DASHING:
		return
	if has_iframes():
		_set_state(State.IFRAME)
	else:
		_set_state(State.NORMAL)


func enter_dead() -> void:
	if _state == State.DEAD:
		return
	if _iframes_left > 0.0:
		_iframes_left = 0.0
		iframes_ended.emit()
	_set_state(State.DEAD)


## Atomic DEAD → IFRAME respawn transition. Called by HealthComponent
## (via Ship root) after the respawn cooldown elapses and the entity has
## been teleported back to its spawn point.
func respawn(iframe_duration: float) -> void:
	if _state != State.DEAD:
		return
	_iframes_left = iframe_duration
	iframes_started.emit()
	_set_state(State.IFRAME)


func start_iframes(duration: float) -> void:
	if _state == State.DEAD:
		return
	var was_active: bool = _iframes_left > 0.0 or _invincible
	_iframes_left = duration
	if not was_active:
		iframes_started.emit()
	if _state == State.NORMAL:
		_set_state(State.IFRAME)


func toggle_invincible() -> void:
	set_invincible(not _invincible)


func set_invincible(active: bool) -> void:
	if _invincible == active:
		return
	_invincible = active
	invincibility_changed.emit(active)
	if active:
		if _iframes_left <= 0.0:
			iframes_started.emit()
		if _state == State.NORMAL:
			_set_state(State.IFRAME)
	else:
		if _iframes_left <= 0.0:
			iframes_ended.emit()
			if _state == State.IFRAME:
				_set_state(State.NORMAL)


func _set_state(new_state: int) -> void:
	if new_state == _state:
		return
	var old_state: int = _state
	_state = new_state
	state_changed.emit(old_state, new_state)
