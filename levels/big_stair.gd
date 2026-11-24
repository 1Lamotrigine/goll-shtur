extends "res://levels/sky_course.gd"

enum Section { TERRACE, FORK, UPDRAFT }

const WIDTH := 44.0
const STEP_COUNT := 19
const REACH := 12.0
var passages: Array[AABB] = []
var layout_seed: int
var vents: Array[Node3D] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var edge := 11.0
	var heights := PackedFloat32Array([0.0])
	for i in STEP_COUNT + 1:
		heights.append(heights[-1] + rng.randf_range(4.5, 7.5))
	var section_order: Array[int] = [Section.TERRACE, Section.FORK, Section.UPDRAFT]
	var previous_ceiling := 0.0
	for i in STEP_COUNT:
		var depth := rng.randf_range(16, 23)
		if i == 0:
			depth += 4.0
		var top := heights[i]
		var ceiling := top + 2.0 * (heights[i + 2] - top + 3.0)
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
			var seam_depth := 0.3 if ceiling > previous_ceiling else -0.3
			block(Vector3(0, (ceiling + previous_ceiling)/2, edge + seam_depth/2),
				Vector3(WIDTH + 1.6, maxf(0.01, absf(ceiling - previous_ceiling)), absf(seam_depth)), wall_color)
		else:
			block(Vector3(0, ceiling/2, edge + 0.25), Vector3(WIDTH + 1.6, ceiling, 0.5), wall_color)
		previous_ceiling = ceiling
		if i > 0:
			# Draw each section once per group of three using the shared layout seed.
			var slot := (i - 1) % section_order.size()
			var pick := rng.randi_range(slot, section_order.size() - 1)
			var chosen := section_order[pick]
			section_order[pick] = section_order[slot]
			section_order[slot] = chosen
			var side := 1 if rng.randf() < 0.5 else -1
			add_section(chosen, side, top, heights[i + 1] - top, edge, depth, i, rng)
		edge -= depth
		if i == STEP_COUNT - 1:
			block(Vector3(0, (top + ceiling)/2, edge - 0.25),
				Vector3(WIDTH + 1.6, ceiling - top, 0.5), wall_color)
	signboard(Vector3(-3, 0, 2), "Big Stair\nE — взяться за руки\nПоднимайтесь по ступеням")

# One side holds the traversal feature. The opposite side stays open,
# with staggered mines that can be threaded or flown over.
func add_section(kind: int, side: int, top: float, rise: float, edge: float, depth: float, step: int, rng: RandomNumberGenerator) -> void:
	var middle := edge - depth * 0.5
	var lane := side * 11.0
	match kind:
		Section.TERRACE:
			var height := rise * 0.5
			block(Vector3(lane, top + height / 2, edge - depth * 0.77),
				Vector3(11, height, depth * 0.46), Color("#468d85"))
			add_vent(Vector3(lane, top + 0.12, edge - depth * 0.3), Vector3(0, 1, -0.4).normalized())
		Section.FORK:
			# Split around the pillar, then emerge into a crosswind on one branch.
			block(Vector3(0, top + 3.5, middle), Vector3(3.2, 7, 3.2), Color("#b87a49"))
			add_vent(Vector3(side * (WIDTH/2 - 0.12), top + 3, middle),
				Vector3(-side, 0.3, -0.25).normalized())
		Section.UPDRAFT:
			# A raised launch pad aims the air stream at the next step.
			block(Vector3(lane, top + 0.45, middle), Vector3(8, 0.9, 7), Color("#5079aa"))
			add_vent(Vector3(lane, top + 1.04, middle), Vector3(0, 1, -0.75).normalized())
	if step >= 7:
		# Narrow the mine route without blocking the assisted route on the other side.
		var wall_x := -side * (WIDTH/2 - 5)
		block(Vector3(wall_x, top + 2.5, middle), Vector3(10, 5, 1.2), Color("#80529f"))
	if step >= 13:
		# Offset the fast high route with a sideways gust near the next riser.
		add_vent(Vector3(side * (WIDTH/2 - 0.12), top + 5, edge - depth * 0.85),
			Vector3(-side, 0.08, 0.32).normalized())
	var rows := 2 if step < 7 else 3
	for row in rows:
		for column in 2:
			var x := -side * (5.0 + column * 8.0 + (row % 2) * 2.0 + rng.randf_range(-0.6, 0.6))
			var z := edge - depth * lerpf(0.2, 0.82, float(row) / (rows - 1))
			create_mine(Vector3(x, top + rng.randf_range(1.6, 4.8), z))

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
