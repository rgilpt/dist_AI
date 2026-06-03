class_name MemoryLocations
extends Node
@export var navigation_region : NavigationRegion2D = null
var my_memory = []
var explored_areas = []
enum Types
{
	CHANGE_LEVEL,
	KEY,
	RESOURCE
}
func _ready() -> void:
	if navigation_region != null:
		divide_region_polygon()
func add_memory(position, type, obj):
	var new_memory = {
		"location_x": position.x, 
		"location_y": position.y,
		"type": type,
		"obj": obj
		}
	my_memory.append(new_memory)

func get_next_key():
	for m in my_memory:
		if m.type == Types.KEY:
			return m
func get_change_of_level():
	for m in my_memory:
		if m.type == Types.CHANGE_LEVEL:
			return m
func remove_memory(obj):
	for m in my_memory:
		if m.obj == obj:
			if m.type != Types.CHANGE_LEVEL:
				my_memory.erase(m)
			return
func get_amount_keys() -> int:
	return my_memory.reduce(func(count, next): return count + 1 if next.type == Types.KEY else count, 0)

func create_exploration_areas(polygon):
	var area = -1
	if len(polygon) == 4:
		area = ((polygon[0].x * polygon[1].y - polygon[1].x * polygon[0].y) + 
				(polygon[1].x * polygon[2].y - polygon[2].x * polygon[1].y) +
				(polygon[2].x * polygon[3].y - polygon[3].x * polygon[2].y) + 
				(polygon[3].x * polygon[0].y - polygon[0].x * polygon[3].y))
	elif len(polygon) == 3:
		area = 0.5 * abs(polygon[0].x * (polygon[1].y - polygon[2].y) +
						polygon[1].x * (polygon[2].y - polygon[0].y) +
						polygon[2].x * (polygon[0].y - polygon[2].y)
		)
	var new_explored_area = {
		"polygon": polygon,
		"area": area,
		"explored": 0
	}
	return new_explored_area
	

func divide_region_polygon():
	var env_polygon:PackedVector2Array = navigation_region.navigation_polygon.get_vertices()
	#var result_polygon_convex = Geometry2D.decompose_polygon_in_convex(env_polygon)
	#
	#for p in result_polygon_convex:
		#create_exploration_areas(p)
	#create_polygons2d(result_polygon_convex)
	var polygons = divide_polygon(env_polygon)
	for p in polygons:
		var new_explored_area = create_exploration_areas(p)
		if new_explored_area.area > 40000:
			var new_polygons = divide_polygon(new_explored_area.polygon)
			for p2 in new_polygons:
				new_explored_area = create_exploration_areas(p2)
				if new_explored_area.area > 40000:
					var new_polygons2 = divide_polygon(new_explored_area.polygon)
					for p3 in new_polygons2:
						new_explored_area = create_exploration_areas(p3)
						explored_areas.append(new_explored_area)
				else:
					explored_areas.append(new_explored_area)
		else:
			explored_areas.append(new_explored_area)
		
	
	create_polygons2d(explored_areas)

func create_polygons2d(polygons):
	for p in polygons:
		var show = Polygon2D.new()
		show.set_polygon(PackedVector2Array(p.polygon))
		show.color = Color(randf(),randf(),randf(),0.1)
		get_tree().root.get_child(0).add_child.call_deferred(show)
	
	

func divide_polygon(env_polygon:PackedVector2Array):
	#var env_polygon = navigation_region.navigation_polygon
	
	
	#var cutting_polygon = Polygon2D.new()
	#cutting_polygon.set_polygon(PackedVector2Array([
		#Vector2(0, 0),
		#Vector2(10, 0),
		#Vector2(10, 10),
		#Vector2(0, 10),
	#]))
	var removed_vectors = []
	var new_p = Vector2()
	for p in env_polygon:
		new_p += p
	new_p /= len(env_polygon) 
	
	var final_polygons = []
	env_polygon.append(new_p)
	var result_polygon = Geometry2D.triangulate_delaunay(env_polygon)
	var result_polygon_convex = Geometry2D.decompose_polygon_in_convex(env_polygon)
	
	if len(result_polygon) == 0:
		removed_vectors.append(env_polygon[len(env_polygon) - 1])
		env_polygon.resize(len(env_polygon) - 1)
		env_polygon.append(new_p)
		result_polygon = Geometry2D.triangulate_polygon(env_polygon)
	
	for index in range(0, len(result_polygon), 3):
		var v1 = env_polygon[result_polygon[index]]
		var v2 = env_polygon[(result_polygon[index + 1])]
		var v3 = env_polygon[(result_polygon[index + 2])]
		
		final_polygons.append(PackedVector2Array([v1, v2, v3]))
		#var show = Polygon2D.new()
		#show.set_polygon(PackedVector2Array([v1, v2, v3]))
		#show.color = Color(randf(),randf(),randf(),)
		#get_tree().root.get_child(0).add_child.call_deferred(show)
	return final_polygons
		
		
func divide_region_polygon_():
	if navigation_region != null:
		var env_polygon:PackedVector2Array = navigation_region.navigation_polygon.get_vertices()
		#for index in env_polygon.size():
		for index in range(2):
			var v1 = env_polygon[index]
			var v2 = env_polygon[(index + 1) % len(env_polygon)]
			var v3 = env_polygon[(index + 2) % len(env_polygon)]
			var v4 = env_polygon[(index + 3) % len(env_polygon)]
			
			var area = ((v1.x * v2.y - v2.x * v1.y) + (v2.x * v3.y - v3.x * v2.y) +
				(v3.x * v4.y - v4.x * v3.y) + (v4.x * v1.y - v1.x * v4.y))
				
			explored_areas.append({
				"polygon":PackedVector2Array([v1, v2, v3, v4]),
				"area": area,
				"explored": 0
			})
			var show = Polygon2D.new()
			show.set_polygon(PackedVector2Array([v1, v2, v3, v4]))
			show.color = Color(randf(),randf(),randf(),)
			get_tree().root.get_child(0).add_child.call_deferred(show)

func store_current_position(position:Vector2):
	for explore_a in explored_areas:
		if Geometry2D.is_point_in_polygon(position, explore_a.polygon):
			explore_a.explored += 0.1
			if explore_a.explored > 1.0:
				explore_a.explored = 1.0
		else:
			explore_a.explored -= 0.01
			if explore_a.explored < 0.0:
				explore_a.explored = 0.0
				
func get_explored_value(position:Vector2):
	for explore_a in explored_areas:
		if Geometry2D.is_point_in_polygon(position, explore_a.polygon):
			return explore_a.explored
