extends Node3D

var members: Dictionary
var walkers: Array[CharacterBody3D] = []
var directions := []
@export_range(1.0, 10.0, 0.1) var link_distance := 4.5
var votes := []
var joined := false
var local_slot: int
var tick := 0
@onready var body := $Polygon

func _ready() -> void:
	$SkyCourse.chain_hit.connect(break_chain)
	directions.resize(members.size())
	directions.fill(Vector2.ZERO)
	votes.resize(members.size())
	votes.fill(false)
	local_slot = members[multiplayer.get_unique_id()].slot
	body.freeze = true
	body.hide()
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_physics_process(false)
	for i in members.size():
		var walker := CharacterBody3D.new()
		add_child(walker)
		walker.position = body.spawn.origin + body.slots[i]
		var shape := CollisionShape3D.new()
		shape.shape = CapsuleShape3D.new()
		walker.add_child(shape)
		var avatar = body.PLAYER.instantiate()
		walker.add_child(avatar)
		avatar.position.y = -0.43
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body.COLORS[body.color_slots[i]]
		avatar.paint(mat)
		avatar.get_node("Number").text = str(i + 1)
		walkers.append(walker)

func _physics_process(delta: float) -> void:
	tick += 1
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).limit_length()
	if multiplayer.is_server():
		directions[local_slot] = direction
		for i in members.size():
			body.cooldown[i] = maxf(0, body.cooldown[i] - delta)
			if not joined:
				var walker := walkers[i]
				var move: Vector2 = directions[i].rotated(-atan2(7,9)) * 5
				walker.velocity.x = move.x
				walker.velocity.z = move.y
				walker.velocity.y -= 9.8 * delta
				walker.move_and_slide()
				walker.get_node("Player").speed = walker.get_real_velocity()
				walker.get_node("Player").grounded = walker.is_on_floor()
				if walker.position.y < -10:
					walker.position = body.spawn.origin + body.slots[i]
					walker.velocity = Vector3.ZERO
		if joined:
			var turn_balance := 0
			for input_direction: Vector2 in directions:
				turn_balance -= int(signf(input_direction.x))
			body.turn_votes = turn_balance
			if turn_balance != 0:
				body.sleeping = false
		if not joined and votes.has(true) and not group_is_close():
			votes.fill(false)
		if joined and body.position.y < -10:
			body.global_transform = body.spawn
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
		if tick % 3 == 0:
			var positions := PackedVector3Array()
			var velocities := PackedVector3Array()
			var grounded := PackedByteArray()
			for walker in walkers:
				velocities.append(walker.get_real_velocity())
				grounded.append(int(walker.is_on_floor()))
				positions.append(walker.position)
			snapshot.rpc(positions, velocities, grounded, body.transform, votes, joined)
	elif tick % 2 == 0:
		movement.rpc_id(1, direction)
	var focus: Vector3 = body.position if joined else walkers[local_slot].position
	$Camera.position = focus + Vector3(7,6,9)
	$Camera.look_at(focus)
	$Overlay/Hud.text = "Игрок %d   •   Esc — выйти\n" % (local_slot+1)
	$Overlay/Hud.text += "A/D — поворот   Space — поднять соседа" if joined else "WASD — ходьба   Space — прыжок   J — соединиться (%d/%d)" % [votes.count(true), members.size()]

	if not joined and not group_is_close():
		$Overlay/Hud.text += "\nСоберитесь ближе: между любыми двумя игроками — до %.1f м" % link_distance

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_parent().close_room("Вы вышли из комнаты")
	elif event.physical_keycode in [KEY_SPACE, KEY_J]:
		if multiplayer.is_server():
			act(local_slot, event.physical_keycode == KEY_J)
		else:
			action.rpc_id(1, event.physical_keycode == KEY_J)

@rpc("any_peer","unreliable_ordered")
func movement(direction: Vector2) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and members.has(id) and direction.is_finite():
		directions[members[id].slot] = direction.limit_length()

@rpc("any_peer","reliable")
func action(link: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and members.has(id):
		act(members[id].slot, link)

func group_is_close() -> bool:
	for i in walkers.size():
		for j in range(i + 1, walkers.size()):
			if walkers[i].position.distance_squared_to(walkers[j].position) > link_distance * link_distance:
				return false
	return true

func act(slot: int, link: bool) -> void:
	if joined:
		if not link:
			body.request_pull(slot)
	elif link:
		if not group_is_close():
			votes.fill(false)
			return
		votes[slot] = not votes[slot]
		if votes.count(true) == members.size():
			var center := Vector3.ZERO
			for walker in walkers:
				center += walker.position / members.size()
			body.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP)
			set_joined()
	elif walkers[slot].is_on_floor():
		walkers[slot].velocity.y = 6.0

func break_chain(origin: Vector3) -> void:
	if not joined:
		return
	for i in walkers.size():
		var point: Vector3 = body.to_global(body.slots[i])
		walkers[i].position = point
		walkers[i].velocity = body.linear_velocity + (point - origin).normalized() * 4 + Vector3.UP * 2
	votes.fill(false)
	show_walkers()

func show_walkers() -> void:
	joined = false
	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.turn_votes = 0
	body.collision_layer = 0
	body.collision_mask = 0
	body.hide()
	for walker in walkers:
		walker.show()
		walker.collision_layer = 1
		walker.collision_mask = 1

func set_joined() -> void:
	joined = true
	for walker in walkers:
		walker.hide()
		walker.collision_layer = 0
		walker.collision_mask = 0
	body.show()
	if multiplayer.is_server():
		body.collision_layer = 1
		body.collision_mask = 1
		body.control_yaw = true
		body.freeze = false

@rpc("authority","unreliable_ordered")
func snapshot(positions: PackedVector3Array, velocities: PackedVector3Array, grounded: PackedByteArray, pose: Transform3D, ready_votes: Array, linked: bool) -> void:
	votes = ready_votes
	for i in members.size():
		walkers[i].position = positions[i]
		walkers[i].get_node("Player").speed = velocities[i]
		walkers[i].get_node("Player").grounded = bool(grounded[i])
	body.transform = pose
	if linked and not joined:
		set_joined()
	elif not linked and joined:
		show_walkers()
