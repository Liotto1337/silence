class_name HingedDoor
extends AnimatableBody3D
## A door that swings around its own origin (the hinge): wardrobe, fridge, room doors, front door.

signal opened

@export var open_angle: float = deg_to_rad(105.0)
@export var open_prompt: String = "Открыть"
@export var close_prompt: String = "Закрыть"

var is_open: bool = false
## Return false to refuse opening (e.g. locked front door). Receives the player.
var can_open: Callable
var locked_prompt: String = ""
## Swings away from whoever opens it (room doors), otherwise always by `open_angle`.
var two_way: bool = false
var open_sound: AudioStream
var close_sound: AudioStream
var locked_sound: AudioStream
var sound_pitch: float = 1.0
var _tween: Tween
var _closed_y: float
var _mirrored: bool = false
var _swing: float  # the angle of the current opening
var _locked_audio: AudioStreamPlayer3D
var _panel_center: Vector3


func _ready() -> void:
	_closed_y = rotation.y
	_swing = open_angle


## Builds a flat door panel extending from the hinge along +X (or -X when mirrored).
func build_panel(size: Vector3, color: Color, mirrored: bool) -> void:
	var sx := -1.0 if mirrored else 1.0
	var center := Vector3(sx * size.x * 0.5, size.y * 0.5, 0)
	_mirrored = mirrored
	_panel_center = center
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
		_play_locked()
		return
	if is_open:
		set_open(false)
	else:
		open_from(player.global_position)


## Opens the door; a two-way door swings to the side away from `opener_pos`.
func open_from(opener_pos: Vector3) -> void:
	if is_open:
		return
	_swing = open_angle
	if two_way:
		var closed := get_parent_node_3d().global_transform * Transform3D(Basis(Vector3.UP, _closed_y), position)
		var local := closed.affine_inverse() * opener_pos
		# A positive angle swings a +X panel towards -Z (a mirrored one towards +Z).
		var away := 1.0 if local.z > 0.0 else -1.0
		_swing = absf(open_angle) * away * (-1.0 if _mirrored else 1.0)
	set_open(true)


func set_open(value: bool) -> void:
	if value == is_open:
		return
	is_open = value
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "rotation:y", _closed_y + (_swing if is_open else 0.0), 0.35).set_trans(Tween.TRANS_SINE)
	var sound := open_sound if is_open else close_sound
	if sound and is_inside_tree():
		Sfx.play_3d(sound, to_global(_panel_center), -2.0, 25.0, sound_pitch * randf_range(0.96, 1.04))
	if is_open:
		opened.emit()


func _play_locked() -> void:
	if locked_sound == null:
		return
	if _locked_audio == null:
		_locked_audio = AudioStreamPlayer3D.new()
		_locked_audio.stream = locked_sound
		_locked_audio.position = _panel_center
		_locked_audio.max_distance = 20.0
		add_child(_locked_audio)
	if not _locked_audio.playing:  # mashing the button doesn't stack rattles
		_locked_audio.play()
