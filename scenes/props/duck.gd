class_name Duck
extends Prop
## Rubber bath duck: squeaks loudly when stepped on or dropped hard.

var _squeak_cooldown: float = 0.0


static func create() -> Duck:
	var d := Duck.new()
	d.display_name = "Резиновая уточка"
	d.mass = 0.2
	d.add_visual(Lowpoly.sphere(0.09, 8, 4), Color("ffd31a"), Vector3(0, 0.08, 0))
	d.add_visual(Lowpoly.sphere(0.06, 7, 4), Color("ffd31a"), Vector3(0.06, 0.18, 0))
	d.add_visual(Lowpoly.cylinder(0.025, 0.06, 4, 0.0), Color("ff7a1a"), Vector3(0.13, 0.18, 0), Vector3(0, 0, -PI / 2))
	d.add_visual(Lowpoly.sphere(0.012, 4, 3), Color("111111"), Vector3(0.1, 0.21, 0.035))
	d.add_visual(Lowpoly.sphere(0.012, 4, 3), Color("111111"), Vector3(0.1, 0.21, -0.035))
	d.add_sphere_shape(0.09, Vector3(0, 0.08, 0))
	d.add_step_trigger(0.12, func(_p: Player) -> void: d.squeak())
	return d


func _physics_process(delta: float) -> void:
	super(delta)
	_squeak_cooldown = maxf(_squeak_cooldown - delta, 0.0)


func squeak() -> void:
	if _squeak_cooldown > 0.0:
		return
	_squeak_cooldown = 0.8
	Sfx.play_3d(Sfx.SQUEAK, global_position, 4.0, 40.0, randf_range(0.95, 1.08))
	NoiseBus.emit_noise(global_position, NoiseBus.DUCK_SQUEAK, self)


func _on_impact(_speed: float) -> void:
	squeak()
