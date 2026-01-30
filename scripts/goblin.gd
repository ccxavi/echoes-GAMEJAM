extends Character

# --- CONFIGURATION ---
@export var fire_damage = 4
@export var damage_time = 4.0 # do fire_damage every 4 seconds

func _ready():
	super._ready()
	
	# override default stats
	speed = 400.0
	max_hp = 100
	defense = 3
	crit_chance = 0.5
	damage = 2
	
	hp = max_hp

func start_attack():
	# 1. Setup State
	is_attacking = true
	velocity = Vector2.ZERO 
	
	AudioManager.play_sfx("torch", 0.1)
	
	var mouse_pos = get_global_mouse_position()
	var diff = mouse_pos - global_position
	
	# 2. Rotate & Animate
	if weapon_pivot:
		weapon_pivot.look_at(mouse_pos)
		
	play_attack_animation(diff)
	
	# 3. Wait for impact frame
	await get_tree().create_timer(0.2).timeout
	
	# 4. FIRE ATTACK LOGIC
	var bodies = attack_area.get_overlapping_bodies()
	
	for body in bodies:
		if body.is_in_group("enemy"):
			# Matches the "apply_burn" method we need in Enemy.gd
			if body.has_method("apply_burn"):
				body.apply_burn(fire_damage, damage_time) 
				print("Applied Burn to ", body.name)
