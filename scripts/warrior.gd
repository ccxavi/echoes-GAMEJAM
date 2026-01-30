extends Character

var attack_count: int = 0
var combo_queued: bool = false

func _ready():
	super._ready()
	
	# override default stats
	speed = 260.0
	max_hp = 100
	defense = 7
	crit_chance = 0.3
	damage = 9
	
	hp = max_hp

# 1. INPUT HANDLING (Queue Logic)
func _unhandled_input(event):
	# Handle Attack Inputs LOCALLY to support queuing
	if event.is_action_pressed("attack"):
		if is_attacking:
			# If we are already doing Slash 1, queue Slash 2
			if attack_count == 1:
				combo_queued = true
		else:
			# Not attacking? Start Slash 1
			perform_slash(1)
			
	# Call parent for things like Dash (will be ignored if is_attacking is true)
	super._unhandled_input(event)

# 2. ATTACK LOGIC
func perform_slash(hit_index: int):
	is_attacking = true
	attack_count = hit_index
	combo_queued = false # Consumed the queue
	
	# A. Aim & Visuals
	var mouse_pos = get_global_mouse_position()
	var attack_vector = (mouse_pos - global_position)
	weapon_pivot.look_at(mouse_pos)
	
	# Determine Animation Name (attack_side, attack_side_2, etc.)
	var suffix = ""
	if hit_index == 2: suffix = "_2"
	
	# Helper from parent to calculate direction (Side/Up/Down)
	# We append our suffix manually
	if abs(attack_vector.y) > abs(attack_vector.x):
		if attack_vector.y < 0: play_anim("attack_up" + suffix)
		else: play_anim("attack_down" + suffix)
	else:
		play_anim("attack_side" + suffix)
		animated_sprite_2d.flip_h = (attack_vector.x < 0)

	# B. Audio
	AudioManager.play_sfx("woosh", 0.1, 0)

	# C. Recoil (Push player back slightly)
	knockback_velocity = -attack_vector.normalized() * (recoil_strength * 0.5)

	# D. Damage (Delayed slightly to match sword swing)
	await get_tree().create_timer(0.15).timeout
	deal_damage_area(hit_index)

func _on_animation_finished():
	# Check if the finished animation was an attack
	if animated_sprite_2d.animation.begins_with("attack"):
		
		if attack_count == 1 and combo_queued:
			# Player clicked during the first animation -> Chain to Attack 2
			perform_slash(2)
		else:
			# No combo queued OR we just finished Attack 2 -> Return to normal
			is_attacking = false
			attack_count = 0
			combo_queued = false
			velocity = Vector2.ZERO # Stop recoil sliding

func deal_damage_area(hit_index: int):
	# Safety check: ensure we didn't die or get interrupted during the 0.15s wait
	if not is_attacking and hit_index == 1: return 
	
	var bodies = attack_area.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			# 2nd hit deals 50% more damage
			var final_dmg = damage * (1.5 if hit_index == 2 else 1.0)
			
			# Check Crit
			var is_crit = randf() <= crit_chance
			if is_crit: final_dmg *= crit_multiplier
			
			body.take_damage(final_dmg, global_position, is_crit)
