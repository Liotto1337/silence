extends Node
## Debug helper: plays the fall-asleep sequence in the real game scene and saves frames to PNG
## (needs a display). Run it with a fixed frame rate so that the timing does not depend on how slow
## saving is: godot --path . --fixed-fps 30 res://tests/sleep_shots.tscn
## Env SHOT_DIR: output dir. Env SHOT_EVERY: save every Nth frame (default 6).


func _ready() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	var every := maxi(int(OS.get_environment("SHOT_EVERY")), 1) if OS.get_environment("SHOT_EVERY") != "" else 6
	GameState.start_phase = GameState.Phase.MORNING
	var game: Node3D = (load(GameState.GAME_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(1.0).timeout
	var bed: Bed = game.house.hero_bed
	game.quests.complete_morning_instantly()
	# Where the player stands when they press E on the bed: in front of its open side.
	var spot := bed.global_transform * Vector3(0, 0.0, bed.width * 0.5 + 0.55)
	game.player.teleport(spot, bed.hide_yaw() + PI)
	await get_tree().create_timer(0.3).timeout
	game._on_bed(game.player)
	var blanket: SleepBlanket = game.player._sleep_blanket
	print("viewport %s, visible rect %s, window %s; the blanket sees %s m, its cloth is %.2f m wide" % [get_viewport().size, get_viewport().get_visible_rect().size, DisplayServer.window_get_size(), blanket.view, blanket.width])
	var frame := 0
	while game._busy:
		await RenderingServer.frame_post_draw
		if frame % every == 0:
			get_viewport().get_texture().get_image().save_png("%s/s_%04d.png" % [dir, frame])
		frame += 1
	print("sleep sequence: %d frames" % frame)
	get_tree().quit()
