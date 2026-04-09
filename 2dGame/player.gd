extends CharacterBody2D

# --- Movement ---
@export var speed = 150.0

# --- Jump ---
@export var jump_height = 16
@export var jump_duration = 0.3
var is_jumping = false
var jump_timer = 0.0
var jump_offset = 0.0

# --- Dash ---
@export var dash_speed = 400.0
@export var dash_duration = 0.2
@export var dash_cooldown = 0.5
var is_dashing = false
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var dash_direction = Vector2.ZERO  # Store the dash direction
var remote_target_position = Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var role_label: Label = $RoleLabel

# --- Dash Mechanic ---
func _physics_process(_delta):
	if not is_multiplayer_authority():
		global_position = global_position.lerp(remote_target_position, 0.35)
		return

	var input_vector = Vector2.ZERO

	# --- Movement Input ---
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("move_down"):
		input_vector.y += 1
	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1

	input_vector = input_vector.normalized()

	# --- Dash Handling ---
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= _delta

	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0:
		is_dashing = true
		dash_timer = 0.0
		dash_direction = input_vector
		# Default dash direction if no input
		if dash_direction == Vector2.ZERO:
			dash_direction = Vector2.RIGHT
		dash_cooldown_timer = dash_cooldown

	if is_dashing:
		# Dash Movement
		velocity = dash_direction * dash_speed
		dash_timer += _delta

		# Apply simple blur effect (modulate alpha to make sprite transparent during dash)
		animated_sprite.modulate = Color(1, 1, 1, 0.3)

		# End dash after dash_duration
		if dash_timer >= dash_duration:
			is_dashing = false
			animated_sprite.modulate = Color(1, 1, 1, 1)  # Reset modulate after dash

	else:
		# Normal movement when not dashing
		velocity = input_vector * speed
		animated_sprite.modulate = Color(1, 1, 1, 1)  # Reset modulate to normal

	# --- Jump Logic ---
	if Input.is_action_just_pressed("jump") and not is_jumping:
		is_jumping = true
		jump_timer = 0.0
		# Play jump animation and go to the second frame
		animated_sprite.play("jump_up")
		animated_sprite.frame = 1  # Set to second frame of the jump animation for the "mid-jump" effect

	if is_jumping:
		jump_timer += _delta
		var t = jump_timer / jump_duration
		if t <= 0.5:
			# Move up (start from 0 and move upwards)
			jump_offset = lerp(0, -jump_height, t * 2)
		else:
			# Move down after peak (return from -jump_height to 0)
			jump_offset = lerp(-jump_height, 0, (t - 0.5) * 2)

		# Apply the jump offset (move the character up and down)
		var sprite_pos = animated_sprite.position
		sprite_pos.y = jump_offset
		animated_sprite.position = sprite_pos

		# End jump after duration
		if jump_timer >= jump_duration:
			is_jumping = false
			jump_offset = 0.0

	# --- Move Player ---
	move_and_slide()

	# --- Animation Logic ---
	var anim = str(animated_sprite.animation)

	if is_jumping:
		# Jump animations
		if input_vector.x > 0:
			animated_sprite.play("jump_right")
		elif input_vector.x < 0:
			animated_sprite.play("jump_left")
		elif input_vector.y < 0:
			animated_sprite.play("jump_up")
		elif input_vector.y > 0:
			animated_sprite.play("jump_down")
		else:
			animated_sprite.play(anim)  # Keep the current animation while jumping
	elif is_dashing:
		# Keep walking animation while dashing
		if input_vector.x > 0:
			animated_sprite.play("walk_right")
		elif input_vector.x < 0:
			animated_sprite.play("walk_left")
		elif input_vector.y < 0:
			animated_sprite.play("walk_up")
		elif input_vector.y > 0:
			animated_sprite.play("walk_down")
	else:
		# Walking / idle
		if input_vector.x > 0:
			animated_sprite.play("walk_right")
		elif input_vector.x < 0:
			animated_sprite.play("walk_left")
		elif input_vector.y < 0:
			animated_sprite.play("walk_up")
		elif input_vector.y > 0:
			animated_sprite.play("walk_down")
		else:
			if anim.begins_with("walk"):
				animated_sprite.play(anim.replace("walk", "idle"))

	_sync_state.rpc(
		global_position,
		animated_sprite.animation,
		animated_sprite.frame,
		animated_sprite.position,
		animated_sprite.modulate
	)


func _ready() -> void:
	remote_target_position = global_position
	apply_network_role()


func apply_network_role() -> void:
	var local_authority := is_multiplayer_authority()
	collision_shape.disabled = not local_authority
	role_label.text = "HOST" if get_multiplayer_authority() == 1 else "PEER"


@rpc("any_peer", "call_remote", "unreliable")
func _sync_state(
	position_value: Vector2,
	animation_name: StringName,
	frame_value: int,
	sprite_position: Vector2,
	sprite_modulate: Color
) -> void:
	if is_multiplayer_authority():
		return

	remote_target_position = position_value
	animated_sprite.play(animation_name)
	animated_sprite.frame = frame_value
	animated_sprite.position = sprite_position
	animated_sprite.modulate = sprite_modulate
