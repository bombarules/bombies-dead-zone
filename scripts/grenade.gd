class_name Grenade
extends Node3D

# Thrown toxic grenade: arcs with gravity, pops a lingering acid cloud on
# landing or after its fuse. Manual projectile — no physics body needed.

const FUSE := 1.6

var velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _done: bool = false
var _sfx: Sfx

func setup(vel: Vector3, sfx: Sfx) -> void:
	velocity = vel
	_sfx = sfx

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.7, 0.1)
	mat.roughness = 0.4
	mat.metallic = 0.3
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mi.mesh = sphere
	mi.material_override = mat
	add_child(mi)

func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	velocity.y -= 20.0 * delta
	position += velocity * delta
	if position.y <= 0.2 or _age >= FUSE:
		_detonate()

func _detonate() -> void:
	_done = true
	var cloud := ToxicCloud.new()
	get_parent().add_child(cloud)
	cloud.global_position = Vector3(global_position.x, 0.15, global_position.z)
	if _sfx != null:
		_sfx.play("boom", -6.0)
	queue_free()
