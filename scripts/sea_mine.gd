class_name SeaMine
extends Area2D
## Floating sea mine that detonates when ships enter proximity.
## Rendered as a 3D model via SubViewport. Supports chain reactions.

signal destroyed(mine: SeaMine)
signal player_damaged(from_position: Vector2)

enum State { ARMING, IDLE, FUSE_ACTIVE, DETONATING }

const TRIGGER_COUNT: int = 14
const SPHERE_RADIUS: float = 0.5
const TRIGGER_HEIGHT: float = 0.25

@export var arm_time: float = 1.5
@export var fuse_time: float = 1.5
@export var blast_radius: float = 40.0
@export var bob_amplitude: float = 1.5
@export var bob_frequency: float = 1.2
@export var rotation_speed: float = 0.3

var _state: State = State.ARMING
var _is_detonated: bool = false
var _bob_phase: float = 0.0
var _base_y: float = 0.0
var _blast_shape: CircleShape2D = null
var _mine_body: Node3D = null

@onready var _viewport_container: SubViewportContainer = $MineSubViewportContainer
@onready var _sub_viewport: SubViewport = $MineSubViewportContainer/SeaMineModel
@onready var _proximity_shape: CollisionShape2D = $ProximityShape
@onready var _visible_notifier: VisibleOnScreenNotifier2D = $VisibleNotifier


func _ready() -> void:
	assert(_viewport_container != null, "SeaMine: MineSubViewportContainer not found")
	assert(_sub_viewport != null, "SeaMine: SubViewport not found")
	assert(_proximity_shape != null, "SeaMine: ProximityShape not found")
	assert(_visible_notifier != null, "SeaMine: VisibleNotifier not found")

	add_to_group("sea_mines")

	# Duplicate shader material for per-instance uniforms
	_viewport_container.material = _viewport_container.material.duplicate()

	# Prepare blast shape resource (not added to scene tree)
	_blast_shape = CircleShape2D.new()
	_blast_shape.radius = blast_radius

	# Build the 14 trigger cylinders on the 3D model
	_mine_body = _sub_viewport.get_node("MineBody")
	_build_triggers()

	# Connect signals
	body_entered.connect(_on_body_entered)
	_visible_notifier.screen_entered.connect(_on_screen_entered)
	_visible_notifier.screen_exited.connect(_on_screen_exited)

	# Randomize bob phase so mines don't sync
	_bob_phase = randf() * TAU

	# Start arming timer
	await get_tree().create_timer(arm_time).timeout
	if _is_detonated or not is_inside_tree():
		return
	_state = State.IDLE
	# Check for bodies already overlapping during ARMING
	for body: Node2D in get_overlapping_bodies():
		_on_body_entered(body)
		if _state != State.IDLE:
			break


func setup() -> void:
	_base_y = global_position.y


func get_bob_phase() -> float:
	return sin(_bob_phase)


func _process(delta: float) -> void:
	if _is_detonated:
		return

	# Bobbing
	_bob_phase += delta * bob_frequency * TAU
	var bob_offset: float = sin(_bob_phase) * bob_amplitude
	global_position.y = _base_y + bob_offset

	# Update water-line shader on the container (radial for top-down)
	var normalized_bob: float = bob_offset / (bob_amplitude * 2.0 + 0.001)
	var mat: ShaderMaterial = _viewport_container.material as ShaderMaterial
	mat.set_shader_parameter("BobOffset", normalized_bob * 0.04)

	# Rotate 3D model
	if _mine_body:
		_mine_body.rotation.y += rotation_speed * delta


func _on_body_entered(body: Node2D) -> void:
	if _state != State.IDLE or _is_detonated:
		return
	if body is CharacterBody2D:
		_start_fuse()


func check_water_impact(impact_pos: Vector2) -> void:
	## Called when a cannonball splashes into water nearby.
	## Detonates if the impact is within proximity radius.
	if _is_detonated or _state == State.ARMING:
		return
	var prox_radius: float = _proximity_shape.shape.radius
	if global_position.distance_squared_to(impact_pos) <= prox_radius * prox_radius:
		_detonate()


func trigger_detonation() -> void:
	## Public API for chain reactions.
	if _is_detonated or is_queued_for_deletion():
		return
	_detonate()


func _start_fuse() -> void:
	_state = State.FUSE_ACTIVE
	# Escalating red glow pulse
	var tween: Tween = create_tween()
	tween.set_loops(0)
	# Pulse from 0 to 1 with increasing frequency over fuse_time
	var steps: int = 15
	var step_duration: float = fuse_time / float(steps)
	for i: int in steps:
		var t: float = float(i) / float(steps)
		# Frequency increases quadratically
		var freq: float = lerpf(2.0, 12.0, t * t)
		var glow: float = 0.5 + 0.5 * sin(t * freq * TAU)
		var cmat: ShaderMaterial = _viewport_container.material as ShaderMaterial
		tween.tween_callback(cmat.set_shader_parameter.bind("GlowIntensity", glow))
		tween.tween_interval(step_duration)
	# Solid glow at the end
	tween.tween_callback(
		func() -> void:
			var m: ShaderMaterial = _viewport_container.material as ShaderMaterial
			m.set_shader_parameter("GlowIntensity", 1.0)
	)

	await get_tree().create_timer(fuse_time).timeout
	if _is_detonated or not is_inside_tree():
		return
	_detonate()


func _detonate() -> void:
	if _is_detonated:
		return
	_is_detonated = true
	_state = State.DETONATING
	_proximity_shape.set_deferred("disabled", true)

	# Spawn explosion VFX on parent so it survives queue_free
	ExplosionEffect.create(get_parent(), global_position, Vector2.UP, 360, 1.5, 80.0)

	# Blast damage via direct physics query
	_apply_blast_damage()

	# Chain reaction via group
	_trigger_chain_reactions()

	destroyed.emit(self)
	queue_free()


func _apply_blast_damage() -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _blast_shape
	query.transform = global_transform
	query.collision_mask = 3  # player (1) + enemies (2)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var results: Array[Dictionary] = space.intersect_shape(query)
	for result: Dictionary in results:
		var body: Node2D = result["collider"] as Node2D
		if body == null:
			continue
		if body is EnemyShip and not body.is_queued_for_deletion():
			body.take_damage(global_position.direction_to(body.global_position))
		elif body is CharacterBody2D:
			# Player ship — wired but deferred (no health system yet)
			player_damaged.emit(global_position)


func _trigger_chain_reactions() -> void:
	var blast_r_sq: float = blast_radius * blast_radius
	for node: Node in get_tree().get_nodes_in_group("sea_mines"):
		var mine: SeaMine = node as SeaMine
		if mine == null or mine == self or mine._is_detonated:
			continue
		if global_position.distance_squared_to(mine.global_position) <= blast_r_sq:
			# Stagger chain detonation
			var chain_mine: SeaMine = mine
			get_tree().create_timer(0.15).timeout.connect(
				func() -> void:
					if is_instance_valid(chain_mine) and not chain_mine.is_queued_for_deletion():
						chain_mine.trigger_detonation()
			)


func _build_triggers() -> void:
	var trigger_mesh := CylinderMesh.new()
	trigger_mesh.top_radius = 0.02
	trigger_mesh.bottom_radius = 0.06
	trigger_mesh.height = TRIGGER_HEIGHT
	trigger_mesh.radial_segments = 8
	trigger_mesh.rings = 1
	var trigger_mat := StandardMaterial3D.new()
	trigger_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trigger_mat.albedo_color = Color(0.45, 0.38, 0.22)
	trigger_mesh.material = trigger_mat

	var points: PackedVector3Array = _fibonacci_sphere_points(TRIGGER_COUNT)
	for i: int in points.size():
		var pos: Vector3 = points[i]
		var cyl := MeshInstance3D.new()
		cyl.mesh = trigger_mesh
		cyl.name = "Trigger%02d" % (i + 1)
		_mine_body.add_child(cyl)
		# Position at sphere surface + half trigger height outward
		cyl.position = pos * (SPHERE_RADIUS + TRIGGER_HEIGHT * 0.5)
		# Orient outward from sphere center
		var up_vec: Vector3 = Vector3.FORWARD if absf(pos.y) > 0.99 else Vector3.UP
		cyl.look_at_from_position(cyl.position, cyl.position + pos, up_vec)
		cyl.rotate_object_local(Vector3.RIGHT, PI / 2.0)


static func _fibonacci_sphere_points(count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(count)
	var golden_ratio: float = (1.0 + sqrt(5.0)) / 2.0
	var epsilon: float = 0.33
	for i: int in count:
		var theta: float = TAU * float(i) / golden_ratio
		var phi: float = acos(
			1.0 - 2.0 * (float(i) + epsilon) / (float(count) - 1.0 + 2.0 * epsilon)
		)
		points[i] = Vector3(cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi))
	return points


func _on_screen_entered() -> void:
	set_process(true)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _on_screen_exited() -> void:
	set_process(false)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
