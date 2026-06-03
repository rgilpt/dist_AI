class_name FSMPathFinding
extends Node

@export var actor: CharacterBody2D = null
@export var navigation_agent: NavigationAgent2D = null
@export var target: Node2D = null

var name_state = "PathFinding"


func _ready() -> void:
	if actor != null and navigation_agent != null :
		navigation_agent.velocity_computed.connect(Callable(actor._on_velocity_computed))
		
func set_target(new_target):
	target = new_target
	set_movement_target(target.position)

##func set_target_position(new_target_position):
	##
	#set_movement_target(new_target_position)

func action_state():
	if target == null:
		get_parent().set_state(null)
		return
	if navigation_agent.is_navigation_finished():
		get_parent().change_state()
	
	var next_path_position: Vector2 = navigation_agent.get_next_path_position()
	var current_agent_position: Vector2 = actor.global_position
	var new_velocity: Vector2 = (next_path_position - current_agent_position).normalized() * actor.max_speed
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
	else:
		actor._on_velocity_computed(new_velocity)
	
func set_movement_target(movement_target: Vector2):
	navigation_agent.set_target_position(movement_target)
