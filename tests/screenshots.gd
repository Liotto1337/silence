extends Node
## Debug helper: renders views of the house to PNG (needs a display, e.g. xvfb-run).
## Output dir: env SHOT_DIR.

const VIEWS_MORNING := [
	["m_hero_room", Vector3(6.5, 1.62, 16.8), Vector3(4.0, 0.6, 12.0)],
	["m_kitchen", Vector3(8.8, 1.62, 6.0), Vector3(3.0, 0.8, 1.5)],
	["m_living", Vector3(12.0, 1.62, 6.0), Vector3(17.0, 0.8, 0.5)],
	["m_corridor", Vector3(1.0, 1.62, 8.25), Vector3(20.0, 1.0, 8.25)],
	["m_bath", Vector3(11.0, 1.62, 10.3), Vector3(13.5, 0.5, 17.0)],
	["m_entry", Vector3(17.0, 1.62, 10.5), Vector3(23.0, 1.0, 15.0)],
	["m_vent_room", Vector3(2.5, 0.7, 15.8), Vector3(2.5, 0.4, 18.5)],
	["m_duct", Vector3(2.5, 0.7, 18.6), Vector3(20.0, 0.5, 18.6)],
	["m_duct_fan", Vector3(8.0, 0.7, 19.0), Vector3(8.0, 0.5, 21.5)],
	["m_under_bed", Vector3(2.2, 0.72, 11.8), Vector3(0.7, 0.05, 11.7)],
]
const VIEWS_NIGHT := [
	["n_hero_room_dark", Vector3(3.0, 1.62, 13.0), Vector3(8.0, 1.0, 14.0), false],
	["n_corridor_flashlight", Vector3(1.0, 1.62, 8.25), Vector3(12.0, 1.0, 8.25), true],
	["n_monster", Vector3(14.0, 1.62, 3.0), Vector3(20.0, 1.2, 3.0), true],
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
	for v: Array in VIEWS_MORNING:
		await _shot(cam, v[1], v[2], dir + "/" + v[0] + ".png")
	# Night.
	game.quests.complete_morning_instantly()
	game._start_night()
	game.monster.active = false
	game.monster.global_position = Vector3(20.0, 0.05, 3.0)
	game.monster.rotation.y = -PI * 0.5
	player.add_item(Pickup.Item.FLASHLIGHT)
	await get_tree().create_timer(0.5).timeout
	for v: Array in VIEWS_NIGHT:
		player.flashlight_on = v[3]
		player.flashlight.visible = v[3]
		player.flashlight.light_energy = 2.2
		await _shot(cam, v[1], v[2], dir + "/" + v[0] + ".png")
	get_tree().quit()


func _shot(cam: Camera3D, pos: Vector3, target: Vector3, path: String) -> void:
	cam.top_level = true
	cam.global_position = pos
	cam.look_at(target)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
