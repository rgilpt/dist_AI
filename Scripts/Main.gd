extends Node2D

@onready var team_select: Control = $TeamSelect
@onready var server_view: Control = $ServerView
@onready var lobby_camera: Camera2D = $LobbyCamera
@onready var lobby: Control = $Lobby

func _ready():
	await get_tree().process_frame
	lobby_camera.enabled = true
	lobby.visible = false

	var args := OS.get_cmdline_args()
	if "--server" in args:
		team_select.visible = false
		server_view.visible = true
	else:
		team_select.visible = true
		server_view.visible = false

	var nm := get_node("NetworkManager")
	nm.game_started.connect(_on_game_started)
	nm.sent_to_lobby.connect(_on_sent_to_lobby)
	nm.released_from_lobby.connect(_on_released_from_lobby)
	nm.round_ended.connect(_on_round_ended)


func _on_game_started() -> void:
	var args := OS.get_cmdline_args()
	if "--server" in args:
		return
	lobby_camera.enabled = false


func _on_sent_to_lobby() -> void:
	if "--server" in OS.get_cmdline_args():
		return
	team_select.visible = false
	lobby.visible = true
	lobby.activate()
	# Lobby is full-screen opaque; camera is irrelevant while it's showing,
	# but re-enable now so it's ready when lobby closes.
	lobby_camera.reset()
	lobby_camera.enabled = true


func _on_round_ended(duration: float) -> void:
	if "--server" in OS.get_cmdline_args():
		return
	team_select.visible = false
	lobby.visible = true
	lobby.activate_post_game(duration)
	lobby_camera.reset()
	lobby_camera.enabled = true


func _on_released_from_lobby() -> void:
	if "--server" in OS.get_cmdline_args():
		return
	lobby.visible = false
	team_select.visible = true
	lobby_camera.enabled = true
