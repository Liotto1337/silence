class_name Drawer
extends AnimatableBody3D
## Pull-out drawer of a dresser. Slides along its local +Z. Items placed in `content` ride along.

const SLIDE := 0.32
## Slide times matched to the sounds: the drawer hits its stop on the knock (open) or the thud (close).
const OPEN_TIME := 0.76
const CLOSE_TIME := 0.6

var is_open: bool = false
var content: Node3D
var _closed_pos: Vector3
var _tween: Tween


## `front` is the drawer front cut from the furniture model; `front_offset` places it on the drawer.
## The tray behind it is the toy box model, squeezed to the drawer's size.
static func create(width: float, height: float, depth: float, front: Mesh, front_offset: Vector3) -> Drawer:
	var d := Drawer.new()
	var face := MeshInstance3D.new()
	face.mesh = front
	face.position = front_offset
	d.add_child(face)
	Lowpoly.add_box_shape(d, Vector3(width, height, 0.02), Vector3(0, 0, depth * 0.5))
	Models.add(d, "toy_box", Vector3(width - 0.04, height * 0.7, depth - 0.02), Vector3(0, -height * 0.5 + 0.005, -0.01))
	Lowpoly.add_box_shape(d, Vector3(width - 0.04, 0.01, depth), Vector3(0, -height * 0.5 + 0.01, 0))
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
	_tween.tween_property(self, "position", target, OPEN_TIME if is_open else CLOSE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	Sfx.play_3d(Sfx.DRAWER_OPEN if is_open else Sfx.DRAWER_CLOSE, global_position, -4.0, 18.0, randf_range(0.95, 1.05))
