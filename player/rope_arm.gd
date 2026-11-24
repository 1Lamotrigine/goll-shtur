extends Node3D

const COUNT := 8
const LENGTH := 1.45 * 0.54 * 3.0
var points := PackedVector3Array()
var previous := PackedVector3Array()
var pieces: Array[MeshInstance3D] = []
var side := 1.0
var exclusions: Array[RID] = []

func _ready() -> void:
	side = signf(position.x)
	var ancestor := get_parent()
	while ancestor:
		if ancestor is CollisionObject3D:
			exclusions.append(ancestor.get_rid())
		ancestor = ancestor.get_parent()
	var capsule := CapsuleMesh.new()
	capsule.height = 1
	capsule.radius = 0.28
	capsule.radial_segments = 10
	capsule.rings = 4
	for i in COUNT:
		var part := MeshInstance3D.new()
		part.mesh = capsule
		add_child(part)
		part.top_level = true
		pieces.append(part)
	visibility_changed.connect(func(): points.clear())

func simulate(dt: float, sway: float, flick: float, pinned: bool, grip: Vector3) -> void:
	var root := global_position
	var outward := get_parent_node_3d().global_basis.x * side
	if points.is_empty() or points[0].distance_to(root) > 5:
		points.resize(COUNT + 1)
		for i in COUNT + 1:
			points[i] = root + outward * LENGTH * i / COUNT
		previous = points.duplicate()
	var step_length := LENGTH / COUNT
	if pinned:
		step_length = maxf(step_length, root.distance_to(grip) * 1.09 / COUNT)
	var floors := PackedFloat32Array()
	floors.resize(COUNT + 1)
	for i in range(1, COUNT + 1):
		var old := points[i]
		var t := float(i) / COUNT
		var acceleration := Vector3.DOWN * 13 + outward * (2 + sway * 3)
		acceleration += Vector3.UP * flick * 85 * sin(PI * (t * 0.8))
		points[i] += (old - previous[i]) * 0.965 + acceleration * dt * dt
		previous[i] = old
		var above := points[i]
		above.y = maxf(root.y, old.y) + 0.2
		var query := PhysicsRayQueryParameters3D.create(above, points[i] + Vector3.DOWN * 0.2, 1, exclusions)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		floors[i] = -INF if hit.is_empty() else hit.position.y + 0.095
	for iteration in 8:
		points[0] = root
		if pinned:
			points[COUNT] = grip
		for i in COUNT:
			var link := points[i+1] - points[i]
			var correction := link.normalized() * (link.length() - step_length)
			var fixed_end := pinned and i == COUNT - 1
			if i > 0:
				points[i] += correction * (1 if fixed_end else 0.5)
			if not fixed_end:
				points[i+1] -= correction * (1 if i == 0 else 0.5)
		for i in range(1, COUNT if pinned else COUNT + 1):
			points[i].y = maxf(points[i].y, floors[i])
	for i in COUNT:
		var link := points[i+1] - points[i]
		var basis := Basis(Quaternion(Vector3.UP, link.normalized())) if link.length_squared() > 0.000001 else Basis.IDENTITY
		pieces[i].global_transform = Transform3D(basis.scaled_local(Vector3(0.38, link.length() + 0.13, 0.38)), points[i].lerp(points[i+1], 0.5))
