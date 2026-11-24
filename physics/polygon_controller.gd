extends RigidBody3D

signal pull_accepted(source: int, target: int)

const PLAYER = preload("res://player/player_visual.tscn")
const COLORS = [Color("#ed494f"), Color("#348cf3"), Color("#ff962e"), Color("#37c67a"), Color("#aa68e8"), Color("#f5dd50")]
const ACTIONS = [&"pull_0", &"pull_1", &"pull_2", &"pull_3"]

@export_range(1.2, 4.0) var radius := 2.0
@export var jump_impulse := 10.0
@export_range(0.0, 1.0) var horizontal_thrust := 0.35
@export var max_horizontal_speed := 6.0
@export var min_press_interval := 0.12
@export var max_linear_speed := 18.0
@export var max_angular_speed := 6.0
@export var kill_y := -10.0

var color_slots := PackedInt32Array([0, 1, 2, 3])
var slots := PackedVector3Array()
var cooldown := PackedFloat32Array([0, 0, 0, 0])
var counts := PackedInt32Array([0, 0, 0, 0])
@export_range(5.0, 55.0, 1.0) var turn_degrees_per_vote := 35.0
var control_yaw := false
var turn_votes := 0
var spawn: Transform3D

func _ready() -> void:
	spawn = global_transform
	cooldown.resize(color_slots.size())
	counts.resize(color_slots.size())
	for i in color_slots.size():
		var angle := TAU * i / color_slots.size()
		slots.append(Vector3(cos(angle), 0, sin(angle)) * radius)
	for i in color_slots.size():
		var avatar := PLAYER.instantiate() as Node3D
		add_child(avatar)
		avatar.position = slots[i]
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[color_slots[i]]
		avatar.paint(material)
		avatar.get_node("Number").text = str(i + 1)
		var shape := CapsuleShape3D.new()
		shape.radius = 0.36
		shape.height = 1.5
		var collider := CollisionShape3D.new()
		collider.shape = shape
		add_child(collider)
		collider.position = slots[i] + Vector3.UP * 0.225
		var neighbor := slots[(i + 1) % slots.size()]
		var toward_neighbor := (neighbor - slots[i]).normalized()
		# The left shoulder lies on the model's negative X axis.
		avatar.rotation.y = atan2(toward_neighbor.z, -toward_neighbor.x)
		var grip := neighbor - toward_neighbor * 0.25 + Vector3.UP * 0.18
		avatar.prepare_grip(avatar.transform.affine_inverse() * grip)

func request_pull(source: int) -> bool:
	if source < 0 or source >= color_slots.size() or cooldown[source] > 0.00001:
		return false
	var target := (source + 1) % color_slots.size()
	var tilt_direction := global_basis.y.slide(Vector3.UP)
	apply_impulse(Vector3.UP * jump_impulse, global_basis * slots[target])
	# Apply steering at the center so it does not add a separate torque.
	apply_central_impulse(tilt_direction * jump_impulse * horizontal_thrust)
	cooldown[source] = min_press_interval
	counts[source] += 1
	pull_accepted.emit(source, target)
	return true

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset") or global_position.y < kill_y or not global_transform.is_finite():
		global_transform = spawn
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		cooldown.fill(0)
		counts.fill(0)
		sleeping = false
		return
	for i in color_slots.size():
		cooldown[i] = maxf(0, cooldown[i] - delta)
		if i < ACTIONS.size() and Input.is_action_just_pressed(ACTIONS[i]):
			request_pull(i)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var vertical := Vector3.UP * state.linear_velocity.y
	var horizontal := state.linear_velocity - vertical
	state.linear_velocity = (vertical + horizontal.limit_length(max_horizontal_speed)).limit_length(max_linear_speed)
	var spin := state.angular_velocity.limit_length(max_angular_speed)
	if control_yaw:
		spin.y = deg_to_rad(turn_degrees_per_vote) * turn_votes
	state.angular_velocity = spin
