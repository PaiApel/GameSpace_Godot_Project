extends CanvasLayer

@onready var ammo_label: Label = $MarginContainer/VBoxContainer/AmmoLabel
@onready var triple_label: Label = $MarginContainer/VBoxContainer/TripleLabel
@onready var triple_cooldown_bar: ProgressBar = $MarginContainer/VBoxContainer/TripleCooldownBar
@onready var slowmo_label: Label = $MarginContainer/VBoxContainer/SlowMoLabel
@onready var slowmo_cooldown_bar: ProgressBar = $MarginContainer/VBoxContainer/SlowMoCooldownBar
@onready var reload_arc: TextureProgressBar = $Crosshair/ReloadArc

func _ready() -> void:
	var player: Player = get_tree().get_first_node_in_group("player")
	if player:
		player.ammo_changed.connect(_on_ammo_changed)
		player.slowmo_changed.connect(_on_slowmo_changed)
		player.triple_changed.connect(_on_triple_changed)
		player.reload_progress.connect(_on_reload_progress)
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
	reload_arc.value = 100.0
	reload_arc.visible = false


func _on_ammo_changed(current: int, in_triple: bool) -> void:
	if in_triple:
		ammo_label.text = "AMMO: %d / 3  [TRIPLE]" % current
	else:
		ammo_label.text = "AMMO: %d" % current


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


func _on_reload_progress(ratio: float, reloading: bool, triple_mode: bool) -> void:
	if reloading:
		# Show arc, set color berdasarkan mode
		reload_arc.modulate = Color(1.0, 0.85, 0.0, 0.9) if triple_mode else Color(1, 1, 1)
		reload_arc.visible = true
		reload_arc.value = ratio * 100.0
	else:
		# Hide arc saat tidak reloading
		reload_arc.visible = false
		reload_arc.value = 100.0
