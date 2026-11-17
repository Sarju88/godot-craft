extends Control

const Blocks = preload("res://blocks.gd")
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

func _process(_delta: float) -> void:
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
	match mode:
		"pause":
			button("Options...", Vector2(x, size.y / 2.0 - 99), func(): game.screen("options"))
			button("Generate new level...", Vector2(x, size.y / 2.0 - 59), func(): game.screen("generate"), BUTTON_WIDTH, game.is_guest())
			button("Multiplayer...", Vector2(x, size.y / 2.0 - 19), func(): game.screen("multiplayer"))
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
			button("Done", Vector2(x, size.y - 39), func(): game.screen("pause"))
		"controls":
			var button_width := minf(210, (size.x - 40) / 2.0)
			for i in game.bindings.size():
				var column: int = i % 2
				var row: int = i / 2
				var label: String = game.binding_label(i)
				button(label, Vector2(size.x / 2.0 + (-button_width - 10 if column == 0 else 10), size.y / 2.0 - 140 + row * 38), func(): game.change_binding(i), button_width)
			button("Done", Vector2(x, size.y - 39), func(): game.screen("options"))
		"multiplayer":
			name_field = edit(Vector2(x, size.y / 2.0 - 109), "Username", game.username)
			name_field.max_length = 20
			address_field = edit(Vector2(x, size.y / 2.0 - 66), "Host IP address", game.address)
			address_field.max_length = 64
			button("Share world on LAN", Vector2(x, size.y / 2.0 - 19),
				func(): game.host_game(name_field.text), BUTTON_WIDTH, game.online())
			button("Join LAN world", Vector2(x, size.y / 2.0 + 16),
				func(): game.join_game(address_field.text, name_field.text), BUTTON_WIDTH, game.online())
			button("Disconnect" if game.online() else "Back", Vector2(x, size.y - 39),
				func(): game.disconnect_game() if game.online() else game.screen("pause"))
		"chat":
			field = edit(Vector2(4, size.y - 51), "Enter a message")
			field.size.x = size.x - 8
			field.max_length = 180
			field.text_submitted.connect(func(line: String): game.send_chat(line))
			field.grab_focus()
		"palette":
			var rect := palette_rect()
			for id in range(1, Blocks.PALETTE_COUNT + 1):
				var slot := id - 1
				var b := button("", rect.position + Vector2(20 + slot % 8 * 25, 36 + slot / 8 * 25), func(): game.pick_block(id), 24)
				b.size.y = 24
				b.flat = true
				b.tooltip_text = Blocks.NAMES[id]
	queue_redraw()

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
	return Rect2((size - Vector2(240, 150)) / 2.0 - Vector2(0, 15), Vector2(240, 150))

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

func _draw() -> void:
	if not is_instance_valid(game) or not is_instance_valid(art):
		return
	var center := size / 2.0
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
		icon(game.hotbar[i], cell + Vector2(14, 15), 10.5)
		if i == game.slot:
			if art.selector != null:
				draw_texture_rect(art.selector, Rect2(cell - Vector2(4, 4), Vector2(36, 36)), false)
			else:
				draw_rect(Rect2(cell - Vector2.ONE, Vector2(30, 32)), Color("292929"), false, 3)
				draw_rect(Rect2(cell, Vector2(28, 30)), Color("e6e8d9"), false, 2)
	if mode == "palette":
		var rect := palette_rect()
		draw_rect(rect, Color(0.025, 0.035, 0.04, 0.65))
		text("Select block", Vector2(center.x, rect.position.y + 20), 12, true)
		for i in Blocks.PALETTE_COUNT:
			var cell := rect.position + Vector2(20 + i % 8 * 25, 36 + i / 8 * 25)
			if Rect2(cell, Vector2(24, 24)).has_point(get_local_mouse_position()):
				draw_rect(Rect2(cell, Vector2(24, 24)), Color(1, 1, 1, 0.2))
			icon(i + 1, cell + Vector2(12, 12), 7.9)
	elif mode in ["pause", "generate", "options", "controls", "multiplayer"]:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0.015, 0.025, 0.58))
		var heading: String = {
			"pause": "Game menu", "generate": "Generate new level", "options": "Options",
			"controls": "Controls", "multiplayer": "Multiplayer"
		}[mode]
		text(heading, Vector2(center.x, size.y / 2.0 - 121 if mode == "pause" else 20), 15, true)
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
