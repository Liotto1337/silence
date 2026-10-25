class_name PauseMenu
extends CanvasLayer
## Esc menu while playing, and the end screen (caught / escaped).

const SettingsMenuScript := preload("res://scenes/ui/settings_menu.gd")

var _panel: Control
var _box: VBoxContainer
var _title: Label
var _subtitle: Label
var _ending: bool = false
var _settings_open: bool = false


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(360, 0)
	_box.add_theme_constant_override("separation", 12)
	center.add_child(_box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_box.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.modulate = Color(1, 1, 1, 0.7)
	_box.add_child(_subtitle)
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _ending or _settings_open:
		return
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if _panel.visible:
			resume()
		else:
			open_pause()


func open_pause() -> void:
	_show("Пауза", "", [
		["Продолжить", resume],
		["Настройки", _open_settings],
		["В главное меню", GameState.go_to_menu],
	])
	get_tree().paused = true


func resume() -> void:
	_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## End screen. `buttons`: [[text, callable], ...]
func show_end(title: String, subtitle: String, buttons: Array) -> void:
	_ending = true
	_show(title, subtitle, buttons)
	get_tree().paused = true


func _show(title: String, subtitle: String, buttons: Array) -> void:
	for c in _box.get_children():
		if c is Button:
			c.queue_free()
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""
	var first: Button
	for entry: Array in buttons:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		_box.add_child(b)
		if first == null:
			first = b
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if first:
		first.grab_focus.call_deferred()


func _open_settings() -> void:
	_settings_open = true
	_panel.visible = false
	var menu: SettingsMenu = SettingsMenuScript.new()
	add_child(menu)
	menu.closed.connect(func() -> void:
		_settings_open = false
		_panel.visible = true)
