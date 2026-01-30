extends CanvasLayer

# --- SIGNALS ---
signal switch_requested(index)
signal skill_button_pressed
signal stats_requested

# --- REFERENCES ---
# New Wave HUD References
@onready var wave_hud_container = $MarginContainer2
@onready var wave_title_label = $MarginContainer2/VBoxContainer/WaveTitleLabel
@onready var wave_progress_bar = $MarginContainer2/VBoxContainer/WaveProgressBar

# Points HUD Reference (Top-Right)
@onready var points_hud_container = $MarginContainer3
@onready var points_label = $MarginContainer3/PointsPanel/InternalPadding/PointsLabel

# Banner References (Centered Pop-up)
@onready var wave_banner = $WaveBannerContainer
@onready var banner_label = $WaveBannerContainer/WaveBannerPanel/InternalPadding/BannerLabel

# Main Health HUD (Bottom Center)
@onready var main_health_bar = $HealthBar
@onready var main_health_label = $HealthBar/HealthLabel

# --- ABILITY HUD REFERENCES ---
@onready var p_skill = $P_Skill
@onready var p_bar = $P_Skill/TextureProgressBar
@onready var p_time = $P_Skill/TextureProgressBar/Time

@onready var s_skill = $S_Skill
@onready var s_bar = $S_Skill/TextureProgressBar
@onready var s_time = $S_Skill/TextureProgressBar/Time

# Cache textures to avoid repeated loading
var tex_dash = preload("res://assets/echoDeck/dash.png")
var tex_heal = preload("res://assets/echoDeck/heal.png")

@onready var cardContainers = [
	$MarginContainer/VBoxContainer/HBoxContainer1,
	$MarginContainer/VBoxContainer/HBoxContainer2,
	$MarginContainer/VBoxContainer/HBoxContainer3,
	$MarginContainer/VBoxContainer/HBoxContainer4
]

@onready var cards = [
	$MarginContainer/VBoxContainer/HBoxContainer1/PanelContainer1,
	$MarginContainer/VBoxContainer/HBoxContainer2/PanelContainer2,
	$MarginContainer/VBoxContainer/HBoxContainer3/PanelContainer3,
	$MarginContainer/VBoxContainer/HBoxContainer4/PanelContainer4
]

@onready var cooldown_bars = [
	$MarginContainer/VBoxContainer/HBoxContainer1/PanelContainer1/HBoxContainer/Control/TextureRect/TextureProgressBar,
	$MarginContainer/VBoxContainer/HBoxContainer2/PanelContainer2/HBoxContainer/Control/TextureRect/TextureProgressBar,
	$MarginContainer/VBoxContainer/HBoxContainer3/PanelContainer3/HBoxContainer/Control/TextureRect/TextureProgressBar,
	$MarginContainer/VBoxContainer/HBoxContainer4/PanelContainer4/HBoxContainer/Control/TextureRect/TextureProgressBar
]

@onready var cooldown_labels = [
	$MarginContainer/VBoxContainer/HBoxContainer1/PanelContainer1/HBoxContainer/Control/TextureRect/TextureProgressBar/Time,
	$MarginContainer/VBoxContainer/HBoxContainer2/PanelContainer2/HBoxContainer/Control/TextureRect/TextureProgressBar/Time,
	$MarginContainer/VBoxContainer/HBoxContainer3/PanelContainer3/HBoxContainer/Control/TextureRect/TextureProgressBar/Time,
	$MarginContainer/VBoxContainer/HBoxContainer4/PanelContainer4/HBoxContainer/Control/TextureRect/TextureProgressBar/Time
]

# --- SWITCH COOLDOWN ---
@export var switch_cooldown_duration: float = 1.5
var switch_timer: Timer
var current_active_index: int = 0 # Tracks the currently active character

var start_messages = [
	"BRACE YOURSELVES!",
	"THEY'RE COMING...",
	"SHOW NO MERCY!",
	"PREPARE FOR GLORY!",
	"THE ECHO AWAKENS..."
]

var clear_messages = [
	"SURVIVED!",
	"AREA SECURED!",
	"EXTERMINATED!",
	"ABSOLUTE VICTORY!",
	"ONE STEP CLOSER..."
]

@onready var pause_button = $MainMenu
@onready var pause_menu_layer = get_node_or_null("../pauseMenu")

var party_manager_ref = null
var wave_manager_ref = null
var is_endless_mode: bool = false
var total_enemies_this_wave: int = 0
var current_score: int = 0

func _ready():
	# 1. Find Managers
	party_manager_ref = get_tree().current_scene.find_child("party_manager", true, false)
	wave_manager_ref = get_tree().current_scene.find_child("WaveManager", true, false)
	
	# Determine Mode based on WaveManager presence
	is_endless_mode = (wave_manager_ref != null)
	
	# --- SETUP SWITCH TIMER ---
	switch_timer = Timer.new()
	switch_timer.one_shot = true
	switch_timer.wait_time = switch_cooldown_duration
	add_child(switch_timer)
	
	# 2. Setup Initial State
	if wave_banner: wave_banner.visible = false
	
	# Only show Wave and Points HUD if in Endless Mode
	if wave_hud_container:
		wave_hud_container.visible = is_endless_mode
	if points_hud_container:
		points_hud_container.visible = is_endless_mode
	
	# Setup Card Pivots for scaling ("lifting") from the center
	for card in cards:
		card.pivot_offset = card.size / 2
	
	# Wait for levels to finish instantiating characters
	await get_tree().process_frame
	refresh_party_ui()
	_update_points_display()

	# 3. Connect UI Signals
	for i in range(cards.size()):
		cards[i].gui_input.connect(_on_card_input.bind(i))
	
	if pause_button:
		pause_button.pressed.connect(_on_pause_pressed)

	if party_manager_ref:
		party_manager_ref.child_order_changed.connect(refresh_party_ui)

	# 4. Connect Wave Signals (Only for Endless)
	if is_endless_mode:
		wave_manager_ref.wave_started.connect(_on_wave_started)
		wave_manager_ref.wave_completed.connect(_on_wave_completed)

func _process(_delta: float) -> void:
	if is_endless_mode:
		update_wave_hud()
	
	# Update cooldown overlays for all party members
	_update_all_cooldowns()
	# Update highlights/lifting every frame to track state changes (like death)
	highlight_card(current_active_index)
	
	# NEW: Update Skill HUD
	_update_skill_hud()
	
	# Dynamic Health Updates
	var party_members = get_actual_characters()
	for i in range(party_members.size()):
		var member = party_members[i]
		update_character_health(i, member.hp, member.max_hp)

# --- NEW: SKILL HUD LOGIC ---

func _update_skill_hud():
	# RESET: Hide both slots every frame so they don't stay visible on the wrong character
	p_skill.visible = false
	s_skill.visible = false

	var party_members = get_actual_characters()
	if party_members.is_empty() or current_active_index >= party_members.size():
		return
		
	var active_char = party_members[current_active_index]
	var char_name = active_char.name.to_lower()
	
	# Logic based on your character specifications
	if "warrior" in char_name or "knight" in char_name:
		_setup_p_skill(active_char, "dash", tex_dash)
	elif "monk" in char_name:
		_setup_p_skill(active_char, "heal", tex_heal)
		_setup_s_skill(active_char, "dash", tex_dash)
	elif "goblin" in char_name:
		_setup_p_skill(active_char, "dash", tex_dash)

func _setup_p_skill(character: Character, skill_key: String, texture: Texture2D):
	p_skill.visible = true
	p_skill.texture = texture
	if character.has_method("get_skill_cooldown"):
		var cd_data = character.get_skill_cooldown(skill_key) # [current, max]
		p_bar.max_value = cd_data[1]
		p_bar.value = cd_data[0]
		
		if cd_data[0] > 0.05:
			p_time.visible = true
			p_time.text = "%0.1f" % cd_data[0]
		else:
			p_time.visible = false

func _setup_s_skill(character: Character, skill_key: String, texture: Texture2D):
	s_skill.visible = true
	s_skill.texture = texture
	if character.has_method("get_skill_cooldown"):
		var cd_data = character.get_skill_cooldown(skill_key) # [current, max]
		s_bar.max_value = cd_data[1]
		s_bar.value = cd_data[0]
		
		if cd_data[0] > 0.05:
			s_time.visible = true
			s_time.text = "%0.1f" % cd_data[0]
		else:
			s_time.visible = false

# --- COOLDOWN OVERLAY LOGIC ---

func _update_all_cooldowns():
	var party_members = get_actual_characters()
	for i in range(cards.size()):
		if i < party_members.size():
			var character = party_members[i]
			_update_card_cooldown_visual(i, character)

func _update_card_cooldown_visual(index: int, character: Character):
	var bar = cooldown_bars[index]
	var label = cooldown_labels[index]
	
	# Cooldown should NOT appear if the character is dead OR the active one
	if character.is_dead or index == current_active_index:
		bar.visible = false
		if label: label.visible = false
		return

	# 1. PRIORITY: Global Switch Cooldown
	if not switch_timer.is_stopped():
		bar.visible = true
		bar.max_value = switch_cooldown_duration
		bar.value = switch_timer.time_left
		if label:
			label.visible = true
			label.text = "%0.1f" % switch_timer.time_left
		return

	# 2. SECONDARY: Character Ability Cooldown
	var status = character.get_cooldown_status()
	var time_left = status[0]
	var max_time = status[1]
	
	if time_left > 0:
		bar.visible = true
		bar.max_value = max_time
		bar.value = time_left
		if label:
			label.visible = true
			label.text = "%0.1f" % time_left
	else:
		bar.visible = false
		if label:
			label.visible = false

# --- HIGHLIGHT & LIFT LOGIC (TARGETING CARDS) ---

func highlight_card(active_index: int):
	current_active_index = active_index
	var party_members = get_actual_characters()
	var switch_on_cooldown = not switch_timer.is_stopped()
	
	for i in range(cards.size()):
		if i < party_members.size() and i < cards.size():
			var char_node = party_members[i]
			var card_node = cards[i]
			
			# Internal Visual Node References
			var hbox = card_node.find_child("HBoxContainer", false, false)
			var vbox = card_node.find_child("VBoxContainer", true, false)
			var portrait = card_node.find_child("TextureRect", true, false)
			var name_label = card_node.find_child("Label", true, false)
			var hp_bar = card_node.find_child("ProgressBar", true, false)
			if not hp_bar: hp_bar = card_node.find_child("TextureProgressBar", true, false)
			
			card_node.pivot_offset = card_node.size / 2
			# Master modulate stays White so Cooldown UI is unaffected
			card_node.modulate = Color.WHITE
			
			# 1. DEAD STATE: Dim everything
			if char_node.is_dead:
				var col = Color(0.1, 0.1, 0.1, 0.8)
				_apply_self_modulate_to_visuals(hbox, vbox, portrait, name_label, hp_bar, col, col)
				card_node.scale = Vector2(1.0, 1.0)
				card_node.z_index = 0
			
			# 2. ACTIVE STATE: Glow background ONLY, keep portrait/label WHITE
			elif i == active_index:
				var glow_col = Color(2, 2, 2, 1.0)
				_apply_self_modulate_to_visuals(hbox, vbox, portrait, name_label, hp_bar, glow_col, Color.WHITE)
				card_node.scale = Vector2(1.15, 1.15)
				card_node.z_index = 10
				
			# 3. INACTIVE STATE: Normal look OR Cooldown Look
			else:
				var target_col = Color(1, 1, 1, 1)
				if switch_on_cooldown:
					target_col = Color(0.4, 0.4, 0.4, 0.9)
				
				_apply_self_modulate_to_visuals(hbox, vbox, portrait, name_label, hp_bar, target_col, target_col)
				card_node.scale = Vector2(1.0, 1.0)
				card_node.z_index = 0

func _apply_self_modulate_to_visuals(hbox, vbox, portrait, label, hp, bg_color: Color, content_color: Color):
	if hbox: hbox.self_modulate = bg_color
	if vbox: vbox.self_modulate = content_color
	if portrait: portrait.self_modulate = content_color
	if label: label.self_modulate = content_color
	if hp: hp.self_modulate = content_color

# --- POINTS LOGIC ---

func add_points(amount: int):
	if is_endless_mode and wave_manager_ref:
		if "score" in wave_manager_ref:
			wave_manager_ref.score += amount
	else:
		current_score += amount
		_update_points_display()

func _update_points_display():
	if points_label:
		points_label.text = "POINTS: %d" % current_score

# --- WAVE HUD LOGIC ---

func update_wave_hud():
	if wave_manager_ref:
		if "score" in wave_manager_ref:
			current_score = wave_manager_ref.score
			_update_points_display()

		if wave_progress_bar:
			var current_count = wave_manager_ref.enemies_alive
			if current_count > total_enemies_this_wave:
				total_enemies_this_wave = current_count
				wave_progress_bar.max_value = total_enemies_this_wave
			
			wave_progress_bar.value = current_count
			var display_wave = wave_manager_ref.current_wave
			if display_wave <= 0: display_wave = 1
			wave_title_label.text = "WAVE %d" % display_wave
			wave_progress_bar.modulate = Color(1.0, 0.2, 0.2)

# --- WAVE & BANNER LOGIC ---

func _on_wave_started(wave_num: int):
	total_enemies_this_wave = 0
	var msg = start_messages.pick_random()
	_play_banner_sequence("WAVE %d" % wave_num, msg, Color.ORANGE_RED)

func _on_wave_completed():
	if wave_manager_ref:
		var msg = clear_messages.pick_random()
		_play_simple_banner(msg, Color.GOLD)
		apply_noise_shake(0.4, 10.0)

# --- ANIMATIONS ---
func _play_banner_sequence(top_text: String, sub_text: String, banner_color: Color):
	if not wave_banner: return
	wave_banner.visible = true
	wave_banner.modulate = banner_color
	wave_banner.modulate.a = 0
	wave_banner.scale = Vector2(0.3, 0.3)
	wave_banner.pivot_offset = wave_banner.size / 2
	banner_label.text = top_text
	var intro = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(wave_banner, "modulate:a", 1.0, 0.4)
	intro.tween_property(wave_banner, "scale", Vector2(1.0, 1.0), 0.4)
	await get_tree().create_timer(1.0).timeout
	var punch = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	punch.tween_property(wave_banner, "scale", Vector2(1.2, 1.2), 0.1)
	punch.tween_callback(func(): banner_label.text = sub_text)
	punch.tween_property(wave_banner, "scale", Vector2(1.0, 1.0), 0.1)
	await get_tree().create_timer(1.5).timeout
	var fade = create_tween()
	fade.tween_property(wave_banner, "modulate:a", 0.0, 0.5)
	await fade.finished
	wave_banner.visible = false

func _play_simple_banner(text: String, banner_color: Color):
	if not wave_banner: return
	banner_label.text = text
	wave_banner.visible = true
	wave_banner.modulate = banner_color
	wave_banner.modulate.a = 0
	wave_banner.scale = Vector2(0.5, 0.5)
	wave_banner.pivot_offset = wave_banner.size / 2
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave_banner, "modulate:a", 1.0, 0.4)
	tween.tween_property(wave_banner, "scale", Vector2(1.0, 1.0), 0.4)
	await get_tree().create_timer(2.0).timeout
	var fade = create_tween()
	fade.tween_property(wave_banner, "modulate:a", 0.0, 0.5)
	await fade.finished
	wave_banner.visible = false

func apply_noise_shake(duration: float, intensity: float):
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	var tween = create_tween()
	for i in range(8):
		var shake_offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(camera, "offset", shake_offset, duration / 8.0)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.05)

# --- PARTY UI LOGIC ---

func get_actual_characters() -> Array:
	var valid_members = []
	if party_manager_ref:
		for child in party_manager_ref.get_children():
			if child is CharacterBody2D and "hp" in child:
				valid_members.append(child)
	return valid_members

func refresh_party_ui():
	var party_members = get_actual_characters()
	for i in range(cards.size()):
		if i < party_members.size():
			cardContainers[i].visible = true
			var member = party_members[i]
			update_character_health(i, member.hp, member.max_hp)
			var portrait = cardContainers[i].find_child("Portrait", true, false)
			if portrait and "portrait_img" in member:
				portrait.texture = member.portrait_img
		else:
			cardContainers[i].visible = false

func update_character_health(index: int, current_hp: int, max_hp: int):
	if index < 0 or index >= cards.size(): return
	var card_node = cards[index]
	var progress_bar = card_node.find_child("ProgressBar", true, false)
	if not progress_bar: progress_bar = card_node.find_child("TextureProgressBar", true, false)
	
	# Determine health color (High contrast)
	var percent = float(current_hp) / float(max_hp)
	var health_color = Color(0.2, 0.9, 0.2, 1.0) # Green
	
	if percent <= 0.25:
		health_color = Color(1.0, 0.1, 0.1, 1.0) # Red
	elif percent <= 0.50:
		health_color = Color(1.0, 0.8, 0.0, 1.0) # Yellow
	
	# 1. Update Main HUD if this is the ACTIVE character
	if index == current_active_index:
		if main_health_bar:
			main_health_bar.max_value = max_hp
			main_health_bar.value = current_hp
			if main_health_bar is TextureProgressBar:
				main_health_bar.tint_progress = health_color
			else:
				# Use self_modulate to prevent the label (child) from changing color
				main_health_bar.self_modulate = health_color
		
		if main_health_label:
			main_health_label.text = str(current_hp) + "/" + str(max_hp)
			main_health_label.modulate = Color.WHITE

	# 2. Update Card individual Health Bar
	if progress_bar:
		if progress_bar.name != "TextureProgressBar" or progress_bar.get_parent().name != "TextureRect":
			# Use alpha 0 for active character to keep spacing identical
			if index == current_active_index:
				progress_bar.modulate.a = 0
			else:
				progress_bar.modulate.a = 1
				progress_bar.max_value = max_hp
				progress_bar.value = current_hp
				
				if progress_bar is TextureProgressBar:
					progress_bar.tint_progress = health_color
				else:
					progress_bar.modulate = health_color

# --- INPUT ---

func _input(event):
	if not switch_timer.is_stopped(): return
	
	var party_members = get_actual_characters()
	var party_count = party_members.size()
	var req_index = -1
	
	if event.is_action_pressed("switch_1") and party_count >= 1: req_index = 0
	elif event.is_action_pressed("switch_2") and party_count >= 2: req_index = 1
	elif event.is_action_pressed("switch_3") and party_count >= 3: req_index = 2
	elif event.is_action_pressed("switch_4") and party_count >= 4: req_index = 3
	
	if req_index != -1 and req_index != current_active_index:
		var target_char = party_members[req_index]
		if not target_char.is_dead:
			switch_timer.start()
			emit_signal("switch_requested", req_index)
	
func _on_pause_pressed():
	if pause_menu_layer:
		pause_menu_layer._toggle_pause_state()

func _on_card_input(event: InputEvent, index: int):
	if not switch_timer.is_stopped(): return
	
	var party_members = get_actual_characters()
	if index >= party_members.size() or not (event is InputEventMouseButton and event.pressed): return
	
	if event.button_index == MOUSE_BUTTON_LEFT:
		if index != current_active_index:
			var target_char = party_members[index]
			if not target_char.is_dead:
				get_viewport().set_input_as_handled()
				switch_timer.start()
				emit_signal("switch_requested", index)
