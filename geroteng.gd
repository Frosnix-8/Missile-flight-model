extends RigidBody3D
##Guided Missile. Features a few chase methods and is highly customizable, 
##featuring many performance settings that can be tinkered (use a file to change them with settings). 
##About 100-200 missiles can be loaded before having heavy impacts
##on performance. HOwever, damage calculations are not done yet. For more roundede trajectories, 
##top speed, acceleration, rotation speeds should be close to each other.
class_name Missile_Guided
##amount of missile instances in the current tree.
static var instance_count := 0
##amount of missile instances with RCS enabled in the current tree. 
static var RCS_instance_count := 0
##performance level assigned depending on the amount of missiles in a scene. this is static because every missile shares it, so there's no need to calculate per-missile, just once per frame.
static var global_performance_level := -1
##the main viewport's active camera. This allows distance based LOD for various systems to work. it's static since there's only ever one active camera at a time. 
static var cached_camera : Camera3D
##frame on which the camera was cached. on new frames, the camera is recached, but only once.
static var cached_camera_frame : int = 0
static var exploding_missiles : int = 0

#region static performance variables

##Past this amount of RCS missiles, the game will no longer render the RCS. 
const PERFORMANCE_RCS_MAX_INSTANCES := 20
##Distance past which RCS will not render.
const PERFORMANCE_RCS_DISTANCE_MAX := 500
##Past this distance, RCS no longer plays audio
const PERFORMANCE_RCS_AUDIO_DISTANCE_MAX := 500
##Distance from target beyond which the performance level is increased. higher levels mean the missile calculates trajectories less often.
const PERFORMANCE_POLL_DISTANCE := 400
##Distance from target beyond which performance level is increased again. higher levels mean the missile calculates trajectories less often.
const PERFORMANCE_POLL_DISTANCE_FAR := 800
##instance count beyond which performance level is increased. higher levels mean the missile calculates trajectories less often.
const PERFORMANCE_POLL_INSTANCE_COUNT := 40
##instance count beyond which performance level is increased again. higher levels mean the missile calculates trajectories less often.
const PERFORMANCE_POLL_INSTANCE_COUNT_FAR := 70
##instance count beyond which performance level is increased more. higher levels mean the missile calculates trajectories less often.
const PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME := 100
##whether RCS is disabled for performance reasons.
var performance_RCS_disabled := false
#endregion
##ID of the current missile if it as RCS. higher ID numbers mean there were more RCS missiles instanced when this specific one entered the tree.
var RCS_this_id := 0
##ID of the current missile. higher ID numbers mean there were more missiles instanced when this specific one entered the tree.
var this_id := 0


@export_category("Debug")
##Prevents RCS from hiding for cosmetic or debug reasons.
@export var show_all_thrusters := false
##Disables fuel timer.
@export var unlimited_fuel := false
##Disables all missile strafing. This disables all forms of lateral movement. without linear velocity damping, this just makes the missile uncontrollable.
@export var disable_strafe := false
##NOTE: depracated.
@export var enable_rear_thrust := false
@export_category("Chase Modes")

##Chase modes.
enum chasemodes {
	PURSUIT , ##Goes after the target's current position irrespective of its velocity. Easier to evade.
	PROPORTIONAL_NAVIGATION ##The missile keeps a constant bearing relative to the target, hitting the future position of the target, no matter its speed.
	}
##How the missile will pursue targets. 
@export var chase_mode : chasemodes = chasemodes.PURSUIT
##current pursue mode. PN doesn't always use PN tracking, such as when the missile isn't facing the missile.
var current_chase_mode : chasemodes = chase_mode
##aggressivity of PN corrections. NOTE: depracated.
@export var pn_gain: float = 4.0

@export_category("Track Modes")
enum trackmodes {
	PASSIVE_INFRARED, ##Chases based on the heat signature of the target. Theoretically less detectable.
	PASSIVE_CROSSFIRE, ##Chases based using built-in pattern recognition to recognize the target instead of heat or radar. Theoretically less detectable.
	PASSIVE_ANTI_RADIATION, ##Chases based on radar emissions emitted by the target.
	SEMI_ACTIVE_LASER, ##Chases based on laser targets provided by the mothership. Theoretically more detectable as it puts a fucking laser on the target.
	SEMI_ACTIVE_RADAR, ##Chases based on radar data supplied from the mothership. Theoretically more detectable because of its radio emissions.
	ACTIVE_RADAR, ##Chases based on radar data supplied by a built-in radar. Theoretically very detectable, as it directly emits frequencies towards the target.
	
}
@export var track_mode : trackmodes = trackmodes.PASSIVE_INFRARED

@onready var Thrust_forward : Missile_thruster = $ThrustEffect
@onready var Thrust_right : Missile_thruster = $ThrustEffect6
@onready var Thrust_left : Missile_thruster = $ThrustEffect7
@onready var Thrust_up : Missile_thruster = $ThrustEffect5
@onready var Thrust_down : Missile_thruster = $ThrustEffect2
@onready var Thrust_left_aft : Missile_thruster = $ThrustEffect8
@onready var Thrust_right_aft : Missile_thruster = $ThrustEffect9
@onready var Thrust_up_aft : Missile_thruster = $ThrustEffect4
@onready var Thrust_down_aft : Missile_thruster = $ThrustEffect3
enum thrusters {
	FORWARD,
	DOWN,
	DOWN_AFT,
	LEFT,
	LEFT_AFT,
	RIGHT,
	RIGHT_AFT,
	UP,
	UP_AFT
}
var all_thrusters : Array[Missile_thruster]
var active_thrusters : Array[bool] = [false,false,false,false,false,false,false,false,false]
var thruster_to_activate : Array[bool] = [false,false,false,false,false,false,false,false,false]


##Shapecast (or Raycast in the future) that detects objects. it faces the missile's attitude and has a length equal to its distance traveled each frame.
@onready var collision_check : ShapeCast3D = $impactcheck
##Audio for main thrust.
@onready var audio_main_thrust : AudioStreamPlayer3D = $MAINTHRUST
##Audio for RCS effects. Has polyphony.
@onready var audio_RCS : AudioStreamPlayer3D = $RCS
##Whether the missile is expecting to play RCS audio this frame.
var RCS_audio_queued := false




@export_category("Missile specifications")
##Speed when launched from ship. When the missile is instanciated (or in the future, activated?), an impulse of n * mass newtons is applied in the negative Z basis (forward)
@export var launch_speed: float = 10.0
##Time before the missile starts maneuvering.
@export var launch_clear_time : float = 0.5
##Time during which the missile cannot collide with its owner.
@export var arm_time : float = 2.0
var can_maneuver := false
var armed := false
##Max forward speed of the missile. this doesn't correspond to strafing speed limits for technical reasons. If the missile exceeds this speed in its forward axis, it'll slow down. 
@export var max_straight_line_speed : float = 1000
##agility of the missile, IE the strength with which it can thrust sideways. 
##by definition, agility is the max sideways acceleration of the missile.
@export var linear_agility := 75.0
##forward acceleration of the missile in m/s.
@export var forward_acceleration := 120.0
##angular agility of the missile, how much angular torque it can produce.
@export var angular_agility :float= PI * 2
##time in seconds before the missile depletes its fuel tanks.
@export var thrust_time := 10.0
##when the fuel timer runs out, should the missile explode? This just looks cool for the moment, and doesn't do anything special.
@export var explode_on_fuel_loss := false


@export_category("Visual Parameters")
##Disables all visual and auditive features concerning RCS for cosmetic reasons. this has the added benefit of slightly improved performance,
## albeit negligible in practice due to LOD and instance limiting systems in place. This does not disable strafing.
@export var hide_RCS := false
##Hides Vaportrail. Slight performnace boost where there's a fuck ton of missiles. Has an unintended consequence of making it hard to see.
@export var hide_trail := false
##Hides particles. Slight performance boost, but it's already moderated.
@export var hide_particles := false

@export_category("Audio Parameters")
##Volume variation in decibels of the main thrusters.
@export var main_thrust_volume_db := 0.0
##Pitch variation of the main thrusters.
@export var main_thrust_pitch_scale := 1.0
##Volume in decibels variations of RCS.
@export var thrust_volume_db := 0.0
##Pitch scale of the RCS thrusters.
@export var thrust_pitch_scale := 1.0
##Volume variation of explosions.
@export var explosion_volume_db := -19
##Volume variation for ALL sound of this node.
@export var master_effect_volume_db := 0.0
@export_category("Target")
##Debug target of the missile. It is best assigned via scripts in proper implimentations.
@export var target : Node3D
##Ship that owns this missile (IE, which ship launched this one.)
var owner_ship : Node3D


##Current target position. not to be confused with the actual target entity, this is where the missile needs to go, rather than where the target entity is.
var target_position := Vector3.ZERO
##To be depracated. PN uses different algorithms, so to separate both systems a new taret location variable was added.
var PN_aim_point := Vector3.ZERO
##Speed of the target entity.
var target_velocity := Vector3.ZERO
##Whether the missile is facing the target.
var is_facing_target :bool= false
##If there is no target, then this is true. Turns the missile into a dumbfire rocket.
var no_target := true
##If the missile has collided, this is true.
var hit_target := false

##physics ticks, increments by one each physics frame.
var tick_avionics := 0
##integer marking performance mode of missiles. 0 is highest performance, 1 is half, 2 is a third, etc. Maxes out at 3 or 4 (P = 60/(n + 1) Hz)
var performance_level := 0
##Tick ratios for calculating avionics. Each higher index is a higher performance level, IE: higher fps modes. calculates every n frame(s). Increase for better performance, at the cost of inferior missile accuracy
@export var avionic_tick_ratios :Array[int]= [1,2,3,4,5]
##compute avionics every n'th physics frame.
var current_avionic_tick_ratio := 1
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if hide_particles:
		$GPUParticles3D.amount_ratio = 0
	if hide_trail:
		$VaporTrail.num_points = 1
		$VaporTrail.update_interval = 100
		
	instance_count += 1
	this_id = instance_count
	var show_rcs_later := false
	if !hide_RCS:
		RCS_instance_count += 1
		RCS_this_id = RCS_instance_count
		show_rcs_later = true
		hide_RCS = true
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
	audio_RCS.pitch_scale *= thrust_pitch_scale
	audio_main_thrust.pitch_scale *= main_thrust_pitch_scale
	audio_main_thrust.volume_db = main_thrust_volume_db
	$explosion.volume_db = explosion_volume_db
	
	
	angular_agility *= randf_range(0.9,1.1)
	linear_agility *= randf_range(0.9,1.1)
	forward_acceleration *= randf_range(0.9,1.1)
	launch_clear_time *= randf_range(0.6,1.0)
	launch_speed *= randf_range(0.9,1.1)
	await get_tree().physics_frame
	apply_central_impulse(basis *  Vector3.FORWARD * launch_speed * mass)
	await get_tree().create_timer(launch_clear_time).timeout
	can_maneuver = true
	hide_RCS = !show_rcs_later
	await get_tree().create_timer(max(0.1, arm_time - launch_clear_time)).timeout
	armed = true


func _physics_process(delta: float) -> void:
	
	tick_avionics += 1
	global_performance_level = -1
	RCS_audio_queued = false
	thrust_time -= delta
	
	if tick_avionics % 15 == 0:
		#reset global performance level.
		
		compute_tick_avionics_ratio()
		allow_RCS()
		missile_LOD()
	

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
		
	if tick_avionics % current_avionic_tick_ratio == 0:
		compute_target_position(delta)
		compute_thrust()
		compute_rotation_thrust()
	missile_thruster_set_visibility()
	_rcs_audio()
	#print("missile has a velocity of ", linear_velocity.length())

	#print(linear_velocity.length())
	collision_check.target_position = collision_check.to_local(linear_velocity) * delta * 0.5
	$"missile final_001".scale = max(1,_distance_to_cam()) * 0.01 * Vector3.ONE + Vector3.ONE
	
##Computes how the missile should strafe relative to the target. Decides based off the chase mode.
func compute_thrust() -> void:
	if no_target or !can_maneuver:
		missile_thrust(Vector3.FORWARD,true)
		return
	match chase_mode:
		chasemodes.PURSUIT:
			current_chase_mode = chasemodes.PURSUIT
			compute_strafe_thrust()
		chasemodes.PROPORTIONAL_NAVIGATION:
			
			if is_facing_target:
				current_chase_mode = chasemodes.PROPORTIONAL_NAVIGATION
				compute_pn_intercept_point()
				#compute_pn_thrust()
				#print("using PN")
			else:
				current_chase_mode = chasemodes.PURSUIT
			compute_strafe_thrust()
				#print("SWITCHING TO PURSUIT")

##Computes which local thrust axes to activate in order to remove all lateral drift, as in the missile is going straight forward. 
func compute_strafe_thrust() -> void:
	var inv_basis: Basis = basis.inverse()
	var local_velocity: Vector3 = inv_basis * linear_velocity

	var final_thrust := Vector3.ZERO
	for axis in range(2):
		final_thrust[axis] = -sign(local_velocity[axis])
	
	var _hide: bool = Vector2(local_velocity.x, local_velocity.y).length() < 2.0
	missile_thrust(final_thrust, true, _hide, inv_basis)

##Computes the necessary rotation forces to face the desired direction.
func compute_rotation_thrust() -> void:
	if no_target or !can_maneuver:
		return
	var rotation_error: Vector3 = get_rotation_error()
	var error_angle: float = rotation_error.length()
	
	
	#if you're more or less facing the target, just snap to it.
	if error_angle < 0.1:
		var this_target_position: Vector3
		
		match current_chase_mode:
			chasemodes.PURSUIT:
				this_target_position = target_position
			chasemodes.PROPORTIONAL_NAVIGATION:
				this_target_position = PN_aim_point
				
		var look_dir: Vector3 = (this_target_position - global_position).normalized()
		var up: Vector3 = basis.y
		
		if abs(look_dir.dot(up)) > 0.99:
			up = basis.x
			
		var to_target_Quat: Quaternion = Basis.looking_at(look_dir, up).get_rotation_quaternion()
		missile_force_rotation(to_target_Quat)
		
		return
	
	var rotation_axis: Vector3 = rotation_error / error_angle
	var spin_towards_target: float = angular_velocity.dot(rotation_axis)
	var angle_to_stop: float = (spin_towards_target * spin_towards_target) / (2.0 * angular_agility)

	var final_torque: Vector3
	if angle_to_stop >= error_angle and spin_towards_target > 0.0:
		final_torque = -rotation_axis
	else:
		final_torque = rotation_axis
	
	#check if you need to rotate
	var _hide := false
	if final_torque.length() < 0.2:
		_hide = true
	
	missile_rotation(final_torque, false, false, _hide)
	
		
##updates the target position. Additionally, checks if the missile is facing the target.
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

##To be removed, calculates motion vectors to cancel all bearing motion
func compute_pn_thrust() -> void:
	var aim_point: Vector3 = get_pn_aim_point(target_position, target_velocity)
	var pn_direction: Vector3 = (aim_point - global_position).limit_length(linear_agility) / linear_agility
	var _hide := false
	if pn_direction.length() <= 0.5:
		_hide = true
	var inverse_basis := basis.inverse()
	missile_thrust(inverse_basis * pn_direction, true, _hide, inverse_basis)

##Computes where the missile should be when PN is enabled
func compute_pn_intercept_point() -> void:
	var los: Vector3 = target_position - global_position
	var range_to_target: float = los.length()
	if range_to_target < 2.0:
		PN_aim_point = target_position
		return
	var relative_velocity: Vector3 = target_velocity - linear_velocity
	var closing_speed: float = -relative_velocity.dot(los / range_to_target)
	if closing_speed <= 0.0:
		PN_aim_point = target_position  ## not closing, just face target
		return
	var time_to_intercept: float = range_to_target / closing_speed
	PN_aim_point = target_position + target_velocity * time_to_intercept

##DEPRACATED. Computes where the missile should point when Pn is enabled.
func get_pn_aim_point(_target_position: Vector3, _target_velocity: Vector3) -> Vector3:
	var los: Vector3 = _target_position - global_position
	var range_to_target: float = los.length()
	if range_to_target < 2.0:
		return _target_position
	var relative_velocity: Vector3 = _target_velocity - linear_velocity
	var los_unit: Vector3 = los / range_to_target
	var closing_velocity: float = -relative_velocity.dot(los_unit)
	var los_rotation: Vector3 = los.cross(relative_velocity) / (range_to_target * range_to_target)
	var commanded_acceleration: Vector3 = pn_gain * closing_velocity * los_rotation.cross(los_unit)
	
	return global_position + commanded_acceleration


##returns a vector pointing towards the target.
func get_position_error() -> Vector3:
	#print(target_position - global_position)
	return target_position - global_position

##Computes the rotation necessary to face the target. 
func get_rotation_error() -> Vector3:
	if !target or linear_velocity.length_squared() < 1.0:
		return Vector3.ZERO
	var this_target_position : Vector3
	
	match current_chase_mode:
		chasemodes.PURSUIT:
			this_target_position = target_position
		chasemodes.PROPORTIONAL_NAVIGATION:
			this_target_position = PN_aim_point
			
	var desired_forward: Vector3 = (this_target_position - global_position).normalized()
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



func missile_thruster_set_visibility() -> void:
	for i in all_thrusters.size():
		if thruster_to_activate[i] != active_thrusters[i]:
			if thruster_to_activate[i]:
				all_thrusters[i].how()
			else:
				all_thrusters[i].ide()
			
			active_thrusters[i] = thruster_to_activate[i]
	
	thruster_to_activate.fill(false)

##Applies all physic forces based on the supplied direction. Additionally, checks which RCS thrusters should be active.
func missile_thrust(direction: Vector3 = Vector3.ZERO, reset := false, _hide := false, inverse_basis := basis.inverse()) -> void:
	if reset:
		thruster_to_activate.fill(false)
	direction.z = clamp(sign(direction.z), -1,0)
	
	if disable_strafe:
		direction = Vector3(0,0,direction.z)
	direction.z = -1.0
	
	if !_hide and (!hide_RCS and !performance_RCS_disabled):
		#left or right
		match sign(direction.x): 
			1.0:
				thruster_to_activate[thrusters.RIGHT] = true
				thruster_to_activate[thrusters.RIGHT_AFT] = true
			-1.0:
				thruster_to_activate[thrusters.LEFT] = true
				thruster_to_activate[thrusters.LEFT_AFT] = true
		
		#up or down
		match sign(direction.y):
			1.0:
				thruster_to_activate[thrusters.UP] = true
				thruster_to_activate[thrusters.UP_AFT] = true
				
			-1.0:
				thruster_to_activate[thrusters.DOWN] = true
				thruster_to_activate[thrusters.DOWN_AFT] = true
	if !_hide:
		RCS_audio_queued = true
	
	if direction.z == -1.0:
		thruster_to_activate[thrusters.FORWARD] = true

	if linear_velocity.length() > max_straight_line_speed:
		direction.z = 0.0
		
	#print("applying force ", direction)
	apply_central_force(basis * (direction * mass * Vector3(linear_agility,linear_agility,forward_acceleration) * current_avionic_tick_ratio) )

##Snaps the missile to the supplied quaternion.
func missile_force_rotation(face: Quaternion, weight := 20.0) -> void:
	var current_rotation :Quaternion= basis.get_rotation_quaternion().normalized()
	current_rotation = current_rotation.slerp(face, 0.5 * get_physics_process_delta_time() * weight)
	basis = Basis(current_rotation)

##Applies torque based off the supplied rotation direction. Additionally, determines which RCS thrusters should be active.
func missile_rotation(direction: Vector3 = Vector3.ZERO, reset := true, visual_only := false, _hide := false) -> void:
	if reset:
		thruster_to_activate.fill(false)
	direction = basis.inverse() * direction
	var temporary_multiplier := 1.0
	if direction.length() < deg_to_rad(15):
		temporary_multiplier = 0.5
	
	if !_hide and (!hide_RCS and !performance_RCS_disabled):

		match sign(direction.x):
			1.0:
				thruster_to_activate[thrusters.UP] = true
				thruster_to_activate[thrusters.DOWN_AFT] = true
				thruster_to_activate[thrusters.DOWN] = false
			-1.0:
				thruster_to_activate[thrusters.DOWN] = true
				thruster_to_activate[thrusters.UP_AFT] = true
				thruster_to_activate[thrusters.UP] = false

		match sign(direction.y):
			1.0:
				thruster_to_activate[thrusters.LEFT] = true
				thruster_to_activate[thrusters.RIGHT_AFT] = true
				thruster_to_activate[thrusters.RIGHT] = false
			-1.0:
				thruster_to_activate[thrusters.RIGHT] = true
				thruster_to_activate[thrusters.LEFT_AFT] = true
				thruster_to_activate[thrusters.LEFT] = false
	if !_hide:
		RCS_audio_queued = true
		
	if visual_only:
		return
	#if !direction.z:
		#direction.z = randf_range(-0.2, 0.2)
	apply_torque(basis * direction * angular_agility * temporary_multiplier * current_avionic_tick_ratio
	)
	

##Logic for what happens when the missile collides.
func missile_impact(collider: Node3D) -> void:
	if hit_target:
		return
	elif (collider == owner_ship or collider.get_parent().get_parent() == owner_ship) and !armed :
		return
	print(collider)
	exploding_missiles += 1
	
	#var root:= get_tree().root.get_child(0)
	#var after_death := [$impact,$explosion,$VaporTrail]
	if collider:
		global_position = global_position + linear_velocity * get_physics_process_delta_time()
	#$explosion.pitch_scale = 10
	#$Camera3D.queue_free()
	$explosion.play()
	audio_main_thrust.queue_free()
	audio_RCS.queue_free()
	if performance_level < 2 or exploding_missiles < 10:
		$impact.emitting = true
	else:
		push_warning("high performance or high explosion count, cancelling explosion.")
		$impact.queue_free()
	for x:Missile_thruster in all_thrusters:
		if x.constant_thrust:
			x.shutdown()
			pass
		x.queue_free()
	set_physics_process(false)
	$LOD.queue_free()
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
	
	#print("freed ", self)
	await get_tree().create_timer(4.0).timeout
	queue_free()
	
func missile_LOD() -> void:
	if _distance_to_cam() > PERFORMANCE_POLL_DISTANCE:
		$"missile final_001".hide()
		$Text_008.hide()
		$LOD.show()
		$GPUParticles3D.emitting = false
	else:
		$"missile final_001".show()
		$Text_008.show()
		$LOD.hide()
		$GPUParticles3D.emitting = true
	if instance_count > PERFORMANCE_POLL_INSTANCE_COUNT and this_id > PERFORMANCE_POLL_INSTANCE_COUNT:
		$GPUParticles3D.emitting = false
		
	if instance_count > PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME + 50 and this_id > PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME:
		$VaporTrail.hide()
	else:
		$VaporTrail.show()
	


##Determines if RCS audio should be played or not, depending on the static distance limit or instance count set.
func _rcs_audio() -> void:
	if hide_RCS:
		return
	if RCS_audio_queued and randi_range(0,2) == 0:
		#don't show if your ID is too high when there are too many and or you're too far.
		if (RCS_instance_count > 20 and RCS_this_id > 20 and _distance_to_cam() > 50) or _distance_to_cam() > PERFORMANCE_RCS_AUDIO_DISTANCE_MAX:
			return
		
		audio_RCS.play()
		RCS_audio_queued = false

##returns the distance to the target entity.
func _distance_to_target() -> float:
	return target_position.distance_to(global_position)

##returns the distance to the active camera for the viewport.
func _distance_to_cam() -> float:
	var current_frame := Engine.get_physics_frames()
	if !cached_camera or cached_camera_frame != current_frame:
		cached_camera = get_viewport().get_camera_3d()
		cached_camera_frame = current_frame
	return global_position.distance_to(cached_camera.global_position)

##Calculates the performance level and tick ratio for the missile instance.
func compute_tick_avionics_ratio() -> void:
	var distance := _distance_to_target()
	var new_performance_level : int
	
	#this first pass is per-missile
	if distance < PERFORMANCE_POLL_DISTANCE:
		new_performance_level = 0
	elif distance < PERFORMANCE_POLL_DISTANCE_FAR:
		new_performance_level = 1
		#print("far from target, increasing performance level")
	else:
		new_performance_level = 2
		#print("very far from target, increasing performance level")
	
	#this means no one has changed it yet.
	if global_performance_level == -1:
		#this second pass is global, every missile will have the same outcome.
		if instance_count < PERFORMANCE_POLL_INSTANCE_COUNT:
			global_performance_level = 0
			
		elif instance_count < PERFORMANCE_POLL_INSTANCE_COUNT_FAR:
			global_performance_level = 1
			#print("instance count high, increasing performance level.")
		elif instance_count < PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME:
			#print("instance count very high, increasing performance level even more.")
			global_performance_level = 2
		else:
			global_performance_level = 3
			#print("instance count very high, increasing performance level")
	
		
		
	new_performance_level += global_performance_level
	new_performance_level = clampi(new_performance_level, 0, avionic_tick_ratios.size() - 1)
	#print("new performance level is " , new_performance_level)
	current_avionic_tick_ratio = avionic_tick_ratios[new_performance_level]
	
	
	

##Whether RCS should be disabled for performance reasons.
func allow_RCS() -> void:
	if RCS_instance_count > PERFORMANCE_RCS_MAX_INSTANCES or _distance_to_cam() > PERFORMANCE_RCS_DISTANCE_MAX:
		performance_RCS_disabled = true
	else:
		performance_RCS_disabled = false

##Called when the Physicsbody of the missile hits something. (NOTE: missile collisions are disabled.)
func _on_impactcheck_body_hit(collider: Node3D) -> void:
	#print("hit" , collider)
	missile_impact(collider)

##Called when the Shape/Ray Cast detects a body.
func _on_body_entered(body: Node) -> void:
	#print("hit" , body)
	missile_impact(body)

##Idk this does something
func _exit_tree() -> void:
	if hit_target:
		exploding_missiles -= 1
	instance_count -= 1
	if !hide_RCS:
		RCS_instance_count -= 1
