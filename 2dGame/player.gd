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

# --- Dash Mechanic ---
func _physics_process(_delta):
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
		$AnimatedSprite2D.modulate = Color(1, 1, 1, 0.3)

		# End dash after dash_duration
		if dash_timer >= dash_duration:
			is_dashing = false
			$AnimatedSprite2D.modulate = Color(1, 1, 1, 1)  # Reset modulate after dash

	else:
		# Normal movement when not dashing
		velocity = input_vector * speed
		$AnimatedSprite2D.modulate = Color(1, 1, 1, 1)  # Reset modulate to normal

	# --- Jump Logic ---
	if Input.is_action_just_pressed("jump") and not is_jumping:
		is_jumping = true
		jump_timer = 0.0
		# Play jump animation and go to the second frame
		$AnimatedSprite2D.play("jump_up")
		$AnimatedSprite2D.frame = 1  # Set to second frame of the jump animation for the "mid-jump" effect

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
		var sprite_pos = $AnimatedSprite2D.position
		sprite_pos.y = jump_offset
		$AnimatedSprite2D.position = sprite_pos

		# End jump after duration
		if jump_timer >= jump_duration:
			is_jumping = false
			jump_offset = 0.0

	# --- Move Player ---
	move_and_slide()

	# --- Animation Logic ---
	var anim = str($AnimatedSprite2D.animation)

	if is_jumping:
		# Jump animations
		if input_vector.x > 0:
			$AnimatedSprite2D.play("jump_right")
		elif input_vector.x < 0:
			$AnimatedSprite2D.play("jump_left")
		elif input_vector.y < 0:
			$AnimatedSprite2D.play("jump_up")
		elif input_vector.y > 0:
			$AnimatedSprite2D.play("jump_down")
		else:
			$AnimatedSprite2D.play(anim)  # Keep the current animation while jumping
	elif is_dashing:
		# Keep walking animation while dashing
		if input_vector.x > 0:
			$AnimatedSprite2D.play("walk_right")
		elif input_vector.x < 0:
			$AnimatedSprite2D.play("walk_left")
		elif input_vector.y < 0:
			$AnimatedSprite2D.play("walk_up")
		elif input_vector.y > 0:
			$AnimatedSprite2D.play("walk_down")
	else:
		# Walking / idle
		if input_vector.x > 0:
			$AnimatedSprite2D.play("walk_right")
		elif input_vector.x < 0:
			$AnimatedSprite2D.play("walk_left")
		elif input_vector.y < 0:
			$AnimatedSprite2D.play("walk_up")
		elif input_vector.y > 0:
			$AnimatedSprite2D.play("walk_down")
		else:
			if anim.begins_with("walk"):
				$AnimatedSprite2D.play(anim.replace("walk", "idle"))
