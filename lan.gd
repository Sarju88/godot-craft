extends Node

const PORT := 25565
var game
var peer: ENetMultiplayerPeer
var avatars: Dictionary = {}
var poses: Dictionary = {}
var position_timer := 0.0
var ready_to_play := false

func setup(controller) -> void:
	game = controller
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_lost)
	multiplayer.server_disconnected.connect(_lost)
	multiplayer.peer_disconnected.connect(_departed)

func clean_name(text: String) -> String:
	var result := ""
	for letter in text.strip_edges().left(20):
		if letter.is_valid_ascii_identifier() or letter.is_valid_int() or letter in [" ", "-"]:
			result += letter
	return result.strip_edges() if not result.strip_edges().is_empty() else "Player"

func host(bind_ip := "*", port := PORT) -> void:
	var connection := ENetMultiplayerPeer.new()
	connection.set_bind_ip(bind_ip)
	var err := connection.create_server(port, 9)
	if err != OK:
		game.ui.set_notice("Could not open LAN port %d." % port)
		return
	peer = connection
	multiplayer.multiplayer_peer = peer
	ready_to_play = true
	game.players[1] = game.username
	game.screen("")
	game.ui.set_notice("LAN world open on UDP %d." % port)

func join(address: String, port := PORT) -> void:
	if address.is_empty():
		game.ui.set_notice("Enter the host's LAN address.")
		return
	var connection := ENetMultiplayerPeer.new()
	var err := connection.create_client(address, port)
	if err != OK:
		game.ui.set_notice("Could not connect to that address.")
		return
	peer = connection
	multiplayer.multiplayer_peer = peer
	game.ui._rebuild()
	game.ui.set_notice("Connecting...")

func disconnect_session() -> void:
	var connection := peer
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if connection != null:
		connection.close()
	ready_to_play = false
	for node in avatars.values():
		node.queue_free()
	avatars.clear()
	poses.clear()
	game.players.clear()

func _lost() -> void:
	disconnect_session()
	game.screen("multiplayer")
	game.ui.set_notice("Disconnected from the host.")

func _departed(id: int) -> void:
	if not multiplayer.is_server() or not game.players.has(id):
		return
	remove_player(id)
	roster.rpc(game.players)

func _connected() -> void:
	hello.rpc_id(1, game.username)

@rpc("any_peer", "call_remote", "reliable")
func hello(username: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if game.players.has(id):
		return
	game.players[id] = clean_name(username)
	send_level(id)
	roster.rpc(game.players)

func send_level(id: int) -> void:
	start_level.rpc_id(id, game.world.level_seed, game.world.edge)
	var patch := PackedInt32Array()
	for cell: Vector3i in game.world.changed:
		patch.append_array(PackedInt32Array([cell.x, cell.y, cell.z, game.world.changed[cell]]))
		if patch.size() >= 2000:
			level_patch.rpc_id(id, patch)
			patch = PackedInt32Array()
	if not patch.is_empty():
		level_patch.rpc_id(id, patch)
	finish_level.rpc_id(id)

func broadcast_level() -> void:
	poses.clear()
	for id in multiplayer.get_peers():
		if game.players.has(id):
			send_level(id)

@rpc("authority", "call_remote", "reliable")
func start_level(new_seed: int, edge: int) -> void:
	if edge not in [128, 256, 512]:
		return
	ready_to_play = false
	game.reset_level(new_seed, edge)

@rpc("authority", "call_remote", "reliable")
func level_patch(patch: PackedInt32Array) -> void:
	for i in range(0, patch.size() - 3, 4):
		game.world.apply_block(Vector3i(patch[i], patch[i + 1], patch[i + 2]), patch[i + 3])

@rpc("authority", "call_remote", "reliable")
func finish_level() -> void:
	ready_to_play = true
	game.screen("")

@rpc("authority", "call_remote", "reliable")
func roster(names: Dictionary) -> void:
	for id in game.players.keys():
		if id not in names:
			remove_player(id)
	game.players = names

func remove_player(id: int) -> void:
	game.players.erase(id)
	poses.erase(id)
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)

func tick(delta: float) -> void:
	if not ready_to_play:
		return
	for id: int in avatars.keys():
		var avatar: Node3D = avatars[id]
		var pose: Array = poses[id]
		avatar.position = avatar.position.lerp(pose[0], minf(1.0, delta * 19.0))
		avatar.rotation.y = lerp_angle(avatar.rotation.y, pose[1], minf(1.0, delta * 19.0))
	position_timer += delta
	if position_timer < 0.05:
		return
	position_timer = 0
	if multiplayer.is_server():
		receive_pose.rpc(1, game.feet, game.yaw)
	else:
		submit_pose.rpc_id(1, game.feet, game.yaw)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_pose(feet: Vector3, yaw: float) -> void:
	if not multiplayer.is_server() or not feet.is_finite() or not is_finite(yaw):
		return
	var id := multiplayer.get_remote_sender_id()
	if not game.players.has(id) or not game.world.inside(Vector3i(feet.floor())):
		return
	receive_pose(id, feet, yaw)
	receive_pose.rpc(id, feet, yaw)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_pose(id: int, feet: Vector3, yaw: float) -> void:
	if id == multiplayer.get_unique_id() or not game.players.has(id):
		return
	poses[id] = [feet, yaw]
	if not avatars.has(id):
		avatars[id] = make_avatar(id)
		avatars[id].position = feet
		avatars[id].rotation.y = yaw

@rpc("any_peer", "call_remote", "reliable")
func request_edit(cell: Vector3i, block: int) -> void:
	if not multiplayer.is_server():
		return
	var player := multiplayer.get_remote_sender_id()
	if not poses.has(player):
		return
	var feet: Vector3 = poses[player][0]
	var eyes: Vector3 = feet + Vector3.UP * game.EYES
	if eyes.distance_to(Vector3(cell) + Vector3.ONE * 0.5) > game.REACH + 1.5:
		return
	if game.legal_edit(cell, block):
		game.accept_edit(cell, block)

@rpc("authority", "call_remote", "reliable")
func receive_edit(cell: Vector3i, block: int) -> void:
	game.world.apply_block(cell, block)

func chat(message: String) -> void:
	if peer == null:
		game.add_chat("%s: %s" % [game.username, message])
	elif multiplayer.is_server():
		publish_chat(game.username, message)
	elif ready_to_play:
		submit_chat.rpc_id(1, message)

@rpc("any_peer", "call_remote", "reliable")
func submit_chat(message: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if game.players.has(id):
		publish_chat(game.players[id], message)

func publish_chat(username: String, message: String) -> void:
	var clean := message.strip_edges().replace("\n", " ").replace("\r", " ").left(180)
	if not clean.is_empty():
		var line := "%s: %s" % [username, clean]
		receive_chat(line)
		receive_chat.rpc(line)

@rpc("authority", "call_remote", "reliable")
func receive_chat(line: String) -> void:
	game.add_chat(line)

func make_avatar(id: int) -> Node3D:
	var avatar := Node3D.new()
	add_child(avatar)
	var skin := Color("c8895f")
	var shirt := Color("42a093")
	var trousers := Color("525982")
	add_cube(avatar, Vector3(0.50, 0.49, 0.30), Vector3(0, 1.03, 0), shirt)
	add_cube(avatar, Vector3(0.46, 0.46, 0.46), Vector3(0, 1.51, 0), skin)
	add_cube(avatar, Vector3(0.46, 0.12, 0.46), Vector3(0, 1.68, 0), Color("50382d"))
	for side in [-1, 1]:
		add_cube(avatar, Vector3(0.21, 0.57, 0.24), Vector3(side * 0.36, 0.92, 0), skin)
		add_cube(avatar, Vector3(0.22, 0.76, 0.26), Vector3(side * 0.12, 0.39, 0), trousers)
		add_cube(avatar, Vector3(0.065, 0.045, 0.018), Vector3(side * 0.105, 1.53, -0.232), Color("403230"))
	var name_tag := Label3D.new()
	name_tag.text = game.players[id]
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.font_size = 32
	name_tag.pixel_size = 0.008
	name_tag.position = Vector3(0, 2.05, 0)
	avatar.add_child(name_tag)
	return avatar

func add_cube(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var cube := BoxMesh.new()
	cube.size = size
	cube.material = game.flat_material(color)
	var node := MeshInstance3D.new()
	node.mesh = cube
	node.position = at
	parent.add_child(node)
