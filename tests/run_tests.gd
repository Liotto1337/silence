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
		if _reachable(map, house.monster_spawn, Vector3(13.0, 0, 4.5)):
			break
		await _frames(1)
	_check(house.navigation_mesh.get_polygon_count() > 50, "navmesh baked (%d polygons)" % house.navigation_mesh.get_polygon_count())
	for p: Vector3 in house.patrol_points:
		_check(_reachable(map, house.monster_spawn, p), "patrol point %s reachable from monster spawn" % p)
	for p: Vector3 in [Vector3(5, 0, 18.6), Vector3(13, 0, 18.6), Vector3(8, 0, 20.5), Vector3(-0.8, 0, 18.6)]:
		var closest := NavigationServer3D.map_get_closest_point(map, p)
		_check(Vector2(closest.x - p.x, closest.z - p.z).length() > 0.6, "vent duct %s is not on the monster navmesh" % p)
	_check(house.key_spots.size() == 12, "12 possible key spots (9 drawers, 2 wardrobes, under bed): %d" % house.key_spots.size())
	_check(house.battery_spots.size() == 5, "5 battery spots")
	_check(house.toys.size() == 7, "7 toys")

	print("--- vents: player crouched fits, standing / monster doesn't")
	var vent_in := Transform3D(Basis(), Vector3(2.5, 0.02, 17.2))
	player.global_transform = vent_in
	player._apply_height(Player.CROUCH_HEIGHT)
	_check(not player.test_move(vent_in, Vector3(0, 0, 1.4)), "crouched player can crawl into the vent")
	player._apply_height(Player.STAND_HEIGHT)
	_check(player.test_move(vent_in, Vector3(0, 0, 1.4)), "standing player can't enter the vent")
	player._apply_height(Player.CROUCH_HEIGHT)
	var in_duct := Transform3D(Basis(), Vector3(2.5, 0.02, 18.6))
	_check(not player.test_move(in_duct, Vector3(9.0, 0, 0)), "crouched player can crawl along the duct to the bathroom vent")
	_check(player.test_move(in_duct, Vector3(-5.0, 0, 0)), "west duct end is blocked by a fan")
	player._apply_height(Player.STAND_HEIGHT)
	player.teleport(house.player_spawn_morning.origin, 0.0)
	var probe: CharacterBody3D = (load("res://scenes/monster/monster.tscn") as PackedScene).instantiate()
	probe.set_script(null)
	probe.collision_layer = 0
	probe.collision_mask = 1
	_game.add_child(probe)
	probe.global_transform = vent_in
	_check(probe.test_move(vent_in, Vector3(0, 0, 1.4)), "monster body can't enter the vent")
	probe.queue_free()

	print("--- interaction: reach, carrying, drawers, noisy props")
	player.set_physics_process(false)
	var under_toy: Toy = house.toys[2]
	var toy_target := under_toy.global_position + Vector3(0, 0.06, 0)
	_pose(player, Vector3(2.1, 0.02, 11.6), Player.CROUCH_HEIGHT, toy_target)
	var hit := player._ray()
	_check(not hit.is_empty() and hit.collider == under_toy, "crouched: toy under the bed is reachable")
	var reachable_standing := false
	for dist: float in [0.9, 1.3, 1.7, 2.1]:
		_pose(player, Vector3(1.2 + dist, 0.02, 11.6), Player.STAND_HEIGHT, toy_target)
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
	var drawer_target := Vector3(7.0, 0.42, 7.56)
	_pose(player, Vector3(7.0, 0.02, 8.7), Player.STAND_HEIGHT, drawer_target)
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
	NoiseBus.noise_emitted.disconnect(rec)
	player.teleport(house.player_spawn_morning.origin, 0.0)
	await _frames(10)

	print("--- morning: breakfast")
	_check(house.fridge_door != null and not house.fridge_door.is_open, "fridge closed at start")
	house.fridge_door.interact(player)
	await _frames(30)
	_check(house.fridge_door.is_open and quests.fridge_opened, "fridge opens via interact")
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
	var box := house.toy_zone.global_position
	for i in house.toys.size():
		house.toys[i].global_position = box + Vector3((i % 3 - 1) * 0.15, 0.1 + (i / 3) * 0.22, 0)
		house.toys[i].linear_velocity = Vector3.ZERO
		await _frames(4)
	await _frames(30)
	_check(quests.toys_done, "all toys in box (%d/%d)" % [quests.toys_in_box, quests.toys_total])
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
	player.teleport(Vector3(4.5, 0.05, 16.5), 0.0)  # hero room, far from monster
	monster.global_position = Vector3(20.0, 0.05, 3.0)
	monster.rotation.y = 0.0
	await _frames(5)
	var noise_pos := Vector3(17.0, 0.1, 3.0)
	NoiseBus.emit_noise(noise_pos, 10.0, null)
	await _frames(2)
	_check(monster.state == Monster.State.SEARCH and monster.patience == 1 and monster._investigating, "1st noise: investigates, patience 1")
	NoiseBus.emit_noise(noise_pos, 10.0, null)
	_check(monster.patience == 2, "2nd noise: patience 2")
	NoiseBus.emit_noise(noise_pos, 10.0, null)
	_check(monster.state == Monster.State.HUNT, "3rd noise: HUNT")
	var hunt_target := monster.agent.target_position - player.global_position
	_check(Vector2(hunt_target.x, hunt_target.z).length() < 0.3, "hunt targets the player's position")
	var far := Vector3(0.0, 0.1, 0.0)
	monster._begin_sweep(monster.global_position)
	NoiseBus.emit_noise(Vector3(2.0, 0.1, 16.0), 3.0, null)
	_check(monster.patience == 0, "noise out of earshot is ignored")
	var dup_source := Node.new()
	add_child(dup_source)
	NoiseBus.emit_noise(noise_pos, 10.0, dup_source)
	NoiseBus.emit_noise(noise_pos, 10.0, dup_source)
	_check(monster.patience == 1, "repeated noise from one source within cooldown counts once")
	dup_source.queue_free()

	print("--- monster: goes to the TV and switches it off")
	monster._begin_sweep(monster.global_position)
	monster._wait_timer = 0.0
	monster.global_position = Vector3(13.0, 0.05, 4.5)
	player.teleport(Vector3(4.5, 0.05, 16.5), 0.0)
	house.tv.set_on(true)
	for i in 14:
		await _seconds(0.5)
		if OS.get_environment("DEBUG_TESTS") != "":
			print("    ", monster.debug_text(), " pos=", monster.global_position.snapped(Vector3.ONE * 0.1), " target=", monster.agent.target_position.snapped(Vector3.ONE * 0.1), " inv=", monster._investigating, " wait=", snappedf(monster._wait_timer, 0.1), " fin=", monster.agent.is_navigation_finished())
	_check(not house.tv.is_on, "monster switched the TV off")

	print("--- monster: sight -> chase -> catch")
	monster._begin_sweep(monster.global_position)
	monster.global_position = Vector3(12.0, 0.05, 8.25)
	monster.rotation.y = -PI * 0.5  # facing +X along the corridor
	player.teleport(Vector3(16.0, 0.05, 8.25), PI * 0.5)
	await _frames(3)
	_check(monster.state == Monster.State.CHASE, "player in sight -> CHASE")
	var caught := [false]
	monster.caught_player.connect(func() -> void: caught[0] = true)
	await _seconds(3.0)
	_check(caught[0], "monster catches a player standing still")
	_check(far != Vector3.ZERO, "")  # keep `far` used

	print("--- monster: player escapes into the vent")
	_game._busy = false
	_game.pause_menu._ending = false
	_game.pause_menu.resume()  # the catch above opened the end screen and paused the tree
	monster.active = true
	monster._begin_sweep(Vector3(5.0, 0, 13.0))
	monster._wait_timer = 0.0
	monster.global_position = Vector3(5.0, 0.05, 11.0)
	monster.rotation.y = PI  # facing +Z, into the hero room
	player.set_controls_enabled(true)
	player.teleport(Vector3(3.0, 0.05, 16.0), 0.0)
	await _frames(3)
	_check(monster.state == Monster.State.CHASE, "monster spots the player near the vent")
	player.set_physics_process(false)
	player._apply_height(Player.CROUCH_HEIGHT)
	player.crouching = true
	player.teleport(Vector3(9.0, 0.05, 18.6), 0.0)  # deep in the duct
	var escaped := false
	var caught_in_vent := [false]
	monster.caught_player.connect(func() -> void: caught_in_vent[0] = true)
	for i in 30:
		await _seconds(0.5)
		if monster.state == Monster.State.SEARCH:
			escaped = true
			break
	_check(escaped and not caught_in_vent[0], "monster can't follow into the vent and gives up (state %s)" % Monster.State.keys()[monster.state])
	_check(monster.global_position.z < 17.9, "monster stayed inside the house")

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
