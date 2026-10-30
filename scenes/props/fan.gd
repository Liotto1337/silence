class_name VentFan
extends StaticBody3D
## Spinning fan behind a grille — explains why a vent branch is a dead end.

## Radius of the blade circle in the fan texture (UV units), just inside the frame's round opening.
const ROTOR_UV_RADIUS := 0.465
const ROTOR_SEGMENTS := 24

var _blades: Node3D


static func create(width: float, height: float) -> VentFan:
	var f := VentFan.new()
	f.collision_layer = Prop.LAYER_WORLD
	# Grille blocks the whole duct cross-section.
	Lowpoly.add_box_shape(f, Vector3(width, height, 0.1))
	# The PC-fan model fills the duct end. It is a flat slab with a picture of a fan on it, so the
	# frame stays as it is and the rotor is a disc in front of it showing the round middle of the
	# same texture: turning the disc turns the blades, the square frame and its corners stay still.
	var model := Models.mesh("fan", Vector3(width, height, 0.1))
	var frame := MeshInstance3D.new()
	frame.mesh = model
	frame.position = Vector3(0, -height * 0.5, -0.05)
	f.add_child(frame)
	f._blades = Node3D.new()
	f._blades.position = Vector3(0, 0, 0.004)
	f.add_child(f._blades)
	var rotor := MeshInstance3D.new()
	rotor.mesh = _rotor_disc(width, height, model.surface_get_material(0))
	f._blades.add_child(rotor)
	var hum := AudioStreamPlayer3D.new()
	hum.stream = Sfx.looped(Sfx.FAN_HUM)
	hum.autoplay = true
	hum.volume_db = -6.0
	hum.unit_size = 1.5
	hum.max_distance = 12.0
	f.add_child(hum)
	return f


## Disc facing +Z whose UVs cover the blade circle of the fan texture (the texture spans the whole
## face: u runs along the width, v up the height).
static func _rotor_disc(width: float, height: float, material: Material) -> ArrayMesh:
	var radius := ROTOR_UV_RADIUS * minf(width, height)
	var verts := PackedVector3Array([Vector3.ZERO])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	var idx := PackedInt32Array()
	for i in ROTOR_SEGMENTS:
		var a := TAU * i / ROTOR_SEGMENTS
		var p := Vector2(cos(a), sin(a)) * radius
		verts.append(Vector3(p.x, p.y, 0.0))
		uvs.append(Vector2(0.5 + p.x / width, 0.5 + p.y / height))
		idx.append_array([0, 1 + (i + 1) % ROTOR_SEGMENTS, 1 + i])  # clockwise seen from +Z = front face
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _process(delta: float) -> void:
	_blades.rotation.z += delta * 14.0
