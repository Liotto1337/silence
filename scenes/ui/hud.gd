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


const LID_EDGE := 56.0  ## the soft edge of an eyelid, in pixels

var _lid_top: ColorRect
var _lid_bottom: ColorRect


func _ready() -> void:
	_build_eyelids()
	title.move_to_front()  # stays readable over the fade
	fade.move_to_front()
	title.move_to_front()
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


## Eyelids closing from the top and the bottom of the screen (falling asleep): they droop, jerk
## half open once more, then shut for good. Await the tween's finished signal; `open_eyes()` puts
## them back.
func close_eyes(duration: float = 1.0) -> Tween:
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_method(_set_lids, 0.0, 0.42, duration * 0.3).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_lids, 0.42, 0.2, duration * 0.14).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_lids, 0.2, 1.0, duration * 0.56).set_ease(Tween.EASE_IN)
	return tw


func open_eyes() -> void:
	_set_lids(0.0)


## `amount` 0 = open, 1 = shut. (The anchors are set with keep_offset: the lids stay at offset 0.)
func _set_lids(amount: float) -> void:
	_lid_top.visible = amount > 0.001  # the soft edges would show as a gradient even when open
	_lid_bottom.visible = amount > 0.001
	_lid_top.set_anchor(SIDE_BOTTOM, 0.52 * amount, true)
	_lid_bottom.set_anchor(SIDE_TOP, 1.0 - 0.52 * amount, true)


## True while the eyelids cover the screen.
func eyes_closed() -> bool:
	return _lid_top.anchor_bottom >= 0.5 and _lid_bottom.anchor_top <= 0.5


func _build_eyelids() -> void:
	_lid_top = _make_lid(true)
	_lid_bottom = _make_lid(false)


## One eyelid: a black bar anchored to the top or the bottom edge, with a soft gradient edge.
func _make_lid(top: bool) -> ColorRect:
	var lid := ColorRect.new()
	lid.name = "LidTop" if top else "LidBottom"
	lid.color = Color.BLACK
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lid.visible = false
	lid.anchor_left = 0.0
	lid.anchor_right = 1.0
	lid.anchor_top = 0.0 if top else 1.0
	lid.anchor_bottom = 0.0 if top else 1.0
	lid.offset_left = 0.0
	lid.offset_right = 0.0
	lid.offset_top = 0.0
	lid.offset_bottom = 0.0
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = gradient
	gt.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
	gt.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
	gt.width = 4
	gt.height = 64
	var edge := TextureRect.new()
	edge.texture = gt
	edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	edge.stretch_mode = TextureRect.STRETCH_SCALE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.anchor_left = 0.0
	edge.anchor_right = 1.0
	edge.anchor_top = 1.0 if top else 0.0
	edge.anchor_bottom = 1.0 if top else 0.0
	edge.offset_top = 0.0 if top else -LID_EDGE
	edge.offset_bottom = LID_EDGE if top else 0.0
	lid.add_child(edge)
	$Root.add_child(lid)
	return lid


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
