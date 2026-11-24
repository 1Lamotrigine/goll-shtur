extends Node3D

var members: Dictionary
var walkers: Array[CharacterBody3D] = []
var directions := []
@export_range(1.0, 10.0, 0.1) var link_distance := 4.5
var votes := []
var joined := false
var prompts: Array[Label3D] = []
var conflicts: Array[Label3D] = []
var warn_until := PackedInt64Array()
var target_positions := PackedVector3Array()
var target_pose := Transform3D.IDENTITY
var received := false
var last_snapshot_tick := -1
var last_sync_ms := 0
var local_slot: int
var tick := 0
var recoil := PackedVector3Array()
var camera_clearance := SphereShape3D.new()
var camera_distance := 9.0
var stair_camera_position := Vector3.ZERO
var wind_course: Node3D
@onready var body := $Polygon

func _ready() -> void:
	if $SkyCourse.has_method("wind_at"):
		wind_course = $SkyCourse
		camera_clearance.radius = 0.32
	$SkyCourse.explosion.connect(on_explosion)
	recoil.resize(members.size())
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
		body.CUES.lifter(avatar, body.COLORS[body.color_slots[posmod(i-1,members.size())]])
		if i == local_slot:
			body.CUES.ring(avatar, Vector3.DOWN * 0.46, mat.albedo_color)
		var prompt := Label3D.new()
		prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		walker.add_child(prompt)
		prompt.position.y = 1.65
		prompts.append(prompt)
		warn_until.append(0)
		var indicator := Label3D.new()
		indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		indicator.modulate = mat.albedo_color
		body.add_child(indicator)
		indicator.position = body.slots[i] + Vector3.UP * 2
		conflicts.append(indicator)
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
				var move: Vector2 = directions[i].rotated(0.0 if wind_course else -atan2(7,9)) * 5
				walker.velocity.x = move.x + recoil[i].x
				walker.velocity.z = move.y + recoil[i].z
				walker.velocity.y -= walker.get_gravity().length() * delta
				if wind_course:
					var wind: Vector3 = wind_course.wind_at(walker.position)
					walker.velocity += Vector3(wind.x, wind.y * delta, wind.z)
				walker.move_and_slide()
				for collision_index in walker.get_slide_collision_count():
					var normal := walker.get_slide_collision(collision_index).get_normal()
					if recoil[i].dot(normal) < 0:
						recoil[i] = recoil[i].slide(normal)
				recoil[i] = recoil[i].move_toward(Vector3.ZERO, delta * 11)
				walker.get_node("Player").speed = walker.get_real_velocity()
				walker.get_node("Player").grounded = walker.is_on_floor()
				if walker.position.y < -10:
					walker.position = body.spawn.origin + body.slots[i]
					walker.velocity = Vector3.ZERO
					recoil[i] = Vector3.ZERO
		if joined:
			if wind_course:
				var wind: Vector3 = wind_course.wind_at(body.position)
				if wind != Vector3.ZERO:
					body.apply_central_force(wind * body.mass)
			var turn_balance := 0
			for input_direction: Vector2 in directions:
				turn_balance -= int(signf(input_direction.x))
			body.turn_votes = turn_balance
			if turn_balance != 0:
				body.sleeping = false
		if not joined and votes.has(true) and not group_is_close():
			for a in walkers.size():
				for b in range(a+1, walkers.size()):
					if walkers[a].position.distance_to(walkers[b].position) > link_distance:
						warn_until[a] = tick + 60
						warn_until[b] = tick + 60
			votes.fill(false)
		if joined and body.position.y < -10:
			body.global_transform = body.spawn
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
		if tick % 3 == 0:
			send_state()
	elif tick % 2 == 0:
		movement.rpc_id(1, direction)
		var now := Time.get_ticks_msec()
		if now - last_sync_ms >= 1000:
			last_sync_ms = now
			request_state.rpc_id(1)
	var left := false
	var right := false
	for d: Vector2 in directions:
		left = left or d.x < 0
		right = right or d.x > 0
	for i in walkers.size():
		conflicts[i].text = ("←" if directions[i].x < 0 else "→") if joined and left and right and directions[i].x != 0 else ""
		prompts[i].modulate = Color.ORANGE_RED if tick < warn_until[i] else Color.WHITE
		prompts[i].text = "Слишком далеко" if tick < warn_until[i] else ("✓" if votes[i] else ("E — взяться за руки" if i == local_slot and group_is_close() else ""))
	$Overlay/Hud.text = "Игрок %d   •   Esc — выйти\n" % (local_slot+1)
	$Overlay/Hud.text += "A/D — поворот   Space — поднять соседа   X — разорвать" if joined else "WASD — ходьба   Space — прыжок   E — соединиться (%d/%d)" % [votes.count(true), members.size()]

	if not joined and not group_is_close():
		$Overlay/Hud.text += "\nСоберитесь ближе: между любыми двумя игроками — до %.1f м" % link_distance

func _process(delta: float) -> void:
	if not multiplayer.is_server() and received:
		var weight := 1.0 - exp(-30 * delta)
		body.transform = body.transform.interpolate_with(target_pose, weight)
		for i in walkers.size():
			walkers[i].position = walkers[i].position.lerp(target_positions[i], weight)
	var focus: Vector3 = body.position if joined else walkers[local_slot].position
	if wind_course:
		var pivot := focus + Vector3.UP * 0.55
		var desired := pivot + Vector3(0, 2.3, 8.8)
		if stair_camera_position == Vector3.ZERO:
			stair_camera_position = desired
		stair_camera_position = stair_camera_position.lerp(desired, 1.0-exp(-16*delta))
		var arm := stair_camera_position - pivot
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = camera_clearance
		query.transform.origin = pivot
		query.motion = arm
		query.collision_mask = 2
		var fraction := get_world_3d().direct_space_state.cast_motion(query)[0]
		var available := arm.length() * fraction
		camera_distance = minf(available, lerpf(camera_distance, available, 1.0 - exp(-5 * delta)))
		$Camera.position = pivot + arm.normalized() * camera_distance
		$Camera.rotation = Vector3(-0.08, 0, 0)
		return
	var offset := Vector3(7,6,9)
	$Camera.position = $Camera.position.lerp(focus + offset, 1.0-exp(-16*delta))
	$Camera.look_at($Camera.position-offset)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_parent().close_room("Вы вышли из комнаты")
	elif event.physical_keycode == KEY_X and joined:
		if multiplayer.is_server():
			break_chain(body.position)
		else:
			request_break.rpc_id(1)
	elif event.physical_keycode in [KEY_SPACE, KEY_E]:
		if multiplayer.is_server():
			act(local_slot, event.physical_keycode == KEY_E)
		else:
			action.rpc_id(1, event.physical_keycode == KEY_E)

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

@rpc("any_peer","reliable")
func request_break() -> void:
	if multiplayer.is_server() and members.has(multiplayer.get_remote_sender_id()):
		break_chain(body.position)

@rpc("authority","reliable")
func remote_flash(target: int) -> void:
	if joined:
		body.flash_target(target)

func group_is_close() -> bool:
	for i in walkers.size():
		for j in range(i + 1, walkers.size()):
			if walkers[i].position.distance_squared_to(walkers[j].position) > link_distance * link_distance:
				return false
	return true

func act(slot: int, link: bool) -> void:
	if joined:
		if not link:
			if body.request_pull(slot) and not multiplayer.get_peers().is_empty():
				remote_flash.rpc((slot + 1) % walkers.size())
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

func on_explosion(origin: Vector3) -> void:
	if joined:
		break_chain(origin, true)
		return
	for i in walkers.size():
		var impulse: Vector3 = $SkyCourse.blast_velocity(walkers[i].position, origin)
		walkers[i].velocity.y += impulse.y
		recoil[i] += Vector3(impulse.x, 0, impulse.z)

func break_chain(origin: Vector3, blasted := false) -> void:
	if not joined:
		return
	for i in walkers.size():
		var point: Vector3 = body.to_global(body.slots[i])
		walkers[i].position = point
		var kick := (point - origin).normalized() * 4 + Vector3.UP * 2
		if blasted:
			kick = $SkyCourse.blast_velocity(point, origin)
		walkers[i].velocity = body.linear_velocity + kick
		recoil[i] = Vector3(walkers[i].velocity.x, 0, walkers[i].velocity.z)
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

func send_state(recipient := 0) -> void:
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var grounded := PackedByteArray()
	for walker in walkers:
		velocities.append(walker.get_real_velocity())
		grounded.append(int(walker.is_on_floor()))
		positions.append(walker.position)
	var state := [positions, velocities, grounded, body.transform, votes, joined, directions, warn_until, tick]
	if recipient:
		recover_state.rpc_id(recipient, state)
	else:
		snapshot.rpc(state)

@rpc("any_peer","reliable")
func request_state() -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and members.has(id):
		send_state(id)

@rpc("authority","reliable")
func recover_state(state: Array) -> void:
	apply_snapshot.callv(state)

@rpc("authority","call_remote","unreliable_ordered", 1)
func snapshot(state: Array) -> void:
	apply_snapshot.callv(state)

func apply_snapshot(positions: PackedVector3Array, velocities: PackedVector3Array, grounded: PackedByteArray, pose: Transform3D, ready_votes: Array, linked: bool, inputs: Array, warnings: PackedInt64Array, host_tick: int) -> void:
	if host_tick <= last_snapshot_tick:
		return
	last_snapshot_tick = host_tick
	last_sync_ms = Time.get_ticks_msec()
	directions = inputs
	for i in walkers.size():
		warn_until[i] = tick + maxi(0, warnings[i] - host_tick)
	target_positions = positions
	target_pose = pose
	var snap: bool = not received or joined != linked or body.position.distance_to(pose.origin) > 8
	received = true
	votes = ready_votes
	for i in members.size():
		if snap or walkers[i].position.distance_to(positions[i]) > 8:
			walkers[i].position = positions[i]
		walkers[i].get_node("Player").speed = velocities[i]
		walkers[i].get_node("Player").grounded = bool(grounded[i])
	if snap:
		body.transform = pose
	if linked and not joined:
		set_joined()
	elif not linked and joined:
		show_walkers()
