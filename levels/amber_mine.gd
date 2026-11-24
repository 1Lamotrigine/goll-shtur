extends "res://levels/big_stair.gd"

const LEDGES := 16
const AXIS := Vector3(0, 0, -19)

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var angle := 0.0
	var height := 0.0
	var handedness := rng.randi_range(0, 1) * 2 - 1
	var amber := material(Color("#ffac38"))
	amber.emission_enabled = true
	amber.emission = Color("#be6815")
	var crystal := CylinderMesh.new()
	crystal.radial_segments = 5
	crystal.bottom_radius = 0.65
	crystal.top_radius = 0
	crystal.height = 2.6
	crystal.material = amber
	var previous := Vector3.ZERO
	for i in LEDGES:
		var outward := Vector3.BACK.rotated(Vector3.UP, angle)
		var radius := 19.0 if i == 0 else rng.randf_range(18, 20)
		var center := AXIS + outward * radius + Vector3.UP * height
		var width := 14.0 if i == 0 else rng.randf_range(9, 12)
		block(center - Vector3.UP * 1.1, Vector3(width, 2.2, width), Color("#66473e"))
		block(center - Vector3.UP * 0.12, Vector3(width, 0.24, width), Color("#d99950"))
		var vein := center + outward * (width / 2 - 0.9)
		visual(self, crystal, vein + Vector3.UP * 1.25).rotation.z = 0.2
		if i > 0:
			var crossing := previous.lerp(center, 0.55)
			create_mine(crossing + outward * rng.randf_range(-3, 3) + Vector3.UP * 1.7)
		if i % 3 == 1:
			var tangent := Vector3.UP.cross(outward) * handedness
			add_vent(center + tangent * 2 + Vector3.UP * 0.15, (Vector3.UP + tangent * 0.5).normalized())
		if i == LEDGES - 1:
			signboard(center, "Вершина шахты")
		previous = center
		height += rng.randf_range(3.8, 5.8)
		angle += handedness * rng.randf_range(0.64, 0.82)
	block(AXIS + Vector3.UP * (height / 2 - 2), Vector3(12, height + 4, 12), Color("#594044"))
	signboard(Vector3(-4, 0, 1), "Янтарная шахта\nПоднимайтесь по уступам\nвокруг скалы")

func camera_pivot(focus: Vector3, _clearance: float) -> Vector3:
	return focus
