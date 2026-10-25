class_name Quests
extends Node
## Morning chores (breakfast, toys) and night goals (key, exit). Pushes objective text to the HUD.

signal objectives_changed(header: String, lines: PackedStringArray)
signal message(text: String)
signal morning_completed

const BREAKFAST_STEPS := [
	"Возьми пачку хлопьев",
	"Положи пачку в тарелку",
	"Открой холодильник",
	"Возьми молоко",
	"Положи молоко в тарелку",
]

var house: House
var player: Player
var night: bool = false

var cereal_grabbed: bool = false
var fridge_opened: bool = false
var milk_grabbed: bool = false
var cereal_in_bowl: bool = false
var milk_in_bowl: bool = false
var breakfast_done: bool = false
var toys_done: bool = false
var toys_total: int = 0
var toys_in_box: int = 0


func setup(h: House, p: Player) -> void:
	house = h
	player = p
	toys_total = house.toys.size()
	player.grabbed.connect(_on_grabbed)
	player.item_added.connect(func(_i: Pickup.Item) -> void: refresh())
	house.fridge_door.opened.connect(func() -> void:
		fridge_opened = true
		refresh())
	house.bowl_zone.contents_changed.connect(_on_bowl_changed)
	house.toy_zone.contents_changed.connect(_on_toys_changed)


func is_morning_done() -> bool:
	return breakfast_done and toys_done


func start_morning() -> void:
	night = false
	refresh()


func start_night() -> void:
	night = true
	refresh()


## Puts the house into the "chores done" state (used when a run starts directly at night).
func complete_morning_instantly() -> void:
	if not breakfast_done:
		for p: Prop in [house.cereal, house.milk]:
			if is_instance_valid(p):
				p.queue_free()
		house.fill_bowl()
		breakfast_done = true
	if not toys_done:
		var box := house.toy_zone.global_position
		for i in house.toys.size():
			var toy := house.toys[i]
			if is_instance_valid(toy):
				toy.global_position = box + Vector3((i % 3 - 1) * 0.15, 0.05 + (i / 3) * 0.2, 0.0)
				toy.linear_velocity = Vector3.ZERO
		toys_done = true
	refresh()


func refresh() -> void:
	var lines: PackedStringArray = []
	if night:
		if player.has_key:
			lines.append("[x] Найди ключ")
			lines.append("[ ] Выберись: открой входную дверь в прихожей")
		else:
			lines.append("[ ] Найди ключ — комоды, шкафы, под кроватью")
			lines.append("[ ] Найди выход")
		if not player.has_flashlight:
			lines.append("Фонарик лежит на твоём столе")
		lines.append("Не шуми.")
		objectives_changed.emit("Ночь", lines)
		return
	if breakfast_done:
		lines.append("[x] Приготовь завтрак")
	else:
		lines.append("[ ] Приготовь завтрак: %s" % BREAKFAST_STEPS[_breakfast_step()])
	if toys_done:
		lines.append("[x] Убери игрушки")
	else:
		lines.append("[ ] Убери игрушки в коробку — осталось: %d" % (toys_total - toys_in_box))
	if is_morning_done():
		lines.append("> Ложись спать (кровать в твоей комнате)")
	objectives_changed.emit("Утро", lines)


func _breakfast_step() -> int:
	var done := [
		cereal_grabbed or cereal_in_bowl,
		cereal_in_bowl,
		fridge_opened,
		milk_grabbed or milk_in_bowl,
		milk_in_bowl,
	]
	for i in done.size():
		if not done[i]:
			return i
	return done.size() - 1


func _on_grabbed(prop: Prop) -> void:
	if prop.is_in_group(&"cereal"):
		cereal_grabbed = true
	elif prop.is_in_group(&"milk"):
		milk_grabbed = true
	refresh()


func _on_bowl_changed() -> void:
	if breakfast_done:
		return
	cereal_in_bowl = house.bowl_zone.count_in_group(&"cereal") > 0
	milk_in_bowl = house.bowl_zone.count_in_group(&"milk") > 0
	if cereal_in_bowl and milk_in_bowl:
		# Two items in the bowl simply become a bowl of cereal. No animation — on purpose.
		for p in house.bowl_zone.get_in_group(&"cereal") + house.bowl_zone.get_in_group(&"milk"):
			if player.held == p:
				player.drop()
			p.queue_free()
		house.fill_bowl()
		breakfast_done = true
		message.emit("Завтрак готов!")
		_check_morning()
	refresh()


func _on_toys_changed() -> void:
	toys_in_box = house.toy_zone.count_in_group(&"toy")
	if not toys_done and toys_in_box >= toys_total:
		toys_done = true
		message.emit("Комната убрана!")
		_check_morning()
	refresh()


func _check_morning() -> void:
	if is_morning_done():
		message.emit("Все дела сделаны. Можно ложиться спать.")
		morning_completed.emit()
