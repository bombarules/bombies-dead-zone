extends SceneTree
# xvfb-run -a godot --path . --script tests/hero_preview.gd -- out_dir
var rig: HeroRig
var cam: Camera3D
var step := 0
var t := 0.0
var out := "/tmp/heroshots"
var views := [
	["front", Vector3(0, 1.0, -3.6), Vector3(0, .95, 0), 0.0, 0.0, 0.0],
	["front_close", Vector3(0, 1.62, -1.5), Vector3(0, 1.45, 0), 0.0, 0.0, 0.0],
	["threeq", Vector3(2.2, 1.2, -2.8), Vector3(0, .95, 0), 0.0, 0.0, 0.0],
	["side", Vector3(3.6, 1.0, 0.0), Vector3(0, .95, 0), 0.0, 0.0, 0.0],
	["back", Vector3(0, 1.1, 3.6), Vector3(0, .95, 0), 0.0, 0.0, 0.0],
	["raised_threeq", Vector3(2.2, 1.3, -2.4), Vector3(0, 1.0, 0), 1.0, 0.0, 0.0],
	["walk_side", Vector3(3.2, 1.0, -0.8), Vector3(0, .95, 0), 0.0, 1.9, 1.0],
	["raised_front", Vector3(0.6, 1.4, -2.6), Vector3(0, 1.2, -.2), 1.0, 0.0, 0.0],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.52)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var key := DirectionalLight3D.new(); key.light_energy = 1.6; key.light_color = Color(1.0, 0.93, 0.82)
	key.rotation_degrees = Vector3(-35, 25, 0); key.shadow_enabled = true; root.add_child(key)
	var fill := DirectionalLight3D.new(); fill.light_energy = 0.5; fill.light_color = Color(0.6, 0.7, 0.9)
	fill.rotation_degrees = Vector3(-20, -150, 0); root.add_child(fill)
	var floor_mi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(12, 12); floor_mi.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.2, 0.2, 0.2); floor_mi.material_override = fm; root.add_child(floor_mi)
	rig = HeroRig.new(); root.add_child(rig)
	cam = Camera3D.new(); cam.fov = 40; root.add_child(cam); cam.current = true
	

func _process(delta: float) -> bool:
	t += delta
	if t < 0.5:
		return false
	if step >= views.size():
		quit(); return true
	var v: Array = views[step]
	cam.position = v[1]
	cam.look_at(v[2], Vector3.UP)
	rig.set_pose(v[4], v[5], v[3], 0.0, delta)
	if t > 0.5 + 0.4*(step+1):
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out, v[0]])
		step += 1
	return false
