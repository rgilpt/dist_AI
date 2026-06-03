class_name Activation

static func sigmoid(value: float, _row: int, _col: int) -> float:
	return 1.0 / (1.0 + exp(-value))

static func dsigmoid(value: float, _row: int, _col: int) -> float:
	return value * (1.0 - value)

static func tanh_func(value: float, _row: int, _col: int) -> float:
	return (exp(value) - exp(-value)) / (exp(value) + exp(-value))

static func dtanh(value: float, _row: int, _col: int) -> float:
	return 1.0 - value * value

static func linear_func(value: float, _row: int, _col: int) -> float:
	return value

static func dlinear(_value: float, _row: int, _col: int) -> float:
	return 1.0
