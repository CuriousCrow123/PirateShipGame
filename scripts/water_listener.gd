class_name WaterListener
extends Node

## Phase 9 Step 42 — Bus subscriber that forwards displacement requests to
## the displacement_stamps Node2D. Kept deliberately dumb: publishers
## (WaterEffectsManager, SpawnService) do the tuning lookups and emit
## pre-computed radius/duration values on the bus; this listener just
## forwards to the displacement_stamps API.

@export var displacement_stamps: Node2D


func _ready() -> void:
	assert(displacement_stamps != null, "WaterListener: displacement_stamps is null")
	Events.displacement_impact_requested.connect(_on_impact_requested)
	Events.displacement_wake_ring_requested.connect(_on_wake_ring_requested)
	Events.displacement_bob_requested.connect(_on_bob_requested)


func _on_impact_requested(pos: Vector2, radius_px: float, duration: float) -> void:
	displacement_stamps.spawn_impact(pos, radius_px, duration)


func _on_wake_ring_requested(pos: Vector2) -> void:
	displacement_stamps.spawn_wake_ring(pos)


func _on_bob_requested(pos: Vector2, phase: float) -> void:
	displacement_stamps.spawn_bob(pos, phase)
