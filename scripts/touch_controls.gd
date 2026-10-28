class_name TouchControls
extends CanvasLayer

# On-screen touch controls for phones/tablets (landscape): floating left
# joystick, drag-to-look on the right side, and action buttons. Only created on
# touch devices (see is_touch_device()); desktop keeps keyboard + mouse.

const LOOK_SENS := 0.0042      # radians per viewport pixel
const STICK_RADIUS := 105.0

var player: DeadZonePlayer
var game: DeadZone

var _canvas: Control
var _vp_size := Vector2(1280, 720)
var _buttons: Array[Dictionary] = []  # {id,label,pos,r,hold,toggle,on,touch}
var _touches: Dictionary = {}          # finger index -> {kind, ...}
var _stick_base := Vector2(170, 540)
var _stick_home := Vector2(170, 540)
var _stick_knob := Vector2.ZERO
var _stick_active := false
var _stick_vec := Vector2.ZERO
var _restart_guard := 0.0
var _font: Font

static func is_touch_device() -> bool:
	if OS.has_environment("DZ_TOUCH"):
		return true
	if OS.has_feature("android") or OS.has_feature("ios"):
		return true
	return DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_canvas.draw.connect(_draw_ui)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _exit_tree() -> void:
	_release_all()

func _layout() -> void:
	_vp_size = get_viewport().get_visible_rect().size
	var w := _vp_size.x
	var h := _vp_size.y
	_stick_home = Vector2(185, h - 175)
	if not _stick_active:
		_stick_base = _stick_home
	var prev := {}
	for b in _buttons:
		prev[b["id"]] = [b["on"], b["touch"]]
	_buttons.clear()
	_add("fire", "FIRE", Vector2(w - 125, h - 125), 66, true, false)
	_add("jump", "JUMP", Vector2(w - 105, h - 262), 38, true, false)
	_add("reload", "RELOAD", Vector2(w - 255, h - 70), 36, false, false)
	_add("grenade", "GREN", Vector2(w - 262, h - 165), 36, false, false)
	_add("ads", "ADS", Vector2(w - 222, h - 270), 38, false, true)
	_add("mine", "MINE", Vector2(w - 360, h - 100), 34, false, false)
	_add("acid", "ACID", Vector2(w - 365, h - 195), 34, false, false)
	_add("sprint", "SPRINT", Vector2(70, h - 360), 38, false, true)
	_add("view", "VIEW", Vector2(w - 145, 128), 30, false, false)
	_add("light", "LIGHT", Vector2(w - 70, 128), 30, false, false)
	for b in _buttons:
		if prev.has(b["id"]):
			b["on"] = prev[b["id"]][0]
			b["touch"] = prev[b["id"]][1]
	_canvas.queue_redraw()

func _add(id: String, label: String, pos: Vector2, r: float, hold: bool, toggle: bool) -> void:
	_buttons.append({"id": id, "label": label, "pos": pos, "r": r, "hold": hold, "toggle": toggle, "on": false, "touch": -1})

func _process(delta: float) -> void:
	if _restart_guard > 0.0:
		_restart_guard -= delta
	# ADS can also change from elsewhere (never does, but stay in sync).
	if is_instance_valid(player):
		for b in _buttons:
			if b["id"] == "ads":
				b["on"] = player.aiming
	_canvas.queue_redraw()

# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_drag(sd.index, sd.position, sd.relative)
		get_viewport().set_input_as_handled()

func _end_screen_up() -> bool:
	return game != null and (game.state == "won" or game.state == "lost")

func _touch_down(idx: int, pos: Vector2) -> void:
	if _end_screen_up():
		if _restart_guard <= 0.0 and game != null:
			game.restart()
		return
	for b in _buttons:
		if pos.distance_to(b["pos"]) <= float(b["r"]) + 10.0:
			_touches[idx] = {"kind": "button", "id": b["id"]}
			_press(b)
			return
	if pos.x < _vp_size.x * 0.42 and pos.y > _vp_size.y * 0.25:
		_touches[idx] = {"kind": "stick"}
		_stick_active = true
		_stick_base = Vector2(clampf(pos.x, STICK_RADIUS + 10, _vp_size.x * 0.42), clampf(pos.y, _vp_size.y * 0.3, _vp_size.y - STICK_RADIUS - 10))
		_stick_knob = Vector2.ZERO
		_update_stick(pos)
	else:
		_touches[idx] = {"kind": "look"}

func _touch_up(idx: int) -> void:
	if not _touches.has(idx):
		return
	var t: Dictionary = _touches[idx]
	_touches.erase(idx)
	match t["kind"]:
		"stick":
			_stick_active = false
			_stick_base = _stick_home
			_stick_knob = Vector2.ZERO
			_stick_vec = Vector2.ZERO
			_apply_move()
		"button":
			var b := _find(t["id"])
			if not b.is_empty():
				_release(b)

func _touch_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _touches.has(idx):
		return
	var t: Dictionary = _touches[idx]
	match t["kind"]:
		"stick":
			_update_stick(pos)
		"look":
			_look(rel)
		"button":
			if t["id"] == "fire":
				_look(rel)  # keep aiming while holding fire

func _look(rel: Vector2) -> void:
	if is_instance_valid(player) and player.alive:
		var k := 0.6 if player.aiming else 1.0
		player.touch_look(rel * LOOK_SENS * k)

func _update_stick(pos: Vector2) -> void:
	var d := pos - _stick_base
	var dist := d.length()
	if dist > STICK_RADIUS:
		d = d / dist * STICK_RADIUS
	_stick_knob = d
	var v := d / STICK_RADIUS
	if v.length() < 0.14:
		_stick_vec = Vector2.ZERO
	else:
		# Actions have a 0.5 deadzone; map the live range onto 0.55..1.
		_stick_vec = v.normalized() * (0.55 + 0.45 * minf(v.length(), 1.0))
	_apply_move()

func _apply_move() -> void:
	var v := _stick_vec
	_set_axis("move_left", maxf(-v.x, 0.0))
	_set_axis("move_right", maxf(v.x, 0.0))
	_set_axis("move_forward", maxf(-v.y, 0.0))
	_set_axis("move_back", maxf(v.y, 0.0))

func _set_axis(action: String, s: float) -> void:
	if s > 0.0:
		Input.action_press(action, s)
	else:
		Input.action_release(action)

func _find(id: String) -> Dictionary:
	for b in _buttons:
		if b["id"] == id:
			return b
	return {}

func _press(b: Dictionary) -> void:
	if not is_instance_valid(player) or not player.alive:
		return
	b["touch"] = 1
	match b["id"]:
		"fire":
			player.set_firing(true)
		"jump":
			Input.action_press("jump")
		"reload":
			player.reload()
		"grenade":
			player.throw_grenade()
		"mine":
			player.place_trap("mine")
		"acid":
			player.place_trap("toxic")
		"ads":
			player.aiming = not player.aiming
			b["on"] = player.aiming
		"sprint":
			b["on"] = not b["on"]
			if b["on"]:
				Input.action_press("sprint")
			else:
				Input.action_release("sprint")
		"view":
			player.toggle_view()
		"light":
			player.toggle_flashlight()

func _release(b: Dictionary) -> void:
	b["touch"] = -1
	match b["id"]:
		"fire":
			if is_instance_valid(player):
				player.set_firing(false)
		"jump":
			Input.action_release("jump")

func _release_all() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint"]:
		Input.action_release(a)
	if is_instance_valid(player):
		player.set_firing(false)

# Called by the game when the round ends so tapping restarts, not fires.
func on_end_screen() -> void:
	_restart_guard = 0.9
	_release_all()
	_touches.clear()
	_stick_active = false
	_stick_knob = Vector2.ZERO

# ---------------------------------------------------------------- drawing
func _draw_ui() -> void:
	if _end_screen_up():
		return
	var c := _canvas
	# Joystick.
	c.draw_circle(_stick_base, STICK_RADIUS, Color(1, 1, 1, 0.07))
	c.draw_arc(_stick_base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.28), 3.0, true)
	c.draw_circle(_stick_base + _stick_knob, 46, Color(0.9, 0.75, 0.2, 0.40 if _stick_active else 0.22))
	c.draw_arc(_stick_base + _stick_knob, 46, 0, TAU, 32, Color(1, 0.85, 0.3, 0.6), 2.0, true)
	for b in _buttons:
		var pressed: bool = b["touch"] != -1 or b["on"]
		var fill := Color(0.9, 0.7, 0.15, 0.50) if pressed else Color(0.05, 0.05, 0.05, 0.38)
		var ring := Color(1, 0.85, 0.3, 0.9) if pressed else Color(1, 1, 1, 0.45)
		if b["id"] == "fire":
			fill = Color(0.75, 0.15, 0.1, 0.6) if pressed else Color(0.45, 0.07, 0.05, 0.42)
			ring = Color(1, 0.4, 0.3, 0.9)
		c.draw_circle(b["pos"], b["r"], fill)
		c.draw_arc(b["pos"], b["r"], 0, TAU, 40, ring, 3.0, true)
		var fs := 22 if b["r"] > 50 else (14 if b["r"] < 36 else 15)
		var sz := _font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var tp: Vector2 = b["pos"] + Vector2(-sz.x * 0.5, sz.y * 0.3)
		c.draw_string(_font, tp + Vector2(1, 1), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
		c.draw_string(_font, tp, b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
