class_name ExplosionAtlasPlayer
extends Node2D
## Loads explosion atlases from atlas_meta.json and plays all 20 variations on loop.

const META_PATH: String = "res://features/vfx/textures/explosions/atlas_meta.json"
const ATLAS_DIR: String = "res://features/vfx/textures/explosions"

var _sprites: Array[Sprite2D] = []
var _variations: Array[Dictionary] = []
var _elapsed: float = 0.0


func _ready() -> void:
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	assert(file != null, "Could not open atlas_meta.json")
	var meta: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	# Layout: 4 rows (types) × 5 columns (variations)
	var types: Array = meta.keys()
	types.sort()
	var cell_w: float = 640.0 / 5.0
	var cell_h: float = 360.0 / 4.0

	for row: int in range(types.size()):
		var base_name: String = types[row] as String
		var type_data: Dictionary = meta[base_name]
		var atlas_path: String = "%s/%s" % [ATLAS_DIR, type_data.atlas as String]
		var atlas_tex: Texture2D = load(atlas_path) as Texture2D
		var fps: float = float(type_data.fps)
		var variations: Array = type_data.variations

		for col: int in range(variations.size()):
			var var_data: Dictionary = variations[col]
			var fw: int = int(var_data.frame_w)
			var fh: int = int(var_data.frame_h)
			var row_y: int = int(var_data.row_y)
			var origin: Array = var_data.origin

			var at := AtlasTexture.new()
			at.atlas = atlas_tex
			at.region = Rect2(0, row_y, fw, fh)

			var sprite := Sprite2D.new()
			sprite.texture = at
			sprite.centered = false
			sprite.offset = Vector2(-float(origin[0]), -float(origin[1]))
			sprite.position = Vector2(cell_w * col + cell_w / 2.0, cell_h * row + cell_h / 2.0)
			add_child(sprite)

			_sprites.append(sprite)
			(
				_variations
				. append(
					{
						"frame_w": fw,
						"frame_h": fh,
						"row_y": row_y,
						"frame_count": int(var_data.frame_count),
						"fps": fps,
					}
				)
			)

		# Row label
		var label := Label.new()
		label.text = base_name
		label.position = Vector2(4, cell_h * row + 2)
		label.add_theme_font_size_override("font_size", 10)
		add_child(label)


func _process(delta: float) -> void:
	_elapsed += delta
	for i: int in range(_sprites.size()):
		var v: Dictionary = _variations[i]
		var frame_idx: int = int(_elapsed * v.fps) % int(v.frame_count)
		var at: AtlasTexture = _sprites[i].texture as AtlasTexture
		at.region = Rect2(frame_idx * v.frame_w, v.row_y, v.frame_w, v.frame_h)
