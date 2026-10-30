class_name MonsterModel
extends Node3D
## The monster: a low-poly rigged creature ("Nightmare Creature 1#" by Rodolfoisreal1423,
## CC BY 4.0, see CREDITS.md) with the model's own animations. The owner (Monster) drives it every
## physics frame through `move_speed`, `pose` and `head_yaw`; the model picks idle / walk / run /
## roar / attack, scales the gait to the real speed and emits `footstep` when a foot plants.

signal footstep(position: Vector3, speed: float)

enum Pose { NORMAL, LOOK, ALERT, ROAR, ATTACK }

const MODEL := preload("res://assets/models/monster/nightmare_creature.glb")
const SKIN := preload("res://assets/models/monster/albedo_ps1.png")
const PS1_SHADER := preload("res://shaders/ps1.gdshader")
const MODEL_SCALE := 1.15  ## the source is ~2 m hunched; the capsule is 2.3 m
const WALK_MIN_SPEED := 0.25
const RUN_MIN_SPEED := 2.6
const WALK_REF_SPEED := 1.7  ## ground speed at which the walk clip looks planted
const RUN_REF_SPEED := 4.6
const BLEND := 0.25
const FOOT_BONES: Array[String] = ["Foot.L_054", "Foot.R_058"]
const TOE_BONES: Array[String] = ["Toe.L_end_071", "Toe.R_end_074"]
const ATTACKS: Array[String] = ["attack_1", "attack_2", "attack_3", "bite"]

var move_speed: float = 0.0
var pose: Pose = Pose.NORMAL
var head_yaw: float = 0.0  ## where the monster is looking, relative to its body (radians)

var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _head: HeadLook
var _current: String = ""
var _last_pose: Pose = Pose.NORMAL
var _foot_ids: Array[int] = []
var _foot_low: Array[bool] = [false, false]
var _foot_min: Array[float] = [INF, INF]
var _foot_max: Array[float] = [-INF, -INF]


func _ready() -> void:
	var root := MODEL.instantiate() as Node3D
	root.rotation.y = PI  # the model faces +Z, the game's "forward" is -Z
	root.scale = Vector3.ONE * MODEL_SCALE
	add_child(root)
	_anim = root.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = root.find_children("*", "Skeleton3D", true, false)[0]
	for m in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = _skin_material()
		(m as MeshInstance3D).extra_cull_margin = 1.0  # skinned AABB is the bind pose
	for name_ in ["idle", "battle_idle", "walk", "Run"]:
		_anim.get_animation(_clip(name_)).loop_mode = Animation.LOOP_LINEAR
	for b in FOOT_BONES:
		_foot_ids.append(_skeleton.find_bone(b))
	_head = HeadLook.new()
	_skeleton.add_child(_head)
	_play("idle")


func _physics_process(delta: float) -> void:
	_head.yaw = head_yaw
	var clip := _pick_clip()
	if clip != _current or (pose != _last_pose and pose in [Pose.ROAR, Pose.ATTACK]):
		_play(clip)
	_last_pose = pose
	match _current:
		"walk":
			_anim.speed_scale = clampf(move_speed / WALK_REF_SPEED, 0.6, 1.6)
		"Run":
			_anim.speed_scale = clampf(move_speed / RUN_REF_SPEED, 0.7, 1.4)
		_:
			_anim.speed_scale = 1.0
	if _current == "walk" or _current == "Run":
		_check_steps()
	else:
		_foot_low = [false, false]


## Height of each toe tip above the model's origin (left, right); used by the tests and debugging.
func foot_heights() -> Array[float]:
	var out: Array[float] = []
	for b in TOE_BONES:
		var id := _skeleton.find_bone(b)
		var tip := _skeleton.global_transform * _skeleton.get_bone_global_pose(id).origin
		out.append(tip.y - global_position.y)
	return out


func _pick_clip() -> String:
	match pose:
		Pose.ATTACK:
			return _current if _current in ATTACKS else ATTACKS[0]
		Pose.ROAR:
			return "roar"
		Pose.ALERT:
			return "battle_idle"
	if move_speed >= RUN_MIN_SPEED:
		return "Run"
	if move_speed >= WALK_MIN_SPEED:
		return "walk"
	return "idle"


func _play(clip: String) -> void:
	_current = clip
	_anim.play(_clip(clip), BLEND)


func _clip(short_name: String) -> String:
	return "Creature_armature|" + short_name


## A foot has planted when its height drops into the lowest quarter of its recent range.
func _check_steps() -> void:
	for i in 2:
		if _foot_ids[i] < 0:
			continue
		var y := (_skeleton.global_transform * _skeleton.get_bone_global_pose(_foot_ids[i])).origin.y
		_foot_min[i] = minf(_foot_min[i], y)
		_foot_max[i] = maxf(_foot_max[i], y)
		var span: float = _foot_max[i] - _foot_min[i]
		var low: bool = span > 0.08 and y < _foot_min[i] + span * 0.25
		if low and not _foot_low[i]:
			var pos := (_skeleton.global_transform * _skeleton.get_bone_global_pose(_foot_ids[i])).origin
			footstep.emit(Vector3(pos.x, global_position.y, pos.z), move_speed)
		_foot_low[i] = low
		# Let the range follow the current gait instead of remembering the run forever.
		_foot_min[i] = lerpf(_foot_min[i], y, 0.002)
		_foot_max[i] = lerpf(_foot_max[i], y, 0.002)


func _skin_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PS1_SHADER
	m.set_shader_parameter("albedo_tex", SKIN)
	m.set_shader_parameter("use_mesh_uv", true)
	m.set_shader_parameter("tint", Color(0.82, 0.74, 0.74))
	m.set_shader_parameter("roughness_value", 0.85)
	m.set_shader_parameter("affine", 0.8)
	return m
