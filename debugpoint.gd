extends CharacterBody3D


var t : float = 0.0
func _physics_process(delta: float) -> void:
	t += delta
	velocity.y = 20*Input.get_axis("ui_up", "ui_down")
	velocity.x = 20*Input.get_axis("ui_left", "ui_right")
	move_and_slide()
