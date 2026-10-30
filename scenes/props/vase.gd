class_name Vase
extends Prop
## Ceramic vase on a dresser. A light knock rings it; a hard hit (knocked off the dresser, dropped
## or thrown) shatters it into shards, which is one of the loudest noises in the house.

const BREAK_SPEED := 3.6  ## falling from the dresser top lands at ~4 m/s
const SIZE := Vector3(0.2, 0.3, 0.2)

var color: Color


static func create(c: Color) -> Vase:
	var p := Vase.new()
	p.color = c
	p.display_name = "Ваза"
	p.mass = 1.2
	p.add_model("vase", SIZE, Vector3.ZERO, 0.0, p._tint())
	p.add_cylinder_shape(0.08, 0.3, Vector3(0, 0.15, 0))
	p.impact_sounds = Sfx.VASE_HIT
	p.place_sounds = Sfx.VASE_HIT
	return p


## The terracotta model takes on a hint of this vase's colour.
func _tint() -> Color:
	return color.lerp(Color.WHITE, 0.55)


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
	# The shards are the vase model itself, cut into eight pieces (four around, two high).
	var parent := get_parent()
	var whole := Models.mesh("vase", SIZE, "", Vector3.ZERO, "", _tint())
	for half in 2:
		for quarter in 4:
			var lo := Vector3(-1.0 if quarter % 2 == 0 else 0.0, half * SIZE.y * 0.5 - (1.0 if half == 0 else 0.0), -1.0 if quarter < 2 else 0.0)
			var piece := Models.split(whole, AABB(lo, Vector3(1.0, SIZE.y * 0.5 + 1.0, 1.0)))[1]
			if piece.get_surface_count() == 0:
				continue
			var center := piece.get_aabb().get_center()
			var shard := RigidBody3D.new()
			shard.collision_layer = 0
			shard.collision_mask = LAYER_WORLD | LAYER_DOORS
			shard.mass = 0.1
			var mi := MeshInstance3D.new()
			mi.mesh = piece
			mi.position = -center
			shard.add_child(mi)
			Lowpoly.add_box_shape(shard, piece.get_aabb().size.clamp(Vector3(0.02, 0.02, 0.02), Vector3(0.1, 0.12, 0.1)))
			parent.add_child(shard)
			shard.global_position = global_transform * center
			shard.global_basis = global_basis
			var out := Vector3(center.x, 0.0, center.z).normalized()
			shard.linear_velocity = (out + Vector3(0, randf_range(0.4, 1.2), 0)) * randf_range(0.8, 1.8)
			shard.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
			# The pieces settle and freeze, so a dozen tiny bodies don't keep the physics busy.
			shard.get_tree().create_timer(4.0).timeout.connect(func() -> void:
				if is_instance_valid(shard):
					shard.freeze = true)
	queue_free()
