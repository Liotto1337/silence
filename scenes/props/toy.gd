class_name Toy
extends Prop
## A toy for the "tidy up your room" quest. Counted by the ToyBox.

enum Kind { BLOCK, BALL, TEDDY, CAR, PYRAMID }

const COLORS := [Color("d9483b"), Color("3b7dd9"), Color("e8c547"), Color("4bb36a"), Color("a45bd1")]


static func create(kind: Kind, color_index: int = 0) -> Toy:
	var t := Toy.new()
	t.add_to_group(&"toy")
	t.mass = 0.4
	var c: Color = COLORS[color_index % COLORS.size()]
	match kind:
		Kind.BLOCK:
			t.display_name = "Кубик"
			t.add_box(Vector3(0.18, 0.18, 0.18), c, Vector3(0, 0.09, 0))
		Kind.BALL:
			t.display_name = "Мячик"
			t.add_visual(Lowpoly.sphere(0.11, 8, 5), c, Vector3(0, 0.11, 0))
			t.add_sphere_shape(0.11, Vector3(0, 0.11, 0))
			var pm := PhysicsMaterial.new()
			pm.bounce = 0.4
			t.physics_material_override = pm
		Kind.TEDDY:
			t.display_name = "Плюшевый мишка"
			t.add_visual(Lowpoly.sphere(0.11, 7, 4), Color("8a5a35"), Vector3(0, 0.11, 0))
			t.add_visual(Lowpoly.sphere(0.075, 7, 4), Color("8a5a35"), Vector3(0, 0.27, 0))
			t.add_visual(Lowpoly.sphere(0.03, 5, 3), Color("6b4428"), Vector3(0.06, 0.33, 0))
			t.add_visual(Lowpoly.sphere(0.03, 5, 3), Color("6b4428"), Vector3(-0.06, 0.33, 0))
			t.add_sphere_shape(0.11, Vector3(0, 0.11, 0))
			t.add_sphere_shape(0.075, Vector3(0, 0.27, 0))
		Kind.CAR:
			t.display_name = "Машинка"
			t.add_box(Vector3(0.26, 0.08, 0.13), c, Vector3(0, 0.07, 0))
			t.add_box(Vector3(0.13, 0.06, 0.11), c.lightened(0.3), Vector3(-0.02, 0.14, 0), false)
			for x: float in [-0.08, 0.08]:
				for z: float in [-0.07, 0.07]:
					t.add_visual(Lowpoly.cylinder(0.035, 0.03, 6), Color("1d1d1d"), Vector3(x, 0.035, z), Vector3(PI / 2, 0, 0))
		Kind.PYRAMID:
			t.display_name = "Пирамидка"
			t.add_visual(Lowpoly.cylinder(0.11, 0.24, 5, 0.0), c, Vector3(0, 0.12, 0))
			t.add_cylinder_shape(0.08, 0.24, Vector3(0, 0.12, 0))
	return t
