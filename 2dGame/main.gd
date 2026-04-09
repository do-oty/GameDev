extends Node2D

const PORT := 7000
const HOST := "127.0.0.1"
const SPAWN_BASE := Vector2(115, 114)
const SPAWN_STEP_X := 48.0

@onready var player_template: CharacterBody2D = $Player

var players: Dictionary = {}
var local_player_claimed := false
var auto_connect_pending := false

func _ready() -> void:
	print("[MP] ----------")
	print("[MP] Game launch detected")
	print("[MP] Launch args: %s" % str(OS.get_cmdline_args()))
	print("[MP] Mode options: --host, --client, or auto (default)")
	print("[MP] ----------")

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_set_player_node_active(player_template, false)
	_start_multiplayer_from_args()
	_print_mp_state("post auto-connect")
	_print_state_after_delay()


func _print_state_after_delay() -> void:
	await get_tree().create_timer(1.5).timeout
	_print_mp_state("1.5s after launch")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			host_game()
		elif event.keycode == KEY_F2:
			join_game(HOST)


func _auto_connect_multiplayer() -> void:
	auto_connect_pending = true
	print("[MP] Auto mode: trying CLIENT first...")
	join_game(HOST)
	_auto_host_fallback_check()


func _auto_host_fallback_check() -> void:
	await get_tree().create_timer(1.0).timeout
	if not auto_connect_pending:
		return

	var peer := multiplayer.multiplayer_peer
	var should_host := false
	if peer == null:
		should_host = true
	elif not multiplayer.is_server() and peer is ENetMultiplayerPeer:
		var status := (peer as ENetMultiplayerPeer).get_connection_status()
		should_host = status != MultiplayerPeer.CONNECTION_CONNECTED

	if should_host:
		print("[MP] Auto mode: no server reached, trying HOST...")
		multiplayer.multiplayer_peer = null
		host_game()


func _start_multiplayer_from_args() -> void:
	var args := OS.get_cmdline_args()

	if args.has("--host"):
		print("[MP] Forced mode: HOST")
		host_game()
		return

	if args.has("--client"):
		print("[MP] Forced mode: CLIENT")
		join_game(HOST)
		return

	print("[MP] Forced mode not provided -> using AUTO mode")
	_auto_connect_multiplayer()


func host_game() -> void:
	multiplayer.multiplayer_peer = null

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err != OK:
		push_error("[MP] Failed to host game: %s" % err)
		print("[MP] Host failed, retrying CLIENT...")
		multiplayer.multiplayer_peer = null
		join_game(HOST)
		return

	multiplayer.multiplayer_peer = peer
	_spawn_player_for_peer(multiplayer.get_unique_id())
	auto_connect_pending = false
	print("[MP] Started as HOST on port %d (id: %d)" % [PORT, multiplayer.get_unique_id()])
	print("[MP] Waiting for another instance to join...")


func join_game(address: String) -> void:
	multiplayer.multiplayer_peer = null

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("[MP] Failed to join game: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	print("[MP] Started as CLIENT, joining %s:%d..." % [address, PORT])


func _spawn_player_for_peer(peer_id: int) -> void:
	if players.has(peer_id):
		return

	var spawned_player: CharacterBody2D
	var is_local_peer := peer_id == multiplayer.get_unique_id()

	if is_local_peer and not local_player_claimed:
		spawned_player = player_template
		local_player_claimed = true
	else:
		spawned_player = player_template.duplicate() as CharacterBody2D
		if spawned_player == null:
			return
		add_child(spawned_player)

	spawned_player.name = "Player_%s" % peer_id
	spawned_player.global_position = _get_spawn_position(peer_id)
	spawned_player.set_multiplayer_authority(peer_id)
	_set_player_node_active(spawned_player, true)
	spawned_player.call("apply_network_role")
	players[peer_id] = spawned_player


func _despawn_player_for_peer(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	var spawned_player: CharacterBody2D = players[peer_id]
	players.erase(peer_id)
	if is_instance_valid(spawned_player):
		spawned_player.queue_free()


func _get_spawn_position(_peer_id: int) -> Vector2:
	var offset := float(players.size()) * SPAWN_STEP_X
	return SPAWN_BASE + Vector2(offset, 0)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	_spawn_player_for_peer(peer_id)
	_spawn_player_remote.rpc(peer_id, _get_player_position(peer_id))
	_announce_instance_joined.rpc(peer_id)
	_announce_instance_joined(peer_id)

	for existing_peer_id in players.keys():
		if int(existing_peer_id) == peer_id:
			continue
		_spawn_player_remote.rpc_id(peer_id, int(existing_peer_id), _get_player_position(int(existing_peer_id)))


func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_player_for_peer(peer_id)
	if multiplayer.is_server():
		_despawn_player_remote.rpc(peer_id)


func _on_connected_to_server() -> void:
	auto_connect_pending = false
	print("[MP] Joined server successfully (id: %d)" % multiplayer.get_unique_id())
	_request_full_sync.rpc_id(1)
	_print_mp_state("client connected")


func _on_connection_failed() -> void:
	push_error("[MP] Connection failed")
	multiplayer.multiplayer_peer = null
	_print_mp_state("connection failed")
	if auto_connect_pending:
		print("[MP] Auto mode: connection failed, trying HOST...")
		host_game()


func _on_server_disconnected() -> void:
	push_error("[MP] Disconnected from server")
	multiplayer.multiplayer_peer = null
	_print_mp_state("server disconnected")


func _get_player_position(peer_id: int) -> Vector2:
	if players.has(peer_id) and is_instance_valid(players[peer_id]):
		return players[peer_id].global_position
	return SPAWN_BASE


@rpc("authority", "call_remote", "reliable")
func _spawn_player_remote(peer_id: int, spawn_position: Vector2) -> void:
	_spawn_player_for_peer(peer_id)
	if players.has(peer_id):
		players[peer_id].global_position = spawn_position


@rpc("authority", "call_remote", "reliable")
func _despawn_player_remote(peer_id: int) -> void:
	_despawn_player_for_peer(peer_id)


@rpc("authority", "call_remote", "reliable")
func _announce_instance_joined(peer_id: int) -> void:
	print("[MP] Instance joined -> peer id: %d" % peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_full_sync() -> void:
	if not multiplayer.is_server():
		return

	var requester_id := multiplayer.get_remote_sender_id()
	print("[MP] Full sync requested by peer id: %d" % requester_id)
	for existing_peer_id in players.keys():
		var player_id := int(existing_peer_id)
		_spawn_player_remote.rpc_id(requester_id, player_id, _get_player_position(player_id))


func _print_mp_state(context: String) -> void:
	var peer := multiplayer.multiplayer_peer
	var has_peer := peer != null
	var role := "none"
	var connection_state := "none"

	if peer is ENetMultiplayerPeer:
		var status := (peer as ENetMultiplayerPeer).get_connection_status()
		match status:
			MultiplayerPeer.CONNECTION_DISCONNECTED:
				connection_state = "disconnected"
			MultiplayerPeer.CONNECTION_CONNECTING:
				connection_state = "connecting"
			MultiplayerPeer.CONNECTION_CONNECTED:
				connection_state = "connected"

		if connection_state == "connected":
			role = "host" if multiplayer.is_server() else "client"
		else:
			role = "pending"

	print("[MP] State (%s): role=%s, net=%s, id=%d, peers=%d" % [
		context,
		role,
		connection_state,
		multiplayer.get_unique_id(),
		players.size()
	])


func _set_player_node_active(player_node: CharacterBody2D, active: bool) -> void:
	player_node.set_process(active)
	player_node.set_physics_process(active)

	if player_node.has_node("AnimatedSprite2D"):
		player_node.get_node("AnimatedSprite2D").visible = active
	if player_node.has_node("CollisionShape2D"):
		player_node.get_node("CollisionShape2D").disabled = not active
