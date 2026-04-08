class_name HitFeedbackComponent
extends Node

## Visual-only damage feedback: white flash on the parent CanvasItem,
## per-sprite shake on hull/sail, iframe blink, and an outgoing screen-shake
## request on the Events bus. Listens to ShipFSM.iframes_started/
## iframes_ended for the blink envelope so the entity root doesn't have to
## drive it manually. (Phase 5 Step 33: signal moved from HealthComponent
## to ShipFSM along with the iframe state itself.)
##
## Phase 4 Step 24: extracted from ship.gd's _apply_hit_feedback,
## _process_hit_shake, and _start_blink_tween / _end_blink. The
## screen_shake_requested publish is one of the two sanctioned bus
## exceptions in component code (the other is AudioEmitterComponent —
## documented in ADR 007).

const HIT_FLASH_DURATION: float = 0.35
const HIT_SHAKE_DURATION: float = 0.6
const HIT_SHAKE_MAX_INTENSITY: float = 5.0
const IFRAME_BLINK_INTERVAL: float = 0.08

## Player ships request a screen shake on hit; enemies do not (the player
## camera shouldn't shake when an enemy gets hit).
@export var shake_on_hit: bool = true
## Trauma to push into the GameCamera shake bus on player hits.
@export var hit_trauma: float = 0.85

var _target: CanvasItem = null
var _hull: Sprite2D = null
var _sail: Sprite2D = null
var _hull_origin: Vector2 = Vector2.ZERO
var _sail_origin: Vector2 = Vector2.ZERO
var _flash_tween: Tween = null
var _blink_tween: Tween = null
var _shake_timer: float = 0.0


func _ready() -> void:
	# Default off — we tick our own _process only while a hit shake is active.
	set_process(false)
	set_physics_process(false)


## target = the CanvasItem to flash + blink (typically the entity root).
## hull/sail = optional sprites for the per-sprite shake offset; pass null
## to skip the shake (enemies use a different shake routine).
func setup(target: CanvasItem, hull: Sprite2D, sail: Sprite2D) -> void:
	assert(target != null, "HitFeedbackComponent.setup: target is null")
	_target = target
	_hull = hull
	_sail = sail
	if _hull != null:
		_hull_origin = _hull.position
	if _sail != null:
		_sail_origin = _sail.position


## Single public entry: triggered by the entity root from its damage path.
func play_hit() -> void:
	if shake_on_hit:
		Events.screen_shake_requested.emit(hit_trauma)
	_shake_timer = HIT_SHAKE_DURATION
	if _hull != null or _sail != null:
		set_process(true)
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_target.modulate = Color(3.0, 3.0, 3.0, 1.0)
	_flash_tween = _target.create_tween()
	_flash_tween.tween_property(_target, "modulate", Color.WHITE, HIT_FLASH_DURATION)


## Wired by the entity root to ShipFSM.iframes_started.
func start_blink() -> void:
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_tween = _target.create_tween().set_loops()
	_blink_tween.tween_property(_target, "modulate:a", 0.35, IFRAME_BLINK_INTERVAL)
	_blink_tween.tween_property(_target, "modulate:a", 1.0, IFRAME_BLINK_INTERVAL)


## Wired by the entity root to ShipFSM.iframes_ended.
func end_blink() -> void:
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_tween = null
	_target.modulate.a = 1.0


func _process(delta: float) -> void:
	if _shake_timer <= 0.0:
		set_process(false)
		return
	_shake_timer -= delta
	if _shake_timer <= 0.0:
		if _hull != null:
			_hull.position = _hull_origin
		if _sail != null:
			_sail.position = _sail_origin
		set_process(false)
		return
	var intensity: float = _shake_timer / HIT_SHAKE_DURATION * HIT_SHAKE_MAX_INTENSITY
	var offset: Vector2 = Vector2(
		roundf(randf_range(-intensity, intensity)), roundf(randf_range(-intensity, intensity))
	)
	if _hull != null:
		_hull.position = _hull_origin + offset
	if _sail != null:
		_sail.position = _sail_origin + offset
