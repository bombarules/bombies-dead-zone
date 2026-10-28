class_name Trap
extends Node3D

# Two trap types, placed by the hazmat engineer:
# - "mine": proximity explosive, 120 damage in 3.5 m.
# - "toxic": acid canister, pops a lingering toxic cloud when a Bombie gets close.

var trap_type: String = "mine"
var lifetime: float = 60.0
var _age: float = 0.0
var _triggered: bool = false
var _blink: MeshInstance3D
var _blink_mat: StandardMaterial3D
var _area: Area3D
var _sfx: Sfx

func setup(p_type: String, sfx: Sfx) -> void:
	trap_type = p_type
	_sfx = sfx

func _ready() -> void:
	_build_visual()
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitoring = true
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2 if trap_type == "mine" else 2.0
	shape.shape = sphere
	shape.position = Vector3(0, 0.6, 0)
	_area.add_child(shape)
	add_child(_area)

func _build_visual() -> void:
	if trap_type == "mine":
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.12, 0.12, 0.12)
		dark.roughness = 0.5
		dark.metallic = 0.6
		var body := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.26
		cyl.height = 0.16
		body.mesh = cyl
		body.material_override = dark
		body.position = Vector3(0, 0.08, 0)
		add_child(body)
		_blink_mat = StandardMaterial3D.new()
		_blink_mat.albedo_color = Color(0.2, 0.0, 0.0)
		_blink_mat.emission_enabled = true
		_blink_mat.emission = Color(1.0, 0.05, 0.05)
		_blink_mat.emission_energy_multiplier = 3.0
		_blink = MeshInstance3D.new()
		var lamp := SphereMesh.new()
		lamp.radius = 0.06
		lamp.height = 0.12
		_blink.mesh = lamp
		_blink.material_override = _blink_mat
		_blink.position = Vector3(0, 0.2, 0)
		add_child(_blink)
	else:
		var yellow := StandardMaterial3D.new()
		yellow.albedo_color = Color(0.85, 0.7, 0.1)
		yellow.roughness = 0.6
		var can := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.18
		cyl.height = 0.5
		can.mesh = cyl
		can.material_override = yellow
		can.position = Vector3(0, 0.25, 0)
		add_child(can)
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(0.2, 0.8, 0.15, 0.5)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(0.15, 0.7, 0.1)
		ring_mat.emission_energy_multiplier = 1.5
		var ring := MeshInstance3D.new()
		var ring_cyl := CylinderMesh.new()
		ring_cyl.top_radius = 1.0
		ring_cyl.bottom_radius = 1.0
		ring_cyl.height = 0.04
		ring.mesh = ring_cyl
		ring.material_override = ring_mat
		ring.position = Vector3(0, 0.05, 0)
		add_child(ring)

func _process(delta: float) -> void:
	_age += delta
	if _blink_mat != null:
		var on := sin(_age * 6.0) > 0.0
		_blink_mat.emission_energy_multiplier = 3.0 if on else 0.2
	if _age >= lifetime and not _triggered:
		queue_free()
		return
	if _triggered:
		return
	for body in _area.get_overlapping_bodies():
		if body is Bombie and not (body as Bombie)._dead:
			_trigger()
			break

func _trigger() -> void:
	_triggered = true
	if trap_type == "mine":
		_explode()
	else:
		var cloud := ToxicCloud.new()
		get_parent().add_child(cloud)
		cloud.global_position = global_position
		if _sfx != null:
			_sfx.play("trap")
		queue_free()

func _explode() -> void:
	var origin := global_position
	# Damage falloff.
	for body in get_tree().get_nodes_in_group("bombie"):
		if body is Bombie and not (body as Bombie)._dead:
			var d := (body as Bombie).global_position.distance_to(origin)
			if d <= 3.5:
				(body as Bombie).take_damage(120.0 * (1.0 - d / 5.0))
	# Flash + expanding ring, then remove.
	if _sfx != null:
		_sfx.play("boom")
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.2)
	flash.light_energy = 6.0
	flash.omni_range = 10.0
	flash.position = Vector3(0, 0.8, 0)
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.tween_callback(queue_free)
	visible = false
	_area.monitoring = false
