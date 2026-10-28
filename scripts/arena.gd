extends Node3D

# Builds a Quake/Doom-style box arena at runtime: a floor, four perimeter walls,
# and a handful of interior obstacle blocks. Everything is plain BoxMesh geometry
# with simple box StaticBody3D collision.
#
# Textures are generated procedurally as tiny 64x64 images with nearest-neighbour
# filtering — zero asset files, zero import step, guaranteed seamless tiling.
# Two shared materials (floor + wall) keep draw-call/material churn minimal.
# No shadows, per-vertex shading, GI disabled — built for the weakest hardware.

const ARENA_SIZE: float = 40.0   # floor is ARENA_SIZE x ARENA_SIZE
const WALL_HEIGHT: float = 6.0
const WALL_THICK: float = 1.0
const TEX_SIZE: int = 64

var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D

func _ready() -> void:
	var floor_tex := _load_tex("res://textures/floor.png", _make_floor_texture())
	var brick_tex := _load_tex("res://textures/brick.png", _make_brick_texture())
	# world_scale = texture repeats per world unit; 0.25 -> one tile image every 4 units.
	_floor_mat = _make_material(floor_tex, 0.25)
	_wall_mat = _make_material(brick_tex, 0.2)
	_build_floor()
	_build_walls()
	_build_obstacles()
	_build_steps()

# Prefer the imported texture (works in exported builds); fall back to reading the
# raw PNG directly (works in-editor before Godot has imported it); finally fall
# back to the procedurally generated texture so the arena always has a surface.
func _load_tex(res_path: String, fallback: Texture2D) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var t = load(res_path)
		if t is Texture2D:
			return t
	var img := Image.new()
	if img.load(res_path) == OK:
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	return fallback

# --- materials ---------------------------------------------------------------

func _make_material(tex: Texture2D, world_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX  # cheap lighting, no per-pixel
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# World-space triplanar: texel size is constant on every face regardless of box
	# dimensions, so nothing stretches and it tiles seamlessly across boxes.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(world_scale, world_scale, world_scale)
	return m

# --- procedural textures -----------------------------------------------------

func _make_brick_texture() -> ImageTexture:
	var s := TEX_SIZE
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var mortar := Color(0.22, 0.20, 0.18)
	var brick_a := Color(0.55, 0.30, 0.22)
	var brick_b := Color(0.48, 0.26, 0.19)
	var brick_h := 16
	var brick_w := 32
	var mortar_px := 2
	for y in range(s):
		var row := y / brick_h
		var offset := (brick_w / 2) if (row % 2 == 1) else 0
		for x in range(s):
			var col := brick_a if (row % 2 == 0) else brick_b
			var yy := y % brick_h
			var xx := (x + offset) % brick_w
			if yy < mortar_px or xx < mortar_px:
				col = mortar
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_floor_texture() -> ImageTexture:
	var s := TEX_SIZE
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var base_a := Color(0.30, 0.30, 0.33)
	var base_b := Color(0.25, 0.25, 0.28)
	var grout := Color(0.14, 0.14, 0.16)
	var tile := 32
	var line := 2
	for y in range(s):
		for x in range(s):
			var checker := (x / tile + y / tile) % 2 == 0
			var col := base_a if checker else base_b
			if (x % tile) < line or (y % tile) < line:
				col = grout
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# --- geometry ----------------------------------------------------------------

func _add_box(box_size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)

	add_child(body)

func _build_floor() -> void:
	_add_box(Vector3(ARENA_SIZE, WALL_THICK, ARENA_SIZE), Vector3(0, -WALL_THICK / 2.0, 0), _floor_mat)

func _build_walls() -> void:
	var half := ARENA_SIZE / 2.0
	var h := WALL_HEIGHT
	var span := ARENA_SIZE + WALL_THICK
	# North / South walls run along X.
	_add_box(Vector3(span, h, WALL_THICK), Vector3(0, h / 2.0, -half), _wall_mat)
	_add_box(Vector3(span, h, WALL_THICK), Vector3(0, h / 2.0, half), _wall_mat)
	# East / West walls run along Z.
	_add_box(Vector3(WALL_THICK, h, span), Vector3(-half, h / 2.0, 0), _wall_mat)
	_add_box(Vector3(WALL_THICK, h, span), Vector3(half, h / 2.0, 0), _wall_mat)

func _build_obstacles() -> void:
	# A few crates, pillars, and a low step to navigate and jump on.
	_add_box(Vector3(4, 3, 4), Vector3(-8, 1.5, -6), _wall_mat)
	_add_box(Vector3(4, 3, 4), Vector3(9, 1.5, 7), _wall_mat)
	_add_box(Vector3(2, 5, 2), Vector3(6, 2.5, -10), _wall_mat)   # pillar
	_add_box(Vector3(2, 5, 2), Vector3(-11, 2.5, 9), _wall_mat)   # pillar
	_add_box(Vector3(10, 1.0, 3), Vector3(0, 0.5, 0), _wall_mat)  # low step / platform

func _build_steps() -> void:
	# A staircase of 1-unit rises so each hop is well within the ~1.4-unit jump
	# reach. Climbs from the floor up to 5 units, close enough to vault onto the
	# 6-unit wall top from the last step.
	for i in range(5):
		var top := float(i + 1)              # step tops at 1, 2, 3, 4, 5
		var z := -6.0 + i * 3.0              # march along Z so you jump forward + up
		_add_box(Vector3(3, top, 3), Vector3(14, top / 2.0, z), _wall_mat)
