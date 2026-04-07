class_name DashFireEffect
extends Node2D
## 3D stylized fire rendered into a SubViewport and displayed via
## SubViewportContainer for pixel-art crunch. Driven from Ship._start_dash /
## _end_dash / _tick_dash_visuals.
##
## The SubViewport renders only while a burst is active (UPDATE_ALWAYS during
## the dash, DISABLED otherwise). The shader's DashStrength uniform is pushed
## from the ship's _process at render rate so the burst envelope stays smooth
## on high-refresh-rate displays.

var _material: ShaderMaterial

@onready var _container: SubViewportContainer = $SubViewportContainer
@onready var _model: SubViewport = $SubViewportContainer/DashFireModel
@onready var _emitter: GPUParticles3D = _model.get_node("FireEmitter")


func _ready() -> void:
	assert(_container != null, "DashFireEffect: SubViewportContainer node is missing")
	assert(_model != null, "DashFireEffect: DashFireModel SubViewport is missing")
	assert(_emitter != null, "DashFireEffect: FireEmitter GPUParticles3D is missing")
	# Duplicate the shader material as a material_override on the emitter so
	# live-tuned uniforms don't leak through the shared QuadMesh sub-resource.
	# (Mirrors docs/solutions/godot-shared-mesh-surface-material.md.)
	var base_mat: ShaderMaterial = _emitter.draw_pass_1.surface_get_material(0)
	assert(base_mat != null, "DashFireEffect: QuadMesh material is missing")
	_material = base_mat.duplicate() as ShaderMaterial
	_emitter.material_override = _material
	_model.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Called from Ship._start_dash. Pushes the current DashConfig values onto the
## shader uniforms, restarts the emitter, and turns the SubViewport on.
func start(config: DashConfig) -> void:
	if config == null:
		return
	if config.fire_noise_texture != null:
		_material.set_shader_parameter("NoiseTexture", config.fire_noise_texture)
	if config.fire_mask_texture != null:
		_material.set_shader_parameter("MaskTexture", config.fire_mask_texture)
	if config.fire_color_ramp != null:
		_material.set_shader_parameter("ColorRamp", config.fire_color_ramp)
	_material.set_shader_parameter("TextureScale", config.fire_texture_scale)
	_material.set_shader_parameter("TimeScale", config.fire_time_scale)
	_material.set_shader_parameter("EdgeSoftness", config.fire_edge_softness)
	_material.set_shader_parameter("EmissionIntensity", config.fire_emission_intensity)
	_material.set_shader_parameter("DashStrength", 0.0)

	_model.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_emitter.emitting = false
	_emitter.restart()
	_emitter.emitting = true
	visible = true


## Called from Ship._end_dash. Resets DashStrength so the next burst doesn't
## render stale state, then stops new emissions. In-flight particles still die
## naturally; once the lifetime elapses we disable the SubViewport entirely.
func stop() -> void:
	_material.set_shader_parameter("DashStrength", 0.0)
	_emitter.emitting = false
	# Schedule SubViewport shutdown after particles fully die out.
	get_tree().create_timer(_emitter.lifetime + 0.1).timeout.connect(
		func() -> void:
			if is_instance_valid(self) and not _emitter.emitting:
				_model.render_target_update_mode = SubViewport.UPDATE_DISABLED
				visible = false
	)


## Called from Ship._tick_dash_visuals at render rate. Pushes the curve-sampled
## envelope onto the shader uniform.
func set_dash_strength(value: float) -> void:
	_material.set_shader_parameter("DashStrength", value)
