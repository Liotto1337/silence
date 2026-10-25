class_name Drawer
extends AnimatableBody3D
## Pull-out drawer of a dresser. Slides along its local +Z. Items placed in `content` ride along.

const SLIDE := 0.32

var is_open: bool = false
var content: Node3D
var _closed_pos: Vector3
var _tween: Tween


static func create(width: float, height: float, depth: float, color: Color) -> Drawer:
	var d := Drawer.new()
	# Front panel + tray (bottom, sides, back) so items inside are visible when pulled out.
	var front := Vector3(width, height, 0.02)
	Lowpoly.add_mesh(d, Lowpoly.box(front), color, Vector3(0, 0, depth * 0.5))
	Lowpoly.add_box_shape(d, front, Vector3(0, 0, depth * 0.5))
	Lowpoly.add_mesh(d, Lowpoly.box(Vector3(0.12, 0.025, 0.025)), Color("c9b26b"), Vector3(0, 0, depth * 0.5 + 0.02))
	var inner := color.darkened(0.35)
	Lowpoly.add_mesh(d, Lowpoly.box(Vector3(width - 0.04, 0.01, depth)), inner, Vector3(0, -height * 0.5 + 0.01, 0))
	Lowpoly.add_box_shape(d, Vector3(width - 0.04, 0.01, depth), Vector3(0, -height * 0.5 + 0.01, 0))
	for sx: float in [-1.0, 1.0]:
		Lowpoly.add_mesh(d, Lowpoly.box(Vector3(0.01, height * 0.7, depth)), inner, Vector3(sx * (width * 0.5 - 0.03), -height * 0.15, 0))
	Lowpoly.add_mesh(d, Lowpoly.box(Vector3(width - 0.04, height * 0.7, 0.01)), inner, Vector3(0, -height * 0.15, -depth * 0.5))
	d.content = Node3D.new()
	d.content.position = Vector3(0, -height * 0.5 + 0.015, 0)
	d.add_child(d.content)
	return d


func _ready() -> void:
	_closed_pos = position


func get_prompt(_player: Player) -> String:
	return "Задвинуть ящик" if is_open else "Выдвинуть ящик"


func interact(_player: Player) -> void:
	is_open = not is_open
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var target := _closed_pos + transform.basis.z * (SLIDE if is_open else 0.0)
	_tween.tween_property(self, "position", target, 0.25).set_trans(Tween.TRANS_SINE)
