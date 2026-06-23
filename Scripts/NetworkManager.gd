extends Node
class_name NetworkManager

var _peer: WebSocketMultiplayerPeer

var flag_instances: Dictionary = {}   # flag_team_id -> Node2D (null if carried)
var flags_at_home: Dictionary = {}    # flag_team_id -> bool
var scores: Dictionary = {}           # team_id -> int
var team_counts: Dictionary = {}      # team_id -> int  (populated from teams.json)
var peer_teams: Dictionary = {}
## Maps team_id -> slot index (0 or 1). Assigned at game start from level.json slots.
var team_slot_map: Dictionary = {}

var is_game_active: bool = false
var game_timer: float = 180.0

var server_port: int = 7777
var is_host: bool = false

var max_players: int = 2
var max_per_team: int = 1

## Default URL used when no --address argument is given.
## Change to wss:// if IIS has SSL enabled on the site.
const DEFAULT_WS_URL: String = "wss://mflxp.pt/game_ai"

signal flag_spawned
signal flag_picked_up
signal flag_scored
signal game_over
signal all_players_joined
signal team_data_updated(counts: Dictionary, your_team: int)
signal game_started
signal game_mode_updated
signal discovery_status(message: String)
signal sent_to_lobby
signal released_from_lobby
signal round_ended(duration: float)
signal role_waiting(count: int, total: int)
signal cheat_detected(peer_id: int, description: String)

var _initialized: bool = false
var player_scene = preload("res://Scenes/Player.tscn")
var npc_scene = preload("res://Scenes/NPC.tscn")
var chest_scene = preload("res://Scenes/Chest.tscn")
var ammo_drop_scene = preload("res://Scenes/AmmoDrop.tscn")
var team_config: Dictionary = {}

## Active ammo drop nodes, keyed by their unique name.
var _ammo_drops: Dictionary = {}
var _ammo_drop_counter: int = 0

## Peers waiting to join the next round.
var lobby_peers: Array[int] = []

## Role constants used by rpc_claim_selection / _resolve_selections.
const ROLE_ATTACK: int = 0
const ROLE_DEFEND: int  = 1

## Server-side collection of {team, role} preferences before game start.
## Cleared by _resolve_selections() and reset_game().
var peer_role_prefs: Dictionary = {}

## How long (seconds) the post-game lobby lasts before auto-returning to team-select.
const LOBBY_DURATION: float = 12.0
## Set to false by reset_game() to cancel a pending end-game countdown.
var _end_game_pending: bool = false

## Server-side anti-cheat: per-peer violation data {count, last_report_time}.
var _cheat_reports: Dictionary = {}

## Team assigned to slot 0 (the "attacker" — must capture the prize).
## Set in _start_game() once team_slot_map is known.
var attacker_team_id: int = -1
## Team assigned to slot 1 (the "defender" — wins if time runs out).
var defender_team_id: int = -1
## All active NPC nodes, keyed by their unique string name.
var npc_nodes: Dictionary = {}
## The prize chest node (exists only on server after game start).
var chest_node: Node = null

@onready var players: Node2D = $"../Players"
@onready var team_manager = $"../TeamManager"
#@onready var level_builder = $"../LevelBuilder"
var level_builder = null
func _ready():
	if _initialized:
		print("WARNING: _ready() called twice, skipping.")
		return
	_initialized = true
	_load_team_config()
	_init_team_data()

	# Debug: print full tree to find level_builder
	print("NetworkManager parent: ", get_parent().name)
	print("level_builder onready: ", level_builder)
	for child in get_parent().get_children():
		print("  sibling: ", child.name, " (", child.get_class(), ")")
		for grandchild in child.get_children():
			print("    child: ", grandchild.name, " script: ", grandchild.get_script())

	var args := OS.get_cmdline_args()

	if "--1v1" in args:
		max_players = 2
		max_per_team = 1
		print("Game mode: 1v1")

	if "--server" in args:
		print("Initializing as SERVER (WebSocket port %d)..." % server_port)
		is_host = true
		_peer = WebSocketMultiplayerPeer.new()
		var error: Error = _peer.create_server(server_port)
		if error != OK:
			printerr("WebSocket server creation failed: ", error)
			return
		multiplayer.multiplayer_peer = _peer
		_peer.peer_connected.connect(_on_peer_connected)
		_peer.peer_disconnected.connect(_on_peer_disconnected)
		print("WebSocket server ready on port ", server_port)

	elif "--client" in args:
		var addr_index := args.find("--address")
		if addr_index != -1 and addr_index + 1 < args.size():
			var raw: String = args[addr_index + 1]
			_connect_to_server(raw)
		else:
			# No address — connect to the production server via IIS proxy
			_connect_to_server(DEFAULT_WS_URL)
	else:
		# No launch argument — default to client connecting to the production server
		_connect_to_server(DEFAULT_WS_URL)

func _process(delta: float) -> void:
	if not is_game_active:
		return
	# All peers decrement locally so clients can display the countdown.
	# Only the server actually triggers the win condition.
	game_timer -= delta
	if game_timer <= 0 and multiplayer.is_server():
		_defenders_win()

func _connect_to_server(address: String) -> void:
	# Accept a bare IP/hostname or a full ws:// / wss:// URL.
	var url: String
	if address.begins_with("ws://") or address.begins_with("wss://"):
		url = address
	elif address == "127.0.0.1" or address == "localhost":
		# Local testing — connect directly to the server port, no proxy path
		url = "ws://%s:%d" % [address, server_port]
	else:
		# Bare hostname — route through the IIS proxy path (SSL)
		url = "wss://%s/game_ai" % address
	_peer = WebSocketMultiplayerPeer.new()
	var error: Error = _peer.create_client(url)
	if error != OK:
		printerr("WebSocket client connection failed: ", error)
		return
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	print("Connecting to ", url)

func _get_level_builder():
	if level_builder == null:
		# Walk the whole tree looking for LevelBuilderClaude
		level_builder = _find_node_by_script(get_parent(), "LevelBuilderClaude")
		if level_builder == null:
			printerr("LevelBuilderClaude not found anywhere!")
	return level_builder

func _find_node_by_script(node: Node, class_name_str: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == class_name_str:
		return node
	for child in node.get_children():
		var result = _find_node_by_script(child, class_name_str)
		if result:
			return result
	return null


# --- Team Config ---

func _load_team_config() -> void:
	var file := FileAccess.open("res://JSON/teams.json", FileAccess.READ)
	if file == null:
		printerr("teams.json not found — using default visuals")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		printerr("teams.json parse error: ", json.get_error_message())
		return
	team_config = json.data
	print("Loaded teams.json: ", team_config.get("teams", []).size(), " teams")

## Populate team_counts, flags_at_home, and scores from the loaded config.
func _init_team_data() -> void:
	team_counts.clear()
	flags_at_home.clear()
	scores.clear()
	for t in team_config.get("teams", []):
		var tid: int = t.get("team_id", -1)
		if tid == -1:
			continue
		team_counts[tid] = 0
		flags_at_home[tid] = true
		scores[tid] = 0
	# Fallback: keep working if teams.json is missing
	if team_counts.is_empty():
		team_counts = {1: 0, 2: 0}
		flags_at_home = {1: true, 2: true}
		scores = {1: 0, 2: 0}

## Returns the config dictionary for team_id, or {} if not found.
func _get_team_config(team_id: int) -> Dictionary:
	for t in team_config.get("teams", []):
		if t.get("team_id", -1) == team_id:
			return t
	return {}

## Assigns the 2 active teams to level slots (sorted team_id order → slot 0, slot 1).
## Must be called after all teams have joined, before _start_game.
func _assign_team_slots() -> void:
	team_slot_map.clear()
	var active: Array = []
	for tid in team_counts:
		if team_counts[tid] > 0:
			active.append(tid)
	active.sort()
	for i in active.size():
		team_slot_map[active[i]] = i
	print("Team slot assignments: ", team_slot_map)

## Returns the level slot config Dictionary for the given team_id, or {}.
func _get_slot_config(team_id: int) -> Dictionary:
	var lb = _get_level_builder()
	if lb == null:
		return {}
	var slot_idx: int = team_slot_map.get(team_id, -1)
	if slot_idx < 0 or slot_idx >= lb.slot_configs.size():
		return {}
	return lb.slot_configs[slot_idx]

## Returns 0 for the first peer on a team, 1 for the second (by sorted peer ID).
func _get_slot_in_team(peer_id: int, team_id: int) -> int:
	var team_peers: Array = []
	for pid in peer_teams:
		if peer_teams[pid] == team_id:
			team_peers.append(pid)
	team_peers.sort()
	var idx := team_peers.find(peer_id)
	return max(idx, 0)

func _apply_player_skin(player: Node, peer_id: int) -> void:
	var team_id: int = peer_teams.get(peer_id, -1)
	if team_id == -1:
		return
	var config := _get_team_config(team_id)
	if config.is_empty():
		return
	var slot := _get_slot_in_team(peer_id, team_id)
	var sprite_key := "player1_sprite" if slot == 0 else "player2_sprite"
	var weapon_key := "player1_weapon" if slot == 0 else "player2_weapon"
	var c_arr = config.get("color", null)
	var team_color := Color(c_arr[0], c_arr[1], c_arr[2]) if c_arr != null else Color.WHITE
	player.apply_team_skin(
		"res://" + config.get(sprite_key, ""),
		"res://" + config.get(weapon_key, ""),
		team_color
	)

func _on_connected_to_server() -> void:
	multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	print("Connected! My ID: ", multiplayer.get_unique_id())

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	for child in players.get_children():
		var existing_id := int(child.name)
		if existing_id != id:
			spawn_remote_player.rpc_id(id, existing_id, child.position)
	rpc_update_team_counts.rpc_id(id, team_counts, -1, -1)
	rpc_set_game_mode.rpc_id(id, max_players, max_per_team)
	# Send to lobby if a game is already running
	if is_game_active:
		lobby_peers.append(id)
		_rpc_go_to_lobby.rpc_id(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if players.has_node(str(id)):
		var p: Node = players.get_node(str(id))
		players.remove_child(p)
		p.queue_free()
	if id in peer_teams:
		team_counts[peer_teams[id]] -= 1
		peer_teams.erase(id)
		rpc_update_team_counts.rpc(team_counts, -1, -1)
	peer_role_prefs.erase(id)
	lobby_peers.erase(id)


# --- Spawning ---

func _get_spawn_position(team_id: int, peer_id: int = -1) -> Vector2:
	var lb = _get_level_builder()
	if lb == null:
		var slot_idx: int = team_slot_map.get(team_id, 0)
		return Vector2(300, 300) if slot_idx == 0 else Vector2(3800, 3800)
	var slot_idx: int = team_slot_map.get(team_id, 0)
	var spawns: Array = lb.slot_spawns[slot_idx] if lb.slot_spawns.size() > slot_idx else []
	if spawns.is_empty():
		return Vector2(300, 300) if team_id == 1 else Vector2(3800, 3800)

	# Use sorted peer-ID order so the index is deterministic even when all
	# players spawn at the same time (before any node enters the tree).
	var idx := 0
	if peer_id != -1:
		var team_peers: Array = []
		for pid in peer_teams:
			if peer_teams[pid] == team_id:
				team_peers.append(pid)
		team_peers.sort()
		var pos_in_list := team_peers.find(peer_id)
		idx = pos_in_list if pos_in_list != -1 else 0

	var base_pos: Vector2 = spawns[idx % spawns.size()]
	return _find_free_spawn_near(base_pos, lb)

# Search outward from base_pos for a floor tile that no existing player occupies.
func _find_free_spawn_near(base_pos: Vector2, lb: Node) -> Vector2:
	var tile_map = lb.tile_map
	if tile_map == null:
		return base_pos

	# Build candidate offsets: centre first, then expanding rings (shuffled per
	# ring so the fallback direction is random rather than always top-left).
	var candidates: Array[Vector2] = [Vector2.ZERO]
	for ring in range(1, 8):  # search up to 7 tiles (224 px) out
		var ring_offsets: Array[Vector2] = []
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if abs(dx) == ring or abs(dy) == ring:
					ring_offsets.append(Vector2(dx * 32, dy * 32))
		ring_offsets.shuffle()
		candidates.append_array(ring_offsets)

	for offset in candidates:
		var candidate := base_pos + offset
		if _is_valid_spawn(candidate, tile_map):
			return candidate

	return base_pos  # give up and use original

func _is_valid_spawn(pos: Vector2, tile_map) -> bool:
	# Every tile the player's bounding box overlaps must be a floor tile.
	var half := 28  # slightly smaller than half of the 64 px player hitbox
	for cx in [-half, half]:
		for cy in [-half, half]:
			var tile := Vector2i(int(pos.x + cx) / 32, int(pos.y + cy) / 32)
			if tile_map.get_cell_atlas_coords(tile) != Vector2i(0, 0):
				return false
	# Must not overlap any player already in the scene.
	for child in players.get_children():
		if child.global_position.distance_to(pos) < 60.0:
			return false
	return true

func _spawn_local_player() -> void:
	var my_id := multiplayer.get_unique_id()
	# Observers are not in peer_teams — never spawn them on the field.
	if not peer_teams.has(my_id):
		return
	if players.has_node(str(my_id)):
		print("Local player already spawned, skipping.")
		return
	var my_team = peer_teams.get(my_id, -1)
	var spawn_pos := _get_spawn_position(my_team, my_id)
	var player = player_scene.instantiate()
	player.name = str(my_id)
	player.position = spawn_pos
	player.is_player_one = (my_team == 1)
	player.team_id = my_team
	player.is_local_player = true
	players.add_child(player)
	player.set_multiplayer_authority(my_id)
	_apply_player_skin(player, my_id)
	print("Spawned local player at: ", spawn_pos, " team: ", my_team)
	spawn_remote_player.rpc(my_id, spawn_pos)

@rpc("any_peer", "call_remote", "reliable")
func spawn_remote_player(peer_id: int, spawn_pos: Vector2 = Vector2(300, 300)) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	# Don't create a visual copy for observer peers — they have no team.
	if not peer_teams.has(peer_id):
		return
	if players.has_node(str(peer_id)):
		# Stale node from a previous round — evict it immediately so we can
		# spawn a fresh one below (queue_free alone would leave it in the tree).
		var stale: Node = players.get_node(str(peer_id))
		players.remove_child(stale)
		stale.queue_free()
	print("Spawning remote copy of peer: ", peer_id, " at ", spawn_pos)
	var player = player_scene.instantiate()
	player.name = str(peer_id)
	player.position = spawn_pos
	player.is_player_one = (peer_teams.get(peer_id, -1) == 1)
	player.team_id = peer_teams.get(peer_id, -1)
	player.is_local_player = false
	players.add_child(player)
	player.set_multiplayer_authority(peer_id)
	_apply_player_skin(player, peer_id)

# Called on clients by server to trigger their own spawn
@rpc("authority", "call_remote", "reliable")
func _rpc_request_spawn() -> void:
	print("Server requested spawn for me")
	call_deferred("_spawn_local_player")


# --- Team + Role Selection ---

## Client sends its chosen team and role. Server collects and starts once
## max_players have confirmed. peer_role_prefs stores {team: int, role: int}.
@rpc("any_peer", "call_remote", "reliable")
func rpc_claim_selection(team_id: int, role: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	if is_game_active or peer_id in peer_teams or peer_id in peer_role_prefs or peer_id in lobby_peers:
		return
	if role != ROLE_ATTACK and role != ROLE_DEFEND:
		return
	if not team_counts.has(team_id):
		return
	# Hard cap: never accept more submissions than there are player slots.
	if peer_role_prefs.size() >= max_players:
		return
	peer_role_prefs[peer_id] = {team = team_id, role = role}
	rpc_sync_role_waiting.rpc(peer_role_prefs.size(), max_players)
	if peer_role_prefs.size() >= max_players:
		_resolve_selections()

@rpc("authority", "call_remote", "reliable")
func rpc_sync_role_waiting(count: int, total: int) -> void:
	emit_signal("role_waiting", count, total)

## Resolve team + role conflicts, broadcast assignments, start the game.
func _resolve_selections() -> void:
	# Mark active immediately so any in-flight rpc_claim_selection calls are rejected.
	is_game_active = true

	# ── Resolve team conflicts (first-come keeps preference; others get any free team) ──
	var team_to_peers: Dictionary = {}
	for pid in peer_role_prefs:
		var tid: int = peer_role_prefs[pid]["team"]
		if not team_to_peers.has(tid):
			team_to_peers[tid] = []
		team_to_peers[tid].append(pid)

	var resolved_team: Dictionary = {}   # peer_id -> team_id
	var taken_teams:   Array       = []
	var reassign:      Array       = []

	for tid in team_to_peers:
		var peers: Array = team_to_peers[tid].duplicate()
		peers.shuffle()
		resolved_team[peers[0]] = tid
		taken_teams.append(tid)
		for i in range(1, peers.size()):
			reassign.append(peers[i])

	var all_tids: Array = team_counts.keys()
	for pid in reassign:
		for tid in all_tids:
			if tid not in taken_teams:
				resolved_team[pid] = tid
				taken_teams.append(tid)
				break

	# ── Resolve role conflicts (random) ──
	var want_attack: Array = []
	var want_defend: Array = []
	for pid in peer_role_prefs:
		if peer_role_prefs[pid]["role"] == ROLE_ATTACK:
			want_attack.append(pid)
		else:
			want_defend.append(pid)

	want_attack.shuffle()
	want_defend.shuffle()

	var final_attack: Array = []
	var final_defend: Array = []
	while final_attack.size() < max_per_team and want_attack.size() > 0:
		final_attack.append(want_attack.pop_front())
	while final_defend.size() < max_per_team and want_defend.size() > 0:
		final_defend.append(want_defend.pop_front())
	for pid in want_attack:
		if final_defend.size() < max_per_team:
			final_defend.append(pid)
	for pid in want_defend:
		if final_attack.size() < max_per_team:
			final_attack.append(pid)

	peer_role_prefs.clear()

	# ── Build assignments and slot_map ──
	var assignments: Dictionary = {}   # peer_id -> team_id
	var slot_map:    Dictionary = {}   # team_id -> slot (0=attack, 1=defend)

	for pid in final_attack:
		var tid: int = resolved_team.get(pid, -1)
		if tid == -1:
			continue
		assignments[pid] = tid
		slot_map[tid]    = 0

	for pid in final_defend:
		var tid: int = resolved_team.get(pid, -1)
		if tid == -1:
			continue
		assignments[pid] = tid
		slot_map[tid]    = 1

	rpc_batch_assign_teams.rpc(assignments, slot_map)

	# Any connected peer not in the assignments becomes an observer this round.
	for pid in multiplayer.get_peers():
		if pid not in assignments:
			lobby_peers.append(pid)
			_rpc_go_to_lobby.rpc_id(pid)

	_begin_game_server()

## Broadcast peer→team assignments and the slot map (which team attacks/defends).
## call_local so the server's own state is updated before _begin_game_server().
@rpc("authority", "call_local", "reliable")
func rpc_batch_assign_teams(assignments: Dictionary, slot_map: Dictionary) -> void:
	for pid in assignments:
		var tid: int = assignments[pid]
		peer_teams[pid] = tid
		team_counts[tid] = team_counts.get(tid, 0) + 1
		if team_manager:
			team_manager.peer_teams[pid] = tid
	team_slot_map = slot_map
	var my_team: int = peer_teams.get(multiplayer.get_unique_id(), -1)
	emit_signal("team_data_updated", team_counts, my_team)

@rpc("any_peer", "call_local", "reliable")
func rpc_update_team_counts(counts: Dictionary, joining_peer: int, joining_team: int) -> void:
	for tid in counts:
		team_counts[tid] = counts[tid]
	if joining_peer != -1:
		peer_teams[joining_peer] = joining_team
		if team_manager:
			team_manager.peer_teams[joining_peer] = joining_team
	var my_team = peer_teams.get(multiplayer.get_unique_id(), -1)
	emit_signal("team_data_updated", team_counts, my_team)

# Server-only: starts the game and tells clients
func _begin_game_server() -> void:
	if not multiplayer.is_server():
		return
	print("Server starting game...")
	_start_game()
	emit_signal("game_started")
	# Tell each client to start game and spawn
	_rpc_begin_game_client.rpc()
	# Server has no player to spawn

@rpc("authority", "call_remote", "reliable")
func _rpc_begin_game_client() -> void:
	print("Client received game start")
	emit_signal("game_started")
	var my_id := multiplayer.get_unique_id()
	# Observers are not in peer_teams — skip game init and spawning entirely.
	if not peer_teams.has(my_id):
		return
	_start_game()
	call_deferred("_spawn_local_player")


# --- Game Logic ---

func _start_game() -> void:
	is_game_active = true
	game_timer = 180.0
	# team_slot_map already set by rpc_batch_assign_teams on all peers
	for tid in scores:
		scores[tid] = 0
	_spawn_home_zones()
	if multiplayer.is_server():
		# Determine attacker (slot 0) and defender (slot 1)
		for tid in team_slot_map:
			if team_slot_map[tid] == 0:
				attacker_team_id = tid
			elif team_slot_map[tid] == 1:
				defender_team_id = tid
		print("Attacker team: ", attacker_team_id, "  Defender team: ", defender_team_id)
		# Spawn the prize chest at the map centre
		_spawn_chest()
		# Spawn 1 NPC per active team
		_spawn_npcs()
		rpc_update_scores.rpc(scores)

## Spawn the prize chest at the position defined in level.json (chest_position).
## Falls back to the geometric centre of the map if no position is set.
func _spawn_chest() -> void:
	if not multiplayer.is_server():
		return
	# Read chest position from level.json
	var pos := Vector2(1752.0, 2752.0)   # default: centre of room_center_mid
	var file := FileAccess.open("res://JSON/level.json", FileAccess.READ)
	if file != null:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var cp = json.data.get("chest_position", null)
			if cp != null:
				pos = Vector2(cp["x"], cp["y"])
		file.close()

	var chest: Node = chest_scene.instantiate()
	chest.name = "PrizeChest"
	chest.position = pos
	get_parent().add_child(chest)
	chest_node = chest
	# Tell clients to create their visual copy
	rpc_spawn_chest.rpc(pos)
	print("Prize chest spawned at ", pos)


@rpc("authority", "call_remote", "reliable")
func rpc_spawn_chest(pos: Vector2) -> void:
	var chest: Node = chest_scene.instantiate()
	chest.name = "PrizeChest"
	chest.position = pos
	get_parent().add_child(chest)


## Spawn one NPC for every active team.
## The NPC starts at the team's first spawn position.
func _spawn_npcs() -> void:
	if not multiplayer.is_server():
		return
	var npc_index := 0
	for tid in team_slot_map:
		if team_counts.get(tid, 0) == 0:
			continue
		var spawn_pos := _get_spawn_position(tid)
		var npc: Node = npc_scene.instantiate()
		var npc_name := "NPC_%d_%d" % [tid, npc_index]
		npc.name = npc_name
		npc.team_id = tid
		npc.position = spawn_pos
		npc.home_position = spawn_pos
		npc.network_manager = self
		players.add_child(npc)   # reuse the Players container
		npc_nodes[npc_name] = npc

		# Apply team colour
		var cfg := _get_team_config(tid)
		var c_arr = cfg.get("color", null)
		if c_arr != null:
			npc.apply_team_color(Color(c_arr[0], c_arr[1], c_arr[2]))

		# Tell clients to place a visual copy
		rpc_spawn_npc.rpc(npc_name, tid, spawn_pos)
		npc_index += 1
	print("Spawned ", npc_index, " NPC(s)")


@rpc("authority", "call_remote", "reliable")
func rpc_spawn_npc(npc_name: String, tid: int, pos: Vector2) -> void:
	if players.has_node(npc_name):
		return
	var npc: Node = npc_scene.instantiate()
	npc.name = npc_name
	npc.team_id = tid
	npc.position = pos
	npc.home_position = pos
	players.add_child(npc)
	var cfg := _get_team_config(tid)
	var c_arr = cfg.get("color", null)
	if c_arr != null:
		npc.apply_team_color(Color(c_arr[0], c_arr[1], c_arr[2]))


## Called when the prize carrier dies (player or NPC).
## Returns the prize to the chest and clears carrier state on all characters.
func on_prize_dropped(_drop_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	print("Prize dropped — returning to chest")
	if is_instance_valid(chest_node):
		chest_node.restore_prize()
	# Clear prize state from all characters
	for child in players.get_children():
		if child.is_in_group("npc"):
			if child.get("carries_prize") == true:
				child.rpc("rpc_set_carries_prize", false)
		else:
			var flag_id = child.get("carried_flag_team")
			if flag_id != null and flag_id == 0:
				child.rpc("rpc_set_flag", -1)


## Called by HomeZone when the attacker team delivers the prize.
## Attackers win immediately.
func on_prize_scored(scoring_team: int) -> void:
	if not multiplayer.is_server():
		return
	print("Prize scored by team ", scoring_team, " — ATTACKERS WIN!")
	scores[scoring_team] = scores.get(scoring_team, 0) + 1
	rpc_update_scores.rpc(scores)
	_end_game()


## Called by Player.sync_position() on the server when a peer's implied speed
## exceeds 1.5× their declared max speed. Debounced to once per 2 s per peer.
func report_suspicious(peer_id: int, speed: float) -> void:
	if not multiplayer.is_server():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var entry: Dictionary = _cheat_reports.get(peer_id, {count = 0, last_report = -999.0})
	entry.count += 1
	_cheat_reports[peer_id] = entry
	if now - entry.last_report < 2.0:
		return   # suppress repeated alerts within the debounce window
	entry.last_report = now
	var cfg := _get_team_config(peer_teams.get(peer_id, -1))
	var tname: String = cfg.get("team_name", "peer %d" % peer_id)
	var desc := "[%s] speed %.0f px/s (max %.0f) — violation #%d" % [
		tname, speed, 600.0, entry.count
	]
	print("⚠ ANTI-CHEAT: ", desc)
	emit_signal("cheat_detected", peer_id, desc)


## Called when the game timer reaches zero: defenders held the prize — they win.
func _defenders_win() -> void:
	if not is_game_active:
		return
	if defender_team_id != -1:
		scores[defender_team_id] = scores.get(defender_team_id, 0) + 1
		rpc_update_scores.rpc(scores)
	print("Time's up! Defenders win — team ", defender_team_id)
	_end_game()


func _end_game() -> void:
	is_game_active = false
	_end_game_pending = true
	print("Game Over! Scores: ", scores)
	emit_signal("game_over")   # for server_view
	# Clean up entities on server; broadcast cleanup + lobby transition to clients.
	_cleanup_game_entities()
	rpc_end_round_client.rpc(LOBBY_DURATION)
	lobby_peers.clear()
	# After the lobby phase, return everyone to team-select and reset scores.
	await get_tree().create_timer(LOBBY_DURATION).timeout
	if _end_game_pending:
		_start_next_round()


func _start_next_round() -> void:
	_end_game_pending = false
	peer_role_prefs.clear()
	peer_teams.clear()
	_cheat_reports.clear()
	lobby_peers.clear()
	team_slot_map.clear()
	attacker_team_id = -1
	defender_team_id = -1
	for tid in team_counts:
		team_counts[tid] = 0
	for tid in scores:
		scores[tid] = 0
	rpc_update_scores.rpc(scores)
	rpc_update_team_counts.rpc(team_counts, -1, -1)
	rpc_go_to_team_select_all.rpc()


## Sent to all clients at round end: clean up entities and show the lobby.
@rpc("authority", "call_remote", "reliable")
func rpc_end_round_client(duration: float) -> void:
	_cleanup_game_entities()
	emit_signal("game_over")
	emit_signal("round_ended", duration)


## Sent to all clients after the lobby countdown: return to team-select.
## Also clears stale round-1 team data so observers in the new round don't
## pass the peer_teams.has() guard and accidentally spawn a player body.
@rpc("authority", "call_remote", "reliable")
func rpc_go_to_team_select_all() -> void:
	peer_teams.clear()
	team_slot_map.clear()
	for tid in team_counts:
		team_counts[tid] = 0
	emit_signal("released_from_lobby")


@rpc("authority", "call_remote", "reliable")
func _rpc_go_to_lobby() -> void:
	emit_signal("sent_to_lobby")


@rpc("authority", "call_remote", "reliable")
func _rpc_go_to_team_select() -> void:
	emit_signal("released_from_lobby")


## Wipe all in-game entities and send everyone back to team selection.
## The new round starts automatically once max_players have re-picked teams.
func reset_game() -> void:
	if not multiplayer.is_server():
		return
	print("Resetting game...")
	_end_game_pending = false   # cancel any pending lobby countdown
	is_game_active = false
	peer_role_prefs.clear()
	for tid in scores:
		scores[tid] = 0
	rpc_reset_game_client.rpc()
	_cleanup_game_entities()
	# Clear all team assignments so everyone must re-pick
	for tid in team_counts:
		team_counts[tid] = 0
	peer_teams.clear()
	lobby_peers.clear()
	team_slot_map.clear()
	attacker_team_id = -1
	defender_team_id = -1
	rpc_update_team_counts.rpc(team_counts, -1, -1)


@rpc("authority", "call_local", "reliable")
func rpc_reset_game_client() -> void:
	_cleanup_game_entities()
	emit_signal("released_from_lobby")  # tells Main to show team_select for everyone


## Remove all spawned in-game nodes: players, NPCs, chest, home zones.
func _cleanup_game_entities() -> void:
	# Players and NPCs — remove_child() first so the node disappears from the
	# tree immediately; queue_free() then frees the memory next frame.
	# This ensures players.get_children() / has_node() are clean right away,
	# preventing stale nodes from appearing in new-round spawn checks.
	for child in players.get_children():
		players.remove_child(child)
		child.queue_free()
	npc_nodes.clear()
	chest_node = null
	# Chest node in scene root
	var chest := get_parent().get_node_or_null("PrizeChest")
	if chest:
		chest.get_parent().remove_child(chest)
		chest.queue_free()
	# Home zones
	for child in get_parent().get_children():
		if child.is_in_group("home_zone"):
			child.get_parent().remove_child(child)
			child.queue_free()
	# Ammo drops
	for drop in _ammo_drops.values():
		if is_instance_valid(drop):
			drop.get_parent().remove_child(drop)
			drop.queue_free()
	_ammo_drops.clear()

func _create_flag_at(flag_team_id: int, pos: Vector2) -> void:
	if flag_instances.get(flag_team_id) != null:
		flag_instances[flag_team_id].queue_free()
	var flag_scene := preload("res://Scenes/Flag.tscn")
	var flag := flag_scene.instantiate()
	flag.flag_team_id = flag_team_id
	flag.global_position = pos
	add_child(flag)
	flag_instances[flag_team_id] = flag
	var flag_config := _get_team_config(flag_team_id)
	var flag_img: String = flag_config.get("flag_image", "")
	if flag_img != "":
		flag.apply_skin("res://" + flag_img)

func spawn_flag(flag_team_id: int) -> void:
	var slot := _get_slot_config(flag_team_id)
	var fp = slot.get("flag_position", null)
	var pos: Vector2
	if fp != null:
		pos = Vector2(fp["x"], fp["y"])
	else:
		var slot_idx: int = team_slot_map.get(flag_team_id, 0)
		pos = Vector2(384, 224) if slot_idx == 0 else Vector2(3184, 5344)
	flags_at_home[flag_team_id] = true
	_create_flag_at(flag_team_id, pos)
	rpc_spawn_flag.rpc(flag_team_id, pos)

func remove_flag(flag_team_id: int) -> void:
	flags_at_home[flag_team_id] = false
	if flag_instances.get(flag_team_id) != null:
		flag_instances[flag_team_id].queue_free()
		flag_instances[flag_team_id] = null
	rpc_remove_flag.rpc(flag_team_id)

func respawn_flag(flag_team_id: int) -> void:
	spawn_flag(flag_team_id)

func drop_flag(flag_team_id: int, drop_pos: Vector2) -> void:
	# Prize (id 0) is always returned to the chest when dropped — never left on floor.
	if flag_team_id == 0:
		on_prize_dropped(drop_pos)
		return
	flags_at_home[flag_team_id] = false
	_create_flag_at(flag_team_id, drop_pos)
	rpc_drop_flag.rpc(flag_team_id, drop_pos)


# --- RPCs ---

@rpc("any_peer", "call_local", "reliable")
func rpc_update_scores(new_scores: Dictionary) -> void:
	for tid in new_scores:
		scores[tid] = new_scores[tid]

func score_for_team(team_id: int) -> void:
	scores[team_id] = scores.get(team_id, 0) + 1
	rpc_update_scores.rpc(scores)
	print("Score: ", scores)

func _spawn_home_zones() -> void:
	for child in get_parent().get_children():
		if child.is_in_group("home_zone"):
			child.queue_free()
	var hz_scene: PackedScene = preload("res://Scenes/HomeZone.tscn")
	for tid in team_slot_map:
		var slot := _get_slot_config(tid)
		var hp = slot.get("home_zone_position", null)
		if hp == null:
			continue
		var zone: Node = hz_scene.instantiate()
		zone.team_id = tid
		zone.position = Vector2(hp["x"], hp["y"])
		zone.add_to_group("home_zone")
		get_parent().add_child(zone)

@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_flag(flag_team_id: int, pos: Vector2) -> void:
	flags_at_home[flag_team_id] = true
	_create_flag_at(flag_team_id, pos)

@rpc("any_peer", "call_remote", "reliable")
func rpc_remove_flag(flag_team_id: int) -> void:
	flags_at_home[flag_team_id] = false
	if flag_instances.get(flag_team_id) != null:
		flag_instances[flag_team_id].queue_free()
		flag_instances[flag_team_id] = null

@rpc("any_peer", "call_remote", "reliable")
func rpc_drop_flag(flag_team_id: int, drop_pos: Vector2) -> void:
	flags_at_home[flag_team_id] = false
	_create_flag_at(flag_team_id, drop_pos)

@rpc("authority", "call_remote", "reliable")
func rpc_set_game_mode(p_max_players: int, p_max_per_team: int) -> void:
	max_players = p_max_players
	max_per_team = p_max_per_team
	emit_signal("game_mode_updated")


# ── Ammo Drops (lobby spectators can drop ammo into the match) ─────────────

## Called by a lobby client pressing the Drop Ammo button.
@rpc("any_peer", "call_local", "reliable")
func rpc_request_ammo_drop() -> void:
	if not multiplayer.is_server():
		return
	if not is_game_active:
		return
	var sender := multiplayer.get_remote_sender_id()
	# Only lobby peers may drop ammo
	if sender != 0 and sender not in lobby_peers:
		return
	_server_spawn_ammo_drop()


## Server: pick a random spawn position and broadcast the ammo drop.
func _server_spawn_ammo_drop() -> void:
	var lb = _get_level_builder()
	var all_spawns: Array[Vector2] = []
	if lb != null:
		for slot in lb.slot_spawns:
			all_spawns.append_array(slot)
	if all_spawns.is_empty():
		all_spawns.append(Vector2(1752, 2752))  # fallback: map centre

	var pos: Vector2 = all_spawns[randi() % all_spawns.size()]
	# Small random offset so drops don't stack perfectly
	pos += Vector2(randf_range(-64, 64), randf_range(-64, 64))

	_ammo_drop_counter += 1
	var drop_name := "AmmoDrop_%d" % _ammo_drop_counter
	_spawn_ammo_drop_node(drop_name, pos)
	rpc_sync_ammo_drop.rpc(drop_name, pos)


func _spawn_ammo_drop_node(drop_name: String, pos: Vector2) -> void:
	if _ammo_drops.has(drop_name):
		return
	var drop: Node = ammo_drop_scene.instantiate()
	drop.name = drop_name
	drop.position = pos
	get_parent().add_child(drop)
	_ammo_drops[drop_name] = drop


## Called by AmmoDrop.gd when a player picks it up (server only).
func remove_ammo_drop(drop_name: String) -> void:
	if not multiplayer.is_server():
		return
	if _ammo_drops.has(drop_name):
		_ammo_drops[drop_name].queue_free()
		_ammo_drops.erase(drop_name)
	rpc_remove_ammo_drop.rpc(drop_name)


@rpc("authority", "call_remote", "reliable")
func rpc_sync_ammo_drop(drop_name: String, pos: Vector2) -> void:
	_spawn_ammo_drop_node(drop_name, pos)


@rpc("authority", "call_remote", "reliable")
func rpc_remove_ammo_drop(drop_name: String) -> void:
	if _ammo_drops.has(drop_name):
		_ammo_drops[drop_name].queue_free()
		_ammo_drops.erase(drop_name)
