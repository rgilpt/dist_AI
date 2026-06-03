class_name FSMExplore
extends Node

@export var actor: CharacterBody2D = null
var name_state = "Explore"

@export var navigation_region: NavigationRegion2D = null
@export var memory_locations: MemoryLocations = null
func action_state():
	actor.velocity = Vector2()
	select_target()



func select_target():
	var result_targets = select_n_targets(4)
	if len(result_targets) < 1:
		return
	var selected_target_point = result_targets[0]
	var current_highscore = 0
	var new_score = 0
	for t in result_targets:
		new_score = get_score(t)
		print(new_score)
		if new_score > current_highscore:
			selected_target_point = t
			current_highscore = new_score
	change_state_target(selected_target_point)
	#if navigation_region == null:
		#return
	#
	#var delta_vector = Vector2.from_angle(randf_range(0, 2 * PI)) * randf_range(50,500)
	#var target_point = actor.global_position + delta_vector
	#
	#var env_polygon:PackedVector2Array = navigation_region.navigation_polygon.get_vertices()
	#var result = Geometry2D.is_point_in_polygon(target_point, env_polygon)
	#if result:
		#change_state_target(target_point)
		
func change_state_target(target_point):
	
	var state = get_parent().get_state_name("PathFinding")
	if target_point != null:
		state.set_target(actor)
		state.set_movement_target(target_point)
		get_parent().set_state(state)

func select_possible_target():
	var delta_vector = Vector2.from_angle(randf_range(0, 2 * PI)) * randf_range(50,1000)
	var target_point = actor.global_position + delta_vector
	
	var env_polygon:PackedVector2Array = navigation_region.navigation_polygon.get_vertices()
	var result = Geometry2D.is_point_in_polygon(target_point, env_polygon)
	if result:
		return target_point
	
	return null

func select_n_targets(n=3):
	var possible_targets = []
	for i in range(n):
		var new_target = select_possible_target()
		if new_target != null:
			possible_targets.append(new_target)
			
	return possible_targets

func get_score(point:Vector2):
	if memory_locations != null:
		return 1 - memory_locations.get_explored_value(point)
	return 0
