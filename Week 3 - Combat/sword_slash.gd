class_name SwordSlash
extends Area3D

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
## Durasi setiap slash hitbox
@export var swing_duration: float = 0.25
## Waktu setelah slash berakhir untuk chain next hit
@export var combo_window: float = 0.5
## Pause setelah hit ketiga sebelum combo restart
@export var recovery_time: float = 0.6

# ---------------------------------------------------------------------------
# Combo hit definitions
# Hit 1: right-to-left diagonal (top-right ke bottom-left)
# Hit 2: left-to-right horizontal
# Hit 3: top-down vertical finisher
# ---------------------------------------------------------------------------
const COMBO_HITS := [
	{
		"from": Vector3(30.0,  60.0, -30.0),
		"to":   Vector3(-20.0, -40.0,  20.0),
	},
	{
		"from": Vector3(-10.0, -50.0, 10.0),
		"to":   Vector3( 10.0,  50.0, -10.0),
	},
	{
		"from": Vector3(60.0,  20.0, 0.0),
		"to":   Vector3(-30.0, -10.0, 0.0),
	},
]
 
#---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _active: bool = false
var _timer: float = 0.0
var _combo_window_timer: float = 0.0
var _in_recovery: bool = false
var _recovery_timer: float = 0.0
var _combo_index: int = 0
var _player: Node = null
var _hit_nodes: Array = []  # Track node yang sudah kena hit

var _sword_pivot: Node3D = null
var _trail: Node = null
var _swing_tween: Tween = null

# ---------------------------------------------------------------------------
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = false


func initialize(player: Node, sword_pivot: Node3D, trail: Node) -> void:
	_player = player
	_sword_pivot = sword_pivot
	_trail = trail


# ---------------------------------------------------------------------------
func try_activate() -> bool:
	if _active or _in_recovery:
		return false
	_activate(_combo_index)
	return true


func _activate(combo_hit: int = -1) -> void:
	_active = true
	_timer = swing_duration
	_combo_window_timer = 0.0
	_hit_nodes.clear()
	monitoring = true
	
	_play_swing(combo_hit)
	
	if _trail and _trail.has_method("start_trail"):
		_trail.start_trail()


# ---------------------------------------------------------------------------
func _play_swing(hit: int) -> void:
	if _sword_pivot == null:
		return
	if _swing_tween:
		_swing_tween.kill()
	
	var data: Dictionary = COMBO_HITS[hit]
	var from_rot := Vector3(
		deg_to_rad(data["from"].x),
		deg_to_rad(data["from"].y),
		deg_to_rad(data["from"].z)
	)
	var to_rot := Vector3(
		deg_to_rad(data["to"].x),
		deg_to_rad(data["to"].y),
		deg_to_rad(data["to"].z)
	)
	
	_sword_pivot.rotation = from_rot
	
	_swing_tween = create_tween()
	_swing_tween.tween_property(_sword_pivot, "rotation", to_rot, swing_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
 

# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _in_recovery:
		_recovery_timer -= delta
		if _recovery_timer <= 0.0:
			_in_recovery = false
			_combo_index = 0
		return
	
	if not _active and _combo_window_timer > 0.0:
		_combo_window_timer -= delta
		if _combo_window_timer <= 0.0:
			_combo_window_timer = 0.0
			_combo_index = 0
	
	if not _active:
		return
	
	_timer -= delta
	if _timer <= 0.0:
		_deactivate()


# ---------------------------------------------------------------------------
func _deactivate() -> void:
	_active = false
	monitoring = false
	
	if _trail and _trail.has_method("stop_trail"):
		_trail.stop_trail()
	
	var was_last_hit := (_combo_index == 2)
	_combo_index = (_combo_index + 1) % 3
	
	if was_last_hit:
		_in_recovery = true
		_recovery_timer = recovery_time
		_combo_window_timer = 0.0
	else:
		_combo_window_timer = combo_window
	
	if _player and _player.has_method("_on_slash_finished"):
		_player._on_slash_finished()


# ---------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	if not _active:
		return
	if body == _player:
		return
	if body in _hit_nodes:
		return
	
	_hit_nodes.append(body)
	
	if body.has_method("take_hit"):
		body.take_hit()
	
	if _player and _player.has_method("_on_hit"):
		_player._on_hit()


# ---------------------------------------------------------------------------
func can_attack() -> bool:
	return not _active and not _in_recovery


func is_in_combo() -> bool:
	return _combo_window_timer > 0.0
 
 
func reset_combo() -> void:
	_combo_index = 0
	_combo_window_timer = 0.0
	_in_recovery = false
	_recovery_timer = 0.0
 
