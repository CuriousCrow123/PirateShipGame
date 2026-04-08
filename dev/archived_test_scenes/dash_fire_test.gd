extends Node2D
## Side-by-side comparison + live tuning panel for the dash fire effect.
## Left:  high-resolution 3D fire (128x256 native) — raw spatial shader output
## Right: pixel-art version (32x64 native, upscaled) — what the dash uses
## Far right: scrollable HSlider panel that writes every parameter into BOTH
##            emitters' process_material and ShaderMaterial in real time.
##
## The shader's per-particle erosion is driven by ParticleProcessMaterial's
## color_ramp (vertex COLOR.rgba), so the particles fade naturally over their
## lifetime. To start/stop the burst, just flip GPUParticles3D.emitting.

var _emitters: Array[GPUParticles3D] = []
var _process_materials: Array[ParticleProcessMaterial] = []
var _shader_materials: Array[ShaderMaterial] = []
var _scale_curves: Array[Curve] = []
var _color_gradients: Array[Gradient] = []

@onready var _hires_emitter: GPUParticles3D = $HiResContainer/HiResViewport/FireEmitter
@onready var _pixel_emitter: GPUParticles3D = $PixelContainer/PixelViewport/FireEmitter
@onready var _controls: VBoxContainer = $ControlsScroll/Controls


func _ready() -> void:
	_emitters = [_hires_emitter, _pixel_emitter]
	# Duplicate process materials, shader materials, scale curves, and gradients
	# per emitter so the panel writes don't leak through shared sub-resources.
	for emitter: GPUParticles3D in _emitters:
		var pm: ParticleProcessMaterial = (
			emitter.process_material.duplicate(true) as ParticleProcessMaterial
		)
		emitter.process_material = pm
		_process_materials.append(pm)

		var base_shader_mat: ShaderMaterial = emitter.draw_pass_1.surface_get_material(0)
		var sm: ShaderMaterial = base_shader_mat.duplicate() as ShaderMaterial
		emitter.material_override = sm
		_shader_materials.append(sm)

		# Scale curve (CurveTexture wraps a Curve sub-resource).
		var scale_tex: CurveTexture = pm.scale_curve as CurveTexture
		if scale_tex != null and scale_tex.curve != null:
			var curve_copy: Curve = scale_tex.curve.duplicate() as Curve
			scale_tex.curve = curve_copy
			_scale_curves.append(curve_copy)

		# Color ramp (GradientTexture1D wraps a Gradient sub-resource).
		var color_tex: GradientTexture1D = pm.color_ramp as GradientTexture1D
		if color_tex != null and color_tex.gradient != null:
			var grad_copy: Gradient = color_tex.gradient.duplicate() as Gradient
			color_tex.gradient = grad_copy
			_color_gradients.append(grad_copy)

		emitter.emitting = true

	_build_controls()


func _build_controls() -> void:
	var first_pm: ParticleProcessMaterial = _process_materials[0]
	var first_sm: ShaderMaterial = _shader_materials[0]
	var first_emitter: GPUParticles3D = _emitters[0]

	_section("EMISSION")
	_int_slider("amount", 1, 200, first_emitter.amount, _on_amount)
	_float_slider("lifetime", 0.1, 4.0, first_emitter.lifetime, 0.05, _on_lifetime)
	_float_slider("randomness", 0.0, 1.0, first_emitter.randomness, 0.01, _on_randomness)
	_float_slider(
		"lifetime_randomness", 0.0, 1.0, first_pm.lifetime_randomness, 0.01, _on_lifetime_randomness
	)

	_section("MOTION")
	_float_slider(
		"initial_velocity_min", 0.0, 10.0, first_pm.initial_velocity_min, 0.05, _on_init_vel_min
	)
	_float_slider(
		"initial_velocity_max", 0.0, 10.0, first_pm.initial_velocity_max, 0.05, _on_init_vel_max
	)
	_float_slider(
		"linear_accel_min", 0.0, 30.0, first_pm.linear_accel_min, 0.1, _on_linear_accel_min
	)
	_float_slider(
		"linear_accel_max", 0.0, 30.0, first_pm.linear_accel_max, 0.1, _on_linear_accel_max
	)
	_float_slider("spread (deg)", 0.0, 90.0, first_pm.spread, 1.0, _on_spread)
	_float_slider("gravity_y", -20.0, 20.0, first_pm.gravity.y, 0.1, _on_gravity_y)
	_float_slider("damping_min", 0.0, 30.0, first_pm.damping_min, 0.1, _on_damping_min)
	_float_slider("damping_max", 0.0, 30.0, first_pm.damping_max, 0.1, _on_damping_max)

	_section("SCALE")
	_float_slider("scale_min", 0.0, 5.0, first_pm.scale_min, 0.05, _on_scale_min)
	_float_slider("scale_max", 0.0, 5.0, first_pm.scale_max, 0.05, _on_scale_max)
	_float_slider("scale curve start", 0.0, 2.0, _curve_y_at_index(0), 0.01, _on_curve_start.bind())
	_float_slider(
		"scale curve peak Y", 0.0, 2.0, _curve_y_at_index(1), 0.01, _on_curve_peak_y.bind()
	)
	_float_slider(
		"scale curve peak X", 0.01, 0.99, _curve_x_at_index(1), 0.01, _on_curve_peak_x.bind()
	)
	_float_slider("scale curve end", 0.0, 2.0, _curve_y_at_index(2), 0.01, _on_curve_end.bind())

	_section("SHADER")
	_float_slider(
		"emission_intensity",
		0.0,
		8.0,
		first_sm.get_shader_parameter("EmissionIntensity"),
		0.05,
		_on_emission_intensity
	)
	_float_slider(
		"time_scale", 0.1, 12.0, first_sm.get_shader_parameter("TimeScale"), 0.05, _on_time_scale
	)
	_float_slider(
		"edge_softness",
		0.0,
		1.0,
		first_sm.get_shader_parameter("EdgeSoftness"),
		0.005,
		_on_edge_softness
	)
	var ts: Vector2 = first_sm.get_shader_parameter("TextureScale") as Vector2
	_float_slider("texture_scale x", 0.1, 5.0, ts.x, 0.05, _on_tex_scale_x)
	_float_slider("texture_scale y", 0.1, 5.0, ts.y, 0.05, _on_tex_scale_y)

	_section("COLOR (start)")
	var start_color: Color = (
		_color_gradients[0].colors[0] if _color_gradients.size() > 0 else Color.WHITE
	)
	_float_slider("start R", 0.0, 1.0, start_color.r, 0.01, _on_start_r)
	_float_slider("start G", 0.0, 1.0, start_color.g, 0.01, _on_start_g)
	_float_slider("start B", 0.0, 1.0, start_color.b, 0.01, _on_start_b)
	_float_slider("start A", 0.0, 1.0, start_color.a, 0.01, _on_start_a)

	_section("COLOR (end)")
	var end_color: Color = (
		_color_gradients[0].colors[_color_gradients[0].colors.size() - 1]
		if _color_gradients.size() > 0
		else Color.WHITE
	)
	_float_slider("end R", 0.0, 1.0, end_color.r, 0.01, _on_end_r)
	_float_slider("end G", 0.0, 1.0, end_color.g, 0.01, _on_end_g)
	_float_slider("end B", 0.0, 1.0, end_color.b, 0.01, _on_end_b)
	_float_slider("end A", 0.0, 1.0, end_color.a, 0.01, _on_end_a)


# --- UI builders ---


func _section(title: String) -> void:
	var label: Label = Label.new()
	label.text = "── %s ──" % title
	label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_controls.add_child(label)


func _float_slider(
	label_text: String, lo: float, hi: float, initial: float, step: float, cb: Callable
) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label: Label = Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)

	var slider: HSlider = HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(180, 0)
	row.add_child(slider)

	var value_label: Label = Label.new()
	value_label.text = "%.2f" % initial
	value_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(value_label)

	slider.value_changed.connect(
		func(new_value: float) -> void:
			value_label.text = "%.2f" % new_value
			cb.call(new_value)
	)
	_controls.add_child(row)


func _int_slider(label_text: String, lo: int, hi: int, initial: int, cb: Callable) -> void:
	_float_slider(
		label_text,
		float(lo),
		float(hi),
		float(initial),
		1.0,
		func(v: float) -> void: cb.call(int(v))
	)


# --- Callbacks (apply to all emitters) ---


func _on_amount(v: int) -> void:
	for e: GPUParticles3D in _emitters:
		e.amount = v
		e.restart()


func _on_lifetime(v: float) -> void:
	for e: GPUParticles3D in _emitters:
		e.lifetime = v


func _on_randomness(v: float) -> void:
	for e: GPUParticles3D in _emitters:
		e.randomness = v


func _on_lifetime_randomness(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.lifetime_randomness = v


func _on_init_vel_min(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.initial_velocity_min = v


func _on_init_vel_max(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.initial_velocity_max = v


func _on_linear_accel_min(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.linear_accel_min = v


func _on_linear_accel_max(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.linear_accel_max = v


func _on_spread(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.spread = v


func _on_gravity_y(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.gravity = Vector3(0, v, 0)


func _on_damping_min(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.damping_min = v


func _on_damping_max(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.damping_max = v


func _on_scale_min(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.scale_min = v


func _on_scale_max(v: float) -> void:
	for pm: ParticleProcessMaterial in _process_materials:
		pm.scale_max = v


func _curve_x_at_index(index: int) -> float:
	if _scale_curves.size() == 0 or index >= _scale_curves[0].point_count:
		return 0.0
	return _scale_curves[0].get_point_position(index).x


func _curve_y_at_index(index: int) -> float:
	if _scale_curves.size() == 0 or index >= _scale_curves[0].point_count:
		return 0.0
	return _scale_curves[0].get_point_position(index).y


func _on_curve_start(v: float) -> void:
	for c: Curve in _scale_curves:
		c.set_point_value(0, v)


func _on_curve_peak_y(v: float) -> void:
	for c: Curve in _scale_curves:
		c.set_point_value(1, v)


func _on_curve_peak_x(v: float) -> void:
	for c: Curve in _scale_curves:
		var pos: Vector2 = c.get_point_position(1)
		c.set_point_offset(1, v)
		c.set_point_value(1, pos.y)


func _on_curve_end(v: float) -> void:
	for c: Curve in _scale_curves:
		c.set_point_value(c.point_count - 1, v)


func _on_emission_intensity(v: float) -> void:
	for sm: ShaderMaterial in _shader_materials:
		sm.set_shader_parameter("EmissionIntensity", v)


func _on_time_scale(v: float) -> void:
	for sm: ShaderMaterial in _shader_materials:
		sm.set_shader_parameter("TimeScale", v)


func _on_edge_softness(v: float) -> void:
	for sm: ShaderMaterial in _shader_materials:
		sm.set_shader_parameter("EdgeSoftness", v)


func _on_tex_scale_x(v: float) -> void:
	for sm: ShaderMaterial in _shader_materials:
		var ts: Vector2 = sm.get_shader_parameter("TextureScale") as Vector2
		sm.set_shader_parameter("TextureScale", Vector2(v, ts.y))


func _on_tex_scale_y(v: float) -> void:
	for sm: ShaderMaterial in _shader_materials:
		var ts: Vector2 = sm.get_shader_parameter("TextureScale") as Vector2
		sm.set_shader_parameter("TextureScale", Vector2(ts.x, v))


func _set_color_component(index: int, channel: int, v: float) -> void:
	for grad: Gradient in _color_gradients:
		var col: Color = grad.colors[index]
		match channel:
			0:
				col.r = v
			1:
				col.g = v
			2:
				col.b = v
			3:
				col.a = v
		grad.set_color(index, col)


func _on_start_r(v: float) -> void:
	_set_color_component(0, 0, v)


func _on_start_g(v: float) -> void:
	_set_color_component(0, 1, v)


func _on_start_b(v: float) -> void:
	_set_color_component(0, 2, v)


func _on_start_a(v: float) -> void:
	_set_color_component(0, 3, v)


func _on_end_r(v: float) -> void:
	if _color_gradients.size() == 0:
		return
	_set_color_component(_color_gradients[0].colors.size() - 1, 0, v)


func _on_end_g(v: float) -> void:
	if _color_gradients.size() == 0:
		return
	_set_color_component(_color_gradients[0].colors.size() - 1, 1, v)


func _on_end_b(v: float) -> void:
	if _color_gradients.size() == 0:
		return
	_set_color_component(_color_gradients[0].colors.size() - 1, 2, v)


func _on_end_a(v: float) -> void:
	if _color_gradients.size() == 0:
		return
	_set_color_component(_color_gradients[0].colors.size() - 1, 3, v)
