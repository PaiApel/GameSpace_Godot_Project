extends MeshInstance3D

# ---------------------------------------------------------------------------
@export var tip_marker: Marker3D
@export var base_marker: Marker3D
@export var max_points: int = 24
@export var fade_time: float = 0.2
@export var trail_color: Color = Color(0.4, 0.85, 1.0, 0.9)

# ---------------------------------------------------------------------------
var _active: bool = false
var _tip_points: Array[Vector3] = []
var _base_points: Array[Vector3] = []
var _fade_timer: float = 0.0
var _im: ImmediateMesh = null
var _mat: StandardMaterial3D = null


# ---------------------------------------------------------------------------
func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color.WHITE
	_mat.emission_enabled = true
	_mat.emission = Color(0.3, 0.8, 1.0)
	_mat.emission_energy_multiplier = 1.5
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	visible = false


# ---------------------------------------------------------------------------
func start_trail() -> void:
	_active = true
	_fade_timer = fade_time
	_tip_points.clear()
	_base_points.clear()
	visible = true


# ---------------------------------------------------------------------------
func stop_trail() -> void:
	_active = false


# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _active and _fade_timer <= 0.0:
		return
	
	if _active:
		if tip_marker and base_marker:
			_tip_points.append(tip_marker.global_position)
			_base_points.append(base_marker.global_position)
			if _tip_points.size() > max_points:
				_tip_points.pop_front()
				_base_points.pop_front()
	else:
		_fade_timer -= delta
		if _fade_timer <= 0.0:
			_fade_timer = 0.0
			visible = false
			_im.clear_surfaces()
			return
	
	_draw_trail()


# ---------------------------------------------------------------------------
func _draw_trail() -> void:
	_im.clear_surfaces()
	
	var count := _tip_points.size()
	if count < 2:
		return
	
	var fade_ratio = 1.0 if _active else clamp(_fade_timer / fade_time, 0.0, 1.0)
	
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	
	for i in range(count):
		var t := float(i) / float(count - 1)
		var alpha = t * fade_ratio * trail_color.a
		var col := Color(trail_color.r, trail_color.g, trail_color.b, alpha)
		
		_im.surface_set_color(col)
		_im.surface_add_vertex(to_local(_tip_points[i]))
		
		_im.surface_set_color(col)
		_im.surface_add_vertex(to_local(_base_points[i]))
	
	_im.surface_end()
