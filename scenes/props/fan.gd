class_name VentFan
extends StaticBody3D
## Spinning fan behind a grille — explains why a vent branch is a dead end.

var _blades: Node3D


static func create(width: float, height: float) -> VentFan:
	var f := VentFan.new()
	f.collision_layer = Prop.LAYER_WORLD
	# Grille blocks the whole duct cross-section.
	Lowpoly.add_box_shape(f, Vector3(width, height, 0.1))
	var metal := Color("6f7479")
	for i in 7:
		var x := -width * 0.5 + (i + 0.5) * width / 7.0
		Lowpoly.add_mesh(f, Lowpoly.box(Vector3(0.015, height, 0.015)), metal, Vector3(x, 0, 0.03))
	for y: float in [-height * 0.3, 0.0, height * 0.3]:
		Lowpoly.add_mesh(f, Lowpoly.box(Vector3(width, 0.015, 0.015)), metal, Vector3(0, y, 0.03))
	f._blades = Node3D.new()
	f._blades.position = Vector3(0, 0, -0.12)
	f.add_child(f._blades)
	Lowpoly.add_mesh(f._blades, Lowpoly.cylinder(0.06, 0.06, 6), Color("2a2a2a"), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	for i in 4:
		var blade := Node3D.new()
		blade.rotation.z = i * PI / 2
		f._blades.add_child(blade)
		Lowpoly.add_mesh(blade, Lowpoly.box(Vector3(0.1, height * 0.42, 0.01)), Color("3c4045"), Vector3(0, height * 0.23, 0), Vector3(0, 0.35, 0))
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
