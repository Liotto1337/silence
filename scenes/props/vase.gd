class_name Vase
extends Prop
## Ceramic vase on a dresser. A light knock rings it; a hard hit (knocked off the dresser, dropped
## or thrown) shatters it into shards, which is one of the loudest noises in the house.

const BREAK_SPEED := 3.6  ## falling from the dresser top lands at ~4 m/s
const SHARDS := 7

var color: Color


static func create(c: Color) -> Vase:
	var p := Vase.new()
	p.color = c
	p.display_name = "Ваза"
	p.mass = 1.2
	p.add_visual(Lowpoly.cylinder(0.07, 0.12, 6, 0.1), c, Vector3(0, 0.06, 0))
	p.add_visual(Lowpoly.cylinder(0.1, 0.12, 6, 0.05), c, Vector3(0, 0.18, 0))
	p.add_visual(Lowpoly.cylinder(0.05, 0.06, 6, 0.06), c.darkened(0.2), Vector3(0, 0.27, 0))
	p.add_cylinder_shape(0.08, 0.3, Vector3(0, 0.15, 0))
	p.impact_sounds = Sfx.VASE_HIT
	p.place_sounds = Sfx.VASE_HIT
	return p


func _on_impact(speed: float) -> void:
	if speed < BREAK_SPEED:
		super(speed)
		return
	shatter(speed)


func shatter(speed: float = BREAK_SPEED) -> void:
	if is_queued_for_deletion():
		return
	Sfx.play_3d(Sfx.VASE_BREAK, global_position, 3.0, 35.0, randf_range(0.95, 1.05))
	NoiseBus.emit_noise(global_position, maxf(impact_noise_radius(speed), NoiseBus.IMPACT_MAX), self)
	var parent := get_parent()
	for i in SHARDS:
		var shard := RigidBody3D.new()
		shard.collision_layer = 0
		shard.collision_mask = LAYER_WORLD | LAYER_DOORS
		shard.mass = 0.1
		var size := Vector3(randf_range(0.04, 0.09), randf_range(0.015, 0.03), randf_range(0.04, 0.08))
		Lowpoly.add_mesh(shard, Lowpoly.box(size), color.darkened(randf() * 0.25))
		Lowpoly.add_box_shape(shard, size)
		parent.add_child(shard)
		var a := TAU * i / SHARDS
		shard.global_position = global_position + Vector3(cos(a) * 0.06, 0.08 + randf() * 0.1, sin(a) * 0.06)
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		shard.linear_velocity = Vector3(cos(a), randf_range(0.4, 1.2), sin(a)) * randf_range(0.8, 1.8)
		shard.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		# The pieces settle and freeze, so a dozen tiny bodies don't keep the physics busy.
		shard.get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(shard):
				shard.freeze = true)
	queue_free()
