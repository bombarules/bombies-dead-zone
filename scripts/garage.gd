class_name Garage
extends Node3D

# Flooded underground parking garage, built at runtime from boxes + procedural
# textures: concrete floor under murky standing water, pillar grid, rusted parked
# cars, a ramp to a mezzanine, debris, amber tube lights and a red emergency light.
# Palette: charcoal / olive concrete, acid yellow hero accents, amber + red light.

const SIZE_X := 44.0
const SIZE_Z := 36.0
const WALL_H := 5.0
const WATER_Y := 0.14

var _flicker_light: OmniLight3D
var _flicker_base: float = 2.2
var _flicker_t: float = 0.0
var _exit_light: OmniLight3D
var _exit_sign_mat: StandardMaterial3D

var spawn_points: Array[Vector3] = []

func _ready() -> void:
	var concrete := _make_material(_concrete_texture(), 0.18, 0.55, 0.05)
	var dark_concrete := _make_material(_concrete_texture(true), 0.18, 0.7, 0.0)
	var rust := _make_material(_rust_texture(), 0.25, 0.8, 0.15)
	_build_shell(concrete, dark_concrete)
	_build_pillars(dark_concrete)
	_build_cars(rust)
	_build_ramp(dark_concrete)
	_build_debris(rust)
	_build_water()
	_build_lights()
	_build_exit()
	spawn_points = [
		Vector3(-19, 0, -15), Vector3(19, 0, -15), Vector3(-19, 0, 15),
		Vector3(19, 0, 15), Vector3(0, 0, -16), Vector3(-14, 0, 0),
		Vector3(14, 0, 0), Vector3(0, 3.4, -12),
	]

func get_player_spawn() -> Vector3:
	return Vector3(0, 0.1, 14)

func random_spawn_point(min_dist_to: Vector3, min_dist: float) -> Vector3:
	var candidates: Array[Vector3] = []
	for p in spawn_points:
		if p.distance_to(min_dist_to) >= min_dist:
			candidates.append(p)
	if candidates.is_empty():
		return spawn_points[randi() % spawn_points.size()]
	return candidates[randi() % candidates.size()]

func set_exit_open(open: bool) -> void:
	if open:
		_exit_light.light_color = Color(0.2, 1.0, 0.35)
		_exit_light.light_energy = 4.0
		_exit_sign_mat.emission = Color(0.1, 1.0, 0.3)
		_exit_sign_mat.emission_enabled = true

func _process(delta: float) -> void:
	# Red emergency light flicker: mostly on, with irregular dropouts.
	_flicker_t += delta
	var f := 1.0
	var n := sin(_flicker_t * 13.0) * sin(_flicker_t * 7.3 + 1.7)
	if n > 0.86:
		f = 0.15
	elif n > 0.6:
		f = 0.55
	_flicker_light.light_energy = _flicker_base * f

# --- materials / textures -----------------------------------------------------

func _make_material(tex: Texture2D, world_scale: float, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(world_scale, world_scale, world_scale)
	return m

func _concrete_texture(dark: bool = false) -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var base := Color(0.16, 0.17, 0.15) if dark else Color(0.32, 0.33, 0.30)
	for y in range(s):
		for x in range(s):
			var n := randf()
			var stain := 0.0
			var dx := float(x - 64) / 64.0
			var dy := float(y - 64) / 64.0
			if dx * dx + dy * dy < 0.5:
				stain = 0.25 * randf()
			var v := clampf(0.75 + n * 0.5 - stain, 0.0, 1.2)
			img.set_pixel(x, y, base * v)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _rust_texture() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in range(s):
		for x in range(s):
			var n := randf()
			var c: Color
			if n < 0.45:
				c = Color(0.32, 0.18, 0.10) # rust brown
			elif n < 0.75:
				c = Color(0.25, 0.24, 0.20) # grimy olive-grey
			else:
				c = Color(0.45, 0.30, 0.16) # flaked orange rust
			img.set_pixel(x, y, c * (0.7 + randf() * 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# --- geometry helpers ---------------------------------------------------------

func _add_box(box_size: Vector3, pos: Vector3, mat: Material, collide: bool = true, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mi.mesh = box
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	body.add_child(mi)
	if collide:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		col.shape = shape
		body.add_child(col)
	add_child(body)
	return body

func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi

# --- level --------------------------------------------------------------------

func _build_shell(concrete: Material, dark: Material) -> void:
	# Floor, ceiling and perimeter walls.
	_add_box(Vector3(SIZE_X, 1.0, SIZE_Z), Vector3(0, -0.5, 0), concrete)
	_add_box(Vector3(SIZE_X, 0.6, SIZE_Z), Vector3(0, WALL_H + 0.3, 0), dark, false)
	var half_x := SIZE_X / 2.0
	var half_z := SIZE_Z / 2.0
	_add_box(Vector3(SIZE_X + 1.0, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, -half_z), dark)
	_add_box(Vector3(SIZE_X + 1.0, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, half_z), dark)
	_add_box(Vector3(1.0, WALL_H, SIZE_Z + 1.0), Vector3(-half_x, WALL_H / 2.0, 0), dark)
	_add_box(Vector3(1.0, WALL_H, SIZE_Z + 1.0), Vector3(half_x, WALL_H / 2.0, 0), dark)

func _build_pillars(mat: Material) -> void:
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		for z in [-12.0, -4.0, 4.0, 12.0]:
			if absf(x) < 2.0 and absf(z - 12.0) < 2.0:
				continue # keep the player spawn clear
			_add_box(Vector3(1.1, WALL_H, 1.1), Vector3(x, WALL_H / 2.0, z), mat)

func _build_cars(rust: Material) -> void:
	var spots: Array = [
		[Vector3(-13, 0.55, -8), 0.3], [Vector3(-5, 0.55, -13), -0.15],
		[Vector3(6, 0.55, -9), 1.62], [Vector3(13, 0.55, -13), 0.1],
		[Vector3(-14, 0.55, 2), 1.45], [Vector3(12, 0.55, 3), -1.5],
		[Vector3(-6, 0.55, 9), 0.05], [Vector3(9, 0.55, 11), 0.2],
		[Vector3(16, 0.55, -4), 1.57], [Vector3(-17, 0.55, -13), -0.4],
	]
	for spot in spots:
		var pos: Vector3 = spot[0]
		var rot_y: float = spot[1]
		var car := StaticBody3D.new()
		car.position = pos
		car.rotation.y = rot_y
		var body_mi := MeshInstance3D.new()
		var body_box := BoxMesh.new()
		body_box.size = Vector3(1.9, 0.62, 4.4)
		body_mi.mesh = body_box
		body_mi.material_override = rust
		body_mi.position = Vector3(0, 0.55, 0)
		car.add_child(body_mi)
		var cabin_mi := MeshInstance3D.new()
		var cabin_box := BoxMesh.new()
		cabin_box.size = Vector3(1.7, 0.55, 2.2)
		cabin_mi.mesh = cabin_box
		cabin_mi.material_override = rust
		cabin_mi.position = Vector3(0, 1.1, -0.2)
		car.add_child(cabin_mi)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.0, 1.5, 4.5)
		col.shape = shape
		col.position = Vector3(0, 0.75, 0)
		car.add_child(col)
		add_child(car)

func _build_ramp(mat: Material) -> void:
	# Sloped ramp up the north wall to a mezzanine platform.
	var ramp := _add_box(Vector3(4.0, 0.4, 9.0), Vector3(-4, 1.7, -13.5), mat)
	ramp.rotation.x = -0.38
	_add_box(Vector3(6.0, 0.4, 6.0), Vector3(-4, 3.4, -15.5), mat)
	# No barrier along the platform edge: Bombies must be able to walk off it
	# toward the player instead of getting wedged there.

func _build_debris(mat: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 26:
		var s := rng.randf_range(0.3, 1.1)
		_add_box(Vector3(s, s * 0.6, s), Vector3(rng.randf_range(-20, 20), s * 0.3, rng.randf_range(-16, 16)), mat, true, rng.randf_range(0, TAU))
	# Crates stacked near the south wall.
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(18, 0.6, 12), mat)
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(18, 0.6, 13.4), mat)
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(18, 1.8, 12.7), mat)

func _build_water() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec4 shallow_color : source_color = vec4(0.16, 0.20, 0.14, 0.72);
uniform vec4 deep_color : source_color = vec4(0.05, 0.08, 0.06, 0.85);
uniform float ripple_speed = 0.6;
varying vec2 wuv;
void vertex() {
	wuv = VERTEX.xz;
	VERTEX.y += sin(VERTEX.x * 0.8 + TIME * ripple_speed) * 0.012 + cos(VERTEX.z * 0.7 + TIME * ripple_speed * 0.8) * 0.012;
}
void fragment() {
	float r = sin(wuv.x * 0.9 + TIME * 0.7) * cos(wuv.y * 1.1 - TIME * 0.5);
	float g = sin((wuv.x + wuv.y) * 0.6 - TIME * 0.4);
	float mixv = clamp(0.5 + 0.25 * r + 0.25 * g, 0.0, 1.0);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, mixv);
	ALPHA = mix(deep_color.a, shallow_color.a, mixv);
	ROUGHNESS = 0.08;
	METALLIC = 0.35;
	SPECULAR = 0.9;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE_X, SIZE_Z)
	plane.subdivide_width = 24
	plane.subdivide_depth = 20
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, WATER_Y, 0)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)

func _tube_light(pos: Vector3, color: Color, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 16.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	add_child(light)
	var tube_mat := StandardMaterial3D.new()
	tube_mat.albedo_color = color
	tube_mat.emission_enabled = true
	tube_mat.emission = color
	tube_mat.emission_energy_multiplier = 3.0
	var tube := BoxMesh.new()
	tube.size = Vector3(3.0, 0.08, 0.18)
	var mi := MeshInstance3D.new()
	mi.mesh = tube
	mi.material_override = tube_mat
	mi.position = pos + Vector3(0, 0.25, 0)
	add_child(mi)
	return light

func _build_lights() -> void:
	_tube_light(Vector3(-8, 4.4, -6), Color(1.0, 0.62, 0.25), 2.6)
	_tube_light(Vector3(10, 4.4, 6), Color(1.0, 0.62, 0.25), 2.0)
	_tube_light(Vector3(0, 4.4, 13), Color(1.0, 0.55, 0.2), 1.5)
	_flicker_light = _tube_light(Vector3(-16, 4.4, 12), Color(1.0, 0.12, 0.08), _flicker_base)
	# Cold spill from the stairwell.
	var spill := OmniLight3D.new()
	spill.position = Vector3(18, 3.5, -15)
	spill.light_color = Color(0.55, 0.7, 0.9)
	spill.light_energy = 1.0
	spill.omni_range = 12.0
	add_child(spill)

func _build_exit() -> void:
	# Stairwell door + EXIT sign on the north-east wall.
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.12, 0.14, 0.12)
	door_mat.roughness = 0.6
	door_mat.metallic = 0.4
	_add_box(Vector3(2.4, 3.4, 0.4), Vector3(18, 1.7, -17.4), door_mat)
	_exit_sign_mat = StandardMaterial3D.new()
	_exit_sign_mat.albedo_color = Color(0.05, 0.2, 0.08)
	_exit_sign_mat.emission_enabled = true
	_exit_sign_mat.emission = Color(0.1, 0.6, 0.2)
	_exit_sign_mat.emission_energy_multiplier = 1.5
	var sign := BoxMesh.new()
	sign.size = Vector3(1.6, 0.5, 0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = sign
	mi.material_override = _exit_sign_mat
	mi.position = Vector3(18, 3.9, -17.2)
	add_child(mi)
	_exit_light = OmniLight3D.new()
	_exit_light.position = Vector3(18, 3.6, -16.0)
	_exit_light.light_color = Color(0.2, 1.0, 0.35)
	_exit_light.light_energy = 0.8
	_exit_light.omni_range = 8.0
	add_child(_exit_light)
