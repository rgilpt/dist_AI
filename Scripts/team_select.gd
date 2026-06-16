extends Control

@onready var status_lbl:    Label          = $Content/Status
@onready var btn_container: VBoxContainer  = $Content/TeamList

var my_team: int = -1   # chosen team_id, -1 = none
var my_role: int = -1   # ROLE_ATTACK / ROLE_DEFEND, -1 = none
var _submitted: bool = false

var nm: Node = null

var _team_buttons: Dictionary = {}   # team_id -> Button
var _attack_btn:   Button     = null
var _defend_btn:   Button     = null
var _ready_btn:    Button     = null


func _ready() -> void:
	await get_tree().process_frame
	nm = get_node("/root/Main/NetworkManager")
	if nm == null:
		printerr("TeamSelect: NetworkManager not found!")
		return

	_build_ui()

	nm.team_data_updated.connect(_on_team_data_updated)
	nm.game_started.connect(_on_game_started)
	nm.game_mode_updated.connect(update_ui)
	nm.role_waiting.connect(_on_role_waiting)

	update_ui()


func _build_ui() -> void:
	for child in btn_container.get_children():
		child.queue_free()
	_team_buttons.clear()

	# ── Team section ─────────────────────────────────────────────────────────
	var team_hdr := Label.new()
	team_hdr.text = "Team"
	team_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_hdr.add_theme_font_size_override("font_size", 16)
	btn_container.add_child(team_hdr)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	btn_container.add_child(grid)

	for t in nm.team_config.get("teams", []):
		var tid: int    = t.get("team_id", -1)
		if tid == -1:
			continue
		var tname: String = t.get("team_name", "Team %d" % tid)
		var c_arr         = t.get("color", null)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 48)
		btn.text = tname
		if c_arr:
			btn.modulate = Color(c_arr[0], c_arr[1], c_arr[2])
		btn.pressed.connect(func(): _on_team_btn_pressed(tid))
		grid.add_child(btn)
		_team_buttons[tid] = btn

	# ── Role section ──────────────────────────────────────────────────────────
	btn_container.add_child(HSeparator.new())

	var role_hdr := Label.new()
	role_hdr.text = "Role"
	role_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_hdr.add_theme_font_size_override("font_size", 16)
	btn_container.add_child(role_hdr)

	var role_row := HBoxContainer.new()
	role_row.alignment = BoxContainer.ALIGNMENT_CENTER
	role_row.add_theme_constant_override("separation", 20)
	btn_container.add_child(role_row)

	_attack_btn = Button.new()
	_attack_btn.custom_minimum_size = Vector2(150, 70)
	_attack_btn.text = "ATTACK\nSteal the prize"
	_attack_btn.modulate = Color(1.0, 0.55, 0.2)
	_attack_btn.pressed.connect(func(): _on_role_btn_pressed(NetworkManager.ROLE_ATTACK))
	role_row.add_child(_attack_btn)

	_defend_btn = Button.new()
	_defend_btn.custom_minimum_size = Vector2(150, 70)
	_defend_btn.text = "DEFEND\nProtect the prize"
	_defend_btn.modulate = Color(0.3, 0.7, 1.0)
	_defend_btn.pressed.connect(func(): _on_role_btn_pressed(NetworkManager.ROLE_DEFEND))
	role_row.add_child(_defend_btn)

	# ── Ready button ──────────────────────────────────────────────────────────
	btn_container.add_child(HSeparator.new())

	_ready_btn = Button.new()
	_ready_btn.custom_minimum_size = Vector2(200, 56)
	_ready_btn.text = "Ready!"
	_ready_btn.visible = false
	_ready_btn.pressed.connect(_on_ready_pressed)
	btn_container.add_child(_ready_btn)


# ── Event handlers ────────────────────────────────────────────────────────────

func _on_team_btn_pressed(team_id: int) -> void:
	if _submitted:
		return
	my_team = team_id
	update_ui()


func _on_role_btn_pressed(role: int) -> void:
	if _submitted:
		return
	my_role = role
	update_ui()


func _on_ready_pressed() -> void:
	if _submitted or my_team == -1 or my_role == -1:
		return
	_submitted = true
	nm.rpc_claim_selection.rpc(my_team, my_role)
	update_ui()


func _on_role_waiting(count: int, total: int) -> void:
	status_lbl.text = "Waiting for others... (%d/%d ready)" % [count, total]
	status_lbl.add_theme_color_override("font_color", Color.WHITE)


func _on_team_data_updated(_counts: Dictionary, _your_team: int) -> void:
	update_ui()


# ── UI refresh ────────────────────────────────────────────────────────────────

func update_ui() -> void:
	# Team buttons: highlight selected, grey out others after submit
	for tid in _team_buttons:
		var btn: Button = _team_buttons[tid]
		var t = nm._get_team_config(tid)
		var c_arr = t.get("color", null)
		var base := Color(c_arr[0], c_arr[1], c_arr[2]) if c_arr else Color.WHITE
		var is_selected = (tid == my_team)

		btn.disabled = _submitted
		if is_selected:
			btn.text = "► %s ◄" % t.get("team_name", "Team %d" % tid)
			btn.modulate = base * 1.4
		else:
			btn.text = t.get("team_name", "Team %d" % tid)
			btn.modulate = base if not _submitted else base * 0.5

	# Role buttons: highlight selected, grey out others after submit
	if _attack_btn:
		_attack_btn.disabled = _submitted
		var selected := (my_role == NetworkManager.ROLE_ATTACK)
		_attack_btn.text = "► ATTACK ◄\nSteal the prize" if selected else "ATTACK\nSteal the prize"
		_attack_btn.modulate = Color(1.3, 0.7, 0.3) if selected else (Color(1.0, 0.55, 0.2) if not _submitted else Color(0.5, 0.28, 0.1))

	if _defend_btn:
		_defend_btn.disabled = _submitted
		var selected := (my_role == NetworkManager.ROLE_DEFEND)
		_defend_btn.text = "► DEFEND ◄\nProtect the prize" if selected else "DEFEND\nProtect the prize"
		_defend_btn.modulate = Color(0.4, 0.9, 1.4) if selected else (Color(0.3, 0.7, 1.0) if not _submitted else Color(0.15, 0.35, 0.5))

	# Ready button: appears only when both are chosen and not yet submitted
	if _ready_btn:
		_ready_btn.visible = (my_team != -1 and my_role != -1 and not _submitted)

	# Status label
	if not _submitted:
		if my_team == -1 and my_role == -1:
			status_lbl.text = "Choose your team and role!"
		elif my_team == -1:
			status_lbl.text = "Now pick a team!"
		elif my_role == -1:
			status_lbl.text = "Now pick a role!"
		else:
			status_lbl.text = "Ready to go!"
		status_lbl.add_theme_color_override("font_color", Color.WHITE)


func _on_game_started() -> void:
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and is_node_ready():
		my_team    = -1
		my_role    = -1
		_submitted = false
		if _ready_btn:
			_ready_btn.visible = false
		update_ui()
