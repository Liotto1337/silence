class_name ItemZone
extends Area3D
## Counts props of a given group inside it (toy box, cereal bowl).

signal contents_changed

var _inside: Dictionary = {}  # instance_id -> Prop


static func create(size: Vector3) -> ItemZone:
	var z := ItemZone.new()
	z.collision_layer = 0
	z.collision_mask = Prop.LAYER_PROPS
	z.monitorable = false
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	z.add_child(cs)
	return z


func _ready() -> void:
	body_entered.connect(func(b: Node3D) -> void:
		if b is Prop:
			_inside[b.get_instance_id()] = b
			contents_changed.emit())
	body_exited.connect(func(b: Node3D) -> void:
		if _inside.erase(b.get_instance_id()):
			contents_changed.emit())


func count_in_group(group: StringName) -> int:
	return get_in_group(group).size()


func get_in_group(group: StringName) -> Array[Prop]:
	var out: Array[Prop] = []
	for p: Variant in _inside.values():
		if is_instance_valid(p) and (p as Prop).is_in_group(group):
			out.append(p)
	return out
