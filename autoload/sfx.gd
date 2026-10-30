extends Node
## Fire-and-forget sound playback plus the shared sound library.

const ROAR := preload("res://assets/sounds/monster_roar.ogg")
const MONSTER_STEPS: Array[AudioStream] = [
	preload("res://assets/sounds/monster_step_1.wav"),
	preload("res://assets/sounds/monster_step_2.wav"),
	preload("res://assets/sounds/monster_step_3.wav"),
	preload("res://assets/sounds/monster_step_4.wav"),
]
const MONSTER_RUN_STEPS: Array[AudioStream] = [
	preload("res://assets/sounds/monster_run_1.wav"),
	preload("res://assets/sounds/monster_run_2.wav"),
	preload("res://assets/sounds/monster_run_3.wav"),
	preload("res://assets/sounds/monster_run_4.wav"),
]
const SQUEAK := preload("res://assets/sounds/toy_squeak.wav")
const TV_STATIC := preload("res://assets/sounds/tv_static.wav")
const WALK_STEPS: Array[AudioStream] = [
	preload("res://assets/sounds/step_walk_1.wav"),
	preload("res://assets/sounds/step_walk_2.wav"),
	preload("res://assets/sounds/step_walk_3.wav"),
	preload("res://assets/sounds/step_walk_4.wav"),
	preload("res://assets/sounds/step_walk_5.wav"),
	preload("res://assets/sounds/step_walk_6.wav"),
]
const RUN_STEPS: Array[AudioStream] = [
	preload("res://assets/sounds/step_run_1.wav"),
	preload("res://assets/sounds/step_run_2.wav"),
	preload("res://assets/sounds/step_run_3.wav"),
	preload("res://assets/sounds/step_run_4.wav"),
	preload("res://assets/sounds/step_run_5.wav"),
	preload("res://assets/sounds/step_run_6.wav"),
]
const AMBIENT: Array[AudioStream] = [
	preload("res://assets/sounds/amb_electric_wave.ogg"),
	preload("res://assets/sounds/amb_crow.ogg"),
	preload("res://assets/sounds/amb_crow_once.ogg"),
	preload("res://assets/sounds/amb_house_1.ogg"),
	preload("res://assets/sounds/amb_house_2.ogg"),
	preload("res://assets/sounds/creak_1.ogg"),
	preload("res://assets/sounds/creak_2.ogg"),
]
const ROOM_TONE := preload("res://assets/sounds/room_tone.ogg")
const MONSTER_BREATH := preload("res://assets/sounds/monster_breath.ogg")
const MONSTER_GROWLS: Array[AudioStream] = [
	preload("res://assets/sounds/monster_growl_1.ogg"),
	preload("res://assets/sounds/monster_growl_2.ogg"),
]
const THUD := preload("res://assets/sounds/impact_thud.wav")
const FAN_HUM := preload("res://assets/sounds/fan_hum.wav")
const BREATH := preload("res://assets/sounds/breath.wav")
const BREATH_RECOVER := preload("res://assets/sounds/breath_recover.wav")
const GOAL := preload("res://assets/sounds/goal.wav")

# Props.
const BALL_BOUNCE: Array[AudioStream] = [
	preload("res://assets/sounds/ball_bounce_1.wav"),
	preload("res://assets/sounds/ball_bounce_2.wav"),
	preload("res://assets/sounds/ball_bounce_3.wav"),
]
const PLASTIC: Array[AudioStream] = [
	preload("res://assets/sounds/plastic_1.wav"),
	preload("res://assets/sounds/plastic_2.wav"),
]
const WOOD_BLOCK: Array[AudioStream] = [preload("res://assets/sounds/wood_block.wav")]
const CAR_RATCHET := preload("res://assets/sounds/car_ratchet.wav")
const VASE_HIT: Array[AudioStream] = [preload("res://assets/sounds/vase_hit.wav")]
const VASE_BREAK := preload("res://assets/sounds/vase_break.wav")

# Furniture and doors.
const DRAWER_OPEN := preload("res://assets/sounds/drawer_open.wav")
const DRAWER_CLOSE := preload("res://assets/sounds/drawer_close.wav")
const CABINET_OPEN := preload("res://assets/sounds/cabinet_open.wav")
const CABINET_CLOSE := preload("res://assets/sounds/cabinet_close.wav")
const DOOR_OPEN := preload("res://assets/sounds/door_open.wav")
const DOOR_CLOSE := preload("res://assets/sounds/door_close.wav")
const DOOR_LOCKED := preload("res://assets/sounds/door_locked.wav")


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


## Returns a looping copy of an Ogg stream.
func looped_ogg(stream: AudioStreamOggVorbis) -> AudioStreamOggVorbis:
	var s := stream.duplicate() as AudioStreamOggVorbis
	s.loop = true
	return s


## Returns a looping copy of a WAV stream (imported WAVs don't loop by default).
func looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	var s := stream.duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s
