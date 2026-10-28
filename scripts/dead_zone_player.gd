class_name DeadZonePlayer
extends PlayerController

# The rogue hazmat engineer: hitscan rifle, toxic grenades, proximity mines and
# acid traps. V toggles first/third person; right mouse aims down sights.

var max_hp: float = 100.0
var hp: float = 100.0
var alive: bool = true

var mag_size: int = 30
var ammo_in_mag: int = 30
var reload_time: float = 1.4
var fire_interval: float = 0.13
var weapon_damage: float = 34.0

var grenades: int = 3
var mines: int = 4
var toxic_traps: int = 3
var trap_selected: String = "mine"

var view_mode: String = "fps" # "fps" | "tps"
var aiming: bool = false

var _fire_timer: float = 0.0
var _reload_timer: float = 0.0
var _grenade_timer: float = 0.0
var _trap_timer: float = 0.0
var _splash_timer: float = 0.0
var _walk_phase: float = 0.0
var _base_walk_speed: float = 5.0
var _base_sprint_speed: float = 8.0

var _hero: Node3D
var _hero_rig: HeroRig
var _raise: float = 0.0
var _since_shot: float = 99.0
var _gun_view: Node3D
var _muzzle: Node3D
var _muzzle_flash: OmniLight3D
var _tps_cam_offset := Vector3(0.85, 0.6, 3.4)
var _flashlight: SpotLight3D
var _firing: bool = false

var hud: DeadZoneHUD = null
var sfx: Sfx = null
var game: DeadZone = null

func _ready() -> void:
	super._ready()
	add_to_group("player")
	_base_walk_speed = walk_speed
	_base_sprint_speed = sprint_speed
	_build_hero()
	_build_gun_view()
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1.0, 0.9, 0.7)
	_flashlight.light_energy = 2.5
	_flashlight.spot_range = 18.0
	_flashlight.spot_angle = 32.0
	head.add_child(_flashlight)
	_flashlight.position = Vector3(0, 0.1, 0)
	_muzzle_flash = OmniLight3D.new()
	_muzzle_flash.light_color = Color(1.0, 0.75, 0.3)
	_muzzle_flash.light_energy = 0.0
	_muzzle_flash.omni_range = 5.0
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.15, -0.16, -1.38)
	camera.add_child(_muzzle)
	_muzzle.add_child(_muzzle_flash)
	_set_view("fps")

func _build_hero() -> void:
	# One-piece skinned hazmat hero (assets/hero/hero.glb): a single mesh with a single
	# material/atlas, posed by HeroRig. The player's origin is the capsule centre, so the
	# model's feet sit 0.9 m below it, on the floor.
	_hero_rig = HeroRig.new()
	_hero_rig.name = "HeroBody"
	_hero_rig.position = Vector3(0, -0.9, 0)
	add_child(_hero_rig)
	_hero = _hero_rig

func _mk(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_gun_view() -> void:
	# First-person viewmodel: the hero's multi-barrel rifle + gloved hands, same atlas material.
	_gun_view = Node3D.new()
	_gun_view.position = Vector3(0.15, -0.2, -0.7)
	camera.add_child(_gun_view)
	var packed: PackedScene = load("res://assets/hero/hero_fps.glb")
	var inst: Node = packed.instantiate()
	_gun_view.add_child(inst)
	var mat: Material = _hero_rig.hero_material()
	_apply_material(inst, mat)

func _apply_material(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_apply_material(c, mat)

func _set_view(mode: String) -> void:
	view_mode = mode
	_hero.visible = (mode != "fps")
	_gun_view.visible = (mode == "fps")
	if mode == "fps":
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
	if hud != null:
		match mode:
			"tps":
				hud.show_message("Third-person view")
			"front":
				hud.show_message("Hero view (front)")
			_:
				hud.show_message("First-person view")

# --- Public actions (used by keyboard handlers and the touch controls) ---
func set_firing(on: bool) -> void:
	_firing = on and alive

func reload() -> void:
	if alive:
		_start_reload()

func throw_grenade() -> void:
	if alive:
		_throw_grenade()

func place_trap(kind: String) -> void:
	if alive:
		trap_selected = kind
		_place_trap()

func toggle_view() -> void:
	_set_view(_next_view())

func _next_view() -> String:
	# fps -> over-the-shoulder -> hero front view -> fps
	match view_mode:
		"fps":
			return "tps"
		"tps":
			return "front"
	return "fps"

func toggle_flashlight() -> void:
	_flashlight.visible = not _flashlight.visible

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not alive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_firing = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			aiming = mb.pressed
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_R:
				_start_reload()
			KEY_G:
				_throw_grenade()
			KEY_1:
				trap_selected = "mine"
				_place_trap()
			KEY_2:
				trap_selected = "toxic"
				_place_trap()
			KEY_Q:
				_place_trap()
			KEY_V:
				_set_view(_next_view())
			KEY_F:
				_flashlight.visible = not _flashlight.visible

func _physics_process(delta: float) -> void:
	if not alive:
		return
	# Water wading: shallow water slows the player; Bombies runners don't care.
	var in_water := global_position.y < 0.35
	var wading := 0.8 if in_water else 1.0
	walk_speed = _base_walk_speed * wading
	sprint_speed = _base_sprint_speed * wading
	super._physics_process(delta)
	_fire_timer -= delta
	_reload_timer -= delta
	_grenade_timer -= delta
	_trap_timer -= delta
	if _reload_timer <= 0.0 and _firing and ammo_in_mag > 0:
		_shoot()
	if _reload_timer > 0.0 and ammo_in_mag == 0:
		pass
	# Walk cycle + weapon pose for the third-person hero + water splash sounds.
	var planar := Vector2(velocity.x, velocity.z).length()
	_walk_phase += planar * delta * 1.9
	_since_shot += delta
	var raise_target := 1.0 if (aiming or _firing or _since_shot < 1.6) else 0.0
	_raise = move_toward(_raise, raise_target, delta * 5.0)
	if _hero.visible:
		_hero_rig.set_pose(_walk_phase, clampf(planar / 4.5, 0.0, 1.0), _raise, head.rotation.x, delta)
	if in_water and planar > 1.0:
		_splash_timer -= delta
		if _splash_timer <= 0.0:
			_splash_timer = 0.55
			if sfx != null:
				sfx.play("splash", -12.0)
	# ADS: narrow the FOV and steady the viewmodel.
	var target_fov := 50.0 if aiming else 70.0
	if absf(camera.fov - target_fov) > 0.2:
		camera.fov = lerpf(camera.fov, target_fov, delta * 10.0)
	if view_mode == "fps":
		var target_x := -0.15 if aiming else 0.0
		_gun_view.position.x = lerpf(_gun_view.position.x, 0.15 + target_x, delta * 10.0)
		_gun_view.position.y = lerpf(_gun_view.position.y, -0.13 if aiming else -0.2, delta * 10.0)
	# Third-person camera: over-the-shoulder boom behind the player.
	if view_mode == "tps":
		_update_tps_camera(delta)
	elif view_mode == "front":
		_update_front_camera(delta)

func _feet_y() -> float:
	return global_position.y - 0.9

func _update_tps_camera(delta: float) -> void:
	# Camera sits behind + right of the hero, looking along the head pitch.
	var yaw := rotation.y
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dist := 2.0 if aiming else _tps_cam_offset.z
	var off := 0.4 if aiming else _tps_cam_offset.x
	var base := Vector3(global_position.x, _feet_y() + 1.55, global_position.z)
	var desired: Vector3 = base + back * dist + right * off + Vector3(0, 0.3, 0)
	desired.y = maxf(desired.y, 0.6)
	desired = _clip_camera(base, desired)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - pow(0.0005, delta))
	var look_target: Vector3 = base - back * 9.0 + Vector3(0, 0.1, 0)
	var pitch := head.rotation.x
	look_target.y += sin(pitch) * 9.0
	camera.look_at(look_target, Vector3.UP)

func _update_front_camera(delta: float) -> void:
	# Hero showcase: camera in front of the hero, looking back at them.
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var feet := Vector3(global_position.x, _feet_y(), global_position.z)
	var focus0: Vector3 = feet + Vector3(0, 1.0, 0)
	var desired: Vector3 = feet + Vector3(0, 1.45, 0)
	var best_d := -1.0
	# Try in front of the hero first, then the sides and back, so a wall never hides the model.
	for off: float in [0.0, 0.5, -0.5, 1.5, -1.5, 3.14]:
		var dir := fwd.rotated(Vector3.UP, off)
		var cand: Vector3 = feet + dir * 3.0 + Vector3(0, 1.45, 0)
		var clipped := _clip_camera(focus0, cand)
		var d := clipped.distance_to(focus0)
		if d > best_d + 0.01:
			best_d = d
			desired = clipped
		if d >= 2.9:
			break
	var focus: Vector3 = feet + Vector3(0, 1.0, 0)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - pow(0.0005, delta))
	camera.look_at(focus, Vector3.UP)

func _clip_camera(from: Vector3, to: Vector3) -> Vector3:
	# Pull the camera in front of any wall/pillar between the hero and the camera.
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	var pos: Vector3 = hit["position"]
	return pos + (from - pos).normalized() * 0.2

func _aim_from() -> Vector3:
	return head.global_position if view_mode == "front" else camera.global_position

func _aim_dir() -> Vector3:
	return -head.global_transform.basis.z if view_mode == "front" else -camera.global_transform.basis.z

func take_damage(amount: float) -> void:
	if not alive:
		return
	hp = maxf(0.0, hp - amount)
	if sfx != null:
		sfx.play("hurt", -4.0)
	if hud != null:
		hud.set_hp(hp, max_hp)
		hud.damage_flash()
	if TouchControls.is_touch_device():
		Input.vibrate_handheld(40)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		if game != null:
			game.on_player_down()

func _start_reload() -> void:
	if _reload_timer > 0.0 or ammo_in_mag == mag_size:
		return
	_reload_timer = reload_time
	ammo_in_mag = mag_size
	if sfx != null:
		sfx.play("reload")
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)

func _shoot() -> void:
	if _fire_timer > 0.0 or _reload_timer > 0.0:
		return
	_fire_timer = fire_interval
	ammo_in_mag -= 1
	if sfx != null:
		sfx.play("shot", -6.0)
	_muzzle_flash.light_energy = 4.0
	var clear := get_tree().create_timer(0.05)
	clear.timeout.connect(func() -> void: _muzzle_flash.light_energy = 0.0)
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)
	# Hitscan ray from the camera through the crosshair.
	_since_shot = 0.0
	var from := _aim_from()
	var dir := _aim_dir()
	var to := from + dir * 80.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 3, [get_rid()])
	var space := get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(query)
	var end: Vector3 = to
	if not hit.is_empty():
		end = hit["position"]
		var collider: Object = hit["collider"]
		if collider is Bombie:
			var b := collider as Bombie
			var headshot: bool = (hit["position"] as Vector3).y > b.global_position.y + 1.45
			b.take_damage(weapon_damage * (2.0 if headshot else 1.0), headshot)
			if sfx != null:
				sfx.play("hit", -8.0)
			if hud != null and headshot:
				hud.show_message("HEADSHOT")
	var muzzle_pos: Vector3 = _muzzle.global_position if view_mode == "fps" else _hero_rig.muzzle_global()
	_spawn_tracer(muzzle_pos, end)
	if ammo_in_mag <= 0:
		_start_reload()

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, dist)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), 0.07)
	tw.tween_callback(mi.queue_free)

func _throw_grenade() -> void:
	if _grenade_timer > 0.0 or grenades <= 0:
		return
	_grenade_timer = 1.0
	grenades -= 1
	var g := Grenade.new()
	get_parent().add_child(g)
	var dir := _aim_dir()
	g.global_position = _aim_from() + dir * 0.6 + Vector3(0, -0.1, 0)
	g.setup(dir * 13.0 + Vector3(0, 4.5, 0), sfx)
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)

func _place_trap() -> void:
	if _trap_timer > 0.0:
		return
	if trap_selected == "mine" and mines <= 0:
		if hud != null:
			hud.show_message("No mines left")
		return
	if trap_selected == "toxic" and toxic_traps <= 0:
		if hud != null:
			hud.show_message("No acid traps left")
		return
	_trap_timer = 0.6
	var dir := -transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var pos: Vector3 = global_position + dir * 2.0
	pos.y = 0.15
	var trap := Trap.new()
	get_parent().add_child(trap)
	trap.global_position = pos
	trap.setup(trap_selected, sfx)
	if trap_selected == "mine":
		mines -= 1
	else:
		toxic_traps -= 1
	if sfx != null:
		sfx.play("beep", -6.0)
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)
		hud.show_message("Mine placed" if trap_selected == "mine" else "Acid trap placed")
