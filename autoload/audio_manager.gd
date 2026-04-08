extends Node

## Centralised audio router. No-op until SoundConfig clips exist; for now just
## subscribes to Events.sound_requested so the contract is end-to-end testable
## as soon as a real emitter wires up.
##
## Registered THIRD in autoload order (after Events and GameState). May NOT
## preload other autoloads at file scope \u2014 the Events reference is taken
## inside _ready(), where the load order guarantees Events already exists.
##
## Phase 1 Step 8 stub. Real bus subscriptions on player_damaged,
## enemy_destroyed, mine_dropped, etc., land alongside the SoundConfig
## Resource and the AudioStreamPlayer pool in a future phase.


func _ready() -> void:
	Events.sound_requested.connect(_on_sound_requested)


func _on_sound_requested(_sound_id: StringName, _pos: Vector2) -> void:
	# No-op: no clips loaded yet. Real implementation will look up
	# `_sound_id` in a SoundLibrary Resource, allocate a free
	# AudioStreamPlayer2D from a pool, position it at `_pos`, and play it.
	pass
