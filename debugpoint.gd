extends CharacterBody3D


var t : float = 0.0
func _physics_process(delta: float) -> void:
	t += delta
	velocity.y = 10*Input.get_axis("ui_up", "ui_down")
	velocity.x = 2*Input.get_axis("ui_left", "ui_right")
	move_and_slide()
