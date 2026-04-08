extends Node2D
## Side-by-side comparison + live tuning panel for the stylized flame shader.
## Left:  high-resolution 3D mesh (256x256 native, LINEAR upscale)
## Right: pixel-art version (64x64 native, NEAREST upscale)
## Right panel: scrollable HSliders that write to BOTH meshes' shader uniforms.
##
## Geometry: a single procedural lathe mesh (DashFlameLathe) replaces the old
## sphere + cone composite, eliminating the seam where their normals were
## discontinuous. Profile is driven by 3 sliders: dome_radius, tail_length,
## tail_sharpness. The shared SHADER MATERIAL still lives at
## resources/dash_flame_material.tres and is referenced by both viewports here
## and by scenes/dash_fire_model.tscn so live tuning still propagates.
## SAVE persists the material to disk via ResourceSaver. The lathe profile
## values are written to res://features/vfx/stylized_flame_snapshot.json so the
## game-side scene can rebuild the same shape.

const SNAPSHOT_PATH: String = "res://features/vfx/stylized_flame_snapshot.json"
const MATERIAL_PATH: String = "res://features/vfx/dash_flame_material.tres"
const PROFILE_PATH: String = "res://features/vfx/dash_flame_profile.tres"

var _flame_meshes: Array[MeshInstance3D] = []
var _material: ShaderMaterial
var _profile: DashFlameProfile
var _save_status_label: Label

@onready var _hires_sphere: MeshInstance3D = $HiResContainer/HiResViewport/FlameSphere
@onready var _hires_cone: MeshInstance3D = $HiResContainer/HiResViewport/FlameCone
@onready var _pixel_sphere: MeshInstance3D = $PixelContainer/PixelViewport/FlameSphere
@onready var _pixel_cone: MeshInstance3D = $PixelContainer/PixelViewport/FlameCone
@onready var _controls: VBoxContainer = $ControlsScroll/Controls


func _ready() -> void:
	# Hide the old per-primitive cone nodes — the new lathe replaces both.
	_hires_cone.visible = false
	_pixel_cone.visible = false

	# Premultiplied-alpha blit so partially-dissolved pixels fade smoothly
	# instead of darkening to black (the SubViewport with transparent_bg
	# writes premultiplied colors; the default container blends straight-alpha
	# and would multiply RGB by alpha a second time). Mirrors dash_fire_effect.
	for container: SubViewportContainer in [
		$HiResContainer as SubViewportContainer, $PixelContainer as SubViewportContainer
	]:
		var blit_mat: CanvasItemMaterial = CanvasItemMaterial.new()
		blit_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		container.material = blit_mat

	_material = load(MATERIAL_PATH) as ShaderMaterial
	assert(_material != null, "StylizedFlameTest: failed to load shared ShaderMaterial")
	_profile = load(PROFILE_PATH) as DashFlameProfile
	assert(_profile != null, "StylizedFlameTest: failed to load shared DashFlameProfile")

	_flame_meshes = [_hires_sphere, _pixel_sphere]
	_rebuild_lathe()

	_build_controls()


func _rebuild_lathe() -> void:
	var mesh: ArrayMesh = DashFlameLathe.build(
		_profile.bulge_radius, _profile.tail_length, _profile.dome_radius
	)
	mesh.surface_set_material(0, _material)
	# Match dash_fire_effect.gd: rotate 180° around X so the dome points down
	# (toward -Y in 3D) — this is the same orientation the game renders.
	for node: MeshInstance3D in _flame_meshes:
		node.mesh = mesh
		node.transform = Transform3D(Basis(Vector3(1, 0, 0), PI), Vector3.ZERO)


func _build_controls() -> void:
	_build_save_row()

	_section("PROFILE")
	_float_slider("bulge_radius", 0.1, 2.5, _profile.bulge_radius, 0.05, _on_bulge_radius)
	_float_slider("tail_length", 0.1, 4.0, _profile.tail_length, 0.05, _on_tail_length)
	_float_slider("dome_radius", 0.1, 2.5, _profile.dome_radius, 0.05, _on_dome_radius)

	_section("MOTION")
	_float_slider(
		"TimeSpeed", 0.0, 8.0, _material.get_shader_parameter("TimeSpeed"), 0.05, _on_time_speed
	)
	_float_slider("Spin", -2.0, 2.0, _material.get_shader_parameter("Spin"), 0.01, _on_spin)

	_section("SHAPE")
	_float_slider("Size", -1.5, 1.5, _material.get_shader_parameter("Size"), 0.01, _on_size)
	_float_slider(
		"CoreSize", 0.1, 4.0, _material.get_shader_parameter("CoreSize"), 0.05, _on_core_size
	)
	_float_slider(
		"HorizontalFrequency",
		0.1,
		8.0,
		_material.get_shader_parameter("HorizontalFrequency"),
		0.05,
		_on_horizontal_frequency
	)
	_float_slider(
		"VerticalFrequency",
		0.1,
		8.0,
		_material.get_shader_parameter("VerticalFrequency"),
		0.05,
		_on_vertical_frequency
	)

	_section("BRIGHTNESS")
	_float_slider(
		"FlameBrightness",
		0.0,
		4.0,
		_material.get_shader_parameter("FlameBrightness"),
		0.05,
		_on_flame_brightness
	)
	_float_slider(
		"ColorIntensity",
		-2.0,
		2.0,
		_material.get_shader_parameter("ColorIntensity"),
		0.01,
		_on_color_intensity
	)
	_float_slider("Opacity", 0.0, 1.0, _material.get_shader_parameter("Opacity"), 0.01, _on_opacity)
	_float_slider(
		"Dissolve", 0.0, 1.0, _material.get_shader_parameter("Dissolve"), 0.01, _on_dissolve
	)

	_section("COLOR 1 (core)")
	_color_sliders("Color1", _material.get_shader_parameter("Color1") as Color)

	_section("COLOR 2")
	_color_sliders("Color2", _material.get_shader_parameter("Color2") as Color)

	_section("COLOR 3")
	_color_sliders("Color3", _material.get_shader_parameter("Color3") as Color)

	_section("COLOR 4 (outer)")
	_color_sliders("Color4", _material.get_shader_parameter("Color4") as Color)


# --- UI builders ---


func _build_save_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var save_btn: Button = Button.new()
	save_btn.text = "  SAVE  "
	save_btn.pressed.connect(_save_to_disk)
	row.add_child(save_btn)

	_save_status_label = Label.new()
	_save_status_label.text = "(values not saved)"
	_save_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(_save_status_label)

	_controls.add_child(row)


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
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)

	var slider: HSlider = HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(160, 0)
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


func _color_sliders(uniform_name: String, initial: Color) -> void:
	_float_slider(
		"  R",
		0.0,
		1.0,
		initial.r,
		0.01,
		func(v: float) -> void: _set_color_channel(uniform_name, 0, v)
	)
	_float_slider(
		"  G",
		0.0,
		1.0,
		initial.g,
		0.01,
		func(v: float) -> void: _set_color_channel(uniform_name, 1, v)
	)
	_float_slider(
		"  B",
		0.0,
		1.0,
		initial.b,
		0.01,
		func(v: float) -> void: _set_color_channel(uniform_name, 2, v)
	)


func _set_color_channel(uniform_name: String, channel: int, v: float) -> void:
	var col: Color = _material.get_shader_parameter(uniform_name) as Color
	match channel:
		0:
			col.r = v
		1:
			col.g = v
		2:
			col.b = v
	_material.set_shader_parameter(uniform_name, col)


# --- Callbacks ---


func _set_param(uniform_name: String, value: float) -> void:
	_material.set_shader_parameter(uniform_name, value)


func _on_bulge_radius(v: float) -> void:
	_profile.bulge_radius = v
	_rebuild_lathe()


func _on_tail_length(v: float) -> void:
	_profile.tail_length = v
	_rebuild_lathe()


func _on_dome_radius(v: float) -> void:
	_profile.dome_radius = v
	_rebuild_lathe()


func _on_time_speed(v: float) -> void:
	_set_param("TimeSpeed", v)


func _on_spin(v: float) -> void:
	_set_param("Spin", v)


func _on_size(v: float) -> void:
	_set_param("Size", v)


func _on_core_size(v: float) -> void:
	_set_param("CoreSize", v)


func _on_horizontal_frequency(v: float) -> void:
	_set_param("HorizontalFrequency", v)


func _on_vertical_frequency(v: float) -> void:
	_set_param("VerticalFrequency", v)


func _on_flame_brightness(v: float) -> void:
	_set_param("FlameBrightness", v)


func _on_color_intensity(v: float) -> void:
	_set_param("ColorIntensity", v)


func _on_opacity(v: float) -> void:
	_set_param("Opacity", v)


func _on_dissolve(v: float) -> void:
	_set_param("Dissolve", v)


# --- Save to disk ---


func _save_to_disk() -> void:
	# Persist the in-memory mutations of the shared resources back to their
	# .tres files. The next time the game (or this test scene) loads, the
	# updated values flow through the shared resource cache.
	var failures: PackedStringArray = PackedStringArray()
	for res: Resource in [_material, _profile]:
		var err: int = ResourceSaver.save(res)
		if err != OK:
			failures.append("%s (err %d)" % [res.resource_path, err])
		else:
			print("Saved: %s" % res.resource_path)

	# Also dump a JSON snapshot for archival / debugging.
	var snapshot: Dictionary = _build_snapshot_dict()
	var file: FileAccess = FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(snapshot, "  "))
		file.close()
		print("JSON snapshot: %s" % SNAPSHOT_PATH)
	else:
		failures.append("%s (FileAccess error %d)" % [SNAPSHOT_PATH, FileAccess.get_open_error()])

	var stamp: String = Time.get_time_string_from_system()
	if failures.size() == 0:
		_save_status_label.text = "saved at %s" % stamp
		_save_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	else:
		_save_status_label.text = "FAILED: %s" % ", ".join(failures)
		_save_status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		push_error("Save failures: %s" % ", ".join(failures))


func _build_snapshot_dict() -> Dictionary:
	return {
		"profile":
		{
			"bulge_radius": _profile.bulge_radius,
			"tail_length": _profile.tail_length,
			"dome_radius": _profile.dome_radius,
		},
		"shader":
		{
			"TimeSpeed": _material.get_shader_parameter("TimeSpeed"),
			"Spin": _material.get_shader_parameter("Spin"),
			"Size": _material.get_shader_parameter("Size"),
			"CoreSize": _material.get_shader_parameter("CoreSize"),
			"HorizontalFrequency": _material.get_shader_parameter("HorizontalFrequency"),
			"VerticalFrequency": _material.get_shader_parameter("VerticalFrequency"),
			"FlameBrightness": _material.get_shader_parameter("FlameBrightness"),
			"ColorIntensity": _material.get_shader_parameter("ColorIntensity"),
			"Color1": _color_to_dict(_material.get_shader_parameter("Color1") as Color),
			"Color2": _color_to_dict(_material.get_shader_parameter("Color2") as Color),
			"Color3": _color_to_dict(_material.get_shader_parameter("Color3") as Color),
			"Color4": _color_to_dict(_material.get_shader_parameter("Color4") as Color),
		}
	}


func _color_to_dict(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
