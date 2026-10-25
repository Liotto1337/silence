class_name House
extends NavigationRegion3D
## Builds the whole house from primitives at runtime and bakes the monster's navmesh.
##
## Plan (metres, X → east, Z → south; door/vent offsets are centres):
##
##   z=0  +------------------+----------------------------+
##        | KITCHEN          |  LIVING ROOM               |
##        | fridge, table    D  bed, TV                   |
##   z=7  +--D---------------+----------------------D-----+
##        | CORRIDOR  (dressers with vases and mirrors)   |
##  z=9.5 +------D-----+--D--+-----D--------------D-------+
##        | HERO ROOM  | BATH|  ENTRY HALL            [front door]
##        | (dead end) |(dead|                              |
##        |            | end)|                              |
##   z=18 +--V---------+--V--+------------V----------------+
##        |  vent duct (crouch only), fans at every dead end  |
##
## Loops: corridor <-> kitchen <-> living room <-> corridor, and corridor <-> entry hall (two openings).
## Dead ends: hero room and bathroom — both have a vent the monster can't fit into.

const H := 2.8  ## wall height
const T := 0.2  ## wall thickness
const DOOR_W := 1.2
const DOOR_H := 2.5
const VENT_W := 0.9
const VENT_H := 1.0
const DUCT_Z0 := 18.1
const DUCT_Z1 := 19.1
const DUCT_X0 := -1.2
const DUCT_X1 := 25.2
const BRANCH_X := 8.0
const BRANCH_Z1 := 21.5

const C_WALL := Color("b7a48a")
const C_WALL_TRIM := Color("8c7a62")
const C_WOOD := Color("7a5636")
const C_WOOD_DARK := Color("4e3622")
const C_METAL := Color("80868c")
const C_WHITE := Color("e8e6e0")
const C_FABRIC := Color("5d6f8f")

# --- references for gameplay code -------------------------------------------
var fridge_door: HingedDoor
var bowl: StaticBody3D
var bowl_zone: ItemZone
var toy_zone: ItemZone
var tv: Tv
var hero_bed: Interactable
var front_door: HingedDoor
var key_spots: Array[Node3D] = []
var battery_spots: Array[Node3D] = []
var flashlight_spot: Node3D
var patrol_points: Array[Vector3] = []
var toys: Array[Toy] = []
var cereal: Prop
var milk: Prop
var lamp_light: OmniLight3D

var player_spawn_morning := Transform3D(Basis(Vector3.UP, PI * 0.75), Vector3(3.0, 0.05, 12.6))
var player_spawn_night := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(1.75, 0.05, 12.0))
var monster_spawn := Vector3(22.0, 0.05, 2.0)

var _room_lights: Array[OmniLight3D] = []
var _fixtures: Array[MeshInstance3D] = []
var _props_root: Node3D


func build() -> void:
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	_build_shell()
	_build_duct()
	_build_kitchen()
	_build_living_room()
	_build_corridor()
	_build_hero_room()
	_build_bathroom()
	_build_entry_hall()
	_build_patrol_points()
	_bake_navmesh()


func set_lights_on(on: bool) -> void:
	for l in _room_lights:
		l.visible = on
	for f in _fixtures:
		f.material_override = Lowpoly.mat(Color("fff1c9"), 0.5, 0.0, 3.0) if on else Lowpoly.mat(Color("6b665c"))
	lamp_light.visible = on


func add_prop(prop: Node3D, pos: Vector3, yaw: float = 0.0) -> Node3D:
	prop.position = pos
	prop.rotation.y = yaw
	_props_root.add_child(prop)
	return prop


# --- shell ------------------------------------------------------------------

func _build_shell() -> void:
	var shell := _group("Shell")
	# Floors per room (top surface at y = 0).
	_floor(shell, Rect2(0, 0, 10, 7), Color("8e9aa1"))  # kitchen tiles
	_floor(shell, Rect2(10, 0, 14, 7), Color("6b4a32"))  # living room wood
	_floor(shell, Rect2(0, 7, 24, 2.5), Color("5a4636"))  # corridor
	_floor(shell, Rect2(0, 9.5, 9, 8.5), Color("46607d"))  # hero room carpet
	_floor(shell, Rect2(9, 9.5, 6, 8.5), Color("cfd8dc"))  # bathroom tiles
	_floor(shell, Rect2(15, 9.5, 9, 8.5), Color("5d5148"))  # entry hall
	# Ceiling.
	_box(shell, Vector3(24.4, 0.1, 18.4), Vector3(12, H + 0.05, 9), Color("d9d4c8"))

	# Exterior walls.
	_wall_x(shell, 0.0, -0.1, 24.1, [])
	_wall_x(shell, 18.0, -0.1, 24.1, [[2.5, VENT_W, VENT_H], [11.8, VENT_W, VENT_H], [20.5, VENT_W, VENT_H]])
	_wall_z(shell, 0.0, 0.0, 18.0, [])
	_wall_z(shell, 24.0, 0.0, 18.0, [[13.5, DOOR_W, DOOR_H]])
	# Interior walls.
	_wall_z(shell, 10.0, 0.0, 7.0, [[3.5, DOOR_W, DOOR_H]])  # kitchen | living
	_wall_x(shell, 7.0, 0.0, 24.0, [[2.5, DOOR_W, DOOR_H], [21.0, DOOR_W, DOOR_H]])  # rooms | corridor
	_wall_x(shell, 9.5, 0.0, 24.0, [[6.0, DOOR_W, DOOR_H], [10.8, DOOR_W, DOOR_H], [16.3, 1.4, DOOR_H], [22.7, 1.4, DOOR_H]])
	_wall_z(shell, 9.0, 9.5, 18.0, [])  # hero room | bathroom
	_wall_z(shell, 15.0, 9.5, 18.0, [])  # bathroom | entry hall

	# Vent openings: frame on the room side and the removed grate leaning next to it.
	for x: float in [2.5, 11.8, 20.5]:
		_vent_frame(shell, x)

	# Front door (locked until the player has the key).
	front_door = HingedDoor.new()
	front_door.name = "FrontDoor"
	front_door.position = Vector3(24.0, 0.0, 12.9)
	front_door.rotation.y = -PI * 0.5
	front_door.open_angle = deg_to_rad(-100)
	front_door.open_prompt = "Открыть входную дверь"
	front_door.close_prompt = ""
	front_door.locked_prompt = "Заперто. Нужен ключ"
	front_door.can_open = func(p: Player) -> bool: return p.has_key
	front_door.build_panel(Vector3(1.2, DOOR_H, 0.08), Color("5b3a24"), false)
	shell.add_child(front_door)


func _vent_frame(parent: Node3D, x: float) -> void:
	var z := 18.0 - T * 0.5 - 0.02
	var c := Color("9aa0a6")
	_mesh(parent, Lowpoly.box(Vector3(VENT_W + 0.12, 0.06, 0.04)), c, Vector3(x, VENT_H + 0.03, z))
	_mesh(parent, Lowpoly.box(Vector3(0.06, VENT_H, 0.04)), c, Vector3(x - VENT_W * 0.5 - 0.03, VENT_H * 0.5, z))
	_mesh(parent, Lowpoly.box(Vector3(0.06, VENT_H, 0.04)), c, Vector3(x + VENT_W * 0.5 + 0.03, VENT_H * 0.5, z))
	# The removed grate leans against the wall next to the opening.
	var grate := Node3D.new()
	grate.position = Vector3(x + VENT_W * 0.5 + 0.6, 0.0, z - 0.22)
	grate.rotation = Vector3(0.2, 0.0, 0.0)
	parent.add_child(grate)
	var gw := VENT_W - 0.05
	for sx: float in [-1.0, 1.0]:
		_mesh(grate, Lowpoly.box(Vector3(0.04, VENT_H - 0.05, 0.03)), c.darkened(0.15), Vector3(sx * gw * 0.5, (VENT_H - 0.05) * 0.5, 0))
	for i in 7:
		_mesh(grate, Lowpoly.box(Vector3(gw, 0.025, 0.02)), c, Vector3(0, 0.06 + i * 0.14, 0))


# --- vent duct --------------------------------------------------------------

func _build_duct() -> void:
	var duct := _group("VentDuct")
	var c := Color("7d848b")
	var length := DUCT_X1 - DUCT_X0
	var cx := (DUCT_X0 + DUCT_X1) * 0.5
	var depth := DUCT_Z1 - DUCT_Z0
	var cz := (DUCT_Z0 + DUCT_Z1) * 0.5
	# Floor and ceiling of the main run (ceiling also covers the house wall top edge gap).
	_box(duct, Vector3(length + 0.4, 0.1, depth + 0.4), Vector3(cx, -0.05, cz), c.darkened(0.3))
	_box(duct, Vector3(length + 0.4, 0.1, depth + 0.4), Vector3(cx, VENT_H + 0.05, cz), c)
	# Outer (south) wall with a gap for the branch.
	var bx0 := BRANCH_X - 0.5
	var bx1 := BRANCH_X + 0.5
	_box(duct, Vector3(bx0 - DUCT_X0 + 0.2, VENT_H, 0.2), Vector3((DUCT_X0 - 0.2 + bx0) * 0.5, VENT_H * 0.5, DUCT_Z1 + 0.1), c)
	_box(duct, Vector3(DUCT_X1 + 0.2 - bx1, VENT_H, 0.2), Vector3((bx1 + DUCT_X1 + 0.2) * 0.5, VENT_H * 0.5, DUCT_Z1 + 0.1), c)
	# North wall where the duct runs past the house corners.
	_box(duct, Vector3(-DUCT_X0 + 0.2, VENT_H, T), Vector3((DUCT_X0 - 0.2) * 0.5, VENT_H * 0.5, 18.0), c)
	_box(duct, Vector3(DUCT_X1 - 24.0 + 0.2, VENT_H, T), Vector3((24.0 + DUCT_X1 + 0.2) * 0.5, VENT_H * 0.5, 18.0), c)
	# South branch.
	var blen := BRANCH_Z1 - DUCT_Z1
	var bcz := (DUCT_Z1 + BRANCH_Z1) * 0.5
	_box(duct, Vector3(1.4, 0.1, blen + 0.2), Vector3(BRANCH_X, -0.05, bcz + 0.1), c.darkened(0.3))
	_box(duct, Vector3(1.4, 0.1, blen + 0.2), Vector3(BRANCH_X, VENT_H + 0.05, bcz + 0.1), c)
	_box(duct, Vector3(0.2, VENT_H, blen + 0.2), Vector3(bx0 - 0.1, VENT_H * 0.5, bcz + 0.1), c)
	_box(duct, Vector3(0.2, VENT_H, blen + 0.2), Vector3(bx1 + 0.1, VENT_H * 0.5, bcz + 0.1), c)
	# Fans at the three dead ends (they double as the end caps).
	_fan(duct, Vector3(DUCT_X0, VENT_H * 0.5, cz), PI * 0.5, depth)
	_fan(duct, Vector3(DUCT_X1, VENT_H * 0.5, cz), -PI * 0.5, depth)
	_fan(duct, Vector3(BRANCH_X, VENT_H * 0.5, BRANCH_Z1), PI, 1.0)
	# Seams for a bit of visual rhythm.
	var x := DUCT_X0 + 1.5
	while x < DUCT_X1:
		_mesh(duct, Lowpoly.box(Vector3(0.04, 0.02, depth)), c.lightened(0.15), Vector3(x, VENT_H - 0.01, cz))
		x += 2.0
	_spot("BatteryDuct", battery_spots, Vector3(BRANCH_X, 0.02, BRANCH_Z1 - 0.7))
	# Dim service lights (morning only) so the duct can be explored before night.
	for lx: float in [2.0, 12.0, 21.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(lx, VENT_H - 0.15, cz)
		l.light_color = Color("cfe0ff")
		l.light_energy = 0.5
		l.omni_range = 4.0
		duct.add_child(l)
		_room_lights.append(l)


func _fan(parent: Node3D, pos: Vector3, yaw: float, width: float) -> void:
	var fan := VentFan.create(width, VENT_H)
	fan.position = pos
	fan.rotation.y = yaw
	parent.add_child(fan)


# --- rooms ------------------------------------------------------------------

func _build_kitchen() -> void:
	var room := _group("Kitchen")
	_room_light(room, Vector3(5.0, H, 3.5))
	# Fridge in the north-west corner, door facing the room.
	var fridge := _furniture(room, Vector3(0.6, 0, 0.5), 0.0)
	fridge_door = _build_fridge(fridge)
	# Counter + stove along the north wall.
	_box(room, Vector3(3.4, 0.9, 0.6), Vector3(2.85, 0.45, 0.4), Color("cfc6b4"))
	_box(room, Vector3(3.44, 0.04, 0.64), Vector3(2.85, 0.92, 0.4), Color("3b3f45"), false)
	_box(room, Vector3(0.8, 0.9, 0.6), Vector3(5.0, 0.45, 0.4), Color("e0e0e0"))
	for dx: float in [-0.18, 0.18]:
		_mesh(room, Lowpoly.cylinder(0.12, 0.02, 8), Color("222222"), Vector3(5.0 + dx, 0.91, 0.4))
	# Table, chairs, bowl.
	var table := _furniture(room, Vector3(5.5, 0, 3.6), 0.0)
	_build_table(table, Vector3(1.6, 0.75, 0.9))
	for side: float in [-1.0, 1.0]:
		var chair := _furniture(room, Vector3(5.5, 0, 3.6 + side * 0.85), 0.0 if side > 0 else PI)
		_build_chair(chair)
	_build_bowl(Vector3(5.5, 0.78, 3.6))
	cereal = add_prop(SimpleProps.cereal_box(), Vector3(2.2, 0.95, 0.4), 0.2) as Prop
	_spot("BatteryKitchen", battery_spots, Vector3(3.8, 0.95, 0.35))


func _build_living_room() -> void:
	var room := _group("LivingRoom")
	_room_light(room, Vector3(17.0, H, 3.5))
	# TV stand + TV against the north wall.
	_box(room, Vector3(1.6, 0.5, 0.5), Vector3(17.0, 0.25, 0.4), C_WOOD_DARK)
	tv = Tv.create()
	tv.position = Vector3(17.0, 0.5, 0.4)
	room.add_child(tv)
	# Sofa-bed along the south wall, open side facing the TV.
	var bed := _furniture(room, Vector3(16.0, 0, 6.2), PI)
	_build_bed(bed, Vector3(2.0, 0, 1.2), Color("7b3f3f"), null)
	# Armchair.
	_box(room, Vector3(0.8, 0.45, 0.8), Vector3(12.0, 0.225, 2.0), Color("5e4a6b"))
	_box(room, Vector3(0.8, 0.5, 0.15), Vector3(12.0, 0.7, 1.67), Color("5e4a6b"))
	# The remote lies on the floor in front of the TV.
	add_prop(TvRemote.create(tv), Vector3(16.6, 0.05, 3.3), 0.4)
	_spot("BatteryLiving", battery_spots, Vector3(16.0, 0.52, 0.4))


func _build_corridor() -> void:
	var room := _group("Corridor")
	_room_light(room, Vector3(5.0, H, 8.25))
	_room_light(room, Vector3(17.5, H, 8.25))
	_mesh(room, Lowpoly.box(Vector3(18.0, 0.01, 1.3)), Color("6e2f2f"), Vector3(12.0, 0.005, 8.25))
	_build_dresser(room, Vector3(7.0, 0, 7.1 + 0.225), 0.0, Color("8fb3c9"))
	_build_dresser(room, Vector3(13.6, 0, 9.4 - 0.225), PI, Color("c98f8f"))
	# The duck is right outside the bathroom — easy to step on in the dark.
	add_prop(Duck.create(), Vector3(9.4, 0.05, 8.4), 0.8)


func _build_hero_room() -> void:
	var room := _group("HeroRoom")
	_room_light(room, Vector3(4.5, H, 13.5))
	# Bed along the west wall, open side facing east. Sleeping here ends the morning.
	var bed := _furniture(room, Vector3(0.7, 0, 12.0), PI * 0.5)
	hero_bed = Interactable.new()
	var under_bed := _build_bed(bed, Vector3(2.0, 0, 1.0), Color("3f6b9e"), hero_bed)
	key_spots.append(under_bed)
	# Desk with lamp against the south wall.
	var desk := _furniture(room, Vector3(6.5, 0, 17.9 - 0.3), PI)
	_build_table(desk, Vector3(1.3, 0.74, 0.6))
	_build_lamp(desk, Vector3(-0.45, 0.76, 0.1))
	flashlight_spot = _spot("FlashlightSpot", [], Vector3(6.2, 0.78, 17.55))
	# Wardrobe against the east wall.
	var wardrobe := _furniture(room, Vector3(8.9 - 0.3, 0, 14.5), -PI * 0.5)
	var shelf_spots := _build_wardrobe(wardrobe)
	# Toy box in the middle of the room — empty until the quest.
	var box := _furniture(room, Vector3(4.5, 0, 13.8), 0.2)
	toy_zone = _build_toy_box(box)
	# Toys: two on the wardrobe shelf, one under the bed, the rest on the floor.
	var kinds := [Toy.Kind.TEDDY, Toy.Kind.BLOCK, Toy.Kind.CAR, Toy.Kind.BALL, Toy.Kind.PYRAMID, Toy.Kind.BLOCK, Toy.Kind.CAR]
	var spots: Array[Vector3] = [
		shelf_spots[0], shelf_spots[1],
		under_bed.global_position + Vector3(0.1, 0.05, -0.2),
		Vector3(2.6, 0.03, 10.8), Vector3(6.9, 0.03, 11.4), Vector3(3.1, 0.03, 16.2), Vector3(5.6, 0.03, 15.4),
	]
	for i in kinds.size():
		var toy := Toy.create(kinds[i], i)
		add_prop(toy, spots[i], randf() * TAU)
		toys.append(toy)


func _build_bathroom() -> void:
	var room := _group("Bathroom")
	_room_light(room, Vector3(12.0, H, 13.5))
	# Bathtub along the east wall (solid body + water surface, so there's no navmesh island inside).
	var tub := _furniture(room, Vector3(14.1, 0, 15.9), 0.0)
	var tc := Color("f2f2f0")
	_box(tub, Vector3(1.5, 0.55, 3.6), Vector3(0, 0.275, 0), tc)
	_mesh(tub, Lowpoly.box(Vector3(1.3, 0.01, 3.4)), Color("9fc4d6"), Vector3(0, 0.555, 0))
	# Toilet.
	_box(room, Vector3(0.4, 0.42, 0.55), Vector3(9.35, 0.21, 16.6), tc)
	_box(room, Vector3(0.18, 0.45, 0.5), Vector3(9.2, 0.65, 16.6), tc)
	# Sink.
	_box(room, Vector3(0.18, 0.8, 0.18), Vector3(9.3, 0.4, 12.6), tc)
	_box(room, Vector3(0.45, 0.12, 0.6), Vector3(9.35, 0.86, 12.6), tc)
	_mesh(room, Lowpoly.box(Vector3(0.02, 0.6, 0.5)), Color("a9c3d1"), Vector3(9.11, 1.5, 12.6))
	_spot("BatteryBath", battery_spots, Vector3(9.4, 0.94, 12.45))


func _build_entry_hall() -> void:
	var room := _group("EntryHall")
	_room_light(room, Vector3(19.5, H, 13.5))
	_mesh(room, Lowpoly.box(Vector3(1.4, 0.01, 1.0)), Color("3d4a3a"), Vector3(23.2, 0.005, 13.5))
	_build_dresser(room, Vector3(18.0, 0, 17.9 - 0.225), PI, Color("a9c98f"))
	var wardrobe := _furniture(room, Vector3(15.1 + 0.3, 0, 14.0), PI * 0.5)
	_build_wardrobe(wardrobe)
	_spot("BatteryEntry", battery_spots, Vector3(23.3, 0.05, 17.3))


func _build_patrol_points() -> void:
	patrol_points = [
		Vector3(5.5, 0, 5.6), Vector3(2.0, 0, 3.5),  # kitchen
		Vector3(13.0, 0, 4.5), Vector3(21.5, 0, 3.0),  # living room
		Vector3(2.0, 0, 8.25), Vector3(11.0, 0, 8.25), Vector3(20.0, 0, 8.25),  # corridor
		Vector3(5.0, 0, 11.5), Vector3(11.5, 0, 12.0),  # dead-end rooms
		Vector3(19.0, 0, 12.0), Vector3(21.0, 0, 16.0),  # entry hall
	]


# --- furniture builders (local space: front faces +Z) -----------------------

func _build_fridge(root: Node3D) -> HingedDoor:
	var w := 0.8
	var d := 0.7
	var h := 1.9
	var outer := Color("d6dade")
	var inner := Color("f4f6f8")
	_box(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015), outer)
	_box(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0), outer)
	_box(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0), outer)
	_box(root, Vector3(w, 0.03, d), Vector3(0, h - 0.015, 0), outer)
	_box(root, Vector3(w, 0.06, d), Vector3(0, 0.03, 0), outer)
	for y: float in [0.6, 1.15]:
		_box(root, Vector3(w - 0.06, 0.02, d - 0.06), Vector3(0, y, 0), inner)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.6, 0)
	light.omni_range = 0.9
	light.light_energy = 0.6
	root.add_child(light)
	var door := HingedDoor.new()
	door.name = "FridgeDoor"
	door.position = Vector3(-w * 0.5, 0.03, d * 0.5 + 0.03)
	door.open_angle = deg_to_rad(-105)
	door.open_prompt = "Открыть холодильник"
	door.close_prompt = "Закрыть холодильник"
	door.build_panel(Vector3(w, h - 0.06, 0.06), outer, false)
	root.add_child(door)
	milk = add_prop(SimpleProps.milk(), root.to_global(Vector3(0.1, 0.62, 0.0))) as Prop
	return door


func _build_table(root: Node3D, size: Vector3) -> void:
	_box(root, Vector3(size.x, 0.05, size.z), Vector3(0, size.y - 0.025, 0), C_WOOD)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(root, Vector3(0.06, size.y - 0.05, 0.06), Vector3(sx * (size.x * 0.5 - 0.06), (size.y - 0.05) * 0.5, sz * (size.z * 0.5 - 0.06)), C_WOOD_DARK)


func _build_chair(root: Node3D) -> void:
	_box(root, Vector3(0.42, 0.04, 0.42), Vector3(0, 0.45, 0), C_WOOD)
	_box(root, Vector3(0.42, 0.45, 0.04), Vector3(0, 0.7, 0.19), C_WOOD)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(root, Vector3(0.04, 0.45, 0.04), Vector3(sx * 0.18, 0.225, sz * 0.18), C_WOOD_DARK)


func _build_bowl(pos: Vector3) -> void:
	bowl = StaticBody3D.new()
	bowl.name = "Bowl"
	bowl.position = pos
	bowl.collision_layer = Prop.LAYER_WORLD
	Lowpoly.add_mesh(bowl, Lowpoly.cylinder(0.08, 0.07, 8, 0.14), Color("e6e1d3"), Vector3(0, 0.035, 0))
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.12
	shape.height = 0.04
	cs.shape = shape
	cs.position = Vector3(0, 0.02, 0)
	bowl.add_child(cs)
	add_child(bowl)
	bowl_zone = ItemZone.create(Vector3(0.6, 0.5, 0.6))
	bowl_zone.position = pos + Vector3(0, 0.25, 0)
	add_child(bowl_zone)


## Turns the bowl into a full bowl of cereal (no animation, on purpose).
func fill_bowl() -> void:
	Lowpoly.add_mesh(bowl, Lowpoly.cylinder(0.13, 0.01, 8), Color("f7f5ef"), Vector3(0, 0.066, 0))
	for i in 9:
		var a := i * TAU / 9.0
		var r := 0.03 + (i % 3) * 0.03
		Lowpoly.add_mesh(bowl, Lowpoly.box(Vector3(0.03, 0.012, 0.03)), Color("e0a23b"), Vector3(cos(a) * r, 0.074, sin(a) * r), Vector3(0, a, 0))


## Bed with the long side along local X and the open side (where you can reach under) at +Z.
## Returns a marker under the bed. `interactable` becomes the mattress body if given.
func _build_bed(root: Node3D, size: Vector3, blanket: Color, interactable: StaticBody3D) -> Node3D:
	var l := size.x
	var w := size.z
	var gap := 0.3
	var frame := C_WOOD_DARK
	var mattress: StaticBody3D = interactable if interactable else StaticBody3D.new()
	mattress.collision_layer = Prop.LAYER_WORLD
	root.add_child(mattress)
	Lowpoly.add_mesh(mattress, Lowpoly.box(Vector3(l, 0.25, w)), C_WHITE, Vector3(0, gap + 0.125, 0))
	Lowpoly.add_box_shape(mattress, Vector3(l, 0.25, w), Vector3(0, gap + 0.125, 0))
	Lowpoly.add_mesh(mattress, Lowpoly.box(Vector3(l * 0.62, 0.04, w + 0.04)), blanket, Vector3(l * 0.17, gap + 0.26, 0))
	Lowpoly.add_mesh(mattress, Lowpoly.box(Vector3(0.35, 0.1, w * 0.7)), C_WHITE.darkened(0.05), Vector3(-l * 0.5 + 0.25, gap + 0.3, 0))
	# Skirts on the back, head and foot so the gap is reachable only from the open side.
	_box(root, Vector3(l, gap, 0.04), Vector3(0, gap * 0.5, -w * 0.5 + 0.02), frame)
	_box(root, Vector3(0.06, 0.95, w), Vector3(-l * 0.5 - 0.03, 0.475, 0), frame)
	_box(root, Vector3(0.06, 0.5, w), Vector3(l * 0.5 + 0.03, 0.25, 0), frame)
	_box(root, Vector3(0.06, gap, 0.06), Vector3(l * 0.5 - 0.03, gap * 0.5, w * 0.5 - 0.03), frame)
	_box(root, Vector3(0.06, gap, 0.06), Vector3(-l * 0.5 + 0.03, gap * 0.5, w * 0.5 - 0.03), frame)
	var marker := Node3D.new()
	marker.name = "UnderBed"
	marker.position = Vector3(0.2, 0.01, -0.05)
	root.add_child(marker)
	return marker


## Returns world positions on the wardrobe shelf. Also registers a key spot inside.
func _build_wardrobe(root: Node3D) -> Array[Vector3]:
	var w := 1.2
	var d := 0.6
	var h := 2.0
	var c := C_WOOD
	_box(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015), c.darkened(0.25))
	_box(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0), c)
	_box(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0), c)
	_box(root, Vector3(w, 0.03, d), Vector3(0, h - 0.015, 0), c)
	_box(root, Vector3(w, 0.06, d), Vector3(0, 0.03, 0), c)
	_box(root, Vector3(w - 0.06, 0.03, d - 0.04), Vector3(0, 1.3, -0.01), c)
	_mesh(root, Lowpoly.cylinder(0.012, w - 0.08, 6), C_METAL, Vector3(0, 1.75, 0), Vector3(0, 0, PI * 0.5))
	for side: float in [-1.0, 1.0]:
		var door := HingedDoor.new()
		door.position = Vector3(side * w * 0.5, 0.06, d * 0.5 + 0.015)
		door.open_angle = deg_to_rad(105.0 * side)
		door.open_prompt = "Открыть шкаф"
		door.close_prompt = "Закрыть шкаф"
		door.build_panel(Vector3(w * 0.5 - 0.005, h - 0.09, 0.025), c.lightened(0.08), side > 0)
		root.add_child(door)
	var key_spot := Node3D.new()
	key_spot.name = "WardrobeKeySpot"
	key_spot.position = Vector3(0.15, 0.07, 0.05)
	root.add_child(key_spot)
	key_spots.append(key_spot)
	return [root.to_global(Vector3(-0.3, 1.33, 0.0)), root.to_global(Vector3(0.25, 1.33, 0.02))]


func _build_dresser(parent: Node3D, pos: Vector3, yaw: float, vase_color: Color) -> void:
	var root := _furniture(parent, pos, yaw)
	var w := 1.0
	var d := 0.45
	var h := 0.8
	var c := Color("6d4c33")
	_box(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015), c.darkened(0.2))
	_box(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0), c)
	_box(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0), c)
	_box(root, Vector3(w + 0.04, 0.03, d + 0.02), Vector3(0, h - 0.015, 0.01), c.darkened(0.1))
	_box(root, Vector3(w, 0.06, d), Vector3(0, 0.03, 0), c.darkened(0.2))
	var slot := (h - 0.09) / 3.0
	var depth := 0.38
	for i in 3:
		var drawer := Drawer.create(w - 0.08, slot - 0.02, depth, c.lightened(0.1))
		drawer.position = Vector3(0, 0.06 + slot * (i + 0.5), d * 0.5 - depth * 0.5)
		root.add_child(drawer)
		key_spots.append(drawer.content)
	# Mirror on the wall above.
	_mesh(root, Lowpoly.box(Vector3(0.8, 1.0, 0.03)), Color("3b2a1c"), Vector3(0, 1.6, -d * 0.5 + 0.015))
	var mirror := MeshInstance3D.new()
	mirror.mesh = Lowpoly.box(Vector3(0.68, 0.88, 0.01))
	mirror.material_override = Lowpoly.mat(Color("b9c7cf"), 0.05, 0.85)
	mirror.position = Vector3(0, 1.6, -d * 0.5 + 0.035)
	root.add_child(mirror)
	# Vase on top — knocking it off makes a lot of noise.
	add_prop(SimpleProps.vase(vase_color), root.to_global(Vector3(0.28, h + 0.01, -0.05)))


func _build_lamp(root: Node3D, pos: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.position = pos
	root.add_child(lamp)
	_mesh(lamp, Lowpoly.cylinder(0.08, 0.03, 7), Color("2f4f6f"), Vector3(0, 0.015, 0))
	_mesh(lamp, Lowpoly.box(Vector3(0.025, 0.35, 0.025)), Color("2f4f6f"), Vector3(0, 0.2, 0))
	_mesh(lamp, Lowpoly.cylinder(0.12, 0.14, 7, 0.05), Color("e8c547"), Vector3(0, 0.42, 0))
	lamp_light = OmniLight3D.new()
	lamp_light.position = Vector3(0, 0.33, 0)
	lamp_light.light_color = Color("ffd9a0")
	lamp_light.omni_range = 2.5
	lamp_light.light_energy = 0.9
	lamp.add_child(lamp_light)


func _build_toy_box(root: Node3D) -> ItemZone:
	var w := 0.7
	var d := 0.5
	var h := 0.4
	var c := Color("b5651d")
	_box(root, Vector3(w, 0.03, d), Vector3(0, 0.015, 0), c)
	_box(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015), c)
	_box(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, d * 0.5 - 0.015), c)
	_box(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0), c.darkened(0.1))
	_box(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0), c.darkened(0.1))
	var zone := ItemZone.create(Vector3(w - 0.06, h + 0.1, d - 0.06))
	zone.position = Vector3(0, (h + 0.1) * 0.5, 0)
	root.add_child(zone)
	return zone


# --- low-level helpers -------------------------------------------------------

func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	add_child(g)
	return g


func _furniture(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	return root


## Registers a named marker (spawn spot) and returns it.
func _spot(n: String, list: Array, pos: Vector3) -> Node3D:
	var m := Marker3D.new()
	m.name = n
	m.position = pos
	add_child(m)
	list.append(m)
	return m


## Static box with collision on the world layer (or visual only).
func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, collide: bool = true) -> Node3D:
	if not collide:
		return _mesh(parent, Lowpoly.box(size), color, pos)
	var body := StaticBody3D.new()
	body.collision_layer = Prop.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	Lowpoly.add_mesh(body, Lowpoly.box(size), color)
	Lowpoly.add_box_shape(body, size)
	return body


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return Lowpoly.add_mesh(parent, mesh, color, pos, rot)


func _floor(parent: Node3D, r: Rect2, color: Color) -> void:
	_box(parent, Vector3(r.size.x, 0.2, r.size.y), Vector3(r.position.x + r.size.x * 0.5, -0.1, r.position.y + r.size.y * 0.5), color)


## Wall running along X at depth z, from x0 to x1. Openings: [[centre_x, width, height], ...].
func _wall_x(parent: Node3D, z: float, x0: float, x1: float, openings: Array) -> void:
	for seg: Array in _segments(x0, x1, openings):
		var a: float = seg[0]
		var b: float = seg[1]
		var y0: float = seg[2]
		var y1: float = seg[3]
		_box(parent, Vector3(b - a, y1 - y0, T), Vector3((a + b) * 0.5, (y0 + y1) * 0.5, z), C_WALL)
		if y0 == 0.0:
			for side: float in [-1.0, 1.0]:
				_mesh(parent, Lowpoly.box(Vector3(b - a, 0.1, 0.02)), C_WALL_TRIM, Vector3((a + b) * 0.5, 0.05, z + side * (T * 0.5 + 0.01)))


## Wall running along Z at x, from z0 to z1.
func _wall_z(parent: Node3D, x: float, z0: float, z1: float, openings: Array) -> void:
	for seg: Array in _segments(z0, z1, openings):
		var a: float = seg[0]
		var b: float = seg[1]
		var y0: float = seg[2]
		var y1: float = seg[3]
		_box(parent, Vector3(T, y1 - y0, b - a), Vector3(x, (y0 + y1) * 0.5, (a + b) * 0.5), C_WALL)
		if y0 == 0.0:
			for side: float in [-1.0, 1.0]:
				_mesh(parent, Lowpoly.box(Vector3(0.02, 0.1, b - a)), C_WALL_TRIM, Vector3(x + side * (T * 0.5 + 0.01), 0.05, (a + b) * 0.5))


## Splits a wall span into solid pieces: [start, end, y_bottom, y_top] (full height or lintels).
func _segments(s0: float, s1: float, openings: Array) -> Array:
	var out := []
	var sorted := openings.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cursor := s0
	for o: Array in sorted:
		var a: float = o[0] - o[1] * 0.5
		var b: float = o[0] + o[1] * 0.5
		if a > cursor:
			out.append([cursor, a, 0.0, H])
		out.append([a, b, o[2], H])
		cursor = b
	if cursor < s1:
		out.append([cursor, s1, 0.0, H])
	return out


func _room_light(parent: Node3D, ceiling_pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = ceiling_pos - Vector3(0, 0.6, 0)
	light.light_color = Color("ffe8c4")
	light.light_energy = 0.9
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	parent.add_child(light)
	_room_lights.append(light)
	var fixture := _mesh(parent, Lowpoly.cylinder(0.22, 0.08, 8, 0.12), Color("fff1c9"), ceiling_pos - Vector3(0, 0.04, 0))
	_fixtures.append(fixture)


func _bake_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Prop.LAYER_WORLD
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.4
	# Taller than the clearance above beds/tables (no walkable islands on furniture), lower than
	# the doorways, and far taller than the vent duct, which the monster can't enter.
	nm.agent_height = 2.3
	nm.agent_max_climb = 0.2
	# Only the house interior: keeps the roof and the duct out of the bake. The top edge just
	# reaches into the ceiling slab so clearance under it is still measured.
	nm.filter_baking_aabb = AABB(Vector3(-0.2, -0.3, -0.2), Vector3(24.4, H + 0.35, 18.15))
	navigation_mesh = nm
	bake_navigation_mesh(false)
