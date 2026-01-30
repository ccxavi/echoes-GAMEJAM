extends Character

@export var heal_amount = 30

func _ready():
	# Update the cooldown duration from the base Character class
	ability_cooldown_duration = 5.0
	
	super._ready()
	
	# override default stats
	speed = 400.0
	max_hp = 100
	defense = 3
	crit_chance = 0.0
	damage = 0
	
	hp = max_hp

func start_attack():
	# Check if the ability_timer is running instead of a local boolean
	if not ability_timer.is_stopped() or is_attacking:
		return
	
	AudioManager.play_sfx("heal", 0.1, -15)

	is_attacking = true
	velocity = Vector2.ZERO
	
	# 1. FACE MOUSE
	var mouse_pos = get_global_mouse_position()
	animated_sprite_2d.flip_h = (mouse_pos.x < global_position.x)

	# 2. PLAY ANIMATION
	play_anim("heal")
	
	# 3. WAIT FOR CAST POINT
	await get_tree().create_timer(0.2).timeout
	
	perform_heal()

func perform_heal():
	print("Monk cast Heal!")

	# 1. SEND TO MANAGER
	# We assume the parent of the Monk is the PartyManager
	var manager = get_parent()
	if manager.has_method("queue_heal_for_next_switch"):
		manager.queue_heal_for_next_switch(heal_amount)
	
	# 2. START COOLDOWN
	# This starts the timer that echoDeck.gd is watching
	ability_timer.start()

func _on_animation_finished():
	if animated_sprite_2d.animation == "heal":
		is_attacking = false
