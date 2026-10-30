class_name House
extends NavigationRegion3D
## Builds the whole house from primitives at runtime and bakes the monster's navmesh.
## The layout follows docs/reference/house_plan.png (a three-room flat), scaled up so the 2.5 m
## monster fits through the doors.
##
## Plan (metres, X → east, Z → south; wall centre lines; V = vent, D = doorway):
##
##        north vent duct (crouch only, fans at both ends)
##   z=0    +-------V------------+-----+------+----------V-----------+
##          | HERO ROOM          |CLOS.|CLOS. |  PARENTS' ROOM       |
##          | bed, desk, wardrobe| 1   +--D---+  bed, wardrobe,      |
##          | toy box            +--D--+      D  dresser             |
##  z=4.8   +----D---------------+     HALL   +----------------------+
##          | LIVING ROOM        :  (dresser) |
##   [bal-  D TV, sofa-bed       :  open arch |
##    cony] |                    :            |
##  z=9.6   +--------------+-----+-------D----+
##          | KITCHEN      D    CORRIDOR      |
##          | fridge,table +--D---+--D--+     |
##          |              | BATH | WC  |VEST.| (dresser)
##  z=14.2  +---V----------+--V---+-----+--D--+
##        south vent duct           front door
##
## On foot the flat is a tree (every room is a dead end off the hall/corridor), so the two vent
## ducts are the loops: hero room <-> parents' room and kitchen <-> bathroom. The monster can't
## fit into a vent. The balcony door is jammed. The closets, bathroom and WC have unlocked two-way
## doors; they are left out of the navmesh and the monster opens them on its way.

const H := 2.8  ## wall height
const T := 0.2  ## wall thickness
const DOOR_W := 1.2
const DOOR_H := 2.5
const VENT_W := 0.9
const VENT_H := 1.0
const DUCT_DEPTH := 1.0

const X_EAST := 20.5  ## east wall of the parents' room
const X_HALL := 12.0  ## east wall of the hall / corridor
const Z_ROOMS := 4.8  ## south wall of the hero and parents' rooms
const Z_MID := 9.6  ## living room / hall | kitchen / corridor
const Z_SOUTH := 14.2
const NORTH_VENTS: Array[float] = [5.6, 16.0]  ## hero room, parents' room
const SOUTH_VENTS: Array[float] = [1.4, 5.25]  ## kitchen, bathroom
const NORTH_DUCT_X := Vector2(-1.2, 21.7)
const SOUTH_DUCT_X := Vector2(-1.2, 9.0)

const RUG_Y := 0.004  ## rugs float a few mm above the floor: some have a curled corner, the flat rest would z-fight
const FLOOR_Y := 0.6  ## wardrobe: height of the inside floor (the model has drawers below it)
const DRESSER_TINT := Color(0.78, 0.7, 0.6)  ## aged cream paint on the dresser model
const C_WALL := Color("b7a48a")
const C_WALL_TRIM := Color("8c7a62")

# --- references for gameplay code -------------------------------------------
var fridge_door: HingedDoor
var bowl: StaticBody3D
var bowl_zone: ItemZone
var toy_zone: ItemZone
var tv: Tv
var hero_bed: Bed
var front_door: HingedDoor
var balcony_door: HingedDoor
var room_doors: Array[HingedDoor] = []
var key_spots: Array[Node3D] = []
var battery_spots: Array[Node3D] = []
var flashlight_spot: Node3D
var patrol_points: Array[Vector3] = []
var toys: Array[Toy] = []
var cereal: Prop
var milk: Prop
var lamp_light: OmniLight3D

var player_spawn_morning := Transform3D(Basis(Vector3.UP, -PI * 0.4), Vector3(2.6, 0.05, 3.9))
var player_spawn_night := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(1.7, 0.05, 2.2))
var monster_spawn := Vector3(16.5, 0.05, 2.6)

var _room_lights: Array[OmniLight3D] = []
var _fixtures: Array[MeshInstance3D] = []
var _props_root: Node3D


func build() -> void:
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	_build_shell()
	_build_duct("NorthDuct", 0.0, -1.0, NORTH_DUCT_X, Vector2(-0.1, X_EAST + 0.1))
	_build_duct("SouthDuct", Z_SOUTH, 1.0, SOUTH_DUCT_X, Vector2(-0.1, X_HALL + 0.1))
	_spot("BatteryDuct", battery_spots, Vector3(10.5, 0.02, -0.6))  # behind the closets
	_build_balcony()
	_build_hero_room()
	_build_living_room()
	_build_hall()
	_build_parents_room()
	_build_kitchen()
	_build_corridor()
	_build_bathroom()
	_build_wc()
	_build_patrol_points()
	_bake_navmesh()


func set_lights_on(on: bool) -> void:
	for l in _room_lights:
		l.visible = on
	for f in _fixtures:
		f.material_override = Lowpoly.mat(Color("fff1c9"), 0.5, 0.0, 3.0) if on else null
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
	_floor(shell, Rect2(0, 0, 8, Z_ROOMS), Color("46607d"), "carpet")  # hero room carpet
	_floor(shell, Rect2(0, Z_ROOMS, 8, Z_MID - Z_ROOMS), Color("6b4a32"), "wood")  # living room wood
	_floor(shell, Rect2(8, 0, X_HALL - 8, Z_MID), Color("5a4636"), "wood")  # hall + closets
	_floor(shell, Rect2(X_HALL, 0, X_EAST - X_HALL, Z_ROOMS), Color("6f5a4a"), "carpet")  # parents' room
	_floor(shell, Rect2(0, Z_MID, 4.6, Z_SOUTH - Z_MID), Color("8e9aa1"), "tile")  # kitchen tiles
	_floor(shell, Rect2(4.6, Z_MID, X_HALL - 4.6, 1.8), Color("5a4636"), "wood")  # corridor
	_floor(shell, Rect2(4.6, 11.4, 2.2, Z_SOUTH - 11.4), Color("cfd8dc"), "tile")  # bathroom tiles
	_floor(shell, Rect2(6.8, 11.4, 2.0, Z_SOUTH - 11.4), Color("c3ccd0"), "tile")  # WC tiles
	_floor(shell, Rect2(8.8, 11.4, X_HALL - 8.8, Z_SOUTH - 11.4), Color("5d5148"), "concrete")  # vestibule
	# Ceiling.
	_box(shell, Vector3(X_EAST + 0.3, 0.1, Z_SOUTH + 0.4), Vector3(X_EAST * 0.5, H + 0.05, Z_SOUTH * 0.5), Color("d9d4c8"), true, "plaster", true)

	# Exterior walls.
	var north_vents := NORTH_VENTS.map(func(x: float) -> Array: return [x, VENT_W, VENT_H])
	var south_vents := SOUTH_VENTS.map(func(x: float) -> Array: return [x, VENT_W, VENT_H])
	_wall_x(shell, 0.0, -0.1, X_EAST + 0.1, north_vents)
	_wall_z(shell, 0.0, 0.0, Z_SOUTH, [[8.0, DOOR_W, DOOR_H]])  # balcony door
	_wall_z(shell, X_EAST, 0.0, Z_ROOMS, [])
	_wall_x(shell, Z_ROOMS, X_HALL, X_EAST + 0.1, [])
	_wall_z(shell, X_HALL, 0.0, Z_SOUTH, [[3.4, DOOR_W, DOOR_H]])  # hall | parents' room, then outside
	_wall_x(shell, Z_SOUTH, -0.1, X_HALL + 0.1, south_vents + [[10.4, DOOR_W, DOOR_H]])
	# Interior walls.
	_wall_x(shell, Z_ROOMS, 0.0, 8.0, [[2.2, DOOR_W, DOOR_H]])  # hero room | living room
	_wall_z(shell, 8.0, 0.0, Z_ROOMS, [])  # hero room | closet + hall
	_wall_z(shell, 8.0, Z_ROOMS, Z_MID, [[7.2, Z_MID - Z_ROOMS, DOOR_H]])  # open arch: lintel only
	_wall_z(shell, 9.5, 0.0, 2.6, [])  # closet 1 | closet 2
	_wall_x(shell, 2.6, 8.0, 9.5, [[8.75, 1.1, DOOR_H]])  # closet 1 doorway
	_wall_x(shell, 1.6, 9.5, X_HALL, [[10.75, DOOR_W, DOOR_H]])  # closet 2 doorway
	_wall_x(shell, Z_MID, 0.0, X_HALL, [[10.4, DOOR_W, DOOR_H]])  # hall | corridor
	_wall_z(shell, 4.6, Z_MID, Z_SOUTH, [[10.6, DOOR_W, DOOR_H]])  # kitchen | corridor
	_wall_x(shell, 11.4, 4.6, 8.8, [[5.7, DOOR_W, DOOR_H], [7.8, DOOR_W, DOOR_H]])  # bath, WC doors
	_wall_z(shell, 6.8, 11.4, Z_SOUTH, [])  # bath | WC
	_wall_z(shell, 8.8, 11.4, Z_SOUTH, [])  # WC | vestibule

	# Unlocked doors: storage closets, bathroom, WC.
	_room_door(shell, 8.75 - 0.55, 2.6, 1.1, false)
	_room_door(shell, 10.75 + DOOR_W * 0.5, 1.6, DOOR_W, true)
	_room_door(shell, 5.7 - DOOR_W * 0.5, 11.4, DOOR_W, false)
	_room_door(shell, 7.8 + DOOR_W * 0.5, 11.4, DOOR_W, true)

	# Vent openings: the removed grate leans next to each one. In the bathroom the tub is in the
	# way, so the grate leans against the west wall there.
	for x in NORTH_VENTS:
		_vent_grate(shell, Vector3(x + VENT_W * 0.5 + 0.6, 0.0, T * 0.5 + 0.24), 0.0)
	_vent_grate(shell, Vector3(SOUTH_VENTS[0] + VENT_W * 0.5 + 0.6, 0.0, Z_SOUTH - T * 0.5 - 0.24), PI)
	_vent_grate(shell, Vector3(4.6 + T * 0.5 + 0.24, 0.0, 13.1), PI * 0.5)

	# Front door (locked until the player has the key), opens outwards.
	front_door = HingedDoor.new()
	front_door.name = "FrontDoor"
	front_door.position = Vector3(10.4 - DOOR_W * 0.5, 0.0, Z_SOUTH)
	front_door.open_angle = deg_to_rad(-100)
	front_door.open_prompt = "Открыть входную дверь"
	front_door.close_prompt = ""
	front_door.locked_prompt = "Заперто. Нужен ключ"
	front_door.can_open = func(p: Player) -> bool: return p.has_key
	front_door.open_sound = Sfx.DOOR_OPEN
	front_door.locked_sound = Sfx.DOOR_LOCKED
	front_door.build_model_panel("door_front", Vector3(DOOR_W, DOOR_H, 0.08), false)
	shell.add_child(front_door)


## Unlocked two-way room door in a doorway of a wall along X at wall_z. The hinge is at hinge_x;
## the panel runs east from it (west when mirrored). Room doors are left out of the navmesh: the
## monster opens them on its way.
func _room_door(parent: Node3D, hinge_x: float, wall_z: float, width: float, mirrored: bool) -> void:
	var door := HingedDoor.new()
	door.name = "RoomDoor%d" % room_doors.size()
	door.position = Vector3(hinge_x + (-0.02 if mirrored else 0.02), 0.01, wall_z)
	door.open_angle = deg_to_rad(92.0)
	door.two_way = true
	door.open_prompt = "Открыть дверь"
	door.close_prompt = "Закрыть дверь"
	door.open_sound = Sfx.DOOR_OPEN
	door.close_sound = Sfx.DOOR_CLOSE
	door.collision_layer = Prop.LAYER_DOORS
	door.build_model_panel("door_room", Vector3(width - 0.04, DOOR_H - 0.03, 0.05), mirrored)
	parent.add_child(door)
	room_doors.append(door)


## The removed vent grate leaning against a wall. `pos` is its foot on the floor; at yaw 0 it
## faces +Z with the wall behind it (on -Z).
func _vent_grate(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var grate := Node3D.new()
	grate.position = pos
	grate.rotation = Vector3(-0.2, yaw, 0.0)
	parent.add_child(grate)
	Models.add(grate, "vent_cover", Vector3(VENT_W - 0.05, VENT_H - 0.05, 0.03))


# --- vent ducts -------------------------------------------------------------

## Straight duct outside the wall along X at wall_z. `side` = -1 (north of it) or +1 (south).
## `span` is the duct's x range; `house_span` is where the house wall closes its inner side.
func _build_duct(n: String, wall_z: float, side: float, span: Vector2, house_span: Vector2) -> void:
	var duct := _group(n)
	var c := Color("7d848b")
	var length := span.y - span.x
	var cx := (span.x + span.y) * 0.5
	var z_in := wall_z + side * T * 0.5
	var cz := z_in + side * DUCT_DEPTH * 0.5
	# Floor and ceiling. The floor reaches under the house wall to its centre line (where the room
	# floor starts); the ceiling starts at the wall's outer face, so neither one shares a surface
	# with the wall or the room floor (that z-fought as a stripe along the walls).
	var outer := z_in + side * (DUCT_DEPTH + 0.2)
	var floor_depth := absf(outer - wall_z)
	var ceil_depth := absf(outer - z_in)
	_box(duct, Vector3(length + 0.4, 0.1, floor_depth), Vector3(cx, -0.05, (outer + wall_z) * 0.5), c.darkened(0.3), true, "metal", true)
	_box(duct, Vector3(length + 0.4, 0.1, ceil_depth), Vector3(cx, VENT_H + 0.05, (outer + z_in) * 0.5), c, true, "metal", true)
	# Outer wall, and inner walls where the duct runs past the house corners.
	_box(duct, Vector3(length + 0.4, VENT_H, 0.2), Vector3(cx, VENT_H * 0.5, z_in + side * (DUCT_DEPTH + 0.1)), c, true, "metal", true)
	if span.x < house_span.x:
		_box(duct, Vector3(house_span.x - span.x + 0.2, VENT_H, T), Vector3((span.x - 0.2 + house_span.x) * 0.5, VENT_H * 0.5, wall_z), c, true, "metal", true)
	if span.y > house_span.y:
		_box(duct, Vector3(span.y - house_span.y + 0.2, VENT_H, T), Vector3((house_span.y + span.y + 0.2) * 0.5, VENT_H * 0.5, wall_z), c, true, "metal", true)
	# Fans at both dead ends (they double as the end caps).
	_fan(duct, Vector3(span.x, VENT_H * 0.5, cz), PI * 0.5, DUCT_DEPTH)
	_fan(duct, Vector3(span.y, VENT_H * 0.5, cz), -PI * 0.5, DUCT_DEPTH)
	# Dim service lights (morning only) so the duct can be explored before night.
	var lx := span.x + 3.0
	while lx < span.y - 1.0:
		var l := OmniLight3D.new()
		l.position = Vector3(lx, VENT_H - 0.15, cz)
		l.light_color = Color("cfe0ff")
		l.light_energy = 0.5
		l.omni_range = 4.0
		duct.add_child(l)
		_room_lights.append(l)
		lx += 6.0


func _fan(parent: Node3D, pos: Vector3, yaw: float, width: float) -> void:
	var fan := VentFan.create(width, VENT_H)
	fan.position = pos
	fan.rotation.y = yaw
	parent.add_child(fan)


## Small glazed balcony behind a jammed door (as on the plan; not playable in the alpha).
func _build_balcony() -> void:
	var b := _group("Balcony")
	_box(b, Vector3(1.6, 0.2, 3.0), Vector3(-0.9, -0.1, 8.0), Color("6d6d6d"), true, "concrete", true)
	_box(b, Vector3(0.1, 1.0, 3.0), Vector3(-1.65, 0.5, 8.0), Color("8a8a8a"), true, "concrete", true)
	_box(b, Vector3(1.6, 1.0, 0.1), Vector3(-0.9, 0.5, 6.55), Color("8a8a8a"), true, "concrete", true)
	_box(b, Vector3(1.6, 1.0, 0.1), Vector3(-0.9, 0.5, 9.45), Color("8a8a8a"), true, "concrete", true)
	_box(b, Vector3(1.8, 0.1, 3.2), Vector3(-0.9, H - 0.2, 8.0), Color("8a8a8a"), true, "concrete", true)
	balcony_door = HingedDoor.new()
	balcony_door.name = "BalconyDoor"
	balcony_door.position = Vector3(0.0, 0.0, 8.0 - DOOR_W * 0.5)
	balcony_door.rotation.y = -PI * 0.5
	balcony_door.locked_prompt = "Балконную дверь заклинило"
	balcony_door.can_open = func(_p: Player) -> bool: return false
	balcony_door.locked_sound = Sfx.DOOR_LOCKED
	balcony_door.build_model_panel("door_balcony", Vector3(DOOR_W, DOOR_H, 0.08), false)
	b.add_child(balcony_door)


# --- rooms ------------------------------------------------------------------

func _build_hero_room() -> void:
	var room := _group("HeroRoom")
	_room_light(room, Vector3(4.0, H, 2.4))
	# Bed along the west wall, open side facing east. Sleeping here ends the morning.
	var bed := _furniture(room, Vector3(0.6, 0, 2.2), PI * 0.5)
	hero_bed = Bed.new()
	var under_bed := _build_bed(bed, Vector3(2.0, 0, 1.0), "bed_single", hero_bed)
	key_spots.append(under_bed)
	# Desk with lamp against the north wall.
	var desk := _furniture(room, Vector3(3.0, 0, 0.1 + 0.3), 0.0)
	_build_table(desk, Vector3(1.3, 0.74, 0.6))
	_build_lamp(desk, Vector3(-0.45, 0.76, -0.1))
	flashlight_spot = _spot("FlashlightSpot", [], Vector3(3.3, 0.78, 0.45))
	# Wardrobe against the east wall.
	var wardrobe := _furniture(room, Vector3(7.9 - 0.3, 0, 2.4), -PI * 0.5)
	var shelf_spots := _build_wardrobe(wardrobe)
	# Toy box in the middle of the room — empty until the quest.
	var box := _furniture(room, Vector3(4.2, 0, 2.6), 0.2)
	toy_zone = _build_toy_box(box)
	# Toys: two on the wardrobe shelf, one under the bed, the rest on the floor.
	var kinds := [Toy.Kind.TEDDY, Toy.Kind.BLOCK, Toy.Kind.CAR, Toy.Kind.BALL, Toy.Kind.PYRAMID, Toy.Kind.BLOCK, Toy.Kind.CAR]
	var spots: Array[Vector3] = [
		shelf_spots[0], shelf_spots[1],
		under_bed.global_position + Vector3(0.1, 0.05, -0.2),
		Vector3(2.4, 0.03, 4.1), Vector3(6.2, 0.03, 3.9), Vector3(2.9, 0.03, 1.5), Vector3(5.3, 0.03, 1.6),
	]
	for i in kinds.size():
		var toy := Toy.create(kinds[i], i)
		add_prop(toy, spots[i], randf() * TAU)
		toys.append(toy)


func _build_living_room() -> void:
	var room := _group("LivingRoom")
	_room_light(room, Vector3(4.0, H, 7.2))
	Models.add(room, "rug_a", Vector3(2.0, 0.01, 3.2), Vector3(4.6, RUG_Y, 7.4), PI * 0.5)
	# TV stand + TV against the south wall, facing north.
	_solid(room, Vector3(1.6, 0.5, 0.5), Vector3(4.6, 0.25, Z_MID - 0.35))
	Models.add(room, "tv_stand", Vector3(1.6, 0.5, 0.5), Vector3(4.6, 0.0, Z_MID - 0.35), PI)
	tv = Tv.create()
	tv.position = Vector3(4.6, 0.5, Z_MID - 0.35)
	tv.rotation.y = PI
	room.add_child(tv)
	# Sofa-bed by the north wall, open side facing the TV.
	var bed := _furniture(room, Vector3(4.8, 0, Z_ROOMS + 0.8), 0.0)
	_build_bed(bed, Vector3(2.0, 0, 1.2), "sofa")
	# Armchair by the west wall, facing east.
	_solid(room, Vector3(0.8, 0.45, 0.8), Vector3(1.0, 0.225, 6.4))
	_solid(room, Vector3(0.15, 0.5, 0.8), Vector3(0.67, 0.7, 6.4))
	Models.add(room, "armchair", Vector3(0.8, 0.95, 0.8), Vector3(1.0, 0.0, 6.4), PI * 0.5)
	# The remote lies on the floor in front of the TV.
	add_prop(TvRemote.create(tv), Vector3(4.0, 0.05, 7.7), 0.4)
	_spot("BatteryLiving", battery_spots, Vector3(4.0, 0.52, Z_MID - 0.35))


func _build_hall() -> void:
	var room := _group("Hall")
	_room_light(room, Vector3(10.0, H, 5.6))
	Models.add(room, "rug_c", Vector3(1.4, 0.01, 5.0), Vector3(10.0, RUG_Y, 6.4))
	_build_dresser(room, Vector3(X_HALL - 0.1 - 0.225, 0, 6.6), -PI * 0.5, Color("8fb3c9"))
	# The duck is right by the doorway to the corridor — easy to step on in the dark.
	add_prop(Duck.create(), Vector3(9.9, 0.05, 8.9), 0.8)
	# Storage closets: shelves with junk.
	var s1 := _furniture(room, Vector3(8.75, 0, 0.1 + 0.18), 0.0)
	_build_shelf(s1, 1.1)
	var s2 := _furniture(room, Vector3(10.35, 0, 0.1 + 0.18), 0.0)  # clear of the door swinging in
	_build_shelf(s2, 1.4)
	_spot("BatteryCloset", battery_spots, s2.to_global(Vector3(-0.5, 0.79, 0.0)))


func _build_parents_room() -> void:
	var room := _group("ParentsRoom")
	_room_light(room, Vector3(16.2, H, 2.4))
	# Double bed against the east wall.
	var bed := _furniture(room, Vector3(X_EAST - 0.1 - 0.8, 0, 2.4), -PI * 0.5)
	_build_bed(bed, Vector3(2.0, 0, 1.6), "bed_double")
	var wardrobe := _furniture(room, Vector3(15.0, 0, Z_ROOMS - 0.1 - 0.3), PI)
	_build_wardrobe(wardrobe)
	_build_dresser(room, Vector3(13.3, 0, 0.1 + 0.225), 0.0, Color("c98f8f"))


func _build_kitchen() -> void:
	var room := _group("Kitchen")
	_room_light(room, Vector3(2.3, H, 11.9))
	# Fridge in the north-west corner, door facing the room.
	var fridge := _furniture(room, Vector3(0.55, 0, Z_MID + 0.1 + 0.35), 0.0)
	fridge_door = _build_fridge(fridge)
	# Counter + stove along the north wall (clear of the doorway in the east wall).
	var cz := Z_MID + 0.1 + 0.3
	_solid(room, Vector3(1.8, 0.92, 0.6), Vector3(1.95, 0.46, cz))
	Models.add(room, "kitchen_counter", Vector3(1.8, 0.92, 0.6), Vector3(1.95, 0.0, cz))
	_solid(room, Vector3(0.8, 0.9, 0.6), Vector3(3.25, 0.45, cz))
	Models.add(room, "stove", Vector3(0.7, 0.9, 0.6), Vector3(3.25, 0.0, cz))
	# Table (long side north-south), chairs, bowl.
	var table := _furniture(room, Vector3(2.6, 0, 12.2), PI * 0.5)
	_build_table(table, Vector3(1.6, 0.75, 0.9))
	for side: float in [-1.0, 1.0]:
		var chair := _furniture(room, Vector3(2.6 + side * 0.85, 0, 12.2), PI * 0.5 * side)
		_build_chair(chair)
	_build_bowl(Vector3(2.6, 0.78, 12.2))
	cereal = add_prop(SimpleProps.cereal_box(), Vector3(1.4, 0.95, cz), 0.2) as Prop
	_spot("BatteryKitchen", battery_spots, Vector3(2.4, 0.95, cz - 0.05))


func _build_corridor() -> void:
	var room := _group("Corridor")
	_room_light(room, Vector3(7.0, H, 10.5))
	_room_light(room, Vector3(10.4, H, 12.8))
	Models.add(room, "rug_b", Vector3(0.9, 0.01, 2.4), Vector3(7.0, RUG_Y, 10.5), PI * 0.5)
	Models.add(room, "rug_a", Vector3(1.4, 0.01, 0.8), Vector3(10.4, RUG_Y, Z_SOUTH - 0.6))
	_build_dresser(room, Vector3(X_HALL - 0.1 - 0.225, 0, 12.9), -PI * 0.5, Color("a9c98f"))


func _build_bathroom() -> void:
	var room := _group("Bathroom")
	_room_light(room, Vector3(5.7, H, 12.8))
	# Bathtub along the east wall (a solid body, so there's no navmesh island inside).
	var tub := _furniture(room, Vector3(6.35, 0, 13.2), 0.0)
	_solid(tub, Vector3(0.65, 0.55, 1.8), Vector3(0, 0.275, 0))
	Models.add(tub, "bathtub", Vector3(1.8, 0.55, 0.65), Vector3.ZERO, PI * 0.5)
	# Washbasin with a mirror on the east wall, by the door.
	_solid(room, Vector3(0.18, 0.8, 0.18), Vector3(6.6, 0.4, 11.9))
	_solid(room, Vector3(0.45, 0.12, 0.55), Vector3(6.475, 0.86, 11.9))
	Models.add(room, "sink", Vector3(0.5, 1.6, 0.5), Vector3(6.5, 0.0, 11.9), -PI * 0.5)
	_spot("BatteryBath", battery_spots, Vector3(6.45, 0.94, 11.75))


func _build_wc() -> void:
	var room := _group("WC")
	_room_light(room, Vector3(7.8, H, 12.8))
	_solid(room, Vector3(0.4, 0.42, 0.55), Vector3(7.8, 0.21, Z_SOUTH - 0.1 - 0.3))
	_solid(room, Vector3(0.5, 0.45, 0.18), Vector3(7.8, 0.65, Z_SOUTH - 0.1 - 0.09))
	Models.add(room, "toilet", Vector3(0.5, 0, 0), Vector3(7.8, 0.0, Z_SOUTH - 0.1 - 0.35), PI)


func _build_patrol_points() -> void:
	patrol_points = [
		Vector3(5.0, 0, 3.8),  # hero room
		Vector3(2.0, 0, 7.2), Vector3(6.5, 0, 7.6),  # living room
		Vector3(10.0, 0, 4.0), Vector3(10.0, 0, 8.3),  # hall
		Vector3(14.0, 0, 2.4), Vector3(17.5, 0, 3.0),  # parents' room
		Vector3(0.9, 0, 13.4),  # kitchen
		Vector3(6.5, 0, 10.5), Vector3(10.4, 0, 12.8),  # corridor, vestibule
		Vector3(5.3, 0, 12.9), Vector3(7.8, 0, 12.6),  # bathroom, WC
	]


# --- furniture builders (local space: front faces +Z) -----------------------

## Open storage shelf (closets): three planks with boxes on them.
func _build_shelf(root: Node3D, width: float) -> void:
	var d := 0.36
	for sx: float in [-1.0, 1.0]:
		_solid(root, Vector3(0.04, 1.8, d), Vector3(sx * (width * 0.5 - 0.02), 0.9, 0))
	for i in 3:
		_solid(root, Vector3(width, 0.03, d), Vector3(0, 0.15 + i * 0.62, 0))
	Models.add(root, "metal_shelf", Vector3(width, 1.8, d))
	for i in int(width / 0.45):
		var w := randf_range(0.25, 0.35)
		var h := randf_range(0.2, 0.3)
		Models.add(root, "cardboard_box" if i % 2 == 0 else "crate", Vector3(w, h, 0.28), Vector3(-width * 0.5 + 0.25 + i * 0.45, 0.17 + 0.62 * (i % 2 * 2), 0), randf_range(-0.2, 0.2))

func _build_fridge(root: Node3D) -> HingedDoor:
	var w := 0.8
	var d := 0.7
	var h := 1.9
	_solid(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015))
	_solid(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0))
	_solid(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0))
	_solid(root, Vector3(w, 0.03, d), Vector3(0, h - 0.015, 0))
	_solid(root, Vector3(w, 0.06, d), Vector3(0, 0.03, 0))
	for y: float in [0.6, 1.15]:
		_solid(root, Vector3(w - 0.06, 0.02, d - 0.06), Vector3(0, y, 0))
	# The model's front slab becomes the door; the rest is drawn double-sided so its inside shows.
	var parts := Models.split(Models.mesh("fridge", Vector3(w, h, d)), AABB(Vector3(-w, 0.04, d * 0.5 - 0.1), Vector3(w * 2.0, h, 0.4)))
	var body := MeshInstance3D.new()
	body.mesh = Models.double_sided(parts[0])
	root.add_child(body)
	# Wire racks inside (the shelf model fitted to the inner space).
	Models.add(root, "metal_shelf", Vector3(w - 0.08, 1.15 - 0.03, d - 0.1), Vector3(0, 0.06, -0.02))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.6, 0)
	light.omni_range = 0.9
	light.light_energy = 0.6
	root.add_child(light)
	var door := HingedDoor.new()
	door.name = "FridgeDoor"
	# Hinged on the side away from the wall, so the open door swings into the kitchen.
	var hinge := Vector3(w * 0.5, 0.0, d * 0.5)
	door.position = hinge
	door.open_angle = deg_to_rad(105)
	door.open_prompt = "Открыть холодильник"
	door.close_prompt = "Закрыть холодильник"
	door.open_sound = Sfx.CABINET_OPEN
	door.close_sound = Sfx.CABINET_CLOSE
	door.sound_pitch = 0.8
	door.build_mesh_panel(parts[1], -hinge, true)
	root.add_child(door)
	milk = add_prop(SimpleProps.milk(), root.to_global(Vector3(0.1, 0.62, 0.0))) as Prop
	return door


func _build_table(root: Node3D, size: Vector3) -> void:
	_solid(root, Vector3(size.x, 0.05, size.z), Vector3(0, size.y - 0.025, 0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_solid(root, Vector3(0.06, size.y - 0.05, 0.06), Vector3(sx * (size.x * 0.5 - 0.06), (size.y - 0.05) * 0.5, sz * (size.z * 0.5 - 0.06)))
	Models.add(root, "table", size)


func _build_chair(root: Node3D) -> void:
	_solid(root, Vector3(0.42, 0.04, 0.42), Vector3(0, 0.45, 0))
	_solid(root, Vector3(0.42, 0.45, 0.04), Vector3(0, 0.7, 0.19))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_solid(root, Vector3(0.04, 0.45, 0.04), Vector3(sx * 0.18, 0.225, sz * 0.18))
	Models.add(root, "chair", Vector3(0.42, 0.95, 0.42), Vector3.ZERO, PI)  # backrest on +Z


func _build_bowl(pos: Vector3) -> void:
	bowl = StaticBody3D.new()
	bowl.name = "Bowl"
	bowl.position = pos
	bowl.collision_layer = Prop.LAYER_WORLD
	Models.add(bowl, "bowl", Vector3(0.26, 0.07, 0.26))
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
	for c in bowl.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).mesh = Models.mesh("bowl_full", Vector3(0.26, 0.11, 0.26), "", Vector3.ZERO, "", Color(1.0, 0.95, 0.8))


## Bed with the long side along local X and the open side (where you can reach under) at +Z.
## Returns a marker under the bed. The mattress is a Bed (crouch + interact hides under it);
## pass one in to keep a reference to it.
func _build_bed(root: Node3D, size: Vector3, model: String, bed: Bed = null) -> Node3D:
	var l := size.x
	var w := size.z
	var gap := 0.3
	var mattress: Bed = bed if bed else Bed.new()
	mattress.width = w
	mattress.collision_layer = Prop.LAYER_WORLD
	root.add_child(mattress)
	Lowpoly.add_box_shape(mattress, Vector3(l, 0.25, w), Vector3(0, gap + 0.125, 0))
	# Skirts on the back, head and foot so the gap is reachable only from the open side.
	_solid(root, Vector3(l, gap, 0.04), Vector3(0, gap * 0.5, -w * 0.5 + 0.02))
	_solid(root, Vector3(0.06, 0.95, w), Vector3(-l * 0.5 - 0.03, 0.475, 0))
	_solid(root, Vector3(0.06, 0.5, w), Vector3(l * 0.5 + 0.03, 0.25, 0))
	_solid(root, Vector3(0.06, gap, 0.06), Vector3(l * 0.5 - 0.03, gap * 0.5, w * 0.5 - 0.03))
	_solid(root, Vector3(0.06, gap, 0.06), Vector3(-l * 0.5 + 0.03, gap * 0.5, w * 0.5 - 0.03))
	# The model with its base cut away under the mattress (legs and back kept), so the gap is open
	# from the front; double-sided, so from underneath the mattress reads as a low ceiling.
	var full := Models.mesh(model, Vector3(l + 0.12, 0.95, w))
	var cut := Models.split(full, AABB(Vector3(-l * 0.5 + 0.1, -0.05, -w * 0.5 + 0.06), Vector3(l - 0.2, gap + 0.02, w)))
	var mi := MeshInstance3D.new()
	mi.mesh = Models.double_sided(cut[0])
	root.add_child(mi)
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
	var size := Vector3(w, h, d)
	_solid(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015))
	_solid(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0))
	_solid(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0))
	_solid(root, Vector3(w, 0.06, d), Vector3(0, h - 0.03, 0))
	# The model has two drawers at the bottom: the inside floor is on top of them.
	_solid(root, Vector3(w, FLOOR_Y, d), Vector3(0, FLOOR_Y * 0.5, 0))
	Models.add(root, "wardrobe", size, Vector3.ZERO, 0.0, "", "Wardrobe Door")
	for side: float in [-1.0, 1.0]:
		var part := "Wardrobe Door Left" if side < 0.0 else "Wardrobe Door Right"
		var mesh := Models.mesh("wardrobe", size, part)
		if side < 0.0:  # the model's left door is modelled ajar: close it about its hinge
			mesh = Models.straighten(mesh, Vector3(mesh.get_aabb().position.x, 0.0, mesh.get_aabb().position.z))
		var box := mesh.get_aabb()
		var hinge := Vector3(box.position.x if side < 0.0 else box.end.x, 0.0, box.get_center().z)
		var door := HingedDoor.new()
		door.position = hinge
		door.open_angle = deg_to_rad(105.0 * side)
		door.open_prompt = "Открыть шкаф"
		door.close_prompt = "Закрыть шкаф"
		door.open_sound = Sfx.CABINET_OPEN
		door.close_sound = Sfx.CABINET_CLOSE
		door.build_mesh_panel(mesh, -hinge, side > 0.0)
		root.add_child(door)
	var key_spot := Node3D.new()
	key_spot.name = "WardrobeKeySpot"
	key_spot.position = Vector3(0.15, FLOOR_Y + 0.01, 0.05)
	root.add_child(key_spot)
	key_spots.append(key_spot)
	return [root.to_global(Vector3(-0.3, FLOOR_Y + 0.03, 0.0)), root.to_global(Vector3(0.25, FLOOR_Y + 0.03, 0.02))]


func _build_dresser(parent: Node3D, pos: Vector3, yaw: float, vase_color: Color) -> void:
	var root := _furniture(parent, pos, yaw)
	var w := 1.0
	var d := 0.45
	var h := 0.8
	_solid(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015))
	_solid(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0))
	_solid(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0))
	_solid(root, Vector3(w + 0.04, 0.03, d + 0.02), Vector3(0, h - 0.015, 0.01))
	_solid(root, Vector3(w, 0.06, d), Vector3(0, 0.03, 0))
	# Old cream paint; the drawer fronts are cut out of the model along the three slots.
	var model := Models.mesh("dresser", Vector3(w, h, d), "", Vector3.ZERO, "", DRESSER_TINT)
	var slot := (h - 0.09) / 3.0
	var depth := 0.38
	for i in 3:
		var y0 := 0.06 + slot * i
		var parts := Models.split(model, AABB(Vector3(-w * 0.5 + 0.035, y0 + 0.005, d * 0.5 - 0.08), Vector3(w - 0.07, slot - 0.01, 0.3)))
		model = parts[0]
		var drawer_pos := Vector3(0, y0 + slot * 0.5, d * 0.5 - depth * 0.5)
		var drawer := Drawer.create(w - 0.08, slot - 0.02, depth, parts[1], -drawer_pos)
		drawer.position = drawer_pos
		root.add_child(drawer)
		key_spots.append(drawer.content)
	var body := MeshInstance3D.new()
	body.mesh = model
	root.add_child(body)
	# A clock on the wall above.
	Models.add(root, "wall_clock", Vector3(0.36, 0.36, 0.04), Vector3(0, 1.45, -d * 0.5 + 0.02))
	# Vase on top — knocking it off makes a lot of noise.
	add_prop(Vase.create(vase_color), root.to_global(Vector3(0.28, h + 0.01, -0.05)))


func _build_lamp(root: Node3D, pos: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.position = pos
	root.add_child(lamp)
	Models.add(lamp, "table_lamp", Vector3(0, 0.42, 0))
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
	_solid(root, Vector3(w, 0.03, d), Vector3(0, 0.015, 0))
	_solid(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, -d * 0.5 + 0.015))
	_solid(root, Vector3(w, h, 0.03), Vector3(0, h * 0.5, d * 0.5 - 0.015))
	_solid(root, Vector3(0.03, h, d), Vector3(-w * 0.5 + 0.015, h * 0.5, 0))
	_solid(root, Vector3(0.03, h, d), Vector3(w * 0.5 - 0.015, h * 0.5, 0))
	Models.add(root, "toy_box", Vector3(w, h, d))
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


## Invisible static collision box (a model on top provides the looks).
func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Prop.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	Lowpoly.add_box_shape(body, size)
	return body


## Static box with collision on the world layer (or visual only).
func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, collide: bool = true, tex: String = "grain", world: bool = false) -> Node3D:
	if not collide:
		return _mesh(parent, Lowpoly.box(size), color, pos, Vector3.ZERO, tex, world)
	var body := StaticBody3D.new()
	body.collision_layer = Prop.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	_mesh(body, Lowpoly.box(size), color, Vector3.ZERO, Vector3.ZERO, tex, world)
	Lowpoly.add_box_shape(body, size)
	return body


## `world` pins the texture to the world (shell pieces); otherwise it follows the object.
func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, tex: String = "grain", world: bool = false) -> MeshInstance3D:
	var mi := Lowpoly.add_mesh(parent, mesh, color, pos, rot, 0.0, tex)
	if world:
		mi.material_override = Lowpoly.mat(color, 0.9, 0.0, 0.0, tex, true, 0.0, 0.85 if tex == "wallpaper" else 0.0)
	return mi


func _floor(parent: Node3D, r: Rect2, color: Color, tex: String = "wood") -> void:
	_box(parent, Vector3(r.size.x, 0.2, r.size.y), Vector3(r.position.x + r.size.x * 0.5, -0.1, r.position.y + r.size.y * 0.5), color, true, tex, true)


## Wall running along X at depth z, from x0 to x1. Openings: [[centre_x, width, height], ...].
func _wall_x(parent: Node3D, z: float, x0: float, x1: float, openings: Array) -> void:
	for seg: Array in _segments(x0, x1, openings):
		var a: float = seg[0]
		var b: float = seg[1]
		var y0: float = seg[2]
		var y1: float = seg[3]
		_box(parent, Vector3(b - a, y1 - y0, T), Vector3((a + b) * 0.5, (y0 + y1) * 0.5, z), C_WALL, true, "wallpaper", true)
		if y0 == 0.0:
			for side: float in [-1.0, 1.0]:
				_mesh(parent, Lowpoly.box(Vector3(b - a, 0.1, 0.02)), C_WALL_TRIM, Vector3((a + b) * 0.5, 0.05, z + side * (T * 0.5 + 0.01)), Vector3.ZERO, "wood_dark", true)


## Wall running along Z at x, from z0 to z1.
func _wall_z(parent: Node3D, x: float, z0: float, z1: float, openings: Array) -> void:
	for seg: Array in _segments(z0, z1, openings):
		var a: float = seg[0]
		var b: float = seg[1]
		var y0: float = seg[2]
		var y1: float = seg[3]
		_box(parent, Vector3(T, y1 - y0, b - a), Vector3(x, (y0 + y1) * 0.5, (a + b) * 0.5), C_WALL, true, "wallpaper", true)
		if y0 == 0.0:
			for side: float in [-1.0, 1.0]:
				_mesh(parent, Lowpoly.box(Vector3(0.02, 0.1, b - a)), C_WALL_TRIM, Vector3(x + side * (T * 0.5 + 0.01), 0.05, (a + b) * 0.5), Vector3.ZERO, "wood_dark", true)


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
	# A bare bulb on a cord; the bulb is cut from the model so only it glows.
	var lamp := Models.mesh("ceiling_light", Vector3(0, 0.45, 0))
	var parts := Models.split(lamp, AABB(Vector3(-1, -0.01, -1), Vector3(2, 0.1, 2)))
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = parts[i]
		mi.position = ceiling_pos - Vector3(0, 0.45, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		if i == 1:
			_fixtures.append(mi)


func _bake_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Prop.LAYER_WORLD
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.4
	# Taller than the clearance above beds/tables (no walkable islands on furniture), lower than
	# the doorways, and far taller than the vent ducts, which the monster can't enter.
	nm.agent_height = 2.3
	nm.agent_max_climb = 0.2
	# Only the house interior: keeps the roof, the ducts and the balcony out of the bake. The top
	# edge just reaches into the ceiling slab so clearance under it is still measured.
	nm.filter_baking_aabb = AABB(Vector3(-0.1, -0.3, -0.1), Vector3(X_EAST + 0.2, H + 0.35, Z_SOUTH + 0.2))
	navigation_mesh = nm
	bake_navigation_mesh(false)
