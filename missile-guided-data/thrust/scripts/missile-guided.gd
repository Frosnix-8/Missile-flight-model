extends RigidBody3D
##Guided Missile. Features a few chase methods and is highly customizable,
##featuring many performance settings that can be tinkered (use a file to change them with settings).
##About 100-200 missiles can be loaded before having heavy impacts
##on performance. Damage calculations are not done yet. For more rounded trajectories,
##top speed, acceleration, rotation speeds should be close to each other.
class_name Missile_Guided
##Reparents all long time nodes. Leave null to not move anything.
signal begin_countdown(new_parent : Node3D)
##amount of missile instances in the current tree.
static var instance_count := 0
##amount of missile instances with RCS enabled in the current tree.
static var RCS_instance_count := 0
##performance level assigned depending on the amount of missiles in a scene.
##static because every missile shares it — no need to calculate per-missile, just once per frame.
static var global_performance_level := -1
##the main viewport's active camera. Allows distance-based LOD for various systems.
##static since there's only ever one active camera at a time.
static var cached_camera : Camera3D
##frame on which the camera was cached. Recached once per new frame.
static var cached_camera_frame : int = 0
static var exploding_missiles : int = 0

#region static performance variables
#all these variables should be configurable via a 
##Past this amount of RCS missiles, RCS will no longer render.
const PERFORMANCE_RCS_MAX_INSTANCES := 20
##Distance past which RCS will not render.
const PERFORMANCE_RCS_DISTANCE_MAX := 500
##Distance past which RCS no longer plays audio.
const PERFORMANCE_RCS_AUDIO_DISTANCE_MAX := 500
##Distance from target beyond which the performance level is increased.
##higher levels mean the missile calculates trajectories less often.
const PERFORMANCE_POLL_DISTANCE := 400
##Distance from target beyond which performance level is increased again.
const PERFORMANCE_POLL_DISTANCE_FAR := 800
##instance count beyond which performance level is increased.
const PERFORMANCE_POLL_INSTANCE_COUNT := 40
##instance count beyond which performance level is increased again.
const PERFORMANCE_POLL_INSTANCE_COUNT_FAR := 70
##instance count beyond which performance level is increased more.
const PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME := 100
const PERFORMANCE_MESH_INSTANCE_COUNT := 200
##whether RCS is disabled for performance reasons.
var performance_RCS_disabled := false
#endregion

##ID of this missile if it has RCS. Higher = more RCS missiles existed at spawn time.
var RCS_this_id := 0
##ID of this missile. Higher = more missiles existed at spawn time.
var this_id := 0

@export_category("Debug")
##Prevents RCS from hiding for cosmetic or debug reasons.
@export var show_all_thrusters := false
##Disables fuel timer. Does not apply to dumbfire missiles, as they would fly forever.
@export var unlimited_fuel := false
##Disables all missile strafing. Without linear velocity damping, makes the missile uncontrollable.
@export var disable_strafe := false

#region track-homing
@export_category("Internode methods")
##Method attempted on the target when damage is dealt, emitted via direct method call. Expects one float damage argument and a Node3D argument for itself. Leave empty to ignore. (missile will not deal damage)
@export var method_deal_damage : StringName = &"TakeDamage"
##Signal Method attempted on the target when tracked, expects 1: Node3D that designates ID of the tracking missile; 2: tracking type of the missile (idk). I'll let you do handle this. Leave empty to ignore.
##the missile does not support signals for this, as only one target can be tracked at once.
@export var method_warn_target : StringName = &"warning_missile_track"
var target_can_be_warned := false

##Method attempted on the owner when launched, which updates what data about the missile the owner has. (Useful for semi-active missiles)
##Expects method to have args 1: Node3D = self ; 2: Node3D = target
@export var method_inform_owner : StringName = &"missile_inform"
var owner_can_be_informed : bool = false
##Variable that the missile searches on targets if armor piercing is used.
@export var variable_armor_hardness : StringName = &"armor_hardness"



@export_category("Missile Homing")
##Chase modes.
enum chasemodes {
	PURSUIT,              ##Goes after the target's current position irrespective of its velocity. Easier to evade.
	PROPORTIONAL_NAVIGATION ##Keeps a constant bearing relative to the target, hitting the future position of the target.
}
##How the missile will pursue targets.
@export var chase_mode : chasemodes = chasemodes.PURSUIT
##Current pursue mode. PN doesn't always use PN tracking (e.g. when the missile isn't facing the target).
var current_chase_mode : chasemodes = chase_mode

@export_category("Missile Tracking")
##How the missile tracks targets. Doesn't do anything on its own.
enum trackmodes {
	PASSIVE_INFRARED,       ##Chases based on the heat signature of the target.
	PASSIVE_CROSSFIRE,      ##Chases using built-in pattern recognition.
	PASSIVE_ANTI_RADIATION, ##Chases based on radar emissions emitted by the target.
	SEMI_ACTIVE_LASER,      ##Chases based on laser targets provided by the mothership.
	SEMI_ACTIVE_RADAR,      ##Chases based on radar data supplied from the mothership.
	ACTIVE_RADAR,           ##Chases based on radar data from a built-in radar.
}
@export var track_mode : trackmodes = trackmodes.PASSIVE_INFRARED
##Whether the missile will lose the target if it faces away.
@export var must_face_target : bool = false
##cos of the angle in rads before the missile loses its tracking.
@export var max_angle_from_target : float = cos(deg_to_rad(60))
#endregion
#region Nodes
@onready var Thrust_forward   : Missile_thruster = $ThrustEffect
@onready var Thrust_right     : Missile_thruster = $ThrustEffect6
@onready var Thrust_left      : Missile_thruster = $ThrustEffect7
@onready var Thrust_up        : Missile_thruster = $ThrustEffect5
@onready var Thrust_down      : Missile_thruster = $ThrustEffect2
@onready var Thrust_left_aft  : Missile_thruster = $ThrustEffect8
@onready var Thrust_right_aft : Missile_thruster = $ThrustEffect9
@onready var Thrust_up_aft    : Missile_thruster = $ThrustEffect4
@onready var Thrust_down_aft  : Missile_thruster = $ThrustEffect3
@onready var textmesh : MeshInstance3D = $Text_008
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
var all_thrusters       : Array[Missile_thruster]
var active_thrusters    : Array[bool] = [false,false,false,false,false,false,false,false,false]
var thruster_to_activate: Array[bool] = [false,false,false,false,false,false,false,false,false]

##ShapeCast that detects objects. Faces missile attitude, length = distance traveled per frame.
@onready var collision_check  : ShapeCast3D           = $impactcheck
##Audio for main thrust.
@onready var audio_main_thrust: AudioStreamPlayer3D = $MAINTHRUST
##Audio for RCS effects. Has polyphony.
@onready var audio_RCS        : AudioStreamPlayer3D = $RCS
##Whether the missile is expecting to play RCS audio this frame.
var RCS_audio_queued := false
#endregion

#region specs
@export_category("Missile Specifications")
##Speed when launched from ship. An impulse of n * mass newtons is applied in -Z (forward) on spawn.
@export var launch_speed       : float = 10.0
var velocity_inherited : Vector3 = Vector3.ZERO
##Time before the missile starts maneuvering.
@export var launch_clear_time  : float = 0.5
##Time during which the missile cannot collide with its owner.
@export var arm_time           : float = 2.0
##If the missile is allowed to rotate and strafe
var can_maneuver := false
##If the missile is allowed to detonate.
var armed        := false
##Max forward speed. If the missile exceeds this along its forward axis, it slows down.
@export var max_straight_line_speed : float = 1000
##Agility: max sideways acceleration of the missile.
@export var linear_agility     : float = 75.0
##Forward acceleration in m/s².
@export var forward_acceleration: float = 120.0
##Angular agility: how much angular torque the missile can produce.
@export var angular_agility    : float = PI * 2
##Time in seconds before the missile depletes its fuel.
@export var thrust_time        : float = 10.0
##When the fuel timer runs out, should the missile explode?
@export var explode_on_fuel_loss := false
##Theoretical health of the missile. If below, forces disable / detonation.
@export var health := 30.0
#endregion

#region damage
@export_category("Missile Damage")
##Base damage of the missile.
@export var base_damage := 60
##damage after computing falloff and other stuff.
var final_damage : int
##Armor penetration of the missile. I don't know how to implement something with this yet, but it's here just in case. SET TO -1 TO DISABLE 
@export var armor_piercing := 60
##AP after computing falloff.
var final_armor_piercing : int
##Types of warheads.
enum warheadtypes {
	DIRECT_WARHEAD, ##Missile only deals damage through a tough warhead. No proximity fuse. (Only direct hits)
	PROXIMITY_WARHEAD, ##Missile uses strong explosives with shrapnel to damage ships with proximity detonation (Favor Proximity, maybe less pen)
	HYBRID_WARHEAD, ##Missile uses a hybrid of small explosives with a mostly tough shell. This penetrates less but can explode via proximity and explode on direct hits (even hull breach!!)
	TANDEM_WARHEAD ##Missile with a tandem-shaped-charge, bypassing reactive armor. The shaped charge could allow exceptional penetration, but it's probably not as visceral as a big boom.
	##Also, proximity fuses are off the table.
}

##The type of warhead on the missile. Purely for descriptor purposes.
@export var warhead_type : warheadtypes = warheadtypes.HYBRID_WARHEAD
##How much of the missile's damage is kinetic. the other part is considered explosive.
@export var damage_type_kinetic_chemical_percentage : float = 0.5
enum proximity {
	AUTO,
	FORCE_ENABLE, 
	FORCE_DISABLE
}
##How to set Proximity fuse. Disabling it increases performance ever so slightly.
@export var proximity_fuse_mode : proximity = proximity.AUTO
##Whether the Proximity fuze should only detonate if the target is close enough.
@export var proximity_fuse_only_target : bool = true
##Proximity enabled.
var proximity_enabled : bool = false
##Proximity fuse distance
@export var proximity_fuse_radius : float = 5.0
##Damage multiplier for when the missile strikes a direct hit.
@export var damage_hit_multiplier_direct := 1.0
##Damage multiplier for when the missile strikes via proximity fuse.
@export var damage_hit_multiplier_proximity := 1.0
##Penetration multiplier for direct hits.
@export var armor_penetration_multiplier_direct := 1.0
##Penetration multiplier for proximity hits.
@export var armor_penetration_multiplier_proximity := 1.0
##How much damage should falloff with speed; 0 is immobile, 1 is max speed. If left empty, no falloff is calculated.
@export var damage_falloff_speed : Curve
##How much AP falls off with speed; 0 is immobile, 1 is max speed. If left empty, no falloff is calculated.
@export var armor_penetration_falloff_speed : Curve
##How much damage should falloff with distance from the launcher, set range to whatever distance needed. If left empty, no falloff is calculated.
@export var damage_falloff_distance : Curve

var fuse_build := false
var fuse_shape :CylinderShape3D
var fuse_sphere :PhysicsShapeQueryParameters3D
#endregion
#region Audio Visual
@export_category("Visual Parameters")
##Whether the missile's mesh should expand with distance for visual consistency.
@export var expand_mesh_with_distance := true
##Disables all visual and auditive RCS features. Does not disable strafing.
@export var hide_RCS    := false
var RCS_deleted := false
##Hides vapor trail. Slight performance boost in dense scenes.
@export var hide_trail  := false
##Hides particles. Slight performance boost.
@export var hide_particles := false


@export_category("Audio Parameters")
##Volume variation in dB of the main thrusters.
@export var main_thrust_volume_db  : float = 0.0
##Pitch variation of the main thrusters.
@export var main_thrust_pitch_scale: float = 1.0
##Volume in dB of RCS.
@export var thrust_volume_db  : float = 0.0
##Pitch scale of RCS thrusters.
@export var thrust_pitch_scale: float = 1.0
##Volume variation of explosions.
@export var explosion_volume_db: float = 0.0
##Volume variation for ALL sounds on this node.
@export var master_effect_volume_db: float = 0.0
#endregion
#region Targetting
@export_category("Target")
##Debug target. Best assigned via script in real implementations.
@export var target    : Node3D
##Ship that owns this missile.
var owner_ship        : Node3D

##Where the missile needs to go (not necessarily where the target entity is).
var target_position   := Vector3.ZERO
##PN intercept aim point. Separate from target_position since PN uses a different algorithm.
var PN_aim_point      := Vector3.ZERO
##Speed of the target entity.
var target_velocity   := Vector3.ZERO
##Whether the missile is facing the target.
var is_facing_target  : bool = false
##If there is no target, this is true. Turns the missile into a dumbfire rocket.
var no_target         := true
##Set to true on collision.
var hit_target        := false
#endregion
#region performance and cache
##Physics tick counter, increments each physics frame.
var tick_avionics     := 0
##0 = highest fidelity, higher = less frequent avionics updates.
var performance_level := 0
##Tick ratios for avionics computation. Index = performance level, value = compute every n frames.
@export var avionic_tick_ratios: Array[int] = [1,2,3,4,5]
##Compute avionics every n-th physics frame.
var current_avionic_tick_ratio := 1

##Cached inverse basis, recomputed once per avionics tick that uses it.
var _cached_inv_basis : Basis
##Cached distance to target, recomputed in compute_tick_avionics_ratio.
var _cached_dist_to_target : float = 0.0
##Cached aim point (PURSUIT or PN depending on current_chase_mode).
var _aim_point : Vector3 = Vector3.ZERO
##Cached distance from the camera, so you odn't have to calculate 10 times a frame.
var cached_camera_distance : float = 0.0
var fuse_basis_offset : Basis 

#endregion

func _ready() -> void:
	if hide_particles:
		$TrailBoom.amount_ratio = 0
	if hide_trail:
		$VaporTrail.num_points = 1
		$VaporTrail.update_interval = 100
	max_straight_line_speed = max_straight_line_speed * max_straight_line_speed
	instance_count += 1
	this_id = instance_count
	if this_id > float(PERFORMANCE_MESH_INSTANCE_COUNT) / 100:
		textmesh.queue_free()
	
	if target and target.has_method(method_warn_target):
		target_can_be_warned = true
	if owner_ship and owner_ship.has_method(method_inform_owner):
		owner_can_be_informed = true
	

	all_thrusters.assign([
		Thrust_forward,
		Thrust_down, Thrust_down_aft,
		Thrust_left,  Thrust_left_aft,
		Thrust_right, Thrust_right_aft,
		Thrust_up,    Thrust_up_aft,
	])

	#prepare all RCS
	for x: Missile_thruster in all_thrusters:
		if x.animation_start() != Error.OK:
			push_error(self, " failed to start thruster animation on ", x)
		if !show_all_thrusters:
			x.ide()

	if hide_RCS:
		for x: Missile_thruster in all_thrusters:
			if !x.constant_thrust:
				x.queue_free()
		var keep: Array[Missile_thruster] = []
		for t: Missile_thruster in all_thrusters:
			if t.constant_thrust:
				keep.append(t)
		all_thrusters = keep
		RCS_deleted = true
	
	var show_rcs_later := false
	if !hide_RCS:
		RCS_instance_count += 1
		RCS_this_id = RCS_instance_count
		show_rcs_later = true
		hide_RCS = true
		
	audio_RCS.volume_db       = thrust_volume_db
	audio_RCS.pitch_scale    *= thrust_pitch_scale
	audio_main_thrust.pitch_scale *= main_thrust_pitch_scale
	audio_main_thrust.volume_db   = main_thrust_volume_db
	$explosion.volume_db      = explosion_volume_db

	angular_agility      *= randf_range(0.9, 1.1)
	linear_agility       *= randf_range(0.9, 1.1)
	forward_acceleration *= randf_range(0.9, 1.1)
	launch_clear_time    *= randf_range(0.6, 1.0)
	launch_speed         *= randf_range(0.9, 1.1)
	
	
	
	await get_tree().physics_frame
	apply_central_impulse(((basis * Vector3.FORWARD * launch_speed) + velocity_inherited) * mass)
	await get_tree().create_timer(launch_clear_time).timeout
	can_maneuver = true
	hide_RCS = !show_rcs_later
	await get_tree().create_timer(max(0.1, arm_time - launch_clear_time)).timeout
	armed = true
	_ready_proximity_fuse()

func _ready_proximity_fuse() -> void:
	match proximity_fuse_mode:
		proximity.FORCE_ENABLE: 
			proximity_enabled = true
			proximity_fuse_mode = proximity.FORCE_ENABLE
		proximity.FORCE_DISABLE: 
			proximity_enabled = false
			proximity_fuse_mode = proximity.FORCE_DISABLE
			return
		_:
			match warhead_type:
				warheadtypes.DIRECT_WARHEAD:
					proximity_enabled = false
					proximity_fuse_mode = proximity.FORCE_DISABLE
					return
				_:
					proximity_enabled = true
					proximity_fuse_mode = proximity.FORCE_ENABLE
	if !proximity_enabled:
		return
	fuse_shape = CylinderShape3D.new()
	fuse_shape.radius = proximity_fuse_radius
	fuse_shape.height = 5.0
	
	fuse_sphere = PhysicsShapeQueryParameters3D.new()
	fuse_sphere.shape = fuse_shape
	fuse_sphere.transform = global_transform.rotated_local(Vector3.RIGHT, PI / 2)
	fuse_basis_offset = Basis(Vector3.RIGHT, PI / 2)
	fuse_sphere.exclude = [self]

##Call with the missile host. Initates the new target.
func ready_launch_parameters(ship_who_launched_the_missile : Node3D, initial_velocity: Vector3, initial_target : Node3D = null) -> Error:
	velocity_inherited = initial_velocity
	owner_ship = ship_who_launched_the_missile
	if !initial_target: 
		no_target = true
		return OK
	no_target = false
	target = initial_target
	
	return OK


func _physics_process(delta: float) -> void:
	tick_avionics += 1
	RCS_audio_queued = false
	thrust_time -= delta
	
	if tick_avionics % 15 == 0:
		global_performance_level = -1
		_compute_tick_avionics_ratio()
		_allow_RCS()
		_missile_LOD()
		if target_can_be_warned:
			target.call(method_warn_target, self, track_mode)
		#print(performance_level)
	if tick_avionics % 6 == 0:
		_compute_damage_and_penetration()
	if thrust_time <= 0 and (!unlimited_fuel or no_target):
		_on_fuel_depleted()
		return

	if tick_avionics % current_avionic_tick_ratio == 0:
		_cached_inv_basis = basis.inverse()
		_compute_target_position(delta)
		_compute_thrust()
		_compute_rotation_thrust()
		
	if (tick_avionics + 1) % (min(current_avionic_tick_ratio + 1, 3)) == 0:
		_compute_proximity_fuse()
		#print("computing fuse")
	

	_missile_thruster_set_visibility()
	_rcs_audio()

	collision_check.target_position = collision_check.to_local(linear_velocity) * delta 
	#$"missile final_001".scale = max(1.0, _distance_to_cam()) * 0.01 * Vector3.ONE + Vector3.ONE

func _internode_data() -> void:
	if target_can_be_warned:
		target.call(method_warn_target, self, track_mode)
	if owner_can_be_informed:
		owner_ship.call(method_inform_owner, self, target)
	

##Handles fuel depletion: frees thrusters, explodes or drifts based on settings.
func _on_fuel_depleted() -> void:
	for x : Missile_thruster in all_thrusters:
		x.queue_free()
	$MAINTHRUST.stop()
	if explode_on_fuel_loss:
		_missile_impact_single(self, global_position)
	else:
		set_physics_process(false)
		await get_tree().create_timer(10.0).timeout
		queue_free()


##Returns the current aim point based on chase mode.
func _get_aim_point() -> Vector3:
	if current_chase_mode == chasemodes.PROPORTIONAL_NAVIGATION:
		return PN_aim_point
	return target_position


##Computes how the missile should strafe relative to the target. Decides based on chase mode.
func _compute_thrust() -> void:
	if no_target or !can_maneuver:
		_missile_thrust(Vector3.FORWARD, true)
		return

	match chase_mode:
		chasemodes.PURSUIT:
			current_chase_mode = chasemodes.PURSUIT
		chasemodes.PROPORTIONAL_NAVIGATION:
			if is_facing_target:
				current_chase_mode = chasemodes.PROPORTIONAL_NAVIGATION
				_compute_pn_intercept_point()
			else:
				current_chase_mode = chasemodes.PURSUIT

	## Update aim point after PN intercept is computed (if applicable).
	_aim_point = _get_aim_point()
	_compute_strafe_thrust()


##Computes which local thrust axes to activate to cancel all lateral drift.
func _compute_strafe_thrust() -> void:
	var local_velocity: Vector3 = _cached_inv_basis * linear_velocity
	var final_thrust := Vector3.ZERO
	# only correct X and Y axes (lateral drift), Z handled separately in missile_thrust
	for axis: int in range(2):
		final_thrust[axis] = -sign(local_velocity[axis])

	var _hide: bool = Vector2(local_velocity.x, local_velocity.y).length() < 2.0
	_missile_thrust(final_thrust, true, _hide)


##Computes the necessary rotation forces to face the desired direction.
func _compute_rotation_thrust() -> void:
	if no_target or !can_maneuver:
		return

	var rotation_error : Vector3 = get_rotation_error()
	var error_angle    : float   = rotation_error.length()

	## If nearly facing the target, snap smoothly to it.
	if error_angle < 0.1:
		var look_dir: Vector3 = (_aim_point - global_position).normalized()
		var up      : Vector3 = basis.y

		if abs(look_dir.dot(up)) > 0.99:
			up = basis.x

		var to_target_quat: Quaternion = Basis.looking_at(look_dir, up).get_rotation_quaternion()
		_missile_force_rotation(to_target_quat)
		return

	var rotation_axis   : Vector3 = rotation_error / error_angle
	var spin_towards    : float   = angular_velocity.dot(rotation_axis)
	var angle_to_stop   : float   = (spin_towards * spin_towards) / (2.0 * angular_agility)

	var final_torque: Vector3
	if angle_to_stop >= error_angle and spin_towards > 0.0:
		final_torque = -rotation_axis
	else:
		final_torque = rotation_axis

	var _hide := final_torque.length() < 0.2
	_missile_rotation(final_torque, false, false, _hide)


##Updates target position, target velocity, and whether the missile is facing the target.
func _compute_target_position(_delta: float) -> void:
	if !target:
		no_target = true
		return
	no_target = false
	target_position = target.global_position
	target_velocity = Vector3.ZERO

	if target is CharacterBody3D:
		target_velocity = (target as CharacterBody3D).velocity
	elif target is RigidBody3D:
		target_velocity = (target as RigidBody3D).linear_velocity

	is_facing_target = get_position_error().normalized().dot(linear_velocity.normalized()) > 0.1
	if must_face_target and (-global_basis.z).dot(target_position) <= 0.0:
		#print(linear_velocity.dot(target_position) <= 0.0, " failed to track, not facing way")
		target = null
		no_target = true

##Computes the PN intercept point: where the target will be when the missile arrives.
func _compute_pn_intercept_point() -> void:
	var los            : Vector3 = target_position - global_position
	var range_to_target: float   = los.length()
	if range_to_target < 2.0:
		PN_aim_point = target_position
		return

	var relative_velocity: Vector3 = target_velocity - linear_velocity
	var closing_speed    : float   = -relative_velocity.dot(los / range_to_target)
	if closing_speed <= 0.0:
		PN_aim_point = target_position  ## not closing — just face the target
		return

	var time_to_intercept: float = range_to_target / closing_speed
	PN_aim_point = target_position + target_velocity * time_to_intercept

##Calculates, based on what's enabled and not, the final damage and piercing values.
func _compute_damage_and_penetration() -> void:
	var sub_final_damage : float = base_damage
	var velocity : float
	if damage_falloff_speed:
		velocity = linear_velocity.length()
		sub_final_damage *= damage_falloff_speed.sample(velocity/ max_straight_line_speed )
	if damage_falloff_distance:
		sub_final_damage *= damage_falloff_distance.sample(global_position.distance_to(owner_ship.global_position))
	final_damage = round(sub_final_damage)
	
	var sub_final_pen : float = armor_piercing
	if armor_penetration_falloff_speed:
		if !velocity:
			velocity = linear_velocity.length()
		sub_final_pen *= armor_penetration_falloff_speed.sample(velocity / max_straight_line_speed)
		
	final_armor_piercing = round(sub_final_pen)



##Checks if anything is in the proximity fuze's radius. Acts accordingly
func _compute_proximity_fuse() -> void:
	if !proximity_enabled or !armed:
		return
	fuse_sphere.transform = Transform3D(global_transform.basis * fuse_basis_offset, global_transform.origin)
	var hits = get_world_3d().direct_space_state.intersect_shape(fuse_sphere, 10)
	if hits.size() == 0:
		return
	#print(hits)
	if proximity_fuse_only_target:
		for hit in hits:
			if target == hit.collider:
				
				if collision_check.check_hit(2.0):
					return
				_missile_impact_single(target, global_position, true)
				return
		return
	else:
		var hitt : Array[Node3D] = []
		for hit in hits:
			if hit.collider in hitt:
				continue
			if target == hit.collider:
				if collision_check.check_hit(2.0):
					return
			hitt.append(hit.collider)
			
		_missile_impact_multiple(hitt, global_position, true)
	
##Checks if the missile is facing towards the target node (default is target) within the specified angle in rads. (angle from target vector and missile facing vector.)
func is_in_front_of_missile(node: Node3D = target, max_angle : float = max_angle_from_target) -> bool:
	if !node:
		return false
	var to_target = (node.global_position - global_position).normalized()
	var forward = -global_transform.basis.z
	if max_angle != max_angle_from_target:
		max_angle = cos(max_angle)
	return forward.dot(to_target) > max_angle

##Checks if the missile's velocity is towards the specified node, defaults to the target. Set max angle in radians (converted to cos) (angle from target vector and missile facing vector.)
func is_moving_to_target(node: Node3D = target, max_angle : float = 0.5) -> bool:
	if !node: 
		return false
	var to_target = (node.global_position - global_position).normalized()
	var forward = linear_velocity.normalized()
	if max_angle != 0.5:
		max_angle = cos(max_angle)
	return forward.dot(to_target) > max_angle
	

##Returns a vector pointing from the missile to the target.
func get_position_error() -> Vector3:
	return target_position - global_position


##Returns the rotation axis*angle needed to align missile forward with the aim point.
func get_rotation_error() -> Vector3:
	if !target or linear_velocity.length_squared() < 1.0:
		return Vector3.ZERO

	var desired_forward: Vector3 = (_aim_point - global_position).normalized()
	var current_forward: Vector3 = -global_transform.basis.z
	var dot            : float   = current_forward.dot(desired_forward)

	## Degenerate case: nearly antiparallel — pick any perpendicular axis.
	if dot < -0.9999:
		var fallback: Vector3 = current_forward.cross(Vector3.UP)
		if fallback.length_squared() < 0.001:
			fallback = current_forward.cross(Vector3.RIGHT)
		return fallback.normalized() * PI

	var rotation_diff: Quaternion = Quaternion(current_forward, desired_forward)
	return rotation_diff.get_axis() * rotation_diff.get_angle()


##Applies thruster visibility changes only when state actually changed.
##thruster_to_activate is always reset here so stale flags don't persist across avionics ticks.
func _missile_thruster_set_visibility() -> void:
	if hide_RCS or RCS_deleted:
		return
	for i: int in all_thrusters.size():
		if thruster_to_activate[i] == active_thrusters[i]:
			continue
		if thruster_to_activate[i]:
			all_thrusters[i].how()
		else:
			all_thrusters[i].ide()
		active_thrusters[i] = thruster_to_activate[i]

	thruster_to_activate.fill(false)


##Applies physics forces based on the supplied direction. Also flags which RCS thrusters to show.
##Uses _cached_inv_basis — must be updated before calling.
func _missile_thrust(direction: Vector3 = Vector3.ZERO, reset: bool = false, _hide: bool = false) -> void:
	if reset:
		thruster_to_activate.fill(false)

	## Z: only allow braking (clamp to [-1,0]), then force forward thrust.
	direction.z = -1.0

	if disable_strafe:
		direction.x = 0.0
		direction.y = 0.0

	if !_hide and !hide_RCS and !performance_RCS_disabled:
		match sign(direction.x):
			1.0:
				thruster_to_activate[thrusters.RIGHT]     = true
				thruster_to_activate[thrusters.RIGHT_AFT] = true
			-1.0:
				thruster_to_activate[thrusters.LEFT]      = true
				thruster_to_activate[thrusters.LEFT_AFT]  = true

		match sign(direction.y):
			1.0:
				thruster_to_activate[thrusters.UP]        = true
				thruster_to_activate[thrusters.UP_AFT]    = true
			-1.0:
				thruster_to_activate[thrusters.DOWN]      = true
				thruster_to_activate[thrusters.DOWN_AFT]  = true

	if !_hide:
		RCS_audio_queued = true

	thruster_to_activate[thrusters.FORWARD] = true

	if linear_velocity.length_squared() > max_straight_line_speed:
		direction.z = 0.0

	apply_central_force(basis * (direction * mass * Vector3(linear_agility, linear_agility, forward_acceleration) * current_avionic_tick_ratio))


##Snaps the missile toward the supplied quaternion via slerp.
func _missile_force_rotation(face: Quaternion, weight: float = 20.0) -> void:
	var current_rotation: Quaternion = basis.get_rotation_quaternion().normalized()
	current_rotation = current_rotation.slerp(face, 0.5 * get_physics_process_delta_time() * weight)
	basis = Basis(current_rotation)


##Applies torque based on the supplied rotation direction. Also flags which RCS thrusters to show.
func _missile_rotation(direction: Vector3 = Vector3.ZERO, reset: bool = true, visual_only: bool = false, _hide: bool = false) -> void:
	if reset:
		thruster_to_activate.fill(false)

	direction = _cached_inv_basis * direction
	var temporary_multiplier := 0.5 if direction.length() < deg_to_rad(15) else 1.0

	if !_hide and !hide_RCS and !performance_RCS_disabled:
		match sign(direction.x):
			1.0:
				thruster_to_activate[thrusters.UP]       = true
				thruster_to_activate[thrusters.DOWN_AFT]  = true
				thruster_to_activate[thrusters.DOWN]      = false
			-1.0:
				thruster_to_activate[thrusters.DOWN]     = true
				thruster_to_activate[thrusters.UP_AFT]   = true
				thruster_to_activate[thrusters.UP]        = false

		match sign(direction.y):
			1.0:
				thruster_to_activate[thrusters.LEFT]      = true
				thruster_to_activate[thrusters.RIGHT_AFT] = true
				thruster_to_activate[thrusters.RIGHT]     = false
			-1.0:
				thruster_to_activate[thrusters.RIGHT]     = true
				thruster_to_activate[thrusters.LEFT_AFT]  = true
				thruster_to_activate[thrusters.LEFT]      = false

	if !_hide:
		RCS_audio_queued = true

	if visual_only:
		return

	apply_torque(basis * direction * angular_agility * temporary_multiplier * current_avionic_tick_ratio)

func _missile_impact_single(collider : Node3D, location : Vector3 = global_position, is_proximity : bool = false) -> void:
	var array : Array[Node3D]
	array.append(collider)
	_missile_impact_multiple(array, location, is_proximity)
##Logic for what happens when the missile collides with something.
func _missile_impact_multiple(colliders: Array[Node3D], location : Vector3 = global_position, is_proximity : bool = false) -> void:
	if hit_target:
		return
	elif !armed:
		return
	elif !colliders or colliders.is_empty():
		return
	set_physics_process(false)
	hit_target = true
	thrust_time = -1
	exploding_missiles += 1
	freeze = true
	#print("HIT!!!")
	if !is_proximity:
		for x in colliders:
			_damage_ship(x)
		$TrailBoom.local_coords = true
		global_position = location
		if performance_level <= 2 or exploding_missiles < 50:
			$impact.emitting = !hide_particles
			$Backboom.emitting = !hide_particles
			$TrailBoom.emitting = !hide_particles
		else:
			push_warning("high performance or high explosion count, cancelling explosion.")
			$impact.queue_free()
			
		begin_countdown.emit(colliders[0])
	else:
		for x in colliders:
			_damage_ship(x)
		$TrailBoom.reparent_to_root = true
		$TrailBoom.time = 1.0
		if performance_level <= 2 or exploding_missiles < 50:
			$Proximityboom.emitting = !hide_particles
		begin_countdown.emit(null)
	
	$explosion.play()
	
	#free stuff
	for x : Missile_thruster in all_thrusters:
		if !x:
			continue
		if x.constant_thrust:
			x.shutdown()
		x.queue_free()
	audio_main_thrust.queue_free()
	audio_RCS.queue_free()
	$LOD.queue_free()
	$"missile final_001".queue_free()
	if textmesh: textmesh.queue_free()
	$impactcheck.queue_free()
	
	
	await get_tree().create_timer(1.5).timeout
	queue_free()

##Deals X damage to the missile.
func take_damage(damage : float) -> void:
	health -= damage
	if health <= 0:
		_missile_impact_single(self, global_position, true)
	
##Deals X damage to the missile.
func TakeDamage(damage: float) -> void:
	take_damage(damage)

##Deals damage to the ship.
func _damage_ship(collider: Node3D) -> void:
	#print("attempting to deal damage to collider.")
	var armor_hardness : float = 1.0
	var final_final_damage :float = final_damage

	if armor_piercing > 0:
		var collider_hard = collider.get(variable_armor_hardness)

		
		#Deal damage based off hardness if the target has it.
		if collider_hard:
			armor_hardness = collider.armor_hardness
			final_final_damage = final_final_damage * (armor_piercing/armor_hardness)
			print("final damage is ", final_final_damage)
	if collider.has_method(method_deal_damage):
		collider.call(method_deal_damage, final_final_damage, self)
	else:
		push_warning("Failed to find method ", method_deal_damage, " on collider. Is the correct one specified?")

func _missile_LOD() -> void:
	var dist_cam := _distance_to_cam()
	var far      := dist_cam > PERFORMANCE_POLL_DISTANCE_FAR
	$"missile final_001".visible = !far
	if textmesh: textmesh.visible= !far
	$LOD.visible                 = far
	#$TrailBoom.emitting          = !far
	proximity_enabled = dist_cam < 200 if proximity_fuse_mode != proximity.FORCE_DISABLE else false
	var too_much := instance_count > PERFORMANCE_MESH_INSTANCE_COUNT
	#$"missile final_001".visible = !too_much
	#if textmesh: textmesh.visible = !too_much
	#$LOD.visible = !too_much
	#if instance_count > PERFORMANCE_POLL_INSTANCE_COUNT and this_id > PERFORMANCE_POLL_INSTANCE_COUNT:
		#$TrailBoom.emitting = false
	
	#permanently removes RCS if there are too many.
	if RCS_this_id > PERFORMANCE_POLL_INSTANCE_COUNT:
		if RCS_deleted:
			return
		for x in all_thrusters:
			if !x.constant_thrust:
				x.queue_free()
		var keep: Array[Missile_thruster] = []
		for t: Missile_thruster in all_thrusters:
			if t.constant_thrust:
				keep.append(t)
		all_thrusters = keep
		hide_RCS = true
		RCS_deleted = true
		
	
	
	$VaporTrail.visible = (not (
		instance_count > PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME + 50
		and this_id > PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME
	)) or !too_much


##Plays RCS audio if conditions allow (distance, instance count, audio queued).
func _rcs_audio() -> void:
	if hide_RCS or !RCS_audio_queued:
		return
	RCS_audio_queued = false
	if randi_range(0, 2) != 0:
		return
	var dist := _distance_to_cam()
	if (RCS_instance_count > 20 and RCS_this_id > 20 and dist > 50) or dist > PERFORMANCE_RCS_AUDIO_DISTANCE_MAX:
		return
	audio_RCS.play()


##Returns the distance from the missile to the target.
func _distance_to_target() -> float:
	return _cached_dist_to_target

var cached_distance := false
##Returns the distance to the active camera for the viewport. Cached once per physics frame.
func _distance_to_cam() -> float:
	if cached_distance:
		return cached_camera_distance
	var current_frame := Engine.get_physics_frames()
	if !cached_camera or cached_camera_frame != current_frame:
		cached_camera       = get_viewport().get_camera_3d()
		cached_camera_frame = current_frame
	cached_distance = false
	cached_camera_distance = global_position.distance_to(cached_camera.global_position)
	return cached_camera_distance


##Calculates performance level and avionics tick ratio for this missile instance.
func _compute_tick_avionics_ratio() -> void:
	_cached_dist_to_target = target_position.distance_to(global_position)
	var distance           := _cached_dist_to_target
	#print(distance)
	var new_performance_level: int
	if distance < PERFORMANCE_POLL_DISTANCE or !armed:
		new_performance_level = 0
	elif distance < PERFORMANCE_POLL_DISTANCE_FAR:
		new_performance_level = 1
	else:
		new_performance_level = 2
	
	

	## global_performance_level is computed once per 15-tick block, shared across all missiles.
	if global_performance_level == -1:
		if instance_count < PERFORMANCE_POLL_INSTANCE_COUNT:
			global_performance_level = 0
		elif instance_count < PERFORMANCE_POLL_INSTANCE_COUNT_FAR:
			global_performance_level = 1
		elif instance_count < PERFORMANCE_POLL_INSTANCE_COUNT_EXTREME:
			global_performance_level = 2
		else:
			global_performance_level = 3

	performance_level = clampi(
	new_performance_level + global_performance_level,
	0,
	avionic_tick_ratios.size() - 1
	)
	current_avionic_tick_ratio = avionic_tick_ratios[performance_level]


##Disables RCS visuals/audio when too many missiles are on screen or missile is too far.
func _allow_RCS() -> void:
	performance_RCS_disabled = (
		RCS_instance_count > PERFORMANCE_RCS_MAX_INSTANCES
		or _distance_to_cam() > PERFORMANCE_RCS_DISTANCE_MAX
	)
	


##Called when the ShapeCast detects a body.
func _on_impactcheck_body_hit(collider: Node3D, location : Vector3) -> void:
	_missile_impact_single(collider, location)
	#print("HIT")


##Called when the RigidBody itself enters a body (backup collision path).
func _on_body_entered(body: Node) -> void:
	_missile_impact_single(body as Node3D, body.global_position)

func _on_proximityfuze_body_entered(body: Node3D) -> void:
	_missile_impact_single(body, body.global_position, true)

func _exit_tree() -> void:
	if hit_target:
		exploding_missiles -= 1
	instance_count -= 1
	if !hide_RCS:
		RCS_instance_count -= 1
