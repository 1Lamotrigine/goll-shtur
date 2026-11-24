extends Node3D

signal chain_hit(origin: Vector3)

const LANDINGS := [Vector3(-24, 15, -15), Vector3(-45, 30, -42), Vector3(-81, 45, -51), Vector3(-105, 63, -84), Vector3(-135, 81, -108)]
var mines: Array[Area3D] = []
var spent := {}

func _ready() -> void:
	var meadow := get_node("../Meadow")
	for landing: Vector3 in LANDINGS:
		for template in ["Spawn", "SpawnStone"]:
			var copy := meadow.get_node(template).duplicate() as Node3D
			add_child(copy)
			copy.position += landing
	var instruction := "Подойдите ближе\nКаждый нажимает J"
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.multiplayer_peer == null:
		instruction = "Цепочка собрана\nQ W O P — рывки"
	signboard(Vector3(-3, 0, 2), instruction)
	signboard(Vector3(1, 0, -4), "↑\nЛетите к платформам")
	var rng := RandomNumberGenerator.new()
	rng.seed = 71031 # The same obstacle IDs and positions on every peer.
	var start := Vector3.ZERO
	for finish: Vector3 in LANDINGS:
		var side := (finish - start).cross(Vector3.UP).normalized()
		for half in 2:
			var along := rng.randf_range(0.17, 0.44) + half * 0.42
			create_mine(start.lerp(finish, along) + side * rng.randf_range(-4, 4) + Vector3.UP * rng.randf_range(-2, 2))
		start = finish

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	return result

func visual(parent: Node3D, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	parent.add_child(part)
	part.position = at
	return part

func signboard(at: Vector3, caption: String) -> void:
	var board := Node3D.new()
	add_child(board)
	board.position = at
	board.rotation.y = atan2(7, 9)
	var post := BoxMesh.new()
	post.size = Vector3(0.14, 1.7, 0.14)
	post.material = material(Color("#915d36"))
	visual(board, post, Vector3.UP * 0.85)
	var panel := BoxMesh.new()
	panel.size = Vector3(2.9, 1.1, 0.14)
	panel.material = material(Color("#22534a"))
	visual(board, panel, Vector3.UP * 1.7)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 38
	label.pixel_size = 0.006
	board.add_child(label)
	label.position = Vector3(0, 1.7, 0.08)

func create_mine(point: Vector3) -> void:
	var mine := Area3D.new()
	add_child(mine)
	mine.position = point
	mine.collision_layer = 0
	mine.monitoring = multiplayer.is_server()
	var shell := SphereMesh.new()
	shell.radius = 0.7
	shell.height = 1.4
	shell.material = material(Color("#881e42"))
	visual(mine, shell, Vector3.ZERO)
	var spike := CylinderMesh.new()
	spike.top_radius = 0
	spike.bottom_radius = 0.14
	spike.height = 0.42
	spike.radial_segments = 6
	spike.material = material(Color("#aeb8bf"))
	for i in 24:
		var y := 1.0 - (i + 0.5) / 12
		var radial := sqrt(1 - y*y)
		var axis := Vector3(cos(i*2.4)*radial, y, sin(i*2.4)*radial)
		visual(mine, spike, axis * 0.84).quaternion = Quaternion(Vector3.UP, axis)
	var hit := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	hit.shape = sphere
	mine.add_child(hit)
	mine.body_entered.connect(contact.bind(mines.size()))
	mines.append(mine)

func contact(body: Node3D, index: int) -> void:
	if spent.has(index) or not (body is CharacterBody3D or body == get_node("../Polygon")):
		return
	if body == get_node("../Polygon"):
		chain_hit.emit.call_deferred(mines[index].position)
	if multiplayer.get_peers().is_empty():
		burst(index)
	else:
		burst.rpc(index)

@rpc("authority", "call_local", "reliable")
func burst(index: int) -> void:
	if spent.has(index):
		return
	spent[index] = true
	var mine := mines[index]
	mine.hide()
	mine.set_deferred("monitoring", false)
	var puff := SphereMesh.new()
	puff.radial_segments = 8
	puff.rings = 4
	var sparks := [material(Color("#fff096")), material(Color("#ff9938")), material(Color("#e84a38"))]
	for i in 16:
		var direction := Vector3(cos(i*2.4), sin(i*1.7)*0.8+0.3, sin(i*2.4)).normalized()
		var part := visual(self, puff, mine.position)
		part.material_override = sparks[i % sparks.size()]
		part.scale = Vector3.ONE * 0.15
		var tween := create_tween()
		tween.tween_property(part, "scale", Vector3.ONE * 1.15, 0.13)
		tween.parallel().tween_property(part, "position", mine.position + direction * 1.2, 0.13)
		tween.tween_property(part, "scale", Vector3.ONE * 0.01, 0.34)
		tween.parallel().tween_property(part, "position", mine.position + direction * 2.2, 0.34)
		tween.tween_callback(part.queue_free)
