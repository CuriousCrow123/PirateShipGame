class_name AudioEmitterComponent
extends Node

## Local sound emitter — publishes Events.sound_requested(sound_id, pos)
## on behalf of the entity root, so callers don't have to touch the bus
## directly. The Events bus publish from a component is one of the two
## sanctioned exceptions in component code (the other is
## HitFeedbackComponent's screen_shake_requested).
##
## Phase 4 Step 32: scaffolding only. AudioManager is currently a no-op
## until SoundConfig clips exist; this component exists so future audio
## work has a single wiring point on each entity.
##
## sound_bank maps local-event StringNames (e.g. &"cannon_fire") to the
## global sound id AudioManager will look up in its (eventually-real)
## SoundLibrary. Player and enemy ships will instance with different
## banks via inspector overrides on main.tscn / enemy spawns.

@export var sound_bank: Dictionary[StringName, StringName] = {}

var _entity: Node2D = null


func _ready() -> void:
	set_physics_process(false)
	set_process(false)


func setup(entity: Node2D) -> void:
	assert(entity != null, "AudioEmitterComponent.setup: entity is null")
	_entity = entity


## Look up a local event id in the sound_bank and emit the resolved global
## sound id on the bus. No-op if the local id isn't bound.
func play(local_event: StringName) -> void:
	if not sound_bank.has(local_event):
		return
	var sound_id: StringName = sound_bank[local_event]
	var pos: Vector2 = _entity.global_position if _entity != null else Vector2.ZERO
	Events.sound_requested.emit(sound_id, pos)


## Direct passthrough for callers that already know the global sound id.
func play_global(sound_id: StringName, at: Vector2) -> void:
	Events.sound_requested.emit(sound_id, at)
