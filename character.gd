extends CharacterBody3D

@export var move_speed: float = 5.0
@export var acceleration: float = 20.0
@export_range(0.0, 1.0) var air_control: float = 0.35
@export var jump_velocity: float = 5.0
@export var gravity_multiplier: float = 1.0
@export var terminal_velocity: float = 50.0
@export_range(0.0005, 0.01) var mouse_sensitivity: float = 0.0025
@export_range(-89.0, 0.0) var minimum_pitch: float = -60.0
@export_range(0.0, 89.0) var maximum_pitch: float = 45.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spring_arm.add_excluded_object(get_rid())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(minimum_pitch),
			deg_to_rad(maximum_pitch)
		)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var direction := _camera_relative_direction(input)
	var control := 1.0 if is_on_floor() else air_control

	velocity.x = move_toward(
		velocity.x,
		direction.x * move_speed,
		acceleration * control * delta
	)
	velocity.z = move_toward(
		velocity.z,
		direction.z * move_speed,
		acceleration * control * delta
	)

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
		elif velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y = max(
			velocity.y - gravity * gravity_multiplier * delta,
			-terminal_velocity
		)

	move_and_slide()

func _camera_relative_direction(input: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0.0, input.y).normalized()

	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()

	return (right * input.x + forward * -input.y).normalized()
