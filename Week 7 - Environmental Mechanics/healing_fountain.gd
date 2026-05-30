class_name HealingFountain
extends Area3D

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export_group("Healing")
@export var heal_per_second: float = 5.0

@export_group("Visual - Floor")
@export var floor_emission_color: Color = Color(0.2, 1.0, 0.5)
@export var floor_emission_min: float = 1.0
@export var floor_emission_max: float = 2.5
@export var pulse_duration: float = 1.8

@export_group("Visual - Barrier")
@export var barrier_emission_color: Color = Color(1.0, 0.9, 0.2)
@export var barrier_emission_min: float = 0.3
@export var barrier_emission_max: float = 1.5
@export var barrier_pulse_offset: float = 0.6

# ---------------------------------------------------------------------------
# Node refs
# ---------------------------------------------------------------------------
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _barrier: MeshInstance3D = $Barrier

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _player: Node = null
var _floor_mat: StandardMaterial3D = null
var _barrier_mat: ShaderMaterial = null
var _floor_tween: Tween = null
var _barrier_tween: Tween = null


# ---------------------------------------------------------------------------
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_setup_floor_material()
	_barrier_mat = _barrier.get_active_material(0)
	_start_floor_pulse()
	await get_tree().create_timer(barrier_pulse_offset).timeout
	_start_barrier_pulse()


# ---------------------------------------------------------------------------
# Material setup
# ---------------------------------------------------------------------------
func _setup_floor_material() -> void:
	var base := _mesh.mesh.surface_get_material(0)
	if base is StandardMaterial3D:
		_floor_mat = base.duplicate()
	else:
		_floor_mat = StandardMaterial3D.new()
	_floor_mat.emission_enabled = true
	_floor_mat.emission = floor_emission_color
	_floor_mat.emission_energy_multiplier = floor_emission_min
	_mesh.set_surface_override_material(0, _floor_mat)


# ---------------------------------------------------------------------------
# Pulse
# ---------------------------------------------------------------------------
func _start_floor_pulse() -> void:
	if _floor_tween:
		_floor_tween.kill()
	_floor_tween = create_tween().set_loops()
	_floor_tween.tween_method(
		func(v: float): _floor_mat.emission_energy_multiplier = v,
		floor_emission_min, floor_emission_max, pulse_duration * 0.5
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_floor_tween.tween_method(
		func(v: float): _floor_mat.emission_energy_multiplier = v,
		floor_emission_max, floor_emission_min, pulse_duration * 0.5
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _start_barrier_pulse() -> void:
	if _barrier_tween:
		_barrier_tween.kill()
	# Barrier pulse duration is slightly different from floor
	var barrier_duration := pulse_duration * 1.3
	_barrier_tween = create_tween().set_loops()
	_barrier_tween.tween_method(
		func(v: float): _barrier_mat.set_shader_parameter("emission_energy", v),
		barrier_emission_min, barrier_emission_max, barrier_duration * 0.5
	)
	_barrier_tween.tween_method(
		func(v: float): _barrier_mat.set_shader_parameter("emission_energy", v),
		barrier_emission_max, barrier_emission_min, barrier_duration * 0.5
	)


# ---------------------------------------------------------------------------
# Healing
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _player and _player.has_method("heal"):
		_player.heal(heal_per_second * delta)


# ---------------------------------------------------------------------------
# Player tracking
# ---------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player = body


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
