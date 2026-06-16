extends Control

@onready var status_lbl:   Label  = $Panel/VBox/Status
@onready var scores_lbl:   Label  = $Panel/VBox/Scores
@onready var timer_lbl:    Label  = $Panel/VBox/Timer
@onready var drop_btn:     Button = $Panel/VBox/DropAmmoBtn
@onready var cooldown_lbl: Label  = $Panel/VBox/CooldownLbl

const DROP_COOLDOWN: float = 10.0

var nm: Node = null
var _cooldown: float = 0.0


func _ready() -> void:
	await get_tree().process_frame
	nm = get_node("/root/Main/NetworkManager")
	nm.game_over.connect(_on_game_over)
	drop_btn.pressed.connect(_on_drop_btn_pressed)


func _process(delta: float) -> void:
	# Live game info
	if nm != null and nm.is_game_active:
		var mins := int(nm.game_timer) / 60
		var secs := int(nm.game_timer) % 60
		timer_lbl.text = "Time remaining: %02d:%02d" % [mins, secs]
		var parts: Array = []
		for tid in nm.scores:
			if nm.team_counts.get(tid, 0) == 0:
				continue
			var cfg = nm._get_team_config(tid)
			parts.append("%s: %d" % [cfg.get("team_name", "Team %d" % tid), nm.scores[tid]])
		scores_lbl.text = "  |  ".join(parts)

	# Cooldown countdown
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_cooldown = 0.0
			drop_btn.disabled = false
			drop_btn.text = "Drop Ammo"
			cooldown_lbl.text = ""
		else:
			cooldown_lbl.text = "Ready in %d s" % ceili(_cooldown)


func activate() -> void:
	status_lbl.text = "Game in progress...\nYou'll join the next round!"
	timer_lbl.visible = true
	scores_lbl.text = ""
	_cooldown = 0.0
	drop_btn.disabled = false
	drop_btn.text = "Drop Ammo"
	cooldown_lbl.text = ""


func _on_drop_btn_pressed() -> void:
	if nm == null:
		return
	nm.rpc_request_ammo_drop.rpc()
	_cooldown = DROP_COOLDOWN
	drop_btn.disabled = true
	drop_btn.text = "Dropped!"
	cooldown_lbl.text = "Ready in %d s" % DROP_COOLDOWN


func _on_game_over() -> void:
	status_lbl.text = "Round over!\nGetting ready for next round..."
	timer_lbl.visible = false
	drop_btn.visible = false
	cooldown_lbl.visible = false
