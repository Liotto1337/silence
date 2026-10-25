extends Node
## Owns user settings: key bindings, mouse sensitivity, volume, VHS effect.
## Default bindings live here (not in project.godot) so "reset to defaults" has one source of truth.

signal changed

const PATH := "user://settings.cfg"

## Rebindable actions in menu order: action -> Russian label.
const ACTION_LABELS := {
	&"move_forward": "Вперёд",
	&"move_back": "Назад",
	&"move_left": "Влево",
	&"move_right": "Вправо",
	&"jump": "Прыжок",
	&"sprint": "Бег",
	&"crouch": "Присесть",
	&"grab": "Взять / нести предмет",
	&"throw": "Бросить предмет",
	&"interact": "Взаимодействовать",
	&"flashlight": "Фонарик",
}

## Binding format: {"key": physical_keycode} or {"mouse": button_index}.
const DEFAULT_BINDINGS := {
	&"move_forward": {"key": KEY_W},
	&"move_back": {"key": KEY_S},
	&"move_left": {"key": KEY_A},
	&"move_right": {"key": KEY_D},
	&"jump": {"key": KEY_SPACE},
	&"sprint": {"key": KEY_SHIFT},
	&"crouch": {"key": KEY_CTRL},
	&"grab": {"mouse": MOUSE_BUTTON_LEFT},
	&"throw": {"mouse": MOUSE_BUTTON_RIGHT},
	&"interact": {"key": KEY_E},
	&"flashlight": {"key": KEY_F},
}

## Fixed (non-rebindable) actions.
const FIXED_BINDINGS := {
	&"pause": {"key": KEY_ESCAPE},
	&"debug_overlay": {"key": KEY_F3},
	&"debug_skip_morning": {"key": KEY_F8},
}

var bindings: Dictionary = {}
var mouse_sensitivity: float = 0.25
var master_volume: float = 0.8
var vhs_enabled: bool = true
var fullscreen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bindings = DEFAULT_BINDINGS.duplicate(true)
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	vhs_enabled = bool(cfg.get_value("video", "vhs_enabled", vhs_enabled))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	for action: StringName in DEFAULT_BINDINGS:
		var saved: Variant = cfg.get_value("bindings", String(action), null)
		if saved is Dictionary and _is_valid_binding(saved):
			bindings[action] = saved


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "vhs_enabled", vhs_enabled)
	cfg.set_value("video", "fullscreen", fullscreen)
	for action: StringName in bindings:
		cfg.set_value("bindings", String(action), bindings[action])
	cfg.save(PATH)


func apply() -> void:
	for action: StringName in DEFAULT_BINDINGS:
		_bind(action, bindings[action])
	for action: StringName in FIXED_BINDINGS:
		_bind(action, FIXED_BINDINGS[action])
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	changed.emit()


## Rebinds an action. If another action already uses the same input, they swap bindings.
func rebind(action: StringName, binding: Dictionary) -> void:
	for other: StringName in bindings:
		if other != action and bindings[other] == binding:
			bindings[other] = bindings[action]
	bindings[action] = binding
	apply()
	save_settings()


func reset_bindings() -> void:
	bindings = DEFAULT_BINDINGS.duplicate(true)
	apply()
	save_settings()


## Converts a captured input event into a binding, or {} if it can't be bound.
func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_ESCAPE or code == KEY_NONE:
			return {}
		return {"key": code}
	if event is InputEventMouseButton and event.pressed:
		return {"mouse": event.button_index}
	return {}


func binding_text(binding: Dictionary) -> String:
	if binding.has("key"):
		var code: int = binding["key"]
		var label := DisplayServer.keyboard_get_label_from_physical(code) if DisplayServer.get_name() != "headless" else KEY_NONE
		return OS.get_keycode_string(label if label != KEY_NONE else code)
	match int(binding.get("mouse", 0)):
		MOUSE_BUTTON_LEFT: return "ЛКМ"
		MOUSE_BUTTON_RIGHT: return "ПКМ"
		MOUSE_BUTTON_MIDDLE: return "СКМ"
		var b: return "Мышь %d" % b


## Short label of whatever the action is bound to, for HUD prompts.
func action_text(action: StringName) -> String:
	return binding_text(bindings.get(action, FIXED_BINDINGS.get(action, {})))


func _bind(action: StringName, binding: Dictionary) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev: InputEvent
	if binding.has("key"):
		var key := InputEventKey.new()
		key.physical_keycode = int(binding["key"])
		ev = key
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = int(binding["mouse"])
		ev = mb
	InputMap.action_add_event(action, ev)


func _is_valid_binding(b: Dictionary) -> bool:
	return (b.has("key") and int(b["key"]) != KEY_NONE) or (b.has("mouse") and int(b["mouse"]) > 0)
