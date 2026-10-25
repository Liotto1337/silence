extends Node3D
## Game loop: morning (chores, no monster) -> sleep -> night (stealth, monster, key, exit).

const MonsterScene := preload("res://scenes/monster/monster.tscn")

var phase: GameState.Phase = GameState.Phase.MORNING
var monster: Monster
var quests: Quests
var _busy: bool = false  # a fade / transition is running

@onready var house: House = $House
@onready var player: Player = $Player
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var world_env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	house.build()
	hud.bind_player(player)
	quests = Quests.new()
	quests.name = "Quests"
	add_child(quests)
	quests.setup(house, player)
	quests.objectives_changed.connect(hud.set_objectives)
	quests.message.connect(hud.show_message)
	house.hero_bed.prompt_provider = _bed_prompt
	house.hero_bed.interacted.connect(_on_bed)
	house.front_door.opened.connect(_on_escaped)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	hud.fade.color.a = 1.0
	if GameState.start_phase == GameState.Phase.NIGHT:
		quests.complete_morning_instantly()
		_start_night()
	else:
		_start_morning()
	hud.fade_to(0.0, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		GameState.debug_overlay = not GameState.debug_overlay
	elif event.is_action_pressed(&"debug_skip_morning") and OS.is_debug_build() and phase == GameState.Phase.MORNING and not _busy:
		quests.complete_morning_instantly()
		_go_to_night()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- phases -----------------------------------------------------------------

func _start_morning() -> void:
	phase = GameState.Phase.MORNING
	world_env.environment = _make_environment(false)
	house.set_lights_on(true)
	player.set_night(false)
	player.teleport(house.player_spawn_morning.origin, house.player_spawn_morning.basis.get_euler().y)
	quests.start_morning()
	hud.show_message("Утро. Мама просила приготовить завтрак и убрать игрушки.", 5.0)


func _start_night() -> void:
	phase = GameState.Phase.NIGHT
	world_env.environment = _make_environment(true)
	house.set_lights_on(false)
	house.tv.set_on(false)
	player.set_night(true)
	player.teleport(house.player_spawn_night.origin, house.player_spawn_night.basis.get_euler().y)

	var flashlight := Pickup.create(Pickup.Item.FLASHLIGHT)
	house.flashlight_spot.add_child(flashlight)
	flashlight.rotation.y = 0.6
	for spot in house.battery_spots:
		house.add_prop(Battery.create(), spot.global_position, randf() * TAU)
	# One key, hidden at a random spot among drawers, wardrobes and under the bed.
	var key_spot: Node3D = house.key_spots.pick_random()
	var key := Pickup.create(Pickup.Item.KEY)
	key_spot.add_child(key)
	key.rotation.y = randf() * TAU

	monster = MonsterScene.instantiate()
	add_child(monster)
	monster.global_position = house.monster_spawn
	monster.caught_player.connect(_on_caught)
	monster.activate(player, house.patrol_points)
	hud.monster = monster
	quests.start_night()
	hud.show_message("Что-то ходит по дому. Найди ключ и выберись. Тихо.", 5.0)


func _go_to_night() -> void:
	_busy = true
	player.set_controls_enabled(false)
	await hud.fade_to(1.0, 1.2).finished
	hud.show_title("Ночь")
	hud.set_gameplay_visible(false)
	_start_night()
	await get_tree().create_timer(2.0).timeout
	hud.show_title("")
	hud.set_gameplay_visible(true)
	await hud.fade_to(0.0, 1.5).finished
	player.set_controls_enabled(true)
	_busy = false


func _bed_prompt(_p: Player) -> String:
	if phase != GameState.Phase.MORNING:
		return ""
	return "Лечь спать" if quests.is_morning_done() else "Лечь спать (сначала дела)"


func _on_bed(_p: Player) -> void:
	if phase != GameState.Phase.MORNING or _busy:
		return
	if not quests.is_morning_done():
		hud.show_message("Рано спать: сначала завтрак и игрушки.")
		return
	_go_to_night()


func _on_caught() -> void:
	if _busy:
		return
	_busy = true
	player.set_controls_enabled(false)
	await hud.fade_to(1.0, 0.5).finished
	pause_menu.show_end("Тебя поймали", "Монстр нашёл тебя. Шуми меньше, прячься в вентиляции.", [
		["Попробовать снова", GameState.start_game.bind(GameState.Phase.NIGHT)],
		["В главное меню", GameState.go_to_menu],
	])


func _on_escaped() -> void:
	if _busy:
		return
	_busy = true
	player.set_controls_enabled(false)
	if monster:
		monster.active = false
	await hud.fade_to(1.0, 2.0).finished
	pause_menu.show_end("Ты выбрался", "Конец альфа-версии. Спасибо за тест!", [
		["Играть заново", GameState.start_game.bind(GameState.Phase.MORNING)],
		["В главное меню", GameState.go_to_menu],
	])


func _make_environment(night: bool) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.5
	if night:
		e.ambient_light_color = Color(0.3, 0.36, 0.55)
		e.ambient_light_energy = 0.07
		e.fog_enabled = true
		e.fog_light_color = Color(0.01, 0.01, 0.015)
		e.fog_density = 0.035
	else:
		e.ambient_light_color = Color(1.0, 0.93, 0.82)
		e.ambient_light_energy = 0.45
	return e
