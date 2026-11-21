extends Node3D

const Blocks = preload("res://blocks.gd")
const VoxelWorld = preload("res://voxel_world.gd")
const ClassicUI = preload("res://classic_ui.gd")
const Lan = preload("res://lan.gd")
const ClientAudio = preload("res://client_audio.gd")
const Inventory = preload("res://survival_inventory.gd")
const Recipes = preload("res://survival_recipes.gd")
const SurvivalEntities = preload("res://survival_entities.gd")
const DAY_SKY := Color("91ccef")
const NIGHT_SKY := Color("151c36")
const SurvivalMotion = preload("res://survival_motion.gd")
const WorldSaves = preload("res://world_saves.gd")

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
	["Save location", KEY_ENTER], ["Load location", KEY_R],
	["Sprint", KEY_CTRL], ["Sneak", KEY_SHIFT]
]
var players: Dictionary = {}
var options := ConfigFile.new()
var effect_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var client_audio: ClientAudio
var step_distance := 0.0
var capture_path := ""
var capture_frame := 0
var capture_menu := ""
var look_after := 0
var fluid_clock := 0.0
var has_level := false
var options_back := "title"
var multiplayer_back := "title"
var launch_seed := 0
var survival := false
var world_id := ""
var world_name := ""
var cherry_groves := true
var deep_world := false
var draft_name := "New World"
var draft_seed := ""
var draft_size := 0
var health := 20
var lava_clock := 0.0
var save_clock := 0.0
var motion := SurvivalMotion.new()
var motion_time := 0.0
var previous_feet := Vector3.ZERO
var eye_height := EYES
var inventory := Inventory.new()
var entities := SurvivalEntities.new()
var attack_ticks := 100
var hurt_ticks := 0
var mining_cell := Vector3i(-1, -1, -1)
var mining_block := 0
var mining_ticks := 0.0
var bow_ticks := 0
var bow_slot := -1
var shield_ticks := 0
var primary_consumed := false
var smelt_ticks := 0
var damage_remainder := 0.0

func _ready() -> void:
	get_tree().auto_accept_quit = false
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
	entities.game = self
	add_child(entities)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = ClassicUI.new()
	canvas.add_child(ui)
	ui.setup(self, blocks)
	lan = Lan.new()
	lan.name = "Lan"
	add_child(lan)
	lan.setup(self)
	launch_seed = randi_range(0, 0x7fffffff)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed=") and arg.substr(7).is_valid_int():
			launch_seed = int(arg.substr(7))
		elif arg.begins_with("--capture="):
			capture_path = arg.substr(10)
		elif arg.begins_with("--capture-menu="):
			capture_menu = arg.substr(15)
	apply_options()
	if capture_path.is_empty() or capture_menu in ["title", "worlds", "create"]:
		screen(capture_menu if not capture_path.is_empty() and not capture_menu.is_empty() else "title")
	else:
		start_classic()

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
	for i in blocks.field_art.size():
		if blocks.field_art[i] == null:
			continue
		var style := StyleBoxTexture.new()
		style.texture = blocks.field_art[i]
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_texture_margin(side, 3)
			style.set_content_margin(side, 7)
		theme.set_stylebox(["normal", "focus"][i], "LineEdit", style)
	return theme

func reset_level(new_seed: int, edge: int, survival_world := false) -> void:
	survival = survival_world
	entities.clear_level()
	inventory = Inventory.new()
	hurt_ticks = 0
	attack_ticks = 100
	smelt_ticks = 0
	damage_remainder = 0.0
	reset_actions()
	update_daylight()
	has_level = true
	world.show()
	clouds.show()
	level_spawn = world.generate(new_seed, edge, survival, cherry_groves, deep_world)
	health = 20
	lava_clock = 0.0
	save_clock = 0.0
	grounded = false
	step_distance = 0.0
	fluid_clock = 0.0
	checkpoint = level_spawn
	feet = level_spawn
	reset_survival_motion()
	velocity = Vector3.ZERO
	yaw = 0.0
	pitch = -0.02
	placing = false
	outline.hide()
	outlined = Vector3i(-1, -1, -1)
	clouds.position = Vector3(edge / 2.0, world.world_height - 1.0, edge / 2.0)
	update_camera()
	world.tick_build(feet, VIEW_RADIUS[view_distance], 9)

func start_classic() -> void:
	world_id = ""
	reset_hotbar()
	reset_level(launch_seed, 128)
	screen("")

func reset_hotbar() -> void:
	hotbar = Blocks.HOTBAR.duplicate()
	slot = 0

func open_options() -> void:
	options_back = mode
	screen("options")

func open_multiplayer() -> void:
	multiplayer_back = mode
	screen("multiplayer")

func open_creation() -> void:
	draft_name = "New World"
	draft_seed = ""
	draft_size = 0
	screen("create")

func create_survival() -> void:
	var title := draft_name.strip_edges()
	if title.is_empty():
		ui.set_notice("Enter a world name.")
		return
	var seed_text := draft_seed.strip_edges()
	var seed_value := randi_range(0, 0x7fffffff)
	if not seed_text.is_empty():
		seed_value = int(seed_text) if seed_text.is_valid_int() else int(seed_text.hash())
	world_id = Crypto.new().generate_random_bytes(16).hex_encode()
	world_name = title
	cherry_groves = true
	deep_world = true
	reset_hotbar()
	reset_level(seed_value, [128, 256][draft_size], true)
	screen("")
	save_survival()

func load_survival(id: String) -> void:
	var data := WorldSaves.read(id)
	if data == null:
		ui.set_notice("Could not load this world.")
		return
	var edge: int = data.get_value("world", "edge", 0)
	if edge not in [128, 256]:
		ui.set_notice("This world has an unsupported size.")
		return
	world_id = id
	world_name = data.get_value("world", "name", "Unnamed World")
	cherry_groves = data.get_value("world", "cherry_groves", false)
	deep_world = data.get_value("world", "deep_world", false)
	reset_hotbar()
	reset_level(data.get_value("world", "seed", 0), edge, true)
	var edits: Dictionary = data.get_value("world", "edits", {})
	for cell: Vector3i in edits:
		world.apply_block(cell, edits[cell])
	var saved_feet: Vector3 = data.get_value("player", "feet", level_spawn)
	feet = saved_feet if not world.overlaps_solid(SurvivalMotion.bounds(saved_feet, SurvivalMotion.CROUCHING)) else level_spawn
	reset_survival_motion()
	yaw = data.get_value("player", "yaw", 0.0)
	pitch = data.get_value("player", "pitch", 0.0)
	var saved_hotbar: Array = data.get_value("player", "hotbar", [])
	if data.get_value("world", "version", 1) >= 2:
		inventory.restore(data.get_value("player", "inventory", []), data.get_value("player", "equipment", {}))
		entities.read_state(data.get_value("world", "entities", {}))
		smelt_ticks = clampi(data.get_value("player", "smelt_ticks", 0), 0, 200)
		damage_remainder = clampf(data.get_value("player", "damage_remainder", 0.0), 0.0, 0.9999)
		update_daylight()
	if saved_hotbar.size() == hotbar.size():
		for i in hotbar.size():
			if can_place(saved_hotbar[i]):
				hotbar[i] = saved_hotbar[i]
				if data.get_value("world", "version", 1) == 1:
					inventory.slots[i] = Inventory.stack(Inventory.block_item(saved_hotbar[i]))
	slot = clampi(data.get_value("player", "slot", 0), 0, hotbar.size() - 1)
	health = clampi(data.get_value("player", "health", 20), 0, 20)
	update_camera()
	world.tick_build(feet, VIEW_RADIUS[view_distance], 9)
	screen("death" if health == 0 else "")

func save_survival() -> bool:
	if not survival or world_id.is_empty():
		return true
	var data := ConfigFile.new()
	data.set_value("world", "version", WorldSaves.VERSION)
	data.set_value("world", "name", world_name)
	data.set_value("world", "edge", world.edge)
	data.set_value("world", "seed", world.level_seed)
	data.set_value("world", "cherry_groves", cherry_groves)
	data.set_value("world", "deep_world", deep_world)
	data.set_value("world", "updated", int(Time.get_unix_time_from_system()))
	data.set_value("world", "edits", world.changed)
	data.set_value("player", "feet", feet)
	data.set_value("player", "yaw", yaw)
	data.set_value("player", "pitch", pitch)
	data.set_value("player", "health", maxi(health, 0))
	data.set_value("player", "hotbar", hotbar)
	data.set_value("player", "inventory", inventory.slots)
	data.set_value("player", "equipment", inventory.equipped)
	data.set_value("player", "smelt_ticks", smelt_ticks)
	data.set_value("player", "damage_remainder", damage_remainder)
	data.set_value("world", "entities", entities.write_state())
	data.set_value("player", "slot", slot)
	if WorldSaves.write(world_id, data) == OK:
		return true
	ui.set_notice("Could not save this world.")
	return false

func return_to_title() -> void:
	if not save_survival():
		return
	if online():
		lan.disconnect_session()
	has_level = false
	survival = false
	world_id = ""
	world.hide()
	entities.clear_level()
	clouds.hide()
	ui.chat_lines.clear()
	screen("title")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if save_survival():
			get_tree().quit()

func new_level(edge: int) -> void:
	if is_guest():
		return
	reset_level(randi_range(0, 0x7fffffff), edge)
	if online():
		lan.broadcast_level()
	screen("")

func _process(delta: float) -> void:
	if has_level:
		world.tick_build(feet, VIEW_RADIUS[view_distance])
		if survival and mode == "":
			update_camera()
			aim()
			save_clock += delta
			if save_clock >= 30.0:
				save_clock = 0.0
				save_survival()
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
	if not has_level or (is_guest() and not lan.ready_to_play) or (mode != "" and not online()):
		return
	if survival:
		tick_survival(delta)
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
		play_effect(client_audio.steps)
	aim()
	if online():
		lan.tick(delta)
	if not is_guest():
		fluid_clock += delta
		if fluid_clock >= 0.12:
			fluid_clock = 0.0
			flow_liquids()

func reset_survival_motion() -> void:
	motion.reset(feet)
	previous_feet = feet
	motion_time = 0.0
	eye_height = EYES

func tick_survival(delta: float) -> void:
	motion_time += delta
	while motion_time + 0.000001 >= SurvivalMotion.STEP and mode == "":
		motion_time = maxf(0.0, motion_time - SurvivalMotion.STEP)
		var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var direction := Vector3.ZERO
		if active:
			direction = Vector3(float(held_key(3)) - float(held_key(1)), 0.0,
				float(held_key(2)) - float(held_key(0))).rotated(Vector3.UP, yaw)
		var sneak := active and held_key(11)
		previous_feet = feet
		motion.tick(world, direction, active and held_key(4),
			active and held_key(10) and held_key(0) and not sneak, sneak)
		feet = motion.position
		grounded = motion.grounded
		eye_height = 1.27 if motion.crouching else EYES
		update_survival()
		if mode != "":
			break
		tick_survival_actions(active)
		entities.tick()
		update_daylight()
		var distance := SurvivalMotion.horizontal_squared(feet - previous_feet)
		if grounded and distance > 0.0:
			step_distance += sqrt(distance)
			if step_distance > 1.8:
				step_distance = 0.0
				play_effect(client_audio.steps)
		fluid_clock += SurvivalMotion.STEP
		if fluid_clock >= 0.12:
			fluid_clock -= 0.12
			flow_liquids()

func update_survival() -> void:
	var fall_damage := maxi(0, ceili(motion.landed_distance - 3.0001))
	if fall_damage > 0:
		hurt_player(fall_damage, feet, false)
	var player_height := SurvivalMotion.CROUCHING if motion.crouching else SurvivalMotion.STANDING
	if world.fluid_in(SurvivalMotion.bounds(feet, player_height)) == Blocks.LAVA:
		lava_clock += SurvivalMotion.STEP
		if lava_clock >= 0.5 - 0.000001:
			lava_clock = 0.0
			hurt_player(4.0, feet, false)
	else:
		lava_clock = 0.0

func respawn() -> void:
	health = 20
	lava_clock = 0.0
	damage_remainder = 0.0
	hurt_ticks = 0
	velocity = Vector3.ZERO
	feet = level_spawn
	# Player edits may have filled the original spawn cell.
	while not world.fits(feet):
		feet.y += 1.0
	reset_survival_motion()
	update_camera()
	screen("")

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
	var render_feet := feet
	if survival and mode == "":
		render_feet = previous_feet.lerp(feet, clampf(motion_time / SurvivalMotion.STEP, 0.0, 1.0))
	camera.position = render_feet + Vector3.UP * (eye_height if survival else EYES)
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
			if mode not in ["title", "death"]:
				if mode == "multiplayer" and is_guest() and not lan.ready_to_play:
					lan.disconnect_session()
				var back: String = {
					"options": options_back, "controls": "options", "generate": "pause",
					"multiplayer": multiplayer_back, "worlds": "title", "create": "worlds"
				}.get(mode, "")
				screen("pause" if mode == "" else back)
			get_viewport().set_input_as_handled()
			return
		if mode in ["palette", "inventory", "recipes"] and (key == bindings[5][1] or (survival and key == KEY_E)):
			screen("")
			return
		if mode != "":
			return
		if key == bindings[5][1] or (survival and key == KEY_E): screen("inventory" if survival else "palette")
		elif key == bindings[6][1]:
			screen("chat")
			get_viewport().set_input_as_handled()
		elif key == bindings[7][1]: toggle_option(4)
		elif key == bindings[8][1] and not survival:
			checkpoint = feet
		elif key == bindings[9][1] and not survival:
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
	if survival and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if event.button_index == MOUSE_BUTTON_LEFT:
			survival_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			survival_use()
		return
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			placing = not placing
		MOUSE_BUTTON_LEFT:
			edit_target()
		MOUSE_BUTTON_MIDDLE:
			aim()
			var id: int = selected.get("block", 0)
			if can_place(id):
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
	play_effect(client_audio.edits)
	aim()

func reset_actions() -> void:
	mining_ticks = 0.0
	mining_block = 0
	bow_ticks = 0
	bow_slot = -1
	shield_ticks = 0
	primary_consumed = false

func tick_survival_actions(active: bool) -> void:
	attack_ticks = mini(100, attack_ticks + 1)
	hurt_ticks = maxi(0, hurt_ticks - 1)
	if smelt_ticks > 0:
		smelt_ticks -= 1
		if smelt_ticks == 0:
			if inventory.add(Recipes.IRON, 1) > 0:
				entities.drop(Inventory.stack(Recipes.IRON), feet, 0)
	var primary := active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var secondary := active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not primary:
		primary_consumed = false
		mining_block = 0
		mining_ticks = 0.0
	elif not primary_consumed:
		mine_tick()
	if secondary:
		shield_ticks += 1
		if bow_slot == slot:
			bow_ticks += 1
	else:
		shield_ticks = 0
		if active and bow_slot == slot and bow_ticks >= 3:
			fire_bow()
		bow_slot = -1
		bow_ticks = 0
	if bow_slot != slot:
		bow_slot = -1

func mine_tick() -> void:
	var origin := feet + Vector3.UP * eye_height
	var hit := world.ray(origin, -camera.basis.z, 4.5)
	if hit.is_empty() or not legal_edit(hit.cell, 0):
		mining_ticks = 0.0
		mining_block = 0
		return
	var cell: Vector3i = hit.cell
	var block: int = hit.block
	if cell != mining_cell or block != mining_block:
		mining_cell = cell
		mining_block = block
		mining_ticks = 0.0
	var tool := Inventory.spec(inventory.slots[slot].get("id", ""))
	var required := 2 if block == 38 else (3 if block == 39 else (1 if block in [1, 2, 37] else 0))
	var correct_pick: bool = tool.get("tool") == "pickaxe"
	var harvest: bool = required == 0 or (correct_pick and int(tool.get("tier", 0)) >= required)
	var wood := block in [4, 5, Blocks.CHERRY_LOG, Blocks.CHERRY_PLANKS]
	var speed := float(tool.get("speed", 1.0)) if (correct_pick and required > 0) or (wood and tool.get("tool") == "axe") else 1.0
	var hardness := 3.0 if block in [37, 38, 39] else (1.5 if required > 0 else (2.0 if wood else 0.5))
	mining_ticks += speed / (hardness * (30.0 if harvest else 100.0))
	if mining_ticks < 1.0:
		return
	accept_edit(cell, 0)
	inventory.damage_slot(slot)
	if harvest:
		var drop_id := block_drop(block)
		if not drop_id.is_empty():
			entities.drop(Inventory.stack(drop_id), Vector3(cell) + Vector3(0.5, 0.2, 0.5))
	mining_ticks = 0.0
	mining_block = 0
	play_effect(client_audio.edits)

func block_drop(block: int) -> String:
	match block:
		1: return Recipes.STONE
		6, Blocks.CHERRY_LEAVES: return Recipes.FIBER
		13: return Recipes.FLINT if randf() < 0.25 else Inventory.block_item(13)
		14: return ""
		Blocks.GRASS: return Inventory.block_item(3)
		37: return Recipes.COAL
		38: return Recipes.RAW_IRON
	return Inventory.block_item(block)

func survival_attack() -> void:
	var origin := feet + Vector3.UP * eye_height
	var facing := -camera.basis.z
	var target := entities.find_target(origin, facing, 3.0)
	if target < 0:
		primary_consumed = false
		return
	primary_consumed = true
	var tool := Inventory.spec(inventory.slots[slot].get("id", ""))
	var charge := clampf(float(attack_ticks) / float(tool.get("cooldown", 5)), 0.0, 1.0)
	var critical := charge > 0.9 and motion.fall_distance > 0.0 and not motion.grounded and not held_key(10)
	var damage := float(tool.get("damage", 1)) * (0.2 + charge * charge * 0.8) * (1.5 if critical else 1.0)
	entities.hurt_mob(target, damage, (facing * Vector3(1, 0, 1)).normalized() * (0.36 if held_key(10) else 0.22) + Vector3.UP * 0.14)
	inventory.damage_slot(slot)
	attack_ticks = 0

func survival_use() -> void:
	var item := inventory.slots[slot]
	var id: String = item.get("id", "")
	if id == Recipes.P + "bow":
		bow_slot = slot
		bow_ticks = 0
		return
	if inventory.equip(slot):
		return
	var block := Inventory.block_id(id)
	var hit := world.ray(feet + Vector3.UP * eye_height, -camera.basis.z, 4.5)
	if hit.is_empty():
		return
	if not motion.crouching and hit.block in [Blocks.CRAFTING_TABLE, Blocks.FURNACE]:
		screen("recipes")
		return
	if block == 0 or hit.normal == Vector3i.ZERO:
		return
	var cell: Vector3i = hit.cell + hit.normal
	if legal_edit(cell, block):
		accept_edit(cell, block)
		inventory.consume(slot)
		play_effect(client_audio.edits)

func fire_bow() -> void:
	if inventory.slots[slot].get("id") != Recipes.P + "bow" or inventory.count_of(Recipes.ARROW) == 0:
		return
	var pull := minf(float(bow_ticks) / 20.0, 1.0)
	var power := (pull * pull + 2.0 * pull) / 3.0
	if power < 0.1:
		return
	inventory.remove(Recipes.ARROW, 1)
	inventory.damage_slot(slot)
	entities.shoot(feet + Vector3.UP * eye_height, -camera.basis.z, power * 3.0, power * 6.0, true)

func hurt_player(amount: float, source: Vector3, combat: bool) -> bool:
	if health <= 0 or (combat and hurt_ticks > 0):
		return false
	if combat:
		var toward_source := (source - feet) * Vector3(1, 0, 1)
		var facing := -camera.basis.z * Vector3(1, 0, 1)
		if shield_ticks >= 5 and bow_slot < 0 and not inventory.equipped.offhand.is_empty() and toward_source.dot(facing) > 0.0:
			inventory.damage_equipped("offhand")
			return false
		var armor := 0.0
		var toughness := 0.0
		for key in Inventory.EQUIPMENT.slice(0, 4):
			var item := Inventory.spec(inventory.equipped[key].get("id", ""))
			armor += float(item.get("armor", 0))
			toughness += float(item.get("toughness", 0))
			inventory.damage_equipped(key)
		amount *= 1.0 - clampf(armor - amount / (2.0 + toughness * 0.25), armor * 0.2, 20.0) / 25.0
		hurt_ticks = 10
	damage_remainder += amount
	var damage := floori(damage_remainder + 0.000001)
	damage_remainder -= damage
	health = maxi(0, health - damage)
	if health == 0:
		for i in inventory.slots.size():
			entities.drop(inventory.slots[i], feet, 20)
			inventory.slots[i] = {}
		for key in Inventory.EQUIPMENT:
			entities.drop(inventory.equipped[key], feet, 20)
			inventory.equipped[key] = {}
		if smelt_ticks > 0:
			entities.drop(Inventory.stack(Recipes.RAW_IRON), feet, 20)
			smelt_ticks = 0
		screen("death")
		save_survival()
	return true

func recipe_available(recipe: Dictionary) -> bool:
	var station: String = recipe.get("station", "")
	if not station.is_empty() and inventory.count_of(station) == 0 and not nearby_station(station):
		return false
	if recipe.id == Recipes.IRON and smelt_ticks > 0:
		return false
	for id: String in recipe.cost:
		if inventory.count_of(id) < recipe.cost[id]:
			return false
	return true

func nearby_station(id: String) -> bool:
	var cell := Vector3i(feet.floor())
	var block := Inventory.block_id(id)
	for x in range(-3, 4):
		for y in range(-2, 3):
			for z in range(-3, 4):
				var offset := Vector3i(x, y, z)
				if offset.length_squared() <= 12 and world.get_block(cell + offset) == block:
					return true
	return false

func craft_recipe(index: int) -> void:
	var recipe: Dictionary = Recipes.LIST[index]
	if not recipe_available(recipe):
		return
	if recipe.id == Recipes.IRON:
		for id: String in recipe.cost:
			inventory.remove(id, recipe.cost[id])
		smelt_ticks = 200
	elif not inventory.craft(recipe):
		ui.set_notice("Inventory is full.")
	ui._rebuild()

func update_daylight() -> void:
	var day := entities.daylight() if survival else 1.0
	world.solid_material.albedo_color = Color.WHITE * Color(day, day, day, 1.0)
	world.water_material.albedo_color = world.solid_material.albedo_color
	environment.background_color = NIGHT_SKY.lerp(DAY_SKY, day)
	environment.fog_light_color = environment.background_color.lightened(0.12)

func palette_blocks() -> Array:
	var choices := range(1, Blocks.PALETTE_COUNT + 1)
	if survival:
		choices.append_array([Blocks.CHERRY_LOG, Blocks.CHERRY_LEAVES, Blocks.CHERRY_PLANKS])
	return choices

func can_place(id: int) -> bool:
	if id <= 0:
		return false
	return Inventory.block_id(Inventory.block_item(id)) > 0 if survival else id >= 1 and id <= Blocks.PALETTE_COUNT

func legal_edit(cell: Vector3i, id: int) -> bool:
	if not world.inside(cell) or cell.y == 0 or (id != 0 and not can_place(id)):
		return false
	var previous := world.get_block(cell)
	if id == 0:
		return previous != 0 and previous != Blocks.BEDROCK and not Blocks.liquid(previous)
	if Blocks.solid(id):
		var box := AABB(Vector3(cell), Vector3.ONE)
		if player_bounds(feet).intersects(box) or (survival and entities.occupied(box)):
			return false
		for pose: Array in lan.poses.values():
			if player_bounds(pose[0]).intersects(box):
				return false
	return previous == 0 or Blocks.plant(previous) or Blocks.liquid(previous)

func player_bounds(at: Vector3) -> AABB:
	return SurvivalMotion.bounds(at, SurvivalMotion.CROUCHING if survival and motion.crouching else SurvivalMotion.STANDING)

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
	if survival and mode != next and (next == "" or mode == ""):
		motion_time = 0.0
		previous_feet = feet
		reset_actions()
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
			load_client_audio()
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
	if music_on and music_player.stream != null and not music_player.playing:
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
	music_player.volume_db = -18.0
	load_client_audio()

func load_client_audio() -> void:
	client_audio = ClientAudio.new()
	client_audio.load_from(blocks.source_path, Blocks.minecraft_directory())
	music_player.stop()
	music_player.stream = client_audio.music
	if music_on and music_player.stream != null:
		music_player.play()

func play_effect(clips: Array[AudioStreamOggVorbis]) -> void:
	if sound_on and not clips.is_empty():
		effect_player.stream = clips.pick_random()
		effect_player.pitch_scale = randf_range(0.9, 1.1)
		effect_player.play()

func online() -> bool:
	return lan != null and lan.peer != null

func is_guest() -> bool:
	return online() and not multiplayer.is_server()

func host_game(name_text: String) -> void:
	if not has_level or survival:
		return
	username = lan.clean_name(name_text)
	lan.host()

func join_game(host: String, name_text: String) -> void:
	username = lan.clean_name(name_text)
	address = host.strip_edges()
	lan.join(address)

func disconnect_game() -> void:
	lan.disconnect_session()
	screen("pause" if has_level else multiplayer_back)

func send_chat(line: String) -> void:
	var trimmed := line.strip_edges().left(180)
	if trimmed != "":
		lan.chat(trimmed)
	screen("")

func add_chat(line: String) -> void:
	chat_until = Time.get_ticks_msec() + 8500
	ui.add_chat(line)
