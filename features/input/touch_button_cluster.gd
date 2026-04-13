class_name TouchButtonCluster
extends Control
## Arranges four TouchActionButtons in a 2x2 grid anchored to the
## bottom-right of the viewport. Each button maps to a gameplay action.

const BUTTON_SIZE: Vector2 = Vector2(40.0, 40.0)
const GAP: float = 4.0

@onready var _fire_port: TouchActionButton = $FirePort
@onready var _fire_starboard: TouchActionButton = $FireStarboard
@onready var _mine: TouchActionButton = $Mine
@onready var _dash: TouchActionButton = $Dash


func _ready() -> void:
	assert(_fire_port != null, "TouchButtonCluster: FirePort not found")
	assert(_fire_starboard != null, "TouchButtonCluster: FireStarboard not found")
	assert(_mine != null, "TouchButtonCluster: Mine not found")
	assert(_dash != null, "TouchButtonCluster: Dash not found")
