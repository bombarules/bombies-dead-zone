class_name HeroRig
extends Node3D

# The hero: ONE skinned mesh (assets/hero/hero.glb) with ONE material/atlas, driven by a
# 17-bone skeleton. This class loads it and poses it procedurally (walk cycle, weapon
# low-ready / raised, two-bone IK for both arms so the gloves stay on the rifle).

const HERO_SCENE := "res://assets/hero/hero.glb"
const UPPER := 0.29          # shoulder -> elbow
const FORE := 0.40           # elbow -> fist centre
const GUN_REST := Vector3(0.26, 1.0, -0.28)
const FOREGRIP := Vector3(0.0, -0.085, -0.25)   # gun-local
const MUZZLE := Vector3(0.0, 0.04, -0.68)       # gun-local

var skeleton: Skeleton3D
var mesh_inst: MeshInstance3D
var raise: float = 0.0            # 0 = low-ready, 1 = shouldered/aiming
var _ids := {}
var _rest := {}

func _ready() -> void:
	var packed: PackedScene = load(HERO_SCENE)
	var inst: Node = packed.instantiate()
	add_child(inst)
	skeleton = _find_skeleton(inst)
	mesh_inst = _find_mesh(inst)
	for i in skeleton.get_bone_count():
		_ids[skeleton.get_bone_name(i)] = i
		_rest[skeleton.get_bone_name(i)] = skeleton.get_bone_rest(i).origin
	if mesh_inst != null:
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_inst.extra_cull_margin = 1.0
	set_pose(0.0, 0.0, 0.0, 0.0, 0.0)

func hero_material() -> Material:
	if mesh_inst != null and mesh_inst.mesh != null:
		return mesh_inst.mesh.surface_get_material(0)
	return null

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null

func _rot(bone: String, q: Quaternion) -> void:
	skeleton.set_bone_pose_rotation(_ids[bone], q)

func _pos(bone: String, p: Vector3) -> void:
	skeleton.set_bone_pose_position(_ids[bone], _rest[bone] + p)

static func _down_basis(dir: Vector3) -> Basis:
	# Basis whose local -Y axis points along dir (rest pose = identity).
	var y := -dir.normalized()
	var x := y.cross(Vector3(0, 0, 1))
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _arm_ik(side: String, target: Vector3) -> void:
	var sx := -1.0 if side == "l" else 1.0
	var shoulder := Vector3(sx * 0.31, 1.42, 0.0)
	var to := target - shoulder
	var d := clampf(to.length(), 0.08, UPPER + FORE - 0.003)
	var dir := to.normalized()
	var x := (d * d + UPPER * UPPER - FORE * FORE) / (2.0 * d)
	var h := sqrt(maxf(UPPER * UPPER - x * x, 0.0))
	var hint := Vector3(sx * 0.55, -1.0, 0.35)
	hint = (hint - dir * hint.dot(dir)).normalized()
	var elbow := shoulder + dir * x + hint * h
	var b1 := _down_basis(elbow - shoulder)
	var b2 := _down_basis(shoulder + dir * d - elbow)
	_rot("up_" + side, b1.get_rotation_quaternion())
	_rot("fore_" + side, (b1.inverse() * b2).get_rotation_quaternion())

func muzzle_global() -> Vector3:
	var gi: int = _ids["gun"]
	var t: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(gi)
	return t * MUZZLE

func set_pose(walk_phase: float, speed01: float, raise_v: float, pitch: float, delta: float) -> void:
	raise = raise_v
	# --- legs
	var amp := 0.55 * speed01
	for s in ["l", "r"]:
		var ph := walk_phase + (0.0 if s == "l" else PI)
		var swing := sin(ph) * amp
		var bend := -maxf(0.0, cos(ph)) * 1.15 * speed01 - 0.04
		_rot("thigh_" + s, Quaternion(Vector3.RIGHT, swing))
		_rot("shin_" + s, Quaternion(Vector3.RIGHT, bend))
		_rot("foot_" + s, Quaternion(Vector3.RIGHT, -(swing + bend) * 0.8))
	var bob := absf(sin(walk_phase)) * 0.025 * speed01
	_pos("hips", Vector3(0, -bob, 0))
	_rot("chest", Quaternion(Vector3.UP, sin(walk_phase) * 0.06 * speed01))
	_rot("head", Quaternion(Vector3.RIGHT, clampf(pitch, -0.8, 0.8) * 0.8))
	# --- gun: low-ready at the right hip, shouldered when raised
	var low_p := Vector3(0.33, 0.84, -0.22)
	var up_p := Vector3(0.11, 1.27, -0.34)
	var low_pitch := -0.95
	var up_pitch := clampf(pitch, -0.9, 0.9)
	var r := clampf(raise_v, 0.0, 1.0)
	var gp := low_p.lerp(up_p, r)
	var gq := Quaternion(Vector3.RIGHT, lerpf(low_pitch, up_pitch, r))
	var swayz := sin(walk_phase * 2.0) * 0.01 * speed01
	gp += Vector3(0, absf(sin(walk_phase)) * 0.012 * speed01, swayz)
	skeleton.set_bone_pose_position(_ids["gun"], _rest["gun"] + (gp - GUN_REST) + Vector3.ZERO)
	_rot("gun", gq)
	var gb := Basis(gq)
	var right_fist := gp
	_arm_ik("r", right_fist + Vector3(0, 0, 0))
	var fg := gp + gb * FOREGRIP
	var left_rest := Vector3(-0.34, 0.77, -0.04 - sin(walk_phase) * 0.12 * speed01)
	_arm_ik("l", left_rest.lerp(fg, r))
