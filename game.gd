extends Node3D

const Blocks = preload("res://blocks.gd")
const VoxelWorld = preload("res://voxel_world.gd")
const ClassicUI = preload("res://classic_ui.gd")
const Lan = preload("res://lan.gd")

const PixelFont = preload("res://art/PixelifySans.ttf")
const SETTINGS := "user://options.cfg"
const EYES := 1.62
const REACH := 5.0
const VIEW_NAMES := ["TINY", "SHORT", "NORMAL", "FAR"]
const VIEW_RADIUS := [1, 2, 3, 5]

var blocks: Blocks
var world: VoxelWorld
var ui: ClassicUI
var lan: Lan
var camera: Camera3D
var environment: Environment
var outline: MeshInstance3D
var clouds: MeshInstance3D
var menu_theme: Theme
var level_spawn := Vector3.ZERO
var checkpoint := Vector3.ZERO
var feet := Vector3.ZERO
var velocity := Vector3.ZERO
var pitch := 0.0
var yaw := 0.0
var grounded := false
var selected: Dictionary = {}
var outlined := Vector3i(-1, -1, -1)
var hotbar := Blocks.HOTBAR.duplicate()
var slot := 0
var placing := false
var mode := ""
var table_visible := false
var chat_until := 0
var username := "Player"
var address := "127.0.0.1"
var show_fps := false
var mouse_invert := false
var view_distance := 3
var sound_on := true
var music_on := false
var rebinding := -1
var bindings := [
	["Forward", KEY_W], ["Left", KEY_A], ["Back", KEY_S], ["Right", KEY_D],
	["Jump", KEY_SPACE], ["Build", KEY_B], ["Chat", KEY_T], ["Toggle fog", KEY_F],
	["Save location", KEY_ENTER], ["Load location", KEY_R]
]
var players: Dictionary = {}
var options := ConfigFile.new()
var effect_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var step_sound: AudioStreamWAV
var edit_sound: AudioStreamWAV
var step_distance := 0.0
var capture_path := ""
var capture_frame := 0
var capture_menu := ""
var look_after := 0
var fluid_clock := 0.0

func _ready() -> void:
	read_options()
	blocks = Blocks.new()
	var preferred: String = options.get_value("assets", "client_jar", "")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minecraft-jar="):
			preferred = arg.substr(16)
	blocks.load_first(preferred)
	print("Textures: ", blocks.source_path.get_file() if not blocks.source_path.is_empty() else "solid colors")
	menu_theme = create_theme()
	make_scene()
	make_audio()
	world = VoxelWorld.new()
	world.configure(blocks.atlas)
	add_child(world)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = ClassicUI.new()
	canvas.add_child(ui)
	ui.setup(self, blocks)
	lan = Lan.new()
	lan.name = "Lan"
	add_child(lan)
	lan.setup(self)
	var launch_seed := randi_range(0, 0x7fffffff)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed=") and arg.substr(7).is_valid_int():
			launch_seed = int(arg.substr(7))
		elif arg.begins_with("--capture="):
			capture_path = arg.substr(10)
		elif arg.begins_with("--capture-menu="):
			capture_menu = arg.substr(15)
	reset_level(launch_seed, 128)
	if blocks.source_path.is_empty():
		ui.set_notice("Choose a Minecraft client JAR in Options > Textures.")
	apply_options()
	screen("")

func make_scene() -> void:
	var outside := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("91ccef")
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_density = 1.0
	environment.fog_light_color = Color("bcdcf2")
	environment.fog_sky_affect = 0.0
	outside.environment = environment
	add_child(outside)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.055
	camera.far = 190.0
	camera.current = true
	add_child(camera)
	outline = MeshInstance3D.new()
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES, flat_material(Color(0.02, 0.02, 0.02)))
	for i in 8:
		for axis in 3:
			if i & (1 << axis):
				continue
			var other := i | (1 << axis)
			for corner in [i, other]:
				line.surface_add_vertex(Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1) * 1.005 - Vector3.ONE * 0.0025)
	line.surface_end()
	outline.mesh = line
	outline.hide()
	add_child(outline)
	clouds = MeshInstance3D.new()
	var cloud_mesh := ImmediateMesh.new()
	var white := flat_material(Color("ffffff"))
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloud_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, white)
	var random := RandomNumberGenerator.new()
	random.seed = 744
	for z in range(-180, 181, 9):
		for x in range(-180, 181, 10):
			if random.randf() > 0.27:
				continue
			var wide := random.randf_range(4, 15)
			var deep := random.randf_range(3, 9)
			var p := Vector3(x, 0, z)
			var a := p + Vector3(wide, 0, 0)
			var b := p + Vector3(0, 0, deep)
			var c := a + Vector3(0, 0, deep)
			for vertex in [p,a,b,a,c,b]:
				cloud_mesh.surface_add_vertex(vertex)
	cloud_mesh.surface_end()
	clouds.mesh = cloud_mesh
	add_child(clouds)

func flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = PixelFont
	theme.default_font_size = 15
	var button_images := {"normal": 0, "hover": 1, "pressed": 1, "disabled": 2}
	for state in ["normal", "hover", "pressed", "disabled"]:
		var id: int = button_images[state]
		if blocks.button_art.size() > id and blocks.button_art[id] != null:
			var texture := StyleBoxTexture.new()
			texture.texture = blocks.button_art[id]
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				texture.set_texture_margin(side, 2)
			theme.set_stylebox(state, "Button", texture)
			continue
		var style := StyleBoxFlat.new()
		style.bg_color = Color("707070") if state == "normal" else Color("8888ae")
		if state == "pressed": style.bg_color = Color("525276")
		if state == "disabled": style.bg_color = Color("464646")
		style.border_color = Color("1c1c1c")
		style.set_border_width_all(2)
		style.shadow_color = Color("383838")
		style.shadow_size = 1
		theme.set_stylebox(state, "Button", style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, "Button", Color.WHITE)
	return theme

func reset_level(new_seed: int, edge: int) -> void:
	level_spawn = world.generate(new_seed, edge)
	checkpoint = level_spawn
	feet = level_spawn
	velocity = Vector3.ZERO
	yaw = 0.0
	pitch = -0.02
	placing = false
	outline.hide()
	outlined = Vector3i(-1, -1, -1)
	clouds.position = Vector3(edge / 2.0, 63, edge / 2.0)
	update_camera()
	world.tick_build(feet, VIEW_RADIUS[view_distance], 9)

func new_level(edge: int) -> void:
	if is_guest():
		return
	reset_level(randi_range(0, 0x7fffffff), edge)
	if online():
		lan.broadcast_level()
	screen("")

func _process(delta: float) -> void:
	world.tick_build(feet, VIEW_RADIUS[view_distance])
	clouds.position.x += delta * 0.35
	if clouds.position.x > world.edge / 2.0 + 15.0:
		clouds.position.x -= 9.0
	if capture_path != "":
		capture_frame += 1
		if capture_frame == 28 and capture_menu in ["pause", "palette", "options", "controls"]:
			screen(capture_menu)
		if capture_frame == 36:
			capture.call_deferred()

func capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var failed := image.save_png(capture_path)
	get_tree().quit(int(failed != OK))

func _physics_process(delta: float) -> void:
	if mode != "" and not online():
		return
	var input := Vector2.ZERO
	if mode == "" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Vector2(float(held_key(3)) - float(held_key(1)), float(held_key(2)) - float(held_key(0)))
	var desired := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw).limit_length()
	var swimming := Blocks.liquid(world.get_block(Vector3i((feet + Vector3.UP * 0.2).floor())))
	var speed := 2.5 if swimming else 4.35
	var acceleration := 32.0 if grounded else 14.0
	velocity.x = move_toward(velocity.x, desired.x * speed, delta * acceleration)
	velocity.z = move_toward(velocity.z, desired.z * speed, delta * acceleration)
	velocity.y = maxf(-6.0 if swimming else -28.0, velocity.y - delta * (9.0 if swimming else 26.0))
	if mode == "" and held_key(4) and (grounded or swimming):
		velocity.y = 4.1 if swimming else 8.25
	var old := feet
	for axis in [0, 2, 1]:
		move_axis(axis, velocity[axis] * delta)
	update_camera()
	var walked := Vector2(feet.x - old.x, feet.z - old.z).length()
	step_distance += walked
	if grounded and walked > 0.001 and step_distance > 1.8:
		step_distance = 0.0
		play_effect(step_sound)
	aim()
	if online():
		lan.tick(delta)
	if not is_guest():
		fluid_clock += delta
		if fluid_clock >= 0.12:
			fluid_clock = 0.0
			flow_liquids()

func move_axis(axis: int, distance: float) -> void:
	if is_zero_approx(distance):
		return
	var next := feet
	next[axis] += distance
	if axis == 1:
		grounded = false
	if world.fits(next):
		feet = next
		return
	var free := 0.0
	var blocked := 1.0
	for i in 8:
		var portion := (free + blocked) * 0.5
		next[axis] = feet[axis] + distance * portion
		if world.fits(next):
			free = portion
		else:
			blocked = portion
	feet[axis] += distance * free
	velocity[axis] = 0
	if axis == 1 and distance < 0.0:
		grounded = true

func update_camera() -> void:
	camera.position = feet + Vector3.UP * EYES
	camera.rotation = Vector3(pitch, yaw, 0)

func aim() -> void:
	selected = world.ray(camera.position, -camera.basis.z, REACH)
	outline.visible = not selected.is_empty() and mode == ""
	if outline.visible:
		var cell: Vector3i = selected.cell
		if cell != outlined:
			outlined = cell
			outline.position = Vector3(cell)

func held_key(row: int) -> bool:
	return Input.is_physical_key_pressed(bindings[row][1])

func _input(event: InputEvent) -> void:
	if not is_instance_valid(ui):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if rebinding >= 0:
			if key != KEY_ESCAPE:
				bindings[rebinding][1] = key
				write_options()
			rebinding = -1
			ui._rebuild()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_ESCAPE:
			var back: String = {"options":"pause", "controls":"options", "generate":"pause", "multiplayer":"pause"}.get(mode, "")
			screen("pause" if mode == "" else back)
			get_viewport().set_input_as_handled()
			return
		if mode == "palette" and key == bindings[5][1]:
			screen("")
			return
		if mode != "":
			return
		if key == bindings[5][1]: screen("palette")
		elif key == bindings[6][1]:
			screen("chat")
			get_viewport().set_input_as_handled()
		elif key == bindings[7][1]: toggle_option(4)
		elif key == bindings[8][1]:
			checkpoint = feet
		elif key == bindings[9][1]:
			feet = checkpoint if world.fits(checkpoint) else level_spawn
			velocity = Vector3.ZERO
			update_camera()
		elif key >= KEY_1 and key <= KEY_9: slot = key - KEY_1
		elif key == KEY_TAB: table_visible = true
	if event is InputEventKey and not event.pressed and event.physical_keycode == KEY_TAB:
		table_visible = false

func _unhandled_input(event: InputEvent) -> void:
	if mode != "":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Time.get_ticks_msec() < look_after:
			return
		yaw = wrapf(yaw - event.relative.x * 0.004, -PI, PI)
		pitch = clampf(pitch - event.relative.y * 0.004 * (-1 if mouse_invert else 1), -1.56, 1.56)
		update_camera()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()
		return
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			placing = not placing
		MOUSE_BUTTON_LEFT:
			edit_target()
		MOUSE_BUTTON_MIDDLE:
			aim()
			var id: int = selected.get("block", 0)
			if id > 0 and id <= Blocks.PALETTE_COUNT:
				var old := hotbar.find(id)
				if old >= 0: slot = old
				else: hotbar[slot] = id
		MOUSE_BUTTON_WHEEL_UP: slot = posmod(slot - 1, 9)
		MOUSE_BUTTON_WHEEL_DOWN: slot = posmod(slot + 1, 9)

func edit_target() -> void:
	aim()
	if selected.is_empty():
		return
	var cell: Vector3i = selected.cell
	var id := 0
	if placing:
		var normal: Vector3i = selected.normal
		if normal == Vector3i.ZERO:
			return
		cell += normal
		id = hotbar[slot]
	if not legal_edit(cell, id):
		return
	if is_guest():
		lan.request_edit.rpc_id(1, cell, id)
	else:
		accept_edit(cell, id)
	play_effect(edit_sound)
	aim()

func legal_edit(cell: Vector3i, id: int) -> bool:
	if not world.inside(cell) or cell.y == 0 or id < 0 or id > Blocks.PALETTE_COUNT:
		return false
	var previous := world.get_block(cell)
	if id == 0:
		return previous != 0 and previous != Blocks.BEDROCK and not Blocks.liquid(previous)
	if Blocks.solid(id):
		var box := AABB(Vector3(cell), Vector3.ONE)
		if player_bounds(feet).intersects(box):
			return false
		for pose: Array in lan.poses.values():
			if player_bounds(pose[0]).intersects(box):
				return false
	return previous == 0 or Blocks.plant(previous) or Blocks.liquid(previous)

func player_bounds(at: Vector3) -> AABB:
	return AABB(at + Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))

func commit_block(cell: Vector3i, id: int) -> void:
	world.apply_block(cell, id)
	if online() and multiplayer.is_server():
		lan.receive_edit.rpc(cell, id)

func flow_liquids() -> void:
	var queue := world.pending_physics
	for cell: Vector3i in queue.keys().slice(0, 40):
		queue.erase(cell)
		if world.get_block(cell) != 0 or world.near_sponge(cell):
			continue
		for side in [Vector3i.UP, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var id: int = world.get_block(cell + side)
			if Blocks.liquid(id):
				commit_block(cell, id)
				world.queue_fluids(cell)
				break

func accept_edit(cell: Vector3i, id: int) -> void:
	commit_block(cell, id)
	if id == 15:
		for x in range(-2, 3):
			for y in range(-2, 3):
				for z in range(-2, 3):
					var p := cell + Vector3i(x, y, z)
					if world.get_block(p) == Blocks.WATER:
						commit_block(p, 0)
	var falling := cell
	while world.inside(falling):
		var kind := world.get_block(falling)
		if kind not in [0, 12, 13] and falling != cell:
			break
		if kind in [12, 13]:
			var below := falling
			while below.y > 1 and not Blocks.solid(world.get_block(below + Vector3i.DOWN)):
				below += Vector3i.DOWN
			if below != falling:
				commit_block(falling, 0)
				commit_block(below, kind)
		falling += Vector3i.UP
	world.queue_fluids(cell)
	var above := cell + Vector3i.UP
	if Blocks.plant(world.get_block(above)) and not Blocks.solid(world.get_block(cell)):
		commit_block(above, 0)

func pick_block(id: int) -> void:
	hotbar[slot] = id
	screen("")

func screen(next: String) -> void:
	mode = next
	table_visible = false
	if next == "":
		capture_mouse()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if next != "":
		outline.hide()
	ui.show_mode(next)

func capture_mouse() -> void:
	if capture_path.is_empty() and DisplayServer.get_name() != "headless":
		look_after = Time.get_ticks_msec() + 100
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func change_binding(i: int) -> void:
	rebinding = i
	ui._rebuild()

func binding_label(i: int) -> String:
	return "%s: %s" % [bindings[i][0], OS.get_keycode_string(bindings[i][1])]

func option_label(i: int) -> String:
	match i:
		0: return "Music: " + ("ON" if music_on else "OFF")
		1: return "Sound: " + ("ON" if sound_on else "OFF")
		2: return "Invert mouse: " + ("ON" if mouse_invert else "OFF")
		3: return "Show FPS: " + ("ON" if show_fps else "OFF")
		_: return "Render distance: " + VIEW_NAMES[view_distance]

func toggle_option(i: int) -> void:
	match i:
		0: music_on = not music_on
		1: sound_on = not sound_on
		2: mouse_invert = not mouse_invert
		3: show_fps = not show_fps
		4: view_distance = (view_distance + 1) % 4
	apply_options()
	write_options()
	if mode != "":
		ui._rebuild()

func choose_textures() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Choose a Minecraft Java client JAR"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.jar", "Minecraft Java client JAR")
	if DirAccess.dir_exists_absolute(Blocks.minecraft_directory()):
		dialog.current_dir = Blocks.minecraft_directory().path_join("versions")
	dialog.file_selected.connect(func(path: String):
		if blocks.load_jar(path):
			world.solid_material.albedo_texture = blocks.atlas
			world.water_material.albedo_texture = blocks.atlas
			menu_theme = create_theme()
			options.set_value("assets", "client_jar", path)
			write_options()
			ui._rebuild()
			ui.set_notice("Loaded textures from " + path.get_file())
		else:
			ui.set_notice("That file does not contain Minecraft block textures.")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.85)

func apply_options() -> void:
	environment.fog_depth_begin = [8.0, 17.0, 30.0, 57.0][view_distance]
	environment.fog_depth_end = [23.0, 47.0, 72.0, 118.0][view_distance]
	camera.far = [31.0, 55.0, 82.0, 158.0][view_distance]
	if music_on and not music_player.playing:
		music_player.play()
	elif not music_on:
		music_player.stop()

func read_options() -> void:
	options.load(SETTINGS)
	view_distance = clampi(options.get_value("video","distance",3), 0, 3)
	show_fps = options.get_value("video","fps",false)
	mouse_invert = options.get_value("input","invert",false)
	sound_on = options.get_value("audio","sound",true)
	music_on = options.get_value("audio","music",false)
	for i in bindings.size():
		bindings[i][1] = options.get_value("keys",str(i),bindings[i][1])

func write_options() -> void:
	options.set_value("video","distance",view_distance)
	options.set_value("video","fps",show_fps)
	options.set_value("input","invert",mouse_invert)
	options.set_value("audio","sound",sound_on)
	options.set_value("audio","music",music_on)
	for i in bindings.size():
		options.set_value("keys",str(i),bindings[i][1])
	options.save(SETTINGS)

func make_audio() -> void:
	effect_player = AudioStreamPlayer.new()
	add_child(effect_player)
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	step_sound = make_sound(0.09, 53.0, true)
	edit_sound = make_sound(0.14, 83.0, true)
	music_player.stream = make_sound(16.0, 110.0, false)
	music_player.volume_db = -18.0

func make_sound(seconds: float, tone: float, noisy: bool) -> AudioStreamWAV:
	var rate := 16000
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 375
	for i in count:
		var t := float(i) / rate
		var sample: float
		if noisy:
			var env := pow(1.0 - t / seconds, 2.0)
			sample = (random.randf_range(-0.48, 0.48) + sin(t * tone * TAU) * 0.39) * env * 0.6
		else:
			var note := floori(t / 2.0) % 8
			var hz: float = [220.0, 261.63, 329.63, 293.66, 196.0, 246.94, 293.66, 261.63][note]
			var phase := fmod(t, 2.0)
			var env := sin(PI * phase / 2.0) * 0.5
			sample = (sin(phase * hz * TAU) + 0.25 * sin(t * tone * TAU)) * env
		data.encode_s16(i * 2, int(sample * 27000.0))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.data = data
	audio.mix_rate = rate
	if not noisy:
		audio.loop_begin = 0
		audio.loop_end = count
		audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return audio

func play_effect(audio: AudioStreamWAV) -> void:
	if sound_on:
		effect_player.stream = audio
		effect_player.pitch_scale = randf_range(0.9, 1.1)
		effect_player.play()

func online() -> bool:
	return lan != null and lan.peer != null

func is_guest() -> bool:
	return online() and not multiplayer.is_server()

func host_game(name_text: String) -> void:
	username = lan.clean_name(name_text)
	lan.host()

func join_game(host: String, name_text: String) -> void:
	username = lan.clean_name(name_text)
	address = host.strip_edges()
	lan.join(address)

func disconnect_game() -> void:
	lan.disconnect_session()
	screen("pause")

func send_chat(line: String) -> void:
	var trimmed := line.strip_edges().left(180)
	if trimmed != "":
		lan.chat(trimmed)
	screen("")

func add_chat(line: String) -> void:
	chat_until = Time.get_ticks_msec() + 8500
	ui.add_chat(line)
