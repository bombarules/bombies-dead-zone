extends SceneTree
# Game-level hero check:  DZ_TOUCH=1 xvfb-run -a godot --path . --script tests/hero_game_probe.gd
# Saves fps / third-person / front-view screenshots to /tmp/herogame/.
var scene: Node
var t := 0.0
var step := 0
var out := "/tmp/herogame"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)

func _shot(n: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("[HEROPROBE] saved ", n)

func _process(delta: float) -> bool:
	t += delta
	var p: DeadZonePlayer = scene.get_node("Player")
	if step == 0 and t > 2.0:
		_shot("fps"); p.toggle_view(); step = 1
	elif step == 1 and t > 4.0:
		_shot("tps_idle"); step = 2
		p._firing = true
	elif step == 2 and t > 5.2:
		_shot("tps_fire"); p._firing = false; step = 3
		Input.action_press("move_forward")
	elif step == 3 and t > 7.0:
		_shot("tps_walk"); Input.action_release("move_forward"); p.toggle_view(); step = 4
	elif step == 4 and t > 9.5:
		_shot("front"); p.toggle_view(); step = 5
	elif step == 5 and t > 10.5 and not p.aiming:
		p.aiming = true
	elif step == 5 and t > 11.2:
		_shot("fps_aim"); step = 6
		print("[HEROPROBE] ammo=", p.ammo_in_mag, " view=", p.view_mode)
		quit()
	return false
