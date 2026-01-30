extends CanvasLayer

# --- REFERENCES ---
@onready var title_label: Label = $CenterContainer/MasterVBox/Label 

# Container References
@onready var vbox_stats: VBoxContainer = $CenterContainer/MasterVBox/VBoxContainer1
@onready var vbox_buttons: VBoxContainer = $CenterContainer/MasterVBox/VBoxContainer2

# Button References
@onready var restart: Button = $CenterContainer/MasterVBox/VBoxContainer2/Restart
@onready var exit: Button = $CenterContainer/MasterVBox/VBoxContainer2/Exit

# Label References
@onready var wave_label: Label = $CenterContainer/MasterVBox/VBoxContainer1/WaveLabel
@onready var score_label: Label = $CenterContainer/MasterVBox/VBoxContainer1/ScoreLabel

@export var main_menu_path: String = "res://scenes/ui/mainMenu.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	restart.pressed.connect(_on_restart_pressed)
	exit.pressed.connect(_on_exit_pressed)
	
	_auto_detect_mode()
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _auto_detect_mode() -> void:
	var wave_manager = get_tree().current_scene.find_child("WaveManager", true, false)
	
	if wave_manager:
		# ENDLESS MODE
		title_label.text = "GAME OVER!"
		vbox_stats.visible = true # This will push VBoxContainer2 down
		_set_endless_stats(wave_manager.current_wave, wave_manager.score)
	else:
		# STORY MODE
		title_label.text = "YOU LOST!"
		vbox_stats.visible = false # This will pull VBoxContainer2 up

func _set_endless_stats(final_wave: int, final_score: int) -> void:
	if wave_label: wave_label.text = "Final Wave: %d" % final_wave
	if score_label: score_label.text = "Final Score: %d" % final_score

# --- BUTTON FUNCTIONS ---
func _on_restart_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _on_exit_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(main_menu_path)
