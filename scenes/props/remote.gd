class_name TvRemote
extends Prop
## TV remote: stepping on it (or pressing interact) toggles the TV.

var tv: Tv
var _cooldown: float = 0.0


static func create(target_tv: Tv) -> TvRemote:
	var r := TvRemote.new()
	r.tv = target_tv
	r.display_name = "Пульт от телевизора"
	r.mass = 0.15
	r.add_box(Vector3(0.06, 0.025, 0.18), Color("1c1c1c"), Vector3(0, 0.0125, 0))
	r.add_box(Vector3(0.018, 0.006, 0.018), Color("c62828"), Vector3(0, 0.028, -0.06), false)
	for i in 3:
		r.add_box(Vector3(0.04, 0.005, 0.012), Color("555555"), Vector3(0, 0.027, -0.02 + i * 0.03), false)
	r.add_step_trigger(0.12, func(_p: Player) -> void: r.press())
	return r


func _physics_process(delta: float) -> void:
	super(delta)
	_cooldown = maxf(_cooldown - delta, 0.0)


func press() -> void:
	if _cooldown > 0.0 or tv == null:
		return
	_cooldown = 1.0
	tv.toggle()


func get_prompt(_player: Player) -> String:
	return "Нажать кнопку пульта"


func interact(_player: Player) -> void:
	press()
