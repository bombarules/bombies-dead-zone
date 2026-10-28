class_name PlayerController
extends CharacterBody3D

# Movement tunables — canonical defaults. Tweak in the inspector, don't fork.
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 7.5            # higher hops
@export var gravity: float = 20.0                 # heavier than Earth — feels better
@export var fall_gravity_multiplier: float = 1.4  # snappier descent than ascent

# Acceleration model — separate ground/air so air control feels real.
@export var ground_accel: float = 80.0
@export var ground_friction: float = 90.0
@export var air_accel: float = 25.0               # ~30% of ground — basic-controller air control
@export var air_friction: float = 5.0

# Grace timers.
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.1

# Camera.
@export_range(0.0001, 0.01) var mouse_sensitivity: float = 0.002
@export var pitch_min: float = -1.4               # ~-80°
@export var pitch_max: float = 1.4                # ~+80°

# External-velocity damping — knockback / explosions / jump pads decay over time.
@export var external_damping: float = 8.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false

# External velocity accumulator — any system can shove the player via add_external_velocity().
var external_velocity: Vector3 = Vector3.ZERO
var _prev_external_applied: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Desktop captures the mouse for look; touch devices never do.
	if not TouchControls.is_touch_device():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Touch look: rel is already in radians (yaw, pitch).
func touch_look(rel: Vector2) -> void:
	rotate_y(-rel.x)
	head.rotate_x(-rel.y)
	head.rotation.x = clamp(head.rotation.x, pitch_min, pitch_max)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, pitch_min, pitch_max)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not TouchControls.is_touch_device():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# 1. Strip last frame's external contribution so it doesn't compound with input.
	velocity -= _prev_external_applied

	# 2. Gravity (asymmetric — falling faster than rising feels better).
	if not is_on_floor():
		var g := gravity * (fall_gravity_multiplier if velocity.y < 0.0 else 1.0)
		velocity.y -= g * delta

	# 3. Coyote-time bookkeeping. Reset on landing; tick down when airborne.
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = max(_coyote_timer - delta, 0.0)

	# 4. Jump buffer — queue a press up to jump_buffer_time before landing.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	# 5. Build wish-direction in worldspace from body yaw.
	var input_v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_v.x, 0.0, input_v.y))
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized() if wish_dir.length() > 0.001 else Vector3.ZERO

	# 6. Pick speed + accel/friction based on grounded state.
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := ground_accel if is_on_floor() else air_accel
	var friction := ground_friction if is_on_floor() else air_friction

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir.length() > 0.0:
		horiz = horiz.move_toward(wish_dir * target_speed, accel * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	# 7. Apply external velocity, remember it for next-frame subtraction, decay it.
	velocity += external_velocity
	_prev_external_applied = external_velocity
	external_velocity = external_velocity.move_toward(Vector3.ZERO, external_damping * delta)

	_was_on_floor = is_on_floor()
	move_and_slide()

# Public API — knockback, explosions, jump pads, conveyor belts, etc.
func add_external_velocity(impulse: Vector3) -> void:
	external_velocity += impulse
