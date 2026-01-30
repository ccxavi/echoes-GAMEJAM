extends Button

@onready var level_num_lbl = $MarginContainer/VBoxContainer/LevelNumber
@onready var level_title_lbl = $MarginContainer/VBoxContainer/LevelTitle
@onready var lock_icon = $LockIcon
@onready var preview_image = $PreviewImage

var level_data: LevelData

func _ready():
	pivot_offset = size / 2
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)
	pressed.connect(_on_pressed)

func setup(data: LevelData):
	level_data = data
	
	# Set text
	level_num_lbl.text = str(data.level_id).pad_zeros(2) 
	level_title_lbl.text = data.level_name
	
	if data.texture:
		preview_image.texture = data.texture
		# Ensure we start with a slight dim so white text pops, or pure white if you prefer
		preview_image.modulate = Color(0.8, 0.8, 0.8) 
	
	# Handle Locked Status
	if data.locked:
		disabled = true
		lock_icon.visible = true
		modulate = Color(0.5, 0.5, 0.5, 1.0) 
	else:
		disabled = false
		lock_icon.visible = false
		modulate = Color.WHITE

func _on_pressed():
	if level_data and not disabled:
		AudioManager.play_sfx("click")
		
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.1)
		await tween.finished
		
		get_tree().change_scene_to_file(level_data.scene_path)

func _on_hover():
	if disabled: return
	
	# 1. Scale Button Up
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true) # Run these tweens at the same time
	tween.tween_property(self, "scale", Vector2(1.02, 1.02), 0.2)
	
	# 2. Darken the Image (Dim it to 40% brightness)
	tween.tween_property(preview_image, "modulate", Color(0.6, 0.6, 0.6), 0.2)

func _on_exit():
	if disabled: return
	
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	
	# 1. Scale Back Down
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	# 2. Restore Image Brightness (Back to default 0.8 or 1.0)
	tween.tween_property(preview_image, "modulate", Color(0.8, 0.8, 0.8), 0.2)
