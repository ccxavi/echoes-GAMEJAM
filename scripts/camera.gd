extends Camera2D

# The PartyManager will set this variable automatically
var target: Node2D = null 

@export var smooth_speed: float = 10.0

func _process(delta: float) -> void:
	if target != null:
		global_position = global_position.lerp(target.global_position, smooth_speed * delta)
