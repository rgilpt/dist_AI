class_name FSMReturnPrize
extends Node

## Secondary-control state: carry the prize back to the team's HomeZone.
##
## Flow:
##   1. If actor no longer carries the prize (scored or dropped) → change_state.
##   2. Locate this team's HomeZone node (cached).
##   3. Hand off movement to PathFinding, targeting the HomeZone position.
##      HomeZone.gd detects the arrival and calls on_prize_scored() automatically.

@export var actor: CharacterBody2D = null

var name_state = "ReturnPrize"

## Cached HomeZone for this NPC's team.
var _home_zone: Node2D = null


func action_state() -> void:
	# Prize no longer held — scored or dropped; let primary re-evaluate
	if actor.get("carries_prize") != true:
		get_parent().change_state()
		return

	# Resolve the team's HomeZone (search once, then cache)
	if not is_instance_valid(_home_zone):
		_home_zone = _find_home_zone()

	# Decide navigation target
	var target_pos: Vector2
	if is_instance_valid(_home_zone):
		target_pos = _home_zone.global_position
	else:
		# Fallback: use the spawn position stored on the actor
		target_pos = actor.get("home_position")
		if target_pos == Vector2.ZERO:
			actor.velocity = Vector2.ZERO
			return

	var path_state = get_parent().get_state_name("PathFinding")
	if path_state == null:
		# No PathFinding wired up — move directly as fallback
		var dir := (target_pos - actor.global_position)
		actor.velocity = Vector2.ZERO if dir.length() < 20.0 \
				else dir.normalized() * actor.get("max_speed")
		return

	# target must be non-null so PathFinding doesn't bail immediately
	path_state.target = _home_zone if is_instance_valid(_home_zone) else actor
	path_state.set_movement_target(target_pos)
	get_parent().set_state(path_state)
	get_parent().force_action_state()


## Walk the scene tree to find the HomeZone that belongs to this NPC's team.
func _find_home_zone() -> Node2D:
	var my_team: int = actor.get("team_id")
	for node in actor.get_tree().get_nodes_in_group("home_zone"):
		if node.get("team_id") == my_team:
			return node as Node2D
	return null
