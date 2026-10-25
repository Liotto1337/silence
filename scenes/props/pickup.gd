class_name Pickup
extends StaticBody3D
## Inventory item (flashlight or key). Only these two can go into the inventory.

enum Item { FLASHLIGHT, KEY }

var item: Item


static func create(kind: Item) -> Pickup:
	var p := Pickup.new()
	p.item = kind
	# Own layer: interact ray hits it, but nobody collides with it and the navmesh ignores it.
	p.collision_layer = Prop.LAYER_PICKUPS
	p.collision_mask = 0
	match kind:
		Item.FLASHLIGHT:
			Lowpoly.add_mesh(p, Lowpoly.cylinder(0.025, 0.16, 7), Color("2b2b2b"), Vector3(0, 0.03, 0), Vector3(PI / 2, 0, 0))
			Lowpoly.add_mesh(p, Lowpoly.cylinder(0.038, 0.05, 7, 0.026), Color("3a3a3a"), Vector3(0, 0.03, -0.1), Vector3(-PI / 2, 0, 0))
			Lowpoly.add_mesh(p, Lowpoly.cylinder(0.032, 0.005, 7), Color("fff6c8"), Vector3(0, 0.03, -0.126), Vector3(PI / 2, 0, 0), 0.6)
			Lowpoly.add_box_shape(p, Vector3(0.1, 0.1, 0.3), Vector3(0, 0.03, -0.03))
		Item.KEY:
			var gold := Color("d4a72c")
			Lowpoly.add_mesh(p, Lowpoly.cylinder(0.03, 0.01, 6), gold, Vector3(0, 0.005, 0))
			Lowpoly.add_mesh(p, Lowpoly.box(Vector3(0.012, 0.008, 0.08)), gold, Vector3(0, 0.005, 0.065))
			Lowpoly.add_mesh(p, Lowpoly.box(Vector3(0.025, 0.008, 0.01)), gold, Vector3(0.012, 0.005, 0.095))
			Lowpoly.add_box_shape(p, Vector3(0.14, 0.08, 0.2), Vector3(0, 0.02, 0.04))
	return p


func get_prompt(_player: Player) -> String:
	return "Взять фонарик" if item == Item.FLASHLIGHT else "Взять ключ"


func interact(player: Player) -> void:
	player.add_item(item)
	queue_free()
