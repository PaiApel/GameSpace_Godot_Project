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
	area_entered.connect(_on_area_entered)


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
	
	if _player and _player.has_method("_on_bullet_hit"):
		_player._on_bullet_hit()
	
	if body.has_method("take_hit"):
		body.take_hit()
	
	queue_free()


func _on_area_entered(area: Node) -> void:
	if area == _player:
		return
	
	if _player and _player.has_method("on_bullet_hit"):
		_player.on_bullet_hit()
	
	if area.has_method("take_hit"):
		area.take_hit()
	
	queue_free()
