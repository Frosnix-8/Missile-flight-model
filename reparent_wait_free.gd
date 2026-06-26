extends Node3D

@export var reparent_to_root : bool = true
##When reparented, this node is no longer handled by the previous script. This built in timer removes it automatically.
@export var time := 2.0
var go := false

func _physics_process(delta: float) -> void:
	if !go:
		return
	time -= delta
	if time < 0:
		queue_free()

func on_begin_countdown(new_parent : Node3D) -> void:
	
	call_deferred("reparent",get_tree().current_scene if reparent_to_root or !new_parent else new_parent, true)
	go = true
