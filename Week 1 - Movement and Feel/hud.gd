extends CanvasLayer

# ---------------------------------------------------------------------------
# Node refs Crosshair
# ---------------------------------------------------------------------------
@export var _crosshair: TextureRect

# ---------------------------------------------------------------------------
# Node refs — Sword Slot
# ---------------------------------------------------------------------------
@onready var _sword: VBoxContainer = %Sword
@onready var _sword_slot_border: Panel = %SwordBorder
@onready var _sword_slot_overlay: Panel = %SwordOverlay
@onready var _sword_skill_bar: ProgressBar = %SwordSkillBar

# ---------------------------------------------------------------------------
# Node refs Gun Slot
# ---------------------------------------------------------------------------
@onready var _gun: VBoxContainer = %Gun
@onready var _gun_slot_border: Panel = %GunBorder
@onready var _gun_slot_overlay: Panel = %GunOverlay
@onready var _gun_reload_bar: ProgressBar = %ReloadBar
@onready var _gun_pips: HBoxContainer = %Pips
@onready var _gun_skill_bar: ProgressBar = %GunSkillBar

# ---------------------------------------------------------------------------
# Node refs Slowmo Bar
# ---------------------------------------------------------------------------
@onready var _slowmo_bar: ProgressBar = %SlowmoBar

# ---------------------------------------------------------------------------
# Crosshair shader constants
# ---------------------------------------------------------------------------
const GUN_CIRCLE_RADIUS: float = 0.25
const GUN_CIRCLE_THICKNESS: float = 0.018
const GUN_CIRCLE_GAP: float = 0.09
const GUN_CROSS_WIDTH: float = 0.12
const GUN_CROSS_THICKNESS: float = 0.03
const GUN_CROSS_GAP: float = 0.06
const GUN_DOT_RADIUS: float = 0.015
 
const SWORD_CIRCLE_RADIUS: float = 0.1
const SWORD_CIRCLE_THICKNESS: float = 0.014
const SWORD_CIRCLE_GAP: float = 0.0
 
const GUN_EXPAND_ADD: float = 0.06
const GUN_CROSS_EXPAND: float = 0.04
const SWORD_CONTRACT_SUB: float = 0.05
const EXPAND_TIME: float = 0.07
const RETURN_TIME: float = 0.20

# ---------------------------------------------------------------------------
# Weapon Slot
# ---------------------------------------------------------------------------
const BASE_SIZE: Vector2 = Vector2(108, 90)
const SCALE_INACTIVE: float = 1.2
const SCALE_ACTIVE: float = 1.6

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
const COLOR_WHITE: Color = Color(1.0,  1.0,  1.0,  1.0)
const COLOR_RED: Color = Color(0.97, 0.44, 0.44, 1.0)
const COLOR_GOLD: Color = Color(0.98, 0.72, 0.14, 1.0)
const COLOR_BORDER_ACTIVE: Color = Color(0.22, 0.55, 0.95, 0.85)
const COLOR_BORDER_INACTIVE: Color = Color(1.0,  1.0,  1.0,  0.18)
const COLOR_SLASH_ACTIVE: Color = Color(1.0,  0.85, 0.35, 1.0)

# Internal state
var _current_weapon: int  = 0
var _triple_active: bool = false
var _pip_nodes: Array = []
var _tween_crosshair: Tween = null
var _tween_hit: Tween = null
var _tween_slot_gun: Tween = null
var _tween_slot_sword: Tween = null

func _ready() -> void:
	var player: Player = get_tree().get_first_node_in_group("player")
	if player:
		player.ammo_changed.connect(_on_ammo_changed)
		player.slowmo_changed.connect(_on_slowmo_changed)
		player.triple_changed.connect(_on_triple_changed)
		player.reload_progress.connect(_on_reload_progress)
		player.shot_fired.connect(_on_shot_fired)
		player.hit_registered.connect(_on_hit_registered)
		player.weapon_changed.connect(_on_weapon_changed)
		player.slash_started.connect(_on_slash_started)
		player.slash_finished.connect(_on_slash_finished)
		player.dash_changed.connect(_on_dash_changed)
	else:
		push_warning("HUD: No node found in group 'player'")
	
	_build_pips()
	_set_gun_active(true)
	_set_sword_active(false)
	_apply_gun_crosshair()
	
	_gun_skill_bar.value = 100.0
	_sword_skill_bar.value = 100.0
	_slowmo_bar.value = 100.0
	_gun_reload_bar.value = 0.0
	_gun_reload_bar.visible = false


# ---------------------------------------------------------------------------
# Pips
# ---------------------------------------------------------------------------
func _build_pips() -> void:
	for child in _gun_pips.get_children():
		child.visible = false
		_pip_nodes.append(child)
	_update_pips(1, false)
 
 
# ---------------------------------------------------------------------------
# Pip helper
# ---------------------------------------------------------------------------
func _update_pips(count: int, triple_active: bool) -> void:
	for i in range(3):
		_pip_nodes[i].visible = i < count
		_pip_nodes[i].modulate = COLOR_GOLD if triple_active else COLOR_WHITE
 
 
# ---------------------------------------------------------------------------
# Slot active/inactive
# ---------------------------------------------------------------------------
func _set_gun_active(active: bool) -> void:
	_gun_slot_overlay.visible = not active
	_gun_slot_border.modulate = COLOR_BORDER_ACTIVE if active else COLOR_BORDER_INACTIVE
	_tween_slot_gun = _tween_slot_size(_gun, active, _tween_slot_gun)
 
 
func _set_sword_active(active: bool) -> void:
	_sword_slot_overlay.visible = not active
	_sword_slot_border.modulate = COLOR_BORDER_ACTIVE if active else COLOR_BORDER_INACTIVE
	_tween_slot_sword = _tween_slot_size(_sword, active, _tween_slot_sword)


func _tween_slot_size(wrapper: Control, active: bool, tween: Tween) -> Tween:
	if tween:
		tween.kill()
	var target := BASE_SIZE * (SCALE_ACTIVE if active else SCALE_INACTIVE)
	tween = create_tween()
	tween.tween_property(wrapper, "custom_minimum_size", target, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return tween


# ---------------------------------------------------------------------------
# Crosshair (gun)
# ---------------------------------------------------------------------------
func _apply_gun_crosshair() -> void:
	var mat := _crosshair.material as ShaderMaterial
	if not mat:
		return
	mat.set_shader_parameter("circle_radius", GUN_CIRCLE_RADIUS)
	mat.set_shader_parameter("circle_thickness", GUN_CIRCLE_THICKNESS)
	mat.set_shader_parameter("circle_gap_size", GUN_CIRCLE_GAP)
	mat.set_shader_parameter("circle_color_main", COLOR_WHITE)
	mat.set_shader_parameter("circle_rotation_speed", 0.0)
	mat.set_shader_parameter("cross_bar_width", GUN_CROSS_WIDTH)
	mat.set_shader_parameter("cross_thickness", GUN_CROSS_THICKNESS)
	mat.set_shader_parameter("cross_gap_size", GUN_CROSS_GAP)
	mat.set_shader_parameter("cross_color_main", COLOR_WHITE)
	mat.set_shader_parameter("dot_radius", GUN_DOT_RADIUS)
	mat.set_shader_parameter("dot_color", COLOR_WHITE)


# ---------------------------------------------------------------------------
# Crosshair (sword)
# ---------------------------------------------------------------------------
func _apply_sword_crosshair() -> void:
	var mat := _crosshair.material as ShaderMaterial
	if not mat:
		return
	mat.set_shader_parameter("circle_radius", SWORD_CIRCLE_RADIUS)
	mat.set_shader_parameter("circle_thickness", SWORD_CIRCLE_THICKNESS)
	mat.set_shader_parameter("circle_gap_size", SWORD_CIRCLE_GAP)
	mat.set_shader_parameter("circle_color_main", COLOR_WHITE)
	mat.set_shader_parameter("circle_rotation_speed", 0.0)
	mat.set_shader_parameter("cross_bar_width", 0.0)
	mat.set_shader_parameter("cross_thickness", 0.0)
	mat.set_shader_parameter("dot_radius", GUN_DOT_RADIUS)
	mat.set_shader_parameter("dot_color", COLOR_WHITE)


# ---------------------------------------------------------------------------
# Weapon changed
# ---------------------------------------------------------------------------
func _on_weapon_changed(weapon: int) -> void:
	_current_weapon = weapon
	if weapon == 0:
		_set_gun_active(true)
		_set_sword_active(false)
		_apply_gun_crosshair()
	else:
		_set_gun_active(false)
		_set_sword_active(true)
		_apply_sword_crosshair()


# ---------------------------------------------------------------------------
# Ammo
# ---------------------------------------------------------------------------
func _on_ammo_changed(current: int, in_triple: bool) -> void:
	_update_pips(current, in_triple)


# ---------------------------------------------------------------------------
# Reload progress signal
# ---------------------------------------------------------------------------
func _on_reload_progress(ratio: float, reloading: bool, triple_mode: bool) -> void:
	_gun_reload_bar.visible = reloading
	_gun_reload_bar.value = 100.0 - (ratio * 100.0)
	_gun_reload_bar.modulate = COLOR_GOLD if triple_mode else COLOR_WHITE


# ---------------------------------------------------------------------------
# Triple
# ---------------------------------------------------------------------------
func _on_triple_changed(active: bool, loaded: int, cooldown_ratio: float) -> void:
	_triple_active = active
	var mat := _crosshair.material as ShaderMaterial
	var color := COLOR_GOLD if active else COLOR_WHITE
	if mat:
			mat.set_shader_parameter("circle_color_main", color)
			mat.set_shader_parameter("cross_color_main", color)
			mat.set_shader_parameter("dot_color", color)
	if active or cooldown_ratio >= 1.0:
		_gun_skill_bar.value = 100.0
	else:
		_gun_skill_bar.value = 100.0 - (cooldown_ratio * 100.0)


# ---------------------------------------------------------------------------
# Dash
# ---------------------------------------------------------------------------
func _on_dash_changed(active: bool, cooldown_ratio: float) -> void:
	_sword_skill_bar.value = 100.0 if (active or cooldown_ratio >= 1.0) else 100.0 - (cooldown_ratio * 100.0)


# ---------------------------------------------------------------------------
# Slow-mo
# ---------------------------------------------------------------------------
func _on_slowmo_changed(active: bool, cooldown_ratio: float) -> void:
	_slowmo_bar.value = 100.0 if (active or cooldown_ratio >= 1.0) else 100.0 - (cooldown_ratio * 100.0)


# ---------------------------------------------------------------------------
# Shot fired
# ---------------------------------------------------------------------------
func _on_shot_fired() -> void:
	if _tween_crosshair:
		_tween_crosshair.kill()
	var mat := _crosshair.material as ShaderMaterial
	if not mat:
		return
	
	var cur_r: float = mat.get_shader_parameter("circle_radius")
	var cur_g: float = mat.get_shader_parameter("cross_gap_size")
	var exp_r: float = GUN_CIRCLE_RADIUS + GUN_EXPAND_ADD
	var exp_g: float = GUN_CROSS_GAP + GUN_CROSS_EXPAND
	
	_tween_crosshair = create_tween().set_parallel(true)
	_tween_crosshair.tween_method(
		func(v): mat.set_shader_parameter("circle_radius", v),
		cur_r, exp_r, EXPAND_TIME
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween_crosshair.tween_method(
		func(v): mat.set_shader_parameter("cross_gap_size", v),
		cur_g, exp_g, EXPAND_TIME
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	_tween_crosshair.chain().set_parallel(true)
	_tween_crosshair.tween_method(
		func(v): mat.set_shader_parameter("circle_radius", v),
		exp_r, GUN_CIRCLE_RADIUS, RETURN_TIME
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween_crosshair.tween_method(
		func(v): mat.set_shader_parameter("cross_gap_size", v),
		exp_g, GUN_CROSS_GAP, RETURN_TIME
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
 
 
# ---------------------------------------------------------------------------
# Slash state
# ---------------------------------------------------------------------------
func _on_slash_started() -> void:
	if _tween_crosshair:
		_tween_crosshair.kill()
	var mat := _crosshair.material as ShaderMaterial
	if not mat:
		return
	
	_sword_slot_border.modulate = COLOR_SLASH_ACTIVE
	
	var cur_r: float = mat.get_shader_parameter("circle_radius")
	var con_r: float = SWORD_CIRCLE_RADIUS - SWORD_CONTRACT_SUB
	
	_tween_crosshair = create_tween()
	_tween_crosshair.tween_method(
		func(v): mat.set_shader_parameter("circle_radius", v),
		cur_r, con_r, EXPAND_TIME
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween_crosshair.tween_method(
		func(v): mat.set_shader_parameter("circle_radius", v),
		con_r, SWORD_CIRCLE_RADIUS, RETURN_TIME
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
 
 
func _on_slash_finished() -> void:
	_sword_slot_border.modulate = COLOR_BORDER_ACTIVE
 
 
# ---------------------------------------------------------------------------
# Hit confirmed
# ---------------------------------------------------------------------------
func _on_hit_registered() -> void:
	if _tween_hit:
		_tween_hit.kill()
	var mat := _crosshair.material as ShaderMaterial
	if not mat:
		return
	
	mat.set_shader_parameter("circle_color_main", COLOR_RED)
	mat.set_shader_parameter("cross_color_main", COLOR_RED)
	mat.set_shader_parameter("dot_color", COLOR_RED)
	
	_tween_hit = create_tween()
	_tween_hit.tween_interval(0.12)
	_tween_hit.tween_callback(func():
		var restore := COLOR_GOLD if _triple_active else COLOR_WHITE
		mat.set_shader_parameter("circle_color_main", restore)
		mat.set_shader_parameter("cross_color_main", COLOR_WHITE)
		mat.set_shader_parameter("dot_color", COLOR_WHITE)
	)
