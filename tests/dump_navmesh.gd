extends Node
## Debug helper: dumps the baked navmesh polygons and static boxes to JSON for plotting.

func _ready() -> void:
	var game: Node3D = (load(GameState.GAME_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(0.5).timeout
	var nm: NavigationMesh = game.house.navigation_mesh
	var verts := nm.get_vertices()
	var polys := []
	for i in nm.get_polygon_count():
		var poly := []
		for idx in nm.get_polygon(i):
			poly.append([verts[idx].x, verts[idx].y, verts[idx].z])
		polys.append(poly)
	var boxes := []
	for body in game.house.find_children("*", "StaticBody3D", true, false):
		for cs in body.get_children():
			if cs is CollisionShape3D and cs.shape is BoxShape3D:
				var t: Transform3D = cs.global_transform
				var s: Vector3 = cs.shape.size
				boxes.append([t.origin.x, t.origin.y, t.origin.z, s.x, s.y, s.z, t.basis.get_euler().y])
	var f := FileAccess.open(OS.get_environment("NAV_DUMP"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"polys": polys, "boxes": boxes}))
	f.close()
	get_tree().quit()
