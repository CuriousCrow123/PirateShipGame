extends Node2D
## Manages displacement stamp Sprite2D nodes inside a SubViewport.
## Stamps encode radial displacement direction as RG color (0.5 = neutral).
## Lives as a child of the displacement SubViewport; main.gd calls its API.

const STAMP_TEXTURE: Texture2D = preload("res://textures/white_4x4.png")
const _MAT_PATH: String = "res://features/water/shaders/displacement_stamp_material.tres"
const BASE_MATERIAL: ShaderMaterial = preload(_MAT_PATH)

const MAX_STAMPS: int = 48

@export var sub_viewport: SubViewport
@export var follow_target: Node2D


func _ready() -> void:
	assert(sub_viewport != null, "DisplacementStamps: sub_viewport must be assigned")
	assert(follow_target != null, "DisplacementStamps: follow_target must be assigned")


func _process(_delta: float) -> void:
	# Track follow_target so stamps placed at world coordinates render
	# at the correct SubViewport position.
	position = -follow_target.global_position + Vector2(sub_viewport.size) / 2.0


func spawn_impact(world_pos: Vector2, scale_px: float, duration: float) -> void:
	## Expanding ring stamp for point impacts (cannonballs, explosions).
	if get_child_count() >= MAX_STAMPS:
		return
	var stamp := _create_stamp(world_pos, scale_px)
	var mat: ShaderMaterial = stamp.material as ShaderMaterial
	mat.set_shader_parameter("RingWidth", 0.06)
	mat.set_shader_parameter("Amplitude", 0.8)

	var tween: Tween = stamp.create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(mat, "shader_parameter/RingRadius", 0.45, duration)
		. from(0.02)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_EXPO)
	)
	tween.tween_property(mat, "shader_parameter/Amplitude", 0.0, duration * 0.6).set_ease(
		Tween.EASE_IN
	)
	tween.set_parallel(false)
	tween.tween_callback(stamp.queue_free)


func spawn_wake_ring(world_pos: Vector2) -> void:
	## Expanding ring that spreads outward from a wake trail point.
	if get_child_count() >= MAX_STAMPS:
		return
	var stamp := _create_stamp(world_pos, 48.0)
	var mat: ShaderMaterial = stamp.material as ShaderMaterial
	mat.set_shader_parameter("RingWidth", 0.08)
	mat.set_shader_parameter("Amplitude", 0.4)

	var tween: Tween = stamp.create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(mat, "shader_parameter/RingRadius", 0.45, 1.5)
		. from(0.0)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	tween.tween_property(mat, "shader_parameter/Amplitude", 0.0, 1.5).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(stamp.queue_free)


func spawn_bob(world_pos: Vector2, phase: float) -> void:
	## Small pulsing stamp for mine idle bob.
	## Phase modulates amplitude — stronger at bob extremes.
	if get_child_count() >= MAX_STAMPS:
		return
	var amplitude: float = absf(phase) * 0.35
	if amplitude < 0.01:
		return
	var stamp := _create_stamp(world_pos, 16.0)
	var mat: ShaderMaterial = stamp.material as ShaderMaterial
	mat.set_shader_parameter("RingRadius", 0.0)
	mat.set_shader_parameter("RingWidth", 0.5)
	mat.set_shader_parameter("Amplitude", amplitude)

	var tween: Tween = stamp.create_tween()
	tween.tween_property(stamp, "modulate:a", 0.0, 0.3)
	tween.tween_callback(stamp.queue_free)


func _create_stamp(world_pos: Vector2, scale_px: float) -> Sprite2D:
	var stamp := Sprite2D.new()
	stamp.texture = STAMP_TEXTURE
	# Phase 6 Step 34k audit: per-instance mutation. BASE_MATERIAL is a shared
	# .tres; duplicate so each stamp's per-frame shader_parameter writes stay
	# on its own copy (see docs/decisions/shared-resource-mutation.md).
	stamp.material = BASE_MATERIAL.duplicate()
	stamp.position = world_pos
	stamp.scale = Vector2(scale_px, scale_px)
	add_child(stamp)
	return stamp
