class_name Drone
extends CharacterBody3D

# Enemy drone with four states:
#   PATROL - wanders and scans the ground with a rotating cone
#   LOCKING - player spotted; tracks them for lock_duration seconds then dives
#   DIVING - charges at full speed in a fixed direction until hitting something
#   DEAD - plays death effect and removes itself

signal drone_died

# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------
enum State { PATROL, LOCKING, DIVING, DEAD }
var _state: State = State.PATROL

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export_group("Health")
@export var max_hits: int = 3

@export_group("Patrol")
@export var patrol_speed: float = 4.0
@export var wander_radius: float = 20.0
@export var arrival_threshold: float = 0.5
@export var patrol_hover_height: float = 8.0
@export var patrol_wait_min: float = 1.0
@export var patrol_wait_max: float = 3.0

@export_group("Detection")
@export var cam_rotate_speed: float = 60.0  # Degrees per second
@export var cam_wait_min: float = 0.8
@export var cam_wait_max: float = 2.0
@export var cone_half_angle: float = 15.0
@export var cone_fallback_length: float = 30.0  # Cone length when a ray hits nothing.
@export var lock_duration: float = 1.5

@export_group("Dive")
@export var dive_speed: float = 60.0

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _raycast_origin: Marker3D = $CameraPivot/RaycastOrigin
@onready var _cone_visual: MeshInstance3D = $ConeVisual
@onready var _health_bar: ProgressBar = $SubViewport/ProgressBar

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _spawn_position: Vector3
var _hits_taken: int = 0

var _patrol_target: Vector3
var _patrol_waiting: bool = false
var _patrol_wait_timer: float = 0.0

var _cam_target_basis: Basis = Basis.IDENTITY
var _cam_wait_timer: float = 0.0
var _cam_is_waiting: bool = false

var _cone_mesh: ImmediateMesh
var _cone_mat: StandardMaterial3D

var _lock_timer: float = 0.0
var _locked_player: Node3D = null

var _dive_direction: Vector3 = Vector3.ZERO

var _player: Node3D = null

# SEGMENTS rays are fired along the cone edge each frame.
# _ring_hits is shared by detection and _draw_cone so no ray is cast twice.
const SEGMENTS := 32
var _ring_hits: Array[Vector3] = []
var _player_detected: bool = false


# ---------------------------------------------------------------------------
func _ready() -> void:
	_health_bar.max_value = max_hits
	_health_bar.value = max_hits
	
	_spawn_position = global_position
	_patrol_target = _pick_patrol_target()
	
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	
	_cone_mesh = ImmediateMesh.new()
	_cone_visual.mesh = _cone_mesh
	
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.vertex_color_use_as_albedo = true
	
	_pick_new_cam_target()


# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	velocity.y = 0.0
	
	match _state:
		State.PATROL:
			_update_patrol(delta)
			_update_camera_scan(delta)
			_update_detection()
		State.LOCKING:
			_update_locking(delta)
			_update_detection()  # Keeps _ring_hits fresh so the cone follows the player.
		State.DIVING:
			_update_diving()
		State.DEAD:
			pass
	
	move_and_slide()
	
	if _state == State.DIVING and get_slide_collision_count() > 0:
		_die()
	
	_draw_cone()


# ---------------------------------------------------------------------------
# Patrol
# ---------------------------------------------------------------------------
func _update_patrol(delta: float) -> void:
	global_position.y = move_toward(global_position.y, patrol_hover_height, 5.0 * delta)
	
	if _patrol_waiting:
		velocity.x = 0.0
		velocity.z = 0.0
		_patrol_wait_timer -= delta
		if _patrol_wait_timer <= 0.0:
			_patrol_waiting = false
			_patrol_target  = _pick_patrol_target()
		return
	
	var flat_pos := Vector3(global_position.x, 0.0, global_position.z)
	var flat_target := Vector3(_patrol_target.x,  0.0, _patrol_target.z)
	var to_target := flat_target - flat_pos
	
	if to_target.length() < arrival_threshold:
		velocity.x = 0.0
		velocity.z = 0.0
		_patrol_waiting = true
		_patrol_wait_timer = randf_range(patrol_wait_min, patrol_wait_max)
		return
	
	var dir := to_target.normalized()
	velocity.x = dir.x * patrol_speed
	velocity.z = dir.z * patrol_speed


func _pick_patrol_target() -> Vector3:
	var angle := randf() * TAU
	var radius := randf() * wander_radius
	return Vector3(
		_spawn_position.x + cos(angle) * radius,
		patrol_hover_height,
		_spawn_position.z + sin(angle) * radius
	)


# ---------------------------------------------------------------------------
# Camera scanning
# ---------------------------------------------------------------------------
func _update_camera_scan(delta: float) -> void:
	if _cam_is_waiting:
		_cam_wait_timer -= delta
		if _cam_wait_timer <= 0.0:
			_cam_is_waiting = false
			_pick_new_cam_target()
		return
	
	var t = clamp(deg_to_rad(cam_rotate_speed) * delta, 0.0, 1.0)
	_camera_pivot.transform.basis = _camera_pivot.transform.basis.slerp(_cam_target_basis, t)
	
	if _camera_pivot.transform.basis.z.dot(_cam_target_basis.z) > 0.9998:
		_cam_is_waiting = true
		_cam_wait_timer = randf_range(cam_wait_min, cam_wait_max)


func _pick_new_cam_target() -> void:
	# Tilt around world X first so -Z always points downward, then pan around world Y.
	# Reversing this order would cause the tilt axis to vary with pan, pointing the cone upward.
	var pan  := deg_to_rad(randf_range(0.0, 360.0))
	var tilt := deg_to_rad(randf_range(20.0, 80.0))
	
	var b := Basis.IDENTITY
	b = b.rotated(Vector3.LEFT, tilt)
	b = b.rotated(Vector3.UP, pan)
	_cam_target_basis = b


# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
func _update_detection() -> void:
	_player_detected = false
	_ring_hits.clear()
	
	var origin := _raycast_origin.global_position
	var forward := _get_cam_forward()
	var space := get_world_3d().direct_space_state
	
	var ref_up := Vector3.UP if abs(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := forward.cross(ref_up).normalized()
	var up := right.cross(forward).normalized()
	var half_rad := deg_to_rad(cone_half_angle)
	
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		var ray_dir := (forward + right * cos(angle) * tan(half_rad) + up * sin(angle) * tan(half_rad)).normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + ray_dir * 1000.0)
		query.exclude = [self]
		var result := space.intersect_ray(query)
		
		if result:
			_ring_hits.append(result.position)
			if _player and (result.collider == _player or result.collider.get_parent() == _player):
				_player_detected = true
		else:
			_ring_hits.append(origin + ray_dir * cone_fallback_length)
	
	if _player_detected:
		_begin_lock(_player)


func _get_cam_forward() -> Vector3:
	return -_camera_pivot.global_transform.basis.z


func _begin_lock(player: Node3D) -> void:
	_state = State.LOCKING
	_locked_player = player
	_lock_timer = lock_duration
	
	# Snap the pivot immediately so the cone visual reflects the lock with no delay.
	var to_target := (player.global_position - _camera_pivot.global_position).normalized()
	if abs(to_target.dot(Vector3.UP)) < 0.99:
		_camera_pivot.global_transform.basis = Basis.looking_at(to_target, Vector3.UP)


# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------
func _update_locking(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	if _locked_player:
		var target_pos := _locked_player.global_position
		var to_target  := (target_pos - _camera_pivot.global_position).normalized()
		if abs(to_target.dot(Vector3.UP)) < 0.99:
			var target_basis := Basis.looking_at(to_target, Vector3.UP)
			var t = clamp(deg_to_rad(cam_rotate_speed * 3.0) * delta, 0.0, 1.0)
			_camera_pivot.global_transform.basis = _camera_pivot.global_transform.basis.slerp(target_basis, t)
	
	_lock_timer -= delta
	if _lock_timer <= 0.0:
		_begin_dive()


func _begin_dive() -> void:
	if _locked_player == null:
		_state = State.PATROL
		return
	_dive_direction = (_locked_player.global_position - global_position).normalized()
	_locked_player = null
	_state = State.DIVING


# ---------------------------------------------------------------------------
# Diving
# ---------------------------------------------------------------------------
func _update_diving() -> void:
	velocity = _dive_direction * dive_speed


# ---------------------------------------------------------------------------
# Attackable
# ---------------------------------------------------------------------------
func take_hit() -> void:
	if _state == State.DEAD:
		return
	_hits_taken += 1
	_health_bar.value = max_hits - _hits_taken
	if _hits_taken >= max_hits:
		_die()
		_health_bar.hide()


# ---------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------
func _die() -> void:
	if _state == State.DEAD:
		return
	
	_state = State.DEAD
	velocity = Vector3.ZERO
	emit_signal("drone_died")
	
	# Detach particles before queue_free so the effect finishes playing.
	var particles: Node = get_node_or_null("GPUParticles3D")
	if particles:
		var parent := get_parent()
		remove_child(particles)
		parent.add_child(particles)
		particles.global_position = global_position
		particles.one_shot = true
		particles.emitting = true
		particles.finished.connect(particles.queue_free)
	else:
		push_warning("Drone: GPUParticles3D node not found on '%s'. No death particles will play." % name)
	
	queue_free()


# ---------------------------------------------------------------------------
# Cone visual
# ---------------------------------------------------------------------------
func _draw_cone() -> void:
	_cone_mesh.clear_surfaces()
	
	if _state == State.DEAD or _state == State.DIVING:
		return
	
	# _ring_hits is populated by _update_detection() every frame, no extra casts needed.
	var ring_world: Array[Vector3] = _ring_hits
	
	var cone_color: Color
	match _state:
		State.PATROL:
			cone_color = Color(0.2, 1.0, 0.3, 0.18)
		State.LOCKING:
			# Transitions from yellow to red as the lock timer counts down.
			var t := 1.0 - (_lock_timer / lock_duration)
			cone_color = Color(1.0, 1.0 - t, 0.0, 0.25 + t * 0.2)
		State.DIVING:
			cone_color = Color(1.0, 0.1, 0.1, 0.5)
	
	# Tip alpha is zero so the cone fades from the apex outward.
	var tip_color := Color(cone_color.r, cone_color.g, cone_color.b, 0.0)
	var cone_origin := _cone_visual.global_position
	var tip_local := _raycast_origin.global_position - cone_origin
	
	var ring: Array[Vector3] = []
	for wp in ring_world:
		ring.append(wp - cone_origin)
	
	var base_center_world := Vector3.ZERO
	for wp in ring_world:
		base_center_world += wp
	base_center_world /= ring_world.size()
	var base_center_local := base_center_world - cone_origin
	
	_cone_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _cone_mat)
	for i in range(SEGMENTS):
		var a := ring[i]
		var b := ring[(i + 1) % SEGMENTS]
		_cone_mesh.surface_set_color(tip_color)
		_cone_mesh.surface_add_vertex(tip_local)
		_cone_mesh.surface_set_color(cone_color)
		_cone_mesh.surface_add_vertex(a)
		_cone_mesh.surface_set_color(cone_color)
		_cone_mesh.surface_add_vertex(b)
	_cone_mesh.surface_end()
	
	_cone_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _cone_mat)
	for i in range(SEGMENTS):
		var a := ring[i]
		var b := ring[(i + 1) % SEGMENTS]
		_cone_mesh.surface_set_color(cone_color)
		_cone_mesh.surface_add_vertex(base_center_local)
		_cone_mesh.surface_set_color(cone_color)
		_cone_mesh.surface_add_vertex(a)
		_cone_mesh.surface_set_color(cone_color)
		_cone_mesh.surface_add_vertex(b)
	_cone_mesh.surface_end()
