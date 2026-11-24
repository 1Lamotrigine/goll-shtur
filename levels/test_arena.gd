extends Node3D

@onready var body := $Polygon
@onready var camera: Camera3D = $Camera
@onready var hud: Label = $Overlay/Hud
const OFFSET := Vector3(7, 6, 9)

var fragments: Array[RigidBody3D] = []

func _ready() -> void:
	$SkyCourse.explosion.connect(break_chain.bind(true))
	body.control_yaw = true
	camera.position = body.position + OFFSET
	camera.look_at(body.position)

func _physics_process(_delta: float) -> void:
	if not fragments.is_empty():
		if Input.is_action_just_pressed("reset"):
			get_tree().reload_current_scene()
		return
	body.turn_votes = int(Input.is_physical_key_pressed(KEY_A)) - int(Input.is_physical_key_pressed(KEY_D))
	if body.turn_votes != 0:
		body.sleeping = false

func _process(delta: float) -> void:
	camera.position = camera.position.lerp(body.position + OFFSET, 1.0 - exp(-7.0 * delta))
	camera.look_at(body.position)
	if not fragments.is_empty():
		hud.text = "Цепочка разорвана   •   R — начать заново"
		return
	var tilt := rad_to_deg(Vector3.UP.angle_to(body.global_basis.y))
	hud.text = "A/D — поворот 1×    •    X — разорвать    •    R — сброс    •    Esc — меню\n1  Space/Q → 2      2  W → 3      3  O → 4      4  P → 1\nРывки %s    Высота %.1f м    Скорость %.1f м/с    Крен %.0f°" % [
		str(body.counts), body.position.y, body.linear_velocity.length(), tilt]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_X:
		break_chain(body.position)
	elif event.is_action_pressed("ui_cancel", false):
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func break_chain(origin: Vector3, blasted := false) -> void:
	if not fragments.is_empty():
		return
	for i in body.slots.size():
		var piece := RigidBody3D.new()
		add_child(piece)
		piece.position = body.to_global(body.slots[i])
		var hit := CollisionShape3D.new()
		hit.shape = CapsuleShape3D.new()
		piece.add_child(hit)
		var avatar = body.PLAYER.instantiate()
		piece.add_child(avatar)
		var color := StandardMaterial3D.new()
		color.albedo_color = body.COLORS[body.color_slots[i]]
		avatar.paint(color)
		avatar.get_node("Number").text = str(i + 1)
		piece.linear_velocity = body.linear_velocity + (piece.position - origin).normalized() * 4 + Vector3.UP * 2
		if blasted:
			piece.linear_velocity = body.linear_velocity
			piece.apply_central_impulse($SkyCourse.blast_velocity(piece.position, origin) * piece.mass)
		fragments.append(piece)
	body.freeze = true
	body.set_physics_process(false)
	body.collision_layer = 0
	body.collision_mask = 0
	body.hide()
