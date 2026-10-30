extends Node
## Debug helper: renders views of the house to PNG (needs a display, e.g. xvfb-run).
## Output dir: env SHOT_DIR. Optional env SHOT_ONLY: comma-separated view names to render (faster).

const VIEWS_MORNING := [
	["m_hero_room", Vector3(7.2, 1.62, 4.3), Vector3(2.0, 0.6, 1.5)],
	["m_hero_vent", Vector3(5.6, 0.7, 2.2), Vector3(5.6, 0.4, -0.5)],
	["m_living", Vector3(9.5, 1.62, 5.5), Vector3(2.0, 0.8, 8.5)],
	["m_hall", Vector3(10.0, 1.62, 9.0), Vector3(10.0, 1.0, 1.0)],
	["m_parents", Vector3(12.8, 1.62, 3.4), Vector3(19.0, 0.8, 2.0)],
	["m_kitchen", Vector3(4.2, 1.62, 13.8), Vector3(1.0, 0.8, 10.0)],
	["m_corridor", Vector3(5.2, 1.62, 10.5), Vector3(11.5, 1.0, 12.5)],
	["m_bath", Vector3(5.7, 1.62, 10.6), Vector3(5.6, 0.5, 14.0)],
	["m_duct", Vector3(5.6, 0.7, -0.6), Vector3(16.0, 0.5, -0.6)],
	["m_under_bed", Vector3(2.1, 0.72, 2.0), Vector3(0.6, 0.05, 2.1)],
	["m_hero_wall", Vector3(2.0, 1.6, 3.9), Vector3(6.5, 1.0, 0.2)],
	["m_closets", Vector3(10.6, 1.62, 4.6), Vector3(9.6, 0.9, 0.5)],
	["m_bath_vent", Vector3(6.4, 1.5, 11.9), Vector3(4.9, 0.4, 14.0)],
	["m_fridge_open", Vector3(2.6, 1.6, 12.6), Vector3(0.6, 1.0, 10.4)],
	["m_wc_door", Vector3(9.5, 1.62, 10.3), Vector3(7.0, 1.0, 11.8)],
	["m_wc", Vector3(7.8, 1.5, 11.6), Vector3(7.8, 0.4, 14.0)],
	["m_tv", Vector3(4.6, 1.3, 7.4), Vector3(4.6, 0.7, 9.6)],
]
const VIEWS_MONSTER := [
	["mon_front", Vector3(10.0, 1.6, 5.6), Vector3(10.0, 1.4, 2.6), MonsterModel.Pose.NORMAL, 0.0],
	["mon_side_walk", Vector3(11.8, 1.3, 4.2), Vector3(10.0, 1.2, 2.6), MonsterModel.Pose.NORMAL, 1.3],
	["mon_run", Vector3(11.4, 1.5, 4.4), Vector3(10.0, 1.3, 2.6), MonsterModel.Pose.NORMAL, 4.3],
	["mon_alert", Vector3(10.0, 1.7, 5.0), Vector3(10.0, 1.5, 2.6), MonsterModel.Pose.ALERT, 0.0],
	["mon_roar", Vector3(11.0, 1.6, 5.0), Vector3(10.0, 1.6, 2.6), MonsterModel.Pose.ROAR, 0.0],
	["mon_face", Vector3(10.0, 2.25, 3.6), Vector3(10.0, 2.25, 2.6), MonsterModel.Pose.NORMAL, 0.0],
	["mon_back", Vector3(9.4, 1.9, 1.7), Vector3(10.0, 1.6, 2.6), MonsterModel.Pose.NORMAL, 0.0],
	["mon_right_arm", Vector3(9.0, 1.3, 3.5), Vector3(9.7, 1.1, 2.5), MonsterModel.Pose.NORMAL, 0.0],
	["mon_legs", Vector3(10.6, 0.6, 3.6), Vector3(10.0, 0.35, 2.6), MonsterModel.Pose.NORMAL, 1.3],
]
const VIEWS_NIGHT := [
	["n_hero_room_dark", Vector3(1.8, 1.62, 2.2), Vector3(7.0, 1.0, 2.6), false],
	["n_hall_flashlight", Vector3(10.0, 1.62, 9.0), Vector3(10.0, 1.0, 1.0), true],
	["n_monster", Vector3(10.0, 1.62, 6.5), Vector3(10.0, 1.6, 2.6), true],
]


func _ready() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	GameState.start_phase = GameState.Phase.MORNING
	var game: Node3D = (load(GameState.GAME_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.5).timeout
	var player: Player = game.player
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var cam := player.camera
	for d in game.house.room_doors:
		d.open_from(d.global_position + d.global_basis.z)
	game.house.fridge_door.set_open(true)
	await get_tree().create_timer(0.5).timeout
	for v: Array in VIEWS_MORNING:
		if not _wanted(v[0]):
			continue
		await _shot(cam, v[1], v[2], dir + "/" + v[0] + ".png")
	# Monster close-ups in daylight (AI off, poses forced).
	var monster: Monster = (load("res://scenes/monster/monster.tscn") as PackedScene).instantiate()
	game.add_child(monster)
	monster.set_physics_process(false)  # AI off: the model plays whatever we set
	monster.global_position = Vector3(10.0, 0.05, 2.6)
	monster.rotation.y = PI  # facing south, towards the cameras
	for v: Array in VIEWS_MONSTER:
		if not _wanted(v[0]):
			continue
		monster.model.pose = v[3]
		monster.model.move_speed = v[4]
		await get_tree().create_timer(0.6).timeout
		await _shot(cam, v[1], v[2], dir + "/" + v[0] + ".png")
	monster.queue_free()
	# Night.
	game.quests.complete_morning_instantly()
	game._start_night()
	game.monster.active = false
	game.monster.global_position = Vector3(10.0, 0.05, 2.6)
	game.monster.rotation.y = PI
	player.add_item(Pickup.Item.FLASHLIGHT)
	await get_tree().create_timer(0.5).timeout
	for v: Array in VIEWS_NIGHT:
		if not _wanted(v[0]):
			continue
		player.flashlight_on = v[3]
		player.flashlight.visible = v[3]
		player.flashlight.light_energy = 2.2
		await _shot(cam, v[1], v[2], dir + "/" + v[0] + ".png")
	# Lying under the hero's bed, the monster standing in front of it.
	player.hide_under(game.house.hero_bed)
	game.monster.global_position = game.house.hero_bed.exit_position() + Vector3(0.9, 0, 0.3)
	cam.top_level = false
	cam.position = Vector3.ZERO
	cam.rotation = Vector3.ZERO
	player.flashlight_on = false
	player.flashlight.visible = false
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/n_under_bed.png")
	get_tree().quit()


func _wanted(view: String) -> bool:
	var only := OS.get_environment("SHOT_ONLY")
	return only.is_empty() or view in only.split(",")


func _shot(cam: Camera3D, pos: Vector3, target: Vector3, path: String) -> void:
	cam.top_level = true
	cam.global_position = pos
	cam.look_at(target)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
