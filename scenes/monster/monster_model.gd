class_name MonsterModel
extends Node3D
## Lowpoly 2.5 m monster after docs/reference/monster_concept.jpg: an emaciated, hunched humanoid
## with a ribbed chest, long arms reaching the knees, clawed fingers and a dark red face with
## glowing eyes. Built from primitives on a joint hierarchy and animated procedurally, so the walk
## cycle always matches the real speed and footsteps land on cue.
##
## It is old ("first seen: 1897") and damaged, and nothing on it is symmetric: the primitives are
## roughened into uneven shapes, an aged-skin shader adds grime, scuffs and dried blood, the right
## shoulder is dislocated and its forearm broken (a bone shard sticks out, the arm is kinked and
## longer), ribs are cracked, a finger and a toe are missing, the jaw hangs crooked with missing
## teeth, the skull is cracked, a rusty shackle with a broken chain hangs on the left ankle, a nail
## sticks out of the right shoulder and rags hang from the hips. It "malfunctions" too: the right
## eye flickers, the broken arm spasms and now and then the whole body stutters for a moment.
##
## The owner (Monster) drives it every physics frame through `move_speed`, `pose` and
## `head_yaw`; the model emits `footstep` exactly when a foot plants.

signal footstep(position: Vector3, speed: float)

enum Pose { NORMAL, LOOK, ALERT, ROAR, ATTACK }

const HIP_Y := 1.25
const THIGH := 0.6
const SHIN := 0.59
const ANKLE := 0.06
const HIP_JOINT := 0.08
const UPPER_ARM := 0.55
const FOREARM: Array[float] = [0.52, 0.58]  ## [left, right]: the broken right one is longer

const C_SKIN := Color("221f21")
const C_BONE := Color("3f3b35")
const C_DARK := Color("121012")
const C_FACE := Color("220606")
const C_EYE := Color("ff1a0d")
const C_TEETH := Color("6f6656")
const C_RAG := Color("2b241e")
const C_RUST := Color("4a2b1a")
const C_WOUND := Color("2e0907")
const SKIN_SHADER := preload("res://shaders/monster_skin.gdshader")

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
var _stutter_timer: float = 4.0
var _stutter: float = 0.0  # > 0: the pose is frozen (a "skipped frame")
var _spasm_timer: float = 2.0
var _spasm: float = 0.0
var _flicker_timer: float = 1.0

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
var _finger_rest: Array[Vector3] = []  # per finger: x = extra curl, z = splay (broken ones stick out)
var _rags: Array[Node3D] = []
var _chain: Node3D
var _bad_eye: StandardMaterial3D
var _mats: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1897  # the same scars on every run
	_build()
	_animate(0.0)


func _physics_process(delta: float) -> void:
	_animate(delta)


# --- construction -----------------------------------------------------------

## Aged-skin material (grime, scuffs, dried blood); shared per colour.
func _mat(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SKIN_SHADER
	m.set_shader_parameter(&"albedo", color)
	_mats[key] = m
	return m


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _joint(parent: Node3D, n: String, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	j.rotation = rot
	parent.add_child(j)
	return j


## A roughened primitive (uneven, organic) with the aged material.
func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scale_: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO, rough: float = 0.012) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _rough(mesh, rough) if rough > 0.0 else mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale_
	parent.add_child(mi)
	return mi


## Tapered limb hanging down (-Y) from a joint: radius r_near at the joint, r_far at the end.
func _limb(parent: Node3D, length: float, r_near: float, r_far: float, color: Color = C_SKIN) -> MeshInstance3D:
	return _part(parent, Lowpoly.cylinder(r_far, length, 6, r_near), color, Vector3(0, -length * 0.5, 0), Vector3.ONE, Vector3.ZERO, r_near * 0.18)


## A thin straight piece (bone, tendon, rib segment) from a to b in the parent's space.
func _strut(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mi := _part(parent, Lowpoly.cylinder(radius, 1.0, 5), color, (a + b) * 0.5, Vector3.ONE, Vector3.ZERO, 0.0)
	var dir := b - a
	var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI * 0.5)  # cylinder Y -> along dir
	mi.basis = basis.scaled_local(Vector3(1.0, dir.length(), 1.0))
	return mi


## Displaces every vertex by a hash of its position: shared corners move together, so the
## flat-shaded mesh stays closed but loses its perfect primitive shape.
func _rough(mesh: Mesh, amount: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var orig: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var n := PackedVector3Array()
	n.resize(v.size())
	var seed_ := Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * 10.0
	for i in v.size():
		v[i] += _hash3(v[i] + seed_) * amount
	for i in range(0, v.size(), 3):
		var nn := (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).normalized()
		if nn.dot(orig[i]) < 0.0:  # keep the original outward orientation
			nn = -nn
		n[i] = nn
		n[i + 1] = nn
		n[i + 2] = nn
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _hash3(p: Vector3) -> Vector3:
	var h := Vector3(
		sin(p.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453,
		sin(p.dot(Vector3(39.3468, 11.1351, 83.1559))) * 24634.6345,
		sin(p.dot(Vector3(73.1563, 52.2351, 9.1514))) * 56445.2345)
	return Vector3(h.x - floorf(h.x), h.y - floorf(h.y), h.z - floorf(h.z)) * 2.0 - Vector3.ONE


func _build() -> void:
	_hips = _joint(self, "Hips", Vector3(0, HIP_Y, 0))
	_build_pelvis()
	for side in 2:
		_build_leg(side)
	_build_torso()
	_build_head()
	for side in 2:
		_build_arm(side)


func _build_pelvis() -> void:
	# Blocky wedge wider than the waist, with the hip bones jutting out at the sides.
	_part(_hips, Lowpoly.cylinder(0.16, 0.3, 6, 0.19), C_SKIN, Vector3(0, -0.04, 0), Vector3(1.0, 1.0, 0.68), Vector3.ZERO, 0.02)
	_part(_hips, Lowpoly.cylinder(0.12, 0.05, 6, 0.17), C_BONE.darkened(0.3), Vector3(0, 0.1, 0), Vector3(1.0, 1.0, 0.7))
	for sx: float in [-1.0, 1.0]:
		_part(_hips, Lowpoly.box(Vector3(0.07, 0.09, 0.15)), C_BONE, Vector3(sx * 0.18, 0.06, 0.0), Vector3.ONE, Vector3(0.2, 0, sx * 0.35), 0.015)
	# Rags hanging from the hips: different lengths, torn ends, swaying with the walk.
	for i in 7:
		var a := lerpf(-2.6, 2.6, i / 6.0) + _rng.randf_range(-0.15, 0.15)
		var rag := _joint(_hips, "Rag%d" % i, Vector3(sin(a) * 0.19, -0.14, -cos(a) * 0.13), Vector3(0, -a, 0))
		var length := _rng.randf_range(0.14, 0.4)
		var w := _rng.randf_range(0.05, 0.1)
		_part(rag, Lowpoly.box(Vector3(w, length, 0.012)), C_RAG.darkened(_rng.randf() * 0.3), Vector3(0, -length * 0.5, 0), Vector3.ONE, Vector3(0, 0, _rng.randf_range(-0.1, 0.1)), 0.012)
		if _rng.randf() < 0.6:  # a torn strip dangling off the end
			_part(rag, Lowpoly.box(Vector3(0.02, length * 0.4, 0.008)), C_RAG, Vector3(w * 0.3, -length - length * 0.15, 0), Vector3.ONE, Vector3(0, 0, 0.2), 0.008)
		_rags.append(rag)


func _build_leg(side: int) -> void:
	var sx := -1.0 if side == 0 else 1.0
	var thigh := _joint(_hips, "Thigh%d" % side, Vector3(sx * 0.12, -HIP_JOINT, 0))
	_limb(thigh, THIGH, 0.1, 0.055)
	_strut(thigh, Vector3(sx * 0.03, -0.08, 0.06), Vector3(sx * 0.01, -THIGH + 0.06, 0.05), 0.014, C_SKIN.lightened(0.05))  # hamstring
	var shin := _joint(thigh, "Shin%d" % side, Vector3(0, -THIGH, 0))
	_part(shin, Lowpoly.sphere(0.068, 6, 4), C_BONE, Vector3(0, 0, -0.01), Vector3(1.0, 1.1, 1.2), Vector3.ZERO, 0.015)  # knobbly knee
	_limb(shin, SHIN, 0.06, 0.035)
	_strut(shin, Vector3(0, -0.05, -0.05), Vector3(0, -SHIN + 0.04, -0.03), 0.012, C_BONE)  # shin bone ridge
	_strut(shin, Vector3(0, -0.1, 0.055), Vector3(0, -SHIN + 0.02, 0.04), 0.01, C_SKIN.lightened(0.06))  # achilles
	var foot := _joint(shin, "Foot%d" % side, Vector3(0, -SHIN, 0))
	# Long bony foot: heel, three toes with claws (the right foot lost one), a heel spur.
	_part(foot, Lowpoly.box(Vector3(0.1, 0.05, 0.16)), C_SKIN, Vector3(0, -ANKLE + 0.025, -0.02), Vector3.ONE, Vector3.ZERO, 0.008)
	_part(foot, Lowpoly.cylinder(0.0, 0.07, 4, 0.025), C_BONE, Vector3(0, -ANKLE + 0.03, 0.08), Vector3.ONE, Vector3(PI * 0.5, 0, 0), 0.0)
	for t in 3:
		var tx := sx * lerpf(-0.035, 0.035, t / 2.0)
		if side == 1 and t == 2:
			_part(foot, Lowpoly.sphere(0.018, 5, 3), C_WOUND, Vector3(tx, -ANKLE + 0.02, -0.1))  # stump
			continue
		var toe_len := 0.13 - absf(t - 1.0) * 0.03
		_part(foot, Lowpoly.box(Vector3(0.026, 0.026, toe_len)), C_SKIN, Vector3(tx, -ANKLE + 0.013, -0.1 - toe_len * 0.5), Vector3.ONE, Vector3(0, _rng.randf_range(-0.12, 0.12), 0), 0.005)
		_part(foot, Lowpoly.cylinder(0.012, 0.06, 4, 0.0), C_DARK, Vector3(tx, -ANKLE + 0.012, -0.12 - toe_len), Vector3.ONE, Vector3(-PI * 0.5, 0, 0), 0.0)
	if side == 0:
		# Rusty shackle on the left ankle with a broken chain hanging off it.
		var ring := _joint(shin, "Shackle", Vector3(0, -SHIN + 0.09, 0))
		for i in 8:
			var a := TAU * i / 8.0
			_part(ring, Lowpoly.box(Vector3(0.04, 0.035, 0.016)), C_RUST, Vector3(cos(a) * 0.056, 0, sin(a) * 0.056), Vector3.ONE, Vector3(0, -a + PI * 0.5, 0), 0.004)
		_chain = _joint(ring, "Chain", Vector3(0.0, -0.01, 0.06))
		var link := _chain
		for i in 3:
			link = _joint(link, "Link%d" % i, Vector3(0, -0.045 if i > 0 else 0.0, 0), Vector3(0, PI * 0.5 * (i % 2), 0))
			_part(link, Lowpoly.box(Vector3(0.008, 0.05, 0.026)), C_RUST, Vector3(0, -0.022, 0), Vector3.ONE, Vector3.ZERO, 0.003)
			_part(link, Lowpoly.box(Vector3(0.026, 0.008, 0.008)), C_RUST, Vector3(0, -0.044, 0), Vector3.ONE, Vector3.ZERO, 0.0)
	_thigh.append(thigh)
	_shin.append(shin)
	_foot.append(foot)


func _build_torso() -> void:
	# Waist: a thin spine with vertebrae spikes at the back, an old stitched seam across the belly.
	_spine = _joint(_hips, "Spine", Vector3(0, 0.08, 0))
	_part(_spine, Lowpoly.cylinder(0.075, 0.3, 6, 0.06), C_SKIN, Vector3(0, 0.15, 0.01), Vector3(1.3, 1.0, 0.8), Vector3.ZERO, 0.012)
	for i in 5:
		if i == 2:
			continue  # one is gone
		var s := _rng.randf_range(0.02, 0.035)
		_part(_spine, Lowpoly.cylinder(s, s * 2.2, 4, 0.0), C_BONE, Vector3(0, 0.03 + i * 0.06, 0.07), Vector3.ONE, Vector3(PI * 0.5 - 0.3, 0, 0), 0.0)
	_strut(_spine, Vector3(-0.075, 0.07, -0.06), Vector3(0.02, 0.26, -0.065), 0.006, C_WOUND)
	for i in 5:
		var p := Vector3(-0.07 + i * 0.022, 0.08 + i * 0.04, -0.064)
		_part(_spine, Lowpoly.box(Vector3(0.024, 0.004, 0.006)), C_TEETH, p, Vector3.ONE, Vector3(0, 0, 0.9), 0.0)
		_part(_spine, Lowpoly.box(Vector3(0.024, 0.004, 0.006)), C_TEETH, p, Vector3.ONE, Vector3(0, 0, -0.5), 0.0)
	# Skin flaps peeling off the belly.
	for sx: float in [-1.0, 0.6]:
		_part(_spine, Lowpoly.box(Vector3(0.04, 0.12, 0.008)), C_SKIN.lightened(0.04), Vector3(sx * 0.06, 0.03, -0.07), Vector3.ONE, Vector3(-0.15, 0, sx * 0.25), 0.01)

	# Ribcage: a dark core wrapped in rib arcs sloping down to the front; some are cracked.
	_chest = _joint(_spine, "Chest", Vector3(0, 0.28, 0))
	_part(_chest, Lowpoly.cylinder(0.12, 0.5, 7, 0.16), C_DARK, Vector3(0, 0.25, 0.01), Vector3(1.25, 1.0, 0.8), Vector3.ZERO, 0.015)
	for i in 6:
		var r := lerpf(0.155, 0.235, float(i) / 5.0)
		var y := 0.1 + i * 0.065 + _rng.randf_range(-0.008, 0.008)
		var c := C_BONE if i < 4 else C_BONE.lerp(C_FACE, 0.45)
		for sx: float in [-1.0, 1.0]:
			_rib(r * 1.18, r * 0.74, y, sx, c, i)
	# Sloping trapezius, collarbones, shoulder blades (the left one sticks out more), sternum.
	for sx: float in [-1.0, 1.0]:
		var left := sx < 0.0
		_part(_chest, Lowpoly.box(Vector3(0.24, 0.07, 0.15)), C_SKIN, Vector3(sx * 0.13, 0.5 + (0.015 if left else -0.02), 0.01), Vector3.ONE, Vector3(0, 0, -sx * 0.35), 0.015)
		_strut(_chest, Vector3(sx * 0.03, 0.47, -0.12), Vector3(sx * 0.27, 0.46 + (0.0 if left else -0.04), -0.03), 0.014, C_BONE)
		_part(_chest, Lowpoly.box(Vector3(0.12, 0.17, 0.025)), C_BONE.darkened(0.15), Vector3(sx * 0.12, 0.36, 0.14), Vector3.ONE, Vector3(0.15, sx * (0.45 if left else 0.2), 0), 0.012)
	_part(_chest, Lowpoly.box(Vector3(0.05, 0.36, 0.05)), C_BONE, Vector3(0, 0.27, -0.155), Vector3.ONE, Vector3.ZERO, 0.01)
	for i in 5:
		var s := _rng.randf_range(0.02, 0.03)
		_part(_chest, Lowpoly.cylinder(s, s * 2.0, 4, 0.0), C_BONE, Vector3(0.0, 0.08 + i * 0.09, 0.13), Vector3.ONE, Vector3(PI * 0.5 - 0.4, 0, 0), 0.0)
	# A dark wound under the right ribs.
	_part(_chest, Lowpoly.sphere(0.045, 6, 4), C_WOUND, Vector3(0.12, 0.1, -0.1), Vector3(1.0, 1.4, 0.4), Vector3(0, 0.5, 0.3), 0.01)


## One side of a rib, from the spine round to near the sternum. a, b: half-axes of the ellipse.
func _rib(a: float, b: float, y: float, sx: float, color: Color, index: int) -> void:
	const SEGMENTS := 7
	var right := sx > 0.0
	var points: Array[Vector3] = []
	for k in SEGMENTS + 1:
		var t := lerpf(0.3, PI - 0.38, float(k) / SEGMENTS)
		points.append(Vector3(sx * a * sin(t), y - 0.05 * (t / PI), b * cos(t)))
	for k in SEGMENTS:
		if right and index == 3 and (k == 4 or k == 5):
			continue  # a snapped rib...
		if not right and index == 1 and k >= 5:
			continue  # ...and one broken off short
		var p0 := points[k]
		var p1 := points[k + 1]
		if right and index == 3 and k == 6:
			p0 += Vector3(sx * 0.02, -0.02, -0.01)  # the loose end sags
		_strut(_chest, p0, p1, 0.014, color)


func _build_head() -> void:
	_neck = _joint(_chest, "Neck", Vector3(0, 0.52, -0.04))
	_part(_neck, Lowpoly.cylinder(0.05, 0.16, 6, 0.045), C_SKIN, Vector3(0, 0.07, 0), Vector3.ONE, Vector3.ZERO, 0.01)
	_strut(_neck, Vector3(-0.03, 0.0, -0.03), Vector3(-0.02, 0.15, -0.04), 0.01, C_BONE)  # neck tendons
	_strut(_neck, Vector3(0.035, 0.0, -0.025), Vector3(0.022, 0.15, -0.035), 0.011, C_BONE)
	_head = _joint(_neck, "Head", Vector3(0, 0.13, -0.01))
	# Lopsided skull: a bulge over the left temple, a crack across the crown, one ear stub.
	_part(_head, Lowpoly.sphere(0.16, 8, 5), C_SKIN, Vector3(0, 0.16, 0.03), Vector3(0.95, 1.15, 1.0), Vector3.ZERO, 0.014)
	_part(_head, Lowpoly.sphere(0.08, 6, 4), C_SKIN, Vector3(-0.075, 0.23, 0.05), Vector3(0.9, 1.1, 1.0), Vector3.ZERO, 0.012)
	_part(_head, Lowpoly.box(Vector3(0.01, 0.01, 0.1)), C_WOUND.darkened(0.3), Vector3(0.03, 0.33, 0.05), Vector3.ONE, Vector3(-0.15, 0.35, 0.1), 0.0)
	_part(_head, Lowpoly.box(Vector3(0.009, 0.009, 0.06)), C_WOUND.darkened(0.3), Vector3(0.085, 0.31, 0.0), Vector3.ONE, Vector3(0.6, -0.4, 0.5), 0.0)
	_part(_head, Lowpoly.box(Vector3(0.03, 0.06, 0.035)), C_SKIN, Vector3(0.15, 0.15, 0.05), Vector3.ONE, Vector3(0, 0, -0.2), 0.008)
	# Dark red face set into the skull, with concentric rings around the eyes.
	_part(_head, Lowpoly.sphere(0.1, 8, 5), C_FACE, Vector3(0, 0.15, -0.1), Vector3(1.0, 1.15, 0.42), Vector3.ZERO, 0.006)
	var ring_mat := _glow(C_FACE.lightened(0.12), 0.4)
	_bad_eye = _glow(C_EYE, 6.0)
	for sx: float in [-1.0, 1.0]:
		var left := sx < 0.0
		var ring := MeshInstance3D.new()
		ring.mesh = Lowpoly.cylinder(0.04, 0.01, 8)
		ring.material_override = ring_mat
		ring.position = Vector3(sx * 0.042, 0.165, -0.138)
		ring.rotation = Vector3(PI / 2, 0, 0)
		_head.add_child(ring)
		var eye := MeshInstance3D.new()
		eye.mesh = Lowpoly.sphere(0.018 if left else 0.015, 6, 4)
		eye.material_override = _glow(C_EYE, 6.0) if left else _bad_eye  # the right one is failing
		eye.position = Vector3(sx * 0.042, 0.165 if left else 0.159, -0.146)
		_head.add_child(eye)
	# Crooked jaw with a broken row of teeth.
	_jaw = _joint(_head, "Jaw", Vector3(0, 0.07, -0.06))
	_part(_jaw, Lowpoly.box(Vector3(0.1, 0.035, 0.08)), C_DARK, Vector3(0, -0.02, -0.03), Vector3.ONE, Vector3.ZERO, 0.006)
	for i in 6:
		if i == 1 or i == 4:
			continue
		var tx := lerpf(-0.04, 0.04, i / 5.0)
		_part(_jaw, Lowpoly.cylinder(0.006, 0.018 + _rng.randf() * 0.01, 4, 0.0), C_TEETH.darkened(0.3), Vector3(tx, 0.0, -0.062), Vector3.ONE, Vector3(0, 0, _rng.randf_range(-0.25, 0.25)), 0.0)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.15, 0.08)
	glow.light_energy = 0.25
	glow.omni_range = 0.45  # just the face, no red spot on the ceiling
	glow.position = Vector3(0, 0.08, -0.28)
	_head.add_child(glow)


func _build_arm(side: int) -> void:
	var sx := -1.0 if side == 0 else 1.0
	var right := side == 1
	# The right shoulder is dislocated: lower and pushed forward.
	var shoulder := _joint(_chest, "Shoulder%d" % side, Vector3(sx * 0.3, 0.4 if right else 0.46, -0.03 if right else 0.0))
	_part(shoulder, Lowpoly.sphere(0.09, 6, 4), C_BONE, Vector3(sx * 0.01, 0.01, 0), Vector3(1.0, 0.9, 1.0), Vector3.ZERO, 0.015)
	_limb(shoulder, UPPER_ARM, 0.06, 0.04)
	_strut(shoulder, Vector3(sx * 0.02, -0.06, -0.045), Vector3(sx * 0.01, -UPPER_ARM + 0.06, -0.03), 0.013, C_SKIN.lightened(0.05))  # biceps tendon
	if right:
		# A rusty nail driven into the shoulder.
		_part(shoulder, Lowpoly.cylinder(0.006, 0.14, 4), C_RUST, Vector3(0.06, 0.02, -0.04), Vector3.ONE, Vector3(0.6, 0, -1.0), 0.0)
		_part(shoulder, Lowpoly.cylinder(0.016, 0.006, 6), C_RUST, Vector3(0.115, 0.06, -0.075), Vector3.ONE, Vector3(0.6, 0, -1.0), 0.0)
	else:
		# Old stitches on the left upper arm.
		for i in 4:
			_part(shoulder, Lowpoly.box(Vector3(0.004, 0.026, 0.006)), C_TEETH, Vector3(-0.045, -0.15 - i * 0.04, -0.03), Vector3.ONE, Vector3(0, 0, 1.2), 0.0)
	var forearm := _joint(shoulder, "Forearm%d" % side, Vector3(0, -UPPER_ARM, 0))
	_part(forearm, Lowpoly.sphere(0.05, 6, 4), C_BONE, Vector3.ZERO, Vector3(1.0, 1.2, 1.0), Vector3.ZERO, 0.012)
	var length: float = FOREARM[side]
	var wrist: Node3D
	if right:
		# Broken forearm: kinked halfway, with a bone shard through the skin.
		_limb(forearm, length * 0.5, 0.048, 0.04)
		var kink := _joint(forearm, "Kink", Vector3(0, -length * 0.5, 0), Vector3(0.22, 0, -0.12))
		_part(kink, Lowpoly.sphere(0.042, 6, 4), C_WOUND, Vector3.ZERO, Vector3(1.1, 0.8, 1.1), Vector3.ZERO, 0.01)
		_limb(kink, length * 0.5, 0.042, 0.03)
		_part(forearm, Lowpoly.cylinder(0.016, 0.11, 4, 0.0), C_TEETH, Vector3(0.03, -length * 0.45, 0.03), Vector3.ONE, Vector3(0.5, 0, -0.9), 0.0)
		wrist = _joint(kink, "Wrist", Vector3(0, -length * 0.5, 0))
	else:
		_limb(forearm, length, 0.048, 0.03)
		wrist = _joint(forearm, "Wrist", Vector3(0, -length, 0))
	_strut(forearm, Vector3(sx * 0.03, -0.05, 0.02), Vector3(sx * 0.02, -length * 0.45, 0.025), 0.009, C_SKIN.lightened(0.07))
	var hand := _joint(wrist, "Hand%d" % side, Vector3.ZERO)
	_part(hand, Lowpoly.box(Vector3(0.09, 0.13, 0.04)), C_SKIN, Vector3(0, -0.06, 0), Vector3.ONE, Vector3.ZERO, 0.01)
	# Four long clawed fingers and a thumb; the left hand lost its ring finger and has a snapped
	# claw, one of the right fingers is broken and sticks out backwards.
	for f in 5:
		var thumb := f == 4
		var fx := sx * (0.05 if thumb else lerpf(-0.03, 0.03, f / 3.0))
		var finger := _joint(hand, "Finger%d" % f, Vector3(fx, -0.05 if thumb else -0.12, -0.02 if thumb else 0.0))
		_part(finger, Lowpoly.sphere(0.016, 5, 3), C_BONE, Vector3.ZERO, Vector3.ONE, Vector3.ZERO, 0.0)  # knuckle
		_fingers.append(finger)
		if not right and f == 2:
			_part(finger, Lowpoly.sphere(0.014, 5, 3), C_WOUND, Vector3(0, -0.012, 0))  # stump
			_finger_rest.append(Vector3.ZERO)
			continue
		_finger_rest.append(Vector3(-0.6, 0, -sx * 0.9) if right and f == 1 else Vector3.ZERO)
		var l1 := (0.08 if thumb else 0.13) * _rng.randf_range(0.9, 1.1)
		_limb(finger, l1, 0.013, 0.01)
		var tip := _joint(finger, "Tip", Vector3(0, -l1, 0))
		tip.rotation.x = 0.5 + _rng.randf_range(-0.15, 0.15)
		var claw := 0.12 * _rng.randf_range(0.7, 1.15)
		if not right and f == 0:
			claw *= 0.45
		_part(tip, Lowpoly.cylinder(0.0, claw, 4, 0.01), C_DARK, Vector3(0, -claw * 0.5, 0), Vector3.ONE, Vector3.ZERO, 0.0)
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
	_update_faults(delta)

	# Gait: one cycle = two steps; step length grows with speed (long, loping strides).
	var prev := _phase
	if move_speed > 0.05:
		var step_len := 0.8 + 0.18 * move_speed
		_phase = fmod(_phase + move_speed * delta / (2.0 * step_len), 1.0)
	_emit_steps(prev, _phase)
	if _stutter > 0.0:
		return  # a skipped frame: the pose holds while the body keeps moving

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
	# Hunched spine, head pushed forward and a little crooked.
	var spine_x := -0.18 - 0.12 * run - 0.02 * breath
	var spine_y := s * 0.1 * walk
	var chest_x := -0.1 - 0.06 * run
	var neck_x := 0.2 + 0.1 * run
	var head_x := 0.0
	var head_z := 0.08
	var jaw_x := 0.05 + 0.03 * breath
	var arm_amp := lerpf(0.28, 0.75, run) * walk
	# The broken right arm swings less and hangs closer to the body.
	var shoulder_x := [-s * arm_amp + 0.08, s * arm_amp * 0.6 + 0.02]
	var shoulder_z := [-(0.1 + 0.25 * run), 0.04 + 0.2 * run]
	var elbow_x := [0.25 + 0.55 * run + maxf(-s, 0.0) * 0.3 * walk, 0.12 + 0.4 * run + maxf(s, 0.0) * 0.2 * walk]
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

	# The broken arm spasms now and then.
	elbow_x[1] += _spasm * 0.7
	shoulder_z[1] += _spasm * 0.25

	# Apply.
	for i in 2:
		_thigh[i].rotation = Vector3(thigh_x[i], 0, 0)
		_shin[i].rotation = Vector3(knee_x[i], 0, 0)
		_foot[i].rotation = Vector3(-(thigh_x[i] + knee_x[i]), 0, 0)  # soles stay level with the floor
		_shoulder[i].rotation = Vector3(shoulder_x[i], 0, shoulder_z[i])
		_forearm[i].rotation = Vector3(elbow_x[i], 0, 0)
	_hand[0].rotation = Vector3(0.15, 0, 0)
	_hand[1].rotation = Vector3(0.5, 0, 0.2 * _spasm)  # limp right wrist
	for f in _fingers.size():
		var idx := f % 5
		var sx := -1.0 if f < 5 else 1.0
		var base_z := sx * 0.6 if idx == 4 else sx * (idx - 1.5) * spread * 0.4
		var rest := _finger_rest[f]
		_fingers[f].rotation = Vector3(curl + rest.x, 0, base_z + rest.z)
	_hips.rotation = Vector3(0, -spine_y * 0.6, s * 0.03 * walk)
	_spine.rotation = Vector3(spine_x, spine_y + spine_twist, 0.03)  # lists slightly to the right
	_chest.rotation = Vector3(chest_x + 0.015 * breath, 0, 0)
	_neck.rotation = Vector3(neck_x, yaw * 0.35, 0)
	_head.rotation = Vector3(head_x + _twitch.x, yaw * 0.65 - spine_twist + _twitch.y, head_z + _twitch.z)
	_jaw.rotation = Vector3(jaw_x, 0, 0.12)  # hangs crooked
	# Rags trail behind and flap with the stride; the chain swings from the shackle.
	for i in _rags.size():
		var flap := sin(_time * (3.0 + run * 5.0) + i * 1.3) * (0.06 + 0.25 * walk)
		_rags[i].rotation.x = 0.15 * walk + 0.25 * run + flap
	if _chain:
		var leg_pitch: float = thigh_x[0] + knee_x[0]
		_chain.rotation = Vector3(-leg_pitch + 0.25 * walk * c, 0, 0.15 * sin(_time * 4.0) * walk)
	# Keep the stance foot on the floor: the hips sit on whichever leg reaches lower (the hip
	# joints hang HIP_JOINT below the hips' origin, the sole is ANKLE below the ankle).
	var reach := maxf(_leg_reach(thigh_x[0], knee_x[0]), _leg_reach(thigh_x[1], knee_x[1]))
	_hips.position.y = reach + HIP_JOINT + ANKLE


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


## Malfunctions: the body stutters (the pose freezes for a few frames), the broken arm spasms,
## the right eye flickers.
func _update_faults(delta: float) -> void:
	_stutter = maxf(_stutter - delta, 0.0)
	_stutter_timer -= delta
	if _stutter_timer <= 0.0:
		_stutter_timer = randf_range(3.0, 8.0)
		if pose != Pose.ATTACK:
			_stutter = randf_range(0.06, 0.14)
	_spasm_timer -= delta
	if _spasm_timer <= 0.0:
		_spasm_timer = randf_range(1.5, 5.0)
		_spasm = randf_range(0.6, 1.0) * (1.0 if randf() < 0.5 else -0.6)
	_spasm = lerpf(_spasm, 0.0, minf(delta * 5.0, 1.0))
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(0.04, 0.12) if randf() < 0.75 else randf_range(0.6, 2.5)
		_bad_eye.emission_energy_multiplier = randf_range(0.0, 1.5) if randf() < 0.35 else randf_range(3.5, 6.0)
