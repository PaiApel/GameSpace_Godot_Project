class_name Player
extends CharacterBody3D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal ammo_changed(current: int, in_triple: bool)
signal slowmo_changed(active: bool, cooldown_ratio: float)
signal triple_changed(active: bool, loaded: int, cooldown_ratio: float)
signal reload_progress(ratio: float, reloading: bool, triple_mode: bool)

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

# --- Triple Shot Skill ---
@export_group("Triple Shots Skill")
@export var triple_active_duration: float = 4.0
@export var triple_load_time: float = 0.8
@export var triple_cooldown: float = 6.0

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

# Slow-mo state
var _slowmo_active: bool = false
var _slowmo_timer: float = 0.0
var _slowmo_cooldown_timer: float = 0.0

# Node refs
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _gun_pivot: Node3D = $GunPivot
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

# ---------------------------------------------------------------------------
func _ready() -> void:
	_jump_velocity = sqrt(2.0 * gravity * jump_height)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	
	# Shoot
	if event.is_action_pressed("shoot"):
		_try_shoot()
	
	# Triple Shots
	if event.is_action_pressed("triple_shot"):
		_try_activate_triple()
	
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
	
	# Gravity pake Engine.time_scale, biar bisa melambat saat slow-mo
	_apply_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	_sync_gun_aim()
	
	# Reset air shot counter saat landing
	if is_on_floor():
		_shots_fired_in_air = 0
	
	move_and_slide()


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


# Senapan nunjuk ke arah camera menghadap
func _sync_gun_aim() -> void:
	if _gun_pivot:
		_gun_pivot.rotation.x = _camera_pivot.rotation.x


# ---------------------------------------------------------------------------
# Shooting & Recoil
# ---------------------------------------------------------------------------
func _try_shoot() -> void:
	if _bullets <= 0:
		return
	
	var in_air := not is_on_floor()
	_bullets -= 1
	emit_signal("ammo_changed", _bullets, _triple_active)
	
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
	if _triple_active:
		return
	
	if _triple_cooldown_timer > 0.0:
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
		emit_signal("slowmo_changed", false, _slowmo_cooldown_timer / slowmo_cooldown)


func _end_slowmo() -> void:
	_slowmo_active = false
	_slowmo_cooldown_timer = slowmo_cooldown
	Engine.time_scale = 1.0
	emit_signal("slowmo_changed", false, 1.0)
