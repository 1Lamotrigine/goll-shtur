extends Node3D

var phase := 0.0
var stride := 0.0
var airborne := 0.0
var speed := Vector3.ZERO
var grounded := true
const FLICK_DURATION := 0.24
@onready var left: Node3D = $Rig/LeftArm
@onready var right: Node3D = $Rig/RightArm
@onready var form: MeshInstance3D = $Rig/LeftArm/Form
@onready var shoulder_rest := left.transform
@onready var form_rest := form.transform
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
		left.transform = shoulder_rest
		form.transform = form_rest
	)

func flick_arm() -> void:
	flick_remaining = FLICK_DURATION

func animate_grip(delta: float, sway: float, flick: float) -> void:
	reach_progress = move_toward(reach_progress, 1.0, delta / 0.28)
	var weight := smoothstep(0.0, 1.0, reach_progress)
	left.position = shoulder_rest.origin + Vector3.UP * (flick * 0.24 + sway * 0.045) * weight
	var reach := grip_target - left.position
	left.quaternion = shoulder_rest.basis.get_rotation_quaternion().slerp(
		Quaternion(Vector3.DOWN, reach.normalized()), weight)
	form.scale.y = lerpf(form_rest.basis.get_scale().y, reach.length() / form.mesh.get_aabb().size.y, weight)
	form.position.y = lerpf(form_rest.origin.y, -reach.length() * 0.5, weight)
	right.rotation.x = sway * 0.15
	right.rotation.z = 0.49 + sway * 0.1

func paint(material: Material) -> void:
	for part in $Rig.find_children("*", "MeshInstance3D", true, false):
		part.material_override = material

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	sway_phase += delta * 4.0
	flick_remaining = maxf(0.0, flick_remaining - delta)
	var flick := sin(PI * pow(1.0 - flick_remaining / FLICK_DURATION, 0.65))
	var sway := sin(sway_phase)
	if linked:
		animate_grip(delta, sway, flick)
		return
	var horizontal := Vector2(speed.x, speed.z)
	stride = move_toward(stride, minf(horizontal.length() / 5.0, 1.0) if grounded else 0.0, delta * 7)
	airborne = move_toward(airborne, 0.0 if grounded else 1.0, delta * 8)
	phase += delta * 8 * stride
	var step := sin(phase) * stride
	if horizontal.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(speed.x, speed.z), 1 - exp(-10 * delta))
	$Rig.rotation.z = step * 0.17 + sin(phase * 0.5) * stride * 0.08
	$Rig.position.y = absf(step) * 0.065
	$Rig/LeftLeg.rotation.x = step * 0.63 - airborne * 0.45
	$Rig/RightLeg.rotation.x = -step * 0.63 - airborne * 0.65
	$Rig/LeftArm.rotation.x = -step * 0.46 + sway * 0.12 - flick * 0.65
	$Rig/RightArm.rotation.x = step * 0.46 - sway * 0.14
	$Rig/LeftArm.rotation.z = -0.49 - airborne * 0.75 + step * 0.12
	$Rig/RightArm.rotation.z = 0.49 + airborne * 0.75 + step * 0.12
