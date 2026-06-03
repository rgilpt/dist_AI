extends Area2D

## The team this zone belongs to.  1 = Blue, 2 = Red.
@export var team_id: int = 1

@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if visual:
		var nm := get_node_or_null("/root/Main/NetworkManager")
		var c_arr = nm._get_team_config(team_id).get("color", null) if nm else null
		if c_arr != null:
			visual.color = Color(c_arr[0], c_arr[1], c_arr[2], 0.35)
		else:
			visual.color = Color(0.2, 0.5, 1.0, 0.35) if team_id == 1 else Color(1.0, 0.2, 0.2, 0.35)


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return

	var is_npc: bool = body.is_in_group("npc")
	var is_player: bool = body.is_in_group("player") and not is_npc

	if not is_npc and not is_player:
		return

	var nm: Node = get_node("/root/Main/NetworkManager")

	# Determine which team this body belongs to
	var body_team: int
	if is_npc:
		body_team = body.get("team_id") if body.get("team_id") != null else -1
	else:
		body_team = nm.peer_teams.get(int(body.name), -1)

	# Body must belong to this zone's team
	if body_team != team_id:
		return

	# ── Human player: refill ammo on friendly zone entry ──────
	if is_player and body.has_method("rpc_refill_ammo"):
		body.rpc_refill_ammo.rpc()

	# ── Check for prize (carried_flag_team == 0 or carries_prize) ─
	var carrying_prize: bool
	if is_npc:
		carrying_prize = body.get("carries_prize") == true
	else:
		carrying_prize = body.get("carried_flag_team") == 0

	if carrying_prize:
		var attacker_team: int = nm.get("attacker_team_id") if nm else -1
		if body_team == attacker_team:
			# Attacker team delivered the prize — they win!
			if is_npc:
				body.rpc("rpc_set_carries_prize", false)
			else:
				body.rpc("rpc_set_flag", -1)
			nm.on_prize_scored(body_team)
		return   # handled (prize path); don't fall through to CTF

	# ── CTF scoring (original flag-capture rules, human players only) ──
	if not is_player:
		return

	var enemy_flag_team: int = body.carried_flag_team
	if enemy_flag_team == -1 or enemy_flag_team == team_id:
		return

	# Own flag must be at home
	if not nm.flags_at_home.get(team_id, false):
		return

	# All checks passed — score!
	body.rpc_set_flag.rpc(-1)           # remove flag from player on all peers
	body.score += 1
	body.rpc_sync_score.rpc(body.score)
	nm.score_for_team(team_id)
	nm.respawn_flag(enemy_flag_team)    # return captured flag to enemy base
