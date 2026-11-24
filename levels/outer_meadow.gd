extends Node3D

const GROUND := -0.34
const LAKE := Vector2(-64, -72)
const PONDS := [Vector2(55, 30), Vector2(-72, 52), Vector2(92, -100)]
var rng := RandomNumberGenerator.new()
var batches := {}

func river_x(z: float) -> float:
	return -68 + 10 * sin(z / 23) + 4 * sin(z / 11)

func shore_clear(p: Vector2) -> bool:
	if absf(p.x - river_x(p.y)) < 8 or ((p - LAKE) / Vector2(29, 21)).length() < 1:
		return false
	for pond: Vector2 in PONDS:
		if p.distance_to(pond) < 12:
			return false
	return true

func _ready() -> void:
	rng.seed = 72411
	var meadow := get_node("../Meadow")
	make_water()
	var obstacles := StaticBody3D.new()
	add_child(obstacles)
	for x in range(-150, 151, 12):
		for z in range(-150, 151, 12):
			var p := Vector2(x + rng.randf_range(-4, 4), z + rng.randf_range(-4, 4))
			if maxf(absf(p.x), absf(p.y)) < 41 or not shore_clear(p):
				continue
			var k := rng.randf_range(0.65, 1.8)
			var base := Vector3(p.x, GROUND, p.y)
			if rng.randf() < 0.57:
				var trunk := base + Vector3.UP * 1.3 * k
				add_form(meadow.get_node("Trunk1").mesh, trunk, k)
				add_hit(obstacles, meadow.get_node("Wood1/Collider").shape, trunk, k)
				for j in 3:
					var angle := j * TAU / 3
					add_form(meadow.get_node("Leaves1_0").mesh, base + Vector3(cos(angle)*0.8, 3+j*0.32, sin(angle)*0.8)*k, k)
			else:
				add_form(meadow.get_node("Boulder0").mesh, base, k)
				add_hit(obstacles, meadow.get_node("Stone0/Collider").shape, base, k*0.86)
	for mesh: Mesh in batches:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = batches[mesh].size()
		for i in batch.instance_count:
			batch.set_instance_transform(i, batches[mesh][i])
		var view := MultiMeshInstance3D.new()
		view.multimesh = batch
		add_child(view)

func add_form(mesh: Mesh, point: Vector3, size_factor: float) -> void:
	if not batches.has(mesh):
		batches[mesh] = []
	batches[mesh].append(Transform3D(Basis(Vector3.UP, rng.randf()*TAU).scaled(Vector3.ONE*size_factor), point))

func add_hit(parent: StaticBody3D, shape: Shape3D, point: Vector3, factor: float) -> void:
	var hit := CollisionShape3D.new()
	hit.shape = shape
	parent.add_child(hit)
	hit.position = point
	hit.scale = Vector3.ONE * factor

func mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func make_water() -> void:
	var water := mat(Color("#43babb"))
	var bank := mat(Color("#c9ba77"))
	for layer in 2:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(bank if layer == 0 else water)
		var y := GROUND + 0.035 + layer * 0.025
		for z in range(-160,160,2):
			var width := 4.6 - layer * 0.9
			var a := Vector3(river_x(z)-width,y,z)
			var b := a + Vector3.RIGHT * width * 2
			var c := Vector3(river_x(z+2)-width,y,z+2)
			var d := c + Vector3.RIGHT * width * 2
			for point: Vector3 in [a,b,c,b,d,c]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(point)
		var pools := [LAKE] + PONDS
		for i in pools.size():
			var center: Vector2 = pools[i]
			var radii := Vector2(25,17) if i == 0 else Vector2(9,6)
			radii -= Vector2.ONE * layer * 0.7
			for j in 48:
				for angle in [-1.0, j*TAU/48, (j+1)*TAU/48]:
					var p := center
					if angle >= 0:
						p += Vector2.from_angle(angle) * radii * (1 + 0.08*sin(3*angle+i))
					surface.set_normal(Vector3.UP)
					surface.add_vertex(Vector3(p.x,y+0.008,p.y))
		var view := MeshInstance3D.new()
		view.mesh = surface.commit()
		add_child(view)
	var bark := mat(Color("#825235"))
	var cut := mat(Color("#dab07b"))
	for pond: Vector2 in PONDS:
		for i in 4:
			var stump := CSGCylinder3D.new()
			stump.sides = 9
			stump.radius = rng.randf_range(0.35,0.65)
			stump.height = rng.randf_range(0.55,1.1)
			stump.material = bark
			stump.use_collision = true
			add_child(stump)
			stump.position = Vector3(pond.x-5+i*2.9, GROUND+stump.height/2, pond.y+rng.randf_range(-2,2))
			var top := CylinderMesh.new()
			top.top_radius = stump.radius*0.86
			top.bottom_radius = top.top_radius
			top.height = 0.02
			top.radial_segments = 9
			top.material = cut
			var cap := MeshInstance3D.new()
			cap.mesh = top
			stump.add_child(cap)
			cap.position.y = stump.height/2
