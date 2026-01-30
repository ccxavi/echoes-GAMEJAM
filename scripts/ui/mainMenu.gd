extends Control

func _ready() -> void:
	AudioManager.play_music("main_menu", -10.0, true)

# --- BUTTON HANDLERS ---

func _on_story_pressed() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://scenes/ui/level_selection.tscn")


func _on_endless_pressed() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://scenes/levels/infinite.tscn")
