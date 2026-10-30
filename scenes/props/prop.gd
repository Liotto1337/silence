class_name Prop
extends RigidBody3D
## A physics object the player can carry with the grab button (Source-engine style).
## Hard impacts make a sound that the monster can hear; gentle set-downs only a quiet one.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_MONSTER := 4
const LAYER_PROPS := 8
const LAYER_PICKUPS := 16
const LAYER_DOORS := 32  ## room doors: solid, but left out of the navmesh (the monster opens them)
const IMPACT_SPEED := 2.4
const PLACE_SPEED := 0.6

@export var display_name: String = "Предмет"
@export var makes_impact_noise: bool = true
## Sounds of a hard hit (a thud when empty) and of being put down (silent when empty).
var impact_sounds: Array[AudioStream] = []
var place_sounds: Array[AudioStream] = []

var held: bool = false
var _prev_velocity: Vector3 = Vector3.ZERO
var _noise_cooldown: float = 0.5  # ignore the settle-in contact right after spawning


func _init() -> void:
	collision_layer = LAYER_PROPS
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_MONSTER | LAYER_PROPS | LAYER_DOORS
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	add_to_group(&"grabbable")


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_noise_cooldown = maxf(_noise_cooldown - delta, 0.0)
	_prev_velocity = linear_velocity


## Called by the player when this prop is picked up / released.
func set_held(value: bool) -> void:
	held = value


func get_grab_prompt() -> String:
	return display_name


## Called by the player right after throwing this prop.
func on_thrown() -> void:
	pass


func _on_body_entered(_body: Node) -> void:
	if held or _noise_cooldown > 0.0:
		return
	var speed := _prev_velocity.length()
	if speed >= IMPACT_SPEED:
		_noise_cooldown = 0.35
		_on_impact(speed)
	elif speed >= PLACE_SPEED:
		_noise_cooldown = 0.25
		_on_place(speed)


func _on_impact(speed: float) -> void:
	if not makes_impact_noise:
		return
	var volume := linear_to_db(clampf(speed / 6.0, 0.3, 1.2))
	if impact_sounds.is_empty():
		Sfx.play_3d(Sfx.THUD, global_position, volume, 25.0, randf_range(0.85, 1.2))
	else:
		Sfx.play_3d(impact_sounds.pick_random(), global_position, volume, 25.0, randf_range(0.94, 1.06))
	NoiseBus.emit_noise(global_position, impact_noise_radius(speed), self)


## Put down gently: a quiet sound only the player hears (no noise for the monster).
func _on_place(speed: float) -> void:
	if place_sounds.is_empty():
		return
	var volume := remap(speed, PLACE_SPEED, IMPACT_SPEED, -20.0, -9.0)
	Sfx.play_3d(place_sounds.pick_random(), global_position, volume, 10.0, randf_range(0.94, 1.06))


static func impact_noise_radius(speed: float) -> float:
	return remap(clampf(speed, IMPACT_SPEED, 9.0), IMPACT_SPEED, 9.0, NoiseBus.IMPACT_MIN, NoiseBus.IMPACT_MAX)


# --- construction helpers used by the factories in subclasses ---

## Visual from a model (see Models), its bottom centre at `pos`.
func add_model(id: String, size: Vector3, pos: Vector3 = Vector3.ZERO, yaw: float = 0.0, tint: Color = Color.WHITE) -> MeshInstance3D:
	return Models.add(self, id, size, pos, yaw, "", "", tint)


func add_box_shape(size: Vector3, pos: Vector3 = Vector3.ZERO) -> void:
	Lowpoly.add_box_shape(self, size, pos)


func add_sphere_shape(radius: float, pos: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	cs.position = pos
	add_child(cs)


func add_cylinder_shape(radius: float, height: float, pos: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	cs.shape = s
	cs.position = pos
	add_child(cs)


## Area that fires when the player walks over the prop.
func add_step_trigger(radius: float, callback: Callable) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = LAYER_PLAYER
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = 0.5
	cs.shape = s
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(func(body: Node3D) -> void:
		if not held and body is Player:
			callback.call(body))
