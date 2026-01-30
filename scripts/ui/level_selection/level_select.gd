extends CanvasLayer

@export var level_button_scene: PackedScene
@export var levels: Array[LevelData] 
# Add the path to your Main Menu scene here
@export var main_menu_path: String = "res://scenes/ui/mainMenu.tscn"

@onready var back_button: Button = $Control/BackButton
@onready var grid: GridContainer = $ScrollContainer/GridContainer

func _ready():
	# Clear any dummy children used for testing
	for child in grid.get_children():
		child.queue_free()
	
	# Create a button for each level
	for level in levels:
		var btn = level_button_scene.instantiate()
		grid.add_child(btn)
		btn.setup(level)
		
	# Connect the Back Button signal
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed():
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file(main_menu_path)
