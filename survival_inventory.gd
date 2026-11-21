extends RefCounted

const Blocks = preload("res://blocks.gd")
const Recipes = preload("res://survival_recipes.gd")
const SLOT_COUNT := 36
const EQUIPMENT := ["head", "chest", "legs", "feet", "offhand"]

var slots: Array[Dictionary] = []
var equipped: Dictionary = {}

func _init() -> void:
	for i in SLOT_COUNT:
		slots.append({})
	for key in EQUIPMENT:
		equipped[key] = {}

static func block_item(block: int) -> String:
	if block == Blocks.CRAFTING_TABLE:
		return Recipes.WORKBENCH
	if block == Blocks.FURNACE:
		return Recipes.FURNACE
	return "godot_craft:block_%d" % block

static func block_id(id: String) -> int:
	if id == Recipes.WORKBENCH:
		return Blocks.CRAFTING_TABLE
	if id == Recipes.FURNACE:
		return Blocks.FURNACE
	var number := id.trim_prefix("godot_craft:block_")
	if id.begins_with("godot_craft:block_") and number.is_valid_int():
		var value := int(number)
		if value in [Blocks.CHERRY_LOG_TOP, Blocks.LOG_TOP, Blocks.GRASS_TOP, Blocks.BEDROCK, Blocks.WATER, Blocks.LAVA, Blocks.CRAFTING_TABLE, Blocks.FURNACE]:
			return 0
		return value if value > 0 and value < Blocks.NAMES.size() else 0
	return 0

static func spec(id: String) -> Dictionary:
	return Recipes.ITEMS.get(id, {})

static func label(id: String) -> String:
	var block := block_id(id)
	return Blocks.NAMES[block] if block > 0 else spec(id).get("name", id.get_slice(":", 1).replace("_", " ").capitalize())

static func stack(id: String, count := 1, wear := 0) -> Dictionary:
	return {"id": id, "count": count, "wear": wear}

static func limit(id: String) -> int:
	return 1 if spec(id).has("durability") else 64

func restore(saved_slots: Array, saved_equipped: Dictionary) -> void:
	for i in mini(slots.size(), saved_slots.size()):
		slots[i] = valid_stack(saved_slots[i])
	for slot in EQUIPMENT:
		var item := valid_stack(saved_equipped.get(slot, {}))
		equipped[slot] = item if spec(item.get("id", "")).get("slot") == slot else {}

static func valid_stack(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var id: String = value.get("id", "")
	if block_id(id) == 0 and not Recipes.ITEMS.has(id):
		return {}
	var count := clampi(value.get("count", 0), 0, limit(id))
	if count == 0:
		return {}
	return stack(id, count, clampi(value.get("wear", 0), 0, maxi(0, int(spec(id).get("durability", 1)) - 1)))

func add(id: String, count: int, wear := 0) -> int:
	for i in slots.size():
		var item := slots[i]
		if item.get("id") == id and item.wear == wear:
			var moved := mini(count, limit(id) - int(item.count))
			item.count += moved
			count -= moved
			if count == 0:
				return 0
	for i in slots.size():
		if slots[i].is_empty():
			var moved := mini(count, limit(id))
			slots[i] = stack(id, moved, wear)
			count -= moved
			if count == 0:
				break
	return count

func consume(index: int, count := 1) -> void:
	if slots[index].is_empty():
		return
	slots[index].count -= count
	if slots[index].count <= 0:
		slots[index] = {}

func count_of(id: String) -> int:
	var result := 0
	for item in slots:
		if item.get("id") == id:
			result += int(item.count)
	return result

func remove(id: String, count: int) -> void:
	for i in slots.size():
		if slots[i].get("id") == id:
			var taken := mini(count, slots[i].count)
			consume(i, taken)
			count -= taken
			if count == 0:
				return

func craft(recipe: Dictionary) -> bool:
	for id: String in recipe.cost:
		if count_of(id) < recipe.cost[id]:
			return false
	var before := slots.duplicate(true)
	for id: String in recipe.cost:
		remove(id, recipe.cost[id])
	if add(recipe.id, recipe.get("count", 1)) > 0:
		slots.assign(before)
		return false
	return true

func equip(index: int) -> bool:
	var item := slots[index]
	var key: String = spec(item.get("id", "")).get("slot", "")
	if key.is_empty():
		return false
	slots[index] = equipped[key]
	equipped[key] = item
	return true

func damage_slot(index: int) -> void:
	if wear_item(slots[index]):
		slots[index] = {}

func damage_equipped(key: String) -> void:
	if wear_item(equipped[key]):
		equipped[key] = {}

func wear_item(item: Dictionary) -> bool:
	var durability: int = spec(item.get("id", "")).get("durability", 0)
	if durability == 0:
		return false
	item.wear += 1
	return item.wear >= durability
