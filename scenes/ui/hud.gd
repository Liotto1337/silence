class_name Hud
extends CanvasLayer
## In-game overlay: objectives, interaction prompt, stamina, flashlight charge, inventory, fades.

var player: Player
var monster: Monster

var _message_tween: Tween

@onready var crosshair: ColorRect = $Root/Crosshair
@onready var prompt: Label = $Root/Prompt
@onready var objectives_title: Label = $Root/Objectives/VBox/Title
@onready var objectives_lines: Label = $Root/Objectives/VBox/Lines
@onready var message_label: Label = $Root/Message
@onready var stamina_bar: ProgressBar = $Root/Stamina
@onready var key_slot: Label = $Root/Inventory/KeySlot
@onready var flashlight_slot: Control = $Root/Inventory/FlashlightSlot
@onready var gauge: RadialGauge = $Root/Inventory/FlashlightSlot/Gauge
@onready var debug_label: Label = $Root/Debug
@onready var title: Label = $Root/Title
@onready var fade: ColorRect = $Root/Fade


func _ready() -> void:
	title.move_to_front()  # stays readable over the fade
	key_slot.visible = false
	flashlight_slot.visible = false
	stamina_bar.max_value = Player.STAMINA_MAX


func bind_player(p: Player) -> void:
	player = p
	player.focus_changed.connect(_on_focus_changed)
	player.message.connect(show_message)
	player.item_added.connect(func(_i: Pickup.Item) -> void: _refresh_inventory())
	_refresh_inventory()


func set_objectives(header: String, lines: PackedStringArray) -> void:
	objectives_title.text = header
	objectives_lines.text = "\n".join(lines)


func show_message(text: String, duration: float = 3.0) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.6)


func show_title(text: String) -> void:
	title.text = text


## Tweens the black fade overlay to `alpha`; await the returned tween's finished signal.
func fade_to(alpha: float, duration: float = 1.0) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, duration)
	return tw


func set_gameplay_visible(v: bool) -> void:
	for n: CanvasItem in [crosshair, prompt, stamina_bar, $Root/Inventory, $Root/Objectives]:
		n.visible = v
	if v:
		_refresh_inventory()


func _process(_delta: float) -> void:
	if player == null:
		return
	stamina_bar.value = player.stamina
	stamina_bar.visible = crosshair.visible and player.stamina < Player.STAMINA_MAX - 0.5
	stamina_bar.modulate = Color(1, 0.45, 0.4) if player.exhausted else Color.WHITE
	if player.has_flashlight:
		gauge.value = player.battery / Player.BATTERY_SECONDS
		gauge.label = "%d" % ceili(player.battery)
		gauge.modulate.a = 1.0 if player.flashlight_on else 0.55
	debug_label.visible = GameState.debug_overlay
	if GameState.debug_overlay:
		var lines: PackedStringArray = ["FPS %d" % Engine.get_frames_per_second()]
		if is_instance_valid(monster):
			lines.append(monster.debug_text())
		lines.append("Стамина %d%s" % [player.stamina, " (выдохся)" if player.exhausted else ""])
		debug_label.text = "\n".join(lines)


func _refresh_inventory() -> void:
	if player == null:
		return
	key_slot.visible = player.has_key
	flashlight_slot.visible = player.has_flashlight


func _on_focus_changed(text: String) -> void:
	prompt.text = text
	crosshair.color = Color(1, 0.9, 0.5, 0.9) if text != "" else Color(1, 1, 1, 0.6)
