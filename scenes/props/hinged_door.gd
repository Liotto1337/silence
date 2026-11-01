class_name HingedDoor
extends AnimatableBody3D
## A door that swings around its own origin (the hinge): wardrobe, fridge, room doors, front door.

signal opened

const SWEEP_STEPS := 9  ## the swing is checked for a monster in its way every ~10 degrees

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
## Swing times; doors with long sounds take longer so the motion lasts as long as the creak.
var open_time: float = 0.35
var close_time: float = 0.35
var open_ease: Tween.EaseType = Tween.EASE_IN_OUT
var close_ease: Tween.EaseType = Tween.EASE_IN_OUT
var _tween: Tween
var _closed_y: float
var _mirrored: bool = false
var _swing: float  # the angle of the current opening
var _locked_audio: AudioStreamPlayer3D
var _panel_center: Vector3


func _ready() -> void:
	# Moved every rendered frame, not every physics tick: with physics at 60 Hz and the screen at
	# 144+ Hz a door synced to physics visibly stepped ("lagged") while it swung.
	sync_to_physics = false
	_closed_y = rotation.y
	_swing = open_angle


## Door panel from a door model (assets/models/props), fitted to `size` and extending from the
## hinge along +X (or -X when mirrored). The door models have their handle on -X, so a panel
## running along +X is the model turned around: the handle always ends up on the free edge.
func build_model_panel(id: String, size: Vector3, mirrored: bool) -> void:
	var sx := -1.0 if mirrored else 1.0
	_mirrored = mirrored
	_panel_center = Vector3(sx * size.x * 0.5, size.y * 0.5, 0)
	Models.add(self, id, size, Vector3(sx * size.x * 0.5, 0, 0), 0.0 if mirrored else PI)
	Lowpoly.add_box_shape(self, size, _panel_center)


## Door panel from a mesh cut out of a piece of furniture; `offset` moves it so the hinge is at
## this node's origin. The collision box follows the mesh.
func build_mesh_panel(mesh: Mesh, offset: Vector3, mirrored: bool) -> void:
	_mirrored = mirrored
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	add_child(mi)
	var box := mesh.get_aabb()
	_panel_center = box.get_center() + offset
	Lowpoly.add_box_shape(self, box.size.max(Vector3(0.02, 0.02, 0.02)), _panel_center)


func get_prompt(player: Player) -> String:
	if not is_open and can_open.is_valid() and not can_open.call(player):
		return locked_prompt
	return close_prompt if is_open else open_prompt


func interact(player: Player) -> void:
	if not is_open and can_open.is_valid() and not can_open.call(player):
		_play_locked()
		return
	if is_open:
		# Don't swing the leaf through a monster standing in the doorway (it clipped through its
		# body / pinned it); the door just refuses to close.
		if _close_blocked():
			_play_locked()
			return
		set_open(false)
	else:
		open_from(player.global_position, player)


## Opens the door; a two-way door swings to the side away from `opener_pos`. If a monster stands in
## the way on that side (the leaf would sweep it into the wall behind the door and pin it there), it
## swings the other way instead; blocked on both sides, it doesn't open. `opener` (the monster that
## opens it, if any) doesn't count as being in the way.
func open_from(opener_pos: Vector3, opener: Node = null) -> void:
	if is_open:
		return
	_swing = open_angle
	if two_way:
		var closed := get_parent_node_3d().global_transform * Transform3D(Basis(Vector3.UP, _closed_y), position)
		var local := closed.affine_inverse() * opener_pos
		# A positive angle swings a +X panel towards -Z (a mirrored one towards +Z).
		var away := 1.0 if local.z > 0.0 else -1.0
		var preferred := absf(open_angle) * away * (-1.0 if _mirrored else 1.0)
		if not _sweep_blocked(preferred, opener):
			_swing = preferred
		elif not _sweep_blocked(-preferred, opener):
			_swing = -preferred
		else:
			_play_locked()
			return
	set_open(true)


## True if a monster (other than `opener`) stands where the leaf would pass while swinging by `angle`.
func _sweep_blocked(angle: float, opener: Node) -> bool:
	return _sweep_range_blocked(0.0, angle, opener)


## True if a monster stands where the leaf would pass while closing from its open angle to the frame
## (the closed position included, so a monster in the doorway counts).
func _close_blocked() -> bool:
	return _sweep_range_blocked(_swing, 0.0, null)


## `_sweep_blocked` for a swing from angle `from` to angle `to` (relative to the closed position).
func _sweep_range_blocked(from: float, to: float, opener: Node) -> bool:
	var box_node: CollisionShape3D
	for c in get_children():
		if c is CollisionShape3D:
			box_node = c
			break
	if box_node == null or not box_node.shape is BoxShape3D or not is_inside_tree():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box_node.shape
	query.collision_mask = Prop.LAYER_MONSTER
	query.exclude = [get_rid()]
	var closed := get_parent_node_3d().global_transform * Transform3D(Basis(Vector3.UP, _closed_y), position)
	var space := get_world_3d().direct_space_state
	for i in range(1, SWEEP_STEPS + 1):
		query.transform = closed * Transform3D(Basis(Vector3.UP, lerpf(from, to, i / float(SWEEP_STEPS))), Vector3.ZERO) * box_node.transform
		for hit in space.intersect_shape(query, 8):
			var body := hit.collider as Node
			# (The head hitbox pokes through the door; only the body can be pinned.)
			if body == null or body.name == &"HeadHitbox":
				continue
			if not (opener and (body == opener or opener.is_ancestor_of(body))):
				return true
	return false


func set_open(value: bool) -> void:
	if value == is_open:
		return
	is_open = value
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "rotation:y", _closed_y + (_swing if is_open else 0.0), open_time if is_open else close_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(open_ease if is_open else close_ease)
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
