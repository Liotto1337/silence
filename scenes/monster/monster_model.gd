class_name MonsterModel
extends Node3D
## Lowpoly 2.5 m monster after docs/reference/monster_concept.jpg: an emaciated, slightly
## hunched humanoid with a ribbed chest, long arms reaching the knees, clawed fingers and a dark
## red face with glowing eyes. Built from primitives on a joint hierarchy and animated
## procedurally, so the walk cycle always matches the real speed and footsteps land on cue.
##
## The owner (Monster) drives it every physics frame through `move_speed`, `pose` and
## `head_yaw`; the model emits `footstep` exactly when a foot plants.

signal footstep(position: Vector3, speed: float)

enum Pose { NORMAL, LOOK, ALERT, ROAR, ATTACK }

const HIP_Y := 1.25
const THIGH := 0.6
const SHIN := 0.59
const ANKLE := 0.06
const UPPER_ARM := 0.55
const FOREARM := 0.52

const C_SKIN := Color("1f1f23")
const C_BONE := Color("34333a")
const C_DARK := Color("111114")
const C_FACE := Color("1f0505")
const C_EYE := Color("ff1a0d")

var move_speed: float = 0.0
var pose: Pose = Pose.NORMAL
var head_yaw: float = 0.0  ## where the monster is looking, relative to its body (radians)

var _phase: float = 0.0  # gait cycle 0..1: left heel strike at 0.25, right at 0.75
var _walk_w: float = 0.0
var _run_w: float = 0.0
var _look_w: float = 0.0
var _alert_w: float = 0.0
var _roar_w: float = 0.0
var _attack_w: float = 0.0
var _time: float = 0.0
var _twitch_timer: float = 3.0
var _twitch := Vector3.ZERO

var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _jaw: Node3D
var _thigh: Array[Node3D] = []  # [left, right]
var _shin: Array[Node3D] = []
var _foot: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _forearm: Array[Node3D] = []
var _hand: Array[Node3D] = []
var _fingers: Array[Node3D] = []  # proximal joints of all fingers
var _mats: Dictionary = {}


func _ready() -> void:
	_build()
	_animate(0.0)


func _physics_process(delta: float) -> void:
	_animate(delta)


# --- construction -----------------------------------------------------------

func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.1f" % [color.to_html(), emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	# Rim light keeps the dark silhouette readable in the flashlight beam.
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.4
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scale_: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, emission)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale_
	parent.add_child(mi)
	return mi


## Tapered limb hanging down (-Y) from a joint: radius r_near at the joint, r_far at the end.
func _limb(parent: Node3D, length: float, r_near: float, r_far: float, color: Color = C_SKIN) -> void:
	_part(parent, Lowpoly.cylinder(r_far, length, 6, r_near), color, Vector3(0, -length * 0.5, 0))


func _build() -> void:
	_hips = _joint(self, "Hips", Vector3(0, HIP_Y, 0))
	# Pelvis: a blocky wedge, wider than the waist (the "loincloth" shape of the concept).
	_part(_hips, Lowpoly.cylinder(0.16, 0.3, 6, 0.19), C_SKIN, Vector3(0, -0.04, 0), Vector3(1.0, 1.0, 0.68))
	_part(_hips, Lowpoly.cylinder(0.12, 0.05, 6, 0.17), C_BONE.darkened(0.3), Vector3(0, 0.1, 0), Vector3(1.0, 1.0, 0.7))

	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var thigh := _joint(_hips, "Thigh%d" % side, Vector3(sx * 0.12, -0.08, 0))
		_limb(thigh, THIGH, 0.1, 0.055)
		var shin := _joint(thigh, "Shin%d" % side, Vector3(0, -THIGH, 0))
		_part(shin, Lowpoly.sphere(0.068, 6, 4), C_BONE, Vector3(0, 0, -0.01), Vector3(1.0, 1.1, 1.2))  # knobbly knee
		_limb(shin, SHIN, 0.06, 0.035)
		var foot := _joint(shin, "Foot%d" % side, Vector3(0, -SHIN, 0))
		_part(foot, Lowpoly.box(Vector3(0.1, 0.05, 0.27)), C_SKIN, Vector3(0, -ANKLE + 0.025, -0.08))
		_part(foot, Lowpoly.cylinder(0.035, 0.12, 5, 0.0), C_DARK, Vector3(0, -ANKLE + 0.02, -0.26), Vector3.ONE, Vector3(-PI / 2, 0, 0))
		_thigh.append(thigh)
		_shin.append(shin)
		_foot.append(foot)

	# Waist: a thin spine with vertebrae showing at the back.
	_spine = _joint(_hips, "Spine", Vector3(0, 0.08, 0))
	_part(_spine, Lowpoly.cylinder(0.075, 0.3, 6, 0.06), C_SKIN, Vector3(0, 0.15, 0.01), Vector3(1.3, 1.0, 0.8))
	for i in 4:
		_part(_spine, Lowpoly.box(Vector3(0.05, 0.035, 0.05)), C_BONE, Vector3(0, 0.04 + i * 0.07, 0.07))

	# Ribcage: a dark core wrapped in elliptical rib bands (gaps show the core).
	_chest = _joint(_spine, "Chest", Vector3(0, 0.28, 0))
	_part(_chest, Lowpoly.cylinder(0.12, 0.5, 7, 0.16), C_DARK, Vector3(0, 0.25, 0.01), Vector3(1.25, 1.0, 0.8))
	for i in 6:
		var r := lerpf(0.155, 0.235, float(i) / 5.0)
		var c := C_BONE if i < 4 else C_BONE.lerp(C_FACE, 0.45)
		_part(_chest, Lowpoly.cylinder(r, 0.04, 9), c, Vector3(0, 0.1 + i * 0.065, 0), Vector3(1.15, 1.0, 0.72))
	# Sloping trapezius from the neck to the bony shoulders.
	for sx: float in [-1.0, 1.0]:
		_part(_chest, Lowpoly.box(Vector3(0.24, 0.07, 0.15)), C_SKIN, Vector3(sx * 0.13, 0.5, 0.01), Vector3.ONE, Vector3(0, 0, -sx * 0.35))
	_part(_chest, Lowpoly.box(Vector3(0.05, 0.36, 0.05)), C_BONE, Vector3(0, 0.27, -0.155))  # sternum

	_neck = _joint(_chest, "Neck", Vector3(0, 0.52, -0.04))
	_part(_neck, Lowpoly.cylinder(0.05, 0.16, 6, 0.045), C_SKIN, Vector3(0, 0.07, 0))
	_head = _joint(_neck, "Head", Vector3(0, 0.13, -0.01))
	_part(_head, Lowpoly.sphere(0.16, 8, 5), C_SKIN, Vector3(0, 0.16, 0.03), Vector3(0.95, 1.15, 1.0))
	# Dark red face set into the skull, with concentric rings around the eyes.
	_part(_head, Lowpoly.sphere(0.1, 8, 5), C_FACE, Vector3(0, 0.15, -0.1), Vector3(1.0, 1.15, 0.42))
	for sx: float in [-1.0, 1.0]:
		_part(_head, Lowpoly.cylinder(0.04, 0.01, 8), C_FACE.lightened(0.12), Vector3(sx * 0.042, 0.165, -0.138), Vector3.ONE, Vector3(PI / 2, 0, 0), 0.4)
		_part(_head, Lowpoly.sphere(0.018, 6, 4), C_EYE, Vector3(sx * 0.042, 0.165, -0.146), Vector3.ONE, Vector3.ZERO, 6.0)
	_jaw = _joint(_head, "Jaw", Vector3(0, 0.07, -0.06))
	_part(_jaw, Lowpoly.box(Vector3(0.1, 0.035, 0.08)), C_DARK, Vector3(0, -0.02, -0.03))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.15, 0.08)
	glow.light_energy = 0.4
	glow.omni_range = 0.6  # just the face, no red spot on the ceiling
	glow.position = Vector3(0, 0.12, -0.28)
	_head.add_child(glow)

	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var shoulder := _joint(_chest, "Shoulder%d" % side, Vector3(sx * 0.3, 0.45, 0.0))
		_part(shoulder, Lowpoly.sphere(0.09, 6, 4), C_BONE, Vector3(sx * 0.01, 0.01, 0), Vector3(1.0, 0.9, 1.0))
		_limb(shoulder, UPPER_ARM, 0.06, 0.04)
		var forearm := _joint(shoulder, "Forearm%d" % side, Vector3(0, -UPPER_ARM, 0))
		_part(forearm, Lowpoly.sphere(0.05, 6, 4), C_BONE, Vector3.ZERO, Vector3(1.0, 1.2, 1.0))
		_limb(forearm, FOREARM, 0.048, 0.03)
		var hand := _joint(forearm, "Hand%d" % side, Vector3(0, -FOREARM, 0))
		_part(hand, Lowpoly.box(Vector3(0.09, 0.13, 0.04)), C_SKIN, Vector3(0, -0.06, 0))
		# Four long clawed fingers and a thumb.
		for f in 5:
			var thumb := f == 4
			var fx := sx * (0.05 if thumb else lerpf(-0.03, 0.03, f / 3.0))
			var finger := _joint(hand, "Finger%d" % f, Vector3(fx, -0.05 if thumb else -0.12, -0.02 if thumb else 0.0))
			if thumb:
				finger.rotation.z = sx * 0.6
			var l1 := 0.08 if thumb else 0.13
			_limb(finger, l1, 0.013, 0.01)
			var tip := _joint(finger, "Tip", Vector3(0, -l1, 0))
			tip.rotation.x = 0.5
			_part(tip, Lowpoly.cylinder(0.0, 0.12, 4, 0.01), C_DARK, Vector3(0, -0.06, 0))
			_fingers.append(finger)
		_shoulder.append(shoulder)
		_forearm.append(forearm)
		_hand.append(hand)


# --- animation --------------------------------------------------------------

func _animate(delta: float) -> void:
	_time += delta
	var k := minf(delta * 7.0, 1.0)
	_walk_w = lerpf(_walk_w, clampf(move_speed / 0.8, 0.0, 1.0), k)
	_run_w = lerpf(_run_w, clampf((move_speed - 2.2) / 1.8, 0.0, 1.0), k)
	_look_w = _blend(_look_w, Pose.LOOK, 6.0, delta)
	_alert_w = _blend(_alert_w, Pose.ALERT, 12.0, delta)
	_roar_w = _blend(_roar_w, Pose.ROAR, 6.0, delta)
	_attack_w = _blend(_attack_w, Pose.ATTACK, 12.0, delta)
	_update_twitch(delta)

	# Gait: one cycle = two steps; step length grows with speed (long, loping strides).
	var prev := _phase
	if move_speed > 0.05:
		var step_len := 0.8 + 0.18 * move_speed
		_phase = fmod(_phase + move_speed * delta / (2.0 * step_len), 1.0)
	_emit_steps(prev, _phase)

	var s := sin(TAU * _phase)
	var c := cos(TAU * _phase)
	var walk := _walk_w
	var run := _run_w
	var breath := sin(_time * 1.7)

	# Legs (index 0 = left, 1 = right; the right leg is half a cycle behind).
	var thigh_amp := lerpf(0.42, 0.78, run) * walk
	var knee_amp := lerpf(0.65, 1.35, run) * walk
	# Slightly bent knees even standing: a predator's crouch.
	var thigh_x := [0.1 + s * thigh_amp, 0.1 - s * thigh_amp]
	var knee_x := [-(0.24 + maxf(c, 0.0) * knee_amp), -(0.24 + maxf(-c, 0.0) * knee_amp)]
	# Hunched spine, head pushed forward.
	var spine_x := -0.18 - 0.12 * run - 0.02 * breath
	var spine_y := s * 0.1 * walk
	var chest_x := -0.1 - 0.06 * run
	var neck_x := 0.2 + 0.1 * run
	var head_x := 0.0
	var head_z := 0.0
	var jaw_x := 0.05 + 0.03 * breath
	var arm_amp := lerpf(0.28, 0.75, run) * walk
	var shoulder_x := [-s * arm_amp + 0.08, s * arm_amp + 0.08]
	var shoulder_z := [-(0.1 + 0.25 * run), 0.1 + 0.25 * run]
	var elbow_x := [0.25 + 0.55 * run + maxf(-s, 0.0) * 0.3 * walk, 0.25 + 0.55 * run + maxf(s, 0.0) * 0.3 * walk]
	var curl := 0.55
	var spread := 0.0

	# Looking around: head and chest follow head_yaw (the owner turns the body too).
	var yaw := head_yaw
	var spine_twist := yaw * 0.3 * _look_w
	head_x += -0.12 * _look_w

	# Alert: snaps to face the player, hunches forward, arms spread with claws open, head tilted.
	var a := _alert_w
	if a > 0.001:
		var tremble := sin(_time * 38.0) * 0.03
		spine_x = lerpf(spine_x, -0.42, a)
		chest_x = lerpf(chest_x, -0.14, a)
		neck_x = lerpf(neck_x, 0.55 + tremble, a)
		head_z = lerpf(head_z, 0.4, a)
		jaw_x = lerpf(jaw_x, 0.45, a)
		for i in 2:
			thigh_x[i] = lerpf(thigh_x[i], 0.4, a)
			knee_x[i] = lerpf(knee_x[i], -0.75, a)
			shoulder_x[i] = lerpf(shoulder_x[i], 0.8 + tremble, a)
			shoulder_z[i] = lerpf(shoulder_z[i], (0.42 if i == 1 else -0.42), a)
			elbow_x[i] = lerpf(elbow_x[i], 1.0, a)
		curl = lerpf(curl, 0.1, a)
		spread = lerpf(spread, 0.35, a)

	# Roar (hunt start): leans back, head thrown up, jaw wide, arms out, whole body shaking.
	var r := _roar_w
	if r > 0.001:
		var shake := sin(_time * 31.0) * 0.04
		spine_x = lerpf(spine_x, 0.18 + shake, r)
		chest_x = lerpf(chest_x, 0.12, r)
		neck_x = lerpf(neck_x, -0.35, r)
		head_x = lerpf(head_x, -0.5 + shake, r)
		jaw_x = lerpf(jaw_x, 0.8, r)
		for i in 2:
			shoulder_x[i] = lerpf(shoulder_x[i], 0.25, r)
			shoulder_z[i] = lerpf(shoulder_z[i], (1.0 if i == 1 else -1.0) + shake, r)
			elbow_x[i] = lerpf(elbow_x[i], 0.35, r)
		curl = lerpf(curl, 0.05, r)
		spread = lerpf(spread, 0.4, r)

	# Attack: lunges forward with both arms reaching out.
	var t := _attack_w
	if t > 0.001:
		spine_x = lerpf(spine_x, -0.5, t)
		neck_x = lerpf(neck_x, 0.5, t)
		jaw_x = lerpf(jaw_x, 0.7, t)
		for i in 2:
			shoulder_x[i] = lerpf(shoulder_x[i], 1.4, t)
			shoulder_z[i] = lerpf(shoulder_z[i], (0.25 if i == 1 else -0.25), t)
			elbow_x[i] = lerpf(elbow_x[i], 0.2, t)
		curl = lerpf(curl, 0.2, t)
		spread = lerpf(spread, 0.3, t)

	# Apply.
	for i in 2:
		_thigh[i].rotation = Vector3(thigh_x[i], 0, 0)
		_shin[i].rotation = Vector3(knee_x[i], 0, 0)
		_foot[i].rotation = Vector3(-(thigh_x[i] + knee_x[i]) * 0.8, 0, 0)
		_shoulder[i].rotation = Vector3(shoulder_x[i], 0, shoulder_z[i])
		_forearm[i].rotation = Vector3(elbow_x[i], 0, 0)
		_hand[i].rotation = Vector3(0.15, 0, 0)
	for f in _fingers.size():
		var idx := f % 5
		var sx := -1.0 if f < 5 else 1.0
		var base_z := sx * 0.6 if idx == 4 else sx * (idx - 1.5) * spread * 0.4
		_fingers[f].rotation = Vector3(curl, 0, base_z)
	_hips.rotation = Vector3(0, -spine_y * 0.6, s * 0.03 * walk)
	_spine.rotation = Vector3(spine_x, spine_y + spine_twist, 0)
	_chest.rotation = Vector3(chest_x + 0.015 * breath, 0, 0)
	_neck.rotation = Vector3(neck_x, yaw * 0.35, 0)
	_head.rotation = Vector3(head_x + _twitch.x, yaw * 0.65 - spine_twist + _twitch.y, head_z + _twitch.z)
	_jaw.rotation = Vector3(jaw_x, 0, 0)
	# Keep the stance foot on the floor: the hips sit on whichever leg reaches lower.
	var reach := maxf(_leg_reach(thigh_x[0], knee_x[0]), _leg_reach(thigh_x[1], knee_x[1]))
	_hips.position.y = reach + ANKLE


func _blend(weight: float, p: Pose, rate: float, delta: float) -> float:
	return lerpf(weight, 1.0 if pose == p else 0.0, minf(delta * rate, 1.0))


func _leg_reach(thigh_x: float, knee_x: float) -> float:
	return THIGH * cos(thigh_x) + SHIN * cos(thigh_x + knee_x)


## Footstep at each heel strike: left foot at phase 0.25, right foot at 0.75.
func _emit_steps(prev: float, now: float) -> void:
	if move_speed < 0.3 or _walk_w < 0.5:
		return
	for mark: float in [0.25, 0.75]:
		var crossed := (prev < mark and now >= mark) or (now < prev and (prev < mark or now >= mark))
		if crossed:
			var foot := _foot[0 if mark < 0.5 else 1]
			footstep.emit(foot.global_position, move_speed)


func _update_twitch(delta: float) -> void:
	# Now and then the head jerks sideways, then settles: unsettling, not quite human.
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(2.5, 6.0)
		_twitch = Vector3(randf_range(-0.15, 0.15), randf_range(-0.3, 0.3), randf_range(-0.45, 0.45))
	_twitch = _twitch.lerp(Vector3.ZERO, minf(delta * 3.0, 1.0))
