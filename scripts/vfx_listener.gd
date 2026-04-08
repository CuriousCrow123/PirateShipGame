class_name VfxListener
extends Node

## Phase 9 Step 41 — Bus subscriber that spawns ExplosionSprite instances in
## response to Events.explosion_requested. All explosion nodes are parented
## to this listener so they outlive the emitting source (cannonball / mine /
## ship / enemy) after it calls queue_free().
##
## Camera shake and camera zoom punch stay on GameCamera's own subscriptions
## (see game_camera.gd _ready) — the receiver is the camera itself, so a
## separate listener would just forward with zero value.


func _ready() -> void:
	Events.explosion_requested.connect(_on_explosion_requested)


func _on_explosion_requested(pos: Vector2, kind: StringName, dir: Vector2, vel: Vector2) -> void:
	ExplosionSprite.create(self, pos, String(kind), dir, vel)
