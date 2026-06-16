extends Node
class_name LevelBuilderClaude

var source: TileSetAtlasSource
@export var tile_map: TileMapLayer
var tile_set


## slot_spawns[0] = spawn positions for slot 1, slot_spawns[1] = slot 2
var slot_spawns: Array = []
## slot_configs[i] = raw dictionary from level.json team_slots[i]
var slot_configs: Array = []

# Legacy aliases so existing code keeps compiling during transition
var blue_spawns: Array[Vector2]:
	get: return slot_spawns[0] if slot_spawns.size() > 0 else []
var red_spawns: Array[Vector2]:
	get: return slot_spawns[1] if slot_spawns.size() > 1 else []

func _ready():
	tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(32, 32)
	tile_map.tile_set = tile_set

	var texture = load("res://Assets/tilesets/GlitchHouse.png")
	if texture == null:
		printerr("Failed to load tileset!")
		return

	source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(32, 32)
	tile_set.add_source(source)

	source.create_tile(Vector2i(0, 0))  # floor
	source.create_tile(Vector2i(1, 0))  # wall

	tile_set.add_physics_layer()

	var wall_tile = source.get_tile_data(Vector2i(1, 0), 0)
	var collision_shape = [
		Vector2(-16, -16),
		Vector2(16, -16),
		Vector2(16, 16),
		Vector2(-16, 16)
	]
	wall_tile.add_collision_polygon(0)
	wall_tile.set_collision_polygon_points(0, 0, PackedVector2Array(collision_shape))


	var file = FileAccess.open("res://JSON/level.json", FileAccess.READ)
	if file == null:
		printerr("Failed to open level.json")
		return

	var json_result = JSON.parse_string(file.get_as_text())
	file.close()

	if json_result == null or typeof(json_result) != TYPE_DICTIONARY:
		printerr("Failed to parse level.json")
		return

	# Step 1: Draw all room floors
	for room in json_result.get("rooms", []):
		_build_room_floor(room)

	# Step 2: Draw all corridor floors
	for corridor in json_result.get("corridors", []):
		_build_corridor_floor(json_result, corridor)

	# Step 3: Draw all room walls (borders only, never overwrites interior)
	for room in json_result.get("rooms", []):
		_build_room_walls(room)

	# Step 4: Draw corridor walls only where no floor exists
	for corridor in json_result.get("corridors", []):
		_build_corridor_walls(json_result, corridor)

	# Step 5: Punch openings through room walls at every corridor entry
	for corridor in json_result.get("corridors", []):
		_open_corridor_entries(json_result, corridor)
	_load_team_slots(json_result)
	_build_navigation(json_result)
	print("Slots loaded: ", slot_spawns.size(), " slots")
	print("Level built successfully!")

func _load_team_slots(level_data: Dictionary) -> void:
	slot_spawns.clear()
	slot_configs.clear()
	for slot in level_data.get("team_slots", []):
		var spawns: Array[Vector2] = []
		for s in slot.get("spawns", []):
			spawns.append(Vector2(s["x"], s["y"]))
		slot_spawns.append(spawns)
		slot_configs.append(slot)

# --- Room building ---

func _build_room_floor(room: Dictionary) -> void:
	var tile_x = room["position"]["x"] / 32
	var tile_y = room["position"]["y"] / 32
	var tile_w = room["size"]["width"] / 32
	var tile_h = room["size"]["height"] / 32
	for x in range(tile_w):
		for y in range(tile_h):
			tile_map.set_cell(Vector2i(tile_x + x, tile_y + y), 0, Vector2i(0, 0))

func _build_room_walls(room: Dictionary) -> void:
	var tile_x = room["position"]["x"] / 32
	var tile_y = room["position"]["y"] / 32
	var tile_w = room["size"]["width"] / 32
	var tile_h = room["size"]["height"] / 32
	var tile_t = room.get("wall_thickness", 32) / 32

	# Top rows
	for x in range(tile_w):
		for t in range(tile_t):
			tile_map.set_cell(Vector2i(tile_x + x, tile_y + t), 0, Vector2i(1, 0))

	# Bottom rows
	for x in range(tile_w):
		for t in range(tile_t):
			tile_map.set_cell(Vector2i(tile_x + x, tile_y + tile_h - tile_t + t), 0, Vector2i(1, 0))

	# Left columns — skip corners already drawn by top/bottom
	for y in range(tile_t, tile_h - tile_t):
		for t in range(tile_t):
			tile_map.set_cell(Vector2i(tile_x + t, tile_y + y), 0, Vector2i(1, 0))

	# Right columns — skip corners already drawn by top/bottom
	for y in range(tile_t, tile_h - tile_t):
		for t in range(tile_t):
			tile_map.set_cell(Vector2i(tile_x + tile_w - tile_t + t, tile_y + y), 0, Vector2i(1, 0))


# --- Corridor building ---

func _get_corridor_start(room: Dictionary, corridor: Dictionary) -> Vector2i:
	var side: String = corridor.get("start_side", "")
	if side != "":
		return _get_room_entry_anchor(room, side)
	return Vector2i(
		room["position"]["x"] / 32 + room["size"]["width"] / 64,
		room["position"]["y"] / 32 + room["size"]["height"] / 64
	)

func _get_corridor_end(room: Dictionary, corridor: Dictionary) -> Vector2i:
	var side: String = corridor.get("end_side", "")
	if side != "":
		return _get_room_entry_anchor(room, side)
	return Vector2i(
		room["position"]["x"] / 32 + room["size"]["width"] / 64,
		room["position"]["y"] / 32 + room["size"]["height"] / 64
	)

# Returns the tile just OUTSIDE the room wall on the given side, centered
func _get_room_entry_anchor(room: Dictionary, side: String) -> Vector2i:
	var rx = room["position"]["x"] / 32
	var ry = room["position"]["y"] / 32
	var rw = room["size"]["width"] / 32
	var rh = room["size"]["height"] / 32
	# Center of each side — corridor floor draws from here
	match side:
		"top":    return Vector2i(rx + rw / 2, ry - 1)
		"bottom": return Vector2i(rx + rw / 2, ry + rh)
		"left":   return Vector2i(rx - 1,      ry + rh / 2)
		"right":  return Vector2i(rx + rw,     ry + rh / 2)
	return Vector2i(rx + rw / 2, ry + rh / 2)

func _build_corridor_floor(level_data: Dictionary, corridor: Dictionary) -> void:
	var start_room := _find_room(level_data, corridor.get("start_room", ""))
	var end_room   := _find_room(level_data, corridor.get("end_room", ""))
	if start_room.is_empty() or end_room.is_empty():
		return
	var corr_w: int = corridor.get("width", 128) / 32
	var s_center := _get_corridor_start(start_room, corridor)
	var e_center := _get_corridor_end(end_room, corridor)
	var start_side: String = corridor.get("start_side", "")
	var end_side: String   = corridor.get("end_side", "")

	var is_vertical   := (start_side in ["top", "bottom"]) and (end_side in ["top", "bottom"])
	var is_horizontal := (start_side in ["left", "right"]) and (end_side in ["left", "right"])

	if is_vertical:
		var y_min := mini(s_center.y, e_center.y)
		var y_max := maxi(s_center.y, e_center.y)
		for y in range(y_min, y_max + 1):
			for w in range(corr_w):
				tile_map.set_cell(Vector2i(s_center.x + w, y), 0, Vector2i(0, 0))

	elif is_horizontal:
		var x_min := mini(s_center.x, e_center.x)
		var x_max := maxi(s_center.x, e_center.x)
		for x in range(x_min, x_max + 1):
			for w in range(corr_w):
				tile_map.set_cell(Vector2i(x, s_center.y + w), 0, Vector2i(0, 0))

	else:
		# L-shaped: horizontal first then vertical
		var x_min := mini(s_center.x, e_center.x)
		var x_max := maxi(s_center.x, e_center.x)
		for x in range(x_min, x_max + 1):
			for w in range(corr_w):
				tile_map.set_cell(Vector2i(x, s_center.y + w), 0, Vector2i(0, 0))
		var y_min := mini(s_center.y, e_center.y)
		var y_max := maxi(s_center.y, e_center.y)
		for y in range(y_min, y_max + 1):
			for w in range(corr_w):
				tile_map.set_cell(Vector2i(e_center.x + w, y), 0, Vector2i(0, 0))

func _build_corridor_walls(level_data: Dictionary, corridor: Dictionary) -> void:
	var start_room := _find_room(level_data, corridor.get("start_room", ""))
	var end_room   := _find_room(level_data, corridor.get("end_room", ""))
	if start_room.is_empty() or end_room.is_empty():
		return
	var corr_w: int = corridor.get("width", 128) / 32
	var s_center := _get_corridor_start(start_room, corridor)
	var e_center := _get_corridor_end(end_room, corridor)
	var start_side: String = corridor.get("start_side", "")
	var end_side: String   = corridor.get("end_side", "")

	var is_vertical   := (start_side in ["top", "bottom"]) and (end_side in ["top", "bottom"])
	var is_horizontal := (start_side in ["left", "right"]) and (end_side in ["left", "right"])

	if is_vertical:
		var y_min := mini(s_center.y, e_center.y)
		var y_max := maxi(s_center.y, e_center.y)
		for y in range(y_min, y_max + 1):
			var wl := Vector2i(s_center.x - 1, y)
			var wr := Vector2i(s_center.x + corr_w, y)
			if tile_map.get_cell_atlas_coords(wl) != Vector2i(0, 0):
				tile_map.set_cell(wl, 0, Vector2i(1, 0))
			if tile_map.get_cell_atlas_coords(wr) != Vector2i(0, 0):
				tile_map.set_cell(wr, 0, Vector2i(1, 0))

	elif is_horizontal:
		var x_min := mini(s_center.x, e_center.x)
		var x_max := maxi(s_center.x, e_center.x)
		for x in range(x_min, x_max + 1):
			var wt := Vector2i(x, s_center.y - 1)
			var wb := Vector2i(x, s_center.y + corr_w)
			if tile_map.get_cell_atlas_coords(wt) != Vector2i(0, 0):
				tile_map.set_cell(wt, 0, Vector2i(1, 0))
			if tile_map.get_cell_atlas_coords(wb) != Vector2i(0, 0):
				tile_map.set_cell(wb, 0, Vector2i(1, 0))

	else:
		var x_min := mini(s_center.x, e_center.x)
		var x_max := maxi(s_center.x, e_center.x)
		for x in range(x_min, x_max + 1):
			var wt := Vector2i(x, s_center.y - 1)
			var wb := Vector2i(x, s_center.y + corr_w)
			if tile_map.get_cell_atlas_coords(wt) != Vector2i(0, 0):
				tile_map.set_cell(wt, 0, Vector2i(1, 0))
			if tile_map.get_cell_atlas_coords(wb) != Vector2i(0, 0):
				tile_map.set_cell(wb, 0, Vector2i(1, 0))
		var y_min := mini(s_center.y, e_center.y)
		var y_max := maxi(s_center.y, e_center.y)
		for y in range(y_min, y_max + 1):
			var wl := Vector2i(e_center.x - 1, y)
			var wr := Vector2i(e_center.x + corr_w, y)
			if tile_map.get_cell_atlas_coords(wl) != Vector2i(0, 0):
				tile_map.set_cell(wl, 0, Vector2i(1, 0))
			if tile_map.get_cell_atlas_coords(wr) != Vector2i(0, 0):
				tile_map.set_cell(wr, 0, Vector2i(1, 0))

func _open_corridor_entries(level_data: Dictionary, corridor: Dictionary) -> void:
	var start_room := _find_room(level_data, corridor.get("start_room", ""))
	var end_room   := _find_room(level_data, corridor.get("end_room", ""))
	if start_room.is_empty() or end_room.is_empty():
		return
	var corr_w: int = corridor.get("width", 128) / 32
	var start_side: String = corridor.get("start_side", "")
	var end_side: String   = corridor.get("end_side", "")

	var s_anchor := _get_room_entry_anchor(start_room, start_side) if start_side != "" else Vector2i(0,0)
	var e_anchor := _get_room_entry_anchor(end_room, end_side) if end_side != "" else Vector2i(0,0)

	if start_side != "":
		# For vertical corridors: use start anchor X for both openings
		# For horizontal corridors: use start anchor Y for both openings
		_open_room_entry(start_room, start_side, s_anchor, corr_w)
	if end_side != "":
		# End opening must align with where corridor actually arrives
		var aligned_anchor := e_anchor
		if end_side in ["left", "right"]:
			# Horizontal corridor: Y comes from start anchor
			aligned_anchor = Vector2i(e_anchor.x, s_anchor.y)
		elif end_side in ["top", "bottom"]:
			# Vertical corridor: X comes from start anchor
			aligned_anchor = Vector2i(s_anchor.x, e_anchor.y)
		_open_room_entry(end_room, end_side, aligned_anchor, corr_w)

func _open_room_entry(room: Dictionary, side: String, anchor: Vector2i, corr_w: int) -> void:
	var rx = room["position"]["x"] / 32
	var ry = room["position"]["y"] / 32
	var rw = room["size"]["width"] / 32
	var rh = room["size"]["height"] / 32
	var rt = room.get("wall_thickness", 32) / 32
	print("Opening ", room.get("name","?"), " side=", side, " anchor=", anchor, " corr_w=", corr_w, " rt=", rt)
	match side:
		"top":
			for w in range(corr_w):
				for t in range(rt):
					tile_map.set_cell(Vector2i(anchor.x + w, ry + t), 0, Vector2i(0, 0))
		"bottom":
			for w in range(corr_w):
				for t in range(rt):
					tile_map.set_cell(Vector2i(anchor.x + w, ry + rh - rt + t), 0, Vector2i(0, 0))
		"left":
			for w in range(corr_w):
				for t in range(rt):
					tile_map.set_cell(Vector2i(rx + t, anchor.y + w), 0, Vector2i(0, 0))
		"right":
			for w in range(corr_w):
				for t in range(rt):
					tile_map.set_cell(Vector2i(rx + rw - rt + t, anchor.y + w), 0, Vector2i(0, 0))
# --- Helpers ---

func _find_room(level_data: Dictionary, name: String) -> Dictionary:
	for room in level_data.get("rooms", []):
		if room.get("name", "") == name:
			return room
	return {}

# ── Navigation (explicit NavigationRegion2D nodes) ────────────────────────────
#
# One region per room interior + one per corridor segment.
# Corridor polygons extend to the inner wall edge of each connected room so
# adjacent regions share an edge and the NavigationServer merges them into a
# single connected mesh.

func _build_navigation(level_data: Dictionary) -> void:
	for room in level_data.get("rooms", []):
		_nav_room(room)
	for corridor in level_data.get("corridors", []):
		_nav_corridor(level_data, corridor)


func _nav_room(room: Dictionary) -> void:
	var rx := float(room["position"]["x"])
	var ry := float(room["position"]["y"])
	var rw := float(room["size"]["width"])
	var rh := float(room["size"]["height"])
	var wt := float(room.get("wall_thickness", 32))
	_nav_add_rect(
		Vector2(rx + wt, ry + wt),
		Vector2(rx + rw - wt, ry + rh - wt)
	)


func _nav_corridor(level_data: Dictionary, corridor: Dictionary) -> void:
	var s_room := _find_room(level_data, corridor.get("start_room", ""))
	var e_room := _find_room(level_data, corridor.get("end_room", ""))
	if s_room.is_empty() or e_room.is_empty():
		return

	var cw      := float(corridor.get("width", 128))   # corridor width in pixels
	var s_side  : String = corridor.get("start_side", "")
	var e_side  : String = corridor.get("end_side", "")

	# Tile-space anchors (one tile outside the room wall on each side)
	var s_anchor := _get_corridor_start(s_room, corridor)
	var e_anchor := _get_corridor_end(e_room, corridor)

	var is_vert  := (s_side in ["top", "bottom"]) and (e_side in ["top", "bottom"])
	var is_horiz := (s_side in ["left", "right"])  and (e_side in ["left", "right"])

	if is_horiz:
		# Corridor runs left–right.
		# x spans from inner wall edge of start room to inner wall edge of end room
		# (this covers both the punched openings and the corridor floor between them).
		var x0 := _nav_inner_edge(s_room, s_side)
		var x1 := _nav_inner_edge(e_room, e_side)
		var y0 := s_anchor.y * 32.0
		_nav_add_rect(
			Vector2(minf(x0, x1), y0),
			Vector2(maxf(x0, x1), y0 + cw)
		)

	elif is_vert:
		# Corridor runs top–bottom.
		var y0 := _nav_inner_edge(s_room, s_side)
		var y1 := _nav_inner_edge(e_room, e_side)
		var x0 := s_anchor.x * 32.0
		_nav_add_rect(
			Vector2(x0, minf(y0, y1)),
			Vector2(x0 + cw, maxf(y0, y1))
		)

	else:
		# L-shaped: horizontal leg first, then vertical leg.
		# Corner is at (e_anchor.x, s_anchor.y) in tile space.
		var cx := e_anchor.x * 32.0   # corner x in pixels
		var cy := s_anchor.y * 32.0   # corner y in pixels

		# Horizontal leg: from start room inner edge to corner (+ cw so it covers corner area)
		var hx0 := _nav_inner_edge(s_room, s_side)
		_nav_add_rect(
			Vector2(minf(hx0, cx + cw), cy),
			Vector2(maxf(hx0, cx + cw), cy + cw)
		)
		# Vertical leg: from corner to end room inner edge (overlap with horiz leg at corner)
		var vy := _nav_inner_edge(e_room, e_side)
		_nav_add_rect(
			Vector2(cx, minf(cy, vy)),
			Vector2(cx + cw, maxf(cy + cw, vy))
		)


## Returns the pixel coordinate of the inner face of a room wall on the given side.
## This is where the room interior meets the wall (and where the corridor begins).
func _nav_inner_edge(room: Dictionary, side: String) -> float:
	var rx := float(room["position"]["x"])
	var ry := float(room["position"]["y"])
	var rw := float(room["size"]["width"])
	var rh := float(room["size"]["height"])
	var wt := float(room.get("wall_thickness", 32))
	match side:
		"right":  return rx + rw - wt
		"left":   return rx + wt
		"bottom": return ry + rh - wt
		"top":    return ry + wt
	return 0.0


## Create a NavigationRegion2D with a simple rectangular polygon.
## Uses direct vertex + index assignment — avoids make_polygons_from_outlines()
## which produces empty polygons in Godot 4 due to Clipper2 winding issues.
func _nav_add_rect(top_left: Vector2, bottom_right: Vector2) -> void:
	var region := NavigationRegion2D.new()
	var poly   := NavigationPolygon.new()
	poly.agent_radius = 18.0
	# Four corners: tl, tr, br, bl
	poly.vertices = PackedVector2Array([
		top_left,
		Vector2(bottom_right.x, top_left.y),
		bottom_right,
		Vector2(top_left.x, bottom_right.y),
	])
	# Two triangles covering the rectangle
	poly.add_polygon(PackedInt32Array([0, 1, 2]))
	poly.add_polygon(PackedInt32Array([0, 2, 3]))
	region.navigation_polygon = poly
	get_parent().add_child(region)
