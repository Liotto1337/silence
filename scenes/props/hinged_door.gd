class_name HingedDoor
extends AnimatableBody3D
## A door that swings around its own origin (the hinge): wardrobe, fridge, front door.

signal opened

@export var open_angle: float = deg_to_rad(105.0)
@export var open_prompt: String = "Открыть"
@export var close_prompt: String = "Закрыть"

var is_open: bool = false
## Return false to refuse opening (e.g. locked front door). Receives the player.
var can_open: Callable
var locked_prompt: String = ""
var _tween: Tween
var _closed_y: float


func _ready() -> void:
	_closed_y = rotation.y


## Builds a flat door panel extending from the hinge along +X (or -X when mirrored).
func build_panel(size: Vector3, color: Color, mirrored: bool) -> void:
	var sx := -1.0 if mirrored else 1.0
	var center := Vector3(sx * size.x * 0.5, size.y * 0.5, 0)
	Lowpoly.add_mesh(self, Lowpoly.box(size), color, center)
	Lowpoly.add_box_shape(self, size, center)
	# Handle on the free edge.
	Lowpoly.add_mesh(self, Lowpoly.box(Vector3(0.03, 0.14, 0.03)), Color("b0b0b0"), Vector3(sx * (size.x - 0.07), size.y * 0.5, size.z * 0.5 + 0.02))


func get_prompt(player: Player) -> String:
	if not is_open and can_open.is_valid() and not can_open.call(player):
		return locked_prompt
	return close_prompt if is_open else open_prompt


func interact(player: Player) -> void:
	if not is_open and can_open.is_valid() and not can_open.call(player):
		return
	set_open(not is_open)


func set_open(value: bool) -> void:
	if value == is_open:
		return
	is_open = value
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "rotation:y", _closed_y + (open_angle if is_open else 0.0), 0.35).set_trans(Tween.TRANS_SINE)
	if is_open:
		opened.emit()
