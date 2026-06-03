# NeuralNetwork2.gd
# Supports multiple hidden layers and transfer learning.
#
# Basic usage:
#   NeuralNetwork2.new(7, [32, 16], 4)
#   Creates: 7 -> 32 -> 16 -> 4
#
# Transfer learning — load a pretrained network then expand it:
#
#   var nn = NeuralNetwork2.new(7, [32, 16], 4)
#   nn.load("res://nn2.json")               # load pretrained 7->32->16->4
#   nn.expand_inputs(10)                    # grow to 10 inputs, keep old weights
#   nn.expand_hidden_layer(0, 64)           # grow hidden layer 0 to 64 neurons
#   nn.expand_hidden_layer(1, 32)           # grow hidden layer 1 to 32 neurons
#   # now: 10 -> 64 -> 32 -> 4, old neurons unchanged, new ones random-small
#   # keep training — old knowledge is preserved

class_name NeuralNetwork3

@export var input_nodes:        int
@export var hidden_layer_sizes: Array  # e.g. [32, 16] or [64, 32, 16]
@export var output_nodes:       int

# One weight matrix and one bias matrix per layer transition.
# For N hidden layers there are N+1 transitions:
#   weights[0] = input       -> hidden[0]
#   weights[1] = hidden[0]   -> hidden[1]
#   ...
#   weights[N] = hidden[N-1] -> output
var weights: Array = []  # Array of Matrix
var biases:  Array = []  # Array of Matrix

# Learning parameters
var learning_rate: float = 0.003

# All hidden layers share the same activation.
# The output layer has its own activation.
var hidden_activation_function:  Callable
var hidden_activation_dfunction: Callable
var output_activation_function:  Callable
var output_activation_dfunction: Callable

@export var output_activation: String = "sigmoid"

# Scale for new weights added during expansion.
# Small values preserve stability of pretrained network —
# new neurons/inputs start with near-zero influence.
const EXPANSION_WEIGHT_SCALE: float = 0.01

# ===========================
# Init
# ===========================

func _init(_input_nodes: int, _hidden_layer_sizes: Array, _output_nodes: int):
	input_nodes        = _input_nodes
	hidden_layer_sizes = _hidden_layer_sizes
	output_nodes       = _output_nodes

	assert(hidden_layer_sizes.size() > 0,
		"NeuralNetwork2: hidden_layer_sizes must have at least 1 element")

	_build_matrices()
	set_learning_rate(learning_rate)
	set_activation_function(Activation.sigmoid, Activation.dsigmoid)
	set_output_activation(output_activation)

func _build_matrices() -> void:
	weights.clear()
	biases.clear()

	var layer_sizes = _get_all_layer_sizes()
	for i in range(layer_sizes.size() - 1):
		var rows = layer_sizes[i + 1]
		var cols = layer_sizes[i]
		weights.append(Matrix.generate_random_matrix(Matrix.new(rows, cols)))
		biases.append( Matrix.generate_random_matrix(Matrix.new(rows, 1)))

func _get_all_layer_sizes() -> Array:
	var sizes = [input_nodes]
	for h in hidden_layer_sizes:
		sizes.append(int(h))
	sizes.append(output_nodes)
	return sizes

# ===========================
# Activation Setup
# ===========================

func set_learning_rate(_lr: float = 0.003) -> void:
	learning_rate = _lr

func set_activation_function(callback: Callable, dcallback: Callable) -> void:
	hidden_activation_function  = callback
	hidden_activation_dfunction = dcallback

func set_output_activation(mode: String) -> void:
	match mode.to_lower():
		"sigmoid":
			output_activation_function  = Activation.sigmoid
			output_activation_dfunction = Activation.dsigmoid
		"tanh":
			output_activation_function  = Activation.tanh_func
			output_activation_dfunction = Activation.dtanh
		"raw":
			output_activation_function  = Activation.linear_func
			output_activation_dfunction = Activation.dlinear
		_:
			pass

# ===========================
# Transfer Learning — Expand Inputs
#
# Grows the input layer from input_nodes to new_input_count.
# Only weights[0] (input->hidden[0]) is affected.
# Existing columns (old inputs) are kept exactly as trained.
# New columns (new inputs) are initialized with small random weights
# so they start with near-zero influence and learn gradually.
#
# Example:
#   Network trained with 7 inputs.
#   nn.expand_inputs(10)  →  now accepts 10 inputs.
#   Old 7-input weights unchanged, 3 new input columns added.
# ===========================

func expand_inputs(new_input_count: int) -> void:
	assert(new_input_count > input_nodes,
		"expand_inputs: new_input_count must be greater than current input_nodes")

	var added_cols = new_input_count - input_nodes
	var old_w      = weights[0]   # shape: (hidden[0] x old_inputs)

	# Build new weight matrix: (hidden[0] x new_input_count)
	# Left block  = old weights (copied exactly)
	# Right block = small random weights for new inputs
	var new_w = Matrix.new(old_w.rows, new_input_count)
	for row in range(old_w.rows):
		# Copy existing weights
		for col in range(old_w.cols):
			new_w.data[row][col] = old_w.data[row][col]
		# Small random weights for new inputs
		for col in range(old_w.cols, new_input_count):
			new_w.data[row][col] = randf_range(-EXPANSION_WEIGHT_SCALE, EXPANSION_WEIGHT_SCALE)

	weights[0]  = new_w
	input_nodes = new_input_count
	print("NeuralNetwork2: inputs expanded from ", old_w.cols, " to ", new_input_count)

# ===========================
# Transfer Learning — Expand Hidden Layer
#
# Grows hidden layer [layer_index] from its current size to new_size.
# Affects two weight matrices:
#   weights[layer_index]     = prev_layer -> this hidden layer  (add rows)
#   weights[layer_index + 1] = this hidden layer -> next layer  (add cols)
# And one bias matrix:
#   biases[layer_index]      = bias for this hidden layer       (add rows)
#
# Existing neurons are kept exactly as trained.
# New neurons start with small random weights and zero bias.
#
# Example:
#   Hidden layer 0 has 32 neurons.
#   nn.expand_hidden_layer(0, 64)  →  hidden layer 0 now has 64 neurons.
#   Old 32 neurons unchanged, 32 new neurons added with small weights.
# ===========================

func expand_hidden_layer(layer_index: int, new_size: int) -> void:
	assert(layer_index >= 0 and layer_index < hidden_layer_sizes.size(),
		"expand_hidden_layer: layer_index out of range")
	var old_size = int(hidden_layer_sizes[layer_index])
	assert(new_size > old_size,
		"expand_hidden_layer: new_size must be greater than current size")

	var added = new_size - old_size

	# --- Expand weights[layer_index]: add rows (new neurons in this layer) ---
	# Shape change: (old_size x prev_cols) -> (new_size x prev_cols)
	var w_in     = weights[layer_index]
	var new_w_in = Matrix.new(new_size, w_in.cols)
	for row in range(w_in.rows):
		for col in range(w_in.cols):
			new_w_in.data[row][col] = w_in.data[row][col]
	# New neuron rows — small random incoming weights
	for row in range(w_in.rows, new_size):
		for col in range(w_in.cols):
			new_w_in.data[row][col] = randf_range(-EXPANSION_WEIGHT_SCALE, EXPANSION_WEIGHT_SCALE)
	weights[layer_index] = new_w_in

	# --- Expand biases[layer_index]: add rows ---
	# Shape change: (old_size x 1) -> (new_size x 1)
	var b_old = biases[layer_index]
	var b_new = Matrix.new(new_size, 1)
	for row in range(b_old.rows):
		b_new.data[row][0] = b_old.data[row][0]
	# New neuron biases start at zero
	for row in range(b_old.rows, new_size):
		b_new.data[row][0] = 0.0
	biases[layer_index] = b_new

	# --- Expand weights[layer_index + 1]: add columns (new neurons feed forward) ---
	# Shape change: (next_rows x old_size) -> (next_rows x new_size)
	var w_out     = weights[layer_index + 1]
	var new_w_out = Matrix.new(w_out.rows, new_size)
	for row in range(w_out.rows):
		# Copy existing outgoing weights
		for col in range(w_out.cols):
			new_w_out.data[row][col] = w_out.data[row][col]
		# New neuron columns — small random outgoing weights
		for col in range(w_out.cols, new_size):
			new_w_out.data[row][col] = randf_range(-EXPANSION_WEIGHT_SCALE, EXPANSION_WEIGHT_SCALE)
	weights[layer_index + 1] = new_w_out

	# Update the recorded hidden layer size
	hidden_layer_sizes[layer_index] = new_size
	print("NeuralNetwork2: hidden layer ", layer_index,
		  " expanded from ", old_size, " to ", new_size)

# ===========================
# Prediction
# ===========================

func predict(input_array: Array) -> Array:
	var activation = Matrix.build_matrix_from_array(input_array)
	var num_layers = weights.size()

	for i in range(num_layers):
		var z = Matrix.multiply_matrices(weights[i], activation)
		z = Matrix.add_matrices(z, biases[i])
		if i == num_layers - 1:
			activation = Matrix.apply_function_to_matrix(z, output_activation_function)
		else:
			activation = Matrix.apply_function_to_matrix(z, hidden_activation_function)

	return Matrix.convert_matrix_to_array(activation)

# ===========================
# Training (direct target)
# ===========================

func train(input_array: Array, target_array: Array) -> void:
	var activations   = _forward_pass(input_array)
	var targets       = Matrix.build_matrix_from_array(target_array)
	var outputs       = activations[activations.size() - 1]
	var output_errors = Matrix.subtract_matrices(targets, outputs)
	_backward_pass(activations, output_errors)

# ===========================
# Gradient Application (experience replay)
# ===========================

func apply_gradient(input_array: Array, _gradients_array: Array, output_errors_array: Array) -> void:
	var activations   = _forward_pass(input_array)
	var output_errors = Matrix.build_matrix_from_array(output_errors_array)
	_backward_pass(activations, output_errors)

# ===========================
# Forward Pass (internal)
# Returns all layer activations including input as activations[0].
#   activations[0]   = input
#   activations[1]   = hidden layer 0 output
#   activations[N]   = hidden layer N-1 output
#   activations[N+1] = output layer
# ===========================

func _forward_pass(input_array: Array) -> Array:
	var activations = []
	var activation  = Matrix.build_matrix_from_array(input_array)
	activations.append(activation)

	var num_layers = weights.size()
	for i in range(num_layers):
		var z = Matrix.multiply_matrices(weights[i], activation)
		z = Matrix.add_matrices(z, biases[i])
		if i == num_layers - 1:
			activation = Matrix.apply_function_to_matrix(z, output_activation_function)
		else:
			activation = Matrix.apply_function_to_matrix(z, hidden_activation_function)
		activations.append(activation)

	return activations

# ===========================
# Backward Pass (internal)
# Walks backwards from output to first hidden layer.
# Transpose BEFORE updating so error propagation uses old weights.
# ===========================

func _backward_pass(activations: Array, output_errors: Matrix) -> void:
	var num_layers = weights.size()
	var errors     = output_errors

	for i in range(num_layers - 1, -1, -1):
		var activation = activations[i + 1]
		var prev_act   = activations[i]

		var deriv_fn: Callable
		if i == num_layers - 1:
			deriv_fn = output_activation_dfunction
		else:
			deriv_fn = hidden_activation_dfunction

		# Transpose BEFORE updating weights
		var weights_transposed = Matrix.tranpose_matrix(weights[i])

		var deltas = Matrix.apply_function_to_matrix(activation, deriv_fn)
		deltas     = Matrix.multiply_matrices_element_wise(deltas, errors)
		deltas     = Matrix.multiply_matrix_by_scalar(deltas, learning_rate)

		var prev_transposed = Matrix.tranpose_matrix(prev_act)
		var weight_deltas   = Matrix.multiply_matrices(deltas, prev_transposed)
		weights[i]          = Matrix.add_matrices(weights[i], weight_deltas)
		biases[i]           = Matrix.add_matrices(biases[i], deltas)

		# Propagate errors to previous layer using OLD weights
		errors = Matrix.multiply_matrices(weights_transposed, errors)

# ===========================
# Copy
# ===========================

func copy(other: NeuralNetwork3) -> void:
	assert(weights.size() == other.weights.size(),
		"NeuralNetwork2.copy: layer count mismatch")
	for i in range(weights.size()):
		weights[i].copy(other.weights[i])
		biases[i].copy(other.biases[i])

# ===========================
# Store
# ===========================

func store(filename: String = "res://nn2.json") -> void:
	var my_json = {}
	my_json["structure"] = {
		"input_nodes":        input_nodes,
		"hidden_layer_sizes": hidden_layer_sizes,
		"output_nodes":       output_nodes
	}
	my_json["layers"] = []
	for i in range(weights.size()):
		my_json["layers"].append({
			"weight_rows":   weights[i].rows,
			"weight_cols":   weights[i].cols,
			"weight_values": Matrix.convert_matrix_to_array(weights[i]),
			"bias_rows":     biases[i].rows,
			"bias_cols":     biases[i].cols,
			"bias_values":   Matrix.convert_matrix_to_array(biases[i]),
		})
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(my_json, "\t"))
		file.close()

# ===========================
# Load
# FIX: cast all JSON numbers to int — JSON has no integer type so
# everything loads as float. Matrix.new() and range() need real ints.
# After loading, call expand_inputs() or expand_hidden_layer() if
# you want to grow the architecture and keep training.
# ===========================

func load(filename: String = "res://nn2.json") -> Error:
	var file = FileAccess.open(filename, FileAccess.READ)
	if file == null:
		return ERR_FILE_CANT_OPEN

	var json_string = file.get_as_text()
	file.close()

	var json  = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		return error

	var my_json  = json.data
	input_nodes  = int(my_json["structure"]["input_nodes"])
	output_nodes = int(my_json["structure"]["output_nodes"])

	# Cast each hidden layer size to int
	hidden_layer_sizes = []
	for size in my_json["structure"]["hidden_layer_sizes"]:
		hidden_layer_sizes.append(int(size))

	# Rebuild empty matrices with correct sizes
	_build_matrices()

	# Fill matrices from saved values
	var layers = my_json["layers"]
	for i in range(layers.size()):
		var l = layers[i]
		weights[i] = Matrix.build_matrix_from_array_rows_cols(
			l["weight_values"],
			Matrix.new(int(l["weight_rows"]), int(l["weight_cols"]))
		)
		biases[i] = Matrix.build_matrix_from_array_rows_cols(
			l["bias_values"],
			Matrix.new(int(l["bias_rows"]), int(l["bias_cols"]))
		)

	print("NeuralNetwork2: loaded from ", filename,
		  " | architecture: ", input_nodes, " -> ",
		  hidden_layer_sizes, " -> ", output_nodes)
	return OK
