extends Node
## Cross-scene session state: which phase the game scene starts in, debug toggles.

enum Phase { MORNING, NIGHT }

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var start_phase: Phase = Phase.MORNING
var debug_overlay: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	Lowpoly.clear_cache()


func start_game(phase: Phase) -> void:
	start_phase = phase
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)
