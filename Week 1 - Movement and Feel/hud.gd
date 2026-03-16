extends CanvasLayer

@onready var ammo_label: Label = $MarginContainer/VBoxContainer/AmmoLabel
@onready var triple_label: Label = $MarginContainer/VBoxContainer/TripleLabel
@onready var triple_cooldown_bar: ProgressBar = $MarginContainer/VBoxContainer/TripleCooldownBar
@onready var slowmo_label: Label = $MarginContainer/VBoxContainer/SlowMoLabel
@onready var slowmo_cooldown_bar: ProgressBar = $MarginContainer/VBoxContainer/SlowMoCooldownBar

@onready var _reload_ring: Control = $Crosshair/ReloadRing

@onready var _cross_top: ColorRect = $Crosshair/Top
@onready var _cross_bottom: ColorRect = $Crosshair/Bottom
@onready var _cross_left: ColorRect = $Crosshair/Left
@onready var _cross_right: ColorRect = $Crosshair/Right
@onready var _hit_marker: Control = $Crosshair/HitMarker

const CROSSHAIR_REST_GAP: float = 5.0   # Gap from center at rest (pixels)
const CROSSHAIR_EXPAND_ADD: float = 12.0   # Extra gap added on shoot
const CROSSHAIR_EXPAND_TIME: float = 0.07  # Time to expand outward
const CROSSHAIR_RETURN_TIME: float = 0.18  # Time to return to rest
const HIT_MARKER_DURATION: float = 0.12   # How long the X is visible

const RING_RADIUS: float = 22.0
const RING_WIDTH: float = 3.5
const RING_SIZE: float = (RING_RADIUS + RING_WIDTH) * 2.0 + 4.0

# Internal state
var _reload_ratio: float = 0.0
var _is_reloading: bool  = false
var _is_triple_mode: bool  = false
var _current_gap: float = CROSSHAIR_REST_GAP   # Live gap value, tweened

var _tween_expand: Tween = null
var _tween_hit:    Tween = null

func _ready() -> void:
	var player: Player = get_tree().get_first_node_in_group("player")
	if player:
		player.ammo_changed.connect(_on_ammo_changed)
		player.slowmo_changed.connect(_on_slowmo_changed)
		player.triple_changed.connect(_on_triple_changed)
		player.reload_progress.connect(_on_reload_progress)
		player.shot_fired.connect(_on_shot_fired)
		player.hit_registered.connect(_on_hit_registered)
	else:
		push_warning("HUD: No node found in group 'player'")
	
	# Default state
	ammo_label.text = "AMMO: 1"
	triple_label.text = "TRIPLE: READY"
	slowmo_label.text = "SLOW-MO: READY"
	triple_cooldown_bar.value = 1.0
	triple_cooldown_bar.max_value = 1.0
	slowmo_cooldown_bar.value = 1.0
	slowmo_cooldown_bar.max_value = 1.0
	
	_hit_marker.visible = false
	_hit_marker.modulate.a = 0.0
 
	# Setup reload ring
	_reload_ring.visible = false
	_reload_ring.custom_minimum_size = Vector2(RING_SIZE, RING_SIZE)
	_reload_ring.size = Vector2(RING_SIZE, RING_SIZE)
	# Center the ring on the crosshair
	_reload_ring.position = Vector2(-RING_SIZE * 0.5, -RING_SIZE * 0.5)
	_reload_ring.draw.connect(_draw_ring)
	call_deferred("_setup_ring")
 
	# Crosshair gap — defer so ColorRect sizes are finalised
	call_deferred("_apply_gap", CROSSHAIR_REST_GAP)


# ---------------------------------------------------------------------------
# Crosshair gap helpers
# ---------------------------------------------------------------------------
func _apply_gap(gap: float) -> void:
	_current_gap = gap
	_cross_top.position.y = -gap - _cross_top.size.y
	_cross_bottom.position.y = gap
	_cross_left.position.x = -gap - _cross_left.size.x
	_cross_right.position.x = gap


# ---------------------------------------------------------------------------
# Shot fired → crosshair expands then returns
# ---------------------------------------------------------------------------
func _on_shot_fired() -> void:
	if _tween_expand:
		_tween_expand.kill()
	_tween_expand = create_tween()
 
	var expanded_gap := CROSSHAIR_REST_GAP + CROSSHAIR_EXPAND_ADD
 
	# Expand outward fast
	_tween_expand.tween_method(_apply_gap, _current_gap, expanded_gap, CROSSHAIR_EXPAND_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Return to rest smoothly
	_tween_expand.tween_method(_apply_gap, expanded_gap, CROSSHAIR_REST_GAP, CROSSHAIR_RETURN_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
 
 
# ---------------------------------------------------------------------------
# Hit confirmed → flash the X marker
# ---------------------------------------------------------------------------
func _on_hit_registered() -> void:
	if _tween_hit:
		_tween_hit.kill()
 
	_hit_marker.visible = true
	_hit_marker.modulate.a = 1.0
 
	_tween_hit = create_tween()
	_tween_hit.tween_property(_hit_marker, "modulate:a", 0.0, HIT_MARKER_DURATION) \
		.set_ease(Tween.EASE_IN)
	_tween_hit.tween_callback(func(): _hit_marker.visible = false)
 

# ---------------------------------------------------------------------------
# Reload ring draw callback
# ---------------------------------------------------------------------------
func _draw_ring() -> void:
	if not _is_reloading:
		return
 
	var center := Vector2(RING_SIZE * 0.5, RING_SIZE * 0.5)
 
	# Background track
	_reload_ring.draw_arc(
		center, RING_RADIUS,
		deg_to_rad(-90), deg_to_rad(270),
		48, Color(1, 1, 1, 0.15), RING_WIDTH, true
	)
 
	# Progress arc
	var arc_color: Color
	if _is_triple_mode:
		arc_color = Color(1.0, 0.85, 0.0, 0.92)   # Gold
	else:
		arc_color = Color(1.0, 1.0, 1.0, 0.88)    # White
 
	var end_angle := deg_to_rad(-90.0 + 360.0 * _reload_ratio)
	_reload_ring.draw_arc(
		center, RING_RADIUS,
		deg_to_rad(-90), end_angle,
		48, arc_color, RING_WIDTH, true
	)
 
	# Completion pulse dot at the tip
	if _reload_ratio >= 1.0:
		var tip_angle := deg_to_rad(-90.0 + 360.0 * _reload_ratio)
		var tip_pos := center + Vector2(cos(tip_angle), sin(tip_angle)) * RING_RADIUS
		_reload_ring.draw_circle(tip_pos, RING_WIDTH * 1.2, arc_color)
 

# ---------------------------------------------------------------------------
# Reload progress signal
# ---------------------------------------------------------------------------
func _on_reload_progress(ratio: float, reloading: bool, triple_mode: bool) -> void:
	_reload_ratio   = ratio
	_is_reloading   = reloading
	_is_triple_mode = triple_mode
	_reload_ring.visible = reloading
	_reload_ring.queue_redraw()


# ---------------------------------------------------------------------------
# Ammo
# ---------------------------------------------------------------------------
func _on_ammo_changed(current: int, in_triple: bool) -> void:
	if in_triple:
		ammo_label.text = "AMMO: %d / 3  [TRIPLE]" % current
	else:
		ammo_label.text = "AMMO: %d" % current


# ---------------------------------------------------------------------------
# Triple
# ---------------------------------------------------------------------------
func _on_triple_changed(active: bool, loaded: int, cooldown_ratio: float) -> void:
	if active and loaded < 3:
		triple_label.text = "TRIPLE: loading %d/3" % loaded
		triple_label.modulate = Color.YELLOW
		triple_cooldown_bar.value = 1.0
	elif loaded >= 3:
		triple_label.text = "TRIPLE: READY TO SHOOT" % loaded
		triple_label.modulate = Color.RED
		triple_cooldown_bar.value = 1.0
	elif cooldown_ratio >= 1.0:
		triple_label.text = "TRIPLE: READY"
		triple_label.modulate = Color.WHITE
		triple_cooldown_bar.value = 1.0
	else:
		triple_label.text = "TRIPLE: cooldown"
		triple_label.modulate = Color.GRAY
		triple_cooldown_bar.value = cooldown_ratio


# ---------------------------------------------------------------------------
# Slow-mo
# ---------------------------------------------------------------------------
func _on_slowmo_changed(active: bool, cooldown_ratio: float) -> void:
	if active:
		slowmo_label.text = "SLOW-MO: ACTIVE"
		slowmo_label.modulate = Color.CYAN
		slowmo_cooldown_bar.value = 1.0
	elif cooldown_ratio >= 1.0:
		slowmo_label.text = "SLOW-MO: READY"
		slowmo_label.modulate = Color.WHITE
		slowmo_cooldown_bar.value = 1.0
	else:
		slowmo_label.text = "SLOW-MO: cooldown"
		slowmo_label.modulate = Color.GRAY
		slowmo_cooldown_bar.value = cooldown_ratio
