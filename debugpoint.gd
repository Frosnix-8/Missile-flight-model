extends CharacterBody3D

var missile :PackedScene = load("res://geroteng_g_1.tscn")
var t : float = 0.0
func _physics_process(delta: float) -> void:
	t += delta
	var input := Input.get_axis("ui_up", "ui_down")
	if input and velocity.length() < 50:
		velocity.y += 1*input
	else:
		velocity.y /=1
		
	
	
	move_and_slide()
	if Input.is_action_just_pressed("ui_accept"):
		for x in range(10):
			var new_missile : Missile_Guided = missile.instantiate()
			new_missile.target = self
			get_parent().add_child(new_missile)
			new_missile.global_position = Vector3(randi_range(-1000,1000),randi_range(-1000,1000),randi_range(-1000,1000))
