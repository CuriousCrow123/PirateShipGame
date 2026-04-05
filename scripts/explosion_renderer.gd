## Run this scene with F6 (Run Current Scene) in the editor.
extends Control

const FRAME_COUNT: int = 16
const FRAME_SIZE: int = 32
const WARMUP_DELAY: float = 0.05
const OUTPUT_PATH: String = "res://textures/explosion_strip.png"
const MODEL_SCENE_PATH: String = "res://scenes/explosion_model.tscn"

var _material: ShaderMaterial
var _capturing: bool = false
var _vert_process_mat: ParticleProcessMaterial
var _horiz_process_mat: ParticleProcessMaterial

@onready var _model: SubViewport = $HBoxContainer/SubViewportContainer/ExplosionModel
@onready
var _vertical_emitter: GPUParticles3D = $HBoxContainer/SubViewportContainer/ExplosionModel/VerticalEmitter
@onready
var _horizontal_emitter: GPUParticles3D = $HBoxContainer/SubViewportContainer/ExplosionModel/HorizontalEmitter
@onready var _camera: Camera3D = $HBoxContainer/SubViewportContainer/ExplosionModel/Camera3D
@onready var _status_label: Label = %StatusLabel
@onready var _play_button: Button = %PlayButton
@onready var _capture_button: Button = %CaptureButton
@onready var _save_model_button: Button = %SaveModelButton
@onready var _dark_color_picker: ColorPickerButton = %DarkColorPicker
@onready var _fire_color_picker: ColorPickerButton = %FireColorPicker
@onready var _emission_slider: HSlider = %EmissionSlider
@onready var _smoothstep_slider: HSlider = %SmoothStepSlider
@onready var _speed_slider: HSlider = %SpeedSlider
@onready var _bright_dissolve_slider: HSlider = %BrightDissolveSlider
@onready var _dark_dissolve_slider: HSlider = %DarkDissolveSlider
@onready var _cam_orbit_slider: HSlider = %CamOrbitSlider
@onready var _cam_elevation_slider: HSlider = %CamElevationSlider
@onready var _cam_distance_slider: HSlider = %CamDistanceSlider
@onready var _vert_velocity_slider: HSlider = %VertVelocitySlider
@onready var _vert_damping_slider: HSlider = %VertDampingSlider
@onready var _vert_spread_slider: HSlider = %VertSpreadSlider
@onready var _horiz_velocity_slider: HSlider = %HorizVelocitySlider
@onready var _horiz_damping_slider: HSlider = %HorizDampingSlider
@onready var _loop_timer: Timer = %LoopTimer


func _ready() -> void:
	# Override project display settings — the game uses 640x360 viewport
	# which is too small for a tool UI. Render at native window resolution.
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color.WHITE)

	assert(_model != null, "ExplosionModel not found")
	assert(_vertical_emitter != null, "VerticalEmitter node not found")
	assert(_horizontal_emitter != null, "HorizontalEmitter node not found")
	assert(_camera != null, "Camera3D node not found")
	assert(_status_label != null, "StatusLabel node not found")
	assert(_play_button != null, "PlayButton node not found")
	assert(_capture_button != null, "CaptureButton node not found")
	assert(_save_model_button != null, "SaveModelButton node not found")

	# Add WorldEnvironment with glow to the SubViewport (created in code
	# because Godot strips it from .tscn on re-save).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 1.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_model.add_child(world_env)

	# Override particle lifetime in code (Godot reverts .tscn edits on re-save)
	_vertical_emitter.lifetime = 1.2
	_horizontal_emitter.lifetime = 1.2

	# Duplicate materials to avoid mutating resources on disk.
	var base_mat: ShaderMaterial = _vertical_emitter.draw_pass_1.surface_get_material(0)
	_material = base_mat.duplicate() as ShaderMaterial
	_vertical_emitter.draw_pass_1.surface_set_material(0, _material)
	_horizontal_emitter.draw_pass_1.surface_set_material(0, _material)

	_vert_process_mat = _vertical_emitter.process_material.duplicate() as ParticleProcessMaterial
	_vertical_emitter.process_material = _vert_process_mat
	_horiz_process_mat = _horizontal_emitter.process_material.duplicate() as ParticleProcessMaterial
	_horizontal_emitter.process_material = _horiz_process_mat

	# Color ramp: white -> yellow -> orange -> dark red -> transparent
	var color_ramp := _create_explosion_color_ramp()
	_vert_process_mat.color_ramp = color_ramp
	_horiz_process_mat.color_ramp = color_ramp

	# Scale curve: quick grow then shrink
	var scale_curve := _create_explosion_scale_curve()
	_vert_process_mat.scale_curve = scale_curve
	_horiz_process_mat.scale_curve = scale_curve

	# Turbulence for organic motion
	_vert_process_mat.turbulence_enabled = true
	_vert_process_mat.turbulence_noise_strength = 3.0
	_vert_process_mat.turbulence_noise_scale = 6.0
	_vert_process_mat.turbulence_influence_min = 0.1
	_vert_process_mat.turbulence_influence_max = 0.25
	_horiz_process_mat.turbulence_enabled = true
	_horiz_process_mat.turbulence_noise_strength = 3.0
	_horiz_process_mat.turbulence_noise_scale = 6.0
	_horiz_process_mat.turbulence_influence_min = 0.1
	_horiz_process_mat.turbulence_influence_max = 0.25

	# Connect UI signals
	_play_button.pressed.connect(_on_play_pressed)
	_capture_button.pressed.connect(_on_capture_pressed)
	_save_model_button.pressed.connect(_on_save_model_pressed)
	_dark_color_picker.color_changed.connect(_on_dark_color_changed)
	_fire_color_picker.color_changed.connect(_on_fire_color_changed)
	_emission_slider.value_changed.connect(_on_emission_changed)
	_smoothstep_slider.value_changed.connect(_on_smoothstep_changed)
	_speed_slider.value_changed.connect(_on_speed_changed)
	_bright_dissolve_slider.value_changed.connect(_on_bright_dissolve_changed)
	_dark_dissolve_slider.value_changed.connect(_on_dark_dissolve_changed)
	_cam_orbit_slider.value_changed.connect(_on_camera_changed)
	_cam_elevation_slider.value_changed.connect(_on_camera_changed)
	_cam_distance_slider.value_changed.connect(_on_camera_changed)
	_vert_velocity_slider.value_changed.connect(_on_vert_velocity_changed)
	_vert_damping_slider.value_changed.connect(_on_vert_damping_changed)
	_vert_spread_slider.value_changed.connect(_on_vert_spread_changed)
	_horiz_velocity_slider.value_changed.connect(_on_horiz_velocity_changed)
	_horiz_damping_slider.value_changed.connect(_on_horiz_damping_changed)
	_loop_timer.timeout.connect(_on_loop_timeout)

	# Set initial UI values
	_dark_color_picker.color = Color(0.3, 0.3, 0.3)
	_fire_color_picker.color = Color(1.0, 0.5, 0.0)
	_smoothstep_slider.value = 0.0
	_speed_slider.value = 1.0
	_bright_dissolve_slider.value = 1.2
	_dark_dissolve_slider.value = 0.8
	_cam_orbit_slider.value = 0.0
	_cam_elevation_slider.value = 20.0
	_cam_distance_slider.value = 8.0
	_vert_velocity_slider.value = _vert_process_mat.initial_velocity_max
	_vert_damping_slider.value = _vert_process_mat.damping_max
	_vert_spread_slider.value = _vert_process_mat.spread
	_horiz_velocity_slider.value = _horiz_process_mat.initial_velocity_max
	_horiz_damping_slider.value = _horiz_process_mat.damping_max

	_status_label.text = "Ready"
	_update_camera()

	# Wait one frame for GPU particle init (issue #101758)
	await get_tree().process_frame
	_play_explosion()


func _play_explosion() -> void:
	_vertical_emitter.emitting = false
	_horizontal_emitter.emitting = false
	_vertical_emitter.restart()
	_horizontal_emitter.restart()
	# Restart loop timer — wait a bit longer than lifetime for full dissolve
	_loop_timer.start(_vertical_emitter.lifetime + 0.5)


func _set_controls_enabled(enabled: bool) -> void:
	_play_button.disabled = not enabled
	_capture_button.disabled = not enabled
	_save_model_button.disabled = not enabled
	_dark_color_picker.disabled = not enabled
	_fire_color_picker.disabled = not enabled
	_smoothstep_slider.editable = enabled
	_speed_slider.editable = enabled
	_bright_dissolve_slider.editable = enabled
	_dark_dissolve_slider.editable = enabled
	_vert_velocity_slider.editable = enabled
	_vert_damping_slider.editable = enabled
	_vert_spread_slider.editable = enabled
	_horiz_velocity_slider.editable = enabled
	_horiz_damping_slider.editable = enabled


# --- Save model ---


func _on_save_model_pressed() -> void:
	if _capturing:
		return
	# Load a fresh instance, apply current slider values, and save.
	# This avoids saving runtime-only state (duplicated materials, color ramps, etc).
	var source: PackedScene = load(MODEL_SCENE_PATH) as PackedScene
	var fresh: SubViewport = source.instantiate() as SubViewport

	var vert: GPUParticles3D = fresh.get_node("VerticalEmitter") as GPUParticles3D
	var horiz: GPUParticles3D = fresh.get_node("HorizontalEmitter") as GPUParticles3D
	var cam: Camera3D = fresh.get_node("Camera3D") as Camera3D

	# Apply particle params from sliders
	var vert_pm: ParticleProcessMaterial = vert.process_material as ParticleProcessMaterial
	vert_pm.initial_velocity_min = _vert_velocity_slider.value * 0.6
	vert_pm.initial_velocity_max = _vert_velocity_slider.value
	vert_pm.damping_min = _vert_damping_slider.value * 0.6
	vert_pm.damping_max = _vert_damping_slider.value
	vert_pm.spread = _vert_spread_slider.value

	var horiz_pm: ParticleProcessMaterial = horiz.process_material as ParticleProcessMaterial
	horiz_pm.initial_velocity_min = _horiz_velocity_slider.value * 0.5
	horiz_pm.initial_velocity_max = _horiz_velocity_slider.value
	horiz_pm.damping_min = _horiz_damping_slider.value * 0.6
	horiz_pm.damping_max = _horiz_damping_slider.value

	# Apply camera transform
	cam.transform = _camera.transform

	var packed := PackedScene.new()
	var pack_err: Error = packed.pack(fresh)
	if pack_err != OK:
		_status_label.text = "Pack error: %s" % error_string(pack_err)
		fresh.free()
		return

	var save_err: Error = ResourceSaver.save(packed, MODEL_SCENE_PATH)
	fresh.free()

	if save_err == OK:
		_status_label.text = "Model saved!"
	else:
		_status_label.text = "Save error: %s" % error_string(save_err)


# --- Signal callbacks ---


func _on_play_pressed() -> void:
	if _capturing:
		return
	_play_explosion()
	_status_label.text = "Playing..."


func _on_loop_timeout() -> void:
	if _capturing:
		return
	_play_explosion()


func _on_capture_pressed() -> void:
	if _capturing:
		return
	_capturing = true
	_loop_timer.stop()
	_set_controls_enabled(false)
	_capture_button.text = "Capturing..."
	assert(OS.has_feature("editor"), "This tool only works in the editor")

	# Restart explosion for capture
	_play_explosion()
	_loop_timer.stop()  # Don't loop during capture

	# Wait warmup for GPU particle latency
	await get_tree().create_timer(WARMUP_DELAY).timeout

	var strip: Image = Image.create(FRAME_SIZE * FRAME_COUNT, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	var capture_duration: float = _vertical_emitter.lifetime
	var interval: float = (capture_duration - WARMUP_DELAY) / float(FRAME_COUNT)

	for i: int in FRAME_COUNT:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_model):
			_capturing = false
			return
		var img: Image = _model.get_texture().get_image()
		# SubViewportContainer stretch resizes the viewport; resize to output size
		if img.get_width() != FRAME_SIZE or img.get_height() != FRAME_SIZE:
			img.resize(FRAME_SIZE, FRAME_SIZE, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(img, Rect2i(0, 0, FRAME_SIZE, FRAME_SIZE), Vector2i(i * FRAME_SIZE, 0))
		_status_label.text = "Frame %d/%d..." % [i + 1, FRAME_COUNT]

		# Wait remaining interval before next frame
		if i < FRAME_COUNT - 1:
			var wait_time: float = interval - (1.0 / 60.0)  # subtract approx frame time
			if wait_time > 0.0:
				await get_tree().create_timer(wait_time).timeout

	var err: Error = strip.save_png(OUTPUT_PATH)
	if err != OK:
		_status_label.text = "Error saving: %s" % error_string(err)
	else:
		_status_label.text = "Saved: %s" % OUTPUT_PATH

	_capture_button.text = "Capture"
	_set_controls_enabled(true)
	_capturing = false
	_loop_timer.start()  # Resume looping


func _on_dark_color_changed(color: Color) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("DarkColour", Vector3(color.r, color.g, color.b))


func _on_fire_color_changed(color: Color) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("FireColour", Vector3(color.r, color.g, color.b))


func _on_emission_changed(value: float) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("EmissionIntensity", value)


func _on_smoothstep_changed(value: float) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("DissolveSoftness", value)


func _on_speed_changed(value: float) -> void:
	if _capturing:
		return
	_vertical_emitter.speed_scale = value
	_horizontal_emitter.speed_scale = value


func _on_bright_dissolve_changed(value: float) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("DissolveSpeed", value)


func _on_dark_dissolve_changed(value: float) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("EdgeGlowWidth", value)


func _on_vert_velocity_changed(value: float) -> void:
	if _capturing:
		return
	_vert_process_mat.initial_velocity_min = value * 0.6
	_vert_process_mat.initial_velocity_max = value


func _on_vert_damping_changed(value: float) -> void:
	if _capturing:
		return
	_vert_process_mat.damping_min = value * 0.6
	_vert_process_mat.damping_max = value


func _on_vert_spread_changed(value: float) -> void:
	if _capturing:
		return
	_vert_process_mat.spread = value


func _on_horiz_velocity_changed(value: float) -> void:
	if _capturing:
		return
	_horiz_process_mat.initial_velocity_min = value * 0.5
	_horiz_process_mat.initial_velocity_max = value


func _on_horiz_damping_changed(value: float) -> void:
	if _capturing:
		return
	_horiz_process_mat.damping_min = value * 0.6
	_horiz_process_mat.damping_max = value


func _on_camera_changed(_value: float) -> void:
	if _capturing:
		return
	_update_camera()


func _update_camera() -> void:
	var orbit_deg: float = _cam_orbit_slider.value
	var elevation_deg: float = _cam_elevation_slider.value
	var dist: float = _cam_distance_slider.value
	var orbit_rad: float = deg_to_rad(orbit_deg)
	var elevation_rad: float = deg_to_rad(elevation_deg)

	# Spherical coordinates to cartesian
	var y: float = dist * sin(elevation_rad)
	var horizontal_dist: float = dist * cos(elevation_rad)
	var x: float = horizontal_dist * sin(orbit_rad)
	var z: float = horizontal_dist * cos(orbit_rad)

	_camera.position = Vector3(x, y, z)
	_camera.look_at(Vector3.ZERO)


static func _create_explosion_color_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.1, 0.3, 0.55, 0.8, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 0.95, 1.0),  # White flash
			Color(1.0, 0.85, 0.3, 1.0),  # Bright yellow
			Color(1.0, 0.45, 0.05, 1.0),  # Orange fire
			Color(0.5, 0.12, 0.0, 0.9),  # Dark red
			Color(0.2, 0.15, 0.1, 0.5),  # Smoke
			Color(0.1, 0.08, 0.05, 0.0),  # Fade out
		]
	)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


static func _create_explosion_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.1))  # Start small
	curve.add_point(Vector2(0.15, 1.0))  # Quick grow
	curve.add_point(Vector2(0.5, 0.7))  # Hold
	curve.add_point(Vector2(1.0, 0.1))  # Shrink away
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex
