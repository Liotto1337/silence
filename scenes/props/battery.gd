class_name Battery
extends Prop
## Flashlight battery. Interact to load it: the charge is refilled to the full minute.


static func create() -> Battery:
	var b := Battery.new()
	b.display_name = "Батарейка"
	b.mass = 0.1
	b.add_visual(Lowpoly.cylinder(0.022, 0.08, 6), Color("2e7d32"), Vector3(0, 0.022, 0), Vector3(0, 0, PI / 2))
	b.add_visual(Lowpoly.cylinder(0.01, 0.012, 6), Color("cfcfcf"), Vector3(0.046, 0.022, 0), Vector3(0, 0, PI / 2))
	b.add_cylinder_shape(0.022, 0.09, Vector3(0, 0.022, 0))
	(b.get_child(b.get_child_count() - 1) as CollisionShape3D).rotation = Vector3(0, 0, PI / 2)
	b.add_to_group(&"battery")
	return b


func get_prompt(player: Player) -> String:
	return "Вставить батарейку" if player.has_flashlight else "Батарейка (сначала найди фонарик)"


func interact(player: Player) -> void:
	if player.insert_battery():
		queue_free()
