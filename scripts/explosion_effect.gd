class_name ExplosionEffect
extends Node2D
## Real-time 3D explosion rendered into a SubViewport and displayed in 2D.
## Spawns, plays, and auto-frees. Use ExplosionEffect.create() to spawn.
##
## Configuration is passed as a Dictionary. All keys are optional — missing keys
## leave the scene default in place. See _apply_config() for the full list.

const DEFAULT_LIFETIME: float = 1.2
const ExplosionScene: PackedScene = preload("res://scenes/explosion_effect.tscn")

var _config: Dictionary = {}
var _lifetime: float = DEFAULT_LIFETIME
var _drift_velocity: Vector2 = Vector2.ZERO

@onready var _model: SubViewport = $SubViewportContainer/ExplosionModel
@onready var _vertical_emitter: GPUParticles3D = _model.get_node("VerticalEmitter")
@onready var _horizontal_emitter: GPUParticles3D = _model.get_node("HorizontalEmitter")


func _ready() -> void:
	assert(_model != null, "ExplosionModel not found")
	assert(_vertical_emitter != null, "VerticalEmitter not found")
	assert(_horizontal_emitter != null, "HorizontalEmitter not found")

	_apply_config()

	# Fire particles
	await get_tree().process_frame
	_vertical_emitter.emitting = false
	_horizontal_emitter.emitting = false
	_vertical_emitter.restart()
	_horizontal_emitter.restart()

	# Auto-free after particles finish
	await get_tree().create_timer(_lifetime + 0.3).timeout
	queue_free()


func _process(delta: float) -> void:
	if _drift_velocity.length_squared() > 0.0:
		global_position += _drift_velocity * delta


## Reads every supported key from _config and applies it. Keys not present use
## the scene/shader defaults.
func _apply_config() -> void:
	# --- Drift, lifetime ---
	_drift_velocity = _config.get("drift_velocity", Vector2.ZERO)
	_lifetime = float(_config.get("lifetime", DEFAULT_LIFETIME))
	_vertical_emitter.lifetime = _lifetime
	_horizontal_emitter.lifetime = _lifetime

	# --- WorldEnvironment for glow (must be created in code) ---
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = bool(_config.get("glow_enabled", true))
	env.glow_intensity = float(_config.get("glow_intensity", 1.0))
	env.glow_strength = float(_config.get("glow_strength", 0.6))
	env.glow_bloom = float(_config.get("glow_bloom", 0.3))
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_model.add_child(world_env)

	# --- Particle counts ---
	if _config.has("vert_amount"):
		_vertical_emitter.amount = int(_config.vert_amount)
	if _config.has("horiz_amount"):
		_horizontal_emitter.amount = int(_config.horiz_amount)

	# --- Shader material (duplicated, applied as material_override on the emitter nodes
	# so we never mutate the shared SphereMesh sub-resource) ---
	var base_mat: ShaderMaterial = _vertical_emitter.draw_pass_1.surface_get_material(0)
	var mat: ShaderMaterial = base_mat.duplicate() as ShaderMaterial
	_vertical_emitter.material_override = mat
	_horizontal_emitter.material_override = mat
	_apply_shader_params(mat)

	# --- Process materials (duplicated for independence) ---
	var vert_pm: ParticleProcessMaterial = (
		_vertical_emitter.process_material.duplicate() as ParticleProcessMaterial
	)
	_vertical_emitter.process_material = vert_pm
	var horiz_pm: ParticleProcessMaterial = (
		_horizontal_emitter.process_material.duplicate() as ParticleProcessMaterial
	)
	_horizontal_emitter.process_material = horiz_pm

	# --- Vertical emitter cone/velocity ---
	var cone_dir: Vector2 = _config.get("cone_dir", Vector2.ZERO)
	if cone_dir.length_squared() > 0.0:
		vert_pm.direction = Vector3(cone_dir.x, -cone_dir.y, 0.0)
	if _config.has("cone_spread"):
		vert_pm.spread = float(_config.cone_spread)
	if _config.has("vert_velocity"):
		var v: float = float(_config.vert_velocity)
		vert_pm.initial_velocity_min = v * 0.6
		vert_pm.initial_velocity_max = v

	# --- Horizontal emitter velocity ---
	if _config.has("horiz_velocity_min"):
		horiz_pm.initial_velocity_min = float(_config.horiz_velocity_min)
	if _config.has("horiz_velocity_max"):
		horiz_pm.initial_velocity_max = float(_config.horiz_velocity_max)

	# --- Damping (single value sets both min and max) ---
	if _config.has("vert_damping"):
		vert_pm.damping_min = float(_config.vert_damping)
		vert_pm.damping_max = float(_config.vert_damping)
	if _config.has("horiz_damping"):
		horiz_pm.damping_min = float(_config.horiz_damping)
		horiz_pm.damping_max = float(_config.horiz_damping)

	# --- Particle scale (size of each sphere) ---
	if _config.has("particle_scale"):
		var ps: float = float(_config.particle_scale)
		for pm: ParticleProcessMaterial in [vert_pm, horiz_pm]:
			pm.scale_min = ps
			pm.scale_max = ps

	# --- Color ramp and scale curve (shared) ---
	var color_ramp: GradientTexture1D = _create_color_ramp()
	vert_pm.color_ramp = color_ramp
	horiz_pm.color_ramp = color_ramp
	var scale_tex: CurveTexture = _create_scale_curve()
	vert_pm.scale_curve = scale_tex
	horiz_pm.scale_curve = scale_tex

	# --- Turbulence ---
	var turb_strength: float = float(_config.get("turbulence_strength", 3.0))
	var turb_influence: float = float(_config.get("turbulence_influence", 0.25))
	for pm: ParticleProcessMaterial in [vert_pm, horiz_pm]:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = turb_strength
		pm.turbulence_noise_scale = 6.0
		pm.turbulence_influence_min = turb_influence * 0.4
		pm.turbulence_influence_max = turb_influence

	# --- Viewport/camera scale based on particle travel distance ---
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

	# --- 2D Node scale ---
	var effect_scale: float = float(_config.get("effect_scale", 1.0))
	if effect_scale != 1.0:
		scale = Vector2.ONE * effect_scale


func _apply_shader_params(mat: ShaderMaterial) -> void:
	# Every key is optional — if the caller omits it we leave the scene/shader default.
	if _config.has("dark_color"):
		mat.set_shader_parameter("DarkColour", _config.dark_color as Color)
	if _config.has("fire_color"):
		mat.set_shader_parameter("FireColour", _config.fire_color as Color)
	if _config.has("bright_alpha_scale"):
		mat.set_shader_parameter("BrightAlphaScale", float(_config.bright_alpha_scale))
	if _config.has("dark_alpha_scale"):
		mat.set_shader_parameter("DarkAlphaScale", float(_config.dark_alpha_scale))
	if _config.has("smooth_step_edge"):
		mat.set_shader_parameter("SmoothStepEdge", float(_config.smooth_step_edge))
	if _config.has("bright_dissolve_scale"):
		mat.set_shader_parameter("BrightDissolveScale", float(_config.bright_dissolve_scale))
	if _config.has("dark_dissolve_scale"):
		mat.set_shader_parameter("DarkDissolveScale", float(_config.dark_dissolve_scale))


## Factory: spawns an explosion at the given world position with the given config dict.
## All config keys are optional — see _apply_config() for the supported keys.
static func create(parent: Node, pos: Vector2, config: Dictionary = {}) -> ExplosionEffect:
	var effect: ExplosionEffect = ExplosionScene.instantiate() as ExplosionEffect
	effect._config = config
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
