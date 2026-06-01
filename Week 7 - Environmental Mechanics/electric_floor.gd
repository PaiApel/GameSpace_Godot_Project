class_name ElectricFloor
extends StaticBody3D

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export_group("Damage")
@export var damage: float = 20.0

@export_group("Timing")
@export var zap_interval: float = 3.0
@export var warning_duration: float = 2.0

@export_group("Visual")
@export var emission_color: Color = Color(0.4, 0.8, 1.0)
@export var emission_peak: float = 4.0
@export var flicker_peak: float = 1.5

@export_group("Arcs")
@export var arc_count: int = 4
@export var arc_height: float = 0.25
@export var arc_displacement: float = 0.3
@export var arc_floor_width: float = 1.0
@export var arc_floor_depth: float = 1.0

# ---------------------------------------------------------------------------
# Node refs
# ---------------------------------------------------------------------------
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _area: Area3D = $Area3D
@onready var _particles: GPUParticles3D = $GPUParticles3D
@onready var _particles_warning: GPUParticles3D = $GPUParticles3DWarning
@onready var _arc_visual: MeshInstance3D = $ArcVisual

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _player: Node = null
var _timer: float = 0.0
var _mat: StandardMaterial3D = null
var _tween: Tween = null
var _in_warning: bool = false

var _arc_mesh: ImmediateMesh
var _arc_mat: StandardMaterial3D

var _arcs: Array = []


# ---------------------------------------------------------------------------
func _ready() -> void:
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_setup_material()
	_setup_arc_mesh()


func _setup_material() -> void:
	# Duplicate the mesh material so the emission can be animated safely
	var base := _mesh.mesh.surface_get_material(0)
	if base is StandardMaterial3D:
		_mat = base.duplicate()
	else:
		_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.emission = emission_color
	_mat.emission_energy_multiplier = 0.0
	_mesh.set_surface_override_material(0, _mat)


func _setup_arc_mesh() -> void:
	_arc_mesh = ImmediateMesh.new()
	_arc_visual.mesh = _arc_mesh
	
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.vertex_color_use_as_albedo = true
	_arc_mat.emission_enabled = true
	_arc_mat.emission = emission_color
	_arc_mat.emission_energy_multiplier = 1.0


# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if Engine.time_scale == 0.0:
		return
	var real_delta: float = delta / Engine.time_scale if Engine.time_scale > 0.0 else 0.0
	_timer += real_delta
	
	var warning_start := zap_interval - warning_duration
	# Trigger the warning once per cycle
	if _timer >= warning_start and _timer - real_delta < warning_start:
		_start_warning()
	
	# Zap at full interval
	if _timer >= zap_interval:
		_timer = 0.0
		_zap()
	
	# Redraw arcs every frame while active
	if _in_warning:
		var progress = clamp(_timer - (zap_interval - warning_duration) / warning_duration, 0.0, 1.0)
		_draw_arcs(flicker_peak * lerp(0.3, 1.0, progress))
	else:
		_arc_mesh.clear_surfaces()


# ---------------------------------------------------------------------------
# Arc generation
# ---------------------------------------------------------------------------
 
# Recursively splits a line segment, randomly displacing each midpoint.
# Points are accumulated into `out` in order so they can be drawn as a line strip.
func _displace(a: Vector3, b: Vector3, depth: int, out: Array) -> void:
	if depth == 0:
		out.append(b)
		return
	
	# Midpoint of the segment
	var mid := (a + b) * 0.5
	
	# Random perpendicular offset, pick a random direction in the plane
	# perpendicular to the segment, then scale it by arc_displacement.
	# Using two random axes (x and z cross products) keeps the offset truly 3D
	var along := (b - a).normalized()
	var perp: Vector3
	if abs(along.dot(Vector3.UP)) < 0.99:
		perp = along.cross(Vector3.UP).normalized()
	else:
		perp = along.cross(Vector3.RIGHT).normalized()
	var binormal := along.cross(perp).normalized()
	
	var scale := (b - a).length() * arc_displacement
	mid += perp * randf_range(-scale, scale)
	mid += binormal * randf_range(-scale, scale)
	# Small vertical jitter keeps arcs from being flat
	mid.y += randf_range(-scale * 0.3, scale * 0.3)
	
	_displace(a, mid, depth - 1, out)
	_displace(mid, b, depth - 1, out)
 
 
func _generate_arc() -> Array:
	# Random start: anywhere on the floor rectangle surface
	var start := Vector3(
		randf_range(-arc_floor_width * 0.5, arc_floor_width * 0.5),
		0.0,
		randf_range(-arc_floor_depth * 0.5, arc_floor_depth * 0.5)
	)
	
	# Random end: also within rectangle bounds but elevated to arc_height
	var end := Vector3(
		randf_range(-arc_floor_width * 0.5, arc_floor_width * 0.5),
		arc_height,
		randf_range(-arc_floor_depth * 0.5, arc_floor_depth * 0.5)
	)
	
	var points := [start]
	# 4 levels of recursion = 16 segments per arc, enough to look jagged
	_displace(start, end, 4, points)
	return points
 
 
func _draw_arcs(brightness: float) -> void:
	_arc_mesh.clear_surfaces()
	
	# Regenerate arc paths every frame, new random offsets = wiggle
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _arc_mat)
	
	for _i in range(arc_count):
		var points := _generate_arc()
		var count := points.size()
		for j in range(count):
			# Fade alpha from full at base to 0 at tip, gives a tapered glow look
			var t := float(j) / float(count - 1)
			var alpha = lerp(1.0, 0.0, t) * brightness / emission_peak
			_arc_mesh.surface_set_color(Color(emission_color.r, emission_color.g, emission_color.b, alpha))
			_arc_mesh.surface_add_vertex(points[j])
	
	_arc_mesh.surface_end()


# ---------------------------------------------------------------------------
# Warning phase: gradually brighten emission
# ---------------------------------------------------------------------------
func _start_warning() -> void:
	_in_warning = true
	_particles_warning.emitting = true
	_flicker(0)


func _flicker(step: int) -> void:
	if not _in_warning:
		return
	
	var elapsed := _timer - (zap_interval - warning_duration)
	var progress = clamp(elapsed / warning_duration, 0.0, 1.0)
	
	var target = flicker_peak * lerp(0.3, 1.0, progress)
	var on_time = lerp(0.4, 0.05, progress) 
	var off_time = lerp(0.3, 0.03, progress)
	
	if _tween:
		_tween.kill()
	_tween = create_tween()
	
	# Flash on
	_tween.tween_method(
		func(v: float): _mat.emission_energy_multiplier = v,
		_mat.emission_energy_multiplier, target, on_time
	).set_trans(Tween.TRANS_LINEAR)
	
	# Flash off, dip to a low value
	var dip = flicker_peak * lerp(0.05, 0.2, progress)
	_tween.tween_method(
		func(v: float): _mat.emission_energy_multiplier = v,
		target, dip, off_time
	).set_trans(Tween.TRANS_LINEAR)
	
	# Schedule next flicker cycle
	_tween.tween_callback(func(): _flicker(step + 1))


# ---------------------------------------------------------------------------
# Zap phase: double discharge, then fade out
# ---------------------------------------------------------------------------
func _zap() -> void:
	_in_warning = false
	
	_particles_warning.emitting = false
	
	# Damage player if inside
	if _player and _player.has_method("take_hit"):
		_player.take_hit(damage)
	if _player and _player.has_method("add_trauma"):
		_player.add_trauma(0.5)
	
	_particles.restart()
	
	# Double-zap: peak -> brief dip -> peak again -> fade out
	if _tween:
		_tween.kill()
	_tween = create_tween()
	
	_tween.tween_method(
		func(v: float): _mat.emission_energy_multiplier = v,
		_mat.emission_energy_multiplier, emission_peak, 0.04
	).set_trans(Tween.TRANS_LINEAR)
	
	_tween.tween_method(
		func(v: float): _mat.emission_energy_multiplier = v,
		emission_peak, emission_peak * 0.3, 0.06
	).set_trans(Tween.TRANS_LINEAR)
	
	_tween.tween_method(
		func(v: float): _mat.emission_energy_multiplier = v,
		emission_peak * 0.3, emission_peak, 0.04
	).set_trans(Tween.TRANS_LINEAR)
	
	_tween.tween_method(
		func(v: float): _mat.emission_energy_multiplier = v,
		emission_peak, 0.0, 0.35
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# ---------------------------------------------------------------------------
# Player tracking
# ---------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player = body


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
