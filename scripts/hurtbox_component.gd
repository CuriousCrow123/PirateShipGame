class_name HurtboxComponent
extends Node2D

## Owns the Area2D used by incoming-damage detection. Emits hit_taken when
## a damage source overlaps; the entity root listens and forwards to its
## HealthComponent. The Area2D is a child Node — collision layer/mask live
## on the Area2D, NOT this Node.
##
## Extends Node2D (not Node like the rest of the component family) because
## the child Area2D is a CanvasItem: Godot's 2D transform chain only walks
## through CanvasItem ancestors, so a plain-Node parent would strand the
## Area2D at world origin (0,0) instead of tracking the entity. Keeping the
## Hurtbox itself at local (0,0) means the Area2D's shape is authored in
## entity-local coordinates as usual.
##
## Phase 4 Step 23: extracted from ship.gd's damage entry path. The legacy
## Ship.take_damage(direction) signature is preserved as a public method
## that forwards into here so cannonball/sea_mine don't need to change in
## the same commit (the area-detection path is added in addition to the
## body-detection path; sea_mine still uses a physics shape query).

signal hit_taken(source: Node)

@export_node_path("Area2D") var area_path: NodePath = ^"Area2D"

var _area: Area2D = null


func _ready() -> void:
	set_physics_process(false)
	set_process(false)
	_area = get_node(area_path) as Area2D
	assert(_area != null, "HurtboxComponent: Area2D child not found at %s" % area_path)
	_area.area_entered.connect(_on_area_entered)


## Toggle the hurtbox on/off. Uses set_deferred so callers can flip
## monitoring inside a contact callback without "can't change state during
## query flush" errors.
func set_active(active: bool) -> void:
	if _area == null:
		return
	_area.set_deferred("monitoring", active)
	_area.set_deferred("monitorable", active)


## Direct entry point for damage sources that don't use area collision yet
## (sea_mine uses a physics shape query against bodies; cannonball still
## uses body_entered for enemy targets). Forwards to hit_taken for parity
## with the area-detected path.
func process_hit(source: Node) -> void:
	hit_taken.emit(source)


func _on_area_entered(area: Area2D) -> void:
	hit_taken.emit(_resolve_entity(area))


## Walk area.owner to resolve the entity root. Public so future Hurtbox
## subscribers can resolve sources from raw area refs.
static func resolve_entity(area: Area2D) -> Node:
	if area == null:
		return null
	if area.owner != null:
		return area.owner
	return area


func _resolve_entity(area: Area2D) -> Node:
	return HurtboxComponent.resolve_entity(area)
