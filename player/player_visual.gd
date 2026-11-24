extends Node3D

var phase := 0.0
var stride := 0.0
var airborne := 0.0
var speed := Vector3.ZERO
var grounded := true
const FLICK_DURATION := 0.24
@onready var left: Node3D = $Rig/LeftArm
@onready var right: Node3D = $Rig/RightArm
var linked := false
var grip_target := Vector3.ZERO
var reach_progress := 0.0
var flick_remaining := 0.0
var sway_phase := 0.0

func prepare_grip(target: Vector3) -> void:
	linked = true
	grip_target = target
	visibility_changed.connect(func():
		reach_progress = 0.0
		flick_remaining = 0.0
	)

func flick_arm() -> void:
	flick_remaining = FLICK_DURATION

func _physics_process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	sway_phase += delta * 4.0
	var previous_flick := flick_remaining
	flick_remaining = maxf(0, flick_remaining - delta)
	var flick := sin(PI * (1 - flick_remaining / FLICK_DURATION))
	var grip := to_global(grip_target)
	if linked and reach_progress < 1:
		reach_progress = move_toward(reach_progress, 1, delta / 0.28)
		grip = left.global_position.lerp(grip, smoothstep(0, 1, reach_progress))
	left.simulate(delta, sin(sway_phase), flick, linked, grip)
	right.simulate(delta, cos(sway_phase), 0, false, Vector3.ZERO)
	if previous_flick > 0.16 and flick_remaining <= 0.16:
		milk_puff(left.points[-1])

func milk_puff(at: Vector3) -> void:
	var puff := CPUParticles3D.new()
	var drop := SphereMesh.new()
	drop.radius = 0.034
	drop.height = 0.11
	drop.radial_segments = 6
	drop.rings = 3
	var milk := StandardMaterial3D.new()
	milk.albedo_color = Color.FLORAL_WHITE
	milk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = milk
	puff.mesh = drop
	puff.amount = 8
	puff.one_shot = true
	puff.explosiveness = 1
	puff.lifetime = 0.23
	puff.direction = Vector3.UP
	puff.spread = 32
	puff.initial_velocity_min = 3
	puff.initial_velocity_max = 5
	puff.gravity = Vector3.DOWN * 6
	puff.emitting = false
	add_child(puff)
	puff.top_level = true
	puff.global_position = at
	puff.finished.connect(puff.queue_free)
	puff.emitting = true

func paint(material: Material) -> void:
	for part in $Rig.find_children("*", "MeshInstance3D", true, false):
		part.material_override = material

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if linked:
		return
	var horizontal := Vector2(speed.x, speed.z)
	stride = move_toward(stride, minf(horizontal.length() / 5.0, 1.0) if grounded else 0.0, delta * 7)
	airborne = move_toward(airborne, 0.0 if grounded else 1.0, delta * 8)
	var run := smoothstep(5.0, 8.5, horizontal.length())
	phase = fposmod(phase + delta * lerpf(8.0, 13.0, run) * stride, TAU * 2)
	var step := sin(phase) * stride
	if horizontal.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(speed.x, speed.z), 1 - exp(-10 * delta))
	var bounce := absf(step)
	var breath := sin(sway_phase * 0.7) * (1 - stride) * (1 - airborne)
	$Rig.rotation.x = run * stride * 0.27 - airborne * 0.09
	$Rig.rotation.y = step * 0.21
	$Rig.rotation.z = step * 0.31 + sin(phase * 0.5) * stride * 0.08
	$Rig.position.x = step * 0.105
	$Rig.position.y = bounce * lerpf(0.10, 0.19, run) + breath * 0.018
	var stretch := (bounce - 0.5 * stride) * 0.13 + airborne * 0.055 + breath * 0.014
	$Rig/Body.scale = Vector3(0.94 * (1 - stretch * 0.5), 0.87 * (1 + stretch), 0.76)
	$Rig/LeftLeg.rotation.z = -maxf(step, 0) * 0.35
	$Rig/RightLeg.rotation.z = maxf(-step, 0) * 0.35
	$Rig/LeftLeg.rotation.x = step * lerpf(0.82, 1.14, run) - airborne * 0.45
	$Rig/RightLeg.rotation.x = -step * lerpf(0.82, 1.14, run) - airborne * 0.65
