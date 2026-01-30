extends Character

# --- CHARGE ATTACK VARIABLES ---
var is_charging_attack = false
var charge_start_time = 0.0
const CHARGE_THRESHOLD = 0.35      # How long to hold before it counts as a Charge
const MAX_CHARGE_TIME = 1.2        # Time to reach max damage
const CHARGE_WALK_SPEED = 0.4      # Movement speed multiplier while aiming
const LUNGE_SPEED = 1000.0         # How fast the lunge travels
const LUNGE_DAMAGE_MULT = 2.5      # Damage multiplier for the charge

# Visuals for charging
var charge_tween: Tween

func _ready():
	super._ready()
	
	# Override default stats for Lancer class
	speed = 310.0
	max_hp = 100
	defense = 5
	damage = 8        # Base poke damage
	crit_chance = 0.25
	
	hp = max_hp
	
	# Lancer specific: slightly longer reach
	# We can scale the weapon pivot to simulate a longer spear
	weapon_pivot.scale = Vector2(1.3, 1.3)

# --- INPUT OVERRIDE ---
# We override the base input to detect HOLD vs TAP
func _unhandled_input(event):
	if is_attacking or is_dead: return

	if event.is_action_pressed("attack"):
		start_charging()
	
	if event.is_action_released("attack"):
		release_charge()

# --- PHYSICS OVERRIDE ---
func _physics_process(delta):
	# If we are charging, we override the movement logic to be slower
	if is_charging_attack:
		handle_charging_movement(delta)
	else:
		# If not charging, use the standard movement from player.gd
		super._physics_process(delta)

# --- DAMAGE OVERRIDE (INTERRUPTION LOGIC) ---
func take_damage(amount: int, source_pos: Vector2, attacker: Node = null):
	# If we are currently charging up, we get interrupted!
	if is_charging_attack:
		cancel_charge()
		# Optional: Add "Charge Interrupted!" UI feedback here
	
	# Pass the actual damage calculation to the base class
	super.take_damage(amount, source_pos, attacker)

# --- CHARGE LOGIC ---
func start_charging():
	is_charging_attack = true
	charge_start_time = Time.get_ticks_msec() / 1000.0
	
	# Visual: Flash/Tint BLUE to indicate power build up
	# Color(0.5, 0.8, 1) is a light icy blue
	modulate = Color(0.5, 0.8, 1) 
	
	# Optional: Start a tween to visualize "charging up"
	if charge_tween: charge_tween.kill()
	charge_tween = create_tween()
	# Tween towards a deep, glowing blue
	charge_tween.tween_property(self, "modulate", Color(0.2, 0.2, 3.0), MAX_CHARGE_TIME)

# Fixed: Added underscore to _delta to remove warning
func handle_charging_movement(_delta):
	# Allow movement but slower (aiming)
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * (speed * CHARGE_WALK_SPEED)
	
	# Force character to face mouse while charging (strafing)
	var mouse_pos = get_global_mouse_position()
	animated_sprite_2d.flip_h = (mouse_pos.x < global_position.x)
	weapon_pivot.look_at(mouse_pos) # Aim the spear
	
	# Play run or idle anim slowly
	if direction != Vector2.ZERO:
		play_anim("run")
		animated_sprite_2d.speed_scale = 0.5
	else:
		play_anim("idle")
		animated_sprite_2d.speed_scale = 1.0

	move_and_slide()

func cancel_charge():
	is_charging_attack = false
	if charge_tween: charge_tween.kill()
	modulate = Color.WHITE
	animated_sprite_2d.speed_scale = 1.0

func release_charge():
	if not is_charging_attack: return
	
	var hold_duration = (Time.get_ticks_msec() / 1000.0) - charge_start_time
	is_charging_attack = false
	
	# Reset visuals
	if charge_tween: charge_tween.kill()
	modulate = Color.WHITE
	animated_sprite_2d.speed_scale = 1.0
	
	if hold_duration < CHARGE_THRESHOLD:
		# If tap was quick, just do normal attack from Base Class
		super.start_attack()
	else:
		# If held long enough, perform LUNGE
		perform_lunge_attack(hold_duration)

# --- THE SPECIAL ATTACK ---
func perform_lunge_attack(charge_time):
	is_attacking = true
	AudioManager.play_sfx("woosh", 0.1, 5.0) # Higher pitch woosh
	
	var mouse_pos = get_global_mouse_position()
	var attack_vector = (mouse_pos - global_position).normalized()
	
	# 1. LOCK ROTATION AND LAUNCH PLAYER
	weapon_pivot.look_at(mouse_pos)
	play_attack_animation(attack_vector) # Use 8-dir logic
	
	# Calculate power based on charge time (clamped to max)
	var power_ratio = min(charge_time / MAX_CHARGE_TIME, 1.0)
	var final_damage = damage * LUNGE_DAMAGE_MULT * (0.5 + (power_ratio * 0.5))
	
	# "Recoil" in base class pushes backwards. Here we hijack it to push FORWARD.
	# We set knockback_decay very high so we stop abruptly after the thrust.
	knockback_velocity = attack_vector * LUNGE_SPEED
	
	# 2. ENABLE HITBOX FOR DURATION OF DASH
	
	# Visual particles for the dash
	if particles:
		particles.emitting = true
		particles.amount = 20 # More particles
		particles.color = Color(0, 0.5, 1) # Blue particles
	
	var dash_duration = 0.25
	var timer = 0.0
	
	# We assume the lunge hits everything in the path continuously
	var enemies_hit = []
	
	while timer < dash_duration:
		# Manually check for collisions during the slide
		var bodies = attack_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("enemy") and body not in enemies_hit and body.has_method("take_damage"):
				# Calculate Crit
				var is_critical = randf() <= crit_chance
				var actual_damage = final_damage * crit_multiplier if is_critical else final_damage
				
				body.take_damage(actual_damage, global_position, is_critical)
				enemies_hit.append(body) # Don't hit the same enemy twice in one lunge
				
				# Impact visuals
				AudioManager.play_sfx("crit" if is_critical else "hurt", 0.1)
				freeze_frame(0.05, 0.1) # Heavy hit feel
		
		timer += get_process_delta_time()
		await get_tree().process_frame
		
	# 3. STOP
	knockback_velocity = Vector2.ZERO
	is_attacking = false
	if particles: 
		particles.emitting = false
		particles.color = Color.WHITE # Reset particle color

# Override the base function to use 8-Directional Logic (Preserved from your code)
func play_attack_animation(diff: Vector2):
	var angle = diff.angle()
	var snapped_angle = snapped(angle, PI / 4.0)
	var octant = int(round(snapped_angle / (PI / 4.0)))
	
	match octant:
		0: # Right
			play_anim("attack_side")
			animated_sprite_2d.flip_h = false
		1: # Down-Right
			play_anim("attack_down_diag")
			animated_sprite_2d.flip_h = false
		2: # Down
			play_anim("attack_down")
		3: # Down-Left
			play_anim("attack_down_diag")
			animated_sprite_2d.flip_h = true 
		4, -4: # Left
			play_anim("attack_side")
			animated_sprite_2d.flip_h = true 
		-3: # Up-Left
			play_anim("attack_up_diag")
			animated_sprite_2d.flip_h = true 
		-2: # Up
			play_anim("attack_up")
		-1: # Up-Right
			play_anim("attack_up_diag")
			animated_sprite_2d.flip_h = false
