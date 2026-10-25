class_name Monster
extends CharacterBody3D
## Honest monster AI with three states. It never reads the player's position except where the
## design explicitly allows it (hunt start, first seconds of a chase).
##
## SEARCH — patrols random waypoints; any heard noise reroutes it to the source and fills patience.
## HUNT   — patience full (3 loud noises): global roar, gets the player's position, moves faster.
## CHASE  — player in line of sight: runs at the player's sprint speed; for the first 5 s it gets
##          the player's position every second even without sight.

signal state_changed(state: State)
signal caught_player

enum State { SEARCH, HUNT, CHASE }

const PATROL_SPEED := 1.7
const INVESTIGATE_SPEED := 2.3
const SWEEP_SPEED := 2.0
const HUNT_SPEED := 4.2
const CHASE_SPEED := Player.SPRINT_SPEED
const TURN_SPEED := 7.0

const PATIENCE_MAX := 3
const PATIENCE_DECAY_TIME := 20.0  ## quiet seconds per patience point lost
const SAME_SOURCE_COOLDOWN_PLAYER := 2.5  ## a burst of footsteps counts as one noise
const SAME_SOURCE_COOLDOWN := 6.0

const CHASE_TRACK_TIME := 5.0
const CHASE_TRACK_INTERVAL := 1.0
const LOSE_SIGHT_GIVE_UP := 6.0

const FOV_DEG := 120.0
const SIGHT_RANGE_LIT := 18.0
const SIGHT_RANGE_DARK := 9.0
const CROUCH_SIGHT_FACTOR := 0.65
const PROXIMITY_SENSE := 1.6
const CATCH_DISTANCE := 1.05
const OCCLUDED_HEARING := 0.55
const EYE_HEIGHT := 1.75
const STUCK_TIME := 2.5

var state: State = State.SEARCH
var patience: int = 0
var player: Player
var patrol_points: Array[Vector3] = []
var active: bool = false

var _speed: float = PATROL_SPEED
var _target: Vector3
var _has_target: bool = false
var _wait_timer: float = 0.0
var _investigating: bool = false
var _noise_source: WeakRef
var _sweep_queue: Array[Vector3] = []
var _quiet_timer: float = 0.0
var _source_times: Dictionary = {}  # instance_id -> last time it added patience
var _chase_time: float = 0.0
var _track_timer: float = 0.0
var _unseen_time: float = 0.0
var _last_seen: Vector3
var _repath_timer: float = 0.0
var _step_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_patrol: int = -1
var _sees_player: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var voice: AudioStreamPlayer3D = $Voice


func _ready() -> void:
	collision_layer = Prop.LAYER_MONSTER
	collision_mask = Prop.LAYER_WORLD | Prop.LAYER_PLAYER | Prop.LAYER_PROPS
	NoiseBus.noise_emitted.connect(_on_noise)


## Starts the AI once the navigation map has synced.
func activate(target_player: Player, points: Array[Vector3]) -> void:
	player = target_player
	patrol_points = points
	# Wait until the freshly baked house is synced into the navigation map.
	var map := agent.get_navigation_map()
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and not points.is_empty() \
				and not NavigationServer3D.map_get_path(map, global_position, points[0], true).is_empty():
			break
		await get_tree().physics_frame
	active = true
	_next_patrol_point()


func debug_text() -> String:
	return "Монстр: %s | терпение %d/%d | вижу: %s" % [State.keys()[state], patience, PATIENCE_MAX, "да" if _sees_player else "нет"]


func _physics_process(delta: float) -> void:
	if not active or player == null:
		return
	_sees_player = _can_see_player()
	if state != State.CHASE and _sees_player:
		_enter_chase()
	if state == State.CHASE:
		_update_chase(delta)
	else:
		_update_patience(delta)
		_update_roaming(delta)
	_move(delta)
	_check_catch()


# --- state transitions ------------------------------------------------------

func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


func _enter_hunt() -> void:
	_set_state(State.HUNT)
	patience = PATIENCE_MAX
	_investigating = false
	_sweep_queue.clear()
	_wait_timer = 0.0
	voice.stream = Sfx.ROAR
	voice.play()
	Sfx.play_2d(Sfx.ROAR, -10.0)  # heard across the whole house
	_go_to(player.global_position, HUNT_SPEED)


func _enter_chase() -> void:
	_set_state(State.CHASE)
	_chase_time = 0.0
	_track_timer = 0.0
	_unseen_time = 0.0
	_wait_timer = 0.0
	_investigating = false
	_sweep_queue.clear()
	_last_seen = player.global_position
	voice.stream = Sfx.GROWL
	voice.play()
	_go_to(_last_seen, CHASE_SPEED)


## Gives up on direct pursuit and sweeps the area around `center`.
func _begin_sweep(center: Vector3) -> void:
	_set_state(State.SEARCH)
	patience = 0
	_quiet_timer = 0.0
	_investigating = false
	_sweep_queue.clear()
	var map := agent.get_navigation_map()
	for i in 3:
		var offset := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		_sweep_queue.append(NavigationServer3D.map_get_closest_point(map, center + offset))
	_wait_timer = 1.5


# --- senses -----------------------------------------------------------------

func _eye() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func _line_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Prop.LAYER_WORLD, [get_rid(), player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _can_see_player() -> bool:
	var eye := _eye()
	var head := player.eye_position()
	var chest := player.global_position + Vector3(0, 0.5, 0)
	var to_player := head - eye
	var dist := to_player.length()
	if dist < PROXIMITY_SENSE:
		return _line_clear(eye, chest) or _line_clear(eye, head)
	var sight := SIGHT_RANGE_LIT if player.is_lit() else SIGHT_RANGE_DARK
	if player.crouching:
		sight *= CROUCH_SIGHT_FACTOR
	if dist > sight:
		return false
	var forward := -global_basis.z
	if forward.dot(to_player / dist) < cos(deg_to_rad(FOV_DEG * 0.5)):
		return false
	return _line_clear(eye, head) or _line_clear(eye, chest)


func _on_noise(pos: Vector3, radius: float, source: Node) -> void:
	if not active or state == State.CHASE:
		return
	if source == self or pos.distance_to(global_position) < 1.5:
		return  # its own bumping around
	var effective := radius
	if not _line_clear(_eye(), pos + Vector3(0, 0.3, 0)):
		effective *= OCCLUDED_HEARING
	if global_position.distance_to(pos) > effective:
		return
	_quiet_timer = 0.0
	if state == State.HUNT:
		_go_to(pos, HUNT_SPEED)  # reroute but keep hunting
		_noise_source = weakref(source) if source else null
		return
	if _adds_patience(source):
		patience += 1
	if patience >= PATIENCE_MAX:
		_enter_hunt()
		return
	_investigating = true
	_noise_source = weakref(source) if source else null
	_sweep_queue.clear()
	_wait_timer = 0.0
	_go_to(pos, INVESTIGATE_SPEED)


func _adds_patience(source: Node) -> bool:
	if source == null:
		return true
	var now := Time.get_ticks_msec() / 1000.0
	var id := source.get_instance_id()
	var cooldown := SAME_SOURCE_COOLDOWN_PLAYER if source is Player else SAME_SOURCE_COOLDOWN
	if _source_times.has(id) and now - float(_source_times[id]) < cooldown:
		return false
	_source_times[id] = now
	return true


func _update_patience(delta: float) -> void:
	if state != State.SEARCH or patience <= 0:
		return
	_quiet_timer += delta
	if _quiet_timer >= PATIENCE_DECAY_TIME:
		_quiet_timer = 0.0
		patience -= 1


# --- behaviours -------------------------------------------------------------

func _update_chase(delta: float) -> void:
	_chase_time += delta
	if _sees_player:
		_unseen_time = 0.0
		_last_seen = player.global_position
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = 0.2
			_go_to(_last_seen, CHASE_SPEED)
		return
	_unseen_time += delta
	if _chase_time <= CHASE_TRACK_TIME:
		# Allowed "sixth sense" for the first seconds of a chase: position every second.
		_track_timer -= delta
		if _track_timer <= 0.0:
			_track_timer = CHASE_TRACK_INTERVAL
			_last_seen = player.global_position
			_go_to(_last_seen, CHASE_SPEED)
	elif _reached() or _unseen_time > LOSE_SIGHT_GIVE_UP:
		_begin_sweep(_last_seen)


func _update_roaming(delta: float) -> void:
	if _wait_timer > 0.0:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_next_target()
		return
	if _has_target and _reached():
		_on_arrived()


func _on_arrived() -> void:
	_has_target = false
	if state == State.HUNT:
		_begin_sweep(global_position)
		return
	if _investigating:
		_investigating = false
		var src: Object = _noise_source.get_ref() if _noise_source else null
		if src and src.has_method(&"monster_disable") and (src as Node3D).global_position.distance_to(global_position) < 3.0:
			src.monster_disable()
		_wait_timer = 2.5
		return
	_wait_timer = 1.0 if not _sweep_queue.is_empty() else randf_range(1.0, 2.5)


func _next_target() -> void:
	if not _sweep_queue.is_empty():
		_go_to(_sweep_queue.pop_front(), SWEEP_SPEED)
	else:
		_next_patrol_point()


func _next_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	var i := randi() % patrol_points.size()
	if patrol_points.size() > 1:
		while i == _last_patrol:
			i = randi() % patrol_points.size()
	_last_patrol = i
	_go_to(patrol_points[i], PATROL_SPEED)


func _go_to(pos: Vector3, speed: float) -> void:
	# Noise sources and the player can be off the navmesh (on furniture, in the vent):
	# head for the closest point the monster can actually stand on.
	var map := agent.get_navigation_map()
	if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
		pos = NavigationServer3D.map_get_closest_point(map, pos)
	_target = pos
	agent.target_position = pos
	_speed = speed
	_has_target = true
	_stuck_timer = 0.0


func _reached() -> bool:
	var d := _target - global_position
	d.y = 0.0
	return agent.is_navigation_finished() or d.length() < 0.9


# --- locomotion -------------------------------------------------------------

func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	if _wait_timer > 0.0 and state != State.CHASE:
		rotation.y += sin(Time.get_ticks_msec() / 600.0) * delta * 1.6  # looking around
	elif _has_target and not _reached():
		var to_next := agent.get_next_path_position() - global_position
		to_next.y = 0.0
		if to_next.length() > 0.05:
			desired = to_next.normalized() * _speed
			var yaw := atan2(-desired.x, -desired.z)
			rotation.y = lerp_angle(rotation.y, yaw, minf(TURN_SPEED * delta, 1.0))
	velocity.x = desired.x
	velocity.z = desired.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	_push_props()
	_update_stuck(delta, desired)
	_update_steps(delta, desired)


func _push_props() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body:
			body.apply_central_impulse(-c.get_normal() * 0.6)


func _update_stuck(delta: float, desired: Vector3) -> void:
	if desired.length() < 0.1:
		_stuck_timer = 0.0
		return
	var real := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	_stuck_timer = _stuck_timer + delta if real < 0.25 else 0.0
	if _stuck_timer > STUCK_TIME and state != State.CHASE:
		_stuck_timer = 0.0
		_investigating = false
		_next_target()


func _update_steps(delta: float, desired: Vector3) -> void:
	var speed := desired.length()
	if speed < 0.1:
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = clampf(1.1 / speed, 0.3, 0.7)
		Sfx.play_3d(Sfx.MONSTER_STEP, global_position, -2.0 if speed > 3.0 else -7.0, 22.0, randf_range(0.85, 1.05))


func _check_catch() -> void:
	var d := global_position - player.global_position
	if Vector2(d.x, d.z).length() < CATCH_DISTANCE and absf(d.y) < 1.2 and _line_clear(_eye(), player.global_position + Vector3(0, 0.4, 0)):
		active = false
		velocity = Vector3.ZERO
		caught_player.emit()
