class_name Character extends CharacterBody2D

# --- SIGNALS ---
signal health_changed(current_hp, max_hp)
signal character_died(character_node)
signal ability_used(current_cooldown, max_cooldown)

@export_group("Stats")
@export var portrait_img: Texture2D
@export var max_hp = 100
@export var speed = 300.0
@export var damage = 1
@export var defense = 0
@export var crit_chance = 0.2
@export var crit_multiplier = 2.0
@export var recoil_strength = 300.0

@export_group("Combat Response")
@export var knockback_strength = 600.0
@export var knockback_decay = 2000.0
@export var invulnerability_time = 1.0
@export var attack_move_speed_multiplier: float = 0.5 # NEW: 50% speed while attacking

# ... (Keep your Dash/Ability exports here) ...
@export_group("Universal Dash")
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0

@export_group("Special Ability")
@export var ability_cooldown_duration = 3.0
@export var ability_name = "None"

@onready var hp = max_hp
@onready var animated_sprite_2d: AnimatedSprite2D = $main_sprite
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var attack_area: Area2D = $WeaponPivot/AttackArea
@onready var vfx: AnimatedSprite2D = $vfx
@onready var particles: CPUParticles2D = $particles
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var collision_shape_2d_attack: CollisionShape2D = $WeaponPivot/AttackArea/CollisionShape2D

var knockback_velocity = Vector2.ZERO
var is_invulnerable = false
var is_attacking = false
var is_dead = false
var is_dashing: bool = false
var can_dash: bool = true

const SLIDE_THRESHOLD = 50.0
var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.35

var ability_timer: Timer
var dash_timer: Timer # ADDED: Required for Dash HUD tracking

func _ready():
	# --- TIMER SETUP ---
	# FIX: Set Process Mode to ALWAYS so cooldowns finish even when character is inactive
	ability_timer = Timer.new()
	ability_timer.one_shot = true
	ability_timer.process_mode = Node.PROCESS_MODE_ALWAYS 
	ability_timer.wait_time = ability_cooldown_duration
	add_child(ability_timer)
	
	dash_timer = Timer.new()
	dash_timer.one_shot = true
	dash_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	dash_timer.wait_time = dash_cooldown
	add_child(dash_timer)

	if animated_sprite_2d.animation_finished.is_connected(_on_animation_finished) == false:
		animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	
	if vfx:
		vfx.visible = false
		if vfx.animation_finished.is_connected(_on_vfx_finished) == false:
			vfx.animation_finished.connect(_on_vfx_finished)
	
	if particles:
		particles.emitting = false

# --- HUD HELPERS ---

# FIX: This handles P_Skill and S_Skill specifically
func get_skill_cooldown(skill_key: String) -> Array:
	if skill_key == "dash":
		return [dash_timer.time_left, dash_timer.wait_time]
	# Special abilities (Heal/Charge)
	return [ability_timer.time_left, ability_timer.wait_time]

# FIX: Return zeros to prevent ability cooldowns from appearing on character cards
func get_cooldown_status():
	return [0.0, 1.0]

func _unhandled_input(event):
	if is_attacking or is_dead: return
	
	if event.is_action_pressed("dash") and can_dash and not is_dashing:
		start_universal_dash()
	
	if event.is_action_pressed("attack"):
		start_attack()

# --- PHYSICS MOVEMENT FIX ---
func _physics_process(delta):
	# 1. PRIORITY: DASH MOVEMENT
	if is_dashing:
		if Engine.get_physics_frames() % 4 == 0:
			spawn_dash_ghost()
		move_and_slide()
		return
		
	# 2. PRIORITY: KNOCKBACK DECAY
	if knockback_velocity != Vector2.ZERO:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)

	# 3. PRIORITY: ATTACKING (Updated to allow movement)
	if is_attacking:
		# Calculate Input Direction
		var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		
		# Combine: (Reduced Input Speed) + (Recoil)
		velocity = (direction * speed * attack_move_speed_multiplier) + knockback_velocity
		
		move_and_slide()
		return

	# 4. NORMAL MOVEMENT
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = (direction * speed) + knockback_velocity
	
	var mouse_pos = get_global_mouse_position()
	animated_sprite_2d.flip_h = (mouse_pos.x < global_position.x)

	# ANIMATION & SOUND
	var current_speed = velocity.length()
	
	if footstep_timer > 0:
		footstep_timer -= delta
	
	if current_speed > SLIDE_THRESHOLD and knockback_velocity.length() > SLIDE_THRESHOLD:
		if particles and not particles.emitting:
			particles.emitting = true
	else:
		if particles and particles.emitting:
			particles.emitting = false
			
		if direction != Vector2.ZERO:
			play_anim("run")
			if footstep_timer <= 0:
				AudioManager.play_sfx("grass", 0.1, -5.0)
				footstep_timer = FOOTSTEP_INTERVAL
		else:
			play_anim("idle")
		
	move_and_slide()

# --- UNIVERSAL DASH LOGIC ---
func start_universal_dash():
	# A. Determine Direction
	var move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dash_dir = move_input
	
	if dash_dir == Vector2.ZERO:
		dash_dir = Vector2.LEFT if animated_sprite_2d.flip_h else Vector2.RIGHT

	# B. Set State
	is_dashing = true
	can_dash = false
	is_invulnerable = true
	velocity = dash_dir.normalized() * dash_speed
	
	# C. Visual Juice
	if particles: particles.emitting = true
	AudioManager.play_sfx("woosh", 0.1)
	
	modulate = Color(0.5, 1, 1)
	
	# D. Dash Duration
	await get_tree().create_timer(dash_duration).timeout
	
	# E. End Dash
	is_dashing = false
	velocity = Vector2.ZERO
	modulate = Color.WHITE # Reset color
	is_invulnerable = false
	if particles: particles.emitting = false
	
	# F. Cooldown (Updated for Timer node sync)
	dash_timer.start()
	await dash_timer.timeout
	can_dash = true

# --- VFX: GHOST TRAIL ---
func spawn_dash_ghost():
	var ghost = Sprite2D.new()
	var texture = animated_sprite_2d.sprite_frames.get_frame_texture(animated_sprite_2d.animation, animated_sprite_2d.frame)
	
	ghost.texture = texture
	ghost.global_position = global_position
	ghost.flip_h = animated_sprite_2d.flip_h
	ghost.modulate = Color(0.5, 0.5, 0.5, 0.4)
	ghost.z_index = 5
	
	get_tree().current_scene.add_child(ghost)
	
	var tween = get_tree().create_tween()
	tween.bind_node(ghost) # Bind to ghost so if ghost is deleted, tween stops
	tween.tween_property(ghost, "modulate:a", 0.0, 0.3)
	tween.tween_callback(ghost.queue_free)

func try_use_special_ability():
	if is_dead: return
	if not ability_timer.is_stopped():
		print("Ability on Cooldown!")
		return

	if ability_name == "Dash":
		start_universal_dash()
		return
	elif ability_name == "Heal":
		perform_heal_skill()
	else:
		print("No ability assigned.")
		return

	ability_timer.start()
	emit_signal("ability_used", ability_cooldown_duration, ability_cooldown_duration)

func perform_dash():
	start_universal_dash()

func perform_heal_skill():
	print("Charging Heal!")
	if get_parent().has_method("queue_heal_for_next_switch"):
		get_parent().queue_heal_for_next_switch(50)

func _on_vfx_finished():
	vfx.visible = false

func take_damage(amount: int, source_pos: Vector2, attacker: Node = null):
	if is_invulnerable or is_dead: return # Don't take damage if already dead
	if attacker and attacker.is_in_group("player"): return

	var reduced_damage = max(1, amount - defense)
	
	hp = clamp(hp - reduced_damage, 0, max_hp)
	
	AudioManager.play_sfx("hurt", 0.1)
	print("%s took %d damage. HP: %s" % [name, reduced_damage, hp])
	
	health_changed.emit(hp, max_hp)
	
	if vfx:
		vfx.visible = true
		vfx.frame = 0
		vfx.play("slash")
	
	if hp <= 0:
		die()
		return

	if source_pos != Vector2.ZERO:
		var knockback_dir = (global_position - source_pos).normalized()
		knockback_velocity = knockback_dir * knockback_strength
		if particles:
			particles.rotation = knockback_dir.angle() + PI
			particles.emitting = true

	flash_hurt_effect()
	shake_camera()
	start_invulnerability()

func start_invulnerability(blink = true):
	is_invulnerable = true
	var blink_timer = 0.0
	var duration = invulnerability_time
	while blink_timer < duration and blink:
		animated_sprite_2d.visible = !animated_sprite_2d.visible
		await get_tree().create_timer(0.1).timeout
		blink_timer += 0.1
	animated_sprite_2d.visible = true
	is_invulnerable = false

func flash_hurt_effect():
	modulate = Color(0.7, 0, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, invulnerability_time/2)

func shake_camera():
	var camera = find_child("Camera2D")
	if camera:
		var original_offset = camera.offset
		var shake_strength = 10.0
		for i in range(10):
			camera.offset = original_offset + Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
			await get_tree().create_timer(0.02).timeout
		camera.offset = original_offset

func start_attack():
	is_attacking = true
	AudioManager.play_sfx("woosh", 0.1)
	
	var mouse_pos = get_global_mouse_position()
	var attack_vector = (mouse_pos - global_position)
	var attack_dir = attack_vector.normalized()
	knockback_velocity = -attack_dir * recoil_strength

	weapon_pivot.look_at(mouse_pos)
	play_attack_animation(attack_vector)
	
	await get_tree().create_timer(0.2).timeout
	
	var bodies = attack_area.get_overlapping_bodies()
	var is_critical = randf() <= crit_chance
	var final_damage = damage
	if is_critical: final_damage *= crit_multiplier
	
	var hit_count = 0
	for body in bodies:
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			body.take_damage(final_damage, global_position, is_critical)
			hit_count += 1
	
	if is_critical and hit_count > 0:
		freeze_frame(0.01, 0.15)
		AudioManager.play_sfx("crit", 0.1)
	elif hit_count > 1:
		freeze_frame(0.001, 0.1)
		AudioManager.play_sfx("crit", 0.1)

func freeze_frame(time_scale: float, duration: float):
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func play_attack_animation(diff: Vector2):
	if abs(diff.y) > abs(diff.x):
		if diff.y < 0: play_anim("attack_up")
		else: play_anim("attack_down")
	else:
		play_anim("attack_side")
		animated_sprite_2d.flip_h = (diff.x < 0)

func play_anim(anim_name: String):
	if animated_sprite_2d.sprite_frames and animated_sprite_2d.sprite_frames.has_animation(anim_name):
		animated_sprite_2d.play(anim_name)

func _on_animation_finished():
	if animated_sprite_2d.animation.begins_with("attack"):
		is_attacking = false

func die():
	if is_dead: return
	print("%s Died!" % [name])
	is_dead = true
	character_died.emit(self)
	
	visible = false
	set_physics_process(false)
	set_process_unhandled_input(false)
	
	if collision_shape_2d:
		collision_shape_2d.set_deferred("disabled", true)
	if collision_shape_2d_attack:
		collision_shape_2d_attack.set_deferred("disabled", true)

func receive_heal(amount: int):
	if is_dead: return # Dead characters shouldn't be healed
	
	hp = clamp(hp + amount, 0, max_hp)
	
	print("%s was healed for %d! HP: %d" % [name, amount, hp])
	health_changed.emit(hp, max_hp)
	
	modulate = Color(0, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.5)
	
	if vfx:
		vfx.visible = true
		vfx.frame = 0
		if vfx.sprite_frames.has_animation("heal"):
			vfx.play("heal")
			AudioManager.play_sfx("healing", 0.1, -10)
		else:
			vfx.play("default")

func reset_visuals():
	if vfx:
		vfx.visible = false
		vfx.stop()
	modulate = Color.WHITE
	if particles:
		particles.emitting = false
	knockback_velocity = Vector2.ZERO
