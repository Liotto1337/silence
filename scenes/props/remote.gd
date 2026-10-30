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
	r.add_box_shape(Vector3(0.056, 0.024, 0.22), Vector3(0, 0.012, 0))
	r.add_model("remote", Vector3(0, 0, 0.22))
	r.add_step_trigger(0.12, func(_p: Player) -> void: r.press())
	r.impact_sounds = Sfx.PLASTIC
	r.place_sounds = Sfx.PLASTIC
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
