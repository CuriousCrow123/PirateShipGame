class_name DashFireEffect
extends Node2D
## 3D stylized flame (single procedural lathe, stylized_flame.gdshader) rendered
## into a SubViewport for pixel-art crunch. Driven from Ship._start_dash /
## _end_dash / _tick_dash_visuals.
##
## The shader has no DashStrength uniform — instead, the burst envelope is
## driven by multiplying FlameBrightness by the intensity_curve sample. The
## SubViewport stays UPDATE_DISABLED + invisible when no dash is active so
## idle GPU cost is zero.
##
## Geometry: DashFlameLathe.build() generates one continuous mesh from a single
## cubic Bezier (no piecewise join). Profile values must stay in sync with
## scripts/stylized_flame_test.gd.
##
## Anchoring: the mesh is rotated 180° around X so the wide dome lands at the
## BOTTOM of the viewport (the thrust nozzle, near the ship), and the tail tip
## projects to the TOP (extending behind). _ready() then projects both endpoints
## through the camera and sets the SubViewportContainer's offset rect so that
## the dome pixel lands EXACTLY on the SternMarker (Node2D origin) and the tail
## extends in -Y. This eliminates manual offset tuning — the only knobs are the
## viewport pixel size below and the lathe profile constants.

const _BRIGHTNESS_PARAM: String = "FlameBrightness"
const _DISSOLVE_PARAM: String = "Dissolve"
const _MATERIAL_PATH: String = "res://resources/dash_flame_material.tres"
const _PROFILE_PATH: String = "res://resources/dash_flame_profile.tres"
const _VIEWPORT_SIZE: Vector2i = Vector2i(11, 19)
# Dissipation duration after stop(): the flame ramps Dissolve 0->1 over this
# many seconds (driven from _process), eroding the tail tip first, then the
# dome, before the SubViewport is finally disabled.
const _DISSOLVE_DURATION: float = 0.35

var _material: ShaderMaterial
var _profile: DashFlameProfile
var _base_brightness: float = 1.0
# Negative = idle. >= 0 = dissolving; counts up to _DISSOLVE_DURATION.
var _dissolve_t: float = -1.0

@onready var _container: SubViewportContainer = $SubViewportContainer
@onready var _model: SubViewport = $SubViewportContainer/DashFireModel
@onready var _sphere: MeshInstance3D = _model.get_node("FlameSphere")
@onready var _cone: MeshInstance3D = _model.get_node("FlameCone")
@onready var _camera: Camera3D = _model.get_node("Camera3D")


func _ready() -> void:
	assert(_container != null, "DashFireEffect: SubViewportContainer node is missing")
	assert(_model != null, "DashFireEffect: DashFireModel SubViewport is missing")
	assert(_sphere != null, "DashFireEffect: FlameSphere is missing")
	assert(_cone != null, "DashFireEffect: FlameCone is missing")
	assert(_camera != null, "DashFireEffect: Camera3D is missing")
	# Duplicate the shared shader material so per-burst FlameBrightness writes
	# don't leak into the test scene's live-tuning material.
	var base_mat: ShaderMaterial = load(_MATERIAL_PATH) as ShaderMaterial
	assert(base_mat != null, "DashFireEffect: failed to load shared ShaderMaterial")
	_material = base_mat.duplicate() as ShaderMaterial
	_profile = load(_PROFILE_PATH) as DashFlameProfile
	assert(_profile != null, "DashFireEffect: failed to load shared DashFlameProfile")
	# Replace the scene's primitive mesh with the procedural lathe and hide the
	# old cone node. Rotate 180° around X so the dome (wide thrust end) points
	# toward -Y in 3D — that puts it at the BOTTOM of the viewport, near the
	# stern when blitted into 2D.
	var lathe: ArrayMesh = DashFlameLathe.build(
		_profile.bulge_radius, _profile.tail_length, _profile.dome_radius
	)
	lathe.surface_set_material(0, _material)
	_sphere.mesh = lathe
	_sphere.transform = Transform3D(Basis(Vector3(1, 0, 0), PI), Vector3.ZERO)
	_cone.visible = false
	# Premultiplied-alpha compositing for the SubViewport blit. Inside the 3D
	# viewport, blend_mix against transparent_bg writes the texture as
	# (rgb*alpha, alpha) — premultiplied. The default 2D SubViewportContainer
	# blends with straight alpha and would multiply RGB by alpha a second time,
	# turning partially-dissolved flame pixels black instead of fading them. A
	# CanvasItemMaterial with BLEND_MODE_PREMULT_ALPHA matches the source.
	var blit_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	blit_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_container.material = blit_mat
	# Counter-scale this Node2D so the SubViewport blit is 1:1 with screen
	# pixels regardless of parent transforms (the Ship has scale=0.5 which
	# would otherwise downsample the 32×56 viewport to 16×28 screen pixels and
	# produce a different look from the test scene). global_scale walks the
	# parent chain, so we just invert it on self before our own children pick
	# up our transform.
	var parent_scale: Vector2 = global_scale
	if parent_scale.x != 0.0 and parent_scale.y != 0.0:
		scale = Vector2(1.0 / parent_scale.x, 1.0 / parent_scale.y)
	# stretch=true makes the SubViewport mirror the container size, so size the
	# container first; the viewport follows automatically.
	var w: float = float(_VIEWPORT_SIZE.x)
	var h: float = float(_VIEWPORT_SIZE.y)
	_container.offset_left = -w * 0.5
	_container.offset_right = w * 0.5
	_container.offset_top = -h
	_container.offset_bottom = 0.0
	_anchor_dome_to_stern()
	_base_brightness = _material.get_shader_parameter(_BRIGHTNESS_PARAM)
	_model.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visible = false


# Project the post-flip dome (3D y = -dome_radius) and tail tip (3D y = +tail_length)
# through the Camera3D, then shift the container vertically so the dome pixel
# lands at this Node2D's origin (the SternMarker). The container width/height
# stay as set above; only the Y offsets move. 1:1 viewport-pixel : container-pixel
# — the parent ship's 0.5 scale halves the on-screen size.
func _anchor_dome_to_stern() -> void:
	var dome_world: Vector3 = Vector3(0.0, -_profile.dome_radius, 0.0)
	var dome_px: Vector2 = _camera.unproject_position(dome_world)
	var h: float = float(_VIEWPORT_SIZE.y)
	_container.offset_top = -dome_px.y
	_container.offset_bottom = -dome_px.y + h


## Called from Ship._start_dash. Records the burst's base FlameBrightness from
## the config (so set_dash_strength can ramp it via the curve), turns on the
## SubViewport, and reveals the flame. Cancels any in-flight dissolve so a
## re-trigger during dissipation snaps back to a fresh full-strength burst.
func start(config: DashConfig) -> void:
	if config == null:
		return
	_base_brightness = config.flame_brightness
	_material.set_shader_parameter(_BRIGHTNESS_PARAM, 0.0)
	_material.set_shader_parameter(_DISSOLVE_PARAM, 0.0)
	_dissolve_t = -1.0
	_model.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visible = true


## Called from Ship._end_dash. Begins the dissipation: keeps the SubViewport
## rendering and the flame visible while _process ramps Dissolve 0->1 over
## _DISSOLVE_DURATION, then disables the viewport once fully gone.
func stop() -> void:
	_dissolve_t = 0.0


## Called from Ship._tick_dash_visuals at render rate. Multiplies the base
## brightness by the curve sample (0..1) to produce the burst envelope.
func set_dash_strength(value: float) -> void:
	_material.set_shader_parameter(_BRIGHTNESS_PARAM, _base_brightness * value)


# Advances the post-stop dissipation. The shader's noise-erosion dissolve mask
# does all the visual work — brightness stays at the burst's last value so the
# surviving flame chunks keep their full color until they burn away. When
# Dissolve hits 1.0 the SubViewport finally stops rendering and the flame hides.
func _process(delta: float) -> void:
	if _dissolve_t < 0.0:
		return
	_dissolve_t += delta
	var t: float = clampf(_dissolve_t / _DISSOLVE_DURATION, 0.0, 1.0)
	_material.set_shader_parameter(_DISSOLVE_PARAM, t)
	if t >= 1.0:
		_dissolve_t = -1.0
		_material.set_shader_parameter(_DISSOLVE_PARAM, 0.0)
		_material.set_shader_parameter(_BRIGHTNESS_PARAM, 0.0)
		_model.render_target_update_mode = SubViewport.UPDATE_DISABLED
		visible = false
