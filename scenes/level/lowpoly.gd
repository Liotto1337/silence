class_name Lowpoly
extends RefCounted
## Helpers for flat-shaded primitive meshes and shared colour materials.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


## Drops cached resources (called on quit so nothing is reported as leaked).
static func clear_cache() -> void:
	_materials.clear()
	_meshes.clear()


static func mat(color: Color, roughness: float = 0.9, metallic: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), roughness, metallic, emission]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_materials[key] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Faceted cylinder (or cone when top_radius = 0).
static func cylinder(radius: float, height: float, sides: int = 7, top_radius: float = -1.0) -> Mesh:
	var key := "cyl|%.3f|%.3f|%d|%.3f" % [radius, height, sides, top_radius]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	var mesh := _flatten(c)
	_meshes[key] = mesh
	return mesh


static func sphere(radius: float, segments: int = 8, rings: int = 5) -> Mesh:
	var key := "sph|%.3f|%d|%d" % [radius, segments, rings]
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = rings
	var mesh := _flatten(s)
	_meshes[key] = mesh
	return mesh


static func capsule(radius: float, height: float) -> Mesh:
	var key := "cap|%.3f|%.3f" % [radius, height]
	if _meshes.has(key):
		return _meshes[key]
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 10
	c.rings = 3
	var mesh := _flatten(c)
	_meshes[key] = mesh
	return mesh


## Adds a coloured mesh instance to parent at a local position.
static func add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, 0.85, 0.0, emission)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func add_box_shape(body: CollisionObject3D, size: Vector3, pos: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	return cs


## Re-indexes a primitive into an ArrayMesh with per-face normals (the flat "lowpoly" look).
static func _flatten(prim: PrimitiveMesh) -> ArrayMesh:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for i in range(0, idx.size(), 3):
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue  # degenerate triangle at a pole
		n = n.normalized()
		# Keep the primitive's outward orientation regardless of winding convention.
		if n.dot(normals[idx[i]] + normals[idx[i + 1]] + normals[idx[i + 2]]) < 0.0:
			n = -n
		out_v.append_array([a, b, c])
		out_n.append_array([n, n, n])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_NORMAL] = out_n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh
