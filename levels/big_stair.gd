extends "res://levels/sky_course.gd"

const WIDTH := 34.0
const REACH := 12.0
var passages: Array[AABB] = []
var layout_seed: int
var vents: Array[Node3D] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var edge := 11.0
	var heights := PackedFloat32Array([0.0])
	for i in 14:
		heights.append(heights[-1] + rng.randf_range(4.5, 7.5))
	var previous_ceiling := heights[2] + 3.0
	for i in 13:
		var depth := rng.randf_range(12, 18)
		if i == 0:
			depth += 4.0
		var top := heights[i]
		var ceiling := heights[i + 2] + 3.0
		passages.append(AABB(Vector3(-WIDTH/2, top, edge - depth), Vector3(WIDTH, ceiling - top, depth)))
		var middle := edge - depth * 0.5
		var tint := Color.from_hsv(rng.randf_range(0.725, 0.78), 0.52, 0.69)
		block(Vector3(0, (top - 4) * 0.5, middle), Vector3(WIDTH, top + 4, depth), tint)
		block(Vector3(0, top - 0.14, middle), Vector3(WIDTH, 0.28, depth), tint.lightened(0.32))
		var wall_color := tint.darkened(0.22)
		for side in [-1, 1]:
			block(Vector3(side * (WIDTH/2 + 0.4), (ceiling + top)/2, middle), Vector3(0.8, ceiling - top, depth), wall_color)
		block(Vector3(0, ceiling + 0.25, middle), Vector3(WIDTH + 1.6, 0.5, depth), tint.lightened(0.16))
		# Seal the vertical face between adjacent ceiling sections.
		if i > 0:
			block(Vector3(0, (ceiling + previous_ceiling)/2, edge + 0.15), Vector3(WIDTH + 1.6, ceiling - previous_ceiling, 0.3), wall_color)
		else:
			block(Vector3(0, ceiling/2, edge + 0.25), Vector3(WIDTH + 1.6, ceiling, 0.5), wall_color)
		previous_ceiling = ceiling
		if i > 0:
			for lane in 4:
				var x := -WIDTH/2 + (lane + rng.randf_range(0.22, 0.78)) * WIDTH/4
				create_mine(Vector3(x, top + rng.randf_range(1.4, 5.5), edge - rng.randf_range(1.3, depth - 1.3)))
			if rng.randf() < 0.5:
				add_vent(Vector3(-WIDTH/2 + 0.12, top + rng.randf_range(1.8, 4.2), middle), Vector3(1, rng.randf_range(0.1, 0.55), rng.randf_range(-0.6, 0.6)).normalized())
			else:
				add_vent(Vector3(rng.randf_range(-8, 8), top - 2.1, edge + 0.12), Vector3(0, rng.randf_range(0.1, 0.65), 1).normalized())
		edge -= depth
	signboard(Vector3(-3, 0, 2), "Big Stair\nE — взяться за руки\nПоднимайтесь по ступеням")

# Keep the sweep origin inside the passage, including both sides of a step seam.
func camera_pivot(focus: Vector3, clearance: float) -> Vector3:
	var pivot := focus
	pivot.x = clampf(pivot.x, -WIDTH/2 + clearance, WIDTH/2 - clearance)
	pivot.z = clampf(pivot.z, passages[-1].position.z + clearance, passages[0].end.z - clearance)
	for passage in passages:
		if pivot.z >= passage.position.z - clearance and pivot.z <= passage.end.z + clearance:
			pivot.y = clampf(pivot.y, passage.position.y + clearance, passage.end.y - clearance)
	return pivot

func block(at: Vector3, size: Vector3, tint: Color) -> void:
	var solid := StaticBody3D.new()
	solid.collision_layer = 3 # World geometry and camera obstacles.
	add_child(solid)
	solid.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(tint)
	visual(solid, mesh, Vector3.ZERO)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	solid.add_child(collider)

func add_vent(at: Vector3, direction: Vector3) -> void:
	var vent := Node3D.new()
	add_child(vent)
	vent.position = at
	vent.quaternion = Quaternion(Vector3.UP, direction)
	vents.append(vent)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.55
	disc.bottom_radius = 1.55
	disc.height = 0.3
	disc.material = material(Color("#171321"))
	visual(vent, disc, Vector3.ZERO)
	var air := CPUParticles3D.new()
	vent.add_child(air)
	air.position.y = 0.22
	air.amount = 42
	air.lifetime = 1.45
	air.preprocess = air.lifetime
	air.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	air.emission_sphere_radius = 1.22
	air.direction = Vector3.UP
	air.spread = 4
	air.gravity = Vector3.ZERO
	air.initial_velocity_min = 7
	air.initial_velocity_max = 8
	air.local_coords = true
	var streak := BoxMesh.new()
	streak.size = Vector3(0.055, 0.7, 0.055)
	streak.material = material(Color("#c0bdc6"))
	air.mesh = streak

func wind_at(point: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for vent in vents:
		var offset := point - vent.position
		var axis := vent.basis.y
		var along := offset.dot(axis)
		if along >= 0 and along < REACH and (offset - axis * along).length_squared() < 5:
			push += axis * 13 * (1 - along / REACH)
	return push
