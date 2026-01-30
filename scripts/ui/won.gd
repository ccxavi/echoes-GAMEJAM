extends CanvasLayer

@onready var quit: Button = $CenterContainer/MasterVBox/VBoxContainer/Quit

@export var main_menu_path: String = "res://scenes/ui/mainMenu.tscn"

func _ready() -> void:
	# CRITICAL: Allows this UI to work while the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect the buttons
	quit.pressed.connect(_on_exit_pressed)
	
	# Optional: Show cursor if it was hidden
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
func _on_exit_pressed() -> void:
	# 1. Reset Game State
	get_tree().paused = false
	Engine.time_scale = 1.0
	
	if AudioManager: AudioManager.play_sfx("click")
	
	# 2. Go to Main Menu
	get_tree().change_scene_to_file(main_menu_path)
