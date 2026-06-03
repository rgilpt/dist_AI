class_name FiniteStateMachine
extends Node

var current_state = null
@export var actor: CharacterBody2D = null

@export var primary: ActionSelection2 = null

var is_on = false
var has_prize = false

func _physics_process(delta):
	if not is_on:
		return 
	if current_state != null:
		if current_state.has_method("action_state"):
			current_state.action_state()
	else:
		if primary != null:
			primary.set_get_next_action = true
			
			
func set_state(new_state):
	current_state = new_state

func force_action_state():
	if current_state != null:
		if current_state.has_method("action_state"):
			current_state.action_state()
	
func set_state_name(new_state):
	for s in get_children():
		if s.name_state == new_state:
			current_state = s
			
func get_state_name(new_state):
	for s in get_children():
		if s.name_state == new_state:
			return s
			
	return null
	
func change_state():
	if primary != null:
		primary.set_get_next_action = true
