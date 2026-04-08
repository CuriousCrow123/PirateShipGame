class_name WaterChunkManager
extends Node2D
## Manages dynamic ocean chunk loading around the ship.
## Creates/frees TileMapLayer nodes as the ship moves through the world.
## Each chunk is CHUNK_SIZE×CHUNK_SIZE tiles (256×256 px at 16px tiles).

const CHUNK_SIZE: int = 16
const TILE_PX: int = 16
const LOAD_RADIUS: int = 2

@export var ship: CharacterBody2D
@export var tile_set: TileSet
@export var water_material: Material

var _loaded_chunks: Dictionary = {}
var _last_chunk_coord: Vector2i = Vector2i(999999, 999999)


func _ready() -> void:
	assert(ship != null, "WaterChunks: ship export must be assigned")
	assert(tile_set != null, "WaterChunks: tile_set export must be assigned")
	assert(water_material != null, "WaterChunks: water_material export must be assigned")
	_update_chunks(_get_chunk_coord(ship.global_position))


func _process(_delta: float) -> void:
	var chunk_coord: Vector2i = _get_chunk_coord(ship.global_position)
	if chunk_coord == _last_chunk_coord:
		return
	_update_chunks(chunk_coord)


func _get_chunk_coord(world_pos: Vector2) -> Vector2i:
	var chunk_px: int = CHUNK_SIZE * TILE_PX
	return Vector2i(floori(world_pos.x / chunk_px), floori(world_pos.y / chunk_px))


func _update_chunks(center: Vector2i) -> void:
	_last_chunk_coord = center

	var desired: Dictionary = {}
	for x: int in range(center.x - LOAD_RADIUS, center.x + LOAD_RADIUS + 1):
		for y: int in range(center.y - LOAD_RADIUS, center.y + LOAD_RADIUS + 1):
			desired[Vector2i(x, y)] = true

	# Unload chunks no longer needed
	var to_remove: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		if not desired.has(coord):
			to_remove.append(coord)
	for coord: Vector2i in to_remove:
		_loaded_chunks[coord].queue_free()
		_loaded_chunks.erase(coord)

	# Load new chunks
	for coord: Vector2i in desired:
		if not _loaded_chunks.has(coord):
			_loaded_chunks[coord] = _create_chunk(coord)


func _create_chunk(coord: Vector2i) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.material = water_material
	layer.position = Vector2(coord.x * CHUNK_SIZE * TILE_PX, coord.y * CHUNK_SIZE * TILE_PX)
	layer.name = "Chunk_%d_%d" % [coord.x, coord.y]

	for x: int in range(CHUNK_SIZE):
		for y: int in range(CHUNK_SIZE):
			layer.set_cell(Vector2i(x, y), 0, Vector2i(1, 20))

	add_child(layer)
	return layer
