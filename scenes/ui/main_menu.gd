extends Control
## Title screen.

const SettingsMenuScript := preload("res://scenes/ui/settings_menu.gd")

@onready var buttons: VBoxContainer = %Buttons


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%NewGame.pressed.connect(GameState.start_game.bind(GameState.Phase.MORNING))
	%StartNight.pressed.connect(GameState.start_game.bind(GameState.Phase.NIGHT))
	%SettingsButton.pressed.connect(_open_settings)
	%Quit.pressed.connect(get_tree().quit)
	%NewGame.grab_focus()


func _open_settings() -> void:
	buttons.visible = false
	var menu: SettingsMenu = SettingsMenuScript.new()
	add_child(menu)
	menu.closed.connect(func() -> void:
		buttons.visible = true
		%NewGame.grab_focus())
