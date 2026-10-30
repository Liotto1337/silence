class_name VentFan
extends StaticBody3D
## Spinning fan behind a grille — explains why a vent branch is a dead end.

var _blades: Node3D


static func create(width: float, height: float) -> VentFan:
	var f := VentFan.new()
	f.collision_layer = Prop.LAYER_WORLD
	# Grille blocks the whole duct cross-section.
	Lowpoly.add_box_shape(f, Vector3(width, height, 0.1))
	# The PC-fan model fills the duct end; its rotor (the middle) is cut out and spins.
	var parts := Models.split(Models.mesh("fan", Vector3(width, height, 0.1)), AABB(Vector3(-width * 0.42, height * 0.08, -1), Vector3(width * 0.84, height * 0.84, 2)))
	var frame := MeshInstance3D.new()
	frame.mesh = parts[0]
	frame.position = Vector3(0, -height * 0.5, -0.05)
	f.add_child(frame)
	f._blades = Node3D.new()
	f._blades.position = Vector3(0, 0, -0.05)
	f.add_child(f._blades)
	var rotor := MeshInstance3D.new()
	rotor.mesh = parts[1]
	rotor.position = Vector3(0, -height * 0.5, 0)
	f._blades.add_child(rotor)
	var hum := AudioStreamPlayer3D.new()
	hum.stream = Sfx.looped(Sfx.FAN_HUM)
	hum.autoplay = true
	hum.volume_db = -6.0
	hum.unit_size = 1.5
	hum.max_distance = 12.0
	f.add_child(hum)
	return f


func _process(delta: float) -> void:
	_blades.rotation.z += delta * 14.0
