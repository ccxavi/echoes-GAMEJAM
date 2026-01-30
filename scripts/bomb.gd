extends Area2D

@export var speed = 300.0
@export var damage = 15
@export var blast_radius = 50.0

# --- SHAKE SETTINGS ---
@export var shake_intensity = 15.0  # How many pixels to shake (Standard hit is ~5)
@export var shake_duration = 0.2    # How long the earth quakes

var target_pos: Vector2
var velocity: Vector2
var has_exploded = false

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var vfx: AnimatedSprite2D = $vfx

func start(start_pos: Vector2, _target_pos: Vector2):
	global_position = start_pos
	target_pos = _target_pos
	
	if vfx:
		vfx.visible = false
	
	velocity = global_position.direction_to(target_pos) * speed
	
	var tween = create_tween().set_loops()
	tween.tween_property(animated_sprite_2d, "rotation", 6.28, 0.5).as_relative()
	
	if animated_sprite_2d.sprite_frames.has_animation("default"):
		animated_sprite_2d.play("default")

func _physics_process(delta):
	if has_exploded: return

	global_position += velocity * delta
	
	if global_position.distance_to(target_pos) < 10.0:
		explode()

func explode():
	if has_exploded: return
	has_exploded = true
	
	# 1. Visuals
	animated_sprite_2d.visible = false 
	
	if vfx:
		vfx.visible = true
		vfx.frame = 0 
		vfx.play("explode")
		AudioManager.play_sfx("tnt_explode", 0.1, -10)
	
	# --- TRIGGER SHAKE ---
	# We call this without 'await' so it runs in parallel with damage calculation
	apply_camera_shake()
	
	# 2. Deal Area Damage
	var potential_targets = get_tree().get_nodes_in_group("player")
	
	for body in potential_targets:
		var dist = global_position.distance_to(body.global_position)
		if dist <= blast_radius:
			if body.has_method("take_damage"):
				body.take_damage(damage, global_position, self)
				print("Bomb hit player!")

	# 3. Cleanup
	if vfx and vfx.sprite_frames.has_animation("explode"):
		await vfx.animation_finished
	else:
		await get_tree().create_timer(0.5).timeout
		
	queue_free()

func _on_body_entered(body):
	if not has_exploded:
		if body.is_in_group("player") or body is TileMap:
			explode()

# --- NEW HELPER FUNCTION ---
func apply_camera_shake():
	# 1. Find the active camera (works for any character)
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	var original_offset = camera.offset
	var elapsed = 0.0
	
	# 2. Shake Loop
	while elapsed < shake_duration:
		# Decay: The shake gets weaker as time passes (starts at 1.0, ends at 0.0)
		var dampening = 1.0 - (elapsed / shake_duration)
		var current_intensity = shake_intensity * dampening
		
		# Apply random offset
		var random_offset = Vector2(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)
		camera.offset = original_offset + random_offset
		
		# Wait for next frame
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	
	# 3. Reset
	camera.offset = original_offset
