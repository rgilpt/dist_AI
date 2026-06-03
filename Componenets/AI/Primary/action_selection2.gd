class_name ActionSelection2
extends Node

@export var actor:PhysicsBody2D = null
@export var change_level:StaticBody2D = null

@export var finite_state_machine: FiniteStateMachine = null
@export var memory_locations: MemoryLocations = null

var model_action_selection: NeuralNetwork3
const EPOCHS = 1000

@export var verbose_level = 2

var has_started = false
var set_get_next_action = false

enum actions{
	PATHFINDING_KEY,
	PATHFINDING_CHANGE_LEVEL,
	EXPLORE,
	GetPrize
}

func get_action_input(action):
	if action == null:
		return [0.5]
	var one_hot = [0]
	one_hot[action] = 1
	
	return one_hot

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	pass # Replace with function body.



func init():
	create_nn()
	#model_action_selection.load("res://data/nn_action_selection.json")
	
	#train()
	#model_action_selection.store("res://data/nn_action_selection.json")
	
	
func create_nn():
	####Inputs 13
	## current_action 5 inputs -> 0 - 1.0 each
	## player_visible 	0 - 1		-> 0 - 1.0
	## health 			0 - 100 	-> 0 - 1.0
	## player_health  	0 - 100 	-> 0 - 1.0
	## friends_nearby 	0 - 10  	-> 0 - 1.0
	## my_defense		1.0 - 2.0  	-> 0 - 1.0
	## my_attack		0 - 100  	-> 0 - 1.0
	## player_defense	1.0 - 2.0  	-> 0 - 1.0
	## player_attack	0 - 100  	-> 0 - 1.0
	
	####Outputs 5 - number of actions
	
	# 13 Inputs, 30 neurons on hidden layer, 5 Outputs
	model_action_selection = NeuralNetwork3.new(2, [6], 3)

func load_tranning_data():
	var file = "res://data/trainning_data2.json"
	var json_as_text = FileAccess.get_file_as_string(file)
	var json_as_dict = JSON.parse_string(json_as_text)
	if json_as_dict:
		#print(json_as_dict)
		return json_as_dict["data"]

func store_model():
	model_action_selection.store("res://data/model/nn_action_selection.json")

func load_model():
	model_action_selection.load("res://data/model/nn_action_selection.json")

func train():
	var inputs = load_tranning_data()
	for i in range(EPOCHS):
		var input = inputs[randi() % inputs.size()]
		model_action_selection.train(input[0], input[1])

func check_change_level_requirements():
	if change_level != null:
		return change_level.check_requirements(actor.inventory)
	else:
		return null
	
	
func get_next_action(set_inputs=null, current_success=false, temperature=0.5):
	
	#Input Vector
	var current_input = set_inputs
	var vector = []
	
	current_input[0] = (1 if current_input[0] else 0)
	var result = model_action_selection.predict(current_input)
	if verbose_level > 2:
		var out_actions = ""
		var index_r = 0
		for a in actions.keys():
			out_actions += a + ": " + "%0.2f" % result[index_r] + ", "
			index_r += 1
		print(out_actions)
	elif verbose_level > 1:
		var result_print = ""
		for r in result:
			result_print += "%0.2f" % r +", "
		print("All outputs: {result}".format({'result': result_print}))
	var result_action = get_action_temperature(temperature, result)
	if verbose_level > 1:
		print(actions.keys()[result_action])
	return result_action

func get_action_temperature(temperature, action_vector):
	var list_actions = action_vector.filter(func(proba): return proba > temperature)
	if len(list_actions) > 0:
		var select = action_vector.find(list_actions[randi() % list_actions.size()])
		return select
	else:
		var max_index = action_vector.find(action_vector.max())
		return max_index

func mapping_value_linear(input:float, min_input:float, max_input:float, min_value:float, max_value:float):
	return (input - min_value) / (max_input - min_input) * (max_value - min_value) + min_value

func start():
	has_started = true
	set_get_next_action = true

func _process(delta: float) -> void:
	if has_started:
		if set_get_next_action:
			var requirements = check_change_level_requirements()
			if requirements == null:
				return
			var inputs = [requirements, memory_locations.get_amount_keys()]
			print("Inputs")
			print(inputs)
			var next_action = get_next_action(inputs)
			match(next_action):
				actions.PATHFINDING_KEY:
					var state = finite_state_machine.get_state_name("PathFinding")
					var key_location = memory_locations.get_next_key()
					#if sequence[step].has("target_path"):
						#print(sequence[step].target_path)
						#var target = get_node("/root").get_child(0).get_node(sequence[step].target_path)
						#if target != null:
							#state.set_target(target)
					if key_location != null:
						state.set_target(key_location.obj)
						#state.set_movement_target(Vector2(key_location.location_x, 
													  #key_location.location_y))
						finite_state_machine.set_state(state)
					else:
						state = finite_state_machine.get_state_name("Explore")
						finite_state_machine.set_state(state)
						
				actions.PATHFINDING_CHANGE_LEVEL:
					var state = finite_state_machine.get_state_name("PathFinding")
					var change_location = memory_locations.get_change_of_level()
					if change_location != null:
						state.set_target(change_location.obj)
						finite_state_machine.set_state(state)
				
				actions.EXPLORE:
					var state = finite_state_machine.get_state_name("Explore")
					finite_state_machine.set_state(state)
				_:
					var state = finite_state_machine.get_state_name("Idle")
					finite_state_machine.set_state(state)
			set_get_next_action = false
	else:
		var state = finite_state_machine.get_state_name("GetPrize")
		finite_state_machine.set_state(state)
