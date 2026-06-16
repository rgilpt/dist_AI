extends Control

@onready var status_lbl:   Label          = $Content/Status
@onready var btn_container: VBoxContainer = $Content/TeamList

var my_role: int = -1   # -1=not chosen, 0=attack, 1=defend
var nm: Node = null

var _attack_btn: Button = null
var _defend_btn: Button = null


func _ready():
	await get_tree().process_frame
	nm = get_node("/root/Main/NetworkManager")
	if nm == null:
		printerr("TeamSelect: NetworkManager not found!")
		return

	_build_role_buttons()

	nm.team_data_updated.connect(_on_team_data_updated)
	nm.game_started.connect(_on_game_started)
	nm.game_mode_updated.connect(update_ui)
	nm.role_waiting.connect(_on_role_waiting)

	update_ui()


func _build_role_buttons() -> void:
	for child in btn_container.get_children():
		child.queue_free()

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	btn_container.add_child(hbox)

	_attack_btn = Button.new()
	_attack_btn.custom_minimum_size = Vector2(160, 90)
	_attack_btn.text = "ATTACK\nSteal the prize"
	_attack_btn.modulate = Color(1.0, 0.55, 0.2)
	_attack_btn.pressed.connect(func(): _on_role_btn_pressed(NetworkManager.ROLE_ATTACK))
	hbox.add_child(_attack_btn)

	_defend_btn = Button.new()
	_defend_btn.custom_minimum_size = Vector2(160, 90)
	_defend_btn.text = "DEFEND\nProtect the prize"
	_defend_btn.modulate = Color(0.3, 0.7, 1.0)
	_defend_btn.pressed.connect(func(): _on_role_btn_pressed(NetworkManager.ROLE_DEFEND))
	hbox.add_child(_defend_btn)


func _on_role_btn_pressed(role: int) -> void:
	my_role = role
	nm.rpc_claim_role.rpc(role)
	update_ui()


func _on_role_waiting(count: int, total: int) -> void:
	if my_role == -1:
		return
	var role_name := "Attack" if my_role == NetworkManager.ROLE_ATTACK else "Defend"
	status_lbl.text = "You chose %s!\nWaiting for others... (%d/%d ready)" % [role_name, count, total]
	status_lbl.add_theme_color_override("font_color", Color.WHITE)


func _on_team_data_updated(_counts: Dictionary, _your_team: int) -> void:
	update_ui()


func update_ui() -> void:
	if my_role == -1:
		status_lbl.text = "Choose your role!"
		status_lbl.add_theme_color_override("font_color", Color.WHITE)
		if _attack_btn:
			_attack_btn.disabled = false
		if _defend_btn:
			_defend_btn.disabled = false
	else:
		var role_name := "Attack" if my_role == NetworkManager.ROLE_ATTACK else "Defend"
		status_lbl.text = "You chose %s!\nWaiting for others..." % role_name
		status_lbl.add_theme_color_override("font_color", Color.WHITE)
		if _attack_btn:
			_attack_btn.disabled = true
		if _defend_btn:
			_defend_btn.disabled = true


func _on_game_started() -> void:
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and is_node_ready():
		my_role = -1
		update_ui()
