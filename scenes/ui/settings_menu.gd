class_name SettingsMenu
extends Control
## Settings screen: sensitivity, volume, VHS effect, fullscreen and key rebinding.
## Built in code because the key list is generated from Settings.ACTION_LABELS.

signal closed

var _waiting_action: StringName = &""
var _bind_buttons: Dictionary = {}  # action -> Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	box.add_child(_header("Настройки", 28))
	box.add_child(_slider_row("Чувствительность мыши", 0.05, 1.0, Settings.mouse_sensitivity,
		func(v: float) -> void: Settings.mouse_sensitivity = v))
	box.add_child(_slider_row("Громкость", 0.0, 1.0, Settings.master_volume,
		func(v: float) -> void:
			Settings.master_volume = v
			Settings.apply()))
	box.add_child(_check_row("VHS-рябь", Settings.vhs_enabled,
		func(v: bool) -> void:
			Settings.vhs_enabled = v
			Settings.apply()))
	box.add_child(_check_row("Полный экран", Settings.fullscreen,
		func(v: bool) -> void:
			Settings.fullscreen = v
			Settings.apply()))

	box.add_child(_header("Управление", 22))
	var hint := Label.new()
	hint.text = "Нажми на кнопку и затем нужную клавишу или кнопку мыши. Esc — отмена."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for action: StringName in Settings.ACTION_LABELS:
		var l := Label.new()
		l.text = Settings.ACTION_LABELS[action]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 0)
		b.pressed.connect(_start_rebind.bind(action))
		grid.add_child(b)
		_bind_buttons[action] = b
	_refresh_bindings()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	var reset := Button.new()
	reset.text = "Сбросить управление"
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_refresh_bindings())
	buttons.add_child(reset)
	var back := Button.new()
	back.text = "Назад"
	back.pressed.connect(close)
	buttons.add_child(back)
	back.grab_focus.call_deferred()


func close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if _waiting_action == &"":
		if event.is_action_pressed(&"pause"):
			get_viewport().set_input_as_handled()
			close()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_waiting_action = &""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
		return
	var binding := Settings.binding_from_event(event)
	if binding.is_empty():
		return
	get_viewport().set_input_as_handled()
	Settings.rebind(_waiting_action, binding)
	_waiting_action = &""
	_refresh_bindings()


func _start_rebind(action: StringName) -> void:
	# Defer so the mouse click that pressed the button isn't captured as the new binding.
	await get_tree().process_frame
	_waiting_action = action
	_refresh_bindings()
	(_bind_buttons[action] as Button).text = "Нажми клавишу…"


func _refresh_bindings() -> void:
	for action: StringName in _bind_buttons:
		(_bind_buttons[action] as Button).text = Settings.action_text(action)


func _header(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	return l


func _slider_row(text: String, min_v: float, max_v: float, value: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(240, 24)
	s.value_changed.connect(on_change)
	row.add_child(s)
	return row


func _check_row(text: String, value: bool, on_change: Callable) -> Control:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(on_change)
	return c
