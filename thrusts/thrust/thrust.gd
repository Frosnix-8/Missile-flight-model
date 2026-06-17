extends Node3D
class_name Missile_thruster
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


func animation_start() -> Error:
	$AnimatedSprite3D.play("default")
	$AnimatedSprite3D.speed_scale = _randf_range_chose()
	$AnimatedSprite3D2.play("default")
	$AnimatedSprite3D2.speed_scale = _randf_range_chose()
	return OK

func _randf_range_chose() -> float:
	return randf_range(0.4,1.4)

func how() -> void:
	show()
