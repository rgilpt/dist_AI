extends Camera2D

const ZOOM_STEP: float = 0.1
const ZOOM_MIN: float = 0.05
const ZOOM_MAX: float = 3.0
const PAN_BUTTON: MouseButton = MOUSE_BUTTON_MIDDLE

var _panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_pos: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	# ── Zoom with scroll wheel ─────────────────────────────────
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_toward(event.position, ZOOM_STEP)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_toward(event.position, -ZOOM_STEP)
			elif event.button_index == PAN_BUTTON:
				_panning = true
				_pan_start_mouse = event.position
				_pan_start_pos = global_position
		else:
			if event.button_index == PAN_BUTTON:
				_panning = false

	# ── Pan by dragging with middle mouse ─────────────────────
	elif event is InputEventMouseMotion and _panning:
		var delta: Vector2 = (event.position - _pan_start_mouse) / zoom
		global_position = _pan_start_pos - delta


func _zoom_toward(screen_point: Vector2, step: float) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clamp(old_zoom + step, ZOOM_MIN, ZOOM_MAX)
	if new_zoom == old_zoom:
		return

	# Keep the point under the cursor fixed in world space
	var viewport_size: Vector2 = get_viewport_rect().size
	var offset: Vector2 = (screen_point - viewport_size * 0.5) / old_zoom
	global_position += offset * (1.0 - old_zoom / new_zoom)
	zoom = Vector2(new_zoom, new_zoom)
