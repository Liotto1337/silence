class_name Monster
extends CharacterBody3D
## Honest monster AI with three states. It never reads the player's position except where the
## design explicitly allows it (hunt start, first seconds of a chase).
##
## SEARCH — patrols random waypoints and looks around each room; any heard noise reroutes it
##          to the source and fills patience.
## HUNT   — patience full (2 loud noises): roars across the house, gets the player's position,
##          moves faster.
## CHASE  — player in line of sight: turns to face the player and freezes for a second, then runs
##          (a bit slower than the player's sprint); for the first 5 s of the run it gets the
##          player's position every second even without sight.
##
## Vision follows the head: while looking around a room the head sweeps and the sight cone with it.
## A player hiding under a bed is invisible to it, unless it saw them crawl in.
## It opens closed room doors that are in its way.

signal state_changed(state: State)
signal caught_player

enum State { SEARCH, HUNT, CHASE }

const PATROL_SPEED := 1.3
const INVESTIGATE_SPEED := 1.8
const SWEEP_SPEED := 1.5
const HUNT_SPEED := 3.3
const CHASE_SPEED := 4.3  ## the player's sprint (5.0) is faster, but stamina runs out
const TURN_SPEED := 6.0
const ALERT_TURN_SPEED := 14.0

const ALERT_TIME := 1.0  ## spotted the player: faces them and freezes before the chase
const ROAR_TIME := 1.6  ## hunt start: roars on the spot before running

## How long it stands looking around after reaching a point (seconds).
const LOOK_TIME_PATROL := Vector2(3.5, 6.0)
const LOOK_TIME_NOISE := 6.0
const LOOK_TIME_SWEEP := 4.0
const LOOK_TIME_SWEEP_START := 3.0
const HEAD_YAW_MAX := 1.2

const PATIENCE_MAX := 2
const PATIENCE_DECAY_TIME := 20.0  ## quiet seconds per patience point lost
const SAME_SOURCE_COOLDOWN_PLAYER := 2.5  ## a burst of footsteps counts as one noise
const SAME_SOURCE_COOLDOWN := 6.0

const CHASE_TRACK_TIME := 5.0
const CHASE_TRACK_INTERVAL := 1.0
const LOSE_SIGHT_GIVE_UP := 6.0

const FOV_DEG := 120.0
const SIGHT_RANGE_LIT := 10.0
const SIGHT_RANGE_DARK := 5.0
const CROUCH_SIGHT_FACTOR := 0.65
const PROXIMITY_SENSE := 1.6
const CATCH_DISTANCE := 1.05
const HIDDEN_CATCH_DISTANCE := 1.3  ## from the bed's open side: pulls out a player it saw hide there
const OCCLUDED_HEARING := 0.55
const EYE_HEIGHT := 2.2
const STUCK_TIME := 2.5
const DOOR_REACH := 1.0  ## opens a door this far ahead (plus the distance covered while it swings)
const SIGHT_MASK := Prop.LAYER_WORLD | Prop.LAYER_DOORS

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
var _alert_timer: float = 0.0
var _roar_timer: float = 0.0
var _head_yaw: float = 0.0
var _scan_yaw: float = 0.0
var _scan_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_patrol: int = -1
var _sees_player: bool = false
var _saw_hide: bool = false  # watched the player crawl under the bed they're hiding under
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

const BREATH_DB := {State.SEARCH: -16.0, State.HUNT: -9.0, State.CHASE: -4.0}

var _breath: AudioStreamPlayer3D

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var voice: AudioStreamPlayer3D = $Voice
@onready var model: MonsterModel = $Model


func _ready() -> void:
	collision_layer = Prop.LAYER_MONSTER
	collision_mask = Prop.LAYER_WORLD | Prop.LAYER_PLAYER | Prop.LAYER_PROPS | Prop.LAYER_DOORS
	NoiseBus.noise_emitted.connect(_on_noise)
	model.footstep.connect(_on_footstep)
	# Heavy breathing you can locate in the dark; it gets louder the angrier the monster is.
	_breath = AudioStreamPlayer3D.new()
	_breath.stream = Sfx.looped_ogg(Sfx.MONSTER_BREATH)
	_breath.position = Vector3(0, 1.8, 0)
	_breath.unit_size = 2.5
	_breath.max_distance = 20.0
	_breath.volume_db = -60.0
	add_child(_breath)
	_breath.play()


## Starts the AI once the navigation map has synced.
func activate(target_player: Player, points: Array[Vector3]) -> void:
	player = target_player
	patrol_points = points
	player.hiding_changed.connect(_on_player_hiding)
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
	var extra := ""
	if _alert_timer > 0.0:
		extra = " (заметил)"
	elif _roar_timer > 0.0:
		extra = " (рёв)"
	return "Монстр: %s%s | терпение %d/%d | вижу: %s" % [State.keys()[state], extra, patience, PATIENCE_MAX, "да" if _sees_player else "нет"]


## True while it stands still for the "spotted you" freeze or the hunt roar.
func is_frozen() -> bool:
	return _alert_timer > 0.0 or _roar_timer > 0.0


func _physics_process(delta: float) -> void:
	if not active or player == null:
		model.move_speed = 0.0
		_breath.volume_db = lerpf(_breath.volume_db, -60.0, 0.04)
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
	_update_model()
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
	_roar_timer = ROAR_TIME
	voice.stream = Sfx.ROAR
	voice.play()
	Sfx.play_3d(Sfx.MONSTER_GROWLS.pick_random(), global_position + Vector3(0, 1.8, 0), -3.0, 40.0)
	Sfx.play_2d(Sfx.ROAR, -12.0)  # heard across the whole house
	_go_to(_player_spot(), HUNT_SPEED)


func _enter_chase() -> void:
	_set_state(State.CHASE)
	_chase_time = 0.0
	_track_timer = 0.0
	_unseen_time = 0.0
	_wait_timer = 0.0
	_roar_timer = 0.0
	_alert_timer = ALERT_TIME
	_investigating = false
	_sweep_queue.clear()
	_last_seen = _player_spot()
	voice.stream = Sfx.ROAR  # the same scream as the hunt start: it has seen you
	voice.play()
	Sfx.play_3d(Sfx.MONSTER_GROWLS.pick_random(), global_position + Vector3(0, 1.8, 0), -3.0, 40.0)
	_has_target = false


## Gives up on direct pursuit and sweeps the area around `center`.
func _begin_sweep(center: Vector3) -> void:
	_set_state(State.SEARCH)
	patience = 0
	_quiet_timer = 0.0
	_alert_timer = 0.0
	_roar_timer = 0.0
	_investigating = false
	_sweep_queue.clear()
	var map := agent.get_navigation_map()
	for i in 3:
		var offset := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		_sweep_queue.append(NavigationServer3D.map_get_closest_point(map, center + offset))
	_start_looking(LOOK_TIME_SWEEP_START)


# --- senses -----------------------------------------------------------------

func _eye() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func _line_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, SIGHT_MASK, [get_rid(), player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _can_see_player() -> bool:
	if player.is_hidden():
		return _saw_hide
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
	var forward := -(global_basis * Basis(Vector3.UP, _head_yaw)).z  # the cone follows the head
	if forward.dot(to_player / dist) < cos(deg_to_rad(FOV_DEG * 0.5)):
		return false
	return _line_clear(eye, head) or _line_clear(eye, chest)


## Where to head for the player: someone under a bed is reached from its open side.
func _player_spot() -> Vector3:
	return player.hidden_in.exit_position() if player.is_hidden() else player.global_position


## The player crawled under a bed (or out). It only knows where they are if it was watching.
func _on_player_hiding(hidden: bool) -> void:
	_saw_hide = hidden and active and _sees_player


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
		_go_to(pos, HUNT_SPEED, source)  # reroute but keep hunting
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
	_go_to(pos, INVESTIGATE_SPEED, source)


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
	if _sees_player:
		_last_seen = _player_spot()
	if _alert_timer > 0.0:
		# Spotted: stare at the player for a moment, then run.
		_alert_timer -= delta
		if _alert_timer <= 0.0:
			_alert_timer = 0.0
			_go_to(_last_seen, CHASE_SPEED)
		return
	_chase_time += delta
	if _sees_player:
		_unseen_time = 0.0
		_last_seen = _player_spot()
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
			_last_seen = _player_spot()
			_go_to(_last_seen, CHASE_SPEED)
	elif _reached() or _unseen_time > LOSE_SIGHT_GIVE_UP:
		_begin_sweep(_last_seen)


func _update_roaming(delta: float) -> void:
	if _roar_timer > 0.0:
		_roar_timer = maxf(_roar_timer - delta, 0.0)
		return
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
		if src and src.has_method(&"monster_disable"):
			var src_pos := (src as Node3D).global_position
			if src_pos.distance_to(global_position) < 3.0 and _sees_point(global_position, src_pos, src as Node):
				src.monster_disable()
		_start_looking(LOOK_TIME_NOISE)
		return
	if not _sweep_queue.is_empty():
		_start_looking(LOOK_TIME_SWEEP)
	else:
		_start_looking(randf_range(LOOK_TIME_PATROL.x, LOOK_TIME_PATROL.y))


## Stands still and looks around the room for `time` seconds.
func _start_looking(time: float) -> void:
	_wait_timer = time
	_scan_timer = 0.0


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


## `source` (optional) is the object at the target, ignored when checking sight lines to it.
func _go_to(pos: Vector3, speed: float, source: Node = null) -> void:
	pos = _standable_point_near(pos, source)
	_target = pos
	agent.target_position = pos
	_speed = speed
	_has_target = true
	_stuck_timer = 0.0


## Noise sources and the player can be off the navmesh (on furniture, by a wall, in the vent):
## head for the closest point the monster can stand on, preferring one on the same side of the
## wall as the target (a TV against a wall is "closest" from the next room otherwise).
func _standable_point_near(pos: Vector3, source: Node = null) -> Vector3:
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return pos
	var closest := NavigationServer3D.map_get_closest_point(map, pos)
	if _sees_point(closest, pos, source):
		return closest
	var best := closest
	var best_dist := INF
	for ring: float in [0.8, 1.4, 2.0]:
		for i in 12:
			var a := TAU * i / 12.0
			var p := NavigationServer3D.map_get_closest_point(map, pos + Vector3(cos(a), 0.0, sin(a)) * ring)
			var d := Vector2(p.x - pos.x, p.z - pos.z).length()
			if d < best_dist and _sees_point(p, pos, source):
				best = p
				best_dist = d
		if best_dist < INF:
			break
	return best


## Line of sight from standing at `from` to `target` (the object `source` there doesn't block it).
func _sees_point(from: Vector3, target: Vector3, source: Node = null) -> bool:
	var exclude: Array[RID] = [get_rid()]
	if source is CollisionObject3D:
		exclude.append((source as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.0, 0), target + Vector3(0, 0.15, 0), SIGHT_MASK, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _reached() -> bool:
	var d := _target - global_position
	d.y = 0.0
	return agent.is_navigation_finished() or d.length() < 0.9


# --- locomotion -------------------------------------------------------------

func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	var looking := _wait_timer > 0.0 and state != State.CHASE and not is_frozen()
	if _alert_timer > 0.0:
		var to_player := _last_seen - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to_player.x, -to_player.z), minf(ALERT_TURN_SPEED * delta, 1.0))
	elif looking:
		_update_scan(delta)
	elif _roar_timer > 0.0:
		pass
	elif _has_target and not _reached():
		var to_next := agent.get_next_path_position() - global_position
		to_next.y = 0.0
		if to_next.length() > 0.05:
			desired = to_next.normalized() * _speed
			var yaw := atan2(-desired.x, -desired.z)
			rotation.y = lerp_angle(rotation.y, yaw, minf(TURN_SPEED * delta, 1.0))
	if not looking:
		_scan_yaw = 0.0
	_head_yaw = lerp_angle(_head_yaw, _scan_yaw, minf(3.0 * delta, 1.0))
	velocity.x = desired.x
	velocity.z = desired.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	if desired.length() > 0.1:
		_open_doors_ahead(desired)
	move_and_slide()
	_push_props()
	_update_stuck(delta, desired)


## Room doors aren't in the navmesh, so paths go straight through them: open a closed one before
## walking into it (it swings away from the monster).
func _open_doors_ahead(desired: Vector3) -> void:
	var from := global_position + Vector3(0, 1.2, 0)
	var reach := DOOR_REACH + desired.length() * 0.35
	var q := PhysicsRayQueryParameters3D.create(from, from + desired.normalized() * reach, Prop.LAYER_DOORS, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is HingedDoor and not (hit.collider as HingedDoor).is_open:
		(hit.collider as HingedDoor).open_from(global_position)


## Looking around a room: the head sweeps to random angles and the body slowly turns after it.
func _update_scan(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = randf_range(1.0, 1.8)
		_scan_yaw = randf_range(-HEAD_YAW_MAX, HEAD_YAW_MAX)
		if absf(_scan_yaw - _head_yaw) < 0.5:
			_scan_yaw = (1.0 if _head_yaw <= 0.0 else -1.0) * randf_range(0.6, HEAD_YAW_MAX)
	rotation.y += _head_yaw * 0.6 * delta


func _update_model() -> void:
	_breath.volume_db = lerpf(_breath.volume_db, BREATH_DB[state] if active else -60.0, 0.04)
	var v := get_real_velocity()
	model.move_speed = Vector2(v.x, v.z).length()
	model.head_yaw = _head_yaw
	if _alert_timer > 0.0:
		model.pose = MonsterModel.Pose.ALERT
	elif _roar_timer > 0.0:
		model.pose = MonsterModel.Pose.ROAR
	elif _wait_timer > 0.0 and state != State.CHASE:
		model.pose = MonsterModel.Pose.LOOK
	else:
		model.pose = MonsterModel.Pose.NORMAL


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


## Called by the model on every heel strike, so the stomps match the walk cycle.
func _on_footstep(pos: Vector3, speed: float) -> void:
	if speed > 2.5:
		Sfx.play_3d(Sfx.MONSTER_RUN_STEPS.pick_random(), pos, -3.0, 26.0, randf_range(0.95, 1.05))
	else:
		Sfx.play_3d(Sfx.MONSTER_STEPS.pick_random(), pos, -8.0, 22.0, randf_range(0.95, 1.05))


func _check_catch() -> void:
	var d := global_position - player.global_position
	var flat := Vector2(d.x, d.z).length()
	var caught := false
	if player.is_hidden():
		var to_bed := global_position - _player_spot()
		caught = _saw_hide and Vector2(to_bed.x, to_bed.z).length() < HIDDEN_CATCH_DISTANCE
	else:
		caught = flat < CATCH_DISTANCE and absf(d.y) < 1.2 and _line_clear(_eye(), player.global_position + Vector3(0, 0.4, 0))
	if caught:
		active = false
		velocity = Vector3.ZERO
		model.move_speed = 0.0
		model.pose = MonsterModel.Pose.ATTACK
		caught_player.emit()
