extends RigidBody3D
class_name Missile_Guided
static var instance_count := 0
static var RCS_instance_count := 0
static var cached_camera : Camera3D
static var cached_camera_frame : int = 0
var RCS_this_id := 0
var this_id := 0
@export_category("Debug")
@export var show_all_thrusters := false
@export var unlimited_fuel := false
@export var disable_strafe := false
@export var enable_rear_thrust := false
@export_category("Chase Modes")
enum chasemodes {
	PURSUIT , ##Goes after the target's current position
	PROPORTIONAL_NAVIGATION ##Flies such that the missile's bearing stays constant relative to the target until impact. Switches to Pursuit if not facing the target
	}
##How the missile will pursue targets. 
@export var chase_mode : chasemodes = chasemodes.PURSUIT
##aggressivity of PN corrections
@export var pn_gain: float = 4.0

@onready var Thrust_forward : Missile_thruster = $ThrustEffect
@onready var Thrust_right : Missile_thruster = $ThrustEffect6
@onready var Thrust_left : Missile_thruster = $ThrustEffect7
@onready var Thrust_up : Missile_thruster = $ThrustEffect5
@onready var Thrust_down : Missile_thruster = $ThrustEffect2
@onready var Thrust_left_aft : Missile_thruster = $ThrustEffect8
@onready var Thrust_right_aft : Missile_thruster = $ThrustEffect9
@onready var Thrust_up_aft : Missile_thruster = $ThrustEffect4
@onready var Thrust_down_aft : Missile_thruster = $ThrustEffect3

@onready var collision_check : ShapeCast3D = $impactcheck
@onready var audio_main_thrust : AudioStreamPlayer3D = $MAINTHRUST
@onready var audio_RCS : AudioStreamPlayer3D = $RCS

##empty? missile can no longer maneuver in vacuum
var thrust_time := 10.0

var all_thrusters : Array[Missile_thruster]

@export_category("Missile specifications")
##Speed when launched from ship. 
@export var launch_speed: float = 2.0
@export var max_straight_line_speed : float = 1000
##agility of the missile, IE the strength with which it can thrust sideways. 
##by definition, agility is the max sideways acceleration of the missile.
@export var linear_agility := 75.0
##forward acceleration of the missile.
@export var forward_acceleration := 120.0
##angular agility of the missile, the max rotation it can do in a second.
@export var angular_agility :float= PI
@export var explode_on_fuel_loss := false

@export_category("Visual Parameters")
@export var hide_RCS := false

@export_category("Audio Parameters")
@export var main_thrust_volume_db := 0.0
@export var thrust_volume_db := 0.0
@export var explosion_volume_db := -19
@export var master_effect_volume_db := 0.0
@export_category("Target")
@export var target : Node3D

var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var is_facing_target :bool= false
var no_target := true
var hit_target := false

var tick_avionics := 0
var ratio_calculate_avionics := 1
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	instance_count += 1
	this_id = instance_count
	if !hide_RCS:
		RCS_instance_count += 1
		RCS_this_id = RCS_instance_count
	all_thrusters.append(Thrust_forward)
	all_thrusters.append(Thrust_down)
	all_thrusters.append(Thrust_down_aft)
	all_thrusters.append(Thrust_left)
	all_thrusters.append(Thrust_left_aft)
	all_thrusters.append(Thrust_right)
	all_thrusters.append(Thrust_right_aft)
	all_thrusters.append(Thrust_up)
	all_thrusters.append(Thrust_up_aft)
	for x in all_thrusters:
		if x.animation_start() != Error.OK:
			push_error(self, " failed to start thruster animation on ", x)
		if !show_all_thrusters:
			x.ide()
	audio_RCS.volume_db = thrust_volume_db
	audio_main_thrust.volume_db = main_thrust_volume_db
	$explosion.volume_db = explosion_volume_db
	apply_central_impulse(basis * Vector3(0,0,-launch_speed))
	
	
	


func _physics_process(delta: float) -> void:
	tick_avionics += 1
	if tick_avionics % 15 == 0:
		compute_tick_avionics_ratio()
		allow_RCS()
	RCS_audio_queued = false
	thrust_time -= delta
	if (thrust_time <= 0 and !unlimited_fuel )or hit_target:
		for x in all_thrusters:
			x.queue_free()
		if explode_on_fuel_loss:
			missile_impact(null)
		else:
			set_physics_process(false)
			for x in get_children():
				if x is not MeshInstance3D or x is not VaporTrail:
					queue_free()
			await get_tree().create_timer(10).timeout
			queue_free()
		return
	if tick_avionics % ratio_calculate_avionics == 0:
		compute_target_position(delta)
		compute_thrust()
		compute_rotation_thrust()
	_rcs_audio()
	#print("missile has a velocity of ", linear_velocity.length())
	
	
	collision_check.target_position = collision_check.to_local(linear_velocity) * delta * 0.5
	
	
	
func compute_thrust() -> void:
	match chase_mode:
		chasemodes.PURSUIT:
			compute_strafe_thrust()
		chasemodes.PROPORTIONAL_NAVIGATION:
			if is_facing_target:
				compute_pn_thrust()
				print("using PN")
			else:
				compute_strafe_thrust()
				print("SWITCHING TO PURSUIT")

func compute_strafe_thrust() -> void:
	var inv_basis: Basis = basis.inverse()
	var local_error: Vector3 = inv_basis * get_position_error()
	var local_velocity: Vector3 = inv_basis * linear_velocity

	var final_thrust := Vector3.ZERO
	for axis in range(3):
		var distance_to_stop: float = (local_velocity[axis] * local_velocity[axis]) / (2.0 * linear_agility)
		var is_towards_target: bool = sign(local_velocity[axis]) == sign(local_error[axis])
		if abs(local_error[axis]) <= distance_to_stop and is_towards_target:
			final_thrust[axis] = -sign(local_error[axis])
		else:
			final_thrust[axis] = sign(local_error[axis])

	var _hide: bool = Vector2(local_error.x, local_error.y).length() < 2.0
	missile_thrust(final_thrust, true, _hide)
	
func compute_rotation_thrust() -> void:
	var rotation_error: Vector3 = get_rotation_error()
	var error_angle: float = rotation_error.length()

	if error_angle < 0.1:
		var look_dir: Vector3 = (target_position - global_position).normalized()
		var up: Vector3 = global_basis.y
		if abs(look_dir.dot(up)) > 0.99:
			up = global_basis.x
		var quat: Quaternion = Basis.looking_at(look_dir, up).get_rotation_quaternion()
		missile_force_rotation(quat)
		return

	var rotation_axis: Vector3 = rotation_error / error_angle
	var spin_towards_target: float = angular_velocity.dot(rotation_axis)
	var angle_to_stop: float = (spin_towards_target * spin_towards_target) / (2.0 * angular_agility)

	var final_torque: Vector3
	if angle_to_stop >= error_angle and spin_towards_target > 0.0:
		final_torque = -rotation_axis
	else:
		final_torque = rotation_axis
	var _hide := false
	if final_torque.length() < 0.2:
		_hide = true
	#print("rotating hide? ",hide)
	missile_rotation(final_torque, false, false, _hide)
	
		
##computes target_position. if the target object is moving, it will change accordingly.
#func compute_target_position(_delta: float) -> void:
	#if !target:
		#no_target = true
		#return
	#no_target = false
#
#
	#if target is CharacterBody3D:
		#target_velocity = target.velocity
	#elif target is RigidBody3D:
		#target_velocity = target.linear_velocity
#
	#match chase_mode:
		#chasemodes.PURSUIT:
			#target_position = target.global_position
		#chasemodes.PROPORTIONAL_NAVIGATION:
			#pass
func compute_target_position(_delta: float) -> void:
	if !target:
		no_target = true
		return
	no_target = false
	target_position = target.global_position
	target_velocity = Vector3.ZERO
	if target is CharacterBody3D:
		target_velocity = target.velocity
	elif target is RigidBody3D:
		target_velocity = target.linear_velocity
		
	var angle_towards_target :float= (get_position_error().normalized().dot(linear_velocity.normalized()))
	if angle_towards_target > 0.1:
		is_facing_target = true
		return
	is_facing_target = false
 
func get_pn_aim_point(_target_position: Vector3, _target_velocity: Vector3) -> Vector3:
	var los: Vector3 = _target_position - global_position
	var range_to_target: float = los.length()
	if range_to_target < 0.5:
		return _target_position
	var relative_velocity: Vector3 = _target_velocity - linear_velocity
	var los_unit: Vector3 = los / range_to_target
	var closing_velocity: float = -relative_velocity.dot(los_unit)
	var los_rotation: Vector3 = los.cross(relative_velocity) / (range_to_target * range_to_target)
	var commanded_acceleration: Vector3 = pn_gain * closing_velocity * los_rotation.cross(los_unit)
	return global_position + commanded_acceleration

func compute_pn_thrust() -> void:
	var aim_point: Vector3 = get_pn_aim_point(target_position, target_velocity)
	var pn_direction: Vector3 = (aim_point - global_position).limit_length(linear_agility) / linear_agility
	var _hide := false
	if pn_direction.length() <= 0.5:
		_hide = true
	missile_thrust(pn_direction, true, _hide)
	
func get_position_error() -> Vector3:
	#print(target_position - global_position)
	return target_position - global_position
	
func get_rotation_error() -> Vector3:
	if !target:
		return Vector3.ZERO
	var desired_forward: Vector3 = (target_position - global_position).normalized()
	var current_forward: Vector3 = -global_transform.basis.z
	
	var dot: float = current_forward.dot(desired_forward)
	
	## degenerate: vectors are nearly antiparallel
	if dot < -0.9999:
		## pick any axis perpendicular to current forward
		var fallback: Vector3 = current_forward.cross(Vector3.UP)
		if fallback.length_squared() < 0.001:
			fallback = current_forward.cross(Vector3.RIGHT)
		return fallback.normalized() * PI
	
	var rotation_diff: Quaternion = Quaternion(current_forward, desired_forward)
	return rotation_diff.get_axis() * rotation_diff.get_angle()

##simulated thrust in the direction. direction must be localized
func missile_thrust(direction: Vector3 = Vector3.ZERO, reset := false, _hide := false) -> void:
	if reset:
		for x in all_thrusters:
			x.ide()

	
	if disable_strafe:
		direction = Vector3(0,0,direction.z)
	if !enable_rear_thrust:
		direction.z = -1
	
	if !_hide and !hide_RCS:
		#left or right
		match sign(direction.x): 
			1.0:
				Thrust_right.how()
				Thrust_right_aft.how()
			-1.0:
				Thrust_left.how()
				Thrust_left_aft.how()
		
		#up or down
		match sign(direction.y):
			1.0:
				Thrust_up.how()
				Thrust_up_aft.how()
				
			-1.0:
				Thrust_down.how()
				Thrust_down_aft.how()
		RCS_audio_queued = true
	if !hit_target and thrust_time >= 0:
		Thrust_forward.how()
		#Thrust_forward.neopitch = 0.8 * clamp((linear_velocity.length()/60.0) * 0.8, 1.0, 1.7)

	#print("applying force ", direction)
	apply_central_force(basis * (direction * mass * Vector3(linear_agility,linear_agility,forward_acceleration)) )

func missile_force_rotation(face: Quaternion, weight := 20.0) -> void:
	var current_rotation :Quaternion= global_basis.get_rotation_quaternion().normalized()
	current_rotation = current_rotation.slerp(face, min(weight * get_physics_process_delta_time(), 1.0))
	basis = Basis(current_rotation)

func missile_rotation(direction: Vector3 = Vector3.ZERO, reset := true, visual_only := false, _hide := false) -> void:
	if reset:
		for x in all_thrusters:
			x.ide()
	direction = basis.inverse() * direction
	var temporary_multiplier := 1.0
	if direction.length() < deg_to_rad(15):
		temporary_multiplier = 0.5
	
	if !_hide and !hide_RCS:

		match sign(direction.x):
			1.0:
				Thrust_up.how()
				Thrust_down_aft.how()
				Thrust_down.ide()
			-1.0:
				Thrust_down.how()
				Thrust_up_aft.how()
				Thrust_up.ide()

		match sign(direction.y):
			1.0:
				Thrust_left.how()
				Thrust_right_aft.how()
				Thrust_left.ide()
			-1.0:
				Thrust_right.how()
				Thrust_left_aft.how()
				Thrust_left.ide()
		RCS_audio_queued = true
		
	if visual_only:
		return
	#if !direction.z:
		#direction.z = randf_range(-0.2, 0.2)
	apply_torque(basis * direction * angular_agility * temporary_multiplier)
	

	
func missile_impact(collider: Node3D) -> void:
	if hit_target:
		return
	#var root:= get_tree().root.get_child(0)
	#var after_death := [$impact,$explosion,$VaporTrail]
	global_position = collider.global_position
	#$explosion.pitch_scale = 10
	
	$explosion.play()
	audio_main_thrust.queue_free()
	audio_RCS.queue_free()
	$impact.emitting = true
	for x:Missile_thruster in all_thrusters:
		if x.constant_thrust:
			x.shutdown()
			pass
		x.queue_free()
	set_physics_process(false)
	$"missile final_001".queue_free()
	$Text_008.queue_free()
	$impactcheck.queue_free()
	$VaporTrail.update_interval= 0.1
	thrust_time = -1
	hit_target = true
	freeze = true
	#$impact.reparent(root)
	#$explosion.reparent(root)
	#$VaporTrail.reparent(root)
	
	print("freed ", self)
	await get_tree().create_timer(8.0).timeout
	queue_free()
	
func _rcs_audio() -> void:
	if randi_range(0,2) == 0:
		if RCS_instance_count > 20 and RCS_this_id > 20 and _distance_to_cam() > 50:
			print("RCS is hidden!")
			return
		
		audio_RCS.play()
		#RCS_audio_queued = false

func _distance_to_target() -> float:
	return target_position.distance_to(global_position)

func _distance_to_cam() -> float:
	var current_frame := Engine.get_physics_frames()
	if !cached_camera or cached_camera_frame != current_frame:
		cached_camera = get_viewport().get_camera_3d()
		cached_camera_frame = current_frame
	return global_position.distance_to(cached_camera.global_position)

var RCS_audio_queued := false

func compute_tick_avionics_ratio() -> void:
	var distance := _distance_to_target()
	if distance < 400.0: 
		ratio_calculate_avionics = 1
	elif distance < 1000.0 or instance_count > 100:
		ratio_calculate_avionics = 2
	else:
		ratio_calculate_avionics = 3

var performance_RCS_disabled := false
func allow_RCS() -> void:
	if RCS_instance_count > 50:
		hide_RCS = true
		performance_RCS_disabled = true
	else:
		hide_RCS = false
		performance_RCS_disabled = false

func _on_impactcheck_body_hit(collider: Node3D) -> void:
	print("hit" , collider)
	missile_impact(collider)


func _on_body_entered(body: Node) -> void:
	print("hit" , body)
	missile_impact(body)
	
func _exit_tree() -> void:
	instance_count -= 1
	if !hide_RCS:
		RCS_instance_count -= 1
