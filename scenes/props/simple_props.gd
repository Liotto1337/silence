class_name SimpleProps
extends RefCounted
## Factories for plain carryable props (no special behaviour beyond Prop).


static func cereal_box() -> Prop:
	var p := Prop.new()
	p.display_name = "Пачка хлопьев"
	p.add_to_group(&"cereal")
	p.mass = 0.5
	p.add_box(Vector3(0.2, 0.3, 0.08), Color("e0892b"), Vector3(0, 0.15, 0))
	p.add_box(Vector3(0.12, 0.08, 0.002), Color("f4e04d"), Vector3(0, 0.2, 0.041), false)
	return p


static func milk() -> Prop:
	var p := Prop.new()
	p.display_name = "Молоко"
	p.add_to_group(&"milk")
	p.mass = 1.0
	p.add_box(Vector3(0.1, 0.22, 0.1), Color("f2f2f2"), Vector3(0, 0.11, 0))
	p.add_visual(Lowpoly.cylinder(0.07, 0.06, 4, 0.0), Color("3b6fd9"), Vector3(0, 0.25, 0), Vector3(0, PI / 4, 0))
	return p


static func vase(color: Color) -> Prop:
	var p := Prop.new()
	p.display_name = "Ваза"
	p.mass = 1.2
	p.add_visual(Lowpoly.cylinder(0.07, 0.12, 6, 0.1), color, Vector3(0, 0.06, 0))
	p.add_visual(Lowpoly.cylinder(0.1, 0.12, 6, 0.05), color, Vector3(0, 0.18, 0))
	p.add_visual(Lowpoly.cylinder(0.05, 0.06, 6, 0.06), color.darkened(0.2), Vector3(0, 0.27, 0))
	p.add_cylinder_shape(0.08, 0.3, Vector3(0, 0.15, 0))
	return p
