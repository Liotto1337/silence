class_name Toy
extends Prop
## A toy for the "tidy up your room" quest. Counted by the ToyBox.
## The teddy squeaks like the duck; a thrown car rattles on the floor and draws the monster.

enum Kind { BLOCK, BALL, TEDDY, CAR, PYRAMID }

const RATTLE_TIME := 2.3  ## length of the clockwork sound
const RATTLE_NOISE := 12.0
const HIGHLIGHT_SHADER := preload("res://shaders/highlight.gdshader")

static var _highlight_mat: ShaderMaterial

var kind: Kind
var highlighted: bool = false
var _wound: bool = false  # thrown car: starts rattling when it lands
var _rattle_time: float = 0.0
var _rattle_noise_timer: float = 0.0
var _rattle_audio: AudioStreamPlayer3D
var _squeak_cooldown: float = 0.0


static func create(kind: Kind, color_index: int = 0) -> Toy:
	var t := Toy.new()
	t.kind = kind
	t.add_to_group(&"toy")
	t.mass = 0.4
	match kind:
		Kind.BLOCK:
			t.display_name = "Кубик"
			t.add_box_shape(Vector3(0.18, 0.18, 0.18), Vector3(0, 0.09, 0))
			t.add_model("block_a" if color_index % 2 == 0 else "block_b", Vector3(0.18, 0.18, 0.18))
			t.impact_sounds = Sfx.WOOD_BLOCK
			t.place_sounds = Sfx.WOOD_BLOCK
		Kind.BALL:
			t.display_name = "Мячик"
			t.add_model("ball", Vector3(0.22, 0.22, 0.22))
			t.add_sphere_shape(0.11, Vector3(0, 0.11, 0))
			var pm := PhysicsMaterial.new()
			pm.bounce = 0.4
			t.physics_material_override = pm
			t.impact_sounds = Sfx.BALL_BOUNCE
			t.place_sounds = Sfx.BALL_BOUNCE
		Kind.TEDDY:
			t.display_name = "Плюшевый мишка"
			t.add_model("teddy", Vector3(0, 0.36, 0))
			t.add_sphere_shape(0.11, Vector3(0, 0.11, 0))
			t.add_sphere_shape(0.075, Vector3(0, 0.27, 0))
			t.add_step_trigger(0.14, func(_p: Player) -> void: t.squeak())
		Kind.CAR:
			t.display_name = "Машинка"
			t.add_box_shape(Vector3(0.26, 0.11, 0.13), Vector3(0, 0.07, 0))
			t.add_model("toy_car", Vector3(0.28, 0, 0.14))
			t.impact_sounds = Sfx.PLASTIC
			t.place_sounds = Sfx.PLASTIC
			t._rattle_audio = AudioStreamPlayer3D.new()
			t._rattle_audio.stream = Sfx.CAR_RATCHET
			t._rattle_audio.unit_size = 3.0
			t._rattle_audio.max_distance = 25.0
			t.add_child(t._rattle_audio)
		Kind.PYRAMID:
			t.display_name = "Пирамидка"
			t.add_model("pyramid", Vector3(0, 0.26, 0))
			t.add_cylinder_shape(0.08, 0.24, Vector3(0, 0.12, 0))
			t.impact_sounds = Sfx.WOOD_BLOCK
			t.place_sounds = Sfx.WOOD_BLOCK
	return t


func _physics_process(delta: float) -> void:
	super(delta)
	_squeak_cooldown = maxf(_squeak_cooldown - delta, 0.0)
	if _rattle_time > 0.0:
		_update_rattle(delta)


func set_held(value: bool) -> void:
	super(value)
	if value:
		_wound = false
		_stop_rattle()


func is_rattling() -> bool:
	return _rattle_time > 0.0


## Pulsing glow seen through furniture: the quest's hint when a toy can't be found.
func set_highlight(on: bool) -> void:
	if on == highlighted:
		return
	highlighted = on
	if _highlight_mat == null:
		_highlight_mat = ShaderMaterial.new()
		_highlight_mat.shader = HIGHLIGHT_SHADER
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_overlay = _highlight_mat if on else null


func squeak() -> void:
	if _squeak_cooldown > 0.0:
		return
	_squeak_cooldown = 0.8
	Sfx.play_3d(Sfx.SQUEAK, global_position, 4.0, 40.0, randf_range(0.95, 1.08))
	NoiseBus.emit_noise(global_position, NoiseBus.DUCK_SQUEAK, self)


func on_thrown() -> void:
	if kind == Kind.CAR:
		_wound = true


func _on_body_entered(body: Node) -> void:
	if _rattle_time > 0.0:
		return  # its own shaking
	if _wound and not held:
		_wound = false
		_start_rattle()
		return
	super(body)


func _on_impact(speed: float) -> void:
	if kind == Kind.TEDDY:
		squeak()
	else:
		super(speed)


## A thrown clockwork car lands and buzzes in place, shaking on the floor (loud: the monster hears it).
func _start_rattle() -> void:
	_rattle_time = RATTLE_TIME
	_rattle_noise_timer = 0.0
	_rattle_audio.play()


func _stop_rattle() -> void:
	_rattle_time = 0.0
	if _rattle_audio:
		_rattle_audio.stop()


func _update_rattle(delta: float) -> void:
	_rattle_time = maxf(_rattle_time - delta, 0.0)
	if _rattle_time <= 0.0:
		_stop_rattle()
		return
	_rattle_noise_timer -= delta
	if _rattle_noise_timer <= 0.0:
		_rattle_noise_timer = 1.0
		NoiseBus.emit_noise(global_position, RATTLE_NOISE, self)
	if get_contact_count() > 0:
		apply_central_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.0), randf_range(-1.0, 1.0)) * 0.03)
		apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.0015)
