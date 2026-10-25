extends Node
## Fire-and-forget sound playback plus the shared sound library.

const ROAR := preload("res://assets/sounds/monster_roar.wav")
const GROWL := preload("res://assets/sounds/monster_growl.wav")
const MONSTER_STEP := preload("res://assets/sounds/monster_step.wav")
const SQUEAK := preload("res://assets/sounds/duck_squeak.wav")
const TV_STATIC := preload("res://assets/sounds/tv_static.wav")
const RUN_STEPS: Array[AudioStream] = [
	preload("res://assets/sounds/step_run_1.wav"),
	preload("res://assets/sounds/step_run_2.wav"),
	preload("res://assets/sounds/step_run_3.wav"),
]
const THUD := preload("res://assets/sounds/impact_thud.wav")
const FAN_HUM := preload("res://assets/sounds/fan_hum.wav")
const BREATH := preload("res://assets/sounds/breath.wav")


func play_3d(stream: AudioStream, position: Vector3, volume_db: float = 0.0, max_distance: float = 30.0, pitch: float = 1.0) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene is Node3D:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 3.0
	p.pitch_scale = pitch
	scene.add_child(p)
	p.global_position = position
	p.finished.connect(p.queue_free)
	p.play()


func play_2d(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Returns a looping copy of a WAV stream (imported WAVs don't loop by default).
func looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	var s := stream.duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s
