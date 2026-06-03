extends Area2D
class_name Chest

## The prize chest placed at the map centre.
##
## The attacking team must reach this chest, pick up the prize,
## and carry it back to their home base to win.
##
## When the prize carrier dies the prize automatically returns here.

signal prize_taken
signal prize_restored

var prize_available: bool = true

@onready var _visual: Polygon2D = $Visual
@onready var _label: Label = $Label


func _ready() -> void:
	add_to_group("chest")
	body_entered.connect(_on_body_entered)
	_update_visual()


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if not prize_available:
		return

	# Only the attacking team may pick up the prize
	var nm: Node = get_node_or_null("/root/Main/NetworkManager")
	if nm == null:
		return
	var attacker_id: int = nm.get("attacker_team_id") if nm else -1
	if attacker_id == -1:
		return

	var body_team: int = body.get("team_id") if body.get("team_id") != null else -1
	if body_team != attacker_id:
		return

	# NPC picks up the prize
	if body.is_in_group("npc"):
		prize_available = false
		_rpc_set_taken.rpc()
		body.call("pickup_prize")
		return

	# Human player picks up the prize  (carried_flag_team 0 = prize)
	if body.is_in_group("player"):
		var carried: int = body.get("carried_flag_team") if body.get("carried_flag_team") != null else -1
		if carried == -1:
			prize_available = false
			_rpc_set_taken.rpc()
			body.rpc("rpc_set_flag", 0)   # 0 is the "prize" flag ID


@rpc("authority", "call_local", "reliable")
func _rpc_set_taken() -> void:
	prize_available = false
	_update_visual()
	prize_taken.emit()


## Called by NetworkManager.on_prize_dropped() — returns the prize here.
func restore_prize() -> void:
	if multiplayer.is_server():
		_rpc_restore.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_restore() -> void:
	prize_available = true
	_update_visual()
	prize_restored.emit()


func _update_visual() -> void:
	if _visual:
		_visual.color = Color(1.0, 0.8, 0.1) if prize_available else Color(0.35, 0.35, 0.35)
	if _label:
		_label.text = "PRIZE" if prize_available else "TAKEN"
