extends SceneTree
# Simulated-touch smoke test:  DZ_TOUCH=1 xvfb-run -a godot --path . --script tests/touch_probe.gd
var scene: Node
var t := 0.0
var step := 0

func _initialize() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)

func _process(delta: float) -> bool:
	t += delta
	var p: DeadZonePlayer = scene.get_node("Player")
	var sz := root.get_visible_rect().size
	if step == 0 and t > 1.0:
		step = 1
		print("[PROBE] viewport ", sz, " touch_node=", scene.get_node("Game").touch != null)
		_touch(0, Vector2(180, sz.y - 180), true)
		_drag(0, Vector2(180, sz.y - 300), Vector2(0, -120))
	elif step == 1 and t > 1.6:
		step = 2
		print("[PROBE] forward strength=", Input.get_action_strength("move_forward"), " pos=", p.global_position)
		var yaw := p.rotation.y
		_touch(1, Vector2(sz.x * 0.7, sz.y * 0.4), true)
		_drag(1, Vector2(sz.x * 0.7 + 100, sz.y * 0.4), Vector2(100, 0))
		print("[PROBE] yaw delta=", p.rotation.y - yaw)
		_touch(1, Vector2(sz.x * 0.7 + 100, sz.y * 0.4), false)
		_touch(2, Vector2(sz.x - 125, sz.y - 125), true)  # fire
	elif step == 2 and t > 2.4:
		step = 3
		print("[PROBE] yaw now=", p.rotation.y, " ammo=", p.ammo_in_mag, " firing=", p._firing)
		_touch(2, Vector2(sz.x - 125, sz.y - 125), false)
		_touch(3, Vector2(sz.x - 262, sz.y - 165), true)  # grenade
		_touch(3, Vector2(sz.x - 262, sz.y - 165), false)
		_touch(4, Vector2(sz.x - 360, sz.y - 100), true)  # mine
		_touch(4, Vector2(sz.x - 360, sz.y - 100), false)
		_touch(5, Vector2(70, sz.y - 360), true)  # sprint
		_touch(5, Vector2(70, sz.y - 360), false)
		_touch(6, Vector2(sz.x - 145, 128), true)  # view
		_touch(6, Vector2(sz.x - 145, 128), false)
	elif step == 3 and t > 3.2:
		step = 4
		print("[PROBE] gren=", p.grenades, " mines=", p.mines, " sprint=", Input.is_action_pressed("sprint"), " view=", p.view_mode)
		root.get_viewport().get_texture().get_image().save_png("/tmp/touch_probe.png")
		p.take_damage(1000.0)
	elif step == 4 and t > 4.0:
		step = 5
		print("[PROBE] state=", scene.get_node("Game").state)
		root.get_viewport().get_texture().get_image().save_png("/tmp/touch_probe_lose.png")
		_touch(7, Vector2(300, 300), true)  # still in guard window? wait
	elif step == 5 and t > 5.2:
		step = 6
		_touch(8, Vector2(300, 300), true)
		_touch(8, Vector2(300, 300), false)
	elif step == 6 and t > 5.8:
		print("[PROBE] after restart state=", current_scene, " player alive=", root.get_node("DeadZone/Player").alive if root.has_node("DeadZone/Player") else "n/a")
		quit()
	return false
