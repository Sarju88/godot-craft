extends RefCounted

const Recipes = preload("res://survival_recipes.gd")
const ClientCache = preload("res://client_cache.gd")
const NAMES = [
	"Air", "Stone", "Cobblestone", "Dirt", "Planks", "Log", "Leaves", "Sapling",
	"Dandelion", "Rose", "Brown mushroom", "Red mushroom", "Sand", "Gravel", "Glass",
	"Sponge", "Gold", "Red cloth", "Orange cloth", "Yellow cloth", "Lime cloth",
	"Green cloth", "Aqua cloth", "Cyan cloth", "Blue cloth", "Indigo cloth",
	"Violet cloth", "Purple cloth", "Magenta cloth", "Pink cloth", "Dark gray cloth",
	"Gray cloth", "White cloth", "Grass", "Bedrock", "Water", "Lava", "Coal ore",
	"Iron ore", "Gold ore", "Grass top", "Oak log top",
	"Cherry log", "Cherry leaves", "Cherry log top", "Cherry planks", "Crafting table", "Furnace"
]
const PALETTE_COUNT := 32
const HOTBAR := [1, 3, 4, 2, 12, 13, 5, 6, 11]
const GRASS := 33
const BEDROCK := 34
const WATER := 35
const LAVA := 36
const GRASS_TOP := 40
const LOG_TOP := 41
const CHERRY_LOG := 42
const CHERRY_LEAVES := 43
const CHERRY_LOG_TOP := 44
const CHERRY_PLANKS := 45
const CRAFTING_TABLE := 46
const FURNACE := 47
const COLS := 8
const ROWS := 6
const TILE := 16

const COLORS = [
	0x000000, 0x818181, 0x777779, 0x795337, 0xad8954, 0x69502e, 0x419323, 0x5c9f2b,
	0xffdc32, 0xe8312c, 0x9b7052, 0xdb322b, 0xdfd49b, 0x8c8381, 0xb7dbea, 0xc4bd48,
	0xffe44c, 0xbe2926, 0xdd7c22, 0xe5ca26, 0x96cf2d, 0x3ab333, 0x31bf85, 0x37bbbd,
	0x478ecf, 0x5755c8, 0x7436b9, 0xa940c0, 0xcd39a3, 0xcd527a, 0x535357, 0x9d9d9d,
	0xdfdedb, 0x765237, 0x424145, 0x416cdb, 0xec631b, 0x818181, 0x818181, 0x818181,
	0x639c38, 0xae8b54, 0x493036, 0xe5a2ba, 0xd58e91, 0xd99da0, 0x9b7953, 0x686b70
]

const LEGACY_TILES := [
	0, 1, 16, 2, 4, 20, 52, 15, 13, 12, 29, 28, 18, 19, 49, 48, 23,
	64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
	3, 17, 205, 237, 34, 33, 32, 0, 21, 20, 52, 21, 4, 4, 1
]
const MODERN_NAMES := [
	"", "stone", "cobblestone", "dirt", "oak_planks", "oak_log", "oak_leaves",
	"oak_sapling", "dandelion", "poppy", "brown_mushroom", "red_mushroom", "sand",
	"gravel", "glass", "sponge", "gold_block", "red_wool", "orange_wool", "yellow_wool",
	"lime_wool", "green_wool", "lime_wool", "cyan_wool", "light_blue_wool", "blue_wool",
	"blue_wool", "purple_wool", "magenta_wool", "pink_wool", "gray_wool", "light_gray_wool",
	"white_wool", "grass_block_side", "bedrock", "water_still", "lava_still",
	"coal_ore", "iron_ore", "gold_ore", "grass_block_top", "oak_log_top", "cherry_log", "cherry_leaves", "cherry_log_top", "cherry_planks", "crafting_table_front", "furnace_front"
]
const BLOCK_PATH := "assets/minecraft/textures/block/"
const PANORAMA_PATH := "textures/gui/title/background/panorama_%d.png"
const GUI_PATH := "assets/minecraft/textures/gui/sprites/hud/"

var atlas: ImageTexture
var icons: Array[AtlasTexture] = []
var hotbar: ImageTexture
var selector: ImageTexture
var crosshair: ImageTexture
var item_art: Dictionary = {}
var palette_slot: ImageTexture
var field_art: Array[ImageTexture] = []
var button_art: Array[ImageTexture] = []
var source_path := ""
var hearts: Array[ImageTexture] = []
var panorama: Array[ImageTexture] = []

static func plant(id: int) -> bool:
	return id >= 7 and id <= 11

static func liquid(id: int) -> bool:
	return id == WATER or id == LAVA

static func solid(id: int) -> bool:
	return id != 0 and not plant(id) and not liquid(id)

static func tile_for(id: int, face: int) -> int:
	if id == GRASS:
		return GRASS_TOP if face == 2 else (3 if face == 3 else GRASS)
	if (id == 5 or id == CHERRY_LOG) and (face == 2 or face == 3):
		return LOG_TOP if id == 5 else CHERRY_LOG_TOP
	return id

static func minecraft_directory() -> String:
	match OS.get_name():
		"macOS":
			return OS.get_environment("HOME").path_join("Library/Application Support/minecraft")
		"Windows":
			return OS.get_environment("APPDATA").path_join(".minecraft")
		_:
			return OS.get_environment("HOME").path_join(".minecraft")

static func default_candidates() -> PackedStringArray:
	var versions := minecraft_directory().path_join("versions")
	var names := Array(DirAccess.get_directories_at(versions)) if DirAccess.dir_exists_absolute(versions) else []
	names.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) > 0)
	var candidates := PackedStringArray()
	# Prefer the requested Java client, then keep the Classic fallback order.
	for release in ["26.3", "c0.0.23a_01", "c0.0.30a-2210", "1.0"]:
		candidates.append(versions.path_join(release).path_join(release + ".jar"))
	for release: String in names:
		var path := versions.path_join(release).path_join(release + ".jar")
		if not candidates.has(path):
			candidates.append(path)
	return candidates

func load_first(preferred: String) -> void:
	if not preferred.is_empty() and load_jar(preferred):
		return
	for path in default_candidates():
		if load_jar(path):
			return
	build_atlas(null, null)

func load_jar(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return false
	var legacy := read_png(archive, "terrain.png")
	var modern := archive.file_exists(BLOCK_PATH + "stone.png")
	if legacy == null and not modern:
		archive.close()
		return false
	if legacy != null and (legacy.get_width() != legacy.get_height() or legacy.get_width() < 256
			or legacy.get_width() > 2048 or legacy.get_width() % 16 != 0):
		archive.close()
		return false
	build_atlas(archive, legacy)
	load_interface(archive)
	load_item_art(archive)
	load_panorama(archive, path)
	archive.close()
	source_path = path
	return true

func read_png(archive: ZIPReader, path: String) -> Image:
	if not archive.file_exists(path):
		return null
	var bytes := archive.read_file(path)
	if bytes.size() > 8 * 1024 * 1024:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

func region(img: Image, rect: Rect2i) -> ImageTexture:
	if img == null or not Rect2i(Vector2i.ZERO, img.get_size()).encloses(rect):
		return null
	return ImageTexture.create_from_image(img.get_region(rect))

func load_panorama(archive: ZIPReader, path: String) -> void:
	panorama.clear()
	var root := minecraft_directory()
	var cherry_client := root.path_join("versions/1.20.2/1.20.2.jar")
	var cherry_index: String = ClientCache.read_json(cherry_client.get_basename() + ".json").get("assetIndex", {}).get("id", "")
	var cherry_cache := root.path_join("assets/indexes").path_join(cherry_index + ".json")
	# Prefer the installed 1.20 cherry-grove scene shown in the reference.
	if load_cached_panorama(cherry_cache):
		return
	var faces: Array[Image] = []
	for face in 6:
		faces.append(read_png(archive, "assets/minecraft/" + (PANORAMA_PATH % face)))
	if set_panorama(faces):
		return
	for index_path in ClientCache.index_candidates(path, root):
		if index_path != cherry_cache and load_cached_panorama(index_path):
			return

func load_cached_panorama(index_path: String) -> bool:
	var objects: Dictionary = ClientCache.read_json(index_path).get("objects", {})
	var faces: Array[Image] = []
	for face in 6:
		var path := ClientCache.object_path(index_path, objects, PANORAMA_PATH % face)
		if path.is_empty() or not FileAccess.file_exists(path):
			return false
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			return false
		faces.append(image)
	return set_panorama(faces)

func set_panorama(faces: Array[Image]) -> bool:
	for image in faces:
		if image == null or image.get_width() < 16 or image.get_width() != image.get_height():
			return false
	for image in faces:
		panorama.append(ImageTexture.create_from_image(image))
	return true

func load_item_art(archive: ZIPReader) -> void:
	item_art.clear()
	for id: String in Recipes.ITEMS:
		var name := id.get_slice(":", 1)
		if id == Recipes.FIBER:
			name = "string"
		var image := read_png(archive, "assets/minecraft/textures/item/" + name + ".png")
		if image != null:
			item_art[id] = ImageTexture.create_from_image(image)
		elif name == "shield":
			var shield := interface_sprite(archive, "container/slot/shield")
			if shield != null:
				item_art[id] = shield
	for station in [Recipes.WORKBENCH, Recipes.FURNACE]:
		var name := "crafting_table_front" if station == Recipes.WORKBENCH else "furnace_front"
		var image := read_png(archive, BLOCK_PATH + name + ".png")
		if image != null:
			item_art[station] = ImageTexture.create_from_image(image)

func interface_sprite(archive: ZIPReader, relative_path: String) -> ImageTexture:
	var image := read_png(archive, "assets/minecraft/textures/gui/sprites/" + relative_path + ".png")
	return ImageTexture.create_from_image(image) if image != null else null

func load_interface(archive: ZIPReader) -> void:
	palette_slot = interface_sprite(archive, "container/slot")
	field_art = [interface_sprite(archive, "widget/text_field"), interface_sprite(archive, "widget/text_field_highlighted")]
	hearts.clear()
	for sprite in ["container", "half", "full"]:
		var heart := read_png(archive, GUI_PATH + "heart/" + sprite + ".png")
		hearts.append(ImageTexture.create_from_image(heart) if heart != null else null)
	hotbar = null
	selector = null
	crosshair = null
	button_art.clear()
	var gui := read_png(archive, "gui/gui.png")
	if gui != null:
		hotbar = region(gui, Rect2i(0, 0, 182, 22))
		selector = region(gui, Rect2i(0, 22, 24, 24))
		crosshair = region(gui, Rect2i(240, 0, 16, 16))
		for y in [66, 86, 46]:
			button_art.append(region(gui, Rect2i(0, y, 200, 20)))
	else:
		var files := ["hotbar", "hotbar_selection", "crosshair"]
		var textures: Array[ImageTexture] = []
		for file: String in files:
			var img := read_png(archive, GUI_PATH + file + ".png")
			textures.append(ImageTexture.create_from_image(img) if img != null else null)
		hotbar = textures[0]
		selector = textures[1]
		crosshair = textures[2]
		var gui_prefix := "assets/minecraft/textures/gui/sprites/widget/"
		for file in ["button", "button_highlighted", "button_disabled"]:
			var img := read_png(archive, gui_prefix + file + ".png")
			button_art.append(ImageTexture.create_from_image(img) if img != null else null)

func build_atlas(archive: ZIPReader, legacy: Image) -> void:
	var image := Image.create(COLS * TILE, ROWS * TILE, false, Image.FORMAT_RGBA8)
	var grass := Color("80b74a")
	var leaves := Color("63ac37")
	if archive != null and legacy == null:
		grass = plains_tint(archive, "grass", grass)
		leaves = plains_tint(archive, "foliage", leaves)
	for id in COLORS.size():
		var tile := load_tile(archive, legacy, id, grass, leaves)
		var origin := Vector2i(id % COLS, id / COLS) * TILE
		image.blit_rect(tile, Rect2i(0, 0, TILE, TILE), origin)
	atlas = ImageTexture.create_from_image(image)
	icons.clear()
	for id in COLORS.size():
		var icon := AtlasTexture.new()
		icon.atlas = atlas
		icon.region = Rect2(id % COLS * TILE, (id / COLS) * TILE, TILE, TILE)
		icon.filter_clip = true
		icons.append(icon)

func plains_tint(archive: ZIPReader, map: String, fallback: Color) -> Color:
	var colors := read_png(archive, "assets/minecraft/textures/colormap/" + map + ".png")
	if colors == null or colors.get_size() != Vector2i(256, 256):
		return fallback
	# A single plains tint suits this milestone's terrain without biome data.
	var temperature := 0.8
	var rainfall := 0.4
	return colors.get_pixel(int((1.0 - temperature) * 255), int((1.0 - rainfall * temperature) * 255))

func load_tile(archive: ZIPReader, legacy: Image, id: int, grass: Color, leaves: Color) -> Image:
	var tile: Image
	if legacy != null and id != 0:
		var cell: int = LEGACY_TILES[id]
		var stride := legacy.get_width() / 16
		tile = legacy.get_region(Rect2i(cell % 16 * stride, cell / 16 * stride, stride, stride))
	elif archive != null and not MODERN_NAMES[id].is_empty():
		tile = read_png(archive, BLOCK_PATH + MODERN_NAMES[id] + ".png")
		if tile != null and tile.get_height() > tile.get_width():
			tile = tile.get_region(Rect2i(0, 0, tile.get_width(), tile.get_width()))
	if tile == null:
		tile = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		tile.fill(Color.hex((int(COLORS[id]) << 8) | (180 if id == WATER else 255)))
		if id == 0:
			tile.fill(Color.TRANSPARENT)
	else:
		tile.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
		if id == GRASS_TOP:
			tint(tile, grass, true)
		elif id == 6:
			tint(tile, leaves, true)
		elif id >= 17 and id <= 32 and legacy != null:
			var color := Color.hex((int(COLORS[id]) << 8) | 255)
			tint(tile, color if id != 32 else Color.WHITE)
		elif id == GRASS and archive != null and legacy == null:
			var overlay := read_png(archive, BLOCK_PATH + "grass_block_side_overlay.png")
			if overlay != null:
				overlay.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
				tint(overlay, grass, true)
				tile.blend_rect(overlay, Rect2i(0, 0, TILE, TILE), Vector2i.ZERO)
		elif id == WATER:
			tint(tile, Color(0.46, 0.63, 1.0, 0.74), true)
	return tile

func tint(tile: Image, multiplier: Color, grayscale_only := false) -> void:
	for y in TILE:
		for x in TILE:
			var pixel := tile.get_pixel(x, y)
			if not grayscale_only or pixel.s < 0.11:
				tile.set_pixel(x, y, pixel * multiplier)
