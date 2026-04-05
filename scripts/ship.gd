extends CharacterBody2D
## Player-controlled ship with floaty, momentum-based movement.
## Thrust accumulates velocity; viscous drag decays it exponentially.
## Brake (S key) decelerates to zero via move_toward.

@export var thrust: float = 80.0
@export var turn_speed: float = 2.5
@export var linear_drag: float = 0.97
@export var brake_decel: float = 120.0


func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING


func _physics_process(delta: float) -> void:
	var is_braking: bool = Input.is_action_pressed("move_back")

	if not is_braking and Input.is_action_pressed("move_forward"):
		velocity += transform.y * thrust * delta

	if is_braking:
		velocity = velocity.move_toward(Vector2.ZERO, brake_decel * delta)
	else:
		velocity *= linear_drag

	var turn_input: float = Input.get_axis("turn_left", "turn_right")
	rotation += turn_input * turn_speed * delta

	move_and_slide()
