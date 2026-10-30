class_name SimpleProps
extends RefCounted
## Factories for plain carryable props (no special behaviour beyond Prop).


static func cereal_box() -> Prop:
	var p := Prop.new()
	p.display_name = "Пачка хлопьев"
	p.add_to_group(&"cereal")
	p.mass = 0.5
	p.add_box_shape(Vector3(0.2, 0.3, 0.08), Vector3(0, 0.15, 0))
	p.add_model("cereal", Vector3(0.2, 0.3, 0.08))
	return p


static func milk() -> Prop:
	var p := Prop.new()
	p.display_name = "Молоко"
	p.add_to_group(&"milk")
	p.mass = 1.0
	p.add_box_shape(Vector3(0.1, 0.22, 0.1), Vector3(0, 0.11, 0))
	p.add_model("milk", Vector3(0.1, 0.22, 0.1))  # fits between the fridge shelves
	return p

