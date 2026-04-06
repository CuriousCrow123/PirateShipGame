class_name ExplosionEffect
extends Node2D
## Real-time 3D explosion rendered into a SubViewport and displayed in 2D.
## Spawns, plays, and auto-frees. Use ExplosionEffect.create() to spawn.

const LIFETIME: float = 1.2
const ExplosionScene: PackedScene = preload("res://scenes/explosion_effect.tscn")

## 2D direction to aim the vertical emitter cone. Set before adding to tree.
var _cone_dir: Vector2 = Vector2.ZERO
## Cone spread override in degrees. -1.0 means use the model default.
var _cone_spread: float = 0
## Scale multiplier for the entire effect. 1.0 = default size.
var _effect_scale: float = 1.0
## Vertical emitter velocity override. -1.0 means use the model default.
var _vert_velocity: float = -1.0
## Drift velocity applied each frame so the effect follows momentum at spawn.
var _drift_velocity: Vector2 = Vector2.ZERO

@onready var _model: SubViewport = $SubViewportContainer/ExplosionModel
@onready var _vertical_emitter: GPUParticles3D = $SubViewportContainer/ExplosionModel/VerticalEmitter
@onready
var _horizontal_emitter: GPUParticles3D = $SubViewportContainer/ExplosionModel/HorizontalEmitter


func _ready() -> void:
	assert(_model != null, "ExplosionModel not found")
	assert(_vertical_emitter != null, "VerticalEmitter not found")
	assert(_horizontal_emitter != null, "HorizontalEmitter not found")

	# WorldEnvironment for glow (must be created in code)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 5
	env.glow_strength = 1.0
	env.glow_bloom = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_model.add_child(world_env)

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

	# Aim cone in 2D direction (mapped to 3D XY plane)
	if _cone_dir.length_squared() > 0.0:
		vert_pm.direction = Vector3(_cone_dir.x, -_cone_dir.y, 0.0)
	if _cone_spread >= 0.0:
		vert_pm.spread = _cone_spread
	if _vert_velocity >= 0.0:
		vert_pm.initial_velocity_min = _vert_velocity * 0.6
		vert_pm.initial_velocity_max = _vert_velocity

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

	# Scale viewport and camera to fit the explosion.
	# Higher velocity = particles travel further = need more room.
	var max_vel: float = vert_pm.initial_velocity_max
	var cam_scale: float = maxf(max_vel / 10.0, 1.0)
	var camera: Camera3D = _model.get_node("Camera3D") as Camera3D
	camera.position *= cam_scale
	var container: SubViewportContainer = $SubViewportContainer
	var half_size: float = 32.0 * cam_scale
	container.offset_left = -half_size
	container.offset_top = -half_size
	container.offset_right = half_size
	container.offset_bottom = half_size

	# Apply scale
	if _effect_scale != 1.0:
		scale = Vector2.ONE * _effect_scale

	# Fire particles
	await get_tree().process_frame
	_vertical_emitter.emitting = false
	_horizontal_emitter.emitting = false
	_vertical_emitter.restart()
	_horizontal_emitter.restart()

	# Auto-free after particles finish
	await get_tree().create_timer(LIFETIME + 0.3).timeout
	queue_free()


func _process(delta: float) -> void:
	if _drift_velocity.length_squared() > 0.0:
		global_position += _drift_velocity * delta


## Convenience factory: spawns an explosion at the given world position.
## cone_dir optionally aims the vertical emitter's cone in a 2D direction.
static func create(
	parent: Node,
	pos: Vector2,
	cone_dir: Vector2 = Vector2.ZERO,
	cone_spread: float = -1.0,
	effect_scale: float = 1.0,
	vert_velocity: float = -1.0,
	drift_velocity: Vector2 = Vector2.ZERO,
) -> ExplosionEffect:
	var effect: ExplosionEffect = ExplosionScene.instantiate() as ExplosionEffect
	effect._cone_dir = cone_dir
	effect._cone_spread = cone_spread
	effect._effect_scale = effect_scale
	effect._vert_velocity = vert_velocity
	effect._drift_velocity = drift_velocity
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
