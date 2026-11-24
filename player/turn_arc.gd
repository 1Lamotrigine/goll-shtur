extends MeshInstance3D

const RADIUS := 0.95
const HALF_WIDTH := 0.055
const SEGMENTS := 20
var ribbon := ImmediateMesh.new()
var last_extent := 0.0

func _ready() -> void:
	top_level = true
	mesh = ribbon
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.albedo_color = Color("#84f5ff")
	material_override = ink
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hide()

func display(center: Vector3, fraction: float) -> void:
	visible = absf(fraction) > 0.015
	if not visible:
		return
	global_position = center + Vector3.UP * 2.65
	var camera := get_viewport().get_camera_3d()
	if camera:
		rotation = Vector3(0.55, camera.global_rotation.y, 0)
	var extent := fraction * PI * 0.85
	if is_equal_approx(extent, last_extent):
		return
	last_extent = extent
	ribbon.clear_surfaces()
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(SEGMENTS + 1):
		var radial := Vector3.FORWARD.rotated(Vector3.UP, extent * i / SEGMENTS)
		ribbon.surface_add_vertex(radial * (RADIUS - HALF_WIDTH))
		ribbon.surface_add_vertex(radial * (RADIUS + HALF_WIDTH))
	ribbon.surface_end()
	var end := Vector3.FORWARD.rotated(Vector3.UP, extent)
	var tangent := Vector3.UP.cross(end) * signf(extent)
	var tip_size := minf(0.25, absf(extent))
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	ribbon.surface_add_vertex(end * (RADIUS - tip_size * 0.65))
	ribbon.surface_add_vertex(end * (RADIUS + tip_size * 0.65))
	ribbon.surface_add_vertex(end * RADIUS + tangent * tip_size)
	ribbon.surface_end()
