class_name Bombie
extends CharacterBody3D

# A mutating Bombie: shambler, runner or tank. Chases the player, swipes in range,
# mutates mid-round (faster, tougher, redder). Built from boxes with glowing eyes.

signal died(b: Bombie)

const GRAVITY := 20.0

var btype: String = "shambler"
var max_hp: float = 60.0
var hp: float = 60.0
var speed: float = 1.6
var attack_damage: float = 8.0
var attack_range: float = 1.9
var attack_cooldown: float = 1.5
var mutated: bool = false
var slow_timer: float = 0.0

var _attack_timer: float = 0.0
var _walk_phase: float = 0.0
var _dead: bool = false
var _sink_timer: float = -1.0
var _pos_last: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
var _sidestep_timer: float = 0.0
var _sidestep_sign: float = 1.0
var _player: Node3D = null
var _skin_mat: StandardMaterial3D
var _leg_l: MeshInstance3D
var _leg_r: MeshInstance3D
var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _eye_mat: StandardMaterial3D

func setup(p_type: String, round_num: int, player: Node3D) -> void:
	btype = p_type
	_player = player
	var hp_scale := 1.0 + 0.15 * float(round_num - 1)
	var speed_scale := 1.0 + 0.08 * float(round_num - 1)
	match p_type:
		"runner":
			max_hp = 40.0 * hp_scale
			speed = 3.9 * speed_scale
			attack_damage = 6.0
			scale = Vector3(0.92, 0.95, 0.92)
		"tank":
			max_hp = 260.0 * hp_scale
			speed = 1.15 * speed_scale
			attack_damage = 16.0
			attack_range = 2.2
			scale = Vector3(1.35, 1.3, 1.35)
		_:
			max_hp = 60.0 * hp_scale
			speed = 1.6 * speed_scale
			attack_damage = 8.0
	hp = max_hp

func _ready() -> void:
	add_to_group("bombie")
	collision_layer = 2
	collision_mask = 1
	_build_body()

func _build_body() -> void:
	_skin_mat = StandardMaterial3D.new()
	_skin_mat.albedo_color = Color(0.45, 0.55, 0.38) # sickly pale green
	_skin_mat.roughness = 0.85
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(0.22, 0.22, 0.20)
	cloth_mat.roughness = 0.95
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.1, 0.0, 0.0)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.08, 0.05)
	_eye_mat.emission_energy_multiplier = 4.0

	var torso := _box(Vector3(0.62, 0.72, 0.36), Vector3(0, 1.12, 0), cloth_mat)
	_box(Vector3(0.5, 0.3, 0.38), Vector3(0, 1.3, 0), _skin_mat)
	var head := _box(Vector3(0.36, 0.36, 0.36), Vector3(0, 1.68, 0), _skin_mat)
	_box(Vector3(0.08, 0.05, 0.02), Vector3(-0.09, 1.7, 0.19), _eye_mat)
	_box(Vector3(0.08, 0.05, 0.02), Vector3(0.09, 1.7, 0.19), _eye_mat)
	_leg_l = _box(Vector3(0.22, 0.72, 0.24), Vector3(-0.17, 0.38, 0), cloth_mat)
	_leg_r = _box(Vector3(0.22, 0.72, 0.24), Vector3(0.17, 0.38, 0), cloth_mat)
	_arm_l = _box(Vector3(0.16, 0.62, 0.18), Vector3(-0.42, 1.15, 0.1), _skin_mat)
	_arm_r = _box(Vector3(0.16, 0.62, 0.18), Vector3(0.42, 1.15, 0.1), _skin_mat)
	_arm_l.rotation.x = -1.2
	_arm_r.rotation.x = -1.2
	# Collision capsule.
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.9
	col.shape = shape
	col.position = Vector3(0, 0.95, 0)
	add_child(col)

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi

func take_damage(amount: float, headshot: bool = false) -> void:
	if _dead:
		return
	hp -= amount
	# Hit flash: brief skin brighten.
	_skin_mat.albedo_color = Color(0.9, 0.5, 0.4)
	var t := get_tree().create_timer(0.08)
	t.timeout.connect(func() -> void:
		if not _dead:
			_skin_mat.albedo_color = Color(0.45, 0.55, 0.38) if not mutated else Color(0.6, 0.3, 0.25)
	)
	if hp <= 0.0:
		die()

func mutate() -> void:
	if _dead or mutated:
		return
	mutated = true
	speed *= 1.25
	max_hp += 30.0
	hp += 30.0
	scale *= 1.12
	_skin_mat.albedo_color = Color(0.6, 0.3, 0.25)
	_eye_mat.emission_energy_multiplier = 7.0

func die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	# Fall flat and sink after a moment.
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI / 2.0, 0.35)
	tw.tween_property(self, "position:y", -0.4, 2.5).set_delay(1.2)
	tw.tween_callback(queue_free).set_delay(0.5)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	if _player == null or not is_instance_valid(_player):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.01 else Vector3.ZERO
	# Face the player.
	if dist > 0.05:
		rotation.y = atan2(dir.x, dir.z)
	# Separation from other bombies.
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("bombie"):
		if other == self or not (other is Bombie) or other._dead:
			continue
		var d: Vector3 = global_position - other.global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.01 and l < 1.3:
			push += d.normalized() * (1.3 - l)
	var eff_speed := speed
	if slow_timer > 0.0:
		eff_speed *= 0.55
		slow_timer -= delta
	# Water: runners keep full speed, everyone else is slightly slowed.
	if btype != "runner":
		eff_speed *= 0.95
	_attack_timer -= delta
	if dist <= attack_range and _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		if _player.has_method("take_damage"):
			_player.take_damage(attack_damage)
		_arm_l.rotation.x = -2.0
		_arm_r.rotation.x = -2.0
	# Unstick: if we are barely moving while trying to reach the player
	# (wedged on a car or pillar), sidestep around the obstacle.
	var moved := global_position.distance_to(_pos_last)
	var expected := eff_speed * delta
	if dist > attack_range and expected > 0.001 and moved < expected * 0.4:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	if _stuck_timer > 1.5:
		_stuck_timer = 0.0
		_sidestep_timer = 1.2
		_sidestep_sign = -_sidestep_sign
	velocity.x = (dir.x * eff_speed) + push.x * 2.0
	velocity.z = (dir.z * eff_speed) + push.z * 2.0
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
		var perp := Vector3(-dir.z, 0.0, dir.x) * _sidestep_sign
		velocity.x += perp.x * eff_speed * 0.9
		velocity.z += perp.z * eff_speed * 0.9
	move_and_slide()
	_pos_last = global_position
	# Walk cycle.
	var planar := Vector2(velocity.x, velocity.z).length()
	_walk_phase += planar * delta * 2.4
	var swing := sin(_walk_phase) * clampf(planar / 2.0, 0.0, 1.0) * 0.5
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	if _attack_timer < attack_cooldown - 0.25:
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.2 + swing * 0.4, delta * 8.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.2 - swing * 0.4, delta * 8.0)
