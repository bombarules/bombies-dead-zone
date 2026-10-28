class_name ToxicCloud
extends Area3D

# Lingering acid cloud: damages + slows Bombies that stand in it.

const DPS := 16.0
const DURATION := 6.0
const RADIUS := 3.0

var _age: float = 0.0
var _tick: float = 0.0
var _visual: MeshInstance3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # only Bombies
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 2.5
	shape.shape = cyl
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.85, 0.2, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.7, 0.1)
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = 2.2
	_visual = MeshInstance3D.new()
	_visual.mesh = mesh
	_visual.material_override = mat
	_visual.position = Vector3(0, 1.1, 0)
	add_child(_visual)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.2)
	light.light_energy = 0.8
	light.omni_range = 6.0
	light.position = Vector3(0, 1.2, 0)
	add_child(light)

func _process(delta: float) -> void:
	_age += delta
	_tick += delta
	if _tick >= 0.5:
		_tick = 0.0
		for body in get_overlapping_bodies():
			if body is Bombie:
				body.take_damage(DPS * 0.5)
				body.slow_timer = 1.0
	if _visual != null:
		var s := 1.0 + sin(_age * 3.0) * 0.04
		_visual.scale = Vector3(s, 1.0, s)
	if _age >= DURATION:
		queue_free()
