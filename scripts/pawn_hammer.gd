extends Enemy


func _ready():
	super._ready()
	
	max_hp = 30
	speed = 200
	damage = 10
	attack_cooldown = 1.0
	
	hp = max_hp
