class_name Player
extends CharacterBody3D
## First-person player: movement with stamina, crouch, Source-style carrying, interaction,
## flashlight with batteries, a two-slot inventory (flashlight + key) and hiding under beds.

signal grabbed(prop: Prop)
signal item_added(item: Pickup.Item)
signal focus_changed(prompt: String)
signal message(text: String)
signal hiding_changed(hidden: bool)

const WALK_SPEED := 2.0
const SPRINT_SPEED := 4.5
const CROUCH_SPEED := 1.0
## Exhausted: walk 1.6 m/s, crouch 0.8 m/s (sprinting is impossible).
const EXHAUSTED_FACTOR := 0.8
const ACCEL_GROUND := 14.0
const ACCEL_AIR := 3.0
const JUMP_VELOCITY := 4.2

const STAND_HEIGHT := 1.28  ## the hero is a small kid: the eyes are at 1.15 m (they were at 1.47)
const CROUCH_HEIGHT := 0.85
const RADIUS := 0.3
const EYE_FROM_TOP := 0.13

const STAMINA_MAX := 100.0
const SPRINT_DRAIN := 30.0  # ~3.3 s of full sprint
const STAMINA_REGEN := 11.0
const REGEN_DELAY := 1.4
const EXHAUST_RECOVER := 45.0  # after running dry you can't sprint until this much is back
const JUMP_COST := 12.0
## Metres per footstep. One step = one head-bob dip = one footstep sound (and noise when sprinting).
## Slower movement shortens the stride a bit and lowers the cadence: walk 1.82, sprint 3.0, crouch 1.33
## steps/s (they were 2.0 / 3.125 / 1.56 at the old speeds).
const WALK_STEP_LENGTH := 1.1
const SPRINT_STEP_LENGTH := 1.5
const CROUCH_STEP_LENGTH := 0.75
## Footstep sample pitch (= playback speed) relative to the old cadence, so slower steps sound slower.
const WALK_STEP_PITCH := 0.91
const SPRINT_STEP_PITCH := 0.96
const CROUCH_STEP_PITCH := 0.86
const LANDING_NOISE_SPEED := 3.0

const REACH := 2.4
const HOLD_MIN := 0.9
const HOLD_MAX := 1.6
const HOLD_BREAK := 1.4
const THROW_SPEED := 7.0

const BATTERY_SECONDS := 60.0
const FLASHLIGHT_START_CHARGE := 20.0  ## the flashlight is found with a half-dead battery
const RAY_MASK := Prop.LAYER_WORLD | Prop.LAYER_PROPS | Prop.LAYER_PICKUPS | Prop.LAYER_DOORS
## Lying under a bed: eye height and how far you can turn your head.
const HIDE_EYE_HEIGHT := 0.17
const HIDE_YAW_RANGE := 1.0
const HIDE_PITCH := Vector2(-0.25, 0.3)
## Falling asleep (see fall_asleep): seated and lying eye heights above the floor (the mattress top
## is at 0.55 m), lying pitch (face up), durations in seconds.
const SLEEP_SIT_EYE := 0.98
const SLEEP_LIE_EYE := 0.8
const SLEEP_LIE_PITCH := 1.42
const SLEEP_SIT_TIME := 1.0
const SLEEP_LIE_TIME := 1.4
const SLEEP_BLANKET_TIME := 1.2
const SLEEP_EYES_TIME := 1.1

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
var hidden_in: Bed  ## the bed the player is hiding under, or null
var sleeping: bool = false  ## the fall-asleep sequence is running (or waiting for finish_sleep)

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
var _breath_loop: AudioStreamWAV
var _sleep_blanket: SleepBlanket
var _physics_was_on: bool = true
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
	collision_mask = Prop.LAYER_WORLD | Prop.LAYER_MONSTER | Prop.LAYER_PROPS | Prop.LAYER_DOORS
	collision.shape = collision.shape.duplicate()
	_stand_shape.radius = RADIUS - 0.03
	_stand_shape.height = STAND_HEIGHT - 0.06
	_breath_loop = Sfx.looped(Sfx.BREATH)
	breath_player.stream = _breath_loop
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


func is_hidden() -> bool:
	return hidden_in != null


func eye_position() -> Vector3:
	return camera.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Settings.mouse_sensitivity * 0.01
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, deg_to_rad(-88), deg_to_rad(88))
		if hidden_in:
			var center := hidden_in.hide_yaw()
			_yaw = center + clampf(angle_difference(center, _yaw), -HIDE_YAW_RANGE, HIDE_YAW_RANGE)
			_pitch = clampf(_pitch, HIDE_PITCH.x, HIDE_PITCH.y)
		rotation.y = _yaw
		head.rotation.x = _pitch
	elif hidden_in:
		if event.is_action_pressed(&"interact") or event.is_action_pressed(&"jump"):
			leave_hiding()
		elif event.is_action_pressed(&"flashlight"):
			toggle_flashlight()
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
	if hidden_in:
		sprinting = false
		_update_stamina(delta)
		_update_flashlight(delta)
		_update_focus()
		return
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
		# Catching your breath: one last shivering breath.
		breath_player.stream = Sfx.BREATH_RECOVER
		breath_player.play()


func _spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_timer = REGEN_DELAY
	if stamina <= 0.0 and not exhausted:
		exhausted = true
		breath_player.stream = _breath_loop
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
	var pitch := WALK_STEP_PITCH
	if sprinting:
		step_player.stream = Sfx.RUN_STEPS.pick_random()
		step_player.volume_db = -3.0
		pitch = SPRINT_STEP_PITCH
		NoiseBus.emit_noise(global_position, NoiseBus.SPRINT_STEP, self)
	else:
		step_player.stream = Sfx.WALK_STEPS.pick_random()
		step_player.volume_db = -21.0 if crouching else -12.0
		if crouching:
			pitch = CROUCH_STEP_PITCH
	step_player.pitch_scale = randf_range(0.93, 1.07) * pitch
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
		if hidden_in:
			prompt = "[%s] Вылезти из-под кровати" % Settings.action_text(&"interact")
		elif held:
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
	prop.on_thrown()


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


# --- hiding under a bed -----------------------------------------------------

## Crawls under the bed: the player lies there looking out of the open side and can't move.
## The monster doesn't see a hidden player, unless it watched them crawl in.
func hide_under(bed: Bed) -> void:
	if hidden_in:
		return
	drop()
	hidden_in = bed
	velocity = Vector3.ZERO
	sprinting = false
	collision.disabled = true
	global_position = bed.hide_position()
	_yaw = bed.hide_yaw()
	_pitch = 0.0
	rotation = Vector3(0, _yaw, 0)
	head.rotation.x = 0.0
	head.position.y = HIDE_EYE_HEIGHT
	_bob_amp = 0.0
	hiding_changed.emit(true)


func leave_hiding() -> void:
	if not hidden_in:
		return
	var bed := hidden_in
	hidden_in = null
	global_position = bed.exit_position()
	velocity = Vector3.ZERO
	crouching = true  # you come out on all fours; stands up once crouch is released
	_apply_height(CROUCH_HEIGHT)
	head.position.y = CROUCH_HEIGHT - EYE_FROM_TOP
	collision.disabled = false
	hiding_changed.emit(false)


## The first-person fall-asleep sequence that ends the morning: walk up to the bed, sit down on its
## edge, lie back, pull the blanket (the cloth of the bed's own blanket) up over the head until it
## fills the screen and let the eyelids droop shut. Takes a few seconds; call `finish_sleep()` once
## the screen is black to give the player their body back.
func fall_asleep(bed: Bed, hud: Hud) -> void:
	drop()
	_physics_was_on = is_physics_processing()
	set_physics_process(false)
	collision.disabled = true
	velocity = Vector3.ZERO
	crouching = false
	_bob_amp = 0.0
	sleeping = true
	_focus_prompt = ""
	_focus_target = null
	focus_changed.emit("")  # physics is off: nothing else would clear the "go to bed" prompt
	var width := bed.width
	var sit_pos := bed.to_global(Vector3(-0.15, 0.0, width * 0.5 - 0.1))
	sit_pos.y = bed.global_position.y
	var lie_pos := bed.to_global(Vector3(-0.55, 0.0, 0.0))
	lie_pos.y = bed.global_position.y
	var yaw_out := atan2(-bed.global_basis.z.x, -bed.global_basis.z.z)  # out of the open side
	var yaw_feet := atan2(-bed.global_basis.x.x, -bed.global_basis.x.z)  # along the bed, towards the feet
	var blanket := SleepBlanket.create(camera, Vector2(get_viewport().size).aspect())  # the real size: 3D ignores the stretch
	camera.add_child(blanket)
	_sleep_blanket = blanket

	# 1. Sit down on the edge of the bed (looking at the room, then glancing at the mattress).
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	tw.tween_property(self, "global_position", sit_pos, SLEEP_SIT_TIME)
	tw.tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, yaw_out), SLEEP_SIT_TIME)
	tw.tween_property(head, "position:y", SLEEP_SIT_EYE, SLEEP_SIT_TIME)
	tw.tween_property(head, "rotation:x", -0.3, SLEEP_SIT_TIME)
	await tw.finished
	Sfx.play_2d(Sfx.BED_CREAKS.pick_random(), -10.0, 1.05)
	# The mattress gives under the weight: the head dips and comes back up.
	tw = create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(head, "position:y", SLEEP_SIT_EYE - 0.045, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "position:y", SLEEP_SIT_EYE, 0.22).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	await get_tree().create_timer(0.03).timeout

	# 2. Lie back along the bed, face up: the body goes down first, then the camera turns to the
	# ceiling, with a slight sway to the side.
	tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	tw.tween_property(self, "global_position", lie_pos, SLEEP_LIE_TIME)
	tw.tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, yaw_feet), SLEEP_LIE_TIME)
	tw.tween_property(head, "position:y", SLEEP_LIE_EYE, SLEEP_LIE_TIME)
	tw.tween_property(head, "rotation:x", SLEEP_LIE_PITCH, SLEEP_LIE_TIME * 0.8).set_delay(SLEEP_LIE_TIME * 0.2).set_trans(Tween.TRANS_QUAD)
	var sway := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(head, "rotation:z", 0.05, SLEEP_LIE_TIME * 0.5)
	sway.tween_property(head, "rotation:z", 0.0, SLEEP_LIE_TIME * 0.5)
	await get_tree().create_timer(SLEEP_LIE_TIME * 0.55).timeout
	Sfx.play_2d(Sfx.BED_CREAKS.pick_random(), -12.0, 0.9)
	await tw.finished
	# A deep breath in the new position.
	tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(head, "position:y", SLEEP_LIE_EYE + 0.015, 0.2)
	tw.tween_property(head, "position:y", SLEEP_LIE_EYE, 0.2)
	await tw.finished

	# 3. Pull the blanket up: it comes into view from below (the whole width of the screen), is
	# gripped for a moment, then is drawn up to the chin. The upper part of the view stays free.
	blanket.reveal()
	var stage := SLEEP_BLANKET_TIME * 0.42
	var grip := SLEEP_BLANKET_TIME * 0.12
	var over := SLEEP_BLANKET_TIME * 0.46
	tw = create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(blanket, "position:y", blanket.hem_y(0.24), stage).set_ease(Tween.EASE_OUT)
	tw.tween_interval(grip)
	tw.tween_callback(func() -> void: Sfx.play_2d(Sfx.PLASTIC.pick_random(), -28.0, 0.5))
	tw.tween_property(blanket, "position:y", blanket.rest_y(), over).set_ease(Tween.EASE_IN_OUT)
	var tilt := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_parallel(true)
	blanket.rotation = Vector3(-0.3, 0.0, 0.04)
	tilt.tween_property(blanket, "rotation:x", 0.0, SLEEP_BLANKET_TIME)
	tilt.tween_property(blanket, "rotation:z", 0.0, SLEEP_BLANKET_TIME)
	Sfx.play_2d(Sfx.PLASTIC.pick_random(), -26.0, 0.6)  # a dull rustle of cloth
	await tw.finished
	# The cloth settles under its own weight.
	tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(blanket, "position:y", blanket.rest_y() - 0.02, 0.2)
	tw.tween_property(blanket, "position:y", blanket.rest_y(), 0.2)
	await tw.finished

	# 4. The eyelids droop shut.
	await hud.close_eyes(SLEEP_EYES_TIME).finished


## Gives the body back after `fall_asleep` (the screen is black by now): the blanket goes away, the
## head and the capsule are as usual again. The caller places the player (`teleport`).
func finish_sleep() -> void:
	if not sleeping:
		return
	sleeping = false
	if is_instance_valid(_sleep_blanket):
		_sleep_blanket.queue_free()
	_sleep_blanket = null
	collision.disabled = false
	set_physics_process(_physics_was_on)
	crouching = false
	_apply_height(STAND_HEIGHT)
	head.position.y = STAND_HEIGHT - EYE_FROM_TOP
	head.rotation = Vector3.ZERO
	_pitch = 0.0


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if not value:
		drop()
		velocity = Vector3.ZERO
