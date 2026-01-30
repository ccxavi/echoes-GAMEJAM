extends Enemy 
class_name BombThrower

@export var bomb_scene: PackedScene 

@export var retreat_distance = 150.0 
@export var throw_distance = 350.0   

func _ready():
	# This runs the Base Enemy _ready() first, so 'home_position' is set correctly!
	super._ready()
	
	# Override Base Stats
	stop_distance = throw_distance
	speed = 80.0
	max_hp = 30

func _physics_process(delta: float) -> void:
	if footstep_timer > 0:
		footstep_timer -= delta

	# A. BASE LOGIC (Knockback & Burn)
	if knockback_velocity != Vector2.ZERO:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_friction * delta)
		velocity = knockback_velocity
		move_and_slide()
		return 
	
	if is_burning:
		_process_burn(delta)
	
	# B. WAIT FOR ANIMATIONS
	if is_reacting or is_confused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not can_attack:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# C. TARGETING & AI DECISION
	var target = get_active_player()
	var dist = 99999.0
	var has_los = false
	
	if target:
		dist = global_position.distance_to(target.global_position)
		has_los = can_see_target(target)

	# --- CASE 1: Player is Visible (Aggro) ---
	if target and dist < detection_range and (has_los or dist < 50.0):
		
		# 1. Alert 
		if not is_alerted:
			start_alert_sequence(target)
			return

		# 2. Update Memory
		last_known_pos = target.global_position

		# 3. RANGED BEHAVIOR (Specific to Bomber)
		if dist < retreat_distance:
			run_away_from_target(target)
			
		elif dist <= stop_distance:
			velocity = Vector2.ZERO
			if can_attack: 
				start_attack_sequence(target)
			else:
				var dir = global_position.direction_to(target.global_position)
				face_direction(dir.x)
				if animated_sprite_2d.animation != "attack":
					play_anim("idle")
		else:
			move_to_position(target.global_position)
			
	# --- CASE 2: Player Not Visible, but we have Memory ---
	elif last_known_pos != null:
		var dist_to_memory = global_position.distance_to(last_known_pos)
		
		if dist_to_memory > 10.0:
			move_to_position(last_known_pos)
		else:
			start_confusion_sequence()
			
			# --- NEW: Update Patrol Spot ---
			# Now the bomber will patrol where they last saw you, 
			# instead of walking all the way back to spawn.
			home_position = global_position
			
	# --- CASE 3: Idle / Wander ---
	else:
		if is_alerted: is_alerted = false
		
		# --- NEW: Enable Wandering ---
		# Instead of standing still (idle_behavior), we use the parent's wander logic
		wander_behavior(delta)

# --- HELPER: RETREAT ---
func run_away_from_target(target: Node2D):
	var direction = target.global_position.direction_to(global_position)
	var final_velocity = direction * speed
	
	final_velocity += get_separation_force()
	
	velocity = final_velocity
	move_and_slide()
	
	play_anim("run")
	
	if footstep_timer <= 0:
		AudioManager.play_sfx("grass", 0.1, -20.0)
		footstep_timer = FOOTSTEP_INTERVAL
	
	face_direction(direction.x) 

# --- ATTACK OVERRIDE ---
func start_attack_sequence(target_node = null):
	can_attack = false
	
	if target_node:
		var dir = global_position.direction_to(target_node.global_position)
		face_direction(dir.x)
	
	play_anim("attack")
	
	await get_tree().create_timer(0.3).timeout
	
	if bomb_scene and target_node:
		var bomb = bomb_scene.instantiate()
		get_tree().current_scene.add_child(bomb)
		
		var spawn_pos = global_position + (target_node.global_position - global_position).normalized() * 20
		bomb.start(spawn_pos, target_node.global_position)
		
		AudioManager.play_sfx("tnt_throw", 0.1)
	
	if animated_sprite_2d.animation == "attack" and animated_sprite_2d.is_playing():
		await animated_sprite_2d.animation_finished
		
	play_anim("idle")
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true
