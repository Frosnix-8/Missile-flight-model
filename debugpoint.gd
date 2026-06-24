extends CharacterBody3D
@export var disabled := true
var missile :PackedScene = load("res://geroteng_g_1.tscn")
var t : float = 0.0
func _physics_process(delta: float) -> void:
	t += delta
	var input := Input.get_axis("ui_up", "ui_down")
	if input and velocity.length() < 50:
		velocity.y += 1*input
	else:
		velocity.y /=1.5
		
	
	if !disabled:
		move_and_slide()
	
