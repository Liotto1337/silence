class_name Player
extends CharacterBody3D
## First-person player: movement with stamina, crouch, Source-style carrying, interaction,
## flashlight with batteries and a two-slot inventory (flashlight + key).

signal grabbed(prop: Prop)
signal item_added(item: Pickup.Item)
signal focus_changed(prompt: String)
signal message(text: String)

const WALK_SPEED := 2.6
const SPRINT_SPEED := 5.0
const CROUCH_SPEED := 1.4
const EXHAUSTED_FACTOR := 0.8
const ACCEL_GROUND := 14.0
const ACCEL_AIR := 3.0
const JUMP_VELOCITY := 4.2

const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 0.85
const RADIUS := 0.3
const EYE_FROM_TOP := 0.13

const STAMINA_MAX := 100.0
const SPRINT_DRAIN := 15.0  # ~6.5 s of full sprint
const STAMINA_REGEN := 11.0
const REGEN_DELAY := 1.4
const EXHAUST_RECOVER := 45.0  # after running dry you can't sprint until this much is back
const JUMP_COST := 12.0
## Metres per footstep. One step = one head-bob dip = one footstep sound (and noise when sprinting).
const WALK_STEP_LENGTH := 1.3
const SPRINT_STEP_LENGTH := 1.6
const CROUCH_STEP_LENGTH := 0.9
const LANDING_NOISE_SPEED := 3.0

const REACH := 2.4
const HOLD_MIN := 0.9
const HOLD_MAX := 1.6
const HOLD_BREAK := 1.4
const THROW_SPEED := 7.0

const BATTERY_SECONDS := 60.0
const FLASHLIGHT_START_CHARGE := 20.0  ## the flashlight is found with a half-dead battery
const RAY_MASK := Prop.LAYER_WORLD | Prop.LAYER_PROPS | Prop.LAYER_PICKUPS

var stamina: float = STAMINA_MAX
var exhausted: bool = false
var crouching: bool = false
var sprinting: bool = false
var has_flashlight: bool = false
var has_key: bool = false
var flashlight_on: bool = false
var battery: float = 0.0
var controls_enabled: bool = true
var night: bool = false
var held: Prop

var _yaw: float = 0.0
var _pitch: float = 0.0
var _regen_timer: float = 0.0
var _step_phase: float = 0.0  # 0..1 between foot plants
var _air_speed: float = 0.0
var _height: float = STAND_HEIGHT
var _hold_distance: float = 1.2
var _held_rel_basis: Basis
var _focus_target: Object
var _focus_prompt: String = ""
var _bob_amp: float = 0.0
var _stand_shape := CapsuleShape3D.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var night_light: OmniLight3D = $NightLight
@onready var step_player: AudioStreamPlayer = $StepPlayer
@onready var breath_player: AudioStreamPlayer = $BreathPlayer


func _ready() -> void:
	collision_layer = Prop.LAYER_PLAYER
	collision_mask = Prop.LAYER_WORLD | Prop.LAYER_MONSTER | Prop.LAYER_PROPS
	collision.shape = collision.shape.duplicate()
	_stand_shape.radius = RADIUS - 0.03
	_stand_shape.height = STAND_HEIGHT - 0.06
	breath_player.stream = Sfx.looped(Sfx.BREATH)
	_yaw = rotation.y
	flashlight.visible = false
	set_night(false)
	_apply_height(STAND_HEIGHT)


func set_night(value: bool) -> void:
	night = value
	night_light.visible = value


## Places the player and faces them along yaw (radians).
func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_yaw = yaw
	_pitch = 0.0
	rotation = Vector3(0, _yaw, 0)
	head.rotation = Vector3.ZERO


func is_lit() -> bool:
	return flashlight_on or not night


func eye_position() -> Vector3:
	return camera.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Settings.mouse_sensitivity * 0.01
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, deg_to_rad(-88), deg_to_rad(88))
		rotation.y = _yaw
		head.rotation.x = _pitch
	elif event.is_action_pressed(&"interact"):
		_try_interact()
	elif event.is_action_pressed(&"grab"):
		_try_grab()
	elif event.is_action_released(&"grab"):
		drop()
	elif event.is_action_pressed(&"throw"):
		throw_held()
	elif event.is_action_pressed(&"flashlight"):
		toggle_flashlight()


func _physics_process(delta: float) -> void:
	_update_crouch(delta)
	_update_movement(delta)
	_update_held(delta)
	_update_flashlight(delta)
	_update_focus()


# --- movement ---------------------------------------------------------------

func _update_movement(delta: float) -> void:
	var input := Vector2.ZERO
	var wants_sprint := false
	var wants_jump := false
	if controls_enabled:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		wants_sprint = Input.is_action_pressed(&"sprint")
		wants_jump = Input.is_action_just_pressed(&"jump")

	var on_floor := is_on_floor()
	var moving := input.length() > 0.1
	# Sprinting is impossible while crouched or out of breath.
	sprinting = wants_sprint and moving and not crouching and not exhausted and stamina > 0.0 and input.y < 0.3

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if exhausted:
		speed *= EXHAUSTED_FACTOR

	_update_stamina(delta)

	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var target := dir * speed
	var accel := ACCEL_GROUND if on_floor else ACCEL_AIR
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta)

	if not on_floor:
		velocity.y -= _gravity * delta
		_air_speed = maxf(_air_speed, -velocity.y)
	elif wants_jump and not crouching and stamina >= JUMP_COST:
		velocity.y = JUMP_VELOCITY
		_spend_stamina(JUMP_COST)

	move_and_slide()
	_push_props()

	if is_on_floor() and not on_floor:
		_on_landed()

	var ground_speed := Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0
	_update_steps(delta, ground_speed)
	_update_head_bob(delta, ground_speed)


func _update_stamina(delta: float) -> void:
	if sprinting:
		_spend_stamina(SPRINT_DRAIN * delta)
	else:
		_regen_timer -= delta
		if _regen_timer <= 0.0:
			stamina = minf(stamina + STAMINA_REGEN * delta, STAMINA_MAX)
	if exhausted and stamina >= EXHAUST_RECOVER:
		exhausted = false
		breath_player.stop()


func _spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_timer = REGEN_DELAY
	if stamina <= 0.0 and not exhausted:
		exhausted = true
		breath_player.play()


func _update_steps(delta: float, ground_speed: float) -> void:
	if ground_speed < 0.4:
		return
	var step_length := WALK_STEP_LENGTH
	if sprinting:
		step_length = SPRINT_STEP_LENGTH
	elif crouching:
		step_length = CROUCH_STEP_LENGTH
	_step_phase += ground_speed * delta / step_length
	if _step_phase >= 1.0:
		_step_phase -= 1.0
		_footstep()


func _footstep() -> void:
	if sprinting:
		step_player.stream = Sfx.RUN_STEPS.pick_random()
		step_player.volume_db = -3.0
		NoiseBus.emit_noise(global_position, NoiseBus.SPRINT_STEP, self)
	else:
		step_player.stream = Sfx.WALK_STEPS.pick_random()
		step_player.volume_db = -21.0 if crouching else -12.0
	step_player.pitch_scale = randf_range(0.93, 1.07)
	step_player.play()


func _on_landed() -> void:
	if _air_speed > LANDING_NOISE_SPEED:
		step_player.stream = Sfx.RUN_STEPS[0]
		step_player.volume_db = 0.0
		step_player.pitch_scale = 0.8
		step_player.play()
		NoiseBus.emit_noise(global_position, NoiseBus.JUMP_LANDING, self)
	_air_speed = 0.0


func _push_props() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body and body != held:
			body.apply_central_impulse(-c.get_normal() * 0.15)


## The head dips lowest exactly when a foot lands (phase 0), so steps and bob stay in sync.
func _update_head_bob(delta: float, ground_speed: float) -> void:
	var amp := 0.0
	if ground_speed >= 0.4:
		amp = 0.05 if sprinting else (0.012 if crouching else 0.025)
	_bob_amp = lerpf(_bob_amp, amp, minf(delta * 8.0, 1.0))
	head.position.y = _height - EYE_FROM_TOP - cos(_step_phase * TAU) * _bob_amp


# --- crouch -----------------------------------------------------------------

func _update_crouch(delta: float) -> void:
	var wants := controls_enabled and Input.is_action_pressed(&"crouch")
	if wants and not crouching:
		crouching = true
	elif not wants and crouching and _can_stand():
		crouching = false
	var target := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	if not is_equal_approx(_height, target):
		_apply_height(move_toward(_height, target, delta * 4.0))


func _apply_height(h: float) -> void:
	_height = h
	var shape := collision.shape as CapsuleShape3D
	shape.height = h
	shape.radius = RADIUS
	collision.position.y = h * 0.5


func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _stand_shape
	q.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_HEIGHT * 0.5 + 0.04, 0))
	q.collision_mask = Prop.LAYER_WORLD
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# --- looking at things ------------------------------------------------------

func _ray() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, [get_rid()])
	if held:
		q.exclude = [get_rid(), held.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


static func _find_interactable(node: Node) -> Node:
	var n := node
	for i in 3:
		if n == null:
			return null
		if n.has_method(&"interact"):
			return n
		n = n.get_parent()
	return null


func _update_focus() -> void:
	var prompt := ""
	var target: Object = null
	if controls_enabled:
		if held:
			prompt = "Отпусти [%s] — положить     [%s] — бросить" % [Settings.action_text(&"grab"), Settings.action_text(&"throw")]
		else:
			var hit := _ray()
			if hit:
				var collider: Object = hit.collider
				target = collider
				var lines: PackedStringArray = []
				var inter := _find_interactable(collider as Node)
				if inter:
					var text: String = inter.get_prompt(self)
					if text != "":
						lines.append("[%s] %s" % [Settings.action_text(&"interact"), text])
				if collider is Prop:
					lines.append("[%s] Взять: %s" % [Settings.action_text(&"grab"), (collider as Prop).get_grab_prompt()])
				prompt = "\n".join(lines)
	if prompt != _focus_prompt or target != _focus_target:
		_focus_prompt = prompt
		_focus_target = target
		focus_changed.emit(prompt)


func _try_interact() -> void:
	var hit := _ray()
	if not hit:
		return
	var inter := _find_interactable(hit.collider as Node)
	if inter:
		inter.interact(self)
		_focus_target = null  # force prompt refresh


# --- carrying (Source-style) ------------------------------------------------

func _try_grab() -> void:
	if held:
		return
	var hit := _ray()
	if not hit or not hit.collider is Prop:
		return
	var prop := hit.collider as Prop
	if _is_standing_on(prop):
		return
	held = prop
	prop.set_held(true)
	add_collision_exception_with(prop)
	prop.add_collision_exception_with(self)
	_hold_distance = clampf(camera.global_position.distance_to(prop.global_position), HOLD_MIN, HOLD_MAX)
	_held_rel_basis = _yaw_basis().inverse() * prop.global_basis.orthonormalized()
	prop.tree_exiting.connect(_on_held_freed.bind(prop), CONNECT_ONE_SHOT)
	grabbed.emit(prop)


func drop() -> void:
	if not held:
		return
	var prop := held
	held = null
	if prop.tree_exiting.is_connected(_on_held_freed):
		prop.tree_exiting.disconnect(_on_held_freed)
	prop.set_held(false)
	prop.linear_velocity = prop.linear_velocity.limit_length(3.0)
	# Re-enable collision a moment later so the prop doesn't explode out of the capsule.
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if is_instance_valid(prop):
			remove_collision_exception_with(prop)
			prop.remove_collision_exception_with(self))


func throw_held() -> void:
	if not held:
		return
	var prop := held
	drop()
	prop.linear_velocity = -camera.global_basis.z * THROW_SPEED + velocity * 0.5


func _on_held_freed(prop: Prop) -> void:
	if held == prop:
		held = null


func _update_held(_delta: float) -> void:
	if not held:
		return
	if not is_instance_valid(held):
		held = null
		return
	var target := camera.global_position - camera.global_basis.z * _hold_distance
	var diff := target - held.global_position
	if diff.length() > HOLD_BREAK:
		drop()  # snagged on something
		return
	held.linear_velocity = (diff * 15.0).limit_length(9.0)
	var target_basis := _yaw_basis() * _held_rel_basis
	var q := (target_basis * held.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	var angle := q.get_angle()
	if angle > 0.001:
		var axis := q.get_axis()
		if angle > PI:
			angle -= TAU
		held.angular_velocity = axis * angle * 10.0
	else:
		held.angular_velocity = Vector3.ZERO


func _yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


func _is_standing_on(body: Node) -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() == body and c.get_normal().y > 0.6:
			return true
	return false


# --- inventory & flashlight -------------------------------------------------

func add_item(item: Pickup.Item) -> void:
	match item:
		Pickup.Item.FLASHLIGHT:
			if not has_flashlight:
				battery = maxf(battery, FLASHLIGHT_START_CHARGE)
			has_flashlight = true
			message.emit("Фонарик в инвентаре. [%s] — включить" % Settings.action_text(&"flashlight"))
		Pickup.Item.KEY:
			has_key = true
			message.emit("Ключ в инвентаре")
	item_added.emit(item)


## Loads a fresh battery: the charge is reset to a full minute. Returns false if there's no flashlight.
func insert_battery() -> bool:
	if not has_flashlight:
		message.emit("Сначала найди фонарик")
		return false
	battery = BATTERY_SECONDS
	message.emit("Батарейка вставлена")
	return true


func toggle_flashlight() -> void:
	if not has_flashlight:
		return
	if not flashlight_on and battery <= 0.0:
		message.emit("Батарейка села")
		return
	_set_flashlight(not flashlight_on)


func _set_flashlight(on: bool) -> void:
	flashlight_on = on
	flashlight.visible = on


func _update_flashlight(delta: float) -> void:
	if not flashlight_on:
		return
	battery = maxf(battery - delta, 0.0)
	if battery <= 0.0:
		_set_flashlight(false)
		message.emit("Батарейка села")
		return
	# Weak battery: flicker.
	if battery < 8.0 and randf() < 0.08:
		flashlight.light_energy = randf_range(0.2, 1.0)
	else:
		flashlight.light_energy = lerpf(flashlight.light_energy, 2.2, 0.3)


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if not value:
		drop()
		velocity = Vector3.ZERO
