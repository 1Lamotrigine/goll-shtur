extends Node3D

static func mesh_at(parent: Node3D, mesh: Mesh, offset: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = offset
	return node

static func ring(parent: Node3D, offset: Vector3, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.48
	mesh.outer_radius = 0.56
	return mesh_at(parent, mesh, offset, color)

static func lifter(parent: Node3D, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	mesh_at(parent, sphere, Vector3.UP * 1.48, color)

static func arrow(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.top_level = true
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.18,0.05,1.4)
	mesh_at(root, shaft, Vector3(0,0,-0.7), Color.GOLD)
	var tip := CylinderMesh.new()
	tip.radial_segments = 3
	tip.height = 0.05
	tip.top_radius = 0.5
	tip.bottom_radius = 0.5
	var head := mesh_at(root, tip, Vector3(0,0,-1.55), Color.GOLD)
	head.rotation.y = PI
	root.hide()
	return root
