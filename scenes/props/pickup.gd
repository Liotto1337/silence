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
			Models.add(p, "flashlight", Vector3(0, 0, 0.26), Vector3(0, -0.01, -0.03))
			Lowpoly.add_box_shape(p, Vector3(0.1, 0.1, 0.3), Vector3(0, 0.03, -0.03))
		Item.KEY:
			Models.add(p, "key", Vector3(0, 0, 0.13), Vector3(0, 0.0, 0.035))
			Lowpoly.add_box_shape(p, Vector3(0.14, 0.08, 0.2), Vector3(0, 0.02, 0.04))
	return p


func get_prompt(_player: Player) -> String:
	return "Взять фонарик" if item == Item.FLASHLIGHT else "Взять ключ"


func interact(player: Player) -> void:
	player.add_item(item)
	queue_free()
