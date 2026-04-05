class_name ExplosionEffect
extends Node2D
## Real-time 3D explosion rendered into a SubViewport and displayed in 2D.
## Spawns, plays, and auto-frees. Use ExplosionEffect.create() to spawn.

const LIFETIME: float = 1.2
const ExplosionScene: PackedScene = preload("res://scenes/explosion_effect.tscn")

@onready var _sub_viewport: SubViewport = %SubViewport
@onready var _vertical_emitter: GPUParticles3D = %VerticalEmitter
@onready var _horizontal_emitter: GPUParticles3D = %HorizontalEmitter


func _ready() -> void:
	assert(_sub_viewport != null, "SubViewport not found")
	assert(_vertical_emitter != null, "VerticalEmitter not found")
	assert(_horizontal_emitter != null, "HorizontalEmitter not found")

	# WorldEnvironment for glow (must be created in code)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 1.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_sub_viewport.add_child(world_env)

	# Override lifetime
	_vertical_emitter.lifetime = LIFETIME
	_horizontal_emitter.lifetime = LIFETIME

	# Duplicate shader material so instances don't share mutations
	var base_mat: ShaderMaterial = _vertical_emitter.draw_pass_1.surface_get_material(0)
	var mat: ShaderMaterial = base_mat.duplicate() as ShaderMaterial
	_vertical_emitter.draw_pass_1.surface_set_material(0, mat)
	_horizontal_emitter.draw_pass_1.surface_set_material(0, mat)

	# Duplicate process materials for independence
	var vert_pm: ParticleProcessMaterial = (
		_vertical_emitter.process_material.duplicate() as ParticleProcessMaterial
	)
	_vertical_emitter.process_material = vert_pm
	var horiz_pm: ParticleProcessMaterial = (
		_horizontal_emitter.process_material.duplicate() as ParticleProcessMaterial
	)
	_horizontal_emitter.process_material = horiz_pm

	# Color ramp: white -> yellow -> orange -> dark -> transparent
	var color_ramp: GradientTexture1D = _create_color_ramp()
	vert_pm.color_ramp = color_ramp
	horiz_pm.color_ramp = color_ramp

	# Scale curve: quick grow then shrink
	var scale_tex: CurveTexture = _create_scale_curve()
	vert_pm.scale_curve = scale_tex
	horiz_pm.scale_curve = scale_tex

	# Turbulence for organic motion
	for pm: ParticleProcessMaterial in [vert_pm, horiz_pm]:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 3.0
		pm.turbulence_noise_scale = 6.0
		pm.turbulence_influence_min = 0.1
		pm.turbulence_influence_max = 0.25

	# Fire particles
	await get_tree().process_frame
	_vertical_emitter.emitting = false
	_horizontal_emitter.emitting = false
	_vertical_emitter.restart()
	_horizontal_emitter.restart()

	# Auto-free after particles finish
	await get_tree().create_timer(LIFETIME + 0.3).timeout
	queue_free()


## Convenience factory: spawns an explosion at the given world position.
static func create(parent: Node, pos: Vector2) -> ExplosionEffect:
	var effect: ExplosionEffect = ExplosionScene.instantiate() as ExplosionEffect
	parent.add_child(effect)
	effect.global_position = pos
	return effect


static func _create_color_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.1, 0.3, 0.55, 0.8, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 0.95, 1.0),
			Color(1.0, 0.85, 0.3, 1.0),
			Color(1.0, 0.45, 0.05, 1.0),
			Color(0.5, 0.12, 0.0, 0.9),
			Color(0.2, 0.15, 0.1, 0.5),
			Color(0.1, 0.08, 0.05, 0.0),
		]
	)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


static func _create_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.1))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.5, 0.7))
	curve.add_point(Vector2(1.0, 0.1))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex
