class_name PoisonFog
extends Area3D

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export_group("Damage")
@export var damage_per_tick: float = 5.0
@export var tick_interval: float = 1.0

@export_group("Visual - Blur")
@export var blur_strength: float = 3.0
@export var blur_fade_duration: float = 1.5

@export_group("Visual - Tint")
@export var tint_color: Color = Color(0.1, 0.4, 0.0, 0.25)
@export var tint_fade_duration: float = 1.0

@export_group("")
@export var blur_rect: ColorRect
@export var tint_rect: ColorRect

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _player: Node = null
var _tick_timer: float = 0.0
var _blur_mat: ShaderMaterial = null
var _tint: ColorRect = null
var _blur_tween: Tween = null
var _tint_tween: Tween = null


# ---------------------------------------------------------------------------
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if blur_rect:
		_blur_mat = blur_rect.material as ShaderMaterial
		if _blur_mat:
			_blur_mat.set_shader_parameter("blur_strength", 0.0)
			_blur_mat.set_shader_parameter("tint_strength", 0.0)
	
	if tint_rect:
		_tint = tint_rect
		_tint.color = Color(tint_color.r, tint_color.g, tint_color.b, 0.0)


# ---------------------------------------------------------------------------
# Damage tick
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _player:
		return
	var real_delta := delta / Engine.time_scale
	_tick_timer += real_delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		if _player.has_method("take_hit"):
			_player.take_hit(damage_per_tick)


# ---------------------------------------------------------------------------
# On enter
# ---------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	if not body is Player:
		return
	_player = body
	_tick_timer = 0.0
	_animate_blur(0.0, blur_strength, blur_fade_duration)
	_animate_tint(0.0, tint_color.a, tint_fade_duration)


# ---------------------------------------------------------------------------
# On exit
# ---------------------------------------------------------------------------
func _on_body_exited(body: Node) -> void:
	if body != _player:
		return
	_player = null
	_tick_timer = 0.0
	_animate_blur(blur_strength, 0.0, blur_fade_duration)
	_animate_tint(tint_color.a, 0.0, tint_fade_duration)


# ---------------------------------------------------------------------------
# Tween helpers
# ---------------------------------------------------------------------------
func _animate_blur(from: float, to: float, duration: float) -> void:
	if not _blur_mat:
		return
	if _blur_tween:
		_blur_tween.kill()
	_blur_tween = create_tween()
	_blur_tween.tween_method(
		func(v: float):
			_blur_mat.set_shader_parameter("blur_strength", v)
			_blur_mat.set_shader_parameter("tint_strength", v / 10.0),
		from, to, duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _animate_tint(from: float, to: float, duration: float) -> void:
	if not _tint:
		return
	if _tint_tween:
		_tint_tween.kill()
	_tint_tween = create_tween()
	_tint_tween.tween_method(
		func(v: float): _tint.color.a = v,
		from, to, duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
