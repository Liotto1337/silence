class_name SleepBlanket
extends Node3D
## The blanket the hero pulls up over their head when they fall asleep, seen from underneath: a
## draped cloth in front of the camera, wider than the view (it spans the whole screen from side to
## side) and pulled up to the chin only: the upper part of the view stays free. Its texture is cut out of the one on the blanket of the bed (the bed
## model's atlas): the plush part makes the cloth, the fringed edge the hem.
## Add it as a child of the camera; `position.y` is what moves it (`hidden_y()` .. 0).

const BED_MODEL := "bed_single"
const OVERLAY_SHADER := preload("res://shaders/ps1_overlay.gdshader")  ## ignores depth: no wall cuts into the cloth
const DIST := 0.4  ## metres in front of the camera
const MIN_HEIGHT := 1.1  ## cloth height (the view is 0.58 m at that distance)
const HEM := 0.11  ## height of the fringed edge
const WIDTH_MARGIN := 1.4  ## times the width of the view: the head sways and the cloth ripples
const REST_FRACTION := 0.46  ## height of the hem at rest, as a part of the view's height from the bottom
const CLOTH_RECT := Rect2i(4, 14, 56, 25)  ## the plush part of the blanket in the bed's atlas, pixels
const HEM_RECT := Rect2i(0, 0, 64, 13)  ## its fringed edge
const CLOTH_TILE := Vector2(0.5, 0.24)  ## metres of cloth per repeat of the patch
const HEM_TILE := 0.55
const COLS := 22
const ROWS := 12

var width: float = 1.0
var height: float = MIN_HEIGHT
var view: Vector2 = Vector2(1.0, 0.58)  ## size of the screen's window on the cloth, metres

var _light: OmniLight3D


## A blanket for `camera` (its field of view) on a screen of this `aspect` ratio, hidden below the view.
static func create(camera: Camera3D, aspect: float) -> SleepBlanket:
	var b := SleepBlanket.new()
	b.name = "SleepBlanket"
	b.view = view_size(camera, aspect)
	b.width = b.view.x * WIDTH_MARGIN
	b.height = maxf(MIN_HEIGHT, b.view.y * 1.9)
	b._build()
	b.position = Vector3(0.0, b.hidden_y(), -DIST)
	b.visible = false
	return b


## Size of what the camera sees at the blanket's distance.
static func view_size(camera: Camera3D, aspect: float) -> Vector2:
	var span := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) * DIST
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		return Vector2(span, span / aspect)
	return Vector2(span * aspect, span)


## `position.y` with the whole cloth below the view.
func hidden_y() -> float:
	return -(view.y + height) * 0.5 - 0.04


## `position.y` with the hem `fraction` of the view's height up from its bottom edge.
func hem_y(fraction: float) -> float:
	return -view.y * 0.5 + view.y * fraction - height * 0.5


## Where the blanket ends up: pulled to the chin, the whole width of the screen but only the lower
## part of its height, so the upper part of the view stays free.
func rest_y() -> float:
	return hem_y(REST_FRACTION)


## Does the cloth span the whole width of the view while the upper part of it stays free?
func spans_width_only() -> bool:
	var hem_screen := position.y + height * 0.5 + view.y * 0.5  # hem height above the view's bottom
	return width >= view.x and hem_screen > 0.0 and hem_screen < view.y * 0.7


## Shows the cloth and lights it (the light only exists while the blanket is on screen).
func reveal() -> void:
	visible = true
	_light.visible = true


func _build() -> void:
	var src := Models.albedo(BED_MODEL)
	var img := src.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	var cloth_tex: Texture2D
	var hem_tex: Texture2D
	if img == null or img.is_empty() or img.get_width() < CLOTH_RECT.end.x or img.get_height() < CLOTH_RECT.end.y:
		cloth_tex = _flat(Color("7a1512"))
		hem_tex = _flat(Color("3a0706"))
	else:
		img.clear_mipmaps()
		cloth_tex = ImageTexture.create_from_image(img.get_region(CLOTH_RECT))
		hem_tex = ImageTexture.create_from_image(img.get_region(HEM_RECT))
	var mesh := ArrayMesh.new()
	var top := height * 0.5
	var cloth_uv := func(x: float, y: float) -> Vector2:
		return Vector2(x / CLOTH_TILE.x + 0.37, (top - y) / CLOTH_TILE.y)
	var hem_uv := func(x: float, y: float) -> Vector2:
		return Vector2(x / HEM_TILE + 0.12, (top - y) / HEM)
	_add_grid(mesh, -top, top - HEM, ROWS, cloth_uv, _material(cloth_tex))
	_add_grid(mesh, top - HEM, top, 2, hem_uv, _material(hem_tex))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Cloth"
	add_child(mi)
	# Light between the face and the cloth: the room's light comes from above, and the cloth faces down.
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.position = Vector3(0.0, 0.0, 0.3)
	_light.omni_range = 1.6
	_light.light_energy = 0.7
	_light.light_color = Color(1.0, 0.84, 0.72)
	_light.visible = false
	add_child(_light)


## A grid of `COLS` x `rows` quads between two heights, folded by `_fold`. UVs come from `uv_of`.
func _add_grid(mesh: ArrayMesh, y0: float, y1: float, rows: int, uv_of: Callable, mat: Material) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in rows + 1:
		var y := lerpf(y0, y1, float(j) / rows)
		for i in COLS + 1:
			var x := lerpf(-width * 0.5, width * 0.5, float(i) / COLS)
			verts.append(Vector3(x, y, _fold(x, y)))
			var dzdx := (_fold(x + 0.01, y) - _fold(x - 0.01, y)) / 0.02
			var dzdy := (_fold(x, y + 0.01) - _fold(x, y - 0.01)) / 0.02
			normals.append(Vector3(-dzdx, -dzdy, 1.0).normalized())
			uvs.append(uv_of.call(x, y))
	for j in rows:
		for i in COLS:
			var bl := j * (COLS + 1) + i
			var br := bl + 1
			var tl := bl + COLS + 1
			var tr := tl + 1
			idx.append_array([bl, tl, tr, bl, tr, br])  # clockwise seen from the camera
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Depth of the cloth (towards the camera): vertical creases, and a bulge in the middle where it
## lies over the face.
func _fold(x: float, y: float) -> float:
	var creases := 0.024 * sin(x * 6.5 + sin(y * 2.3) * 0.9) + 0.011 * sin(x * 15.0 + y * 1.7 + 1.3)
	var bulge := 0.03 * (1.0 - minf(x * x, 1.0))
	return creases + bulge


static func _material(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OVERLAY_SHADER
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("use_mesh_uv", true)
	m.set_shader_parameter("affine", 0.0)  # the cloth is right in front of the eyes: no texture swimming
	m.set_shader_parameter("roughness_value", 1.0)
	return m


static func _flat(color: Color) -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
