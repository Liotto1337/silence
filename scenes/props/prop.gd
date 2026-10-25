class_name Prop
extends RigidBody3D
## A physics object the player can carry with the grab button (Source-engine style).
## Hard impacts make a thud that the monster can hear.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_MONSTER := 4
const LAYER_PROPS := 8
const LAYER_PICKUPS := 16
const IMPACT_SPEED := 2.4

@export var display_name: String = "Предмет"
@export var makes_impact_noise: bool = true

var held: bool = false
var _prev_velocity: Vector3 = Vector3.ZERO
var _noise_cooldown: float = 0.5  # ignore the settle-in contact right after spawning


func _init() -> void:
	collision_layer = LAYER_PROPS
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_MONSTER | LAYER_PROPS
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


func _on_body_entered(_body: Node) -> void:
	if held or _noise_cooldown > 0.0:
		return
	var speed := _prev_velocity.length()
	if speed < IMPACT_SPEED:
		return
	_noise_cooldown = 0.35
	_on_impact(speed)


func _on_impact(speed: float) -> void:
	if not makes_impact_noise:
		return
	var radius := remap(clampf(speed, IMPACT_SPEED, 9.0), IMPACT_SPEED, 9.0, NoiseBus.IMPACT_MIN, NoiseBus.IMPACT_MAX)
	Sfx.play_3d(Sfx.THUD, global_position, linear_to_db(clampf(speed / 6.0, 0.3, 1.2)), 25.0, randf_range(0.85, 1.2))
	NoiseBus.emit_noise(global_position, radius, self)


# --- construction helpers used by the factories in subclasses ---

func add_box(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO, collide: bool = true) -> void:
	Lowpoly.add_mesh(self, Lowpoly.box(size), color, pos)
	if collide:
		Lowpoly.add_box_shape(self, size, pos)


func add_visual(mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, emission: float = 0.0) -> void:
	Lowpoly.add_mesh(self, mesh, color, pos, rot, emission)


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
