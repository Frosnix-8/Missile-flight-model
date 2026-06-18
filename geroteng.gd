extends RigidBody3D
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
##empty? missile can no longer maneuver in vacuum
var thrust_time := 10.0

var all_thrusters : Array[Missile_thruster]

@export_category("Missile specifications")
##Speed when launched from ship. 
@export var launch_speed: float = 2.0
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

@export_category("Target")
@export var target : Node3D

var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var is_facing_target :bool= false
var no_target := true
var hit_target := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
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
			x.hide()	
	linear_velocity = global_transform.basis.z * launch_speed


func _physics_process(delta: float) -> void:
	thrust_time -= delta
	if (thrust_time <= 0 and !unlimited_fuel )or hit_target:
		missile_thrust(Vector3.ZERO, true, true)
		if explode_on_fuel_loss:
			missile_impact(null)
		return
	compute_target_position(delta)
	compute_thrust()
	compute_rotation_thrust()
	print("missile has a velocity of ", linear_velocity.length())
	
	collision_check.target_position = collision_check.to_local(linear_velocity) * delta
	
	
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
	var position_error := get_position_error()
	
	var local_error: Vector3 = basis.inverse() * position_error
	var final_thrust := Vector3.ZERO
	for axis in range(3):
		var distance_to_stop := (linear_velocity[axis] * linear_velocity[axis]) / (2.0 * linear_agility)
		var is_towards_target: bool = bool(sign(linear_velocity[axis]) == sign(position_error[axis]))
		if abs(position_error[axis]) <= distance_to_stop and is_towards_target:
			final_thrust[axis] = -sign(position_error[axis])
		else:
			final_thrust[axis] = sign(position_error[axis])
	var hide: bool = Vector2(local_error.x, local_error.y).length() < 2.0
	#print("strafing hide ",hide, " ; ",Vector2(local_error.x, local_error.y).length())
	missile_thrust(final_thrust, true, hide)
	
func compute_rotation_thrust() -> void:
	var rotation_error: Vector3 = get_rotation_error()
	var error_angle: float = rotation_error.length()

	if error_angle < 0.1:
		#var forward_target : Vector3 = get_position_error()
		var quat : Quaternion = global_transform.looking_at(target_position,global_basis.y).basis.get_rotation_quaternion()
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
	var hide := false
	if final_torque.length() < 0.2:
		hide = true
	#print("rotating hide? ",hide)
	missile_rotation(final_torque, false, false, hide)
	
		
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
	var hide := false
	if pn_direction.length() <= 0.5:
		hide = true
	missile_thrust(pn_direction, true, hide)
	
func get_position_error() -> Vector3:
	#print(target_position - global_position)
	return target_position - global_position
	
func get_rotation_error() -> Vector3:
	if !target:
		return Vector3.ZERO
	var desired_forward: Vector3 = (target_position - global_position).normalized()
	var current_forward: Vector3 = -global_transform.basis.z
	var rotation_diff: Quaternion = Quaternion(current_forward, desired_forward)
	return rotation_diff.get_axis() * rotation_diff.get_angle()

##simulated thrust in the direction.
func missile_thrust(direction: Vector3 = Vector3.ZERO, reset := false, hide := false) -> void:
	if reset:
		for x in all_thrusters:
			x.hide()
	#a missile never retreats, it always goes forward.
	#direction.z = sign(direction.z)
	#direction.x = sign(direction.x)
	#direction.y = sign(direction.y)
	#right or left
	direction = basis.inverse() * direction
	if disable_strafe:
		direction = Vector3(0,0,direction.z)
	if !enable_rear_thrust:
		direction.z = -1
	
	if !hide and !hide_RCS:
		match sign(direction.x): 
			1.0:
				#print("thrust right")
				Thrust_right.how()
				Thrust_right_aft.how()
			-1.0:
				#print("thrust left")
				Thrust_left.how()
				Thrust_left_aft.how()

		#up or down
		match sign(direction.y):
			1.0:
				#print("thrust up")
				Thrust_up.how()
				Thrust_up_aft.how()
			-1.0:
				#print("thrust down")
				Thrust_down.how()
				Thrust_down_aft.how()
			#_:
				#print("didn't thrust vertically")
	if !hit_target and thrust_time >= 0:
		match sign(direction.z):
			1.0: 
				Thrust_forward.how()
			-1.0:
				Thrust_forward.show()

	#print("applying force ", direction)
	apply_central_force(basis * (direction * mass * Vector3(linear_agility,linear_agility,forward_acceleration)) )

func missile_force_rotation(face: Quaternion, weight := 20.0) -> void:
	var current_rotation :Quaternion= global_basis.get_rotation_quaternion().normalized()
	current_rotation = current_rotation.slerp(face, min(weight * get_physics_process_delta_time(), 1.0))
	basis = Basis(current_rotation)

func missile_rotation(direction: Vector3 = Vector3.ZERO, reset := true, visual_only := false, hide := false) -> void:
	if reset:
		for x in all_thrusters:
			x.hide()
	direction = basis.inverse() * direction
	#direction.x = sign(direction.x)
	#direction.y = sign(direction.z)
	#direction.z = sign(direction.z)
	var temporary_multiplier := 1.0
	if direction.length() < deg_to_rad(15):
		temporary_multiplier = 0.5
	if !hide and !hide_RCS:
		match sign(direction.x):
			1.0:
				Thrust_up.how()
				Thrust_down_aft.how()
				Thrust_down.hide()
			-1.0:
				Thrust_down.how()
				Thrust_up_aft.how()
				Thrust_up.hide()

		match sign(direction.y):
			1.0:
				Thrust_left.how()
				Thrust_right_aft.how()
				Thrust_left.hide()
			-1.0:
				Thrust_right.how()
				Thrust_left_aft.how()
				Thrust_left.hide()
	if visual_only:
		return
	apply_torque(basis * direction * angular_agility * temporary_multiplier)
	

	
func missile_impact(collider: Node3D) -> void:
	if hit_target:
		return
	$explosion.play()
	$impact.emitting = true
	for x in all_thrusters:
		x.shutdown()
	$"missile final_001".hide()
	$Text_008.hide()
	$impactcheck.queue_free()
	thrust_time = -1
	hit_target = true
	
	
	
	


func _on_impactcheck_body_hit(collider: Node3D) -> void:
	print("hit" , collider)
	missile_impact(collider)


func _on_body_entered(body: Node) -> void:
	print("hit" , body)
	missile_impact(body)
