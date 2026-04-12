class_name Player
extends CharacterBody3D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal ammo_changed(current: int, in_triple: bool)
signal slowmo_changed(active: bool, cooldown_ratio: float)
signal triple_changed(active: bool, loaded: int, cooldown_ratio: float)
signal reload_progress(ratio: float, reloading: bool, triple_mode: bool)
signal shot_fired()
signal hit_registered()
signal weapon_changed(weapon: int)
signal slash_started()
signal slash_finished()
signal dash_changed(active: bool, cooldown_ratio: float)

# ---------------------------------------------------------------------------
# Weapon enum
# ---------------------------------------------------------------------------
enum Weapon { GUN, SWORD }

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

# --- Ground Movement ---
@export_group("Ground Movement")
@export var move_speed: float = 7.0
@export var acceleration: float = 20.0
@export var friction: float = 20.0

# --- Jump ---
@export_group("Jump")
@export var jump_height: float = 4.0
@export var gravity: float = 22.0

# --- Shooting & Recoil ---
@export_group("Shooting")
@export var recoil_force: float = 14.0
@export var reload_time: float = 0.8  # Waktu dalam detik untuk reload satu bullet
@export var recoil_mode: int = 1  # Recoil force untuk triple shots. 0 = equal, 1 = increasing, 2 = decreasing

# --- Bullet ---
@export_group("Bullet")
@export var bullet_scene: PackedScene
@export var bullet_speed: float = 80.0

# --- Triple Shot Skill ---
@export_group("Triple Shots Skill")
@export var triple_active_duration: float = 4.0
@export var triple_load_time: float = 0.8
@export var triple_cooldown: float = 6.0

# --- Dash Skill ---
@export_group("Dash Skill")
@export var dash_speed: float = 30.0
@export var dash_duration: float = 0.25
@export var dash_cooldown: float = 4.0

# --- Slow-Mo ---
@export_group("Slow-Mo")
@export var slowmo_time_scale: float = 0.25  
@export var slowmo_duration: float = 3.0
@export var slowmo_cooldown: float = 5.0

# --- Camera ---
@export_group("Camera")
@export var mouse_sensitivity: float = 0.003

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _jump_velocity: float
var _current_weapon: Weapon = Weapon.GUN

# Bullet state
var _bullets: int = 1 
var _is_reloading: bool = false
var _reload_timer: float = 0.0
var _shots_fired_in_air: int = 0  # Untuk increasing/decreasing recoil

# Triple shot
var _triple_active: bool = false
var _triple_loaded: int = 0
var _triple_load_timer: float = 0.0
var _triple_window_timer: float = 0.0
var _triple_cooldown_timer: float = 0.0

# Sword state
var _is_slashing: bool = false

# Dash state
var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

# Slow-mo state
var _slowmo_active: bool = false
var _slowmo_timer: float = 0.0
var _slowmo_cooldown_timer: float = 0.0

# Node refs
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _gun_pivot: Node3D = $GunPivot
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _gun_tip: Marker3D = $GunPivot/MeshInstance3D/GunTip
@onready var _sword_pivot: Node3D = $SwordPivot
@onready var _sword_slash: SwordSlash = $SwordPivot/Blade/SwordHitbox
@onready var _sword_trail: MeshInstance3D = $SwordPivot/SwordTrail

# ---------------------------------------------------------------------------
func _ready() -> void:
	_jump_velocity = sqrt(2.0 * gravity * jump_height)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if _sword_slash:
		_sword_slash.initialize(self, _sword_pivot, _sword_trail)
		_sword_slash.monitoring = false
	
	if _gun_pivot:
		_gun_pivot.visible = true
	if _sword_pivot:
		_sword_pivot.visible = false


# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Rotate character ke kiri/kanan
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Rotate camera ke atas/bawah
		_camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x, deg_to_rad(-70), deg_to_rad(30))
	
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Weapon swap
	if event.is_action_pressed("swap_weapon"):
		_swap_weapon()
	
	# Noraml attack
	if event.is_action_pressed("attack"):
		match _current_weapon:
			Weapon.GUN:
				_try_shoot()
			Weapon.SWORD:
				_try_slash()
	
	# Weapon skills
	if event.is_action_pressed("activate_skill"):
		match _current_weapon:
			Weapon.GUN:
				_try_activate_triple()
			Weapon.SWORD:
				_try_activate_dash()
	
	# Slow-mo
	if event.is_action_pressed("slowmo"):
		_try_activate_slowmo()


# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	# Pake real delta untuk slow-mo timers (tidak terpengaruh oleh Engine.time_scale)
	var real_delta: float = delta / Engine.time_scale
	
	_update_slowmo(real_delta)
	_update_reload(real_delta)
	_update_triple(real_delta)
	_update_dash(real_delta)
	
	# Gravity pake Engine.time_scale, biar bisa melambat saat slow-mo
	_apply_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	_sync_aim()
	
	# Reset air shot counter saat landing
	if is_on_floor():
		_shots_fired_in_air = 0
	
	move_and_slide()


# ---------------------------------------------------------------------------
# Weapon swap
# ---------------------------------------------------------------------------
func _swap_weapon() -> void:
	if _is_slashing or _is_dashing:
		return
	if _triple_active and _triple_loaded < 3:
		return
	
	if _current_weapon == Weapon.GUN:
		_current_weapon = Weapon.SWORD
		_gun_pivot.visible = false
		_sword_pivot.visible = true
		if _is_reloading:
			_is_reloading = false
			emit_signal("reload_progress", 0.0, false, false)
		emit_signal("weapon_changed", _current_weapon)
		if _is_dashing:
			emit_signal("dash_changed", true, 0.0)
		elif _dash_cooldown_timer > 0.0:
			emit_signal("dash_changed", false, _dash_cooldown_timer / dash_cooldown)
		else:
			emit_signal("dash_changed", false, 1.0)
	else:
		_current_weapon = Weapon.GUN
		_gun_pivot.visible = true
		_sword_pivot.visible = false
		if _sword_slash:
			_sword_slash.reset_combo()
		emit_signal("weapon_changed", _current_weapon)
		if _bullets > 0:
			emit_signal("ammo_changed", _bullets, false)
		else:
			_is_reloading = true
			_reload_timer = reload_time
			emit_signal("ammo_changed", 0, false)
			emit_signal("reload_progress", 0.0, true, false)
		if _triple_active:
			emit_signal("triple_changed", true, _triple_loaded, 1.0)
		elif _triple_cooldown_timer > 0.0:
			emit_signal("triple_changed", false, 0, _triple_cooldown_timer / triple_cooldown)
		else:
			emit_signal("triple_changed", false, 0, 1.0)


# ---------------------------------------------------------------------------
# Gravity, dipengaruhi oleh time scale (melambat saat slow-mo)
# ---------------------------------------------------------------------------
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


# ---------------------------------------------------------------------------
# Jump
# ---------------------------------------------------------------------------
func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _jump_velocity


# ---------------------------------------------------------------------------
# Ground movement
# ---------------------------------------------------------------------------
func _handle_movement(delta: float) -> void:
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)
	
	var direction := Vector3.ZERO
	if input != Vector2.ZERO:
		direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	
	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)


func _sync_aim() -> void:
	if _gun_pivot:
		_gun_pivot.rotation.x = _camera_pivot.rotation.x
	if _sword_pivot and not _is_slashing:
		_sword_pivot.rotation.x = _camera_pivot.rotation.x


# ---------------------------------------------------------------------------
# Shooting & Recoil
# ---------------------------------------------------------------------------
func _try_shoot() -> void:
	if _bullets <= 0:
		return
	if _triple_active and _triple_loaded < 3:
		return
	
	var in_air := not is_on_floor()
	_bullets -= 1
	emit_signal("ammo_changed", _bullets, _triple_active)
	emit_signal("shot_fired")
	
	_spawn_bullet()
	
	# Recoil hanya saat di udara
	if in_air:
		# Menghitung arah recoil, kebalikan dari ke mana camera menghadap
		var recoil_dir := _camera.global_transform.basis.z 
		
		# Menghitung strength recoil berdasarkan mode
		var strength: float = _get_recoil_strength()
		_shots_fired_in_air += 1
		
		# Menerapkan recoil
		velocity.x += recoil_dir.x * strength
		velocity.z += recoil_dir.z * strength
		velocity.y += recoil_dir.y * strength * 0.5  # Vertical recoil cuma setengah
	
	# Menembak satu bullet akan reload saat triple tidak aktif
	if not _triple_active and _bullets <= 0:
		_is_reloading = true
		_reload_timer = reload_time
		emit_signal("reload_progress", 0.0, true, false)


func _spawn_bullet() -> void:
	if bullet_scene == null:
		push_warning("Player: bullet_scene not assigned!")
		return
	
	# Raycast dari camera center untuk menemukan posisi crosshair menunjuk
	# Bullet spawns di gun tip dan mengarah ke posisi crosshair menunjuk
	var viewport := get_viewport()
	var screen_center := viewport.get_visible_rect().size * 0.5
	var ray_origin := _camera.project_ray_origin(screen_center)
	var ray_target := ray_origin + _camera.project_ray_normal(screen_center) * 1000.0
	
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
	query.exclude = [self]
	var result := space.intersect_ray(query)
	
	var aim_point = result.position if result else ray_target
	
	var bullet: Node = bullet_scene.instantiate()
	# Add ke root agar bullet independent dari player
	get_tree().root.add_child(bullet)
	bullet.global_transform = _gun_tip.global_transform
	
	# Arah dari gun tip ke aim point
	var shoot_dir = (aim_point - _gun_tip.global_position).normalized()
	
	if bullet.has_method("initialize"):
		bullet.initialize(shoot_dir, bullet_speed, self)


func _on_hit() -> void:
	emit_signal("hit_registered")


func _get_recoil_strength() -> float:
	match recoil_mode:
		0:  # Equal
			return recoil_force
		1:  # Increasing
			return recoil_force * (1.0 + _shots_fired_in_air * 0.4)
		2:  # Decreasing
			return recoil_force * max(0.4, 1.0 - _shots_fired_in_air * 0.3)
		_:
			return recoil_force


# ---------------------------------------------------------------------------
# Auto Reload (pake real time, tidak terpengaruh oleh slow-mo)
# ---------------------------------------------------------------------------
func _update_reload(real_delta: float) -> void:
	if not _is_reloading:
		return
	
	_reload_timer -= real_delta
	var ratio = 1.0 - clamp(_reload_timer / reload_time, 0.0, 1.0)
	emit_signal("reload_progress", ratio, true, false)
	if _reload_timer <= 0.0:
		_bullets = 1
		_is_reloading = false
		emit_signal("ammo_changed", _bullets, false)
		emit_signal("reload_progress", 1.0, false, false)


# ---------------------------------------------------------------------------
# Triple Shot Skill
# Activate -> bullets load satu-satu.
# Player harus menembak ketiga bullets dalam kurun triple_active_duration atau skill akan expired.
# ---------------------------------------------------------------------------
func _try_activate_triple() -> void:
	if _triple_active or _triple_cooldown_timer > 0.0:
		return
	
	_triple_active = true
	_triple_loaded = 0
	_triple_load_timer = triple_load_time
	_triple_window_timer = triple_active_duration
	_bullets = 0
	_is_reloading = false
	emit_signal("triple_changed", true, 0, 1.0)
	emit_signal("ammo_changed", 0, true)


func _update_triple(real_delta: float) -> void:
	# Tick cooldown saat tidak active
	if not _triple_active:
		if _triple_cooldown_timer > 0.0:
			_triple_cooldown_timer -= real_delta
			if _triple_cooldown_timer <= 0.0:
				_triple_cooldown_timer = 0.0
				emit_signal("triple_changed", false, 0, 1.0)
			else:
				emit_signal("triple_changed", false, 0, _triple_cooldown_timer / triple_cooldown)
		return
	
	# Count down fire window
	_triple_window_timer -= real_delta
	if _triple_window_timer <= 0.0:
		_end_triple()
		return
	
	# Load bullets satu-satu
	if _triple_loaded < 3:
		_triple_load_timer -= real_delta
		var load_ratio = 1.0 - clamp(_triple_load_timer / triple_load_time, 0.0, 1.0)
		emit_signal("reload_progress", load_ratio, true, true)
		if _triple_load_timer <= 0.0:
			_triple_loaded += 1
			_bullets = _triple_loaded
			_triple_load_timer = triple_load_time
			emit_signal("reload_progress", 0.0, true, true)
			emit_signal("triple_changed", true, _triple_loaded, 1.0)
			emit_signal("ammo_changed", _bullets, true)
	
	# Auto-end saat ketiga bullets sudah ditembakkan
	if _triple_loaded >= 3 and _bullets <= 0:
		_end_triple()


func _end_triple() -> void:
	_triple_active = false
	_triple_loaded = 0
	_triple_cooldown_timer = triple_cooldown
	_bullets = 0
	_is_reloading = true
	_reload_timer = reload_time
	emit_signal("triple_changed", false, 0, 1.0)
	emit_signal("ammo_changed", 0, false)


# ---------------------------------------------------------------------------
# Sword Slash
# ---------------------------------------------------------------------------
func _try_slash() -> void:
	if _is_slashing and not (_sword_slash and _sword_slash.is_in_combo()):
		return
	
	if _sword_slash.try_activate():
		_is_slashing = true
		emit_signal("slash_started")
 
 
func _on_slash_finished() -> void:
	_is_slashing = false
	emit_signal("slash_finished")


# ---------------------------------------------------------------------------
# Dash Skill
# ---------------------------------------------------------------------------
func _try_activate_dash() -> void:
	if _is_dashing or _dash_cooldown_timer > 0.0:
		return
	
	_dash_direction = -transform.basis.z
	_dash_direction.y = 0.0
	_dash_direction = _dash_direction.normalized()
	
	_is_dashing = true
	_dash_timer = dash_duration
	
	# Remove layer 2 from collision mask so player passes through Destructibles
	collision_mask = collision_mask & ~(1 << 3)  # Clear bit 1 (layer 2)
	
	if _sword_slash:
		_sword_slash.try_activate()
	
	emit_signal("dash_changed", true, 0.0)
 
 
func _update_dash(real_delta: float) -> void:
	if not _is_dashing:
		if _dash_cooldown_timer > 0.0:
			_dash_cooldown_timer -= real_delta
			if _dash_cooldown_timer <= 0.0:
				_dash_cooldown_timer = 0.0
				emit_signal("dash_changed", false, 1.0)
			else:
				emit_signal("dash_changed", false, _dash_cooldown_timer / dash_cooldown)
		return
	
	_dash_timer -= real_delta / Engine.time_scale
	if _dash_timer <= 0.0:
		_end_dash()
		return
	
	velocity.x = _dash_direction.x * dash_speed
	velocity.z = _dash_direction.z * dash_speed
 
 
func _end_dash() -> void:
	_is_dashing = false
	_dash_cooldown_timer = dash_cooldown
	# Restore layer 2 collision so player hits Destructibles again
	collision_mask = collision_mask | (1 << 3)
	emit_signal("dash_changed", false, 1.0)


# ---------------------------------------------------------------------------
# Slow-Mo
# ---------------------------------------------------------------------------
func _try_activate_slowmo() -> void:
	if _slowmo_active or _slowmo_cooldown_timer > 0.0:
		return
	
	_slowmo_active = true
	_slowmo_timer = slowmo_duration
	Engine.time_scale = slowmo_time_scale
	emit_signal("slowmo_changed", true, 0.0)


func _update_slowmo(real_delta: float) -> void:
	if _slowmo_active:
		_slowmo_timer -= real_delta
		if _slowmo_timer <= 0.0:
			_end_slowmo()
	elif _slowmo_cooldown_timer > 0.0:
		_slowmo_cooldown_timer -= real_delta
		if _slowmo_cooldown_timer <= 0.0:
			_slowmo_cooldown_timer = 0.0
			emit_signal("slowmo_changed", false, 1.0)
		else:
			emit_signal("slowmo_changed", false, _slowmo_cooldown_timer / slowmo_cooldown)


func _end_slowmo() -> void:
	_slowmo_active = false
	_slowmo_cooldown_timer = slowmo_cooldown
	Engine.time_scale = 1.0
	emit_signal("slowmo_changed", false, 1.0)
