extends Node2D

signal party_wiped

# --- VARIABLES ---
var characters: Array = []
var active_character_index: int = 0
var is_switching = false 
var can_switch = true
const SWITCH_COOLDOWN = 1.0 
const onCharacterSwitchSpeed = 0.3
var queued_heal_amount: int = 0 

# --- REFERENCES ---
@onready var camera: Camera2D = %Camera2D
@onready var switch_vfx: AnimatedSprite2D = $switch_vfx
@export var echo_deck_ui: CanvasLayer 
@export var game_over_scene: PackedScene

func _ready():
	switch_vfx.visible = false 
	
	# 1. DYNAMIC CHARACTER DETECTION
	# We wait one frame to ensure the level has finished instantiating the characters
	await get_tree().process_frame
	
	# Find the node named 'party_manager' in the current level
	var party_node = get_tree().current_scene.find_child("party_manager", true, false)
	
	if party_node:
		# Clear array to avoid duplicates on scene reload
		characters.clear()
		
		# Fill the characters array from the party_manager children
		for child in party_node.get_children():
			if child is CharacterBody2D:
				characters.append(child)
				if child.has_signal("character_died"):
					child.character_died.connect(_on_character_died)
	
		for i in range(characters.size()):
			var char_node = characters[i]
			
			# Connect Health Signal
			if char_node.has_signal("health_changed"):
				# Bind the index so the UI knows which card to update
				char_node.health_changed.connect(_on_health_update_received.bind(i))
				
				# Send initial HP to UI immediately
				if echo_deck_ui and "hp" in char_node:
					echo_deck_ui.update_character_health(i, char_node.hp, char_node.max_hp)
			
			# Connect Ability Signal
			if char_node.has_signal("ability_used"):
				char_node.ability_used.connect(_on_char_ability_used)

			# Set initial active state (Warrior at index 0 starts active)
			if i == 0: 
				activate_character(char_node)
			else: 
				deactivate_character(char_node)
	else:
		print("Error: 'party_manager' node not found in this scene!")

	# 2. SETUP UI CONNECTIONS
	if echo_deck_ui:
		# Connect UI signals if not already connected
		if not echo_deck_ui.switch_requested.is_connected(_on_ui_switch_requested):
			echo_deck_ui.switch_requested.connect(_on_ui_switch_requested)
		
		if not echo_deck_ui.skill_button_pressed.is_connected(_on_ui_skill_pressed):
			echo_deck_ui.skill_button_pressed.connect(_on_ui_skill_pressed)
		
		if not echo_deck_ui.stats_requested.is_connected(_on_ui_stats_requested):
			echo_deck_ui.stats_requested.connect(_on_ui_stats_requested)
		
		# Sync the UI visuals
		echo_deck_ui.highlight_card(0)
		if characters.size() > 0:
			update_ui_button_state(characters[0])

# --- UI HANDLERS ---
func _on_ui_stats_requested():
	# Sends current party array to the UI for the Tab/Stats screen
	echo_deck_ui.show_stats_screen(characters)

func _on_ui_switch_requested(target_index):
	try_switch_to_index(target_index)

func _on_ui_skill_pressed():
	if active_character_index < characters.size():
		var active_char = characters[active_character_index]
		if active_char.has_method("try_use_special_ability"):
			active_char.try_use_special_ability()

func _on_health_update_received(current_hp, max_hp, index):
	if echo_deck_ui: 
		echo_deck_ui.update_character_health(index, current_hp, max_hp)

func _on_char_ability_used(_time, max_time):
	if echo_deck_ui and echo_deck_ui.has_method("trigger_cooldown_animation"):
		echo_deck_ui.trigger_cooldown_animation(max_time)

# --- INPUT HANDLING ---
func _unhandled_input(event):
	# Only allow switching to indices that actually exist in the current level
	if event.is_action_pressed("switch_1") and characters.size() >= 1: try_switch_to_index(0)
	elif event.is_action_pressed("switch_2") and characters.size() >= 2: try_switch_to_index(1)
	elif event.is_action_pressed("switch_3") and characters.size() >= 3: try_switch_to_index(2)
	elif event.is_action_pressed("switch_4") and characters.size() >= 4: try_switch_to_index(3)

# --- SWITCHING LOGIC ---
func try_switch_to_index(target_index: int):
	if is_switching or not can_switch: return
	if target_index >= characters.size() or target_index == active_character_index: return
	
	if characters[target_index].is_dead:
		print("Character is dead, cannot switch.")
		AudioManager.play_sfx("unable")
		return
		
	perform_switch(target_index)

func perform_switch(target_index: int):
	is_switching = true 
	can_switch = false 
	
	var old_char = characters[active_character_index]
	
	# Audio Feedback
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("switch", 0.1)
	
	play_vfx(old_char.global_position)
	if old_char.has_node("main_sprite"): 
		old_char.get_node("main_sprite").visible = false
	
	# Update active reference
	active_character_index = target_index
	var new_char = characters[active_character_index]
	
	# Sync UI
	if echo_deck_ui:
		echo_deck_ui.highlight_card(active_character_index)
		update_ui_button_state(new_char)
	
	# Physical Swap
	new_char.global_position = old_char.global_position
	deactivate_character(old_char)
	activate_character(new_char)
	
	# Invulnerability on entry
	if new_char.has_method("start_invulnerability"):
		new_char.start_invulnerability()
	
	# Visual Switch Speed Adjustment
	var duration = 0.5 
	if switch_vfx.sprite_frames.has_animation("switch"):
		var frames = switch_vfx.sprite_frames.get_frame_count("switch")
		var fps = switch_vfx.sprite_frames.get_animation_speed("switch")
		if fps > 0: duration = frames / fps
		
	var original_speed = new_char.speed
	new_char.speed = original_speed * onCharacterSwitchSpeed
	
	if new_char.has_node("main_sprite"):
		new_char.get_node("main_sprite").visible = false
		await get_tree().create_timer(duration * 0.5).timeout
		new_char.get_node("main_sprite").visible = true
	
	new_char.speed = original_speed
	switch_vfx.visible = false
	
	# Apply any heals that were waiting for this character to spawn
	if queued_heal_amount > 0:
		await get_tree().create_timer(0.1).timeout
		if new_char.has_method("receive_heal"): 
			new_char.receive_heal(queued_heal_amount)
		queued_heal_amount = 0
	
	is_switching = false
	await get_tree().create_timer(SWITCH_COOLDOWN).timeout
	can_switch = true

func update_ui_button_state(char_node):
	if echo_deck_ui and char_node.has_method("get_cooldown_status"):
		var _status = char_node.get_cooldown_status() 

# --- DEATH & GAME OVER ---
func _on_character_died(dead_char_node):
	# 1. Identify if the ACTIVE character is the one who died
	var active_char_died = (dead_char_node == characters[active_character_index])
	
	var survivor_index = -1
	
	# 2. Search for ANY living character
	# We start checking from the "next" index to keep the rotation order natural,
	# but we loop through the ENTIRE list (size + 1) to ensure we check everyone.
	for i in range(1, characters.size() + 1):
		var check_index = (active_character_index + i) % characters.size()
		
		if not characters[check_index].is_dead:
			survivor_index = check_index
			break # Found a survivor!
	
	# 3. Decision Logic
	if survivor_index == -1:
		# No survivors found at all. Game Over.
		trigger_game_over()
		
	elif active_char_died:
		# The player currently in control died, so we MUST switch to the survivor.
		perform_switch(survivor_index)
		
	else:
		# A background character died, but the active player is still alive.
		# Do nothing (continue playing), just maybe print a log.
		print("A background character died. Active player remains.")

func trigger_game_over():
	# Emit the signal so the Level knows we lost!
	party_wiped.emit() 
	
	AudioManager.stop_music();
	
	Engine.time_scale = 0.1 
	can_switch = false
	
	await get_tree().create_timer(0.2, true).timeout
	get_tree().paused = true
	
	AudioManager.play_sfx("game_over")
	
	if game_over_scene:
		var game_over_instance = game_over_scene.instantiate()
		get_tree().current_scene.add_child(game_over_instance)

# --- UTILITY ---
func play_vfx(pos):
	switch_vfx.global_position = pos
	switch_vfx.visible = true
	switch_vfx.play("switch")
	switch_vfx.frame = 0 

func activate_character(char_node):
	if char_node.is_dead: return
	if char_node.has_method("reset_visuals"):
		char_node.reset_visuals()
		
	char_node.visible = true
	if char_node.has_node("main_sprite"): 
		char_node.get_node("main_sprite").visible = true
	
	char_node.set_process_unhandled_input(true)
	char_node.set_physics_process(true)
	char_node.process_mode = Node.PROCESS_MODE_INHERIT
	if camera: 
		camera.target = char_node

func deactivate_character(char_node):
	if char_node.has_method("reset_visuals"):
		char_node.reset_visuals()

	char_node.visible = false
	char_node.set_process_unhandled_input(false)
	char_node.set_physics_process(false)
	char_node.process_mode = Node.PROCESS_MODE_DISABLED

func queue_heal_for_next_switch(amount: int):
	queued_heal_amount = amount
