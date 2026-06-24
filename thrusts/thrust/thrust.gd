extends Node3D
class_name Missile_thruster
##NOTE: depracated
@export var constant_thrust := false
@export var volume := 0.0
var time_since_last := 0
var off := false
var hidden := false

# Called when the node enters the scene tree for the first time.
func animation_start() -> Error:
	return OK

func ide() -> void:
	if !hidden:
		hide()
		hidden = true

func how() -> void:
	if hidden:
		show()
		hidden = false
	
	
func shutdown() -> void:

	off = true
