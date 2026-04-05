## Run this scene with F6 (Run Current Scene) in the editor.
extends Control

const FRAME_COUNT: int = 8
const FRAME_SIZE: int = 32
const WARMUP_DELAY: float = 0.05
const OUTPUT_PATH: String = "res://textures/explosion_strip.png"

var _material: ShaderMaterial
var _capturing: bool = false

@onready var _emitter: GPUParticles3D = %Emitter
@onready var _sub_viewport: SubViewport = %SubViewport
@onready var _status_label: Label = %StatusLabel
@onready var _play_button: Button = %PlayButton
@onready var _capture_button: Button = %CaptureButton
@onready var _dark_color_picker: ColorPickerButton = %DarkColorPicker
@onready var _fire_color_picker: ColorPickerButton = %FireColorPicker
@onready var _smoothstep_slider: HSlider = %SmoothStepSlider
@onready var _speed_slider: HSlider = %SpeedSlider
@onready var _bright_dissolve_slider: HSlider = %BrightDissolveSlider
@onready var _dark_dissolve_slider: HSlider = %DarkDissolveSlider


func _ready() -> void:
	assert(_emitter != null, "Emitter node not found")
	assert(_sub_viewport != null, "SubViewport node not found")
	assert(_status_label != null, "StatusLabel node not found")
	assert(_play_button != null, "PlayButton node not found")
	assert(_capture_button != null, "CaptureButton node not found")

	# Duplicate material to avoid mutating the .tres on disk.
	# NoiseTexture inside is intentionally shared (read-only).
	var base_mat: ShaderMaterial = _emitter.draw_pass_1.surface_get_material(0)
	_material = base_mat.duplicate() as ShaderMaterial
	_emitter.draw_pass_1.surface_set_material(0, _material)

	# Connect UI signals
	_play_button.pressed.connect(_on_play_pressed)
	_capture_button.pressed.connect(_on_capture_pressed)
	_dark_color_picker.color_changed.connect(_on_dark_color_changed)
	_fire_color_picker.color_changed.connect(_on_fire_color_changed)
	_smoothstep_slider.value_changed.connect(_on_smoothstep_changed)
	_speed_slider.value_changed.connect(_on_speed_changed)
	_bright_dissolve_slider.value_changed.connect(_on_bright_dissolve_changed)
	_dark_dissolve_slider.value_changed.connect(_on_dark_dissolve_changed)

	# Set initial UI values from material defaults
	_dark_color_picker.color = Color(0.3, 0.3, 0.3)
	_fire_color_picker.color = Color(1.0, 0.5, 0.0)
	_smoothstep_slider.value = 0.0
	_speed_slider.value = 1.0
	_bright_dissolve_slider.value = 1.2
	_dark_dissolve_slider.value = 0.8

	_status_label.text = "Ready"

	# Wait one frame for GPU particle init (issue #101758)
	await get_tree().process_frame
	_play_explosion()


func _play_explosion() -> void:
	_emitter.emitting = false
	_emitter.restart()


func _set_controls_enabled(enabled: bool) -> void:
	_play_button.disabled = not enabled
	_capture_button.disabled = not enabled
	_dark_color_picker.disabled = not enabled
	_fire_color_picker.disabled = not enabled
	_smoothstep_slider.editable = enabled
	_speed_slider.editable = enabled
	_bright_dissolve_slider.editable = enabled
	_dark_dissolve_slider.editable = enabled


# --- Signal callbacks ---


func _on_play_pressed() -> void:
	if _capturing:
		return
	_play_explosion()
	_status_label.text = "Playing..."


func _on_capture_pressed() -> void:
	if _capturing:
		return
	_capturing = true
	_set_controls_enabled(false)
	_capture_button.text = "Capturing..."
	assert(OS.has_feature("editor"), "This tool only works in the editor")

	# Restart explosion for capture
	_play_explosion()

	# Wait warmup for GPU particle latency
	await get_tree().create_timer(WARMUP_DELAY).timeout

	var strip: Image = Image.create(FRAME_SIZE * FRAME_COUNT, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	var capture_duration: float = _emitter.lifetime
	var interval: float = (capture_duration - WARMUP_DELAY) / float(FRAME_COUNT)

	for i: int in FRAME_COUNT:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_sub_viewport):
			_capturing = false
			return
		var img: Image = _sub_viewport.get_texture().get_image()
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


func _on_dark_color_changed(color: Color) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("DarkColour", Vector3(color.r, color.g, color.b))


func _on_fire_color_changed(color: Color) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("FireColour", Vector3(color.r, color.g, color.b))


func _on_smoothstep_changed(value: float) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("SmoothStepEdge", value)


func _on_speed_changed(value: float) -> void:
	if _capturing:
		return
	_emitter.speed_scale = value


func _on_bright_dissolve_changed(value: float) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("BrightDissolveScale", value)


func _on_dark_dissolve_changed(value: float) -> void:
	if _capturing:
		return
	_material.set_shader_parameter("DarkDissolveScale", value)
