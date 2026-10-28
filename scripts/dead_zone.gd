class_name DeadZone
extends Node

# Game manager: rounds, spawning, mid-round mutation, win / lose, ambience.
# First playable version: 3 rounds in the flooded garage, then the exit opens.

const TOTAL_ROUNDS := 3
const INTERMISSION := 5.0

@onready var player: DeadZonePlayer = get_parent().get_node("Player")
@onready var garage: Garage = get_parent().get_node("World")
@onready var hud: DeadZoneHUD = get_parent().get_node("HUD")
@onready var sfx: Sfx = get_parent().get_node("Sfx")

var touch: TouchControls = null
var round_num: int = 0
var spawn_queue: Array[String] = []
var spawn_timer: float = 0.0
var round_time: float = 0.0
var mutated_this_round: bool = false
var intermission_timer: float = 0.0
var state: String = "intermission" # "intermission" | "fighting" | "won" | "lost"
var _drip_timer: float = 2.0
var _groan_timer: float = 6.0

# Debug / self-test hooks (env-gated, inert in normal play):
# DZ_SELFTEST=1 auto-plays (aims, shoots, throws grenades, places traps) and
# prints progress lines; DZ_SHOT=1 saves viewport frames to /tmp.
var _selftest: bool = false
var _elapsed: float = 0.0
var _shot_marks: Array = [8.0, 30.0, 75.0, 150.0]
var _shots_done: Array = []
var _status_timer: float = 0.0
var _test_grenade_timer: float = 12.0
var _test_trap_timer: float = 18.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_selftest = OS.has_environment("DZ_SELFTEST")
	player.hud = hud
	player.sfx = sfx
	player.game = self
	if TouchControls.is_touch_device():
		_setup_touch()
	# HUD builds its controls in its own _ready, which runs after ours
	# (sibling order), so initialise it deferred.
	call_deferred("_init_hud")
	intermission_timer = 3.0
	state = "intermission"

func _setup_touch() -> void:
	# Phones: on-screen controls + a cheaper shadow setup.
	touch = TouchControls.new()
	touch.player = player
	touch.game = self
	get_parent().add_child.call_deferred(touch)
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	for n in get_parent().get_children():
		if n is DirectionalLight3D:
			(n as DirectionalLight3D).directional_shadow_max_distance = 30.0
			(n as DirectionalLight3D).directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _init_hud() -> void:
	hud.set_hp(player.hp, player.max_hp)
	hud.set_ammo(player.ammo_in_mag, player.mag_size, player.grenades, player.mines, player.toxic_traps)
	hud.set_round(0, TOTAL_ROUNDS, 0)
	hud.show_message("BOMBIES: DEAD ZONE — hold the flooded garage", 4.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_R and (state == "won" or state == "lost"):
			restart()

func _process(delta: float) -> void:
	_elapsed += delta
	if _selftest:
		_selftest_tick(delta)
	if state == "won" or state == "lost":
		if _selftest:
			_capture("dz-shot-win.png" if state == "won" else "dz-shot-lose.png")
			print("[SELFTEST] %s at t=%.1f round=%d" % [state.to_upper(), _elapsed, round_num])
			get_tree().quit()
		return
	# Ambience: drips and distant groans while the garage breathes.
	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = randf_range(1.5, 5.0)
		sfx.play("drip", -14.0)
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = randf_range(4.0, 10.0)
		if alive_count() > 0:
			sfx.play("groan", -10.0)
	if state == "intermission":
		intermission_timer -= delta
		if intermission_timer <= 0.0:
			_start_round(round_num + 1)
		return
	# Fighting.
	round_time += delta
	spawn_timer -= delta
	if not spawn_queue.is_empty() and spawn_timer <= 0.0:
		spawn_timer = _spawn_interval()
		_spawn_next()
	# Mid-round mutation: after 40 seconds the survivors change.
	if not mutated_this_round and round_time >= 40.0:
		mutated_this_round = true
		var count := 0
		for b in get_tree().get_nodes_in_group("bombie"):
			if b is Bombie:
				(b as Bombie).mutate()
				count += 1
		if count > 0:
			hud.show_message("WARNING: THE BOMBIES ARE MUTATING", 3.5)
			sfx.play("sting", -4.0)
	var alive := alive_count()
	hud.set_round(round_num, TOTAL_ROUNDS, alive + spawn_queue.size())
	if spawn_queue.is_empty() and alive == 0:
		_round_cleared()

func alive_count() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("bombie"):
		if b is Bombie and not (b as Bombie)._dead:
			n += 1
	return n

func _spawn_interval() -> float:
	return maxf(0.55, 1.3 - 0.2 * float(round_num))

func _round_composition(n: int) -> Array[String]:
	var comp: Array[String] = []
	match n:
		1:
			for i in 6:
				comp.append("shambler")
		2:
			for i in 7:
				comp.append("shambler")
			for i in 3:
				comp.append("runner")
		3:
			for i in 8:
				comp.append("shambler")
			for i in 4:
				comp.append("runner")
			for i in 2:
				comp.append("tank")
		_:
			for i in 6:
				comp.append("shambler")
	comp.shuffle()
	return comp

func _start_round(n: int) -> void:
	round_num = n
	round_time = 0.0
	mutated_this_round = false
	spawn_queue = _round_composition(n)
	spawn_timer = 0.5
	state = "fighting"
	hud.show_message("ROUND %d — they know you're here" % n, 3.0)
	sfx.play("sting", -6.0)

func _spawn_next() -> void:
	var type: String = spawn_queue.pop_front()
	var b := Bombie.new()
	get_parent().add_child(b)
	b.global_position = garage.random_spawn_point(player.global_position, 9.0)
	b.setup(type, round_num, player)
	b.died.connect(_on_bombie_died)

func _on_bombie_died(_b: Bombie) -> void:
	pass # counts are derived live from the group

func _round_cleared() -> void:
	if round_num >= TOTAL_ROUNDS:
		state = "won"
		garage.set_exit_open(true)
		hud.show_message("EXIT OPEN", 4.0)
		hud.show_win()
		if touch != null:
			touch.on_end_screen()
		sfx.play("sting")
		return
	state = "intermission"
	intermission_timer = INTERMISSION
	hud.show_message("ROUND %d CLEARED — next wave in %d seconds" % [round_num, int(INTERMISSION)], 4.0)
	# Small reward: restock a little.
	player.grenades = mini(player.grenades + 1, 5)
	player.mines = mini(player.mines + 1, 6)
	player.toxic_traps = mini(player.toxic_traps + 1, 5)
	hud.set_ammo(player.ammo_in_mag, player.mag_size, player.grenades, player.mines, player.toxic_traps)

func _capture(fname: String) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.save_png("/tmp/" + fname)
	print("[SELFTEST] saved /tmp/" + fname)

func _selftest_tick(delta: float) -> void:
	for t in _shot_marks:
		if _elapsed >= t and not _shots_done.has(t):
			_shots_done.append(t)
			_capture("dz-shot-%d.png" % int(t))
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 5.0
		print("[SELFTEST] t=%.0f round=%d state=%s alive=%d queue=%d hp=%.0f ammo=%d gren=%d mines=%d traps=%d" % [
			_elapsed, round_num, state, alive_count(), spawn_queue.size(),
			player.hp, player.ammo_in_mag, player.grenades, player.mines, player.toxic_traps])
	if _elapsed > 300.0:
		print("[SELFTEST] TIMEOUT state=%s round=%d" % [state, round_num])
		get_tree().quit()
		return
	if state != "fighting" or not player.alive:
		player._firing = false
		_set_test_move("", false)
		return
	# Pick the nearest living Bombie with a clear line of sight; fall back to
	# the nearest overall and strafe until a lane opens up.
	var target: Bombie = null
	var best := 1e9
	var nearest_any: Bombie = null
	var best_any := 1e9
	for b in get_tree().get_nodes_in_group("bombie"):
		if b is Bombie and not (b as Bombie)._dead:
			var d := (b as Bombie).global_position.distance_to(player.global_position)
			if d < best_any:
				best_any = d
				nearest_any = b as Bombie
			if d < best and _has_los(b as Bombie):
				best = d
				target = b as Bombie
	if target != null:
		var dir: Vector3 = target.global_position - player.global_position
		dir.y = 0.0
		player.rotation.y = atan2(-dir.x, -dir.z)
		# Aim the head at the target's chest (matters for Bombies up on the
		# mezzanine: a level ray passes under them).
		var to_chest: Vector3 = (target.global_position + Vector3(0, 1.2, 0)) - player.camera.global_position
		var horiz := Vector2(to_chest.x, to_chest.z).length()
		player.head.rotation.x = clampf(atan2(to_chest.y, horiz), -1.4, 1.4)
		player._firing = true
		# Kite: back away when the target closes in.
		_set_test_move("move_back", best < 6.0)
	else:
		player._firing = false
		if nearest_any != null:
			var dir2: Vector3 = nearest_any.global_position - player.global_position
			dir2.y = 0.0
			player.rotation.y = atan2(-dir2.x, -dir2.z)
		# No lane: close the distance, then strafe, until a lane opens up.
		var phase := int(_elapsed) % 6
		if phase < 3:
			_set_test_move("move_forward", true)
		elif phase < 5:
			_set_test_move("move_left", true)
		else:
			_set_test_move("move_right", true)
	# Exercise the engineer's kit on a timer.
	_test_grenade_timer -= delta
	if _test_grenade_timer <= 0.0:
		_test_grenade_timer = 14.0
		player._throw_grenade()
	_test_trap_timer -= delta
	if _test_trap_timer <= 0.0:
		_test_trap_timer = 16.0
		player.trap_selected = "mine" if randf() < 0.5 else "toxic"
		player._place_trap()

var _held_test_move: String = ""

func _set_test_move(action: String, pressed: bool) -> void:
	if action == _held_test_move and pressed:
		return
	if _held_test_move != "":
		var up := InputEventAction.new()
		up.action = _held_test_move
		up.pressed = false
		Input.parse_input_event(up)
		_held_test_move = ""
	if pressed and action != "":
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		Input.parse_input_event(ev)
		_held_test_move = action

func _has_los(b: Bombie) -> bool:
	var from: Vector3 = player.camera.global_position
	var to: Vector3 = b.global_position + Vector3(0, 1.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 3, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit["collider"] == b

func on_player_down() -> void:
	if state == "lost":
		return
	state = "lost"
	hud.show_lose()
	if touch != null:
		touch.on_end_screen()
	sfx.play("sting", -2.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
