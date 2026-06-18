extends Node3D
class_name Missile_thruster

@export var constant_thrust := false
@export var volume := 0.0
var time_since_last := 0
var off := false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$AudioStreamPlayer3D.volume_db = volume

func _physics_process(_delta: float) -> void:
	if constant_thrust and !off:
		_play_or_resume()
		return
	time_since_last += 1
	if !visible and time_since_last > 10:
		$AudioStreamPlayer3D.stop()

func animation_start() -> Error:
	return OK

func _randf_range_chose() -> float:
	return randi_range(2,10)

func how() -> void:
	off = false
	if time_since_last > randi_range(1, 30) and !visible:
		_play_or_resume()
		time_since_last = 0
	show()
	
	
func shutdown() -> void:
	$AudioStreamPlayer3D.stop()
	off = true
func _play_or_resume() -> void:
	if $AudioStreamPlayer3D.playing:
		return
	$AudioStreamPlayer3D.play()
