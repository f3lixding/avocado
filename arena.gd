extends Node3D

const PORT := 7000
const MAX_CLIENT := 16
const PLAYER_SCENE := preload("res://player.tscn")

@onready var players: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	player_spawner.spawn_function = _create_player

	var args := OS.get_cmdline_user_args()

	if "--server" in args:
		start_server()
		return

	if "--test-single" in args:
		spawn_player(multiplayer.get_unique_id())
		return

	for argument in args: 
		if argument.begins_with("--connect="):
			var address := argument.trim_prefix("--connect=")
			connect_to_server(address)
			return

func _create_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	var peer_id = data["peer_id"]
	var pos = data["position"]
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id, true)
	player.position = pos

	return player

func _on_peer_connected(peer_id: int) -> void: 
	print("Peer connected: ", peer_id)

	if multiplayer.is_server():
		spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)

	if not multiplayer.is_server():
		return

	var player := players.get_node_or_null(str(peer_id))

	if player:
		player.queue_free()

func _on_connected_to_server() -> void: 
	print("Connected as peer ", multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	push_error("Connection failed")

func _on_server_disconnected() -> void:
	print("Server disconnected")

func start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENT)

	if error != OK:
		push_error("Could not start server: %s" % error_string(error))
		return

	multiplayer.multiplayer_peer = peer
	print("Server listening on port %d" % PORT)

func connect_to_server(address: String) -> void: 
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)

	if error != OK: 
		push_error("Could not connect to server at port %d" % PORT)
		return

	multiplayer.multiplayer_peer = peer
	print("Client created at %s:%d" % [address, PORT])

func spawn_player(peer_id: int) -> void:
	var pos := Vector3(
		players.get_child_count(false) * 2.0,
		2.0,
		0.0,
	)

	player_spawner.spawn({
		"peer_id": peer_id,
		"position": pos,
	})
