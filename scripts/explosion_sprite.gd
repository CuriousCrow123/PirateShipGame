class_name ExplosionSprite
extends Node2D
## Plays a pre-rendered explosion animation from a baked atlas.
## Drop-in replacement for ExplosionEffect — no SubViewport, no 3D particles.
## Atlases and metadata are baked by scripts/explosion_test.gd.

const META_PATH: String = "res://textures/explosions/atlas_meta.json"
const ATLAS_DIR: String = "res://textures/explosions"
const CONFIG_PATH: String = "res://resources/explosion_config.tres"

## Draw order: above ships (z=2) and cannonballs (z=3).
const EXPLOSION_Z_INDEX: int = 10

## Runtime toggle: when false, create() delegates to ExplosionEffect (real-time 3D).
static var use_sprite: bool = true

## Cached metadata and atlas textures — loaded once on first spawn.
static var _meta: Dictionary = {}
static var _atlases: Dictionary = {}

var _type_name: String
var _variation: Dictionary
var _fps: float
var _frame_count: int
var _elapsed: float = 0.0
var _drift_velocity: Vector2 = Vector2.ZERO
var _sprite: Sprite2D


## Spawns an explosion of the given type at the given position.
## [param type_name] one of "muzzle_flash", "cannonball_impact", "enemy_destruction", "sea_mine".
## [param direction] rotates the sprite for directional types; ignored for omnidirectional.
## [param drift_velocity] applied each frame so the effect follows momentum at spawn.
static func create(
	parent: Node,
	pos: Vector2,
	type_name: String,
	direction: Vector2 = Vector2.ZERO,
	drift_velocity: Vector2 = Vector2.ZERO,
) -> Node2D:
	_ensure_meta_loaded()
	assert(_meta.has(type_name), "Unknown explosion type: " + type_name)

	if not use_sprite:
		return _create_3d(parent, pos, type_name, direction, drift_velocity)

	var effect := ExplosionSprite.new()
	effect._type_name = type_name
	effect._drift_velocity = drift_velocity
	effect.z_index = EXPLOSION_Z_INDEX
	parent.add_child(effect)
	effect.global_position = pos

	# Atlases were captured at effect_scale = 1.0 (native viewport pixels),
	# so apply the per-type scale to match the original in-game size.
	var effect_scale: float = float(_meta[type_name].effect_scale)
	effect.scale = Vector2.ONE * effect_scale

	# Directional atlases (muzzle_flash, cannonball_impact) were baked with cone_dir = RIGHT,
	# so rotating by the direction's angle aligns them. Omnidirectional atlases are unaffected.
	if direction.length_squared() > 0.0:
		effect.rotation = direction.angle()

	return effect


func _ready() -> void:
	var type_data: Dictionary = _meta[_type_name]
	_fps = float(type_data.fps)

	# Pick a random variation for visual variety
	var variations: Array = type_data.variations
	_variation = variations[randi() % variations.size()]
	_frame_count = int(_variation.frame_count)

	var atlas_tex: Texture2D = _get_atlas(_type_name)
	var at := AtlasTexture.new()
	at.atlas = atlas_tex
	at.region = Rect2(
		0, float(_variation.row_y), float(_variation.frame_w), float(_variation.frame_h)
	)

	_sprite = Sprite2D.new()
	_sprite.texture = at
	_sprite.centered = false
	var origin: Array = _variation.origin
	_sprite.offset = Vector2(-float(origin[0]), -float(origin[1]))
	add_child(_sprite)


func _process(delta: float) -> void:
	if _drift_velocity.length_squared() > 0.0:
		global_position += _drift_velocity * delta

	_elapsed += delta
	var frame_idx: int = int(_elapsed * _fps)
	if frame_idx >= _frame_count:
		queue_free()
		return

	var at: AtlasTexture = _sprite.texture as AtlasTexture
	at.region = Rect2(
		float(frame_idx * int(_variation.frame_w)),
		float(_variation.row_y),
		float(_variation.frame_w),
		float(_variation.frame_h),
	)


## Delegates to the real-time ExplosionEffect using parameters that match
## what the original callsites passed before the sprite refactor.
static func _create_3d(
	parent: Node,
	pos: Vector2,
	type_name: String,
	direction: Vector2,
	drift_velocity: Vector2,
) -> Node2D:
	# Load the shared ExplosionConfig Resource. Because Godot caches Resources by path,
	# editing the .tres in the editor Inspector while the game runs updates the same
	# instance the game holds — so new spawns pick up the edits immediately.
	var config_res: ExplosionConfig = load(CONFIG_PATH) as ExplosionConfig
	var config: Dictionary = config_res.get_params(type_name)
	# Omnidirectional types were originally passed Vector2.UP as a placeholder.
	config["cone_dir"] = direction if direction.length_squared() > 0.0 else Vector2.UP
	config["drift_velocity"] = drift_velocity
	config["effect_scale"] = float(_meta[type_name].effect_scale)
	var effect: ExplosionEffect = ExplosionEffect.create(parent, pos, config)
	effect.z_index = EXPLOSION_Z_INDEX
	return effect


static func _ensure_meta_loaded() -> void:
	if not _meta.is_empty():
		return
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	assert(file != null, "atlas_meta.json missing — run explosion_test scene to regenerate")
	_meta = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()


static func _get_atlas(type_name: String) -> Texture2D:
	if _atlases.has(type_name):
		return _atlases[type_name]
	var atlas_file: String = _meta[type_name].atlas as String
	var tex: Texture2D = load("%s/%s" % [ATLAS_DIR, atlas_file]) as Texture2D
	_atlases[type_name] = tex
	return tex
