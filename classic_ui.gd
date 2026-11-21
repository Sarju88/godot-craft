extends Control

const Blocks = preload("res://blocks.gd")
const WorldSaves = preload("res://world_saves.gd")
const Inventory = preload("res://survival_inventory.gd")
const Recipes = preload("res://survival_recipes.gd")
const PanoramaShader = preload("res://menu_panorama.gdshader")
const HOTBAR_SLOTS := 9
const BUTTON_WIDTH := 300.0
const BUTTON_HEIGHT := 29.0

var game
var art: Blocks
var mode := ""
var layer: Control
var field: LineEdit
var name_field: LineEdit
var address_field: LineEdit
var message := ""
var message_until := 0
var chat_lines: Array[String] = []
var selected_world := ""
var selected_recipe := 0
var panorama_material: ShaderMaterial
var panorama_angle := -0.35

func setup(controller, textures: Blocks) -> void:
	game = controller
	art = textures
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_rebuild)

func show_mode(next: String) -> void:
	if mode == next:
		return
	mode = next
	_rebuild()

func set_notice(text: String) -> void:
	message = text
	message_until = Time.get_ticks_msec() + 4500
	queue_redraw()

func add_chat(text: String) -> void:
	chat_lines.append(text)
	if chat_lines.size() > 8:
		chat_lines.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	if panorama_material != null and not game.has_level:
		panorama_angle = wrapf(panorama_angle + delta * 0.035, 0.0, TAU)
		panorama_material.set_shader_parameter("yaw", panorama_angle)
	queue_redraw()

func _rebuild() -> void:
	if not is_instance_valid(game):
		return
	if is_instance_valid(layer):
		remove_child(layer)
		layer.queue_free()
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	field = null
	name_field = null
	address_field = null
	var x := (size.x - BUTTON_WIDTH) / 2.0
	var middle := size.y / 2.0
	panorama_material = null
	if not game.has_level and not art.panorama.is_empty():
		var background := ColorRect.new()
		background.size = size
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panorama_material = ShaderMaterial.new()
		panorama_material.shader = PanoramaShader
		var uniforms := ["front", "right_face", "back", "left_face", "top", "bottom"]
		for i in uniforms.size():
			panorama_material.set_shader_parameter(uniforms[i], art.panorama[i])
		panorama_material.set_shader_parameter("yaw", panorama_angle)
		background.material = panorama_material
		background.z_index = -2
		layer.add_child(background)
	match mode:
		"title":
			var left := center_menu_x()
			var top := roundf(size.y * 0.42)
			button("Singleplayer", Vector2(left, top), func(): game.screen("worlds"), 284)
			button("Multiplayer", Vector2(left, top + 36), game.open_multiplayer, 284)
			button("Options", Vector2(left, roundf(size.y * 0.765)), game.open_options, 138)
			button("Quit", Vector2(left + 146, roundf(size.y * 0.765)), func(): get_tree().quit(), 138)
		"worlds":
			var worlds := WorldSaves.list_worlds()
			var list := ItemList.new()
			list.theme = game.menu_theme
			list.position = Vector2(x, middle - 111)
			list.size = Vector2(BUTTON_WIDTH, 174)
			layer.add_child(list)
			list.visible = not worlds.is_empty()
			var selected := -1
			for world in worlds:
				var index := list.add_item("%s   /   %d" % [world.name, world.seed])
				list.set_item_metadata(index, world.id)
				if world.id == selected_world:
					selected = index
			if selected < 0 and not worlds.is_empty():
				selected = 0
			selected_world = "" if selected < 0 else list.get_item_metadata(selected)
			var play := button("Play Selected", Vector2(x, middle + 76),
				func(): game.load_survival(selected_world), 146, selected < 0)
			if selected >= 0:
				list.select(selected)
				list.ensure_current_is_visible()
			list.item_selected.connect(func(index: int):
				selected_world = list.get_item_metadata(index)
				play.disabled = false
			)
			list.item_activated.connect(func(index: int): game.load_survival(list.get_item_metadata(index)))
			button("Create World", Vector2(x + 154, middle + 76), game.open_creation, 146)
			button("Classic Sandbox", Vector2(x, size.y - 39), game.start_classic, 146)
			button("Back", Vector2(x + 154, size.y - 39), func(): game.screen("title"), 146)
		"create":
			var world_title := edit(Vector2(x, middle - 84), "World name", game.draft_name)
			world_title.max_length = 48
			world_title.text_changed.connect(func(value: String): game.draft_name = value)
			var seed_input := edit(Vector2(x, middle - 25), "Random when blank", game.draft_seed)
			seed_input.max_length = 80
			seed_input.text_changed.connect(func(value: String): game.draft_seed = value)
			var terrain_size := OptionButton.new()
			terrain_size.theme = game.menu_theme
			terrain_size.position = Vector2(x, middle + 34)
			terrain_size.size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
			terrain_size.add_item("Small  /  128 × 128")
			terrain_size.add_item("Large  /  256 × 256")
			terrain_size.select(game.draft_size)
			terrain_size.item_selected.connect(func(index: int): game.draft_size = index)
			layer.add_child(terrain_size)
			button("Create Survival World", Vector2(x, middle + 78), game.create_survival)
			button("Cancel", Vector2(x, size.y - 39), func(): game.screen("worlds"))
		"death":
			button("Respawn", Vector2(x, middle + 12), game.respawn)
			button("Save and Return to Title", Vector2(x, middle + 50), game.return_to_title)
		"pause":
			if game.survival:
				button("Resume", Vector2(x, middle - 69), func(): game.screen(""))
				button("Options", Vector2(x, middle - 29), game.open_options)
				button("Save and Return to Title", Vector2(x, middle + 11), game.return_to_title)
				queue_redraw()
				return
			button("Options...", Vector2(x, size.y / 2.0 - 99), game.open_options)
			button("Generate new level...", Vector2(x, size.y / 2.0 - 59), func(): game.screen("generate"), BUTTON_WIDTH, game.is_guest())
			button("Multiplayer...", Vector2(x, size.y / 2.0 - 19), game.open_multiplayer)
			button("Return to Title", Vector2(x, middle + 21), game.return_to_title)
			button("Back to game", Vector2(x, size.y - 69), func(): game.screen(""))
		"generate":
			for i in 3:
				var edge: int = [128, 256, 512][i]
				button(["Small", "Normal", "Huge"][i], Vector2(x, size.y / 2.0 - 75 + i * 40), func(): game.new_level(edge))
			button("Cancel", Vector2(x, size.y - 39), func(): game.screen("pause"))
		"options":
			for i in 5:
				button(game.option_label(i), Vector2(x, size.y / 2.0 - 140 + i * 36), func(): game.toggle_option(i))
			button("Controls...", Vector2(x, size.y / 2.0 + 57), func(): game.screen("controls"))
			button("Textures...", Vector2(x, size.y / 2.0 + 92), func(): game.choose_textures())
			button("Done", Vector2(x, size.y - 39), func(): game.screen(game.options_back))
		"controls":
			var button_width := minf(210, (size.x - 40) / 2.0)
			for i in game.bindings.size():
				var column: int = i % 2
				var row: int = i / 2
				var label: String = game.binding_label(i)
				button(label, Vector2(size.x / 2.0 + (-button_width - 10 if column == 0 else 10), size.y / 2.0 - 140 + row * 36), func(): game.change_binding(i), button_width)
			button("Done", Vector2(x, size.y - 39), func(): game.screen("options"))
		"multiplayer":
			name_field = edit(Vector2(x, size.y / 2.0 - 109), "Username", game.username)
			name_field.max_length = 20
			address_field = edit(Vector2(x, size.y / 2.0 - 66), "Host IP address", game.address)
			address_field.max_length = 64
			if game.has_level:
				button("Share world on LAN", Vector2(x, middle - 19),
					func(): game.host_game(name_field.text), BUTTON_WIDTH, game.online())
			button("Join LAN world", Vector2(x, size.y / 2.0 + 16),
				func(): game.join_game(address_field.text, name_field.text), BUTTON_WIDTH, game.online())
			button("Disconnect" if game.online() else "Back", Vector2(x, size.y - 39),
				func(): game.disconnect_game() if game.online() else game.screen(game.multiplayer_back))
		"chat":
			field = edit(Vector2(4, size.y - 51), "Enter a message")
			field.size.x = size.x - 8
			field.max_length = 180
			field.text_submitted.connect(func(line: String): game.send_chat(line))
			field.grab_focus()
		"inventory":
			build_inventory()
		"recipes":
			build_recipes()
		"palette":
			var rect := palette_rect()
			var choices: Array = game.palette_blocks()
			for slot in choices.size():
				var id: int = choices[slot]
				var b := button("", rect.position + Vector2(20 + slot % 8 * 25, 36 + slot / 8 * 25), func(): game.pick_block(id), 24)
				b.size.y = 24
				b.flat = true
				b.tooltip_text = Blocks.NAMES[id]
	queue_redraw()

func inventory_panel() -> Rect2:
	return Rect2((size - Vector2(344, 246)) * 0.5, Vector2(344, 246))

func inventory_cell(origin: Vector2, index: int) -> Vector2:
	var row := 3 if index < 9 else (index - 9) / 9
	return origin + Vector2(44 + index % 9 * 29, 72 + row * 29)

func build_inventory() -> void:
	var origin := inventory_panel().position
	for i in Inventory.SLOT_COUNT:
		var item: Dictionary = game.inventory.slots[i]
		var cell := button("", inventory_cell(origin, i), func(): choose_inventory_item(i), 27)
		cell.flat = true
		cell.size.y = 27
		cell.tooltip_text = describe_item(item)
	for i in Inventory.EQUIPMENT.size():
		var key: String = Inventory.EQUIPMENT[i]
		var cell := button("", origin + Vector2(44 + i * 29, 37), func(): unequip_item(key), 27)
		cell.flat = true
		cell.size.y = 27
		cell.tooltip_text = "%s — %s" % [key.capitalize(), describe_item(game.inventory.equipped[key])]
	button("Recipes", origin + Vector2(44, 202), func(): game.screen("recipes"), 126)
	button("Done", origin + Vector2(179, 202), func(): game.screen(""), 126)

func describe_item(item: Dictionary) -> String:
	if item.is_empty():
		return "Empty"
	var label := Inventory.label(item.id)
	var durability: int = Inventory.spec(item.id).get("durability", 0)
	if durability > 0:
		return "%s · %d/%d durability" % [label, durability - int(item.wear), durability]
	return "%s ×%d" % [label, item.count]

func choose_inventory_item(index: int) -> void:
	if not game.inventory.equip(index):
		if index < HOTBAR_SLOTS:
			game.slot = index
		else:
			var selected: Dictionary = game.inventory.slots[game.slot]
			game.inventory.slots[game.slot] = game.inventory.slots[index]
			game.inventory.slots[index] = selected
	_rebuild()

func unequip_item(key: String) -> void:
	var item: Dictionary = game.inventory.equipped[key]
	if not item.is_empty() and game.inventory.add(item.id, item.count, item.wear) == 0:
		game.inventory.equipped[key] = {}
	_rebuild()

func build_recipes() -> void:
	var origin := inventory_panel().position
	var list := ItemList.new()
	list.theme = game.menu_theme
	list.position = origin + Vector2(20, 37)
	list.size = Vector2(304, 150)
	layer.add_child(list)
	for recipe: Dictionary in Recipes.LIST:
		var label: String = recipe.get("name", Inventory.label(recipe.id))
		var count: int = recipe.get("count", 1)
		var row := list.add_item("%s ×%d" % [label, count])
		var ingredients := PackedStringArray()
		for id: String in recipe.cost:
			ingredients.append("%s ×%d" % [Inventory.label(id), recipe.cost[id]])
		var station: String = recipe.get("station", "")
		if not station.is_empty():
			ingredients.append("Requires " + Inventory.label(station))
		list.set_item_tooltip(row, ", ".join(ingredients))
		if not game.recipe_available(recipe):
			list.set_item_custom_fg_color(row, Color("9b9b9b"))
	list.select(selected_recipe)
	list.ensure_current_is_visible()
	var craft := button("Make Selected", origin + Vector2(20, 202), func(): game.craft_recipe(selected_recipe),
		147, not game.recipe_available(Recipes.LIST[selected_recipe]))
	list.item_selected.connect(func(index: int):
		selected_recipe = index
		craft.disabled = not game.recipe_available(Recipes.LIST[index])
	)
	button("Back", origin + Vector2(177, 202), func(): game.screen("inventory"), 147)

func button(caption: String, at: Vector2, action: Callable, width := BUTTON_WIDTH, disabled := false) -> Button:
	var b := Button.new()
	b.position = at
	b.size = Vector2(width, BUTTON_HEIGHT)
	b.theme = game.menu_theme
	b.text = caption
	b.disabled = disabled
	b.pressed.connect(action)
	layer.add_child(b)
	return b

func edit(at: Vector2, hint: String, value := "") -> LineEdit:
	var input := LineEdit.new()
	input.position = at
	input.size = Vector2(BUTTON_WIDTH, 28)
	input.placeholder_text = hint
	input.text = value
	input.theme = game.menu_theme
	layer.add_child(input)
	return input

func palette_rect() -> Rect2:
	var panel_size := Vector2(240, 175 if game.survival else 150)
	return Rect2((size - panel_size) / 2.0 - Vector2(0, 15), panel_size)

func text(s: String, point: Vector2, font_size := 14, centered := false) -> void:
	var font: Font = game.menu_theme.default_font
	var at := point
	if centered:
		at.x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2.0
	draw_string(font, at + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.13, 0.13, 0.13))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func icon_face(points: PackedVector2Array, tile: int, shade: float) -> void:
	var tile_at := Vector2(tile % Blocks.COLS, tile / Blocks.COLS)
	var uv := PackedVector2Array()
	for p in [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]:
		uv.append((tile_at + p * 0.97 + Vector2(0.015,0.015)) / Vector2(Blocks.COLS, Blocks.ROWS))
	draw_polygon(points, PackedColorArray([Color(shade, shade, shade)]), uv, art.atlas)

func icon(id: int, at: Vector2, d: float) -> void:
	if Blocks.plant(id):
		draw_texture_rect(art.icons[id], Rect2(at - Vector2.ONE * d, Vector2.ONE * 2 * d), false)
		return
	var top := at + Vector2(0, -d)
	var left := at + Vector2(-d, -d * 0.49)
	var mid := at
	var right := at + Vector2(d, -d * 0.49)
	var depth := Vector2(0, d)
	icon_face(PackedVector2Array([left, mid, mid + depth, left + depth]), Blocks.tile_for(id, 0), 0.68)
	icon_face(PackedVector2Array([mid, right, right + depth, mid + depth]), Blocks.tile_for(id, 4), 0.86)
	icon_face(PackedVector2Array([top, right, mid, left]), Blocks.tile_for(id, 2), 1.0)

func draw_inventory_item(item: Dictionary, at: Vector2, scale: float) -> void:
	if item.is_empty():
		return
	var id: String = item.id
	var block := Inventory.block_id(id)
	if block > 0:
		icon(block, at, scale)
	elif art.item_art.has(id):
		draw_texture_rect(art.item_art[id], Rect2(at - Vector2.ONE * scale, Vector2.ONE * scale * 2), false)
	else:
		text(Inventory.label(id).left(2), at + Vector2(0, 4), 11, true)
	if item.count > 1:
		text(str(item.count), at + Vector2(scale - 3, scale), 11, true)
	var durability: int = Inventory.spec(id).get("durability", 0)
	if durability > 0 and item.wear > 0:
		var length := 2.0 * scale * (1.0 - float(item.wear) / durability)
		draw_rect(Rect2(at + Vector2(-scale, scale), Vector2(length, 2.0)), Color("72cf64"))

func draw_inventory_cell(at: Vector2, item: Dictionary, focused := false) -> void:
	var rect := Rect2(at, Vector2(27, 27))
	if art.palette_slot != null:
		draw_texture_rect(art.palette_slot, rect, false)
	else:
		draw_rect(rect, Color("52606c"))
	if focused or rect.has_point(get_local_mouse_position()):
		draw_rect(rect, Color(1, 1, 1, 0.26))
	draw_inventory_item(item, at + Vector2(13.5, 13.5), 9.0)

func _draw() -> void:
	if not is_instance_valid(game) or not is_instance_valid(art):
		return
	var center := size / 2.0
	if not game.has_level:
		draw_front_menu(center)
		return
	var version := "0.1.0"
	if game.show_fps:
		version += "  %d fps" % Engine.get_frames_per_second()
	text(version, Vector2(4, 15))
	if art.crosshair != null:
		draw_texture_rect(art.crosshair, Rect2(center - Vector2(7, 7), Vector2(14, 14)), false)
	else:
		draw_rect(Rect2(center - Vector2(0.5, 5.5), Vector2(1, 11)), Color.WHITE)
		draw_rect(Rect2(center - Vector2(5.5, 0.5), Vector2(11, 1)), Color.WHITE)
	var at := Vector2(center.x - 136, size.y - 34)
	if art.hotbar != null:
		draw_texture_rect(art.hotbar, Rect2(at, Vector2(273, 33)), false)
	else:
		draw_rect(Rect2(at, Vector2(272, 34)), Color("1a1a1a"))
	for i in HOTBAR_SLOTS:
		var cell := at + Vector2(2 + i * 30, 2)
		if art.hotbar == null:
			draw_rect(Rect2(cell, Vector2(28, 30)), Color(0.18, 0.18, 0.18, 0.8))
			draw_rect(Rect2(cell, Vector2(28, 30)), Color("737373"), false, 1.5)
		if game.survival:
			draw_inventory_item(game.inventory.slots[i], cell + Vector2(14, 15), 10.5)
		else:
			icon(game.hotbar[i], cell + Vector2(14, 15), 10.5)
		if i == game.slot:
			if art.selector != null:
				draw_texture_rect(art.selector, Rect2(cell - Vector2(4, 4), Vector2(36, 36)), false)
			else:
				draw_rect(Rect2(cell - Vector2.ONE, Vector2(30, 32)), Color("292929"), false, 3)
				draw_rect(Rect2(cell, Vector2(28, 30)), Color("e6e8d9"), false, 2)
	if game.survival:
		var health_origin := at + Vector2(1, -12)
		for i in 10:
			var cell := health_origin + Vector2(i * 11, 0)
			var fill := clampi(game.health - i * 2, 0, 2)
			if art.hearts.size() == 3 and art.hearts[0] != null and art.hearts[fill] != null:
				var heart_rect := Rect2(cell, Vector2(11, 11))
				draw_texture_rect(art.hearts[0], heart_rect, false)
				if fill > 0:
					draw_texture_rect(art.hearts[fill], heart_rect, false)
			else:
				draw_rect(Rect2(cell, Vector2(9, 7)), Color("2a181b"))
				if fill > 0:
					draw_rect(Rect2(cell + Vector2.ONE, Vector2(fill * 3, 5)), Color("ed6468"))
	if mode == "death":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.04, 0.06, 0.77))
		text("You died", Vector2(center.x, center.y - 16), 30, true)
	if mode in ["inventory", "recipes"]:
		var panel := inventory_panel()
		draw_rect(panel, Color("18242f"))
		draw_rect(panel, Color("677985"), false)
		var heading := "Inventory" if mode == "inventory" else "Crafting and Smelting"
		text(heading, panel.position + Vector2(panel.size.x * 0.5, 24), 17, true)
		if mode == "inventory":
			for i in Inventory.SLOT_COUNT:
				draw_inventory_cell(inventory_cell(panel.position, i), game.inventory.slots[i], i == game.slot)
			for i in Inventory.EQUIPMENT.size():
				draw_inventory_cell(panel.position + Vector2(44 + i * 29, 37), game.inventory.equipped[Inventory.EQUIPMENT[i]])
			text("Select a slot to equip or move it", panel.position + Vector2(44, 194), 11)
		elif game.smelt_ticks > 0:
			text("Smelting iron · %ds" % ceili(game.smelt_ticks / 20.0), panel.position + Vector2(22, 199), 11)
	if mode == "palette":
		var rect := palette_rect()
		draw_rect(rect, Color(0.025, 0.035, 0.04, 0.65))
		text("Select block", Vector2(center.x, rect.position.y + 20), 12, true)
		var choices: Array = game.palette_blocks()
		for i in choices.size():
			var cell := rect.position + Vector2(20 + i % 8 * 25, 36 + i / 8 * 25)
			if art.palette_slot != null:
				draw_texture_rect(art.palette_slot, Rect2(cell, Vector2(24, 24)), false)
			if Rect2(cell, Vector2(24, 24)).has_point(get_local_mouse_position()):
				draw_rect(Rect2(cell, Vector2(24, 24)), Color(1, 1, 1, 0.2))
			icon(choices[i], cell + Vector2(12, 12), 7.9)
	elif mode in ["pause", "generate", "options", "controls", "multiplayer"]:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0.015, 0.025, 0.58))
		var heading: String = {
			"pause": "Game menu", "generate": "Generate new level", "options": "Options",
			"controls": "Controls", "multiplayer": "Multiplayer"
		}[mode]
		text(game.world_name if mode == "pause" and game.survival else heading, Vector2(center.x, size.y / 2.0 - 121 if mode == "pause" else 20), 15, true)
		if mode == "controls" and game.rebinding >= 0:
			text("Press a key for %s" % game.bindings[game.rebinding][0], Vector2(center.x, size.y - 59), 13, true)
		if mode == "multiplayer":
			text("LAN  •  UDP 25565", Vector2(center.x, size.y / 2.0 + 64), 12, true)
	if mode == "chat" or (mode == "" and Time.get_ticks_msec() < game.chat_until):
		for i in chat_lines.size():
			text(chat_lines[i], Vector2(5, size.y - 61 - (chat_lines.size() - i - 1) * 14), 12)
	if message_until > Time.get_ticks_msec():
		text(message, Vector2(5, size.y - 56), 12)
	if game.online() and game.table_visible and mode == "":
		draw_rect(Rect2(Vector2(center.x - 78, 25), Vector2(156, 20 + game.players.size() * 16)), Color(0, 0, 0, 0.65))
		text("Players", Vector2(center.x, 40), 12, true)
		var row := 0
		for username in game.players.values():
			text(username, Vector2(center.x, 55 + row * 16), 12, true)
			row += 1

func center_menu_x() -> float:
	return roundf((size.x - 284) * 0.5)

func draw_front_menu(center: Vector2) -> void:
	if art.panorama.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color("172a35"))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.11, 0.08 if mode == "title" else 0.72))
	if mode == "title":
		var banner := Rect2(center.x - 166, roundf(size.y * 0.12), 332, 64)
		draw_rect(banner, Color(0.075, 0.095, 0.13, 0.88))
		draw_rect(Rect2(banner.position, Vector2(banner.size.x, 2)), Color("efaaa8"))
		text("Minecraft Godot Edition", Vector2(center.x, banner.position.y + 30), 25, true)
		text("Unofficial fan project", Vector2(center.x, banner.position.y + 50), 14, true)
		text("Independent of Mojang and Microsoft", Vector2(10, size.y - 10), 12)
		return
	var heading: String = {
		"worlds": "Survival Worlds", "create": "Create World",
		"options": "Options", "controls": "Controls", "multiplayer": "LAN Multiplayer"
	}.get(mode, "")
	var title_y := center.y - 130
	if mode in ["options", "controls"]:
		title_y = 24
	text(heading, Vector2(center.x, title_y), 22, true)
	var x := center.x - BUTTON_WIDTH / 2.0
	if mode == "create":
		text("World name", Vector2(x, center.y - 91), 13)
		text("Seed", Vector2(x, center.y - 32), 13)
		text("World size", Vector2(x, center.y + 27), 13)
	if mode == "worlds" and selected_world.is_empty():
		text("Create a world to start playing.", Vector2(center.x, center.y - 21), 14, true)
	if mode == "controls" and game.rebinding >= 0:
		text("Press a key for %s" % game.bindings[game.rebinding][0], Vector2(center.x, size.y - 59), 13, true)
	if mode == "multiplayer":
		text("LAN  •  UDP 25565", Vector2(center.x, center.y + 64), 12, true)
	if message_until > Time.get_ticks_msec():
		text(message, Vector2(8, size.y - 48), 12)
