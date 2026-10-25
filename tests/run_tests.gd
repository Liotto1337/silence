extends Node
## Headless smoke/integration tests for the alpha (run as a scene so autoloads are available).
## Run: godot --headless --path . res://tests/test_runner.tscn

var _failures: int = 0
var _game: Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameState.start_phase = GameState.Phase.MORNING
	_game = (load(GameState.GAME_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(_game)
	await _frames(10)
	var house: House = _game.house
	var player: Player = _game.player
	var quests: Quests = _game.quests

	print("--- level / navigation")
	var map := house.get_navigation_map()
	for i in 120:  # wait for the baked region to be synced into the map
		if _reachable(map, house.monster_spawn, house.patrol_points[0]):
			break
		await _frames(1)
	_check(house.navigation_mesh.get_polygon_count() > 50, "navmesh baked (%d polygons)" % house.navigation_mesh.get_polygon_count())
	for p: Vector3 in house.patrol_points:
		_check(_reachable(map, house.monster_spawn, p), "patrol point %s reachable from monster spawn" % p)
	for p: Vector3 in [Vector3(5.6, 0, -0.6), Vector3(10.5, 0, -0.6), Vector3(16.0, 0, -0.6), Vector3(-0.8, 0, -0.6),
			Vector3(1.4, 0, 14.8), Vector3(5.25, 0, 14.8), Vector3(8.5, 0, 14.8)]:
		var closest := NavigationServer3D.map_get_closest_point(map, p)
		_check(Vector2(closest.x - p.x, closest.z - p.z).length() > 0.6, "vent duct %s is not on the monster navmesh" % p)
	for p: Vector3 in [Vector3(8.75, 0, 1.6), Vector3(10.75, 0, 1.0)]:
		_check(_reachable(map, house.monster_spawn, p), "storage closet %s reachable for the monster" % p)
	_check(not house.balcony_door.get_prompt(player).begins_with("Открыть"), "balcony door is jammed")
	_check(house.key_spots.size() == 12, "12 possible key spots (9 drawers, 2 wardrobes, under bed): %d" % house.key_spots.size())
	_check(house.battery_spots.size() == 5, "5 battery spots")
	_check(house.toys.size() == 7, "7 toys")

	print("--- vents: player crouched fits, standing / monster doesn't")
	var vent_in := Transform3D(Basis(), Vector3(5.6, 0.02, 0.9))  # hero room, north vent
	player.global_transform = vent_in
	player._apply_height(Player.CROUCH_HEIGHT)
	_check(not player.test_move(vent_in, Vector3(0, 0, -1.4)), "crouched player can crawl into the hero room vent")
	player._apply_height(Player.STAND_HEIGHT)
	_check(player.test_move(vent_in, Vector3(0, 0, -1.4)), "standing player can't enter the vent")
	player._apply_height(Player.CROUCH_HEIGHT)
	var in_duct := Transform3D(Basis(), Vector3(5.6, 0.02, -0.6))
	_check(not player.test_move(in_duct, Vector3(10.4, 0, 0)), "north duct leads to the parents' room vent")
	_check(not player.test_move(Transform3D(Basis(), Vector3(16.0, 0.02, -0.6)), Vector3(0, 0, 1.5)), "crouched player can climb out into the parents' room")
	_check(player.test_move(in_duct, Vector3(-7.5, 0, 0)), "west end of the north duct is blocked by a fan")
	var kitchen_vent := Transform3D(Basis(), Vector3(1.4, 0.02, 13.4))
	_check(not player.test_move(kitchen_vent, Vector3(0, 0, 1.4)), "crouched player can crawl into the kitchen vent")
	_check(not player.test_move(Transform3D(Basis(), Vector3(1.4, 0.02, 14.8)), Vector3(3.85, 0, 0)), "south duct leads to the bathroom vent")
	_check(player.test_move(Transform3D(Basis(), Vector3(5.25, 0.02, 14.8)), Vector3(5.0, 0, 0)), "east end of the south duct is blocked by a fan")
	player._apply_height(Player.STAND_HEIGHT)
	player.teleport(house.player_spawn_morning.origin, 0.0)
	var probe: CharacterBody3D = (load("res://scenes/monster/monster.tscn") as PackedScene).instantiate()
	probe.set_script(null)
	probe.collision_layer = 0
	probe.collision_mask = 1
	_game.add_child(probe)
	probe.global_transform = vent_in
	_check(probe.test_move(vent_in, Vector3(0, 0, -1.4)), "monster body can't enter the vent")
	probe.queue_free()

	print("--- interaction: reach, carrying, drawers, noisy props")
	player.set_physics_process(false)
	var under_toy: Toy = house.toys[2]
	var toy_target := under_toy.global_position + Vector3(0, 0.06, 0)
	_pose(player, Vector3(2.0, 0.02, 1.8), Player.CROUCH_HEIGHT, toy_target)
	var hit := player._ray()
	_check(not hit.is_empty() and hit.collider == under_toy, "crouched: toy under the bed is reachable")
	var reachable_standing := false
	for dist: float in [0.9, 1.3, 1.7, 2.1]:
		_pose(player, Vector3(1.1 + dist, 0.02, 1.8), Player.STAND_HEIGHT, toy_target)
		var h := player._ray()
		if not h.is_empty() and h.collider == under_toy:
			reachable_standing = true
	_check(not reachable_standing, "standing: toy under the bed is out of reach")

	var floor_toy: Toy = house.toys[3]
	_pose(player, floor_toy.global_position + Vector3(0, 0, 1.3), Player.STAND_HEIGHT, floor_toy.global_position + Vector3(0, 0.08, 0))
	player._try_grab()
	_check(player.held == floor_toy and floor_toy.held, "grab picks up the prop under the crosshair")
	player.set_physics_process(true)
	await _frames(30)
	var hold_point := player.camera.global_position - player.camera.global_basis.z * player._hold_distance
	_check(floor_toy.global_position.distance_to(hold_point) < 0.4, "held prop follows the hold point")
	player.throw_held()
	_check(player.held == null and floor_toy.linear_velocity.length() > 4.0, "throw releases the prop with speed")
	player.set_physics_process(false)
	await _frames(60)

	var noises: Array = []
	var rec := func(pos: Vector3, radius: float, _src: Node) -> void: noises.append(radius)
	NoiseBus.noise_emitted.connect(rec)
	_check(noises.is_empty(), "")
	var drawer_target := Vector3(11.44, 0.42, 6.6)  # hall dresser, middle drawer
	_pose(player, Vector3(10.2, 0.02, 6.6), Player.STAND_HEIGHT, drawer_target)
	player._try_interact()
	await _frames(30)
	var drawer := player._ray().get("collider") as Object
	var opened := false
	for d in house.find_children("*", "Drawer", true, false):
		if (d as Drawer).is_open:
			opened = true
	_check(opened, "interact opens the drawer under the crosshair")

	var duck: Duck
	var remote: TvRemote
	for c in house.get_node("Props").get_children():
		if c is Duck:
			duck = c
		elif c is TvRemote:
			remote = c
	player.set_physics_process(true)
	player.teleport(duck.global_position + Vector3(0, 0.05, 0), 0.0)
	await _frames(6)
	_check(noises.has(NoiseBus.DUCK_SQUEAK), "stepping on the duck squeaks (noise radius %.0f)" % NoiseBus.DUCK_SQUEAK)
	_check(not house.tv.is_on, "TV off at start")
	player.teleport(remote.global_position + Vector3(0, 0.05, 0), 0.0)
	await _frames(6)
	_check(house.tv.is_on, "stepping on the remote turns the TV on")
	await _seconds(0.2)
	_check(noises.has(NoiseBus.TV), "TV emits noise")
	house.tv.set_on(false)

	print("--- doors")
	_check(house.room_doors.size() == 4, "4 unlocked room doors (2 closets, bathroom, WC)")
	var all_closed := true
	for d in house.room_doors:
		all_closed = all_closed and not d.is_open and d.collision_layer == Prop.LAYER_DOORS
	_check(all_closed, "room doors start closed, on the door layer (not baked into the navmesh)")
	var bath_door: HingedDoor = house.room_doors[2]
	player.teleport(Vector3(5.7, 0.05, 10.5), 0.0)  # corridor, north of the bathroom door
	player.force_update_transform()
	bath_door.interact(player)
	await _frames(30)
	_check(bath_door.is_open and bath_door.to_global(bath_door._panel_center).z > 11.8, "door opens away from the player (into the bathroom)")
	bath_door.interact(player)
	await _frames(30)
	player.teleport(Vector3(5.7, 0.05, 12.6), 0.0)  # inside the bathroom
	player.force_update_transform()
	bath_door.interact(player)
	await _frames(30)
	_check(bath_door.to_global(bath_door._panel_center).z < 11.0, "from the other side it swings into the corridor")
	bath_door.set_open(false)
	house.front_door.interact(player)
	_check(not house.front_door.is_open and house.front_door._locked_audio != null and house.front_door._locked_audio.playing, "locked front door rattles")
	await _frames(30)

	print("--- breakable vase, clockwork car")
	var vase: Vase
	for c in house.get_node("Props").get_children():
		if c is Vase:
			vase = c
			break
	noises.clear()
	vase.global_position = Vector3(10.0, 0.06, 5.0)
	vase.linear_velocity = Vector3.ZERO
	await _seconds(0.8)
	_check(is_instance_valid(vase) and noises.is_empty(), "a vase set down gently doesn't break or make noise")
	vase.global_position = Vector3(10.0, 0.6, 5.0)
	vase.linear_velocity = Vector3(0, -6.0, 0)
	await _seconds(0.5)
	_check(not is_instance_valid(vase) and noises.has(maxf(Prop.impact_noise_radius(6.0), NoiseBus.IMPACT_MAX)), "a hard hit shatters the vase: loud noise")
	var car: Toy = house.toys[6]
	_check(car.kind == Toy.Kind.CAR, "")
	noises.clear()
	car.global_position = Vector3(3.5, 0.6, 3.5)
	car.linear_velocity = Vector3(0, -2.0, 0)
	car.on_thrown()
	var rattled := false
	for i in 30:
		await _frames(2)
		rattled = rattled or car.is_rattling()
	_check(rattled and noises.has(Toy.RATTLE_NOISE), "a thrown car rattles on the floor and makes noise (%.0f m)" % Toy.RATTLE_NOISE)
	await _seconds(2.4)
	_check(not car.is_rattling(), "the rattle stops after the clockwork runs down")
	NoiseBus.noise_emitted.disconnect(rec)
	player.teleport(house.player_spawn_morning.origin, 0.0)
	await _frames(10)

	print("--- morning: breakfast")
	_check(house.fridge_door != null and not house.fridge_door.is_open, "fridge closed at start")
	house.fridge_door.interact(player)
	await _frames(30)
	_check(house.fridge_door.is_open and quests.fridge_opened, "fridge opens via interact")
	var fridge_tip := house.fridge_door.to_global(Vector3(-0.8, 1.0, 0.0))
	_check(fridge_tip.x > 0.15 and fridge_tip.z > 10.6, "open fridge door swings into the kitchen, not through the wall (%s)" % fridge_tip.snapped(Vector3.ONE * 0.01))
	var bowl_top := house.bowl_zone.global_position
	house.cereal.global_position = bowl_top + Vector3(-0.1, 0.0, 0)
	await _frames(20)
	_check(quests.cereal_in_bowl and not quests.breakfast_done, "cereal in bowl, waiting for milk")
	house.milk.global_position = bowl_top + Vector3(0.12, 0.0, 0)
	await _frames(20)
	_check(quests.breakfast_done, "milk + cereal turn into a bowl of cereal")
	_check(not is_instance_valid(house.cereal) and not is_instance_valid(house.milk), "cereal and milk removed")

	print("--- morning: toys")
	_check(quests.toys_in_box == 0, "toy box empty before quest")
	_check(not quests.toy_hint_on, "no toy hint at first")
	quests._toy_idle = Quests.TOY_HINT_DELAY
	await _frames(2)
	var lit := 0
	for t in house.toys:
		lit += 1 if t.highlighted else 0
	_check(quests.toy_hint_on and lit == house.toys.size(), "toys light up after %.0f s without progress (%d lit)" % [Quests.TOY_HINT_DELAY, lit])
	var box := house.toy_zone.global_position
	for i in house.toys.size():
		house.toys[i].global_position = box + Vector3((i % 3 - 1) * 0.15, 0.1 + (i / 3) * 0.22, 0)
		house.toys[i].linear_velocity = Vector3.ZERO
		await _frames(4)
	await _frames(30)
	_check(quests.toys_done, "all toys in box (%d/%d)" % [quests.toys_in_box, quests.toys_total])
	var still_lit := false
	for t in house.toys:
		still_lit = still_lit or t.highlighted
	_check(not quests.toy_hint_on and not still_lit, "the hint goes off once toys go into the box")
	_check(quests.is_morning_done(), "morning complete")

	print("--- inventory / flashlight")
	_check(not player.insert_battery(), "can't load a battery without flashlight")
	player.add_item(Pickup.Item.FLASHLIGHT)
	_check(player.has_flashlight and is_equal_approx(player.battery, Player.FLASHLIGHT_START_CHARGE), "flashlight starts with partial charge")
	player.battery = 12.0
	_check(player.insert_battery() and is_equal_approx(player.battery, Player.BATTERY_SECONDS), "new battery refills to a full minute")
	player.has_flashlight = false
	player.battery = 0.0

	print("--- sleep -> night")
	_game._on_bed(player)
	await _seconds(6.0)
	var monster: Monster = _game.monster
	_check(_game.phase == 1 and is_instance_valid(monster), "night started with a monster")
	_check(get_tree().get_nodes_in_group(&"battery").size() == 5, "5 batteries spawned")
	var keys := 0
	for spot in house.key_spots:
		for c in spot.get_children():
			if c is Pickup:
				keys += 1
	_check(keys == 1, "exactly one key hidden")
	_check(monster.active, "monster AI active")
	_check(not house.front_door.get_prompt(player).begins_with("Открыть"), "front door locked without key")

	print("--- monster: noise -> investigate -> hunt")
	var far_spot := Vector3(0.9, 0.05, 13.4)  # kitchen, far from the parents' room
	player.teleport(far_spot, 0.0)
	monster.global_position = Vector3(17.5, 0.05, 2.0)
	monster.rotation.y = 0.0
	await _frames(5)
	var noise_pos := Vector3(15.0, 0.1, 2.5)
	NoiseBus.emit_noise(noise_pos, 10.0, null)
	await _frames(2)
	_check(monster.state == Monster.State.SEARCH and monster.patience == 1 and monster._investigating, "1st noise: investigates, patience 1")
	NoiseBus.emit_noise(noise_pos, 10.0, null)
	_check(monster.patience == 2, "2nd noise: patience 2")
	NoiseBus.emit_noise(noise_pos, 10.0, null)
	_check(monster.state == Monster.State.HUNT, "3rd noise: HUNT")
	var hunt_target := monster.agent.target_position - player.global_position
	_check(Vector2(hunt_target.x, hunt_target.z).length() < 0.3, "hunt targets the player's position")
	await _frames(2)
	_check(monster.is_frozen() and monster.model.pose == MonsterModel.Pose.ROAR, "hunt starts with a roar on the spot")
	var roar_pos := monster.global_position
	await _seconds(0.9)
	_check(monster.global_position.distance_to(roar_pos) < 0.05, "stands still while roaring")
	await _seconds(1.2)
	_check(not monster.is_frozen() and monster.global_position.distance_to(roar_pos) > 0.3, "runs off after the roar")
	monster.global_position = Vector3(17.5, 0.05, 2.0)
	monster._begin_sweep(monster.global_position)
	NoiseBus.emit_noise(Vector3(2.0, 0.1, 12.0), 3.0, null)
	_check(monster.patience == 0, "noise out of earshot is ignored")
	var dup_source := Node.new()
	add_child(dup_source)
	NoiseBus.emit_noise(noise_pos, 10.0, dup_source)
	NoiseBus.emit_noise(noise_pos, 10.0, dup_source)
	_check(monster.patience == 1, "repeated noise from one source within cooldown counts once")
	dup_source.queue_free()

	print("--- monster: speed, room inspection, footsteps")
	_check(Monster.CHASE_SPEED < Player.SPRINT_SPEED and Monster.HUNT_SPEED < Monster.CHASE_SPEED and Monster.PATROL_SPEED < Player.WALK_SPEED, "monster is slower than the sprinting player")
	monster._begin_sweep(monster.global_position)
	_check(monster._wait_timer >= Monster.LOOK_TIME_SWEEP_START, "looks around before sweeping (%.1f s)" % monster._wait_timer)
	monster._investigating = false
	monster._sweep_queue.clear()
	monster._on_arrived()
	_check(monster._wait_timer >= Monster.LOOK_TIME_PATROL.x, "inspects a room for at least %.1f s after a patrol point" % Monster.LOOK_TIME_PATROL.x)
	await _frames(2)
	_check(monster.model.pose == MonsterModel.Pose.LOOK, "look-around animation while inspecting")
	var yaw_before := monster._head_yaw
	var sweep := 0.0
	for i in 15:
		await _seconds(0.1)
		sweep = maxf(sweep, absf(monster._head_yaw - yaw_before))
	_check(sweep > 0.2, "head sweeps while looking around (%.2f rad)" % sweep)
	var steps: Array[float] = []
	var on_step := func(_pos: Vector3, speed: float) -> void: steps.append(speed)
	monster.model.footstep.connect(on_step)
	monster._wait_timer = 0.0
	monster.global_position = Vector3(14.5, 0.05, 2.0)
	await _frames(1)
	monster._go_to(Vector3(10.0, 0, 8.3), Monster.PATROL_SPEED)  # parents' room -> hall
	var lowest_sole := INF
	var highest_stance := -INF
	for i in 180:
		await _frames(1)
		var soles: Array[float] = []
		for f in monster.model._foot:
			soles.append(f.global_position.y - MonsterModel.ANKLE - monster.global_position.y)
		lowest_sole = minf(lowest_sole, soles.min())
		highest_stance = maxf(highest_stance, soles.min())
	var walk_steps := steps.size()
	var expected := 3.0 * Monster.PATROL_SPEED / (0.8 + 0.18 * Monster.PATROL_SPEED)
	_check(walk_steps >= int(expected) - 1 and walk_steps <= int(expected) + 2, "footsteps follow the walk cycle (%d steps in 3 s, ~%.1f expected)" % [walk_steps, expected])
	_check(lowest_sole > -0.015 and highest_stance < 0.03, "feet don't sink into the floor while walking (lowest sole %.3f m, stance foot up to %.3f m)" % [lowest_sole, highest_stance])
	monster.model.footstep.disconnect(on_step)
	monster.active = false
	monster.global_position = Vector3(10.0, 0.05, 6.0)  # middle of the hall
	monster.rotation.y = 0.0  # body faces north
	monster.force_update_transform()
	player.teleport(Vector3(7.0, 0.05, 6.0), 0.0)  # to its left (west), in the living room
	player.force_update_transform()
	monster._head_yaw = PI * 0.5  # looking left
	var head_cone := monster._can_see_player()
	monster._head_yaw = 0.0
	_check(head_cone and not monster._can_see_player(), "vision cone follows the head")
	monster.global_position = Vector3(10.0, 0.05, 2.0)
	monster.rotation.y = PI  # facing south down the hall
	monster.force_update_transform()
	player.teleport(Vector3(10.0, 0.05, 9.0), 0.0)
	player.force_update_transform()
	var seen_far_dark := monster._can_see_player()
	player.flashlight_on = true
	var seen_far_lit := monster._can_see_player()
	player.teleport(Vector3(10.0, 0.05, 13.6), 0.0)
	player.force_update_transform()
	var seen_very_far_lit := monster._can_see_player()
	player.flashlight_on = false
	player.teleport(Vector3(10.0, 0.05, 5.5), 0.0)
	player.force_update_transform()
	_check(not seen_far_dark and seen_far_lit and not seen_very_far_lit and monster._can_see_player(),
			"sight range: %.0f m in the dark, %.0f m with the flashlight on" % [Monster.SIGHT_RANGE_DARK, Monster.SIGHT_RANGE_LIT])
	var wc_door: HingedDoor = house.room_doors[3]
	monster.global_position = Vector3(7.8, 0.05, 10.3)
	monster.force_update_transform()
	player.teleport(Vector3(7.8, 0.05, 12.8), 0.0)  # in the WC, door closed
	player.force_update_transform()
	var through_closed := monster._can_see_player()
	wc_door.set_open(true)
	await _frames(30)
	_check(not through_closed and monster._can_see_player(), "a closed door blocks sight, an open one doesn't")
	wc_door.set_open(false)
	await _frames(30)
	player.teleport(far_spot, 0.0)
	monster.active = true
	monster._begin_sweep(monster.global_position)

	print("--- monster: goes to the TV and switches it off")
	monster._begin_sweep(monster.global_position)
	monster._wait_timer = 0.0
	monster.global_position = Vector3(10.0, 0.05, 4.0)
	player.teleport(Vector3(7.0, 0.05, 0.6), 0.0)  # hero room corner, out of sight of the TV
	house.tv.set_on(true)
	for i in 30:
		await _seconds(0.5)
		if OS.get_environment("DEBUG_TESTS") != "":
			print("    ", monster.debug_text(), " pos=", monster.global_position.snapped(Vector3.ONE * 0.1), " target=", monster.agent.target_position.snapped(Vector3.ONE * 0.1), " inv=", monster._investigating, " wait=", snappedf(monster._wait_timer, 0.1), " fin=", monster.agent.is_navigation_finished())
		if not house.tv.is_on:
			break
	_check(not house.tv.is_on, "monster switched the TV off")

	print("--- monster: opens a closed door on its way")
	monster._begin_sweep(monster.global_position)
	monster._sweep_queue.clear()
	monster._wait_timer = 0.0
	monster.global_position = Vector3(7.8, 0.05, 10.4)  # corridor, in front of the closed WC door
	_check(not wc_door.is_open, "")
	monster._go_to(Vector3(7.8, 0, 12.8), Monster.PATROL_SPEED)
	await _seconds(4.0)
	_check(wc_door.is_open and monster.global_position.z > 11.8, "monster opens the WC door and walks in (z %.1f)" % monster.global_position.z)
	wc_door.set_open(false)

	print("--- monster: sight -> freeze facing the player -> chase -> catch")
	monster._begin_sweep(monster.global_position)
	monster.global_position = Vector3(10.0, 0.05, 2.8)  # hall, facing south
	monster.rotation.y = PI + 0.6  # not quite facing the player
	monster._wait_timer = 0.0
	monster._head_yaw = 0.0
	player.teleport(Vector3(10.0, 0.05, 7.0), 0.0)
	await _frames(3)
	_check(monster.state == Monster.State.CHASE and monster.is_frozen(), "player in sight -> CHASE, freezes first")
	var caught := [false]
	monster.caught_player.connect(func() -> void: caught[0] = true)
	var spot_pos := monster.global_position
	await _seconds(0.7)
	var to_player := player.global_position - monster.global_position
	var facing := (-monster.global_basis.z).dot(Vector3(to_player.x, 0, to_player.z).normalized())
	_check(monster.global_position.distance_to(spot_pos) < 0.05 and facing > 0.97, "turns to face the player and waits (facing %.2f)" % facing)
	_check(monster.model.pose == MonsterModel.Pose.ALERT, "alert animation while staring")
	await _seconds(0.5)
	_check(not monster.is_frozen() and monster.global_position.distance_to(spot_pos) > 0.2, "after ~1 s it starts running")
	await _seconds(2.5)
	_check(caught[0], "monster catches a player standing still")

	print("--- monster: player escapes into the vent")
	_game._busy = false
	_game.pause_menu._ending = false
	_game.pause_menu.resume()  # the catch above opened the end screen and paused the tree
	monster.active = true
	monster._begin_sweep(Vector3(4.0, 0, 3.0))
	monster._wait_timer = 0.0
	monster.global_position = Vector3(4.5, 0.05, 4.0)
	monster.rotation.y = 0.0  # facing north, towards the vent
	player.set_controls_enabled(true)
	player.teleport(Vector3(5.6, 0.05, 1.0), 0.0)
	await _frames(3)
	_check(monster.state == Monster.State.CHASE, "monster spots the player near the vent")
	player.set_physics_process(false)
	player._apply_height(Player.CROUCH_HEIGHT)
	player.crouching = true
	player.teleport(Vector3(8.0, 0.05, -0.6), 0.0)  # deep in the north duct
	var escaped := false
	var caught_in_vent := [false]
	monster.caught_player.connect(func() -> void: caught_in_vent[0] = true)
	for i in 44:
		await _seconds(0.5)
		if monster.state == Monster.State.SEARCH:
			escaped = true
			break
	_check(escaped and not caught_in_vent[0], "monster can't follow into the vent and gives up (state %s)" % Monster.State.keys()[monster.state])
	_check(monster.global_position.z > 0.05, "monster stayed inside the house")
	player.set_physics_process(true)
	player.crouching = false

	print("--- hiding under the bed")
	var bed := house.hero_bed
	player._apply_height(Player.STAND_HEIGHT)
	player.teleport(bed.exit_position(), 0.0)
	_check(not bed.get_prompt(player).contains("кровать"), "")
	player.crouching = true
	_check(bed.get_prompt(player) == "Залезть под кровать", "crouched: the bed offers hiding under it")
	monster._begin_sweep(monster.global_position)
	monster._sweep_queue.clear()
	monster._wait_timer = 0.0
	monster.global_position = Vector3(4.5, 0.05, 1.5)
	monster.rotation.y = -PI * 0.5  # facing east, away from the bed
	await _frames(2)
	player.crouching = true
	bed.interact(player)
	_check(player.is_hidden() and player.global_position.distance_to(bed.hide_position()) < 0.05, "interact while crouched: hides under the bed")
	var caught_hidden := [false]
	monster.caught_player.connect(func() -> void: caught_hidden[0] = true)
	monster._go_to(bed.exit_position(), Monster.PATROL_SPEED)
	await _seconds(4.0)
	var d_bed := monster.global_position - bed.exit_position()
	_check(not caught_hidden[0] and monster.state != Monster.State.CHASE and Vector2(d_bed.x, d_bed.z).length() < Monster.HIDDEN_CATCH_DISTANCE,
			"the monster walks right up to the bed and doesn't notice the hidden player")
	monster._begin_sweep(monster.global_position)
	monster._sweep_queue.clear()
	monster._wait_timer = 10.0
	monster.global_position = Vector3(4.0, 0.05, 1.5)
	player.leave_hiding()
	_check(not player.is_hidden() and player.crouching, "interact again: crawls out, crouched")
	var to_bed := player.global_position - monster.global_position
	monster.rotation.y = atan2(-to_bed.x, -to_bed.z)
	await _frames(3)
	_check(monster.state == Monster.State.CHASE, "monster spots the player by the bed")
	player.hide_under(bed)
	for i in 20:
		await _seconds(0.25)
		if caught_hidden[0]:
			break
	_check(caught_hidden[0], "hiding in front of the monster doesn't work: it pulls the player out")
	await _seconds(1.0)  # let the catch fade finish and open the end screen
	_game._busy = false
	_game.pause_menu._ending = false
	_game.pause_menu.resume()
	player.leave_hiding()
	player.set_controls_enabled(true)
	player.crouching = false

	print("--- player footsteps follow the step cycle")
	monster.active = false
	player._apply_height(Player.STAND_HEIGHT)
	player.teleport(Vector3(10.0, 0.05, 2.5), PI)  # hall, facing south
	var sprint_noises: Array[float] = []
	var rec_sprint := func(_pos: Vector3, radius: float, src: Node) -> void:
		if src == player:
			sprint_noises.append(radius)
	NoiseBus.noise_emitted.connect(rec_sprint)
	Input.action_press(&"move_forward")
	await _seconds(1.2)
	_check(player.step_player.stream in Sfx.WALK_STEPS and sprint_noises.is_empty(), "walking plays quiet steps and makes no noise")
	player.teleport(Vector3(10.0, 0.05, 2.5), PI)
	Input.action_press(&"sprint")
	await _seconds(1.6)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	var expected_steps := 1.6 * Player.SPRINT_SPEED / Player.SPRINT_STEP_LENGTH
	_check(player.step_player.stream in Sfx.RUN_STEPS and sprint_noises.size() >= int(expected_steps) - 2 and sprint_noises.size() <= int(expected_steps) + 1,
			"sprinting: one run step + noise per stride (%d in 1.6 s, ~%.1f expected)" % [sprint_noises.size(), expected_steps])
	NoiseBus.noise_emitted.disconnect(rec_sprint)
	_check(_game._ambient_timer > 0.0 and Sfx.AMBIENT.size() == 3, "random night ambience is scheduled")

	print("--- settings")
	var settings: Node = Settings
	var old_interact: Dictionary = settings.bindings[&"interact"]
	settings.rebind(&"jump", old_interact)
	_check(settings.bindings[&"jump"] == old_interact and settings.bindings[&"interact"] == {"key": KEY_SPACE}, "rebinding to a used key swaps the two")
	settings.reset_bindings()
	_check(settings.bindings[&"interact"] == {"key": KEY_E}, "reset restores defaults")

	print("")
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	get_tree().paused = false
	get_tree().quit(1 if _failures > 0 else 0)


## Places the player with a given capsule height and aims the camera at target.
func _pose(player: Player, feet: Vector3, height: float, target: Vector3) -> void:
	player.global_position = feet
	player._apply_height(height)
	player.crouching = height < Player.STAND_HEIGHT
	player.head.position.y = height - Player.EYE_FROM_TOP
	var cam := feet + Vector3(0, height - Player.EYE_FROM_TOP, 0)
	var d := target - cam
	player._yaw = atan2(-d.x, -d.z)
	player.rotation = Vector3(0, player._yaw, 0)
	player._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	player.head.rotation.x = player._pitch
	player.force_update_transform()
	player.camera.force_update_transform()


func _reachable(map: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 0 and Vector2(path[-1].x - to.x, path[-1].z - to.z).length() < 0.6


func _check(cond: bool, label: String) -> void:
	if label == "":
		return
	if cond:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
