class_name Enemy extends CharacterBody2D

signal enemy_died
# --- CONFIGURATION ---
@export_group("Movement")
@export var speed = 100.0            
@export var separation_force = 50.0 

@export_group("Combat")
@export var max_hp = 30
@export var damage = 10
@export var attack_cooldown = 1.0
@export var knockback_friction = 600.0
@export var knockback_power = 400.0    

@export_group("AI")
@export var detection_range = 400.0 
@export var stop_distance = 20.0    
@export var attack_windup_time = 0.5
@export var alert_duration = 0.6 
@export var confusion_duration = 1.5 # How long to wait at last seen spot
@export var wander_radius: float = 150.0 # How far from spawn they can roam
@export var min_wander_wait: float = 1.0
@export var max_wander_wait: float = 3.0

# --- STATE VARIABLES ---
var hp = max_hp
var can_attack = true
var knockback_velocity = Vector2.ZERO 
var is_alerted: bool = false 
var is_reacting: bool = false 
var home_position: Vector2 # Where they spawned (the center of their wander circle)
var wander_target: Variant = null # Current random spot we are walking to
var wander_timer: float = 0.0 # How long to stand still between walks

# --- MEMORY VARIABLES ---
var last_known_pos: Variant = null # Stores Vector2 or null
var is_confused: bool = false # Tracks if we are looking around at the last spot

# --- AUDIO VARIABLES ---
var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.35 

# --- BURN STATE ---
var is_burning: bool = false
var burn_duration: float = 0.0
var burn_damage_per_tick: int = 0
var burn_tick_timer: float = 0.0

# --- NODES ---
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $hitbox
@onready var vfx: AnimatedSprite2D = $vfx
@onready var hit_particles: CPUParticles2D = $HitParticles 
@onready var death: AnimatedSprite2D = $death
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

func _ready():
	hp = max_hp
	if death: death.visible = false
	
	home_position = global_position
	
	vfx.visible = false 
	if not vfx.animation_finished.is_connected(_on_vfx_finished):
		vfx.animation_finished.connect(_on_vfx_finished)

	if hitbox and not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	if hit_particles: 
		hit_particles.emitting = false

func _physics_process(delta: float) -> void:
	if footstep_timer > 0:
		footstep_timer -= delta

	# 1. KNOCKBACK PRIORITY
	if knockback_velocity != Vector2.ZERO:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_friction * delta)
		velocity = knockback_velocity
		move_and_slide()
		return 
	
	if is_burning:
		_process_burn(delta)

	# 2. WAIT FOR ANIMATIONS (Alert or Confusion)
	if is_reacting or is_confused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not can_attack:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# --- AI DECISION TREE ---
	var target = get_active_player()
	var dist_to_player = 99999.0
	var has_los = false
	
	if target:
		dist_to_player = global_position.distance_to(target.global_position)
		has_los = can_see_target(target)

	# CASE A: Player is in Range AND (Visible OR Close Enough to Touch)
	# FIX: We added "or dist_to_player <= stop_distance"
	# This ensures that if we are hugging the player, we don't stop attacking just because 
	# the raycast acted weird at close range.
	if target and dist_to_player < detection_range and (has_los or dist_to_player <= stop_distance):
		
		# 1. Trigger Alert if new sighting
		if not is_alerted:
			start_alert_sequence(target)
			return

		# 2. Update Memory
		last_known_pos = target.global_position
		
		# 3. Combat or Chase
		if dist_to_player <= stop_distance:
			velocity = Vector2.ZERO
			if can_attack: start_attack_sequence(target)
			else: 
				if animated_sprite_2d.animation != "attack": play_anim("idle")
		else:
			move_to_position(target.global_position)

	# CASE B: Player NOT visible (Blocked by wall), but we remember
	elif last_known_pos != null:
		var dist_to_memory = global_position.distance_to(last_known_pos)
		
		if dist_to_memory > 5.0:
			# Still travelling to last known spot
			move_to_position(last_known_pos)
		else:
			# We arrived at the spot, but player is gone.
			start_confusion_sequence()
			
			# This makes them patrol the area where they last saw you
			home_position = global_position
			
	# CASE C: No target, no memory -> WANDER
	else:
		if is_alerted: is_alerted = false
		
		wander_behavior(delta)

# --- SEQUENCES ---

func start_alert_sequence(target: Node2D):
	is_reacting = true 
	velocity = Vector2.ZERO 
	
	var direction = global_position.direction_to(target.global_position)
	face_direction(direction.x)
	play_anim("idle")
	play_alert_vfx()
	
	await get_tree().create_timer(alert_duration).timeout
	
	is_alerted = true 
	is_reacting = false 

func start_confusion_sequence():
	# We reached the spot, nobody is there.
	is_confused = true
	velocity = Vector2.ZERO
	play_anim("idle")
	
	# Optional: Show a "?" VFX here if you have one
	# AudioManager.play_sfx("confusion", 0.1)
	
	await get_tree().create_timer(confusion_duration).timeout
	
	# Forget everything and return to idle
	last_known_pos = null
	is_alerted = false
	is_confused = false

func play_alert_vfx():
	if vfx:
		vfx.visible = true
		vfx.frame = 0
		vfx.rotation = 0
		vfx.position = Vector2(0, -40) 
		vfx.play("exclamation")
		AudioManager.play_sfx("exclamation", 0.0, -8.0)

# --- MOVEMENT LOGIC (REFACTORED) ---
# Renamed from chase_target to move_to_position to handle Vector2s
func move_to_position(target_pos: Vector2):
	var direction = global_position.direction_to(target_pos)
	var final_velocity = direction * speed
	final_velocity += get_separation_force()
	
	velocity = final_velocity
	move_and_slide()
	
	play_anim("run")
	
	if footstep_timer <= 0:
		AudioManager.play_sfx("grass", 0.1, -20.0)
		footstep_timer = FOOTSTEP_INTERVAL
	
	face_direction(direction.x)

func idle_behavior():
	velocity = Vector2.ZERO
	move_and_slide()
	play_anim("idle")

func get_separation_force() -> Vector2:
	var force = Vector2.ZERO
	var neighbors = get_tree().get_nodes_in_group("enemy")
	for neighbor in neighbors:
		if neighbor != self and global_position.distance_to(neighbor.global_position) < 30:
			var push_dir = (global_position - neighbor.global_position).normalized()
			force += push_dir * separation_force
	return force

func face_direction(dir_x: float):
	if dir_x < 0: 
		animated_sprite_2d.flip_h = true 
	elif dir_x > 0: 
		animated_sprite_2d.flip_h = false

# --- COMBAT LOGIC ---
func take_damage(amount: int, source_pos: Vector2 = Vector2.ZERO, is_critical: bool = false, is_fire_damage: bool = false):
	hp -= amount
	
	vfx.visible = true
	vfx.frame = 0
	vfx.position = Vector2.ZERO 
	
	if is_fire_damage:
		vfx.play("fire") 
		vfx.rotation = randf_range(0, 6.28) 
	else:
		vfx.play("slash") 
		vfx.rotation = 0
		
	if source_pos != Vector2.ZERO and not is_fire_damage:
		var knockback_dir = (global_position - source_pos).normalized()
		var power = knockback_power * 1.5 if is_critical else knockback_power
		knockback_velocity = knockback_dir * power
		
		if hit_particles: 
			hit_particles.rotation = knockback_dir.angle()
			hit_particles.restart()
			hit_particles.emitting = true

	if is_fire_damage:
		modulate = Color(2, 0.5, 0)
		AudioManager.play_sfx("fire", 0.1, -20)
	elif is_critical:
		modulate = Color(0.6, 0, 0) 
		AudioManager.play_sfx("crit", 0.1)
	else:
		modulate = Color(10, 10, 10)
		AudioManager.play_sfx("hit", 0.1)
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)
	
	var source = "Burn" if is_fire_damage else "Attack"
	print("%s took %s damage from %s. HP: %s" % [name, amount, source, hp])

	if hp <= 0:
		die()

func start_attack_sequence(target_node = null):
	can_attack = false
	
	if target_node:
		var dir_to_target = global_position.direction_to(target_node.global_position)
		face_direction(dir_to_target.x)
	
	play_anim("attack")
	AudioManager.play_sfx("woosh", 0.1, -10)
	
	if hp > 0:
		var bodies = hitbox.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("player") and body.has_method("take_damage"):
				body.take_damage(damage, global_position, self)
	
	await get_tree().create_timer(attack_windup_time).timeout
	
	if animated_sprite_2d.animation == "attack" and animated_sprite_2d.is_playing():
		await animated_sprite_2d.animation_finished
	
	play_anim("idle")
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func die():
	if not is_physics_processing(): return

	# 1. STOP GAMEPLAY LOGIC
	set_physics_process(false)
	can_attack = false
	velocity = Vector2.ZERO
	
	# 2. KILL COLLISIONS
	if collision_shape_2d:
		collision_shape_2d.set_deferred("disabled", true)
	
	# Disable Hitbox (So they don't take more damage or deal damage)
	if hitbox:
		hitbox.set_deferred("monitoring", false)
		hitbox.set_deferred("monitorable", false)
	
	# 3. HIDE ALIVE VISUALS
	animated_sprite_2d.visible = false 
	vfx.visible = false
	if hit_particles: hit_particles.emitting = false

	# 4. PLAY DEATH ANIMATION
	if death:
		death.visible = true
		death.play("default")
		AudioManager.play_sfx("enemy_death", 0.1)
		await death.animation_finished
	
	# 5. DELETE OBJECT
	emit_signal("enemy_died")
	queue_free()

func get_active_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.visible: return p
	return null

func play_anim(anim_name: String):
	if animated_sprite_2d.animation == anim_name and animated_sprite_2d.is_playing():
		return
	if animated_sprite_2d.sprite_frames.has_animation(anim_name):
		animated_sprite_2d.play(anim_name)

func _on_hitbox_body_entered(_body): pass
func _on_vfx_finished(): vfx.visible = false

func apply_burn(dmg_per_tick: int, duration: float):
	is_burning = true
	burn_damage_per_tick = dmg_per_tick
	burn_duration = duration
	burn_tick_timer = 0.0
	modulate = Color(1.5, 0.5, 0)

func _process_burn(delta: float):
	burn_duration -= delta
	burn_tick_timer -= delta
	
	if burn_tick_timer <= 0:
		take_damage(burn_damage_per_tick, Vector2.ZERO, false, true)
		burn_tick_timer = 1.0 
	
	if burn_duration <= 0:
		is_burning = false
		modulate = Color.WHITE

func can_see_target(target: Node2D) -> bool:
	# 1. Get the Physics State
	var space_state = get_world_2d().direct_space_state
	
	# 2. Create the Raycast parameters
	# From: Enemy Eye Level, To: Player Position
	var params = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	
	# 3. Exclude the Enemy itself so we don't block our own view
	params.exclude = [self]
	
	# 4. (Optional) Set Mask: Ensure walls and players are on layers this ray can hit!
	# By default, it hits everything.
	
	# 5. Shoot the laser!
	var result = space_state.intersect_ray(params)
	
	# 6. Check result
	if result:
		# If the first thing we hit is the player, we have line of sight
		if result.collider == target:
			return true
	
	# If we hit a wall or nothing, return false
	return false

func wander_behavior(delta: float):
	# 1. If we are waiting, count down and stand still
	if wander_timer > 0:
		wander_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		play_anim("idle")
		return

	# 2. If we don't have a target, pick a valid random one
	if wander_target == null:
		wander_target = get_random_wander_point()
	
	# 3. Move towards the wander target
	move_to_position(wander_target)
	
	# --- NEW: WALL AVOIDANCE LOGIC ---
	# We check if the move_and_slide() inside move_to_position() hit anything
	if get_slide_collision_count() > 0:
		var collision = get_slide_collision(0)
		var collider = collision.get_collider()
		
		# Check if we hit something that IS NOT a Player or Enemy (so, a Wall/Prop)
		# (We assume players/enemies are in groups "player" and "enemy")
		if collider and not collider.is_in_group("player") and not collider.is_in_group("enemy"):
			
			# "Bonk!" - We hit a wall.
			# 1. Clear the invalid target
			wander_target = null
			
			# 2. Briefly pause to "think" before turning (makes it look natural)
			wander_timer = randf_range(0.5, 1.0) 
			
			# 3. Stop moving immediately
			velocity = Vector2.ZERO
			play_anim("idle")
			return

	# 4. Check if we arrived at destination
	var dist_to_target = global_position.distance_to(wander_target)
	if dist_to_target < 10.0:
		wander_target = null
		wander_timer = randf_range(min_wander_wait, max_wander_wait)
		velocity = Vector2.ZERO
		play_anim("idle")

func get_random_wander_point() -> Vector2:
	# Pick a random angle and distance
	var angle = randf() * 2.0 * PI
	var dist = randf() * wander_radius
	
	# Calculate offset based on Home Position (so they don't wander off the map)
	var offset = Vector2(cos(angle), sin(angle)) * dist
	return home_position + offset
