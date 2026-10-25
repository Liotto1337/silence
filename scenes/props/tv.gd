class_name Tv
extends Interactable
## Television. While on, it hisses static and keeps making noise the monster can hear.
## The monster switches it off when it reaches it.

const NOISE_INTERVAL := 3.0

var is_on: bool = false
var _screen: MeshInstance3D
var _light: OmniLight3D
var _audio: AudioStreamPlayer3D
var _noise_timer: float = 0.0
var _off_mat: StandardMaterial3D
var _on_mat: StandardMaterial3D


static func create() -> Tv:
	var tv := Tv.new()
	tv.collision_layer = Prop.LAYER_WORLD
	Lowpoly.add_mesh(tv, Lowpoly.box(Vector3(1.0, 0.6, 0.12)), Color("202020"), Vector3(0, 0.3, 0))
	Lowpoly.add_box_shape(tv, Vector3(1.0, 0.6, 0.12), Vector3(0, 0.3, 0))
	tv._screen = Lowpoly.add_mesh(tv, Lowpoly.box(Vector3(0.88, 0.5, 0.01)), Color("0d1110"), Vector3(0, 0.3, 0.061))
	tv._off_mat = Lowpoly.mat(Color("0d1110"), 0.3)
	tv._on_mat = Lowpoly.mat(Color("b8c8d0"), 0.3, 0.0, 2.5)
	tv._light = OmniLight3D.new()
	tv._light.position = Vector3(0, 0.3, 0.5)
	tv._light.light_color = Color("a9c4ff")
	tv._light.omni_range = 4.5
	tv._light.light_energy = 0.0
	tv.add_child(tv._light)
	tv._audio = AudioStreamPlayer3D.new()
	tv._audio.stream = Sfx.looped(Sfx.TV_STATIC)
	tv._audio.position = Vector3(0, 0.3, 0)
	tv._audio.unit_size = 4.0
	tv._audio.max_distance = 30.0
	tv.add_child(tv._audio)
	tv.prompt_provider = func(_p: Player) -> String: return "Выключить телевизор" if tv.is_on else "Включить телевизор"
	tv.interacted.connect(func(_p: Player) -> void: tv.toggle())
	return tv


func toggle() -> void:
	set_on(not is_on)


func set_on(value: bool) -> void:
	is_on = value
	_screen.material_override = _on_mat if is_on else _off_mat
	_light.light_energy = 1.2 if is_on else 0.0
	if is_on:
		_audio.play()
		_noise_timer = 0.0
	else:
		_audio.stop()


## Called by the monster when it arrives at the noise source.
func monster_disable() -> void:
	set_on(false)


func _physics_process(delta: float) -> void:
	if not is_on:
		return
	_light.light_energy = 0.9 + randf() * 0.6
	_noise_timer -= delta
	if _noise_timer <= 0.0:
		_noise_timer = NOISE_INTERVAL
		NoiseBus.emit_noise(global_position + Vector3(0, 0.3, 0.3), NoiseBus.TV, self)
