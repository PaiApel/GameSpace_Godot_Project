class_name Destructible
extends StaticBody3D

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var max_hits: int = 3

# Warna per state object
@export_group("State Colors")
@export var color_healthy:  Color = Color(1.0, 1.0, 1.0)
@export var color_damaged:  Color = Color(1.0, 0.55, 0.1)
@export var color_critical: Color = Color(0.9, 0.1, 0.1)

# ---------------------------------------------------------------------------
# State enum
# ---------------------------------------------------------------------------
enum State { HEALTHY, DAMAGED, CRITICAL, DESTROYED }

var _hits_taken: int = 0
var _current_state: State = State.HEALTHY

# Node refs
@onready var _mesh: MeshInstance3D = $Mesh


# ---------------------------------------------------------------------------
func _ready() -> void:
	_apply_state()


# ---------------------------------------------------------------------------
# Dipanggil oleh Bullet saat collision
# ---------------------------------------------------------------------------
func take_hit() -> void:
	if _current_state == State.DESTROYED:
		return
	
	_hits_taken += 1
	_update_state()


# ---------------------------------------------------------------------------
func _update_state() -> void:
	var prev_state := _current_state
	
	if _hits_taken >= max_hits:
		_current_state = State.DESTROYED
	elif _hits_taken >= max_hits - 1:
		_current_state = State.CRITICAL
	elif _hits_taken > 0:
		_current_state = State.DAMAGED
	else:
		_current_state = State.HEALTHY
	
	if _current_state != prev_state:
		_apply_state()


# ---------------------------------------------------------------------------
func _apply_state() -> void:
	match _current_state:
		State.HEALTHY:
			_set_tint(color_healthy)
		
		State.DAMAGED:
			_set_tint(color_damaged)
		
		State.CRITICAL:
			_set_tint(color_critical)
		
		State.DESTROYED:
			queue_free()


# ---------------------------------------------------------------------------
# State color
# ---------------------------------------------------------------------------
func _set_tint(color: Color) -> void:
	if _mesh == null:
		return
	
	var mat: StandardMaterial3D = _mesh.get_surface_override_material(0)
	
	if mat == null:
		var base := _mesh.mesh.surface_get_material(0)
		if base is StandardMaterial3D:
			mat = base.duplicate()
		else:
			mat = StandardMaterial3D.new()
		_mesh.set_surface_override_material(0, mat)
	
	mat.albedo_color = color


# ---------------------------------------------------------------------------
func get_state_name() -> String:
	return State.keys()[_current_state]
