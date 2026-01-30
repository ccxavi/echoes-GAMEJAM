class_name WaveManager extends Node

# SIGNALS
signal wave_started(wave_number: int)
signal wave_completed

# CONFIGURATION
@export var spawn_points_container: Node2D
@export var time_between_waves: float = 5.0
@export var banner_prep_time: float = 2.5 # Time for banner animation before spawning

# --- ENEMY CONFIGURATION ---
@export var enemy_scenes: Array[PackedScene]
@export var enemy_costs: Array[int] = [1, 3]  # Cost to spawn (Budget)
@export var enemy_scores: Array[int] = [10, 50] # Points awarded on kill
@onready var enemy_container: Node2D = $"../enemies"

# DIFFICULTY SCALING
@export var initial_budget: int = 20
@export var budget_multiplier: float = 1.5
@export var hp_scaling_per_wave: int = 2
@export var damage_scaling_per_wave: int = 1

# STATE
var current_wave: int = 0
var enemies_alive: int = 0
var is_spawning: bool = false
var score: int = 0 # Tracks total score

func _ready():
	AudioManager.stop_music()
	AudioManager.play_music("higher_waves")
	
	# Initial delay before the very first wave starts
	await get_tree().create_timer(2.0).timeout
	start_next_wave()
	
func start_next_wave():
	current_wave += 1
	
	AudioManager.play_sfx("horn", 0, -10)
	
	# 1. Show the Banner
	wave_started.emit(current_wave)
	
	# 2. PREP PHASE: Wait for the UI banner to finish/peak before spawning
	await get_tree().create_timer(banner_prep_time).timeout
	
	var budget = float(initial_budget) * pow(budget_multiplier, current_wave - 1)
	
	print("--- WAVE %s STARTED (Budget: %d) ---" % [current_wave, int(budget)])
	spawn_wave(int(budget))

func spawn_wave(budget: int):
	is_spawning = true
	var spawn_points = spawn_points_container.get_children()
	
	while budget > 0:
		var index = randi() % enemy_scenes.size()
		var cost = enemy_costs[index]
		
		# Get the score value for this specific enemy type
		var score_value = 10
		if index < enemy_scores.size():
			score_value = enemy_scores[index]
		
		if cost > budget:
			if budget < _get_cheapest_cost():
				break
			continue
		
		var point = spawn_points.pick_random()
		var pos = point.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50))
		
		create_enemy(enemy_scenes[index], pos, score_value)
		budget -= cost
		
		await get_tree().create_timer(0.2).timeout
	
	is_spawning = false

func create_enemy(scene: PackedScene, pos: Vector2, points_worth: int):
	var enemy = scene.instantiate()
	enemy.global_position = pos
	
	# --- ADD TO GROUP ---
	enemy.add_to_group("enemy") 
	
	# --- SCALING ---
	if "max_hp" in enemy:
		enemy.max_hp += (current_wave * hp_scaling_per_wave)
		enemy.hp = enemy.max_hp
	if "damage" in enemy:
		enemy.damage += (current_wave * damage_scaling_per_wave)
	
	# --- CONNECTION LOGIC ---
	enemy.tree_exited.connect(_on_enemy_tree_exited)
	
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_killed.bind(points_worth))
	
	if enemy_container:
		enemy_container.call_deferred("add_child", enemy)
	else:
		get_tree().current_scene.call_deferred("add_child", enemy)
		
	enemies_alive += 1

func _on_enemy_killed(points: int):
	score += points
	print("Enemy Killed! +%d Points. Total Score: %d" % [points, score])

func _on_enemy_tree_exited():
	if not is_inside_tree(): return

	enemies_alive -= 1
	
	if enemies_alive <= 0 and not is_spawning:
		print("Wave Cleared!")
		# Show "SURVIVED" banner immediately
		wave_completed.emit()
		
		# Wait for the peaceful inter-wave period
		await get_tree().create_timer(time_between_waves).timeout
		start_next_wave()

func _get_cheapest_cost() -> int:
	var min_cost = 999
	for c in enemy_costs:
		if c < min_cost: min_cost = c
	return min_cost
