class_name Models
extends RefCounted
## Third-party low-poly models (assets/models/props/, authors in CREDITS.md) prepared for the house
## builder. A model (or a few named nodes of a pack) is baked into one ArrayMesh with its origin at
## the bottom centre and its front turned to +Z, then stretched to the size the gameplay code asks
## for, so the existing collision boxes, drawers and door hinges keep their exact dimensions.
## Materials become the PS1 shader with the model's own texture.

const DIR := "res://assets/models/props/"
const PS1_SHADER := preload("res://shaders/ps1.gdshader")
const PS1_DOUBLE := preload("res://shaders/ps1_double.gdshader")

## id: [file, nodes to keep ("" = all; "|" separates alternatives), yaw that turns the front to +Z,
##      optional pitch (about X, applied first) for models lying on the wrong axis, optional nodes to drop]
const DEFS := {
	"bed_single": ["bed_single", "", PI * 0.5],
	"bed_double": ["bed_double", "", PI * 0.5],
	"sofa": ["sofa", "", 0.0, 0.0, "/Wall/"],
	"table": ["table", "", 0.0],
	"chair": ["chair", "", 0.0],
	"table_lamp": ["table_lamp", "", 0.0],
	"wardrobe": ["wardrobe", "", 0.0],
	"dresser": ["dresser", "", 0.0],
	"crt_tv": ["crt_tv", "/TVCRT/", 0.0],
	"tv_stand": ["tv_stand", "", 0.0],
	"armchair": ["armchair", "", 0.0],
	"metal_shelf": ["metal_shelf", "", 0.0],
	"cardboard_box": ["barrels_boxes", "/CardboardBox/", 0.0],
	"crate": ["barrels_boxes", "/Crate/", 0.0],
	"fridge": ["fridge", "", 0.0],
	"kitchen_counter": ["kitchen_cabinets", "", -PI * 0.5],
	"stove": ["stove", "", 0.0],
	"bathtub": ["bathtub", "", 0.0],
	"toilet": ["toilet", "", PI * 0.5],
	"sink": ["sink", "", 0.0],
	"ceiling_light": ["ceiling_light", "", 0.0],
	"toy_box": ["toy_box", "", 0.0],
	"door_room": ["doors_interior", "/Wooden Door_001/", 0.0],
	"door_front": ["doors_front", "/Front Door_003/", 0.0],
	"door_balcony": ["doors_essential", "/Front Door_006_001/", 0.0],
	"door_closet": ["doors_essential", "/Wooden Door_009_001/", 0.0],
	"rug_a": ["rugs", "/Vintage Rugs_009/", 0.0],
	"rug_b": ["rugs", "/Vintage Rugs_007/", 0.0],
	"rug_c": ["rugs", "/Vintage Rugs_012/", 0.0],
	"wall_clock": ["wall_clocks", "/Wall Clock_007/", 0.0],
	"vent_cover": ["vents", "/vent_cover_33/", 0.0],
	"fan": ["pc_fan", "", 0.0, PI * 0.5],
	"teddy": ["toy_pack", "/SM_Oyuncak_Ayi_0/", 0.0],
	"duck": ["toy_pack", "/SM_Ordek_1/", 0.0],
	"ball": ["beach_ball", "", 0.0],
	"block_a": ["abc_blocks", "/A_low/", 0.0],
	"block_b": ["abc_blocks", "/B_low/", 0.0],
	"toy_car": ["toy_car", "", 0.0],
	"pyramid": ["toy_pyramid", "", 0.0],
	"vase": ["vase", "", 0.0],
	"milk": ["milk", "", 0.0],
	"cereal": ["cereal", "", 0.0],
	"bowl": ["bowl", "", 0.0],
	"bowl_full": ["bowl_soup", "", 0.0],
	"remote": ["remote", "", 0.0, PI * 0.5],
	"flashlight": ["flashlight", "", 0.0, -PI * 0.5],
	"key": ["key", "", PI * 0.5],
	"battery": ["battery", "", PI * 0.5, PI * 0.5],
}

static var _raw: Dictionary = {}  # id -> {"surfaces": [{path, arrays, material}], "aabb": AABB}
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


static func clear_cache() -> void:
	_raw.clear()
	_meshes.clear()
	_materials.clear()


## Mesh of `id` stretched to `size` (a 0 component scales uniformly with the others), origin at the
## bottom centre, front +Z. `part` keeps only matching nodes but places them as in the whole model;
## `pivot` (in the sized space) becomes the part's origin. `exclude` drops matching nodes.
static func mesh(id: String, size: Vector3, part: String = "", pivot: Vector3 = Vector3.ZERO, exclude: String = "", tint: Color = Color.WHITE) -> ArrayMesh:
	var key := "%s|%s|%s|%s|%s|%s" % [id, size, part, pivot, exclude, tint.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var raw := _load(id)
	var fit := _fit(raw["aabb"], size)
	var out := ArrayMesh.new()
	for s: Dictionary in raw["surfaces"]:
		if not _matches(s["path"], part, true) or (exclude != "" and _matches(s["path"], exclude, false)):
			continue
		var arrays: Array = (s["arrays"] as Array).duplicate()
		var verts := PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
		var normals := PackedVector3Array(arrays[Mesh.ARRAY_NORMAL]) if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		for i in verts.size():
			verts[i] = fit * verts[i] - pivot
		for i in normals.size():
			normals[i] = (fit.basis.inverse().transposed() * normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		if normals.size() > 0:
			arrays[Mesh.ARRAY_NORMAL] = normals
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, _ps1(s["material"], tint))
	_meshes[key] = out
	return out


## Bounding box of a part after fitting the whole model to `size` (to place hinges, drawers...).
static func part_aabb(id: String, size: Vector3, part: String) -> AABB:
	return mesh(id, size, part).get_aabb()


## Adds the model as a MeshInstance3D at a local position.
static func add(parent: Node3D, id: String, size: Vector3, pos: Vector3 = Vector3.ZERO, yaw: float = 0.0, part: String = "", exclude: String = "", tint: Color = Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(id, size, part, Vector3.ZERO, exclude, tint)
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi


## Copy of a mesh whose materials render both faces (for models the player can be inside of).
static func double_sided(src: ArrayMesh) -> ArrayMesh:
	var out := src.duplicate() as ArrayMesh
	for i in out.get_surface_count():
		var m := out.surface_get_material(i).duplicate() as ShaderMaterial
		m.shader = PS1_DOUBLE
		out.surface_set_material(i, m)
	return out


## Turns a flat part (a door modelled ajar) about `hinge` until its long side runs along X.
static func straighten(src: ArrayMesh, hinge: Vector3) -> ArrayMesh:
	var center := Vector2.ZERO
	var count := 0
	for si in src.get_surface_count():
		for p: Vector3 in src.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			center += Vector2(p.x, p.z)
			count += 1
	center /= maxf(count, 1)
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for si in src.get_surface_count():
		for p: Vector3 in src.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			var d := Vector2(p.x, p.z) - center
			sxx += d.x * d.x
			szz += d.y * d.y
			sxz += d.x * d.y
	# Principal axis in the XZ plane; a yaw of that angle brings it back onto X.
	var turn := Transform3D(Basis(Vector3.UP, 0.5 * atan2(2.0 * sxz, sxx - szz)), Vector3.ZERO)
	var xf := Transform3D(Basis(), hinge) * turn * Transform3D(Basis(), -hinge)
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = xf * verts[i]
		arrays[Mesh.ARRAY_VERTEX] = verts
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i] = turn.basis * normals[i]
			arrays[Mesh.ARRAY_NORMAL] = normals
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(si, src.surface_get_material(si))
	return out


## Splits a mesh by triangle centre: returns [outside, inside] for the given box.
static func split(src: ArrayMesh, box: AABB) -> Array[ArrayMesh]:
	var outside := ArrayMesh.new()
	var inside := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			var target := b if box.has_point(c) else a
			target.append_array([idx[t], idx[t + 1], idx[t + 2]])
		for pair: Array in [[outside, a], [inside, b]]:
			if (pair[1] as PackedInt32Array).is_empty():
				continue
			var copy := arrays.duplicate()
			copy[Mesh.ARRAY_INDEX] = pair[1]
			(pair[0] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy)
			(pair[0] as ArrayMesh).surface_set_material((pair[0] as ArrayMesh).get_surface_count() - 1, src.surface_get_material(si))
	return [outside, inside]


# --- internals ---------------------------------------------------------------

## Loads a model once: every surface with its node transform and the definition's yaw applied.
static func _load(id: String) -> Dictionary:
	if _raw.has(id):
		return _raw[id]
	var def: Array = DEFS[id]
	var scene := load(DIR + def[0] + ".glb") as PackedScene
	var root := scene.instantiate()
	var pitch: float = def[3] if def.size() > 3 else 0.0
	var drop: String = def[4] if def.size() > 4 else ""
	var turn := Transform3D(Basis(Vector3.UP, def[2]) * Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
	var surfaces := []
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var path := "/" + str(root.get_path_to(mi)) + "/"
		if not _matches(path, def[1], true) or (drop != "" and _matches(path, drop, false)):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		xf = turn * xf
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var verts := PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
			for i in verts.size():
				verts[i] = xf * verts[i]
				if first:
					box = AABB(verts[i], Vector3.ZERO)
					first = false
				else:
					box = box.expand(verts[i])
			arrays[Mesh.ARRAY_VERTEX] = verts
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals := PackedVector3Array(arrays[Mesh.ARRAY_NORMAL])
				for i in normals.size():
					normals[i] = (xf.basis.inverse().transposed() * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			for extra in [Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
				arrays[extra] = null
			if arrays[Mesh.ARRAY_INDEX] == null:
				var seq := PackedInt32Array()
				seq.resize(verts.size())
				for i in verts.size():
					seq[i] = i
				arrays[Mesh.ARRAY_INDEX] = seq
			var m := mi.get_surface_override_material(si)
			if m == null:
				m = mi.mesh.surface_get_material(si)
			surfaces.append({"path": path, "arrays": arrays, "material": m})
	root.free()
	assert(not surfaces.is_empty(), "model %s: no meshes match %s" % [id, def[1]])
	_raw[id] = {"surfaces": surfaces, "aabb": box}
	return _raw[id]


## Transform from the raw model space into the sized space (bottom centre at the origin).
static func _fit(box: AABB, size: Vector3) -> Transform3D:
	var s := Vector3.ONE
	var known := 0
	var sum := 0.0
	for i in 3:
		if size[i] > 0.0 and box.size[i] > 0.0001:
			s[i] = size[i] / box.size[i]
			sum += s[i]
			known += 1
	var uniform := sum / maxf(known, 1)
	for i in 3:
		if size[i] <= 0.0 or box.size[i] <= 0.0001:
			s[i] = uniform
	var origin := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return Transform3D(Basis.from_scale(s), -origin * s)


static func _matches(path: String, filter: String, empty_matches: bool) -> bool:
	if filter == "":
		return empty_matches
	for f in filter.split("|"):
		if path.contains(f):
			return true
	return false


## PS1 version of an imported material (texture, colour, cut-out alpha, vertex colours).
static func _ps1(src: Material, tint: Color) -> ShaderMaterial:
	var key := "%s|%s" % [src.get_instance_id() if src else 0, tint.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = PS1_SHADER
	m.set_shader_parameter("use_mesh_uv", true)
	# No affine warp: pack textures are atlases, and a warped UV slides into the neighbour's cell.
	m.set_shader_parameter("affine", 0.0)
	m.set_shader_parameter("roughness_value", 0.9)
	var color := tint
	var sm := src as BaseMaterial3D
	if sm:
		color *= sm.albedo_color
		m.set_shader_parameter("albedo_tex", sm.albedo_texture if sm.albedo_texture else Lowpoly.white_texture())
		m.set_shader_parameter("use_vertex_color", sm.vertex_color_use_as_albedo)
		if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			m.set_shader_parameter("alpha_cut", 0.5)
		if sm.emission_enabled:
			m.set_shader_parameter("emission_color", sm.emission)
			m.set_shader_parameter("emission_energy", sm.emission_energy_multiplier)
	else:
		m.set_shader_parameter("albedo_tex", Lowpoly.white_texture())
	m.set_shader_parameter("tint", Color(color.r, color.g, color.b, 1.0))
	_materials[key] = m
	return m
