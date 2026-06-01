class_name Bullet
extends Area3D

# ---------------------------------------------------------------------------
# Jarak maks yang bisa dilewati bullet
# ---------------------------------------------------------------------------
@export var max_distance: float = 100.0

var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 80.0
var _player: Node = null
var _spawn_position: Vector3

# ---------------------------------------------------------------------------
func initialize(direction: Vector3, speed: float, player: Node) -> void:
	_direction = direction.normalized()
	_speed = speed
	_player = player
	_spawn_position = global_position


# ---------------------------------------------------------------------------
func _ready() -> void:
	body_entered.connect(_on_body_entered)


# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	global_position += _direction * _speed * delta
	if global_position.distance_to(_spawn_position) >= max_distance:
		queue_free()
		return


# ---------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	if body == _player:
		return
	
	if body.has_method("take_hit"):
		var hit_pos := global_position
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			global_position - _direction * 0.2,
			global_position + _direction * 0.2
		)
		query.exclude = [self, _player]
		var result := space.intersect_ray(query)
		if result:
			hit_pos = result.position
		body.take_hit(hit_pos, -_direction)
		
		if _player and _player.has_method("_on_hit"):
			_player._on_hit()
	
	
	queue_free()
