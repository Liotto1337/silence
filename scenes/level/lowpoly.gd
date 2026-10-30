class_name Lowpoly
extends RefCounted
## Shared PS1 materials and helpers for the house shell (boxes) and collision shapes.

const PS1_SHADER := preload("res://shaders/ps1.gdshader")

static var _materials: Dictionary = {}
static var _textures: Dictionary = {}


## Drops cached resources (called on quit so nothing is reported as leaked).
static func clear_cache() -> void:
	_materials.clear()
	_textures.clear()


## Shared PS1 material. `tex` is a name from assets/textures/ (neutral detail map, tinted by `color`);
## `world` pins the texture to the world instead of the object (walls, floors, ceilings).
static func mat(color: Color, roughness: float = 0.9, metallic: float = 0.0, emission: float = 0.0, tex: String = "grain", world: bool = false, affine: float = 0.6, dirt: float = 0.0, uv_scale: float = 1.0) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.2f|%s|%s|%.2f|%.2f|%.2f" % [color.to_html(), roughness, metallic, emission, tex, world, affine, dirt, uv_scale]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = PS1_SHADER
	m.set_shader_parameter("albedo_tex", _texture(tex))
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("roughness_value", roughness)
	m.set_shader_parameter("metallic_value", metallic)
	m.set_shader_parameter("world_uv", world)
	if world:
		# No vertex snapping on the shell: on huge floor/wall quads it shifts the depth by centimetres
		# and the floor pokes through rugs and skirting along the quad's diagonal.
		m.set_shader_parameter("snap_grid", Vector2.ZERO)
	m.set_shader_parameter("affine", affine)
	m.set_shader_parameter("dirt", dirt)
	m.set_shader_parameter("uv_scale", uv_scale)
	if emission > 0.0:
		m.set_shader_parameter("emission_color", color)
		m.set_shader_parameter("emission_energy", emission)
	_materials[key] = m
	return m


## Plain white texture for materials that only have a colour.
static func white_texture() -> Texture2D:
	if not _textures.has("__white"):
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_textures["__white"] = ImageTexture.create_from_image(img)
	return _textures["__white"]


static func _texture(tex: String) -> Texture2D:
	if not _textures.has(tex):
		_textures[tex] = load("res://assets/textures/%s.png" % tex)
	return _textures[tex]


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Adds a coloured mesh instance to parent at a local position.
static func add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, emission: float = 0.0, tex: String = "grain") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, 0.85, 0.0, emission, tex)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func add_box_shape(body: CollisionObject3D, size: Vector3, pos: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	return cs
