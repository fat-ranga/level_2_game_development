extends KinematicBody

signal player_died

# For the terminal.
signal correct_answer
signal self_destruct

# For fixing physics jitter via interpolation.
const PHYSICS_FRAMERATE = 60
const JITTER_LERP_WEIGHT = 50
var original_head_transform

# Health.
var max_health = 100
var current_health
var death_height = -50

# Movement.
var walk_speed: float = 5.0
var sprint_speed: float = 10.0
var crouch_speed: float = 0.5
var crouch_transition_speed: float = 20.0
var regular_height: float = 1.342
var crouch_height: float = 0.25

var air_acceleration: float = 2.0
var regular_acceleration: float = 10.0
var h_acceleration: float = 10.0 # Determined by either air or regular acceleration.
var jump_power: float = 10.0
var gravity: float = 20.0
var full_contact: bool = false

var mouse_sensitivity: float = 0.06
var has_coyote_time = true
var was_jump_pressed = false

# Hand sway.
var mouse_movement
var sway_threshold = 5
var sway_speed = 0.005
var sway_factor = 1
var original_arms_position = Vector3.ZERO
var relative_mouse_movement = Vector2.ZERO

# Aim down sights (ADS).
export var ads_position = Vector3.ZERO
var ads_speed = 10
var is_ads = false
var ads_fov = 30
var regular_fov
var sprint_fov

var fov_change_factor = 1.3 # High-speed FOV change, determines sprint_fov.
var fov_change_speed = 6 # How fast we transition into different FOVs.

# Movement.
var gravity_vector: Vector3 = Vector3()
var direction: Vector3 = Vector3()
var h_velocity: Vector3 = Vector3() # Horizontal velocity, determined by walk, crouch and sprint speeds.
var movement: Vector3 = Vector3()

# References to other nodes in our player scene.
onready var ground_check = $GroundCheck
onready var head = $Head
onready var head_bonker = $HeadBonker
onready var collision_shape = $CollisionShape
onready var camera = $Head/Camera
onready var first_person_camera = $Head/Camera/ViewportContainer/Viewport/FirstPersonCamera
onready var aimcast = $Head/Camera/AimCast # Raycast used for close-range firefights.
onready var item_manager = $Head/Camera/Arms/Items
onready var hud = $Head/Camera/ViewportContainer/HUD
onready var timer_coyote = $CoyoteTimer
onready var timer_was_jump_pressed = $WasJumpPressedTimer

# Rigging and animation.
onready var arms = $Head/Camera/Arms
#onready var arms_animation_player = $Head/Camera/Arms/player_arms/AnimationPlayer
#onready var hand = $Head/Camera/Hand
#onready var skeleton = $HumanArmature/Skeleton
#onready var skeleton_ik_node = $HumanArmature/Skeleton/SkeletonIK
#onready var animation_tree = $AnimationTree

# Called when the node enters the scene tree for the first time.
func _ready():
	# Set the original head position. For fixing jitter.
	original_head_transform = head.translation
	
	# Set our current health to whatever ouw maximum health is.
	current_health = max_health
	hud.update_health_ui(current_health)
	
	# Keep the mouse positioned at screen centre.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Connect to signals emitted when settings are changed, and call
	# the relevant function.
	Global.connect("fov_updated", self, "_on_fov_updated")
	Global.connect("mouse_sensitivity_updated", self, "_on_mouse_sensitivity_updated")
	
	# Get local location for hand so that the hand sway and ADS has a value to go back to.
	original_arms_position = arms.translation
	
	# Same with the camera FOV.
	regular_fov = camera.fov
	
	# Set our secondary camera to the same FOV.
	first_person_camera.fov = regular_fov
	
	# Set sprint FOV to be a bit larger than the FOV set by the user.
	# Make sure it doesn't end up over 179 degrees, since that's an
	# impossible FOV for a camera.
	sprint_fov = regular_fov * fov_change_factor
	if sprint_fov >= 179:
		sprint_fov = 179
		print("Turn down your FOV, bro!")

func _input(event):
	if event is InputEventMouseMotion:
		# Looking around.
		rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		head.rotate_x(deg2rad(event.relative.y * mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg2rad(-90), deg2rad(80))
		
		# Get relative mouse movement for hand sway.
		relative_mouse_movement = event.relative
	
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				BUTTON_WHEEL_UP:
					item_manager.next_item()
				BUTTON_WHEEL_DOWN:
					item_manager.previous_item()

func _process(delta):
	#fix_jitter(delta)
	# Set the HUD/first person camera to the same position as the actual camera.
	first_person_camera.global_transform = camera.global_transform
	handle_animation()
	handle_items()
	

func _physics_process(delta):
	# If we fall off the world, die.
	if translation.y < death_height:
		die()
	handle_movement(delta)
	handle_hand_sway(delta)
	process_movement_effects(delta)

func die():
	emit_signal("player_died")

func fix_jitter(delta):
	var fps = Engine.get_frames_per_second()
	# Slices the direction vector into little pieces, which get smaller as FPS increases.
	var lerp_interval = direction/fps
	# The position we should actually be at is our physics position plus these little slices.
	var lerp_position = global_transform.origin# + lerp_interval
	var skeleton_lerp_position = lerp_position + lerp_interval
	lerp_position = (lerp_position + original_head_transform) + lerp_interval
	
	# If the FPS is greater than the physics framerate, then we interpolate
	# to where the head and stuff should be in any _process frame.
	# Otherwise, we don't bother with any interpolation.
#	if fps > PHYSICS_FRAMERATE:
#		head.set_as_toplevel(true)
#		head.global_transform.origin = head.global_transform.origin.linear_interpolate(lerp_position, JITTER_LERP_WEIGHT * delta)
#		skeleton.set_as_toplevel(true)
#		skeleton.global_transform.origin = skeleton.global_transform.origin.linear_interpolate(skeleton_lerp_position, JITTER_LERP_WEIGHT * delta)
#	else:
#		#head.global_transform = head.global_transform
#		#head.set_as_toplevel(false)
#
#		head.set_as_toplevel(true)
#		head.global_transform.origin = head.global_transform.origin.linear_interpolate(lerp_position, JITTER_LERP_WEIGHT * delta)
#		#print(head.global_transform.origin)
#		skeleton.set_as_toplevel(true)
#		skeleton.global_transform.origin = skeleton.global_transform.origin.linear_interpolate(skeleton_lerp_position, JITTER_LERP_WEIGHT * delta)

func aim_down_sights(value:bool, delta):
	is_ads = value
	
	# If value is set to true, we look down sights.
	if is_ads:
		arms.transform.origin = arms.transform.origin.linear_interpolate(ads_position, ads_speed * delta)
		camera.fov = lerp(camera.fov, ads_fov, ads_speed * delta)
		first_person_camera.fov = lerp(camera.fov, ads_fov, ads_speed * delta)
	# If not, we don't.
	else:
		arms.transform.origin = arms.transform.origin.linear_interpolate(original_arms_position, ads_speed * delta)
		camera.fov = lerp(camera.fov, regular_fov, ads_speed * delta)
		first_person_camera.fov = lerp(camera.fov, regular_fov, ads_speed * delta)

func process_movement_effects(delta):
	# Head bobbing.
	if h_velocity.length() <3.0 or is_on_floor() == false:
		pass
	elif h_velocity.length():
		pass
	else:
		pass
	
	# High velocity FOV change effect.
	if Input.is_action_pressed("sprint"):
		camera.fov = lerp(camera.fov, sprint_fov , fov_change_speed * delta)
		first_person_camera.fov = lerp(first_person_camera.fov, sprint_fov , fov_change_speed * delta)
	else:
		camera.fov = lerp(camera.fov, regular_fov , fov_change_speed * delta)
		first_person_camera.fov = lerp(first_person_camera.fov, regular_fov , fov_change_speed * delta)

func handle_movement(delta):
	# Which way we are going to move.
	direction = Vector3()
	
	# By default, we are not hitting our head on a ceiling.
	var is_head_bonked = false
	
	# The head_bonker raycast checks if we are hitting our head on a ceiling.
	if head_bonker.is_colliding():
		is_head_bonked = true
	
	if is_on_floor() or ground_check.is_colliding():
		has_coyote_time = true
		if was_jump_pressed:
			gravity_vector = Vector3.UP * jump_power
			was_jump_pressed = false
	else:
		timer_coyote.start() # Starts the coyote time countdown.
	
	# Check if we're on the ground or not.
	if ground_check.is_colliding():
		full_contact = true
	else:
		full_contact = false
	
	# Change gravity direction so we stick to slopes if moving down them.
	if not is_on_floor():
		gravity_vector += Vector3.DOWN * gravity * delta
		h_acceleration = air_acceleration
	elif is_on_floor() and full_contact:
		# Multiply gravity by some small value when on the ground so that we will still
		# stick to the ground, but won't immediately fall fast if we go off a slope.
		gravity_vector = -get_floor_normal() * (gravity * 0.2)
		h_acceleration = regular_acceleration
	else:
		gravity_vector = -get_floor_normal()
		h_acceleration = regular_acceleration
	
	# Jumping.
	if Input.is_action_pressed("jump") and not is_head_bonked:
		was_jump_pressed = true
		timer_was_jump_pressed.start()
		if has_coyote_time:
			gravity_vector = Vector3.UP * jump_power
			has_coyote_time = false # Make sure we cannot jump again.
	
	# Forwards/backwards and left/right input and movement.
	direction += transform.basis.x * (Input.get_action_strength("move_left") - Input.get_action_strength("move_right"))
	direction += transform.basis.z * (Input.get_action_strength("move_forwards") - Input.get_action_strength("move_backwards"))
	
	# Ensure we aren't faster when moving diagonally.
	direction = direction.normalized()
	
	# Smooth acceleration and sprinting.
	if Input.is_action_pressed("sprint"):
		h_velocity = h_velocity.linear_interpolate(direction * sprint_speed, h_acceleration * delta)
	else:
		h_velocity = h_velocity.linear_interpolate(direction * walk_speed, h_acceleration * delta)
	
	if Input.is_action_pressed("crouch"):
		collision_shape.shape.height -= crouch_transition_speed
		h_velocity = h_velocity.linear_interpolate(direction * crouch_speed, h_acceleration * delta)
	elif not is_head_bonked:
		collision_shape.shape.height += crouch_transition_speed
	# Crouch and regular height determine the shortest and highest we can stand, respectively.
	collision_shape.shape.height = clamp(collision_shape.shape.height, crouch_height, regular_height)
	
	# Movement vector calculated from direction and gravity.
	movement.z = h_velocity.z + gravity_vector.z
	movement.x = h_velocity.x + gravity_vector.x
	movement.y = gravity_vector.y
	
	# Actually move the player.
	move_and_slide(movement, Vector3.UP)

func handle_hand_sway(delta):
	# Aim down sights.
	if Input.is_action_pressed("aim_down_sights"):
		aim_down_sights(true, delta)
	else:
		aim_down_sights(false, delta)
	
	var location = Vector3(
		original_arms_position.x - relative_mouse_movement.x * 5,
		original_arms_position.y + relative_mouse_movement.y * 5,
		original_arms_position.z
	)
	arms.translation = arms.translation.linear_interpolate(location, delta * sway_speed)
	relative_mouse_movement = Vector2.ZERO

func handle_animation():
	pass
	# TODO check if moving foward abckwadfs
	#animation_tree.set("parameters/IdleWalkRun/blend_position", h_velocity.length())

func handle_items():
	if Input.is_action_just_pressed("select_melee"):
		item_manager.change_item("Melee")
	if Input.is_action_just_pressed("select_primary"):
		item_manager.change_item("Primary")
	if Input.is_action_just_pressed("select_secondary"):
		item_manager.change_item("Secondary")
	
	# Firing.
	if Input.is_action_pressed("fire"):
		item_manager.fire()
	if Input.is_action_just_released("fire"):
		item_manager.fire_stop()
	
	# Reloading.
	if Input.is_action_just_pressed("reload"):
		item_manager.reload()
	
	# Drop item.
	if Input.is_action_just_pressed("drop_item"):
		item_manager.drop_item()
	
	# Item pickup.
	item_manager.process_item_pickup()

# Update the regular/default FOV variable to the one set.
func _on_fov_updated(value):
	regular_fov = value

func _on_mouse_sensitivity_updated(value):
	mouse_sensitivity = value

func damage(damage):
	current_health -= (damage)
	hud.update_health_ui(current_health)
	if current_health < 0:
		die()

func _on_WasJumpPressedTimer_timeout():
	was_jump_pressed = false
	pass

# This means we can jump even if we aren't touching the ground.
func _on_CoyoteTimer_timeout():
	has_coyote_time = false
	pass

# These are passed from the HUD, now we use these to influence the flow of the game.
func _on_HUD_correct_answer():
	emit_signal("correct_answer")

func _on_HUD_self_destruct():
	emit_signal("self_destruct")
	get_tree().change_scene("res://scenes/bad_ending.tscn")
