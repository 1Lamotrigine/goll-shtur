extends Node3D

var phase := 0.0
var stride := 0.0
var airborne := 0.0
var speed := Vector3.ZERO
var grounded := true
var reach_tween: Tween

func prepare_grip(target: Vector3) -> void:
	# Linked avatars share a rigid frame, so this target stays in model space.
	set_process(false)
	var shoulder: Node3D = $Rig/LeftArm
	var form: MeshInstance3D = $Rig/LeftArm/Form
	var rest_shoulder := shoulder.transform
	var rest_form := form.transform
	var extend := func():
		if reach_tween:
			reach_tween.kill()
		shoulder.transform = rest_shoulder
		form.transform = rest_form
		if is_visible_in_tree():
			extend_left_arm(target)
	visibility_changed.connect(extend)
	extend.call()

func extend_left_arm(target: Vector3) -> void:
	var shoulder: Node3D = $Rig/LeftArm
	var form: MeshInstance3D = $Rig/LeftArm/Form
	var reach := target - shoulder.position
	reach_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reach_tween.tween_property(shoulder, "quaternion", Quaternion(Vector3.DOWN, reach.normalized()), 0.28)
	reach_tween.tween_property(form, "scale:y", reach.length() / form.mesh.get_aabb().size.y, 0.28)
	reach_tween.tween_property(form, "position:y", -reach.length() * 0.5, 0.28)

func paint(material: Material) -> void:
	for part in $Rig.find_children("*", "MeshInstance3D", true, false):
		part.material_override = material

func _process(delta: float) -> void:
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
	$Rig/LeftArm.rotation.x = -step * 0.46
	$Rig/RightArm.rotation.x = step * 0.46
	$Rig/LeftArm.rotation.z = -0.49 - airborne * 0.75 + step * 0.12
	$Rig/RightArm.rotation.z = 0.49 + airborne * 0.75 + step * 0.12
