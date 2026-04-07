class_name ExplosionTest
extends Node2D
## Captures each explosion variant's SubViewport into sprite sheets and atlases.
## Each type gets one atlas PNG with all variations stacked as rows.
## Auto-saves to res://textures/explosions/.

const CAPTURE_FPS: int = 20
const CAPTURE_INTERVAL: float = 1.0 / CAPTURE_FPS
const TRIM_PADDING: int = 2
const ALPHA_CUTOFF: int = 10  # 0-255; strips faint glow bleed
const VARIATIONS: int = 10
const OUTPUT_DIR: String = "res://textures/explosions"

## [name, cone_dir, cone_spread, effect_scale, vert_velocity]
## Matches the actual create() calls in the game.
const VARIANTS: Array = [
	["muzzle_flash", Vector2.RIGHT, 0.0, 0.25, 100.0],
	["cannonball_impact", Vector2.RIGHT, 45.0, 1.0, 15.0],
	["enemy_destruction", Vector2.UP, 360.0, 1.0, 55.0],
	["sea_mine", Vector2.UP, 360.0, 1.5, 80.0],
]

## Aggregated metadata across all atlases, written to JSON at the end.
var _atlas_meta: Dictionary = {}

@onready var _status_label: Label = $Title


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_capture_all_variants()


func _capture_all_variants() -> void:
	for variant: Array in VARIANTS:
		var base_name: String = variant[0] as String
		var cone_dir: Vector2 = variant[1] as Vector2
		var cone_spread: float = variant[2] as float
		var effect_scale: float = variant[3] as float
		var vert_velocity: float = variant[4] as float

		# Capture 5 variations of this type, accumulate in a local list only
		var type_variations: Array = []

		for v: int in range(VARIATIONS):
			var vname: String = "%s_%d" % [base_name, v + 1]
			_status_label.text = "Capturing: %s..." % vname
			print("Capturing %s..." % vname)

			var effect: ExplosionEffect = (
				ExplosionEffect
				. create(
					self,
					Vector2(320, 180),
					{
						"cone_dir": cone_dir,
						"cone_spread": cone_spread,
						"effect_scale": 1.0,
						"vert_velocity": vert_velocity,
					}
				)
			)

			# Wait for effect to initialize (its _ready awaits one process_frame)
			await get_tree().process_frame
			await get_tree().process_frame

			var viewport: SubViewport = effect.get_node("SubViewportContainer/ExplosionModel")
			var native_size: int = viewport.size.x

			# Capture frames at fixed interval
			var frames: Array[Image] = []
			var elapsed: float = 0.0
			while elapsed < ExplosionEffect.DEFAULT_LIFETIME:
				await RenderingServer.frame_post_draw
				elapsed += get_process_delta_time()
				var target_count: int = int(elapsed / CAPTURE_INTERVAL) + 1
				if frames.size() < target_count and is_instance_valid(viewport):
					frames.append(viewport.get_texture().get_image())

			var var_data: Dictionary = _process_variation(vname, frames, native_size)
			if not var_data.is_empty():
				type_variations.append(var_data)

			await get_tree().create_timer(0.5).timeout

		# Build this type's atlas immediately so we release frame memory before the next type
		_build_atlas_for_type(base_name, type_variations, cone_dir, cone_spread, effect_scale)
		type_variations.clear()

	# Save aggregated metadata JSON after all types are done
	var json_path: String = "%s/atlas_meta.json" % OUTPUT_DIR
	var json_str: String = JSON.stringify(_atlas_meta, "\t")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	file.store_string(json_str)
	file.close()
	print("Saved metadata to %s" % json_path)

	var total: int = VARIANTS.size() * VARIATIONS
	_status_label.text = "Done! Captured %d variations." % total
	print("All atlases saved to %s" % OUTPUT_DIR)


## Thresholds frames, computes crop, returns { cropped_frames, frame_w, frame_h, origin }.
func _process_variation(vname: String, frames: Array[Image], native_size: int) -> Dictionary:
	if frames.is_empty():
		push_warning("No frames captured for %s" % vname)
		return {}

	# Threshold faint pixels before computing bounds
	for i: int in range(frames.size()):
		_threshold_alpha(frames[i])

	# Find union bounding rect across all non-empty frames
	var union_rect := Rect2i()
	var has_first: bool = false
	for i: int in range(frames.size()):
		var used: Rect2i = frames[i].get_used_rect()
		if used.size.x == 0 or used.size.y == 0:
			continue
		if not has_first:
			union_rect = used
			has_first = true
		else:
			union_rect = union_rect.merge(used)

	union_rect = union_rect.grow(TRIM_PADDING)
	union_rect = union_rect.intersection(Rect2i(0, 0, native_size, native_size))

	# Explosion origin is at viewport center; compute where it lands in the cropped frame
	var origin_in_crop := Vector2(
		native_size / 2.0 - union_rect.position.x,
		native_size / 2.0 - union_rect.position.y,
	)

	var cw: int = union_rect.size.x
	var ch: int = union_rect.size.y

	# Collect cropped frames
	var cropped_frames: Array[Image] = []
	for i: int in range(frames.size()):
		cropped_frames.append(frames[i].get_region(union_rect))

	print(
		(
			"  %s: %d frames, frame %dx%d, origin (%.0f, %.0f)"
			% [vname, frames.size(), cw, ch, origin_in_crop.x, origin_in_crop.y]
		)
	)

	return {
		"cropped_frames": cropped_frames,
		"frame_w": cw,
		"frame_h": ch,
		"origin": origin_in_crop,
	}


## Builds one atlas PNG for a single explosion type.
## Each row = one variation. Atlas width = max row width, height = sum of row heights.
func _build_atlas_for_type(
	base_name: String,
	variations: Array,
	cone_dir: Vector2,
	cone_spread: float,
	effect_scale: float,
) -> void:
	if variations.is_empty():
		return

	# Compute atlas dimensions
	var max_row_width: int = 0
	var total_height: int = 0
	for var_data: Dictionary in variations:
		var row_width: int = var_data.frame_w * var_data.cropped_frames.size()
		max_row_width = maxi(max_row_width, row_width)
		total_height += var_data.frame_h

	# Create atlas and blit rows
	var atlas := Image.create(max_row_width, total_height, false, Image.FORMAT_RGBA8)
	var y_offset: int = 0
	var variation_meta: Array = []

	for var_data: Dictionary in variations:
		var fw: int = var_data.frame_w
		var fh: int = var_data.frame_h
		var cropped_frames: Array = var_data.cropped_frames
		for f_idx: int in range(cropped_frames.size()):
			(
				atlas
				. blit_rect(
					cropped_frames[f_idx] as Image,
					Rect2i(0, 0, fw, fh),
					Vector2i(f_idx * fw, y_offset),
				)
			)
		(
			variation_meta
			. append(
				{
					"row_y": y_offset,
					"frame_w": fw,
					"frame_h": fh,
					"frame_count": cropped_frames.size(),
					"origin": [var_data.origin.x, var_data.origin.y],
				}
			)
		)
		y_offset += fh

	var atlas_path: String = "%s/%s_atlas.png" % [OUTPUT_DIR, base_name]
	atlas.save_png(atlas_path)
	print(
		(
			"Saved atlas: %s (%dx%d, %d variations)"
			% [atlas_path, max_row_width, total_height, variations.size()]
		)
	)

	_atlas_meta[base_name] = {
		"atlas": "%s_atlas.png" % base_name,
		"atlas_size": [max_row_width, total_height],
		"cone_dir": [cone_dir.x, cone_dir.y],
		"cone_spread": cone_spread,
		"effect_scale": effect_scale,
		"fps": CAPTURE_FPS,
		"variations": variation_meta,
	}


static func _threshold_alpha(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = img.get_data()
	for i: int in range(3, data.size(), 4):
		if data[i] < ALPHA_CUTOFF:
			data[i] = 0
			data[i - 1] = 0
			data[i - 2] = 0
			data[i - 3] = 0
	var clean := Image.create_from_data(
		img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data
	)
	img.copy_from(clean)
