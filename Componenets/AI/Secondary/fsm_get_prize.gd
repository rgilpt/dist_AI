class_name FSMGetPrize
extends Node

## Secondary-control state: navigate to the prize chest and receive the prize.
##
## Flow:
##   1. If the actor already carries the prize → hand back to primary (change_state).
##   2. If the chest doesn't exist yet or the prize is already taken → change_state.
##   3. Otherwise → hand off to PathFinding to walk to the chest.
##      Chest.gd's Area2D awards the prize automatically when the NPC arrives.

@export var actor: CharacterBody2D = null

var name_state = "GetPrize"

## Cached reference to the prize chest; re-resolved if it becomes invalid.
var _chest: Node2D = null


func action_state() -> void:
	# Already carrying the prize — nothing more to do here
	if actor.get("carries_prize") == true:
		get_parent().change_state()
		return

	# Resolve chest (cached to avoid tree searches every frame)
	if not is_instance_valid(_chest):
		_chest = actor.get_tree().get_first_node_in_group("chest")

	if not is_instance_valid(_chest):
		# Chest not spawned yet — stay idle until it appears
		actor.velocity = Vector2.ZERO
		return

	# Prize already taken by someone else — let primary re-evaluate
	if _chest.get("prize_available") == false:
		get_parent().change_state()
		return

	# Hand off movement to the PathFinding state
	var path_state = get_parent().get_state_name("PathFinding")
	if path_state == null:
		# No PathFinding state available — move directly as fallback
		var dir := (_chest.global_position - actor.global_position)
		actor.velocity = Vector2.ZERO if dir.length() < 20.0 \
				else dir.normalized() * actor.get("max_speed")
		return

	path_state.set_movement_target(_chest.global_position)
	path_state.target = _chest
	get_parent().set_state(path_state)
	get_parent().force_action_state()
